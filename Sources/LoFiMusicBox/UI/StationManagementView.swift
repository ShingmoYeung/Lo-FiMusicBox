import AppKit
import SwiftUI

/// 频道管理页：在 macOS Settings 窗口中以单列列表展示全部频道（含被隐藏的内置频道），
/// 每行可点击编辑、检测、删除/隐藏/恢复默认。
/// 重要交互：所有破坏性操作都会通过 `.confirmationDialog` 弹出确认提示。
struct StationManagementView: View {
    @EnvironmentObject private var repository: StationRepository
    @EnvironmentObject private var checker: ScheduledHealthChecker

    @State private var editingStation: Station?
    @State private var isShowingAddSheet = false
    @State private var pendingDeleteStation: Station?
    @State private var pendingHideStation: Station?
    @State private var pendingUnhideStation: Station?
    @State private var pendingResetStation: Station?
    @State private var detailStation: Station?
    @State private var checkingStationIds: Set<String> = []
    @State private var searchText: String = ""
    @State private var sortMode: StationSortMode = .availability
    @State private var activeFilter: StationManagementFilter?

    private let healthService = StationHealthService()
    /// 与搜索框本体左侧对齐：放大镜图标宽度约 16pt，图标与输入框间距 6pt。
    private let searchFieldLeadingOffset: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolbar
            statisticsRow
            stationsList
        }
        .padding(14)
        .sheet(item: $editingStation) { station in
            StationEditSheet(
                originalStation: station,
                onSave: { updated in
                    save(edited: updated)
                    editingStation = nil
                },
                onCancel: { editingStation = nil }
            )
            .frame(minWidth: 460, minHeight: 460)
        }
        .sheet(isPresented: $isShowingAddSheet) {
            StationEditSheet(
                originalStation: makeNewCustomStationDraft(),
                isAddingNew: true,
                onSave: { newStation in
                    repository.addCustomStation(newStation)
                    isShowingAddSheet = false
                },
                onCancel: { isShowingAddSheet = false }
            )
            .frame(minWidth: 460, minHeight: 460)
        }
        .sheet(item: $detailStation) { station in
            StationDetailSheet(station: station) {
                detailStation = nil
            }
            .frame(minWidth: 520, minHeight: 420)
        }
        .confirmationDialog(
            LocalizedStrings.text("station.management.delete_custom.title"),
            isPresented: bindingPresence($pendingDeleteStation),
            titleVisibility: .visible,
            presenting: pendingDeleteStation
        ) { station in
            Button(LocalizedStrings.text("station.management.delete_custom.action", station.name), role: .destructive) {
                repository.deleteCustomStation(station)
                pendingDeleteStation = nil
            }
            Button(LocalizedStrings.text("common.cancel"), role: .cancel) { pendingDeleteStation = nil }
        } message: { station in
            Text(LocalizedStrings.text("station.management.delete_custom.message", station.name))
        }
        .confirmationDialog(
            LocalizedStrings.text("station.management.hide_bundled.title"),
            isPresented: bindingPresence($pendingHideStation),
            titleVisibility: .visible,
            presenting: pendingHideStation
        ) { station in
            Button(LocalizedStrings.text("station.management.hide_bundled.action", station.name), role: .destructive) {
                repository.hideBundledStation(stationId: station.id)
                pendingHideStation = nil
            }
            Button(LocalizedStrings.text("common.cancel"), role: .cancel) { pendingHideStation = nil }
        } message: { _ in
            Text(LocalizedStrings.text("station.management.hide_bundled.message"))
        }
        .confirmationDialog(
            LocalizedStrings.text("station.management.unhide.title"),
            isPresented: bindingPresence($pendingUnhideStation),
            titleVisibility: .visible,
            presenting: pendingUnhideStation
        ) { station in
            Button(LocalizedStrings.text("station.management.unhide.action", station.name)) {
                repository.unhideBundledStation(stationId: station.id)
                pendingUnhideStation = nil
            }
            Button(LocalizedStrings.text("common.cancel"), role: .cancel) { pendingUnhideStation = nil }
        } message: { _ in
            Text(LocalizedStrings.text("station.management.unhide.message"))
        }
        .confirmationDialog(
            LocalizedStrings.text("station.management.reset.title"),
            isPresented: bindingPresence($pendingResetStation),
            titleVisibility: .visible,
            presenting: pendingResetStation
        ) { station in
            Button(LocalizedStrings.text("station.management.reset.action", station.name), role: .destructive) {
                repository.resetBundledStation(stationId: station.id)
                pendingResetStation = nil
            }
            Button(LocalizedStrings.text("common.cancel"), role: .cancel) { pendingResetStation = nil }
        } message: { _ in
            Text(LocalizedStrings.text("station.management.reset.message"))
        }
    }

    // MARK: - 顶部工具栏

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(LocalizedStrings.text("station.management.search"), text: $searchText)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(maxWidth: .infinity)

                Button {
                    isShowingAddSheet = true
                } label: {
                    Label(LocalizedStrings.text("station.management.add"), systemImage: "plus")
                }
            }

            HStack(spacing: 8) {
                Picker("", selection: $sortMode) {
                    ForEach(StationSortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                .help(LocalizedStrings.text("station.management.sort_help"))

                Button {
                    Task { await checker.runOneRoundNow() }
                } label: {
                    Label(
                        checker.isCheckingNow
                            ? "\(checker.completedCount)/\(checker.totalCount)"
                            : LocalizedStrings.text("station.management.bulk_check"),
                        systemImage: "stethoscope"
                    )
                }
                .disabled(checker.isCheckingNow)

                Spacer()
            }
        }
    }

    private var statisticsRow: some View {
        let allStations = repository.allStationsIncludingHidden
        let bundledCount = allStations.filter { $0.source == .bundled }.count
        let customCount = allStations.filter { $0.source == .custom }.count
        let hiddenCount = repository.hiddenBundledStationIds.count
        let favoriteCount = repository.favoriteStationIds.count

        return HStack(spacing: 8) {
            StatisticPill(
                label: LocalizedStrings.text("station.source.bundled"),
                value: bundledCount,
                color: PlayerTheme.bundledBadgeColor,
                isSelected: activeFilter == .bundled
            ) {
                toggleFilter(.bundled)
            }
            StatisticPill(
                label: LocalizedStrings.text("station.source.custom"),
                value: customCount,
                color: PlayerTheme.customBadgeColor,
                isSelected: activeFilter == .custom
            ) {
                toggleFilter(.custom)
            }
            if favoriteCount > 0 {
                StatisticPill(
                    label: LocalizedStrings.text("station.management.favorite_count"),
                    value: favoriteCount,
                    color: PlayerTheme.brassDark,
                    isSelected: activeFilter == .favorites
                ) {
                    toggleFilter(.favorites)
                }
            }
            if hiddenCount > 0 {
                StatisticPill(label: LocalizedStrings.text("station.management.hidden_count"), value: hiddenCount, color: PlayerTheme.neutralGray)
            }
            Spacer()
        }
        .padding(.leading, searchFieldLeadingOffset)
    }

    private var stationsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredStations) { station in
                    StationManagementRow(
                        station: station,
                        isHidden: repository.isHidden(stationId: station.id),
                        isFavorite: repository.isFavorite(stationId: station.id),
                        hasOverride: repository.hasBundledOverride(stationId: station.id),
                        isCheckingNow: checkingStationIds.contains(station.id),
                        onToggleFavorite: { repository.toggleFavorite(stationId: station.id) },
                        onShowDetails: { detailStation = station },
                        onEdit: { editingStation = station },
                        onCheck: { checkOne(station) },
                        onDeleteCustom: { pendingDeleteStation = station },
                        onHideBundled: { pendingHideStation = station },
                        onUnhideBundled: { pendingUnhideStation = station },
                        onResetBundled: { pendingResetStation = station }
                    )
                    .padding(.vertical, 4)

                    Divider()
                        .opacity(0.55)
                }
            }
        }
        .padding(.leading, searchFieldLeadingOffset)
    }

    /// 搜索结果只匹配“频道名称”和“标签”（包含自定义标签和 style/scene 等 fallback 标签），
    /// 不再匹配 URL 或分类，避免用户输入随意字符就把列表过滤空。
    /// 排序提供名称、可用性、来源三种明确维度。
    private var filteredStations: [Station] {
        let stations = repository.allStationsIncludingHidden
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filterMatched = stations.filter { station in
            switch activeFilter {
            case .bundled:
                return station.source == .bundled
            case .custom:
                return station.source == .custom
            case .favorites:
                return repository.favoriteStationIds.contains(station.id)
            case nil:
                return true
            }
        }

        let filtered: [Station]
        if trimmed.isEmpty {
            filtered = filterMatched
        } else {
            let lowered = trimmed.lowercased()
            filtered = filterMatched.filter { station in
                if station.name.lowercased().contains(lowered) { return true }
                return station.effectiveTags.contains { $0.lowercased().contains(lowered) }
            }
        }

        return filtered.sorted(using: sortMode)
    }

    private func toggleFilter(_ filter: StationManagementFilter) {
        activeFilter = activeFilter == filter ? nil : filter
    }

    // MARK: - 业务方法

    private func makeNewCustomStationDraft() -> Station {
        Station(
            stableIdentifier: AppConstants.Resource.customStationIdPrefix + UUID().uuidString,
            name: "",
            category: LocalizedStrings.text("station.source.custom"),
            type: .mp3,
            url: URL(string: "https://example.com/stream")!,
            customTags: [],
            source: .custom
        )
    }

    private func save(edited station: Station) {
        switch station.source {
        case .custom:
            repository.updateCustomStation(station)
        case .bundled:
            repository.applyOverrideToBundledStation(updated: station)
        }
    }

    private func checkOne(_ station: Station) {
        guard !checkingStationIds.contains(station.id) else { return }
        checkingStationIds.insert(station.id)

        repository.updateHealth(for: station, health: StationHealth(
            status: .checking,
            checkedAt: Date(),
            responseTimeMilliseconds: nil,
            statusCode: nil,
            contentType: nil,
            message: LocalizedStrings.text("station.management.checking")
        ))

        Task {
            let health = await healthService.check(station)
            await MainActor.run {
                checkingStationIds.remove(station.id)
                repository.updateHealth(for: station, health: health)
            }
        }
    }

    private func bindingPresence<Value>(_ binding: Binding<Value?>) -> Binding<Bool> {
        Binding(
            get: { binding.wrappedValue != nil },
            set: { newValue in
                if !newValue { binding.wrappedValue = nil }
            }
        )
    }
}

