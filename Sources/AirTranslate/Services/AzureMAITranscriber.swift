import AVFoundation
import Foundation

// REST 전사는 5초 구간을 순서대로 처리한다. 오디오는 메모리에만 보관한다.
final class AzureMAITranscriber: @unchecked Sendable {
    static let sampleRate = 16_000
    static let chunkBytes = sampleRate * 2 * 5
    static let maxPendingChunks = 6
    private let lock = NSLock()
    private let configuration: URLSessionConfiguration
    private var streaming: AzureMAIStreamingTranscriber?

    init(configuration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration
    }
    private var buffer = Data()
    private var tail: Task<Void, Never>?
    private var pending = 0
    private var active = false
    private var paused = false
    private var failed = false
    private var session: URLSession?
    private var endpoint = ""
    private var key = ""
    private var language: String?
    private var handler: (@Sendable (Result<String, AzureMAIError>) async -> Void)?

    func start(endpoint: String, key: String, language: String?,
               handler: @escaping @Sendable (Result<String, AzureMAIError>) async -> Void) throws {
        _ = try Self.endpointURL(endpoint)
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AzureMAIError.configuration }
        lock.withLock {
            self.endpoint = endpoint
            self.key = key
            self.language = language
            self.handler = handler
            let config = configuration
            config.timeoutIntervalForRequest = 45
            config.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: config, delegate: AzureNoRedirect(), delegateQueue: nil)
            active = true
        }
    }

    func startStreaming(endpoint: String, key: String, deployment: String, language: String?,
                        handler: @escaping @Sendable (Result<String, AzureMAIError>) async -> Void,
                        partialHandler: @escaping @Sendable (String) async -> Void) async throws {
        stop()
        let service = AzureMAIStreamingTranscriber()
        lock.withLock { streaming = service }
        do {
            try await service.start(endpoint: endpoint, key: key, deployment: deployment,
                                    language: language, handler: handler, partialHandler: partialHandler)
        } catch {
            service.stop()
            lock.withLock { if streaming === service { streaming = nil } }
            throw error
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        if let service = lock.withLock({ streaming }) { service.append(sampleBuffer); return }
        lock.withLock {
            guard active, !paused, !failed else { return }
            guard let pcm = Self.pcm16(sampleBuffer) else {
                failLocked(.audioFormat)
                return
            }
            buffer.append(pcm)
            while buffer.count >= Self.chunkBytes, !failed {
                let chunk = Data(buffer.prefix(Self.chunkBytes))
                buffer.removeFirst(Self.chunkBytes)
                enqueueLocked(chunk)
            }
        }
    }

    func setPaused(_ value: Bool) {
        if let service = lock.withLock({ streaming }) { service.setPaused(value); return }
        lock.withLock {
            paused = value
            if value, active, !buffer.isEmpty {
                let chunk = buffer
                buffer.removeAll(keepingCapacity: true)
                enqueueLocked(chunk)
            }
        }
    }

    func finish() async {
        if let service = lock.withLock({ streaming }) { await service.finish(); return }
        let task = lock.withLock {
            active = false
            if !buffer.isEmpty, !failed {
                let chunk = buffer
                buffer.removeAll()
                enqueueLocked(chunk)
            }
            return tail
        }
        await task?.value
    }

    func stop() {
        let service = lock.withLock { let value = streaming; streaming = nil; return value }
        service?.stop()
        lock.withLock {
            active = false
            handler = nil
            buffer.removeAll()
            tail?.cancel()
            session?.invalidateAndCancel()
            session = nil
            key = ""
        }
    }

    private func failLocked(_ error: AzureMAIError) {
        guard !failed else { return }
        failed = true
        buffer.removeAll()
        let callback = handler
        Task { await callback?(.failure(error)) }
    }

    private func enqueueLocked(_ pcm: Data) {
        guard !failed else { return }
        guard pending < Self.maxPendingChunks else { failLocked(.backlog); return }
        pending += 1
        let previous = tail
        let endpoint = endpoint, key = key, language = language
        let session = session
        tail = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            defer { self.lock.withLock { self.pending -= 1 } }
            guard !Task.isCancelled,
                  self.lock.withLock({ !self.failed && self.handler != nil }), let session else { return }
            do {
                let request = try Self.request(endpoint: endpoint, key: key, pcm: pcm, language: language)
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else { throw AzureMAIError.response }
                guard response.statusCode == 200 else { throw AzureMAIError.http(response.statusCode) }
                let text = try Self.transcript(data)
                let callback = self.lock.withLock { self.handler }
                if !Task.isCancelled, !text.isEmpty { await callback?(.success(text)) }
            } catch {
                if !Task.isCancelled {
                    let publicError = error as? AzureMAIError ?? .connection
                    let callback = self.lock.withLock {
                        guard !self.failed else { return nil as (@Sendable (Result<String, AzureMAIError>) async -> Void)? }
                        self.failed = true
                        self.buffer.removeAll()
                        return self.handler
                    }
                    // 마지막 요청의 실패 안내까지 전달한 뒤 finish()가 완료되어야 한다.
                    await callback?(.failure(publicError))
                }
            }
        }
    }

    static func endpointURL(_ endpoint: String) throws -> URL {
        guard var parts = URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", let host = parts.host,
              host.hasSuffix(".cognitiveservices.azure.com"),
              !host.dropLast(".cognitiveservices.azure.com".count).isEmpty,
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else { throw AzureMAIError.configuration }
        parts.path = "/speechtotext/transcriptions:transcribe"
        parts.queryItems = [URLQueryItem(name: "api-version", value: "2025-10-15")]
        guard let url = parts.url else { throw AzureMAIError.configuration }
        return url
    }

    static func request(endpoint: String, key: String, pcm: Data, language: String?) throws -> URLRequest {
        let boundary = "AirTranslate-\(UUID().uuidString)"
        var definition: [String: Any] = ["enhancedMode": ["enabled": true, "model": "MAI-Transcribe-2"]]
        if let language, !language.isEmpty { definition["locales"] = [language] }
        let metadata = try JSONSerialization.data(withJSONObject: definition, options: [.sortedKeys])
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"definition\"\r\nContent-Type: application/json\r\n\r\n".utf8)
        body.append(metadata)
        body.append(Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav(pcm))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: try endpointURL(endpoint))
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    static func wav(_ pcm: Data) -> Data {
        var data = Data("RIFF".utf8)
        func number<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        number(UInt32(36 + pcm.count))
        data.append(Data("WAVEfmt ".utf8))
        number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(UInt32(sampleRate)); number(UInt32(sampleRate * 2))
        number(UInt16(2)); number(UInt16(16))
        data.append(Data("data".utf8)); number(UInt32(pcm.count)); data.append(pcm)
        return data
    }

    static func transcript(_ data: Data) throws -> String {
        struct Response: Decodable { struct Phrase: Decodable { let text: String }; let combinedPhrases: [Phrase] }
        guard let result = try? JSONDecoder().decode(Response.self, from: data) else { throw AzureMAIError.response }
        return result.combinedPhrases.map(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func pcm16(_ sample: CMSampleBuffer) -> Data? {
        guard let format = CMSampleBufferGetFormatDescription(sample),
              let pointer = CMAudioFormatDescriptionGetStreamBasicDescription(format) else { return nil }
        let info = pointer.pointee
        guard info.mFormatID == kAudioFormatLinearPCM, info.mSampleRate == Double(sampleRate),
              info.mChannelsPerFrame == 1, info.mFormatFlags & kAudioFormatFlagIsBigEndian == 0 else { return nil }
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
        let count = CMBlockBufferGetDataLength(block)
        guard count > 0 else { return Data() }
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count, destination: $0.baseAddress!) }
        guard status == kCMBlockBufferNoErr else { return nil }
        if info.mFormatFlags & kAudioFormatFlagIsFloat != 0, info.mBitsPerChannel == 32 {
            var pcm = Data()
            bytes.withUnsafeBytes { raw in
                for offset in stride(from: 0, to: count - count % 4, by: 4) {
                    let value = raw.loadUnaligned(fromByteOffset: offset, as: Float.self)
                    var sample = Int16(max(-1, min(1, value.isFinite ? value : 0)) * Float(Int16.max)).littleEndian
                    withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
                }
            }
            return pcm
        }
        guard info.mBitsPerChannel == 16, info.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0 else { return nil }
        return bytes
    }
}

