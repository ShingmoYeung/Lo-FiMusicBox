import AppKit
import SwiftUI

/// 滑入式频道列表遮罩，用于在主小组件内快速切换频道。
/// 关键设计：
/// - 行点击区域用 `contentShape + onTapGesture`，杜绝 SwiftUI Button 在 ScrollView 中点击不灵敏的问题；
/// - 可用性状态以小圆点颜色直观表达：绿=可用、黄=不稳定、红=不可用、灰=未检测、循环=检测中；
/// - 列表支持按名称、可用性或来源排序；
/// - 自定义标签作为高亮胶囊横排展示在频道名下方，比之前更醒目。
struct StationListOverlay: View {
    var stations: [Station]
    var currentStationId: String?
    var favoriteStationIds: Set<String>
    var onSelect: (Station) -> Void
    var onClose: () -> Void

    @State private var sortMode: StationSortMode = .availability
    @State private var showsFavoritesOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppConstants.UserInterface.smallSpacing) {
            header

            ScrollView {
                LazyVStack(spacing: AppConstants.UserInterface.smallSpacing) {
                    ForEach(displayedStations) { station in
                        StationOverlayRow(
                            station: station,
                            isActive: station.id == currentStationId,
                            isFavorite: favoriteStationIds.contains(station.id),
                            onTap: {
                                onSelect(station)
                            }
                        )
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, AppConstants.UserInterface.smallSpacing)
            }
            .scrollIndicators(.hidden)
        }
        .padding(AppConstants.UserInterface.stationOverlayPadding)
        .background(
            RoundedRectangle(cornerRadius: AppConstants.UserInterface.widgetCornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.78))
                .overlay {
                    RoundedRectangle(cornerRadius: AppConstants.UserInterface.widgetCornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
        )
    }

    /// 按当前排序维度展示；当前选中的频道无论排序方式如何都置顶。
    /// 当前选中的频道无论状态如何都置顶，方便用户看到当前播放位置。
    private var displayedStations: [Station] {
        let filtered = showsFavoritesOnly
            ? stations.filter { favoriteStationIds.contains($0.id) }
            : stations
        return filtered.sorted(using: sortMode, currentStationId: currentStationId)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(LocalizedStrings.text("station.overlay.title"))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PlayerTheme.primaryText)

            Spacer()

            Menu {
                Toggle(isOn: $showsFavoritesOnly) {
                    Label(LocalizedStrings.text("station.overlay.favorite_only"), systemImage: showsFavoritesOnly ? "star.fill" : "star")
                }
                .disabled(favoriteStationIds.isEmpty)

                Divider()

                Picker(LocalizedStrings.text("station.overlay.sort"), selection: $sortMode) {
                    ForEach(StationSortMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.iconName)
                            .tag(mode)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showsFavoritesOnly ? "star.fill" : sortMode.iconName)
                        .font(.system(size: 9, weight: .bold))
                    Text(sortMode.title)
                        .font(.system(size: 10, weight: .medium))
                }
                .frame(width: 58)
                .foregroundStyle(showsFavoritesOnly ? PlayerTheme.warmText : PlayerTheme.primaryText.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.white.opacity(showsFavoritesOnly ? 0.16 : 0.1), in: Capsule())
                .overlay {
                    Capsule().stroke(.white.opacity(0.08), lineWidth: 0.6)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 74)
            .help(favoriteStationIds.isEmpty ? LocalizedStrings.text("station.overlay.favorite_empty") : LocalizedStrings.text("station.overlay.sort_help"))

            StationOverlayCountIndicator(
                favoriteCount: displayedStations.count,
                totalCount: stations.count,
                showsFavoritesOnly: showsFavoritesOnly
            )

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(PlayerTheme.primaryText.opacity(0.85))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LocalizedStrings.text("station.overlay.close"))
        }
    }

}

private struct StationOverlayCountIndicator: View {
    var favoriteCount: Int
    var totalCount: Int
    var showsFavoritesOnly: Bool

    var body: some View {
        HStack(spacing: 5) {
            if showsFavoritesOnly {
                countItem(
                    systemName: "star.fill",
                    count: favoriteCount,
                    color: PlayerTheme.warmText,
                    help: LocalizedStrings.text("station.overlay.favorite_count_help", favoriteCount)
                )

                Text("·")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PlayerTheme.secondaryText.opacity(0.45))
            }

            countItem(
                systemName: "music.note.list",
                count: totalCount,
                color: PlayerTheme.secondaryText.opacity(0.72),
                help: LocalizedStrings.text("station.overlay.total_count_help", totalCount)
            )
        }
        .accessibilityLabel(accessibilityText)
    }

    private func countItem(systemName: String, count: Int, color: Color, help: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .semibold))
            Text("\(count)")
                .font(.caption.monospacedDigit().weight(.medium))
        }
        .foregroundStyle(color)
        .help(help)
    }

    private var accessibilityText: String {
        if showsFavoritesOnly {
            return "\(LocalizedStrings.text("station.overlay.favorite_count_help", favoriteCount))，\(LocalizedStrings.text("station.overlay.total_count_help", totalCount))"
        }
        return LocalizedStrings.text("station.overlay.total_count_help", totalCount)
    }
}

