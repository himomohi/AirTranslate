import Foundation
import llama

// llama.cpp는 이 actor와 전용 직렬 큐에서만 접근한다. 모델을 발화마다 다시 로드하지 않는다.
actor HyMTTranslationService {
    private final class Resources: @unchecked Sendable {
        let model: OpaquePointer
        let context: OpaquePointer
        var lastPromptTokens: [llama_token] = []

        init(model: OpaquePointer, context: OpaquePointer) {
            self.model = model
            self.context = context
        }

        deinit {
            llama_free(context)
            llama_model_free(model)
        }
    }

    private final class CancellationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }

    private final class ProgressCoalescer: @unchecked Sendable {
        private let lock = NSLock()
        private let handler: @MainActor @Sendable (String) -> Void
        private var latestText: String?
        private var isScheduled = false
        private var stopped = false

        init(_ handler: @escaping @MainActor @Sendable (String) -> Void) {
            self.handler = handler
        }

        func publish(_ text: String) {
            let shouldSchedule = lock.withLock {
                guard !stopped else { return false }
                latestText = text
                if isScheduled { return false }
                isScheduled = true
                return true
            }
            guard shouldSchedule else { return }
            Task { @MainActor [weak self] in
                self?.drainOnMainActor()
            }
        }

        func stop() {
            lock.withLock {
                stopped = true
                latestText = nil
            }
        }

        @MainActor
        private func drainOnMainActor() {
            while true {
                let next: String? = lock.withLock {
                    guard !stopped, let text = latestText else {
                        isScheduled = false
                        return nil
                    }
                    latestText = nil
                    return text
                }
                guard let next else { return }
                handler(next)
            }
        }
    }

    private static let llamaQueue = DispatchQueue(
        label: "AirTranslate.HyMTTranslationService.llama",
        qos: .userInitiated
    )

    private var resources: Resources?
    private var isTranslating = false
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []
    private var isLoading = false
    private var loadGeneration: UInt64 = 0
    private var loadWaiters: [(id: UUID, continuation: CheckedContinuation<Resources, Error>)] = []
    private static let backend: Void = {
        // 모델 경로·입력 문장이 native 로그에 남지 않도록 한다.
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
    }()

    func unload() {
        loadGeneration &+= 1
        isLoading = false
        let pendingLoads = loadWaiters
        loadWaiters.removeAll()
        for waiter in pendingLoads {
            waiter.continuation.resume(throwing: CancellationError())
        }
        let currentResources = resources
        resources = nil
        if let currentResources {
            // llama_free / llama_model_free가 직렬 큐의 작업과 겹치지 않도록 큐에서 마지막 참조를 해제한다.
            Self.llamaQueue.async {
                withExtendedLifetime(currentResources) {}
            }
        }
    }

    func prepare() async throws {
        try Task.checkCancellation()
        _ = try await ensureLoaded()
    }

    nonisolated static func prompt(_ text: String, target: LanguageOption, options: HyMTTranslationOptions = .init()) -> String {
        // 고정한 Tencent 모델의 chat_template.jinja: user 한 턴, system 없음.
        "<｜hy_begin▁of▁sentence｜><｜hy_User｜>" + content(text, target: target, options: options) + "<｜hy_Assistant｜>"
    }

    nonisolated private static func content(_ text: String, target: LanguageOption, options: HyMTTranslationOptions) -> String {
        var sections: [String] = []
        let terms = options.normalizedTerminology
        if !terms.isEmpty {
            sections.append("[Terminology]\n" + terms.joined(separator: "\n"))
            sections.append("Use these canonical names for matching technical terms. The source is a speech transcript and may contain phonetic errors. Correct a term only when supported by the terminology and context; do not invent details.")
        }
        if !options.boundedContext.isEmpty {
            sections.append("[Background Information — do not translate this section]\n" + options.boundedContext)
        }
        sections.append("Translate the source text into \(target.title). Preserve its meaning and proper names. Output only the translation without explanations.\n[Source Text]\n\(options.preparedSource(text))")
        return sections.joined(separator: "\n\n")
    }

    func translate(
        _ text: String, source: LanguageOption, target: LanguageOption,
        options: HyMTTranslationOptions = .init(),
        decoding: HyMTDecodingPolicy = .stable,
        progress: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        if source == target { return text }
        // 새 자막이 이전 요청을 취소한 직후 도착해도 번역을 잃지 않도록 FIFO 대기한다.
        try await acquireTurn()
        defer { releaseTurn() }
        try Task.checkCancellation()
        let activeResources = try await ensureLoaded()
        try Task.checkCancellation()

        let promptContent = Self.content(text, target: target, options: options)
        let cancellation = CancellationFlag()
        let coalescer = progress.map(ProgressCoalescer.init)
        defer { coalescer?.stop() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Self.llamaQueue.async {
                    do {
                        let output = try Self.runInference(
                            resources: activeResources,
                            promptContent: promptContent,
                            decoding: decoding,
                            cancellation: cancellation,
                            coalescer: coalescer
                        )
                        continuation.resume(returning: output)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func acquireTurn() async throws {
        try Task.checkCancellation()
        if !isTranslating {
            isTranslating = true
            return
        }
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.enqueueTurnWaiter(id: waiterID, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancelTurnWaiter(id: waiterID) }
        }
    }

    private func enqueueTurnWaiter(id: UUID, continuation: CheckedContinuation<Void, Error>) {
        if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
            return
        }
        if !isTranslating {
            isTranslating = true
            continuation.resume()
            return
        }
        waiters.append((id: id, continuation: continuation))
    }

    private func cancelTurnWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func releaseTurn() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.continuation.resume()
            return
        }
        isTranslating = false
    }

    private func ensureLoaded() async throws -> Resources {
        try Task.checkCancellation()
        if let resources { return resources }

        if !isLoading {
            isLoading = true
            let currentGeneration = loadGeneration
            Task {
                await self.performLoad(generation: currentGeneration)
            }
        }

        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Resources, Error>) in
                self.enqueueLoadWaiter(id: waiterID, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancelLoadWaiter(id: waiterID) }
        }
    }

    private func enqueueLoadWaiter(id: UUID, continuation: CheckedContinuation<Resources, Error>) {
        if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
            return
        }
        if let resources {
            continuation.resume(returning: resources)
            return
        }
        loadWaiters.append((id: id, continuation: continuation))
    }

    private func cancelLoadWaiter(id: UUID) {
        guard let index = loadWaiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = loadWaiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func performLoad(generation: UInt64) async {
        do {
            guard let url = try await HyMTModelStore.shared.installedModel() else {
                throw HyMTTranslationError.modelMissing
            }
            let loaded = try await Self.loadResources(from: url)
            guard loadGeneration == generation else {
                Self.llamaQueue.async { withExtendedLifetime(loaded) {} }
                return
            }
            resources = loaded
            isLoading = false
            let pending = loadWaiters
            loadWaiters.removeAll()
            for waiter in pending {
                waiter.continuation.resume(returning: loaded)
            }
        } catch {
            guard loadGeneration == generation else { return }
            isLoading = false
            let pending = loadWaiters
            loadWaiters.removeAll()
            for waiter in pending {
                waiter.continuation.resume(throwing: error)
            }
        }
    }

    private static func loadResources(from url: URL) async throws -> Resources {
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        return try await withCheckedThrowingContinuation { continuation in
            llamaQueue.async {
                _ = Self.backend
                var modelParams = llama_model_default_params()
                modelParams.n_gpu_layers = 99
                guard let model = llama_model_load_from_file(url.path, modelParams) else {
                    continuation.resume(throwing: HyMTTranslationError.loadFailed)
                    return
                }
                var contextParams = llama_context_default_params()
                contextParams.n_ctx = 4096
                contextParams.n_batch = 512
                contextParams.n_ubatch = 256
                contextParams.n_threads = Int32(min(8, max(1, processorCount - 2)))
                contextParams.n_threads_batch = contextParams.n_threads
                guard let context = llama_init_from_model(model, contextParams) else {
                    llama_model_free(model)
                    continuation.resume(throwing: HyMTTranslationError.loadFailed)
                    return
                }
                continuation.resume(returning: Resources(model: model, context: context))
            }
        }
    }

    private static func runInference(
        resources: Resources,
        promptContent: String,
        decoding: HyMTDecodingPolicy,
        cancellation: CancellationFlag,
        coalescer: ProgressCoalescer?
    ) throws -> String {
        if cancellation.isCancelled { throw CancellationError() }
        guard let vocab = llama_model_get_vocab(resources.model) else { throw HyMTTranslationError.loadFailed }
        let context = resources.context
        let memory = llama_get_memory(context)

        var tokens: [llama_token] = []
        tokens.reserveCapacity(promptContent.utf8.count / 2 + 32)
        // 원문에 포함된 역할 토큰 문자열은 텍스트로 처리한다.
        for (part, parseSpecial) in [
            ("<｜hy_begin▁of▁sentence｜><｜hy_User｜>", true),
            (promptContent, false),
            ("<｜hy_Assistant｜>", true)
        ] {
            var buffer = [llama_token](repeating: 0, count: part.utf8.count + 32)
            let count = part.withCString {
                llama_tokenize(vocab, $0, Int32(part.utf8.count), &buffer, Int32(buffer.count), false, parseSpecial)
            }
            guard count >= 0 else { throw HyMTTranslationError.inputTooLong }
            tokens.append(contentsOf: buffer.prefix(Int(count)))
        }
        guard !tokens.isEmpty, tokens.count < 3000 else { throw HyMTTranslationError.inputTooLong }

        var commonPrefix = 0
        let limit = min(resources.lastPromptTokens.count, tokens.count)
        while commonPrefix < limit, resources.lastPromptTokens[commonPrefix] == tokens[commonPrefix] {
            commonPrefix += 1
        }
        if commonPrefix == tokens.count, commonPrefix > 0 {
            commonPrefix -= 1
        }

        var prefixLen = commonPrefix
        if prefixLen > 0 {
            let seqMax = llama_memory_seq_pos_max(memory, 0)
            if seqMax < llama_pos(prefixLen - 1) || !llama_memory_seq_rm(memory, 0, llama_pos(prefixLen), -1) {
                llama_memory_clear(memory, true)
                prefixLen = 0
            }
        } else {
            llama_memory_clear(memory, true)
        }

        do {
            try decodePromptSuffix(
                tokens[prefixLen...],
                startPosition: llama_pos(prefixLen),
                context: context,
                cancellation: cancellation
            )

            guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
                throw HyMTTranslationError.inferenceFailed
            }
            defer { llama_sampler_free(sampler) }
            llama_sampler_chain_add(sampler, llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), 64, 1.05, 0, 0))
            switch decoding {
            case .stable:
                llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
            case .recommended:
                llama_sampler_chain_add(sampler, llama_sampler_init_top_k(20))
                llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.6, 1))
                llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.7))
                llama_sampler_chain_add(sampler, llama_sampler_init_dist(42))
            }

            var output = Data()
            output.reserveCapacity(1024)
            var piece = [CChar](repeating: 0, count: 256)
            var lastPublished = ContinuousClock.now
            var stepBatch = llama_batch_init(1, 0, 1)
            defer { llama_batch_free(stepBatch) }
            stepBatch.n_tokens = 1
            stepBatch.n_seq_id[0] = 1
            stepBatch.seq_id[0]![0] = 0
            stepBatch.logits[0] = 1

            for step in 0..<1024 {
                if cancellation.isCancelled { throw CancellationError() }
                let token = llama_sampler_sample(sampler, context, -1)
                if llama_vocab_is_eog(vocab, token) {
                    let result = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !result.isEmpty else { throw HyMTTranslationError.emptyOutput }
                    resources.lastPromptTokens = tokens
                    return result
                }

                var length = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
                if length < 0 {
                    piece = [CChar](repeating: 0, count: Int(-length))
                    length = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
                }
                guard length >= 0 else { throw HyMTTranslationError.inferenceFailed }
                piece.withUnsafeBytes { raw in
                    if let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                        output.append(base, count: Int(length))
                    }
                }
                if let coalescer {
                    let now = ContinuousClock.now
                    if now - lastPublished >= .milliseconds(80),
                       let partial = String(data: output, encoding: .utf8) {
                        lastPublished = now
                        coalescer.publish(partial.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }

                if cancellation.isCancelled { throw CancellationError() }
                stepBatch.token[0] = token
                stepBatch.pos[0] = llama_pos(tokens.count + step)
                let result = llama_decode(context, stepBatch)
                guard result == 0 else { throw HyMTTranslationError.inferenceFailed }
            }
            throw HyMTTranslationError.outputTooLong
        } catch {
            llama_memory_clear(memory, true)
            resources.lastPromptTokens.removeAll(keepingCapacity: true)
            throw error
        }
    }

    private static func decodePromptSuffix(
        _ suffix: ArraySlice<llama_token>,
        startPosition: llama_pos,
        context: OpaquePointer,
        cancellation: CancellationFlag
    ) throws {
        let total = suffix.count
        guard total > 0 else { return }
        let baseIndex = suffix.startIndex
        var offset = 0
        while offset < total {
            if cancellation.isCancelled { throw CancellationError() }
            let chunkCount = min(512, total - offset)
            var batch = llama_batch_init(Int32(chunkCount), 0, 1)
            defer { llama_batch_free(batch) }
            batch.n_tokens = Int32(chunkCount)
            for i in 0..<chunkCount {
                batch.token[i] = suffix[baseIndex + offset + i]
                batch.pos[i] = startPosition + llama_pos(offset + i)
                batch.n_seq_id[i] = 1
                batch.seq_id[i]![0] = 0
                batch.logits[i] = (offset + i == total - 1) ? 1 : 0
            }
            let result = llama_decode(context, batch)
            guard result == 0 else { throw HyMTTranslationError.inferenceFailed }
            offset += chunkCount
        }
    }
}