private final class AzureNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum AzureMAIError: LocalizedError, Sendable {
    case configuration, audioFormat, backlog, connection, response
    case http(Int)
    var errorDescription: String? {
        switch self {
        case .configuration: AzureMAICopy.configurationRequired
        case .audioFormat: AppText.localized(english: "Azure requires 16 kHz mono PCM audio.", korean: "Azure 입력은 16 kHz 모노 PCM 오디오여야 합니다.")
        case .backlog: AppText.localized(english: "Azure transcription is falling behind. Capture stopped to bound the audio queue.", korean: "Azure 전사 응답이 입력보다 느립니다. 오디오 대기열 제한에 도달해 캡처를 중지했습니다.")
        case .connection: AppText.localized(english: "Azure connection failed or timed out. Check your network and resource region.", korean: "Azure 연결 실패 또는 시간 초과입니다. 네트워크와 리소스 지역을 확인하세요.")
        case .response: AppText.localized(english: "Azure returned an invalid transcription response.", korean: "Azure 전사 응답 형식이 올바르지 않습니다.")
        case .http(let status): AppText.localized(english: "Azure request failed (HTTP \(status)). Check the resource, key, MAI availability and quota.", korean: "Azure 요청 실패(HTTP \(status)). 리소스·키·MAI 지원 지역·할당량을 확인하세요.")
        }
    }
}

