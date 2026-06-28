import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// macOS 偏好设置窗口（Cmd+, 触发）。当前包含五个分页：
/// - 通用：应用语言、播放体验；
/// - 频道管理：增删改自定义频道、编辑或隐藏内置频道；
/// - 数据管理：查看并打开用户数据目录；
/// - 可用性检测：自动检测、手动检测、结果分布；
/// - 关于：版本与说明信息。
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
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppConstants.Identity.displayName)
                .font(.title2.bold())

            Text(LocalizedStrings.text("settings.about.description"))
                .foregroundStyle(.secondary)

            Divider()

            Button {
                showNoUpdateAvailableAlert()
            } label: {
                Label(LocalizedStrings.text("app.menu.check_updates"), systemImage: "arrow.triangle.2.circlepath")
            }

            Spacer()
        }
        .padding(20)
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
