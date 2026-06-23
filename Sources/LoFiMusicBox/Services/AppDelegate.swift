import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var mainWindowCoordinator: MainWindowCoordinator?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindowCoordinator?.showMainWindow()
        return false
    }
}
