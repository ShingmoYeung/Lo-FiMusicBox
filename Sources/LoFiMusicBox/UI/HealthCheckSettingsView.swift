import SwiftUI

/// 可用性检测的独立配置面板。
/// 这里只暴露用户可调的设置，实际定时调度逻辑都在 `ScheduledHealthChecker` 中。
struct HealthCheckSettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var checker: ScheduledHealthChecker
    @EnvironmentObject private var repository: StationRepository

    var body: some View {
        Form {
            Section {
                Toggle(
                    LocalizedStrings.text("availability.auto.enable"),
                    isOn: Binding(
                        get: { settings.healthAutoCheckEnabled },
                        set: { newValue in
                            settings.updateHealthAutoCheckEnabled(newValue)
                            checker.reschedule()
                        }
                    )
                )
                .help(LocalizedStrings.text("availability.auto.enable_help"))

                Picker(
                    LocalizedStrings.text("availability.auto.interval"),
                    selection: Binding(
                        get: { settings.healthCheckIntervalMinutes },
                        set: { newValue in
                            settings.updateHealthCheckIntervalMinutes(newValue)
                            checker.reschedule()
                        }
                    )
                ) {
                    ForEach(AppConstants.Settings.healthCheckIntervalChoices, id: \.self) { minutes in
                        Text(intervalDisplayName(forMinutes: minutes)).tag(minutes)
                    }
                }
                .disabled(!settings.healthAutoCheckEnabled)

                Toggle(
                    LocalizedStrings.text("availability.auto.idle_only"),
                    isOn: Binding(
                        get: { settings.healthCheckOnlyWhenIdle },
                        set: { newValue in
                            settings.updateHealthCheckOnlyWhenIdle(newValue)
                        }
                    )
                )
                .help(LocalizedStrings.text("availability.auto.idle_only_help"))
                .disabled(!settings.healthAutoCheckEnabled)
            } header: {
                Text(LocalizedStrings.text("availability.section.auto"))
            }

            Section {
                HStack {
                    Text(LocalizedStrings.text("availability.last_checked"))
                    Spacer()
                    Text(lastCheckedDescription)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(LocalizedStrings.text("availability.progress"))
                    Spacer()
                    if checker.isCheckingNow {
                        Text("\(checker.completedCount) / \(checker.totalCount)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        Text(LocalizedStrings.text("availability.idle"))
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    Task {
                        await checker.runOneRoundNow()
                    }
                } label: {
                    Label(LocalizedStrings.text("availability.run_now"), systemImage: "bolt.fill")
                }
                .disabled(checker.isCheckingNow)

                statusBreakdown
            } header: {
                Text(LocalizedStrings.text("availability.section.manual"))
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }

    private var statusBreakdown: some View {
        let stations = repository.allStationsIncludingHidden
        let buckets = Dictionary(grouping: stations) { station in
            station.lastHealth?.status ?? .unknown
        }

        return VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStrings.text("availability.result_distribution"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                healthChip(label: StationHealthStatus.available.friendlyDisplayName, count: buckets[.available]?.count ?? 0, color: .green)
                healthChip(label: StationHealthStatus.unstable.friendlyDisplayName, count: buckets[.unstable]?.count ?? 0, color: .yellow)
                healthChip(label: StationHealthStatus.unknown.friendlyDisplayName, count: buckets[.unknown]?.count ?? 0, color: .gray)
                healthChip(label: StationHealthStatus.unavailable.friendlyDisplayName, count: buckets[.unavailable]?.count ?? 0, color: .red)
            }
        }
    }

    private func healthChip(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label) \(count)")
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1), in: Capsule())
    }

    private var lastCheckedDescription: String {
        guard let lastCheckedAt = settings.healthLastCheckedAt else { return LocalizedStrings.text("availability.never_checked") }
        let absoluteFormatter = DateFormatter()
        absoluteFormatter.locale = .current
        absoluteFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.locale = .current
        relativeFormatter.unitsStyle = .short
        let relative = relativeFormatter.localizedString(for: lastCheckedAt, relativeTo: Date())
        return "\(absoluteFormatter.string(from: lastCheckedAt))（\(relative)）"
    }

    private func intervalDisplayName(forMinutes minutes: Int) -> String {
        switch minutes {
        case 60: return LocalizedStrings.text("availability.interval.hour")
        default: return LocalizedStrings.text("availability.interval.minutes", minutes)
        }
    }
}