enum StationSortMode: String, CaseIterable, Identifiable {
    case name
    case availability
    case source

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: LocalizedStrings.text("station.sort.name")
        case .availability: LocalizedStrings.text("station.sort.availability")
        case .source: LocalizedStrings.text("station.sort.source")
        }
    }

    var iconName: String {
        switch self {
        case .name: "list.bullet"
        case .availability: "checkmark.seal"
        case .source: "tray.full"
        }
    }
}

private enum StationManagementFilter: Equatable {
    case bundled
    case custom
    case favorites
}

extension Array where Element == Station {
    func sorted(using mode: StationSortMode, currentStationId: String? = nil) -> [Station] {
        sorted { lhs, rhs in
            switch mode {
            case .name:
                return compareByName(lhs, rhs)
            case .availability:
                if shouldPinCurrentStation(lhs, before: rhs, currentStationId: currentStationId) {
                    return true
                }
                if shouldPinCurrentStation(rhs, before: lhs, currentStationId: currentStationId) {
                    return false
                }
                let lhsPriority = (lhs.lastHealth?.status ?? .unknown).sortPriority
                let rhsPriority = (rhs.lastHealth?.status ?? .unknown).sortPriority
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return compareByName(lhs, rhs)
            case .source:
                if shouldPinCurrentStation(lhs, before: rhs, currentStationId: currentStationId) {
                    return true
                }
                if shouldPinCurrentStation(rhs, before: lhs, currentStationId: currentStationId) {
                    return false
                }
                let lhsPriority = lhs.source.sortPriority
                let rhsPriority = rhs.source.sortPriority
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return compareByName(lhs, rhs)
            }
        }
    }

