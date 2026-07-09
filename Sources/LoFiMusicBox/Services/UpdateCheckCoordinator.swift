import AppKit
import Foundation
import UserNotifications

/// 检查更新的 UI 协调层：手动检查、按策略静默检查、播放中延迟提示、稍后提醒 / 忽略版本。
@MainActor
final class UpdateCheckCoordinator: ObservableObject {
    @Published private(set) var isChecking: Bool = false
    @Published private(set) var lastOutcome: UpdateCheckOutcome?
    /// 后台发现有更新但因正在播放而暂缓弹窗时置位，关于页可展示提示。
    @Published private(set) var hasDeferredUpdatePrompt: Bool = false

    private let settings: AppSettingsStore
    private weak var playback: PlaybackCoordinator?
    private let service: UpdateCheckService
    private var schedulingTask: Task<Void, Never>?
    private var deferredRelease: GitHubLatestRelease?
    private var isPresentingAlert: Bool = false

    init(
        settings: AppSettingsStore,
        playback: PlaybackCoordinator,
        service: UpdateCheckService = UpdateCheckService()
    ) {
        self.settings = settings
        self.playback = playback
        self.service = service
    }

    deinit {
        schedulingTask?.cancel()
    }

    /// 根据当前 CheckPolicy 启动或停止后台检查。
    func reschedule() {
        schedulingTask?.cancel()
        schedulingTask = nil

        let policy = settings.updateCheckPolicy
        guard policy != .off else { return }

        schedulingTask = Task { [weak self] in
            guard let self else { return }

            let delay = UInt64(AppConstants.UpdateCheck.startupDelaySeconds * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            if Task.isCancelled { return }

            // 启动后 / 定期：每次冷启动在延迟后先跑一轮（仍尊重 snooze / 忽略版本）。
            await self.performCheck(triggeredByUser: false)

            guard policy == .periodic else { return }

            let intervalHours = settings.updatePeriodicIntervalHours
            let intervalNanoseconds = UInt64(intervalHours) * 60 * 60 * 1_000_000_000
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: intervalNanoseconds)
                } catch {
                    return
                }
                if Task.isCancelled { return }
                if self.shouldRunPeriodicCheckNow() {
                    await self.performCheck(triggeredByUser: false)
                }
            }
        }
    }

    /// 关于页 / 菜单的手动检查：始终给出结果反馈。
    func checkNowFromUser() async {
        await performCheck(triggeredByUser: true)
    }

    /// 播放暂停后，若有暂缓的更新提示则补发系统通知（后台路径）或弹窗。
    func presentDeferredPromptIfNeeded() {
        guard let release = deferredRelease else { return }
        guard playback?.isPlaying != true else { return }
        deferredRelease = nil
        hasDeferredUpdatePrompt = false
        Task {
            await presentUpdateAvailable(
                for: release,
                triggeredByUser: false,
                allowDeferBecausePlaying: false
            )
        }
    }

    func openReleasesPage() {
        guard let url = URL(string: AppConstants.UpdateCheck.latestReleasePageURL) else { return }
        NSWorkspace.shared.open(url)
    }

    /// 定期循环里是否该再查：距上次检查已超过设定间隔。
    private func shouldRunPeriodicCheckNow() -> Bool {
        guard settings.updateCheckPolicy == .periodic else { return false }
        guard let last = settings.updateLastCheckedAt else { return true }
        let hours = settings.updatePeriodicIntervalHours
        return Date().timeIntervalSince(last) >= TimeInterval(hours * 60 * 60)
    }

    private func performCheck(triggeredByUser: Bool) async {
        guard !isChecking else { return }

        // 后台检查尊重「稍后提醒」：到期前不打 GitHub，避免无意义请求。
        if !triggeredByUser,
           let snoozeUntil = settings.updateSnoozeUntil,
           snoozeUntil > Date() {
            return
        }

        isChecking = true
        defer { isChecking = false }

        if !triggeredByUser {
            UpdateNotificationService.shared.prepareIfNeeded()
        }

        let outcome = await service.checkLatestRelease()
        settings.updateUpdateLastCheckedAt(Date())
        lastOutcome = outcome

        switch outcome {
        case .upToDate:
            if triggeredByUser {
                presentUpToDateAlert()
            }
        case .updateAvailable(let release):
            if let ignored = settings.updateIgnoredVersion,
               ignored == release.marketingVersion {
                if triggeredByUser {
                    presentIgnoredVersionAlert(version: release.marketingVersion)
                }
                return
            }
            await presentUpdateAvailable(
                for: release,
                triggeredByUser: triggeredByUser,
                allowDeferBecausePlaying: !triggeredByUser
            )
        case .failed(let message):
            if triggeredByUser {
                presentNetworkFailureAlert(detail: message)
            }
            // 静默失败不弹窗，避免打扰收听；关于页可通过 lastOutcome 展示。
        }
    }

    private func presentUpToDateAlert() {
        runAlert { alert in
            alert.messageText = LocalizedStrings.text("update.alert.up_to_date.title")
            alert.informativeText = LocalizedStrings.text(
                "update.alert.up_to_date.message",
                AppVersion.marketingVersion
            )
            alert.alertStyle = .informational
            alert.addButton(withTitle: LocalizedStrings.text("common.ok"))
            _ = alert.runModal()
        }
    }

    private func presentIgnoredVersionAlert(version: String) {
        runAlert { alert in
            alert.messageText = LocalizedStrings.text("update.alert.ignored.title")
            alert.informativeText = LocalizedStrings.text("update.alert.ignored.message", version)
            alert.alertStyle = .informational
            alert.addButton(withTitle: LocalizedStrings.text("update.action.open_releases"))
            alert.addButton(withTitle: LocalizedStrings.text("update.action.clear_ignore"))
            alert.addButton(withTitle: LocalizedStrings.text("common.ok"))
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                openReleasesPage()
            } else if response == .alertSecondButtonReturn {
                settings.clearIgnoredUpdateVersion()
            }
        }
    }

    private func presentNetworkFailureAlert(detail: String) {
        runAlert { alert in
            alert.messageText = LocalizedStrings.text("update.alert.network.title")
            alert.informativeText = LocalizedStrings.text("update.alert.network.message", detail)
            alert.alertStyle = .warning
            alert.addButton(withTitle: LocalizedStrings.text("update.action.retry"))
            alert.addButton(withTitle: LocalizedStrings.text("update.action.open_releases"))
            alert.addButton(withTitle: LocalizedStrings.text("common.ok"))
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                Task { await self.checkNowFromUser() }
            } else if response == .alertSecondButtonReturn {
                openReleasesPage()
            }
        }
    }

    /// 手动检查：模态 Alert；后台检查：系统通知（播放中则暂缓）。
    /// 若通知权限被拒，则在非播放时回退为一次 Alert，避免用户完全收不到提醒。
    private func presentUpdateAvailable(
        for release: GitHubLatestRelease,
        triggeredByUser: Bool,
        allowDeferBecausePlaying: Bool
    ) async {
        if allowDeferBecausePlaying, playback?.isPlaying == true {
            deferredRelease = release
            hasDeferredUpdatePrompt = true
            return
        }

        if triggeredByUser {
            presentUpdateAvailableAlert(for: release)
            return
        }

        await UpdateNotificationService.shared.postUpdateAvailable(release: release)
        // 通知权限被拒时不抢焦点弹窗；关于页通过 lastOutcome=.updateAvailable 展示状态。
    }

    private func presentUpdateAvailableAlert(for release: GitHubLatestRelease) {
        let notes = truncatedReleaseNotes(release.body)
        let info: String
        if notes.isEmpty {
            info = LocalizedStrings.text(
                "update.alert.available.message",
                release.marketingVersion,
                AppVersion.marketingVersion
            )
        } else {
            info = LocalizedStrings.text(
                "update.alert.available.message_with_notes",
                release.marketingVersion,
                AppVersion.marketingVersion,
                notes
            )
        }

        runAlert { alert in
            alert.messageText = LocalizedStrings.text("update.alert.available.title")
            alert.informativeText = info
            alert.alertStyle = .informational
            alert.addButton(withTitle: LocalizedStrings.text("update.action.open_download"))
            alert.addButton(withTitle: LocalizedStrings.text("update.action.remind_later"))
            alert.addButton(withTitle: LocalizedStrings.text("update.action.ignore_version"))
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.htmlURL)
            } else if response == .alertSecondButtonReturn {
                let until = Date().addingTimeInterval(AppConstants.UpdateCheck.snoozeIntervalSeconds)
                settings.updateUpdateSnoozeUntil(until)
            } else if response == .alertThirdButtonReturn {
                settings.updateIgnoredUpdateVersion(release.marketingVersion)
            }
        }
    }

    private func truncatedReleaseNotes(_ body: String?) -> String {
        guard let body else { return "" }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let limit = 280
        if trimmed.count <= limit { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<end]) + "…"
    }

    private func runAlert(_ configure: (NSAlert) -> Void) {
        guard !isPresentingAlert else { return }
        isPresentingAlert = true
        defer { isPresentingAlert = false }
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        configure(alert)
    }
}
