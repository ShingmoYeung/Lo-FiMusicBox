import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// macOS 偏好设置窗口（Cmd+, 触发）。当前包含五个分页：
/// - 通用：应用语言、播放体验、频道来源依赖说明；
/// - 频道管理：增删改自定义频道、编辑或隐藏内置频道；
/// - 数据管理：查看并打开用户数据目录；
/// - 可用性检测：自动检测、手动检测、结果分布；
/// - 关于：应用身份与全部软件更新能力（检查策略、手动检查、状态）。
struct SettingsView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label(LocalizedStrings.text("settings.tab.general"), systemImage: "gearshape")
                }

            StationManagementView()
                .tabItem {
                    Label(LocalizedStrings.text("settings.tab.station_management"), systemImage: "list.star")
                }

            DataManagementView()
                .tabItem {
                    Label(LocalizedStrings.text("settings.tab.data_management"), systemImage: "externaldrive")
                }

            HealthCheckSettingsView()
                .tabItem {
                    Label(LocalizedStrings.text("settings.tab.availability"), systemImage: "stethoscope")
                }

            AboutSettingsView()
                .tabItem {
                    Label(LocalizedStrings.text("settings.tab.about"), systemImage: "info.circle")
                }
        }
        .frame(
            width: AppConstants.UserInterface.stationManagerMinimumWidth,
            height: AppConstants.UserInterface.stationManagerMinimumHeight
        )
        .id(appSettings.appLanguage.id)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    var body: some View {
        Form {
            Section {
                Picker(
                    LocalizedStrings.text("language.app_language"),
                    selection: Binding(
                        get: { appSettings.appLanguage },
                        set: { appSettings.updateAppLanguage($0) }
                    )
                ) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .help(LocalizedStrings.text("language.help"))
            } header: {
                Text(LocalizedStrings.text("language.section"))
            } footer: {
                Text(LocalizedStrings.text("language.help"))
            }

            Section {
                Picker(
                    LocalizedStrings.text("general.playback_aura.picker"),
                    selection: Binding(
                        get: { appSettings.playbackAuraIntensity },
                        set: { appSettings.updatePlaybackAuraIntensity($0) }
                    )
                ) {
                    ForEach(PlaybackAuraIntensity.allCases) { intensity in
                        Text(intensity.displayName).tag(intensity)
                    }
                }
                .help(LocalizedStrings.text("general.playback_aura.help"))
            } header: {
                Text(LocalizedStrings.text("general.section.playback"))
            } footer: {
                Text(LocalizedStrings.text("general.playback_aura.footer"))
            }

            Section {
                dependencyMatrix
            } header: {
                Text(LocalizedStrings.text("general.section.dependencies"))
            } footer: {
                Text(LocalizedStrings.text("general.dependencies.footer"))
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }

    /// 频道来源 × 外部依赖对照表：让用户一眼看清"每种源需要什么组件、是必需还是可选"。
    /// v1.0.0 起 App 只承诺三类系统原生可播的音源，均无需外部依赖。
    private var dependencyMatrix: some View {
        VStack(alignment: .leading, spacing: 10) {
            dependencyRow(
                sourceKey: "general.dependencies.source.builtin_hls",
                requirementKey: "general.dependencies.requirement.none"
            )
            dependencyRow(
                sourceKey: "general.dependencies.source.mp3",
                requirementKey: "general.dependencies.requirement.none"
            )
            dependencyRow(
                sourceKey: "general.dependencies.source.bilibili",
                requirementKey: "general.dependencies.requirement.none"
            )
        }
    }

    private func dependencyRow(sourceKey: String, requirementKey: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
                .imageScale(.small)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStrings.text(sourceKey))
                    .font(.subheadline.weight(.medium))
                Text(LocalizedStrings.text(requirementKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// 关于页同时承载应用身份与全部软件更新能力（策略、手动检查、状态），
/// 避免「通用改策略 / 关于点检查」拆成两处。
private struct AboutSettingsView: View {
    @EnvironmentObject private var updateCheckCoordinator: UpdateCheckCoordinator
    @EnvironmentObject private var appSettings: AppSettingsStore
    @State private var isShowingIntervalHelp = false

    /// 两个操作按钮固定同宽，避免文案长短导致一宽一窄。
    private let updateActionButtonWidth: CGFloat = 140

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppConstants.Identity.displayName)
                        .font(.title2.bold())
                    Text(LocalizedStrings.text("settings.about.version", AppVersion.marketingVersion))
                        .foregroundStyle(.secondary)
                    Text(LocalizedStrings.text("settings.about.description"))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker(
                    LocalizedStrings.text("update.policy.picker"),
                    selection: Binding(
                        get: { appSettings.updateCheckPolicy },
                        set: { newPolicy in
                            appSettings.updateUpdateCheckPolicy(newPolicy)
                            updateCheckCoordinator.reschedule()
                        }
                    )
                ) {
                    ForEach(UpdateCheckPolicy.allCases) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }

                if appSettings.updateCheckPolicy == .periodic {
                    Picker(selection: Binding(
                        get: { appSettings.updatePeriodicIntervalHours },
                        set: { hours in
                            appSettings.updateUpdatePeriodicIntervalHours(hours)
                            updateCheckCoordinator.reschedule()
                        }
                    )) {
                        ForEach(AppConstants.Settings.updatePeriodicIntervalHourChoices, id: \.self) { hours in
                            Text(updateIntervalLabel(hours)).tag(hours)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(LocalizedStrings.text("update.interval.picker"))
                            // 说明只走点击 popover；悬停仅短提示，避免系统 tooltip 截断长文案。
                            Button {
                                isShowingIntervalHelp.toggle()
                            } label: {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                                    .imageScale(.medium)
                            }
                            .buttonStyle(.plain)
                            .help(LocalizedStrings.text("update.interval.help_hint"))
                            .popover(isPresented: $isShowingIntervalHelp, arrowEdge: .bottom) {
                                Text(LocalizedStrings.text("update.interval.help"))
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(width: 280, alignment: .leading)
                                    .padding(12)
                            }
                            .accessibilityLabel(LocalizedStrings.text("update.interval.help_accessibility"))
                        }
                    }
                }

                if updateCheckCoordinator.hasDeferredUpdatePrompt {
                    Text(LocalizedStrings.text("update.status.deferred_while_playing"))
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                if let statusText = statusSummaryText {
                    Text(statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        Task {
                            await updateCheckCoordinator.checkNowFromUser()
                        }
                    } label: {
                        Group {
                            if updateCheckCoordinator.isChecking {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(LocalizedStrings.text("update.action.checking"))
                                }
                            } else {
                                Label(
                                    LocalizedStrings.text("app.menu.check_updates"),
                                    systemImage: "arrow.triangle.2.circlepath"
                                )
                            }
                        }
                        .frame(width: updateActionButtonWidth)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(updateCheckCoordinator.isChecking)

                    Button {
                        updateCheckCoordinator.openReleasesPage()
                    } label: {
                        Label(
                            LocalizedStrings.text("update.action.open_releases"),
                            systemImage: "safari"
                        )
                        .frame(width: updateActionButtonWidth)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Spacer(minLength: 0)
                }

                if let ignored = appSettings.updateIgnoredVersion {
                    HStack {
                        Text(LocalizedStrings.text("update.status.ignored", ignored))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(LocalizedStrings.text("update.action.clear_ignore")) {
                            appSettings.clearIgnoredUpdateVersion()
                        }
                        .font(.caption)
                    }
                }
            } header: {
                Text(LocalizedStrings.text("update.section.title"))
            } footer: {
                Text(LocalizedStrings.text("update.section.footer"))
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }

    private func updateIntervalLabel(_ hours: Int) -> String {
        switch hours {
        case 24:
            return LocalizedStrings.text("update.interval.daily")
        case 168:
            return LocalizedStrings.text("update.interval.weekly")
        case 720:
            return LocalizedStrings.text("update.interval.monthly")
        default:
            return LocalizedStrings.text("update.interval.weekly")
        }
    }

    private var statusSummaryText: String? {
        if case .updateAvailable(let release)? = updateCheckCoordinator.lastOutcome {
            return LocalizedStrings.text(
                "update.status.available",
                release.marketingVersion
            )
        }
        if let last = appSettings.updateLastCheckedAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let stamped = formatter.string(from: last)
            if case .failed(let message)? = updateCheckCoordinator.lastOutcome {
                return LocalizedStrings.text("update.status.last_failed", stamped, message)
            }
            return LocalizedStrings.text("update.status.last_checked", stamped)
        }
        if case .failed(let message)? = updateCheckCoordinator.lastOutcome {
            return LocalizedStrings.text("update.status.failed", message)
        }
        return nil
    }
}

private struct DataManagementView: View {
    @EnvironmentObject private var repository: StationRepository
    @State private var operationMessage: String?
    @State private var isShowingOperationMessage = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedStrings.text("data.storage_location"))
                        .font(.headline)
                    Text(repository.dataDirectoryURL.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                }

                HStack {
                    Button {
                        try? FileManager.default.createDirectory(
                            at: repository.dataDirectoryURL,
                            withIntermediateDirectories: true
                        )
                        NSWorkspace.shared.activateFileViewerSelecting([repository.dataDirectoryURL])
                    } label: {
                        Label(LocalizedStrings.text("data.open_in_finder"), systemImage: "folder")
                    }

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(repository.dataDirectoryURL.path, forType: .string)
                    } label: {
                        Label(LocalizedStrings.text("data.copy_path"), systemImage: "doc.on.doc")
                    }
                }
            } header: {
                Text(LocalizedStrings.text("data.local_data"))
            } footer: {
                Text(LocalizedStrings.text("data.local_data.footer"))
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStrings.text("data.custom_stations"))
                        .font(.headline)
                    Text(LocalizedStrings.text("data.custom_count", repository.customStations.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button {
                        exportCustomStations()
                    } label: {
                        Label(LocalizedStrings.text("data.export_custom"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(repository.customStations.isEmpty)

                    Button {
                        importCustomStations()
                    } label: {
                        Label(LocalizedStrings.text("data.import_custom"), systemImage: "square.and.arrow.down")
                    }
                }
            } header: {
                Text(LocalizedStrings.text("data.backup_restore"))
            } footer: {
                Text(LocalizedStrings.text("data.backup_restore.footer"))
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
        .alert(LocalizedStrings.text("data.alert.title"), isPresented: $isShowingOperationMessage) {
            Button(LocalizedStrings.text("common.ok"), role: .cancel) {}
        } message: {
            Text(operationMessage ?? "")
        }
    }

    private func exportCustomStations() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "lo-fi-music-box-custom-stations.json"
        panel.title = LocalizedStrings.text("data.export.title")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try repository.exportCustomStations(to: url)
            showOperationMessage(LocalizedStrings.text("data.export.success", repository.customStations.count))
        } catch {
            showOperationMessage(LocalizedStrings.text("data.export.failure", error.localizedDescription))
        }
    }

    private func importCustomStations() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = LocalizedStrings.text("data.import.title")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try repository.importCustomStations(from: url)
            showOperationMessage(LocalizedStrings.text("data.import.success", repository.customStations.count))
        } catch {
            showOperationMessage(LocalizedStrings.text("data.import.failure", error.localizedDescription))
        }
    }

    private func showOperationMessage(_ message: String) {
        operationMessage = message
        isShowingOperationMessage = true
    }
}
