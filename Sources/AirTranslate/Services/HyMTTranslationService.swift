import Foundation
import llama

// llama.cpp는 이 actor에서만 접근한다. 모델을 발화마다 다시 로드하지 않는다.
actor HyMTTranslationService {
    private final class Resources: @unchecked Sendable {
        let model: OpaquePointer
        let context: OpaquePointer
        init(model: OpaquePointer, context: OpaquePointer) {
            self.model = model
            self.context = context
        }
        deinit { llama_free(context); llama_model_free(model) }
    }

    private var resources: Resources?
    private var isTranslating = false
    private static let backend: Void = {
        // 모델 경로·입력 문장이 native 로그에 남지 않도록 한다.
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
    }()

    func unload() { resources = nil }

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
        // 새 자막이 이전 요청을 취소한 직후 도착해도 번역을 잃지 않도록 직렬 대기한다.
        while isTranslating { try await Task.sleep(for: .milliseconds(5)) }
        isTranslating = true
        defer { isTranslating = false }
        try Task.checkCancellation()
        if resources == nil {
            guard let url = try await HyMTModelStore.shared.installedModel() else { throw HyMTTranslationError.modelMissing }
            try Task.checkCancellation()
            _ = Self.backend
            var modelParams = llama_model_default_params()
            modelParams.n_gpu_layers = 99
            guard let model = llama_model_load_from_file(url.path, modelParams) else { throw HyMTTranslationError.loadFailed }
            var contextParams = llama_context_default_params()
            contextParams.n_ctx = 4096
            contextParams.n_batch = 512
            contextParams.n_ubatch = 256
            contextParams.n_threads = Int32(min(8, max(1, ProcessInfo.processInfo.activeProcessorCount - 2)))
            contextParams.n_threads_batch = contextParams.n_threads
            guard let context = llama_init_from_model(model, contextParams) else {
                llama_model_free(model)
                throw HyMTTranslationError.loadFailed
            }
            resources = Resources(model: model, context: context)
        }
        try Task.checkCancellation()
        guard let resources, let vocab = llama_model_get_vocab(resources.model) else { throw HyMTTranslationError.loadFailed }
        let context = resources.context
        llama_memory_clear(llama_get_memory(context), true)
        defer { llama_memory_clear(llama_get_memory(context), true) }
        var tokens: [llama_token] = []
        // 원문에 포함된 역할 토큰 문자열은 텍스트로 처리한다.
        for (part, parseSpecial) in [("<｜hy_begin▁of▁sentence｜><｜hy_User｜>", true), (Self.content(text, target: target, options: options), false), ("<｜hy_Assistant｜>", true)] {
            var buffer = [llama_token](repeating: 0, count: part.utf8.count + 32)
            let count = part.withCString { llama_tokenize(vocab, $0, Int32(part.utf8.count), &buffer, Int32(buffer.count), false, parseSpecial) }
            guard count >= 0 else { throw HyMTTranslationError.inputTooLong }
            tokens.append(contentsOf: buffer.prefix(Int(count)))
        }
        guard !tokens.isEmpty, tokens.count < 3000 else { throw HyMTTranslationError.inputTooLong }
        for offset in stride(from: 0, to: tokens.count, by: 512) {
            try Task.checkCancellation()
            var chunk = Array(tokens[offset..<min(tokens.count, offset + 512)])
            let result = chunk.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress, Int32(buffer.count)))
            }
            guard result == 0 else { throw HyMTTranslationError.inferenceFailed }
        }
        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else { throw HyMTTranslationError.inferenceFailed }
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
        var lastPublished = ContinuousClock.now
        for _ in 0..<1024 {
            try Task.checkCancellation()
            let token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) {
                let result = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !result.isEmpty else { throw HyMTTranslationError.emptyOutput }
                return result
            }
            var piece = [CChar](repeating: 0, count: 256)
            var length = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            if length < 0 {
                piece = [CChar](repeating: 0, count: Int(-length))
                length = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            }
            guard length >= 0 else { throw HyMTTranslationError.inferenceFailed }
            output.append(contentsOf: piece.prefix(Int(length)).map { UInt8(bitPattern: $0) })
            if let progress, ContinuousClock.now - lastPublished >= .milliseconds(80),
               let partial = String(data: output, encoding: .utf8) {
                lastPublished = .now
                await progress(partial.trimmingCharacters(in: .whitespacesAndNewlines))
                try Task.checkCancellation()
            }
            var next = token
            let result = withUnsafeMutablePointer(to: &next) { llama_decode(context, llama_batch_get_one($0, 1)) }
            guard result == 0 else { throw HyMTTranslationError.inferenceFailed }
        }
        throw HyMTTranslationError.outputTooLong
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