enum HyMTTranslationError: LocalizedError {
    case modelMissing, loadFailed, inputTooLong, inferenceFailed, emptyOutput, outputTooLong, busy
    var errorDescription: String? {
        switch self {
        case .modelMissing: HyMTCopy.required
        case .busy: HyMTCopy.copy("The previous translation is finishing. Try again shortly.", "이전 번역이 종료되는 중입니다. 잠시 후 다시 시도해 주세요.", "前の翻訳を終了しています。しばらくしてから再試行してください。", "上一次翻译正在结束。请稍后重试。")
        case .loadFailed: HyMTCopy.copy("Could not load Hy-MT2. Free memory or download the model again.", "Hy-MT2를 불러오지 못했습니다. 메모리를 확보하거나 모델을 다시 다운로드해 주세요.", "Hy-MT2を読み込めません。メモリを確保するか再ダウンロードしてください。", "无法加载 Hy-MT2。请释放内存或重新下载模型。")
        case .inputTooLong, .outputTooLong: HyMTCopy.copy("The text exceeds the local model's translation limit. Try a shorter passage.", "로컬 모델의 번역 길이 제한을 넘었습니다. 짧은 문장으로 다시 시도해 주세요.", "翻訳の長さ制限を超えました。短い文章でお試しください。", "文本超出本地模型的翻译长度限制。请尝试较短文本。")
        case .inferenceFailed, .emptyOutput: HyMTCopy.copy("Local Hy-MT2 translation failed. Try again.", "로컬 Hy-MT2 번역에 실패했습니다. 다시 시도해 주세요.", "ローカルHy-MT2翻訳に失敗しました。再試行してください。", "本地 Hy-MT2 翻译失败。请重试。")
        }
    }
}
