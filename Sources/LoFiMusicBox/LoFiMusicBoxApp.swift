import AppKit
import SwiftUI

@main
struct LoFiMusicBoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var stationRepository: StationRepository
    @StateObject private var playbackCoordinator: PlaybackCoordinator
    @StateObject private var focusTimeService: FocusTimeService
    @StateObject private var appSettings: AppSettingsStore
    @StateObject private var scheduledHealthChecker: ScheduledHealthChecker
    @StateObject private var mainWindowCoordinator: MainWindowCoordinator

    init() {
        // 必须在 SwiftUI 创建任何 NSWindow 之前安装好 borderless 窗口的 canBecomeKey
        // 覆盖：widget 主窗口会在 styleMask 中拆掉 .titled 来消除底部透明带，
        // 没这层覆盖的话它无法成为 key window，键盘快捷键就会失效。
        ensureLofiBorderlessKeyWindowOverrideInstalled()

        // 各个服务对象按依赖关系手动构造，再交给 StateObject 持有，
        // 这样 ScheduledHealthChecker 可以拿到真实的 repository / settings / playback 引用。
        let repository = StationRepository()
        let playback = PlaybackCoordinator()
        let focus = FocusTimeService()
        let settings = AppSettingsStore()
        let windowCoordinator = MainWindowCoordinator()
        let checker = ScheduledHealthChecker(
            repository: repository,
            settings: settings,
            playback: playback
        )

        _stationRepository = StateObject(wrappedValue: repository)
        _playbackCoordinator = StateObject(wrappedValue: playback)
        _focusTimeService = StateObject(wrappedValue: focus)
        _appSettings = StateObject(wrappedValue: settings)
        _scheduledHealthChecker = StateObject(wrappedValue: checker)
        _mainWindowCoordinator = StateObject(wrappedValue: windowCoordinator)
        appDelegate.mainWindowCoordinator = windowCoordinator
    }

    var body: some Scene {
        WindowGroup(AppConstants.Identity.displayName) {
            ContentView()
                .environmentObject(stationRepository)
                .environmentObject(playbackCoordinator)
                .environmentObject(focusTimeService)
                .environmentObject(appSettings)
                .environmentObject(scheduledHealthChecker)
                .environmentObject(mainWindowCoordinator)
                .task {
                    // App 启动后按当前设置启动周期性可用性检测。
                    scheduledHealthChecker.reschedule()
                }
        }
        .windowStyle(.hiddenTitleBar)
        // 不再使用 .windowResizability(.contentSize)：这个修饰符会让 SwiftUI
        // 在每次 layout 后把 NSWindow 的 contentRect 反推成 SwiftUI view 大小，
        // 进而和 WidgetWindowConfigurator 中的 setFrame / minSize 冲突，
        // 表现就是窗口 frame 在 220 / 248 之间反复抖动，底部出现透明带。
        // 真实尺寸完全交给 WidgetWindowConfigurator 用 minSize=maxSize=setFrame 锁死。
        .defaultSize(
            width: AppConstants.UserInterface.widgetWindowWidth,
            height: AppConstants.UserInterface.widgetWindowHeight
        )

        MenuBarExtra {
            AppMenuBarContent()
                .environmentObject(appSettings)
                .environmentObject(mainWindowCoordinator)
        } label: {
            Label {
                Text(AppConstants.Identity.displayName)
            } icon: {
                Image(nsImage: MenuBarTurntableIcon.image(isPlaying: playbackCoordinator.isPlaying))
                    .renderingMode(.template)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(stationRepository)
                .environmentObject(focusTimeService)
                .environmentObject(appSettings)
                .environmentObject(scheduledHealthChecker)
                .environmentObject(mainWindowCoordinator)
        }
    }
}

private enum MenuBarTurntableIcon {
    private static let imageSize = NSSize(width: 18, height: 18)

    static func image(isPlaying: Bool) -> NSImage {
        let image = NSImage(size: imageSize)
        image.lockFocus()

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let baseRect = NSRect(x: 1.25, y: 1.25, width: 15.5, height: 15.5)
        let basePath = NSBezierPath(roundedRect: baseRect, xRadius: 3.2, yRadius: 3.2)
        basePath.lineWidth = 1.25
        basePath.stroke()

        let recordRect = NSRect(x: 2.2, y: 5.2, width: 7.4, height: 7.4)
        let recordPath = NSBezierPath(ovalIn: recordRect)
        recordPath.lineWidth = isPlaying ? 1.45 : 1.2
        recordPath.stroke()

        NSBezierPath(ovalIn: NSRect(x: 5.0, y: 8.0, width: 1.8, height: 1.8)).fill()
        NSBezierPath(ovalIn: NSRect(x: 12.8, y: 12.2, width: 2.2, height: 2.2)).fill()

        let tonearmPath = NSBezierPath()
        tonearmPath.move(to: NSPoint(x: 13.1, y: 13.8))
        tonearmPath.line(to: isPlaying ? NSPoint(x: 9.1, y: 8.3) : NSPoint(x: 13.0, y: 6.2))
        tonearmPath.lineWidth = 1.25
        tonearmPath.lineCapStyle = .round
        tonearmPath.stroke()

        image.unlockFocus()
        image.isTemplate = true
        image.size = imageSize
        return image
    }
}

private struct AppMenuBarContent: View {
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var mainWindowCoordinator: MainWindowCoordinator

    var body: some View {
        let _ = appSettings.appLanguage

        Button {
            mainWindowCoordinator.prepareForUserFacingWindow()
            NSApplication.shared.orderFrontStandardAboutPanel(nil)
        } label: {
            menuItemLabel(LocalizedStrings.text("app.menu.about"))
        }

        Button {
            mainWindowCoordinator.prepareForUserFacingWindow()
            openSettings()
        } label: {
            menuItemLabel(LocalizedStrings.text("app.menu.preferences"))
        }

        Divider()

        Button {
            mainWindowCoordinator.showMainWindow()
        } label: {
            menuItemLabel(LocalizedStrings.text("app.menu.show_main_window"))
        }

        Divider()

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            menuItemLabel(LocalizedStrings.text("app.menu.quit"))
        }
    }

    private func menuItemLabel(_ title: String) -> some View {
        Text(title)
            .frame(minWidth: 132, alignment: .leading)
    }
}

@MainActor
func showNoUpdateAvailableAlert() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = LocalizedStrings.text("app.alert.up_to_date.title")
    alert.informativeText = LocalizedStrings.text("app.alert.up_to_date.message")
    alert.alertStyle = .informational
    alert.addButton(withTitle: LocalizedStrings.text("common.ok"))
    alert.runModal()
}
