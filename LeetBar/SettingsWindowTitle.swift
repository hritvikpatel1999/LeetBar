import AppKit
import SwiftUI

struct SettingsWindowTitle: NSViewRepresentable {
    func makeNSView(context: Context) -> TitleView {
        TitleView(frame: .zero)
    }

    func updateNSView(_ nsView: TitleView, context: Context) {
        nsView.applyTitle()
    }

    final class TitleView: NSView {
        private var titleObservation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            titleObservation = window?.observe(\.title, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.applyTitle() }
            }
            applyTitle()
        }

        func applyTitle() {
            guard let window else { return }
            if window.title != "LeetBar" { window.title = "LeetBar" }
            window.titleVisibility = .visible
            if window.toolbarStyle != .preference { window.toolbarStyle = .preference }
        }
    }
}