/// 单个频道行。
private struct StationOverlayRow: View {
    var station: Station
    var isActive: Bool
    var isFavorite: Bool
    var onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: AppConstants.UserInterface.smallSpacing) {
            healthIndicator

            VStack(alignment: .leading, spacing: 3) {
                titleRow
                tagsRow
            }

            Spacer(minLength: 4)

            trailingIcon
        }
        .padding(.horizontal, 10)
        .padding(.vertical, AppConstants.UserInterface.stationRowPadding)
        .background(rowBackground)
        .overlay(rowBorder)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .pointingHandCursor()
        .onTapGesture {
            onTap()
        }
        .help(healthHelpText)
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .animation(.easeInOut(duration: 0.18), value: isActive)
    }

    private var titleRow: some View {
        HStack(spacing: 4) {
            Text(station.name)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(textColor)
                .lineLimit(1)

            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(PlayerTheme.warmText)
            }

            if station.source == .custom {
                SourcePill(source: .custom, isCompact: true)
            }
        }
    }

    /// 标签行：优先展示用户自定义标签（暖色调高亮胶囊），
    /// 自定义标签为空时用 style/scene 等元数据做次级灰色胶囊。
    private var tagsRow: some View {
        let tags = station.effectiveTags
        let isUsingCustomTags = !station.customTags.isEmpty

        return HStack(spacing: 4) {
            ForEach(tags.prefix(4), id: \.self) { tag in
                TagPill(text: tag, isCustom: isUsingCustomTags)
            }
            if tags.count > 4 {
                Text("+\(tags.count - 4)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(PlayerTheme.secondaryText.opacity(0.6))
            }

            // 协议类型用更弱的胶囊补充信息。
            Text(station.type.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(PlayerTheme.secondaryText.opacity(0.7))
        }
        .lineLimit(1)
    }

    private var trailingIcon: some View {
        Image(systemName: isActive ? "waveform" : "play.circle.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(
                isActive
                    ? PlayerTheme.warmText
                    : PlayerTheme.primaryText.opacity(isHovering ? 0.95 : 0.55)
            )
    }

    /// 健康状态指示器：圆点颜色直接对应健康状态；检测中时用 ProgressView。
    private var healthIndicator: some View {
        let status = station.lastHealth?.status ?? .unknown
        return Group {
            if status == .checking {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 10, height: 10)
            } else {
                Circle()
                    .fill(healthColor(for: status))
                    .frame(width: 10, height: 10)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.25), lineWidth: 0.6)
                    }
                    .shadow(
                        color: healthColor(for: status).opacity(0.6),
                        radius: status == .available ? 4 : 0
                    )
            }
        }
        .frame(width: 14)
    }

    private func healthColor(for status: StationHealthStatus) -> Color {
        switch status {
        case .available: return PlayerTheme.successGreen
        case .unstable: return PlayerTheme.warningYellow
        case .unavailable: return PlayerTheme.dangerRed
        case .unknown, .checking: return PlayerTheme.neutralGray
        }
    }

    private var healthHelpText: String {
        let status = station.lastHealth?.status ?? .unknown
        let selectText = LocalizedStrings.text("station.overlay.select_help", station.name)
        if let message = station.lastHealth?.message {
            return "\(selectText) · \(status.friendlyDisplayName)：\(message)"
        }
        return "\(selectText) · \(status.friendlyDisplayName)"
    }

    private var textColor: Color {
        if isActive { return PlayerTheme.warmText }
        return isHovering ? PlayerTheme.primaryText : PlayerTheme.primaryText.opacity(0.92)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: PlayerTheme.stationRowCornerRadius, style: .continuous)
            .fill(rowFillColor)
    }

    private var rowFillColor: Color {
        if isActive {
            return PlayerTheme.warmText.opacity(0.18)
        }
        if isHovering {
            return Color.white.opacity(0.12)
        }
        return Color.white.opacity(0.05)
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: PlayerTheme.stationRowCornerRadius, style: .continuous)
            .stroke(borderColor, lineWidth: isActive ? 1.2 : 1)
    }

    private var borderColor: Color {
        if isActive { return PlayerTheme.warmText.opacity(0.55) }
        if isHovering { return Color.white.opacity(0.22) }
        return Color.white.opacity(0.08)
    }
}

/// 自定义标签胶囊：暖色高亮，与协议类型/scene 等次级文本拉开层次。
struct TagPill: View {
    var text: String
    var isCustom: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(fillColor)
            )
            .overlay(
                Capsule().stroke(strokeColor, lineWidth: 0.6)
            )
    }

    private var textColor: Color {
        isCustom ? PlayerTheme.warmText : PlayerTheme.secondaryText.opacity(0.85)
    }

    private var fillColor: Color {
        isCustom ? PlayerTheme.warmText.opacity(0.16) : Color.white.opacity(0.08)
    }

    private var strokeColor: Color {
        isCustom ? PlayerTheme.warmText.opacity(0.36) : Color.white.opacity(0.12)
    }
}

/// 频道来源胶囊：内置=蓝、自定义=橘。
struct SourcePill: View {
    var source: StationSource
    var isCompact: Bool = false

    var body: some View {
        Text(source.displayName)
            .font(.system(size: isCompact ? 8 : 10, weight: .bold))
            .foregroundStyle(textColor)
            .frame(width: isCompact ? 42 : 54)
            .padding(.horizontal, isCompact ? 4 : 6)
            .padding(.vertical, isCompact ? 1 : 2)
            .background(
                Capsule().fill(fillColor)
            )
            .overlay(
                Capsule().stroke(strokeColor, lineWidth: 0.6)
            )
    }

    private var textColor: Color {
        switch source {
        case .bundled: return PlayerTheme.bundledBadgeColor
        case .custom: return PlayerTheme.customBadgeColor
        }
    }

    private var fillColor: Color {
        textColor.opacity(0.14)
    }

    private var strokeColor: Color {
        textColor.opacity(0.32)
    }
}