    private func compareByName(_ lhs: Station, _ rhs: Station) -> Bool {
        let result = lhs.name.localizedStandardCompare(rhs.name)
        if result != .orderedSame { return result == .orderedAscending }
        return lhs.id < rhs.id
    }

    private func shouldPinCurrentStation(
        _ station: Station,
        before otherStation: Station,
        currentStationId: String?
    ) -> Bool {
        guard let currentStationId else { return false }
        return station.id == currentStationId && otherStation.id != currentStationId
    }
}

private extension StationSource {
    var sortPriority: Int {
        switch self {
        case .bundled: 0
        case .custom: 1
        }
    }
}

// MARK: - 单行视图

private struct StationManagementRow: View {
    var station: Station
    var isHidden: Bool
    var isFavorite: Bool
    var hasOverride: Bool
    var isCheckingNow: Bool
    var onToggleFavorite: () -> Void
    var onShowDetails: () -> Void
    var onEdit: () -> Void
    var onCheck: () -> Void
    var onDeleteCustom: () -> Void
    var onHideBundled: () -> Void
    var onUnhideBundled: () -> Void
    var onResetBundled: () -> Void

    private let availabilityColumnWidth: CGFloat = 132

    var body: some View {
        headerRow
        .opacity(isHidden ? 0.55 : 1)
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            primaryInfo
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            availabilityBadge
                .frame(width: availabilityColumnWidth, alignment: .trailing)

            rowActions
        }
    }

    private var primaryInfo: some View {
        HStack(spacing: 6) {
            SourcePill(source: station.source)
            Text(station.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.85)
                .strikethrough(isHidden, color: .secondary)
                .layoutPriority(1)
            if hasOverride {
                Text(LocalizedStrings.text("common.modified"))
                    .font(.caption2.bold())
                    .foregroundStyle(PlayerTheme.warningYellow)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(PlayerTheme.warningYellow.opacity(0.18), in: Capsule())
            }
            if isHidden {
                Text(LocalizedStrings.text("common.hidden"))
                    .font(.caption2.bold())
                    .foregroundStyle(PlayerTheme.neutralGray)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(PlayerTheme.neutralGray.opacity(0.18), in: Capsule())
            }
        }
    }

    private var rowActions: some View {
        Menu {
            Button {
                onShowDetails()
            } label: {
                Label(LocalizedStrings.text("station.management.view_details"), systemImage: "info.circle")
            }

            Divider()

            Button {
                onToggleFavorite()
            } label: {
                Label(
                    isFavorite ? LocalizedStrings.text("station.management.favorite.remove") : LocalizedStrings.text("station.management.favorite.add"),
                    systemImage: isFavorite ? "star.slash" : "star"
                )
            }

            Divider()

            Button {
                onCheck()
            } label: {
                Label(
                    isCheckingNow ? LocalizedStrings.text("station.management.checking") : LocalizedStrings.text("station.management.check_one"),
                    systemImage: isCheckingNow ? "hourglass" : "stethoscope"
                )
            }
            .disabled(isCheckingNow)

            Button {
                onEdit()
            } label: {
                Label(LocalizedStrings.text("common.edit"), systemImage: "pencil")
            }

            if station.source == .custom {
                Button(role: .destructive) {
                    onDeleteCustom()
                } label: {
                    Label(LocalizedStrings.text("common.delete"), systemImage: "trash")
                }
            } else {
                if isHidden {
                    Button {
                        onUnhideBundled()
                    } label: {
                        Label(LocalizedStrings.text("station.management.unhide"), systemImage: "eye")
                    }
                } else {
                    Button(role: .destructive) {
                        onHideBundled()
                    } label: {
                        Label(LocalizedStrings.text("station.management.hide"), systemImage: "eye.slash")
                    }
                }
                if hasOverride {
                    Button(role: .destructive) {
                        onResetBundled()
                    } label: {
                        Label(LocalizedStrings.text("station.management.reset_default"), systemImage: "arrow.uturn.backward.circle")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(Color.secondary.opacity(0.10), in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .controlSize(.small)
        .frame(width: 24, height: 24)
        .help(LocalizedStrings.text("station.management.more_actions"))
    }

    private var availabilityBadge: some View {
        let status = station.lastHealth?.status ?? .unknown
        let summary = station.lastHealth.map(healthSummary) ?? status.friendlyDisplayName
        return HStack(spacing: 4) {
            Circle()
                .fill(healthColor(status))
                .frame(width: 7, height: 7)
            Text(availabilitySummary)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(healthColor(status))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(healthColor(status).opacity(0.14), in: Capsule())
        .help(summary)
    }

    private func healthColor(_ status: StationHealthStatus) -> Color {
        switch status {
        case .available: return PlayerTheme.successGreen
        case .unstable: return PlayerTheme.warningYellow
        case .unavailable: return PlayerTheme.dangerRed
        case .unknown, .checking: return PlayerTheme.neutralGray
        }
    }

    private func healthSummary(_ health: StationHealth) -> String {
        var parts: [String] = [health.status.friendlyDisplayName]
        if let statusCode = health.statusCode {
            parts.append("HTTP \(statusCode)")
        }
        if let responseTime = health.responseTimeMilliseconds {
            parts.append("\(responseTime) ms")
        }
        if let message = health.message {
            parts.append(message)
        }
        return parts.joined(separator: " · ")
    }

    private var availabilitySummary: String {
        guard let health = station.lastHealth else { return StationHealthStatus.unknown.friendlyDisplayName }
        if let responseTime = health.responseTimeMilliseconds {
            return "\(health.status.friendlyDisplayName) \(responseTime)ms"
        }
        return health.status.friendlyDisplayName
    }
}

extension StationHealthStatus {
    var friendlyDisplayName: String {
        switch self {
        case .available: LocalizedStrings.text("station.health.available")
        case .unstable: LocalizedStrings.text("station.health.unstable")
        case .unavailable: LocalizedStrings.text("station.health.unavailable")
        case .checking: LocalizedStrings.text("station.health.checking")
        case .unknown: LocalizedStrings.text("station.health.unknown")
        }
    }
}

private struct StatisticPill: View {
    var label: String
    var value: Int
    var color: Color
    var isSelected: Bool = false
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
        .help(action == nil ? "" : LocalizedStrings.text("station.management.filter_help"))
    }

    private var content: some View {
        HStack(spacing: 4) {
            Text(label)
            Text("\(value)").bold().monospacedDigit()
        }
        .font(.caption.weight(isSelected ? .bold : .medium))
        .foregroundStyle(isSelected ? Color.white : color)
        .padding(.horizontal, isSelected ? 10 : 8)
        .padding(.vertical, 3)
        .background((isSelected ? color : color.opacity(0.15)), in: Capsule())
        .overlay {
            Capsule().stroke(color.opacity(isSelected ? 0.55 : 0.22), lineWidth: isSelected ? 1.2 : 0.6)
        }
    }
}

private struct StationDetailSheet: View {
    var station: Station
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(station.name)
                        .font(.headline)
                    Text(LocalizedStrings.text("station.management.details.title"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                SourcePill(source: station.source)
            }
            .padding(16)

            Divider()

            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    detailRow(LocalizedStrings.text("common.name"), station.name)
                    detailRow(LocalizedStrings.text("station.sort.source"), station.source.displayName)
                    detailRow(LocalizedStrings.text("common.type"), station.type.displayName)
                    detailRow(LocalizedStrings.text("common.category"), station.category)
                    detailRow(LocalizedStrings.text("common.url"), station.url.absoluteString, isMonospaced: true)
                    detailRow(LocalizedStrings.text("station.management.details.tags"), tagsText)
                    detailRow(LocalizedStrings.text("station.management.details.health"), healthText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }

            Divider()

            HStack {
                Spacer()
                Button(LocalizedStrings.text("common.ok")) {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
    }

    private func detailRow(_ label: String, _ value: String, isMonospaced: Bool = false) -> some View {
        GridRow {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
            Text(value)
                .font(isMonospaced ? .caption.monospaced() : .caption)
                .textSelection(.enabled)
                .lineLimit(nil)
        }
    }

    private var tagsText: String {
        let tags = station.effectiveTags
        return tags.isEmpty ? LocalizedStrings.text("station.management.details.none") : tags.joined(separator: " / ")
    }

    private var healthText: String {
        guard let health = station.lastHealth else {
            return StationHealthStatus.unknown.friendlyDisplayName
        }

        var parts = [health.status.friendlyDisplayName]
        if let responseTime = health.responseTimeMilliseconds {
            parts.append("\(responseTime) ms")
        }
        if let statusCode = health.statusCode {
            parts.append("HTTP \(statusCode)")
        }
        if let contentType = health.contentType {
            parts.append(contentType)
        }
        if let message = health.message {
            parts.append(message)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 编辑 / 新增 Sheet

/// 用于新增和编辑两种场景。
private struct StationEditSheet: View {
    @State var draft: Station
    var isAddingNew: Bool
    var onSave: (Station) -> Void
    var onCancel: () -> Void

    init(
        originalStation: Station,
        isAddingNew: Bool = false,
        onSave: @escaping (Station) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: originalStation)
        self.isAddingNew = isAddingNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    @State private var urlString: String = ""
    @State private var newTagText: String = ""
    @State private var isShowingValidationError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Form {
                Section {
                    TextField(LocalizedStrings.text("common.name"), text: $draft.name)
                    TextField(LocalizedStrings.text("common.url"), text: $urlString)
                        .onChange(of: urlString) { _, newValue in
                            if let url = URL(string: newValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                draft.url = url
                            }
                            draft.type = StationType.inferred(from: newValue)
                        }
                    Picker(LocalizedStrings.text("common.type"), selection: $draft.type) {
                        ForEach(StationType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    if isAddingNew {
                        TextField(LocalizedStrings.text("common.category"), text: $draft.category)
                    }
                } header: {
                    Text(LocalizedStrings.text("station.management.basic_info"))
                } footer: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(LocalizedStrings.text("station.management.url_help"))
                        Text(LocalizedStrings.text("station.management.url_help.bilibili"))
                        Text(LocalizedStrings.text("station.management.url_help.hls"))
                        Text(LocalizedStrings.text("station.management.url_help.direct"))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    customTagsEditor
                } header: {
                    Text(LocalizedStrings.text("station.management.custom_tags"))
                } footer: {
                    Text(LocalizedStrings.text("station.management.custom_tags.footer"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            footerButtons
        }
        .onAppear {
            urlString = draft.url.absoluteString
        }
        .alert(LocalizedStrings.text("station.management.validation_error"), isPresented: $isShowingValidationError) {
            Button(LocalizedStrings.text("common.ok"), role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(isAddingNew ? LocalizedStrings.text("station.management.edit.title.add") : LocalizedStrings.text("station.management.edit.title.edit"))
                    .font(.headline)
                Text(draft.source == .bundled ? LocalizedStrings.text("station.management.edit.subtitle.bundled") : LocalizedStrings.text("station.management.edit.subtitle.custom"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SourcePill(source: draft.source)
        }
        .padding(16)
    }

    private var customTagsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if draft.customTags.isEmpty {
                Text(LocalizedStrings.text("station.management.no_custom_tags"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(Array(draft.customTags.enumerated()), id: \.offset) { index, tag in
                        EditableTagPill(text: tag) {
                            draft.customTags.remove(at: index)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                TextField(LocalizedStrings.text("station.management.tag_placeholder"), text: $newTagText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitNewTag() }
                Button(LocalizedStrings.text("common.add")) { commitNewTag() }
                    .disabled(trimmedNewTag.isEmpty)
            }
        }
        .padding(.vertical, 4)
    }

    private var trimmedNewTag: String {
        newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commitNewTag() {
        let tag = trimmedNewTag
        guard !tag.isEmpty, !draft.customTags.contains(tag) else { return }
        draft.customTags.append(tag)
        newTagText = ""
    }

    private var footerButtons: some View {
        HStack {
            Spacer()
            Button(LocalizedStrings.text("common.cancel"), role: .cancel) { onCancel() }
                .keyboardShortcut(.cancelAction)
            Button(isAddingNew ? LocalizedStrings.text("common.add") : LocalizedStrings.text("common.save")) {
                if let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
                   !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    var finalDraft = draft
                    finalDraft.url = url
                    onSave(finalDraft)
                } else {
                    isShowingValidationError = true
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }
}

private struct EditableTagPill: View {
    var text: String
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PlayerTheme.warmText)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(PlayerTheme.warmText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(PlayerTheme.warmText.opacity(0.16), in: Capsule())
        .overlay(Capsule().stroke(PlayerTheme.warmText.opacity(0.32), lineWidth: 0.6))
    }
}

// FlowLayout 已抽取为共享组件，见 UI/FlowLayout.swift。
