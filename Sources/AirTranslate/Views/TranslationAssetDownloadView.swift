import AppKit
import SwiftUI
@preconcurrency import Translation

/// 설정·메뉴 막대·시작 버튼에서 공통으로 사용할, 요청 동안만 존재하는 창이다.
@MainActor
final class TranslationAssetDownloadWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let completion: TranslationAssetDownloader.Completion
    private var cancelSession: (() -> Void)?
    private var isPreparing = false
    private var dismissalRequested = false

    init(request: TranslationAssetDownloader.Request, completion: @escaping TranslationAssetDownloader.Completion) {
        self.completion = completion
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 180),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        super.init()
        window.isReleasedWhenClosed = false
        window.title = AppText.translationLanguagePack
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: TranslationAssetDownloadView(
            request: request,
            prepare: { [weak self] session in
                guard let self, !dismissalRequested else { return }
                isPreparing = true
                // 이 취소 핸들은 translationTask action이 실행되는 동안에만 유효하다.
                cancelSession = { session.cancel() }
                defer {
                    cancelSession = nil
                    isPreparing = false
                    if dismissalRequested { closeWindow() }
                }
                do {
                    try Task.checkCancellation()
                    // installedSource 생성자는 다운로드 승인 UI를 제공하지 않는다.
                    try await session.prepareTranslation()
                    try await TranslationAssetDownloader.waitUntilInstalled(
                        source: request.source, target: request.target,
                        isCancelled: { self.dismissalRequested }
                    )
                    try Task.checkCancellation()
                    cancelSession = nil
                    completion(.success(()))
                } catch {
                    cancelSession = nil
                    completion(.failure(error))
                }
            },
            cancel: { completion(.failure(CancellationError())) }
        ))
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        dismissalRequested = true
        cancelSession?()
        cancelSession = nil
        // 세션이 action을 빠져나오기 전에는 호스팅 뷰를 제거하지 않는다.
        if !isPreparing { closeWindow() }
    }

    private func closeWindow() {
        window.delegate = nil
        window.close()
        window.contentViewController = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        completion(.failure(CancellationError()))
        return false
    }
}

private struct TranslationAssetDownloadView: View {
    let request: TranslationAssetDownloader.Request
    let prepare: @MainActor (TranslationSession) async -> Void
    let cancel: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("\(request.source.localizedTitle) → \(request.target.localizedTitle)")
                .font(.headline)
            ProgressView(AppText.modelStatusDownloading)
                .controlSize(.small)
            Button(AppText.cancel, action: cancel)
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 420, height: 180)
        .translationTask(.init(
            source: Locale.Language(identifier: request.source.id),
            target: Locale.Language(identifier: request.target.id)
        )) { session in
            await prepare(session)
        }
    }
}
