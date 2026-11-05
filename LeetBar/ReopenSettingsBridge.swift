import AppKit
import SwiftUI

struct ReopenSettingsBridge: NSViewRepresentable {
    @Environment(\.openSettings) private var openSettings
    let registerReopenAction: (@escaping @MainActor () -> Void) -> Void
    var registerStartupAction: (@escaping @MainActor () -> Void) -> Void = { _ in }
    var needsSetup: @MainActor () -> Bool = { false }

    func makeNSView(context: Context) -> NSView {
        registerAction()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        registerAction()
    }

    private func registerAction() {
        registerReopenAction {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openSettings()
        }
        registerStartupAction {
            if needsSetup() {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
            }
        }
    }
}
