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
    /// 通知权限被拒时不弹 Alert，关于页仍可通过 `lastOutcome` 看到「有可用更新」。
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
        let notes = plainReleaseNotes(release.body)
        let info = LocalizedStrings.text(
            "update.alert.available.message",
            release.marketingVersion,
            AppVersion.marketingVersion
        )

        runAlert { alert in
            alert.messageText = LocalizedStrings.text("update.alert.available.title")
            alert.informativeText = info
            alert.alertStyle = .informational
            if !notes.isEmpty {
                alert.accessoryView = makeReleaseNotesAccessoryView(notes: notes)
            }
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

    /// 把 GitHub Release Markdown body 收成适合 NSAlert 附件区的纯文本（不渲染富文本）。
    private func plainReleaseNotes(_ body: String?) -> String {
        guard let body else { return "" }
        var text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        // 代码围栏：去掉围栏标记，保留内容。
        text = text.replacingOccurrences(
            of: #"```[^\n]*\n([\s\S]*?)```"#,
            with: "$1",
            options: .regularExpression
        )
        // 图片：丢弃。
        text = text.replacingOccurrences(
            of: #"!\[[^\]]*\]\([^)]*\)"#,
            with: "",
            options: .regularExpression
        )
        // 链接：[label](url) → label (url)
        text = text.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)]+)\)"#,
            with: "$1 ($2)",
            options: .regularExpression
        )
        // 标题前缀 ## / ### …
        text = text.replacingOccurrences(
            of: #"(?m)^#{1,6}\s+"#,
            with: "",
            options: .regularExpression
        )
        // 引用 >
        text = text.replacingOccurrences(
            of: #"(?m)^>\s?"#,
            with: "",
            options: .regularExpression
        )
        // 无序/有序列表
        text = text.replacingOccurrences(
            of: #"(?m)^[\t ]*[-*+]\s+"#,
            with: "• ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?m)^[\t ]*\d+\.\s+"#,
            with: "• ",
            options: .regularExpression
        )
        // 加粗 / 斜体 / 行内代码
        text = text.replacingOccurrences(
            of: #"\*\*([^*]+)\*\*"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"__([^_]+)__"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?<!_)_([^_\n]+)_(?!_)"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"`([^`]+)`"#,
            with: "$1",
            options: .regularExpression
        )
        // 水平线
        text = text.replacingOccurrences(
            of: #"(?m)^(?:-{3,}|\*{3,}|_{3,})\s*$"#,
            with: "",
            options: .regularExpression
        )
        // 压缩多余空行
        text = text.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let limit = AppConstants.UpdateCheck.alertReleaseNotesMaxCharacterCount
        if text.count > limit {
            let end = text.index(text.startIndex, offsetBy: limit)
            return String(text[..<end]) + "…"
        }
        return text
    }

    private func makeReleaseNotesAccessoryView(notes: String) -> NSView {
        let width = AppConstants.UpdateCheck.alertReleaseNotesAccessoryWidth
        let height = AppConstants.UpdateCheck.alertReleaseNotesAccessoryHeight

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        textView.textColor = .labelColor
        textView.string = notes
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        return scrollView
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
