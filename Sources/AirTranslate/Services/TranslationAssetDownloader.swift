import Foundation
@preconcurrency import Translation

/// 다운로드 요청의 수명과 SwiftUI 시스템 승인 창을 연결한다.
@MainActor
final class TranslationAssetDownloader {
    struct Request: Identifiable, Equatable {
        let id = UUID()
        let source: LanguageOption
        let target: LanguageOption
    }

    typealias Completion = @MainActor (Result<Void, Error>) -> Void
    typealias Dismiss = @MainActor () -> Void
    typealias Presenter = @MainActor (Request, @escaping Completion) -> Dismiss

    private let present: Presenter
    private(set) var request: Request?
    private var continuation: CheckedContinuation<Void, Error>?
    private var dismiss: Dismiss?

    init(present: @escaping Presenter = { request, completion in
        let controller = TranslationAssetDownloadWindowController(request: request, completion: completion)
        controller.show()
        return { controller.dismiss() }
    }) {
        self.present = present
    }

    func download(source: LanguageOption, target: LanguageOption) async throws {
        try Task.checkCancellation()
        // 호출 측에서도 중복을 막지만, 이미 진행 중인 승인 창을 교체하지 않는다.
        guard request == nil else { throw CancellationError() }
        let request = Request(source: source, target: target)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.request = request
                self.continuation = continuation
                let dismiss = present(request) { [weak self] result in
                    self?.finish(requestID: request.id, result: result)
                }
                if self.request?.id == request.id {
                    self.dismiss = dismiss
                } else {
                    dismiss()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(requestID: request.id, result: .failure(CancellationError()))
            }
        }
    }

    func cancel() {
        guard let request else { return }
        finish(requestID: request.id, result: .failure(CancellationError()))
    }

    /// prepareTranslation은 이미 다운로드 중인 경우 설치 완료 전에 반환할 수 있다.
    static func waitUntilInstalled(
        source: LanguageOption,
        target: LanguageOption,
        isCancelled: @MainActor () -> Bool,
        status: @MainActor (LanguageOption, LanguageOption) async -> LanguageAvailability.Status = { source, target in
            await LanguageAvailability().status(
                from: Locale.Language(identifier: source.id), to: Locale.Language(identifier: target.id)
            )
        },
        wait: @MainActor () async throws -> Void = { try await Task.sleep(for: .milliseconds(500)) }
    ) async throws {
        while true {
            try Task.checkCancellation()
            guard !isCancelled() else { throw CancellationError() }
            let currentStatus = await status(source, target)
            try Task.checkCancellation()
            guard !isCancelled() else { throw CancellationError() }
            switch currentStatus {
            case .installed:
                return
            case .supported:
                try await wait()
            case .unsupported:
                throw TranslationServiceError.unsupportedPair(source.localizedTitle, target.localizedTitle)
            @unknown default:
                throw TranslationError.internalError
            }
        }
    }

    private func finish(requestID: UUID, result: Result<Void, Error>) {
        guard request?.id == requestID else { return }
        let continuation = continuation
        let dismiss = dismiss
        request = nil
        self.continuation = nil
        self.dismiss = nil
        dismiss?()
        continuation?.resume(with: result)
    }
}
