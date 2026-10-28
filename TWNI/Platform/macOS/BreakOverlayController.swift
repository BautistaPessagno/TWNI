#if os(macOS)
import AppKit
import SwiftUI

/// Shows the break screen above everything, on every display and Space,
/// including over full-screen apps. Driven by `TimerManager.isShowingBreak`.
@MainActor
final class BreakOverlayController {
    private weak var timerManager: TimerManager?
    private var panels: [NSPanel] = []
    private var screenObserver: NSObjectProtocol?

    init(timerManager: TimerManager) {
        self.timerManager = timerManager
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildIfVisible() }
        }
    }

    func setVisible(_ visible: Bool) {
        if visible, panels.isEmpty {
            show()
        } else if !visible, !panels.isEmpty {
            hide()
        }
    }

    private func show() {
        guard let timerManager else { return }
        let screens = NSScreen.screens
        let primary = NSScreen.main ?? screens.first
        for screen in screens {
            let panel = BreakPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isMovable = false

            // Controls only on the main display; the others just dim.
            let view = BreakOverlayView(timerManager: timerManager, showsControls: screen == primary)
            panel.contentView = FirstClickHostingView(rootView: view)
            panel.setFrame(screen.frame, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                panel.animator().alphaValue = 1
            }
            if screen == primary { panel.makeKey() }
            panels.append(panel)
        }
    }

    private func hide() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }

    private func rebuildIfVisible() {
        guard !panels.isEmpty else { return }
        hide()
        show()
    }
}

/// Borderless panels can't become key by default; the break screen needs
/// keyboard focus so typing doesn't go to the app underneath.
private final class BreakPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Lets the first click on Snooze / Skip work without activating TWNI first.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
#endif
