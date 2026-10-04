import SwiftUI

struct FloatingCaptionModeChoiceView: View {
    let session: TranslationSessionStore
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(AppText.floatingCaptionModeChoiceTitle, systemImage: "captions.bubble")
                .font(.headline)

            Text(AppText.floatingCaptionModeChoiceDetail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(AppText.cancel) { dismissWindow() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(AppText.showCaptionsAlongsideMain) {
                    dismissWindow()
                    CaptionControlActions.showMainWindow(using: openWindow)
                    FloatingCaptionWindowController.open(session: session)
                }
                Button(AppText.useFloatingCaptionsOnly) {
                    dismissWindow()
                    CaptionControlActions.showCaptionsOnly(session: session, using: openWindow)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(session.captureControlState.phase == .finishing)
            }
        }
        .padding(24)
        .frame(width: 450)
        .onAppear {
            if session.isFloatingCaptionPresentationActive { dismissWindow() }
        }
        .onChange(of: session.isFloatingCaptionPresentationActive) { _, isActive in
            // 다른 진입점에서 이미 자막을 열었다면 남은 확인 창을 닫는다.
            if isActive { dismissWindow() }
        }
    }
}
