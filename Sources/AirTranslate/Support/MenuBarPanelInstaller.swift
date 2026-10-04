import SwiftUI

struct MenuBarPanelInstaller: NSViewRepresentable {
    @Environment(\.openWindow) private var openWindow
    let session: TranslationSessionStore
    let controller: MenuBarPanelController

    func makeNSView(context _: Context) -> NSView {
        let session = session
        let controller = controller
        let openWindow = openWindow
        Task { @MainActor in
            controller.install(session: session, openWindow: openWindow)
        }
        return NSView(frame: .zero)
    }

    func updateNSView(_: NSView, context _: Context) {}
}
