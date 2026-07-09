import AppKit
import Foundation

@MainActor
final class MainWindowCoordinator: ObservableObject {
    private weak var mainWindow: NSWindow?
    private var lastMainWindowFrame: NSRect?

    func updateMainWindow(_ window: NSWindow) {
        // 已有主窗时，把后来的 borderless 副本直接藏掉，避免 ⌘N 等多开残留抢引用。
        if let existing = mainWindow, existing !== window {
            window.orderOut(nil)
            return
        }

        mainWindow = window
        if window.isVisible {
            lastMainWindowFrame = window.frame
        }
    }

    func applyMenuBarActivationPolicy() {
        applyActivationPolicy()
    }

    /// 隐藏主唱机窗。优先藏调用方传入的本窗（与最小化一致），再回退到已跟踪主窗。
    func hideMainWindow(_ window: NSWindow? = nil) {
        let target = window ?? resolvedMainWindow()
        if let target {
            lastMainWindowFrame = target.frame
            target.orderOut(nil)
            if mainWindow == nil || mainWindow === target {
                mainWindow = target
            }
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
