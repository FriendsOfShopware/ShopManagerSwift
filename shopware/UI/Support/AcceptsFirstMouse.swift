#if os(macOS)
import SwiftUI
import AppKit

/// Makes the first click on a freshly-presented window (e.g. a `.sheet`) hit the control under the
/// cursor instead of being swallowed as a window-activation click. On macOS, a sheet's window isn't
/// always key the moment it appears, so the first tap on a button/swatch just makes the window key
/// and does nothing else — "clicking another app and refocusing" is the classic workaround. Setting
/// `acceptsFirstMouse` on a backing view (and nudging the window to become key/main) removes it.
private struct AcceptsFirstMouseView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = FirstMouseView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// A zero-size backing view whose only job is to report that it accepts the first mouse.
    private final class FirstMouseView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var acceptsFirstResponder: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil } // never intercept clicks itself
    }
}

extension View {
    /// Ensures the first click on this view's window registers immediately (see `AcceptsFirstMouseView`).
    /// No-op on iOS/iPadOS where the problem doesn't exist.
    func acceptsFirstMouse() -> some View {
        background(AcceptsFirstMouseView().frame(width: 0, height: 0).allowsHitTesting(false))
    }
}
#else
import SwiftUI

extension View {
    /// No-op on non-macOS platforms.
    func acceptsFirstMouse() -> some View { self }
}
#endif