enum AzureMAICopy {
    static let title = "Azure MAI (Preview)"
    static let modelLabel = AppText.localized(english: "Transcription model", korean: "전사 모델", japanese: "文字起こしモデル", chineseSimplified: "转写模型")
    static let translationFinishTimedOut = AppText.localized(english: "Capture stopped. Some final translations did not finish in time; the source transcript was saved.", korean: "캡처를 중지했습니다. 일부 마지막 번역이 제한 시간 안에 끝나지 않았으며 원문 전사는 저장했습니다.", japanese: "キャプチャを停止しました。一部の最終翻訳が時間内に完了しませんでした。原文は保存しました。", chineseSimplified: "已停止捕获。部分最终翻译未能及时完成，原文转写已保存。")
    static let deploymentLabel = AppText.localized(english: "Foundry deployment name", korean: "Foundry 배포 이름", japanese: "Foundry デプロイ名", chineseSimplified: "Foundry 部署名称")
    static let streamingEndpointLabel = AppText.localized(english: "Foundry resource endpoint", korean: "Foundry 리소스 엔드포인트", japanese: "Foundry リソースのエンドポイント", chineseSimplified: "Foundry 资源终结点")
    static let streamingEndpointRequired = AppText.localized(english: "Enter your Foundry resource’s HTTPS endpoint ending in services.ai.azure.com.", korean: "services.ai.azure.com으로 끝나는 Foundry 리소스의 HTTPS 주소를 입력하세요.", japanese: "services.ai.azure.com で終わる Foundry リソースの HTTPS アドレスを入力してください。", chineseSimplified: "请输入以 services.ai.azure.com 结尾的 Foundry 资源 HTTPS 地址。")
    static let streamingConfigurationDetail = AppText.localized(
        english: "Use the endpoint, key and deployment name from the Foundry resource hosting MAI-Transcribe-2-Streaming. The key must belong to this resource.",
        korean: "MAI-Transcribe-2-Streaming을 배포한 Foundry 리소스의 엔드포인트·키·배포 이름을 입력하세요. 키는 이 리소스의 키여야 합니다.",
        japanese: "MAI-Transcribe-2-Streaming を配置した Foundry リソースのエンドポイント・キー・デプロイ名を入力してください。キーは同じリソースのものを使用してください。",
        chineseSimplified: "请输入部署 MAI-Transcribe-2-Streaming 的 Foundry 资源终结点、密钥和部署名称。密钥必须属于该资源。"
    )
    static func detail(for model: AzureTranscriptionModel) -> String {
        model.isStreaming ? streamingDetail : detail
    }
    static let streamingDetail = AppText.localized(
        english: "Streams 16 kHz audio to Microsoft Foundry and displays partial captions. Audio is committed every 3 seconds and when paused or stopped; finalized text is translated with Apple. Microsoft usage is billed separately.",
        korean: "16 kHz 오디오를 Microsoft Foundry로 전송하고 중간 자막을 표시합니다. 3초마다, 일시정지·중지 시 오디오를 확정하며 확정된 텍스트는 Apple로 번역합니다. Microsoft 사용료는 별도입니다.",
        japanese: "16 kHz 音声を Microsoft Foundry に送信し、中間字幕を表示します。3 秒ごと、および一時停止・停止時に音声を確定し、確定テキストを Apple で翻訳します。Microsoft の利用料金は別途発生します。",
        chineseSimplified: "将 16 kHz 音频流发送到 Microsoft Foundry 并显示中间字幕。每 3 秒以及暂停或停止时提交音频，最终文本由 Apple 翻译。Microsoft 使用费用另行计费。"
    )
    static let detail = AppText.localized(
        english: "Optional MAI-Transcribe-2 cloud transcription. Audio in the selected source language is sent to Azure in 5-second segments, then translated with Apple. Results arrive after each request. Azure usage is billed separately.",
        korean: "선택형 MAI-Transcribe-2 클라우드 전사입니다. 선택한 원문 언어의 오디오를 5초 구간으로 Azure에 보내고 Apple로 번역합니다. 요청 완료 후 결과가 표시되며 Azure 사용료는 별도입니다.",
        japanese: "任意の MAI-Transcribe-2 クラウド文字起こしです。選択した原文言語の音声を 5 秒単位で Azure に送り、Apple で翻訳します。結果は各リクエスト後に表示されます。Azure の利用料金は別途発生します。",
        chineseSimplified: "可选的 MAI-Transcribe-2 云端转写。所选源语言的音频会以 5 秒分段发送到 Azure，然后使用 Apple 翻译。每次请求完成后显示结果。Azure 使用费用另行计费。"
    )
    static let configurationRequired = AppText.localized(
        english: "Set the Microsoft resource endpoint and key in API Keys settings. Streaming also requires a Foundry deployment name.",
        korean: "API 키 설정에서 Microsoft 리소스 엔드포인트와 키를 입력하세요. 스트리밍은 Foundry 배포 이름도 필요합니다.",
        japanese: "API キー設定で Microsoft リソースのエンドポイントとキーを入力してください。ストリーミングには Foundry デプロイ名も必要です。",
        chineseSimplified: "请在 API 密钥设置中输入 Microsoft 资源终结点和密钥。流式转写还需要 Foundry 部署名称。"
    )
    static let endpointRequired = AppText.localized(
        english: "Set a valid Azure Speech resource endpoint in API Keys settings.",
        korean: "API 키 설정에서 올바른 Azure Speech 리소스 엔드포인트를 입력하세요.",
        japanese: "API キー設定で有効な Azure Speech リソースのエンドポイントを入力してください。",
        chineseSimplified: "请在 API 密钥设置中输入有效的 Azure Speech 资源终结点。"
    )
    static let keyRequired = AppText.localized(
        english: "Save your Azure / Microsoft Foundry resource key in API Keys settings.",
        korean: "API 키 설정에서 Azure / Microsoft Foundry 리소스 키를 저장하세요.",
        japanese: "API キー設定で Azure / Microsoft Foundry リソースのキーを保存してください。",
        chineseSimplified: "请在 API 密钥设置中保存 Azure / Microsoft Foundry 资源密钥。"
    )
    static let configureSpeech = AppText.localized(
        english: "Configure Azure / Foundry",
        korean: "Azure / Foundry 설정",
        japanese: "Azure / Foundry を設定",
        chineseSimplified: "配置 Azure / Foundry"
    )
    static let endpointLabel = AppText.localized(
        english: "Azure Speech endpoint",
        korean: "Azure Speech 엔드포인트",
        japanese: "Azure Speech エンドポイント",
        chineseSimplified: "Azure Speech 终结点"
    )
    static let apiKeyLabel = AppText.localized(
        english: "Azure Speech API key",
        korean: "Azure Speech API 키",
        japanese: "Azure Speech API キー",
        chineseSimplified: "Azure Speech API 密钥"
    )
    static let saveKey = AppText.localized(
        english: "Save key",
        korean: "키 저장",
        japanese: "キーを保存",
        chineseSimplified: "保存密钥"
    )
    static let removeKey = AppText.localized(
        english: "Remove key",
        korean: "키 삭제",
        japanese: "キーを削除",
        chineseSimplified: "删除密钥"
    )
    static let removeKeyConfirmation = AppText.localized(
        english: "Remove the Azure key from Keychain?",
        korean: "Keychain의 Azure 키를 삭제할까요?",
        japanese: "Keychain から Azure キーを削除しますか？",
        chineseSimplified: "要从 Keychain 中删除 Azure 密钥吗？"
    )
    static let keySaved = AppText.localized(
        english: "Saved in Keychain.",
        korean: "Keychain에 저장했습니다.",
        japanese: "Keychain に保存しました。",
        chineseSimplified: "已保存到 Keychain。"
    )
    static let keyRemoved = AppText.localized(
        english: "Key removed.",
        korean: "키를 삭제했습니다.",
        japanese: "キーを削除しました。",
        chineseSimplified: "密钥已删除。"
    )
    static let keyConfiguredUnverified = AppText.localized(
        english: "Key configured. Service access has not been verified.",
        korean: "키가 설정되어 있습니다. 서비스 연결은 아직 검증하지 않았습니다.",
        japanese: "キーは設定済みです。サービス接続はまだ検証されていません。",
        chineseSimplified: "密钥已配置。尚未验证服务访问。"
    )
    static let documentation = AppText.localized(
        english: "MAI-Transcribe documentation",
        korean: "MAI-Transcribe 문서",
        japanese: "MAI-Transcribe ドキュメント",
        chineseSimplified: "MAI-Transcribe 文档"
    )
    static let finishing = AppText.localized(
        english: "Finishing the last Azure audio segments…",
        korean: "Azure 마지막 오디오 구간 처리 중…",
        japanese: "最後の Azure 音声区間を処理中…",
        chineseSimplified: "正在处理最后的 Azure 音频片段…"
    )
}
