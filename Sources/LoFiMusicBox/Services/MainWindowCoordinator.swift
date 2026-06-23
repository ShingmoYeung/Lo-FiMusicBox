import AppKit
import Foundation

@MainActor
final class MainWindowCoordinator: ObservableObject {
    private weak var mainWindow: NSWindow?
    private var lastMainWindowFrame: NSRect?

    func updateMainWindow(_ window: NSWindow) {
        mainWindow = window
        if window.isVisible {
            lastMainWindowFrame = window.frame
        }
    }

    func applyMenuBarActivationPolicy() {
        applyActivationPolicy()
    }

    func hideMainWindow() {
        let window = resolvedMainWindow()
        if let window {
            lastMainWindowFrame = window.frame
            window.orderOut(nil)
        }
        applyActivationPolicy()
    }

    func showMainWindow() {
        applyActivationPolicy()
        NSApp.activate(ignoringOtherApps: true)
        guard let window = resolvedMainWindow() else { return }
        if let lastMainWindowFrame {
            window.setFrame(lastMainWindowFrame, display: false)
        }
        window.makeKeyAndOrderFront(nil)
    }

    func prepareForUserFacingWindow() {
        applyActivationPolicy()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyActivationPolicy() {
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func resolvedMainWindow() -> NSWindow? {
        if let mainWindow {
            return mainWindow
        }

        return NSApp.windows.first { window in
            !window.styleMask.contains(.titled)
                && window.isMovableByWindowBackground
        }
    }
}
