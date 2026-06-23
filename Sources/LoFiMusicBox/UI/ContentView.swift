import AppKit
import SwiftUI

/// 主播放小组件。整体是一台连续的复古木质唱机（与应用图标一致的实物语言）：
/// - 顶部：左侧 [关闭][最小化]（macOS 风格红绿灯位置），右侧 [频道列表] 功能按钮；
/// - 顶面：左侧唱盘（黑胶 + 唱针，嵌入机身顶面），右侧嵌入式深色"显示屏"展示频道名 + 标签；
/// - 前面板：一道蚀刻接缝之下，是黄铜音量调谐 + 今日专注 + 上一曲/播放/下一曲控件；
/// - 深靛蓝主题不再铺满背景，而是延续在"显示屏"中，木质机身成为画面主体；
/// - 频道切换通过覆盖层 `StationListOverlay` 实现；频道管理收纳到菜单栏“首选项”。
struct ContentView: View {
    @EnvironmentObject private var repository: StationRepository
    @EnvironmentObject private var playback: PlaybackCoordinator
    @EnvironmentObject private var focusTimeService: FocusTimeService
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var mainWindowCoordinator: MainWindowCoordinator

    @State private var isShowingStationOverlay = false
    @State private var hasRestoredInitialPlaybackState = false
    @State private var hostWindow: NSWindow?
    /// 静音前的音量，用于"取消静音"时恢复到原来的大小。
    @State private var volumeBeforeMute: Float = AppConstants.Playback.defaultVolume
    /// 专注计时胶囊的悬停态，用于浮现"重置"提示图标。
    @State private var isFocusChipHovering = false
    /// 当前选中的唱片盘面序号，持久化保存（关 App 后仍记住上次换的盘面）。
    @AppStorage("selectedVinylFaceIndex") private var vinylFaceIndex = 0
    /// 当前播放氛围动效序号。它与唱盘盘面独立随机，避免用户感知到固定映射。
    @AppStorage("selectedPlaybackAuraIndex") private var playbackAuraIndex = 0
    /// 首次恢复上次播放频道时不随机换盘，避免打开 App 就改变用户上次选择的盘面。
    @State private var suppressNextVinylFaceRandomization = false
    @State private var isShowingLoadingTape = false
    @State private var loadingTapeTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            widgetBody

            if isShowingStationOverlay {
                StationListOverlay(
                    stations: repository.stations,
                    currentStationId: playback.currentStation?.id,
                    favoriteStationIds: repository.favoriteStationIds,
                    onSelect: { station in
                        playAndRemember(station)
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isShowingStationOverlay = false
                        }
                    },
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isShowingStationOverlay = false
                        }
                    }
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(
            width: AppConstants.UserInterface.widgetWindowWidth,
            height: AppConstants.UserInterface.widgetWindowHeight
        )
        .background(WidgetWindowConfigurator { window in
            hostWindow = window
            mainWindowCoordinator.updateMainWindow(window)
        })
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.UserInterface.widgetCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppConstants.UserInterface.widgetCornerRadius, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 14)
        // ignoresSafeArea 必须放在所有装饰修饰符之后的最外层，
        // 才能让"已经做完背景/裁切/边框/阴影"的整组合视图布局到 contentView 的整个区域，
        // 包括原 titlebar 高度的那 28pt，从而消除顶部和底部的透明带。
        .ignoresSafeArea()
        .onAppear {
            mainWindowCoordinator.applyMenuBarActivationPolicy()
            restoreInitialPlaybackStateIfNeeded()
            focusTimeService.updatePlaybackState(isPlaying: playback.isPlaying)
        }
        .onChange(of: playback.isPlaying) { _, isPlaying in
            focusTimeService.updatePlaybackState(isPlaying: isPlaying)
        }
        .onChange(of: playback.currentStation) { oldStation, station in
            appSettings.updateLastStationIdentifier(station?.id)
            guard oldStation?.id != station?.id, station != nil else { return }
            if suppressNextVinylFaceRandomization {
                suppressNextVinylFaceRandomization = false
            } else {
                showLoadingTapeCue()
                randomizeVinylFace()
                randomizePlaybackAura(for: station)
            }
        }
        .onChange(of: playback.volume) { _, volume in
            appSettings.updatePreferredVolume(volume)
        }
    }

    /// 整个小组件 = 一台连续的复古木质唱机：
    /// - 底层是一整块木质机身（`woodConsoleSurface`），顶面亮、前面板暗；
    /// - 顶面左侧嵌入唱盘（`VinylRecordView` 嵌入式：无独立木箱），右侧是下陷的深色"显示屏"；
    /// - 一道蚀刻接缝把顶面与前面板分开，前面板上是音量调谐与播放/切台控件。
    /// 深靛蓝主题不再铺满背景，而是延续在"显示屏"里，机身则成为画面主体实物。
    private var widgetBody: some View {
        ZStack {
            woodConsoleSurface

            VStack(spacing: AppConstants.UserInterface.smallSpacing) {
                topBar

                HStack(alignment: .top, spacing: AppConstants.UserInterface.mediumSpacing) {
                    turntableDeck

                    // 嵌入木面的深色"显示屏"：频道名 + 标签，沿用深靛蓝主题作为点亮的屏幕。
                    displayScreen
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // 前面板控件区：蚀刻接缝 + 音量调谐 + 传输三键，直接做在同一块木质机身上。
                controlStrip
            }
            // 上下左右 padding 都用 widgetEdgeInset (14)，与 widgetCornerRadius (16) 配合：
            // 顶部按钮起点 (14, 14) 距左上圆角圆心 (16, 16) 仅 2.83pt，远小于半径 16，必在圆内不会被剪。
            .padding(.horizontal, AppConstants.UserInterface.widgetEdgeInset)
            .padding(.top, AppConstants.UserInterface.widgetEdgeInset)
            .padding(.bottom, AppConstants.UserInterface.widgetEdgeInset)
        }
    }

    /// 顶面唱机区域：唱盘本体 + 右侧外沿的拟物换盘配件。
    /// 配件贴在唱机旁边而非压在唱盘上，避免与唱片和唱针形成物理冲突。
    private var turntableDeck: some View {
        ZStack(alignment: .trailing) {
            VinylRecordView(
                isPlaying: playback.isPlaying,
                // 传入当前频道 ID，VinylRecordView 内部以此驱动"换片"抬针-落针动画。
                stationToken: playback.currentStation?.id,
                embedded: true,
                face: currentVinylFace,
                auraStyle: currentPlaybackAuraStyle,
                auraIntensity: appSettings.playbackAuraIntensity
            ) {
                playback.togglePlayPause()
            }
            .frame(width: 132, height: 112, alignment: .leading)
            .padding(.trailing, 22)

            VinylFaceSwapButton(face: currentVinylFace) {
                cycleVinylFace()
            }
            .offset(x: 1, y: 28)
        }
        .frame(width: 156, height: 112, alignment: .leading)
    }

    /// 一体化木质机身表面：主体木纹（顶亮底暗）+ 顶部高光 + 前面板暗带 + 细木纹横纹。
    /// 外层 body 已用 clipShape 把四角裁成圆角，这里直接铺满即可。
    private var woodConsoleSurface: some View {
        ZStack {
            LinearGradient(
                colors: [
                    PlayerTheme.cabinetWoodTop,
                    PlayerTheme.cabinetWoodMid,
                    PlayerTheme.cabinetWoodBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // 顶面高光：模拟光从上方打在机身顶面。
            LinearGradient(
                colors: [.white.opacity(0.10), .clear],
                startPoint: .top,
                endPoint: .center
            )

            // 细木纹横纹，极淡，增加木质质感。
            VStack(spacing: 13) {
                ForEach(0..<12, id: \.self) { _ in
                    Rectangle()
                        .fill(.white.opacity(0.022))
                        .frame(height: 1)
                }
            }
            .padding(.vertical, 6)

            // 前面板暗带：底部加深，暗示机身从水平顶面转折到竖直前面板。
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.30)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 104)
            }
        }
    }

    /// 嵌入木面的复古数显屏（VFD/LED 风格）：深色暖底 + 琥珀发光字 + 扫描线 + 黄铜凸框。
    /// 暖色家族与木质机身协调，整体像老式电子时钟/收音机的数显窗口，而非割裂的蓝屏。
    private var displayScreen: some View {
        infoSection
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                let profile = playback.currentStation?.spectrumProfile ?? (energy: 0.72, tempo: 0.95)
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    PlayerTheme.displayPanelTop,
                                    PlayerTheme.displayPanelBottom
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    // 动态频谱层：位于背景渐变之上、文字之下，按风格律动且不挡内容。
                    SpectrumVisualizerBackground(
                        isPlaying: playback.isPlaying,
                        energy: profile.energy,
                        tempo: profile.tempo
                    )
                    .padding(.horizontal, 6)
                    .padding(.bottom, 5)
                    .padding(.top, 14)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
            // 极淡的水平扫描线，强化电子数显的屏幕质感。
            .overlay {
                displayScanlines
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .allowsHitTesting(false)
            }
            // 屏幕整体一层琥珀辉光，像点亮的荧光数显。
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [PlayerTheme.displayGlow.opacity(0.12), .clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: 90
                        )
                    )
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                // 玻璃面顶部反光。
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.06), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .padding(1)
            }
            // 凹陷内投影：顶部内壁被口沿挡光更暗，制造下陷纵深。
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.6), lineWidth: 3)
                    .blur(radius: 3)
                    .offset(y: 1.5)
                    .mask(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            // 黄铜凸起外框，把屏幕和木面清晰分隔，呼应机身上的金属件。
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                PlayerTheme.brassLight.opacity(0.7),
                                PlayerTheme.brassDark.opacity(0.6)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.2
                    )
            }
    }

    /// 数显屏的水平扫描线层：等距细暗线，模拟 CRT/VFD 行栅。
    private var displayScanlines: some View {
        GeometryReader { proxy in
            let lineGap: CGFloat = 3
            let count = Int(proxy.size.height / lineGap)
            VStack(spacing: lineGap - 1) {
                ForEach(0..<max(count, 1), id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.18))
                        .frame(height: 1)
                }
            }
        }
    }

    /// 前面板控件区：顶部蚀刻接缝 + 音量调谐行 + 传输三键行，直接坐落在木质机身上。
    private var controlStrip: some View {
        VStack(spacing: 8) {
            consoleSeam
            volumeDeckRow
            transportDeckRow
        }
    }

    /// 木面折边：顶面与前面板交界的转折棱。
    /// 折边棱被顶光照亮（木色高光线），紧接其下的前面板背光转暗（阴影线），
    /// 形成"顶面水平、前面板竖直"的折角纵深，而非一条平铺的分割线。
    private var consoleSeam: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(PlayerTheme.cabinetEdgeHighlight.opacity(0.5))
                .frame(height: 1)
            Rectangle()
                .fill(.black.opacity(0.45))
                .frame(height: 1.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 2)
    }

    /// 顶部工具栏：左 macOS 风格红绿灯位（关闭+最小化），右侧只保留频道列表入口。
    private var topBar: some View {
        HStack(spacing: AppConstants.UserInterface.smallSpacing) {
            TrafficLightControls(
                closeAccessibilityLabel: closeButtonAccessibilityLabel,
                onClose: {
                    mainWindowCoordinator.hideMainWindow()
                },
                onMinimize: { hostWindow?.miniaturize(nil) }
            )

            Spacer()

            CompactIconButton(
                systemName: "list.bullet",
                accessibilityLabel: LocalizedStrings.text("main.channel_list")
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isShowingStationOverlay.toggle()
                }
            }
        }
    }

    private var closeButtonAccessibilityLabel: String {
        LocalizedStrings.text("main.hide_to_menu_bar")
    }

    /// 显示屏内的信息内容（数显风格）：所有频道信息都限制为单行，避免长名称/多标签撑高屏幕。
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            displayStatusRow

            MarqueeText(
                text: playback.currentStation?.name ?? LocalizedStrings.text("main.no_station"),
                font: .system(size: 15, weight: .semibold, design: .monospaced),
                color: PlayerTheme.displayAmber,
                height: 19,
                speed: 22,
                shadowColor: PlayerTheme.displayGlow.opacity(0.7),
                shadowRadius: 4
            )
                .frame(maxWidth: .infinity, alignment: .leading)

            MarqueeText(
                text: currentStationSubtitle,
                font: .system(size: 10, design: .monospaced),
                color: PlayerTheme.displayAmberDim.opacity(0.9),
                height: 13,
                speed: 18,
                startDelay: 1.2,
                shadowColor: PlayerTheme.displayGlow.opacity(0.4),
                shadowRadius: 2
            )
                .frame(maxWidth: .infinity, alignment: .leading)

            tagSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 屏幕顶部状态行：左侧闪烁指示灯 + 状态字，右侧"检测时延 · 流类型徽标"，
    /// 像电子时钟顶部的状态指示，强化数显实物感。
    private var displayStatusRow: some View {
        HStack(spacing: 5) {
            // 播放时常亮、暂停时熄灭的琥珀指示灯。
            Circle()
                .fill(playback.isPlaying ? PlayerTheme.displayAmber : PlayerTheme.displayAmberDim.opacity(0.35))
                .frame(width: 5, height: 5)
                .shadow(
                    color: playback.isPlaying ? PlayerTheme.displayGlow.opacity(0.9) : .clear,
                    radius: 3
                )

            Text(displayStatusText)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(PlayerTheme.displayAmberDim.opacity(0.95))
                .lineLimit(1)

            Spacer(minLength: 0)

            // 最近一次可用性检测的响应时延（毫秒），让用户在屏上直接感知线路质量。
            if let latencyText = currentStationLatencyText {
                Text(latencyText)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(PlayerTheme.displayAmberDim.opacity(0.8))
                    .lineLimit(1)
                Text("·")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(PlayerTheme.displayAmberDim.opacity(0.45))
            }

            if let station = playback.currentStation {
                Text(station.type.streamBadge)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(PlayerTheme.displayAmberDim.opacity(0.7))
                    .lineLimit(1)
            }

        }
    }

    /// 前面板收藏键：使用通用星标识别，视觉与播放/切台圆键保持同一类控件。
    @ViewBuilder
    private var favoritePresetKey: some View {
        if let station = playback.currentStation {
            let isFavorite = repository.isFavorite(stationId: station.id)
            PhysicalRoundButton(
                systemName: isFavorite ? "star.fill" : "star",
                accessibilityLabel: isFavorite ? LocalizedStrings.text("main.favorite.remove") : LocalizedStrings.text("main.favorite.add"),
                diameter: 26,
                isHighlighted: isFavorite,
                indicatorColor: isFavorite ? PlayerTheme.warmText : nil
            ) {
                repository.toggleFavorite(stationId: station.id)
            }
            .help(isFavorite ? LocalizedStrings.text("main.favorite.remove") : LocalizedStrings.text("main.favorite.add"))
        }
    }

    /// 标签区：主显示屏空间有限，只做单行摘要；完整标签留给频道列表和频道管理展示。
    @ViewBuilder
    private var tagSection: some View {
        if let summary = currentStationTagSummary {
            displayTagChip(summary)
        }
    }

    /// 数显屏内的标签小胶囊：琥珀描边 + 暗琥珀字，与屏幕发光字统一，区别于覆盖层里的 TagPill。
    private func displayTagChip(_ text: String) -> some View {
        MarqueeText(
            text: text,
            font: .system(size: 9, weight: .semibold, design: .monospaced),
            color: PlayerTheme.displayAmberDim,
            height: 12,
            speed: 18,
            startDelay: 1.4
        )
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Capsule().fill(PlayerTheme.displayGlow.opacity(0.10))
            )
            .overlay(
                Capsule().stroke(PlayerTheme.displayAmberDim.opacity(0.5), lineWidth: 0.6)
            )
    }

    private var volumeDeckRow: some View {
        HStack(spacing: 8) {
            Image(systemName: volumeIconName)
                .font(.system(size: 10))
                .foregroundStyle(PlayerTheme.brassLight.opacity(0.85))
                .frame(width: 16)

            BrassVolumeSlider(
                value: Binding(
                    get: { Double(playback.volume) },
                    set: { playback.updateVolume(Float($0)) }
                )
            )

            // 右侧由数字读数改为一键静音/取消静音；当前音量直观地由滑杆位置与左侧喇叭图标体现。
            MuteToggleButton(isMuted: isMuted) {
                toggleMute()
            }
            .keyboardShortcut("m", modifiers: [.command])
            .help(isMuted ? LocalizedStrings.text("main.unmute") : LocalizedStrings.text("main.mute"))
        }
    }

    private var transportDeckRow: some View {
        HStack(spacing: 10) {
            focusChip

            Spacer()

            HStack(spacing: 9) {
                favoritePresetKey

                TransportButton(
                    systemName: "backward.fill",
                    accessibilityLabel: LocalizedStrings.text("main.previous_station"),
                    diameter: 26
                ) {
                    playPrevious()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])

                PlayDeckButton(
                    isPlaying: playback.isPlaying,
                    diameter: 34
                ) {
                    playback.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])

                TransportButton(
                    systemName: "forward.fill",
                    accessibilityLabel: LocalizedStrings.text("main.next_station"),
                    diameter: 26
                ) {
                    playNext()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])

                TransportButton(
                    systemName: "shuffle",
                    accessibilityLabel: LocalizedStrings.text("main.random_available"),
                    diameter: 26
                ) {
                    playRandomAvailable()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .help(LocalizedStrings.text("main.random_available_help"))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .controlGroupChrome()
        }
    }

    /// 专注计时胶囊：点击即把当前专注分钟数清零、重新计时，
    /// 配合"播放时累计"形成一个可反复开始的番茄钟式专注计时。
    private var focusChip: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                focusTimeService.resetTodayFocus()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(PlayerTheme.brassLight.opacity(isFocusChipHovering ? 1 : 0.85))
                Text(focusMinutesDisplayText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(PlayerTheme.creamTrack.opacity(0.85))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(width: 42, alignment: .leading)
                // 悬停时浮现"重置"图标，提示该胶囊可点按重新计时。
                if isFocusChipHovering {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(PlayerTheme.brassLight)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(.black.opacity(isFocusChipHovering ? 0.30 : 0.22))
            )
            .overlay(
                Capsule().stroke(PlayerTheme.brassDark.opacity(isFocusChipHovering ? 0.6 : 0.35), lineWidth: 0.6)
            )
        }
        .frame(width: 82, alignment: .leading)
        .buttonStyle(.plain)
        .accessibilityLabel(LocalizedStrings.text("main.focus.accessibility", focusTimeService.todayFocusMinutes))
        .help(LocalizedStrings.text("main.focus.help"))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isFocusChipHovering = hovering
            }
        }
        .pointingHandCursor()
    }

    private var focusMinutesDisplayText: String {
        let minutes = focusTimeService.todayFocusMinutes
        if minutes < 60 {
            return LocalizedStrings.text("main.focus.minutes_short", minutes)
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours < 10 {
            return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h\(remainingMinutes)m"
        }
        return "\(hours)h+"
    }

    /// 当前频道最近一次可用性检测的响应时延文案（如 "234ms"）。
    /// 从仓库取最新 health（而非播放时的 Station 快照），保证检测后能即时刷新；
    /// 未检测过（unknown）或无耗时数据时返回 nil，状态行不显示该段。
    private var currentStationLatencyText: String? {
        guard let health = repository.station(matching: playback.currentStation?.id)?.lastHealth,
              health.status != .unknown,
              let milliseconds = health.responseTimeMilliseconds else {
            return nil
        }
        return "\(milliseconds)ms"
    }

    /// 当前是否处于静音（音量为 0）。
    private var isMuted: Bool {
        playback.volume <= 0.001
    }

    /// 一键静音 / 取消静音：
    /// - 当前有声 → 记下音量再置 0；
    /// - 当前静音 → 恢复到记录的音量（若记录值过小则回退到默认音量，避免恢复后仍听不到）。
    private func toggleMute() {
        if isMuted {
            let restored = volumeBeforeMute > 0.01 ? volumeBeforeMute : AppConstants.Playback.defaultVolume
            playback.updateVolume(restored)
        } else {
            volumeBeforeMute = playback.volume
            playback.updateVolume(0)
        }
    }

    /// 音量喇叭图标随音量档位变化：静音 / 低 / 中 / 高，给出直观反馈。
    private var volumeIconName: String {
        let volume = playback.volume
        if volume <= 0.001 { return "speaker.slash.fill" }
        if volume < 0.4 { return "speaker.wave.1.fill" }
        if volume < 0.75 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func playNext() {
        let stations = repository.stations
        playback.playNext(in: stations)
        if let nextStation = playback.currentStation {
            appSettings.updateLastStationIdentifier(nextStation.id)
        }
    }

    private func playPrevious() {
        let stations = repository.stations
        playback.playPrevious(in: stations)
        if let nextStation = playback.currentStation {
            appSettings.updateLastStationIdentifier(nextStation.id)
        }
    }

    /// 随机播放一个"当前检测顺畅"的频道；如果用户有收藏，优先从收藏里随机。
    /// 优先级回退，保证按钮在任何检测状态下都可用：
    /// 1. 最近一次可用性检测为 `.available` 的频道（首选）；
    /// 2. 没有可用记录时，放宽到 `.available` + `.unstable`（勉强能放的）；
    /// 3. 仍为空（例如从未检测过）时，回退到全部可见频道。
    /// 每一级都尽量排除当前正在播放的频道，避免"随机"到原地不动；
    /// 若排除后候选为空（候选仅剩当前台），则允许包含当前台。
    private func playRandomAvailable() {
        let allVisible = repository.stations
        guard !allVisible.isEmpty else { return }

        let available = allVisible.filter { $0.lastHealth?.status == .available }
        let playable = allVisible.filter {
            $0.lastHealth?.status == .available || $0.lastHealth?.status == .unstable
        }
        let favoriteAvailable = available.filter { repository.isFavorite(stationId: $0.id) }
        let favoritePlayable = playable.filter { repository.isFavorite(stationId: $0.id) }
        let favoriteAny = allVisible.filter { repository.isFavorite(stationId: $0.id) }

        let candidatePool: [Station]
        if !favoriteAvailable.isEmpty {
            candidatePool = favoriteAvailable
        } else if !favoritePlayable.isEmpty {
            candidatePool = favoritePlayable
        } else if !available.isEmpty {
            candidatePool = available
        } else if !playable.isEmpty {
            candidatePool = playable
        } else if !favoriteAny.isEmpty {
            candidatePool = favoriteAny
        } else {
            candidatePool = allVisible
        }

        let currentId = playback.currentStation?.id
        let withoutCurrent = candidatePool.filter { $0.id != currentId }
        let finalPool = withoutCurrent.isEmpty ? candidatePool : withoutCurrent

        guard let pick = finalPool.randomElement() else { return }
        playAndRemember(pick)
    }

    /// 当前盘面主题。对持久化的序号做范围保护，避免预设增减后越界。
    private var currentVinylFace: VinylFace {
        let presets = VinylFace.presets
        let safeIndex = min(max(vinylFaceIndex, 0), presets.count - 1)
        return presets[safeIndex]
    }

    private var currentPlaybackAuraStyle: PlaybackAuraStyle {
        let allStyles = PlaybackAuraStyle.allCases
        guard !allStyles.isEmpty else { return .notes }
        let safeIndex = min(max(playbackAuraIndex, 0), allStyles.count - 1)
        return allStyles[safeIndex]
    }

    /// 循环切换到下一款盘面；VinylRecordView 监听 face 变化会自动演一次换片动画。
    private func cycleVinylFace() {
        let count = VinylFace.presets.count
        guard count > 0 else { return }
        let safeIndex = min(max(vinylFaceIndex, 0), count - 1)
        vinylFaceIndex = (safeIndex + 1) % count
        randomizePlaybackAura(for: playback.currentStation)
    }

    /// 切换频道时随机换一张不同盘面；如果只有一张预设，则保持当前盘面不变。
    private func randomizeVinylFace() {
        let count = VinylFace.presets.count
        guard count > 1 else { return }
        let safeIndex = min(max(vinylFaceIndex, 0), count - 1)
        let candidates = Array(0..<count).filter { $0 != safeIndex }
        if let nextIndex = candidates.randomElement() {
            vinylFaceIndex = nextIndex
        }
    }

    /// 切换频道或手动换盘时随机一个不同的播放氛围，与盘面独立组合。
    private func randomizePlaybackAura(for station: Station?) {
        let count = PlaybackAuraStyle.allCases.count
        guard count > 1 else { return }
        let safeIndex = min(max(playbackAuraIndex, 0), count - 1)
        let preferredStyles = preferredAuraStyles(for: station)
        let weightedIndexes = (
            preferredStyles.map(\.rawValue)
            + PlaybackAuraStyle.allCases.map(\.rawValue)
        )
        let candidates = weightedIndexes.filter { $0 != safeIndex }
        if let nextIndex = candidates.randomElement() {
            playbackAuraIndex = nextIndex
        }
    }

    private func preferredAuraStyles(for station: Station?) -> [PlaybackAuraStyle] {
        guard let station else { return [] }
        let haystack = ([station.name, station.category] + station.effectiveTags)
            .joined(separator: " ")
            .lowercased()

        if matches(haystack, ["rain", "sleep", "calm", "ambient", "relax", "雨", "睡", "助眠", "舒缓", "放松"]) {
            return [.bubbles, .fireflies, .waveRings]
        }
        if matches(haystack, ["jazz", "groove", "cafe", "café", "piano", "爵士", "咖啡", "钢琴", "律动"]) {
            return [.sparkles, .notes, .fireflies]
        }
        if matches(haystack, ["beat", "beats", "dance", "edm", "electronic", "game", "节拍", "电子", "游戏", "动感"]) {
            return [.comets, .waveRings, .sparkles]
        }
        return []
    }

    private func matches(_ haystack: String, _ keywords: [String]) -> Bool {
        keywords.contains { haystack.contains($0) }
    }

    private var displayStatusText: String {
        if isShowingLoadingTape { return "LOADING TAPE" }
        return playback.isPlaying ? "ON AIR" : "PAUSED"
    }

    private func showLoadingTapeCue() {
        loadingTapeTask?.cancel()
        isShowingLoadingTape = true
        loadingTapeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            isShowingLoadingTape = false
        }
    }

    /// 次级信息：分类 + 协议类型。scene/style 等已下沉到标签区展示，这里不再重复。
    private var currentStationSubtitle: String {
        guard let station = playback.currentStation else {
            return LocalizedStrings.text("main.select_station_hint")
        }
        let category = station.category.isEmpty ? nil : station.category
        let parts = [category, station.type.displayName].compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    private var currentStationTagSummary: String? {
        guard let station = playback.currentStation else { return nil }
        let tags = station.effectiveTags
        guard !tags.isEmpty else { return nil }
        return tags.joined(separator: " / ")
    }

    private func restoreInitialPlaybackStateIfNeeded() {
        guard !hasRestoredInitialPlaybackState else { return }
        hasRestoredInitialPlaybackState = true

        playback.updateVolume(appSettings.preferredVolume)
        if playback.currentStation == nil {
            let stationToRestore = repository.station(matching: appSettings.lastStationIdentifier)
                ?? repository.stations.first
            if let stationToRestore {
                suppressNextVinylFaceRandomization = true
                playAndRemember(stationToRestore)
            }
        }
    }

    private func playAndRemember(_ station: Station) {
        playback.play(station)
        appSettings.updateLastStationIdentifier(station.id)
    }
}

/// 单行数显跑马灯：内容能放下时静止显示，超出容器宽度时才横向循环滚动。
private struct MarqueeText: View {
    var text: String
    var font: Font
    var color: Color
    var height: CGFloat
    var speed: CGFloat = 22
    var startDelay: TimeInterval = 1.0
    var gap: CGFloat = 28
    var shadowColor: Color = .clear
    var shadowRadius: CGFloat = 0

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var scrollToken = UUID()

    private var shouldScroll: Bool {
        textWidth > containerWidth + 1
    }

    private var scrollDistance: CGFloat {
        textWidth + gap
    }

    private var scrollDuration: TimeInterval {
        max(TimeInterval(scrollDistance / max(speed, 1)), 4.5)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                if shouldScroll {
                    HStack(spacing: gap) {
                        label.fixedSize(horizontal: true, vertical: false)
                        label.fixedSize(horizontal: true, vertical: false)
                    }
                    .offset(x: offset)
                } else {
                    label
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                label
                    .fixedSize(horizontal: true, vertical: false)
                    .background {
                        GeometryReader { textProxy in
                            Color.clear.preference(
                                key: MarqueeTextWidthKey.self,
                                value: textProxy.size.width
                            )
                        }
                    }
                    .hidden()
            }
            .frame(width: proxy.size.width, height: height, alignment: .leading)
            .clipped()
            .onAppear {
                containerWidth = proxy.size.width
                restartIfNeeded()
            }
            .onChange(of: proxy.size.width) { _, newWidth in
                containerWidth = newWidth
                restartIfNeeded()
            }
            .onPreferenceChange(MarqueeTextWidthKey.self) { newWidth in
                textWidth = newWidth
                restartIfNeeded()
            }
            .onChange(of: text) { _, _ in
                restartIfNeeded()
            }
        }
        .frame(height: height)
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: 0)
    }

    private func restartIfNeeded() {
        let token = UUID()
        scrollToken = token
        offset = 0

        guard shouldScroll else { return }
        let distance = scrollDistance
        let duration = scrollDuration

        DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
            guard scrollToken == token, shouldScroll else { return }
            offset = 0
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                offset = -distance
            }
        }
    }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 通用紧凑圆形图标按钮，用于顶部右侧功能区（频道列表）；
/// 显式悬停反馈以避免“点不中”错觉。
struct CompactIconButton: View {
    var systemName: String
    var accessibilityLabel: String
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isHovering ? PlayerTheme.brassLight : PlayerTheme.creamTrack.opacity(0.85))
                .frame(width: 22, height: 22)
                // 嵌在木面上的小黄铜按钮：顶亮底暗的金属盘面 + 黄铜环 + 落影，呼应机身金属件。
                .background(
                    Circle().fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(isHovering ? 0.16 : 0.10),
                                Color.black.opacity(0.32)
                            ],
                            center: .top,
                            startRadius: 1,
                            endRadius: 22
                        )
                    )
                )
                .overlay {
                    Circle().stroke(PlayerTheme.brassDark.opacity(isHovering ? 0.9 : 0.6), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.4), radius: 1.5, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
        .onHover { hovering in
            isHovering = hovering
        }
        .pointingHandCursor()
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}

/// macOS 风格的窗口控制红绿灯组（关闭 + 最小化）。
/// 与系统一致：默认只显示彩色圆点，鼠标悬停在整组上时才统一浮现 ×/− 符号。
private struct TrafficLightControls: View {
    var closeAccessibilityLabel: String
    var onClose: () -> Void
    var onMinimize: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: PlayerTheme.trafficButtonSpacing) {
            TrafficLightButton(
                fillColor: PlayerTheme.trafficCloseFill,
                borderColor: PlayerTheme.trafficCloseBorder,
                glyph: "xmark",
                accessibilityLabel: closeAccessibilityLabel,
                showsGlyph: isHovering,
                action: onClose
            )

            TrafficLightButton(
                fillColor: PlayerTheme.trafficMinimizeFill,
                borderColor: PlayerTheme.trafficMinimizeBorder,
                glyph: "minus",
                accessibilityLabel: LocalizedStrings.text("main.minimize_window"),
                showsGlyph: isHovering,
                action: onMinimize
            )
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .pointingHandCursor()
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}

/// 单个 macOS 风格红绿灯按钮：实心彩色圆点 + 同色系暗描边 + 顶部柔光高光。
/// 符号只在 `showsGlyph` 为真（整组悬停）时显示，未悬停时是纯色圆点。
private struct TrafficLightButton: View {
    var fillColor: Color
    var borderColor: Color
    var glyph: String
    var accessibilityLabel: String
    var showsGlyph: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .overlay {
                        Circle().stroke(borderColor, lineWidth: 0.5)
                    }
                    .overlay(alignment: .top) {
                        // 顶部一抹柔光，模拟系统红绿灯的玻璃质感。
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.45), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .padding(0.5)
                    }

                Image(systemName: glyph)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(PlayerTheme.trafficGlyph)
                    .opacity(showsGlyph ? 1 : 0)
            }
            .frame(
                width: PlayerTheme.trafficButtonDiameter,
                height: PlayerTheme.trafficButtonDiameter
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}

/// 数显屏背景的动态频谱可视化层。
///
/// 实现说明：当前播放走远程 HLS / AVPlayer，未接入实时音频 FFT，
/// 因此按"音乐风格（energy/tempo）+ 播放状态"程序化模拟频谱：
/// 每根条用一组随机化的频率 / 相位参数叠加，使各条互不同步、律动不规律更自然；
/// 起停时以淡入 / 淡出包络平滑过渡，并用垂直遮罩让上半部几乎无频谱、保护文字可读性。
struct SpectrumVisualizerBackground: View {
    /// 是否正在播放：决定频谱是律动还是落回基线。
    let isPlaying: Bool
    /// 能量：整体幅度系数（越大越高）。
    let energy: Double
    /// 节奏：律动速度系数（越大越快）。
    let tempo: Double

    /// 频谱条数量。
    private let barCount = 26
    /// 起停包络过渡时长（秒）。
    private let envelopeDuration: TimeInterval = 0.8
    /// 每根条的随机律动参数，初始化时用固定种子生成，保证稳定不抖动。
    private let barSeeds: [SpectrumBarSeed]

    /// 播放状态切换的时间锚点，用于计算淡入 / 淡出包络，避免频谱条突变。
    @State private var envelopeAnchor = Date()

    init(isPlaying: Bool, energy: Double, tempo: Double) {
        self.isPlaying = isPlaying
        self.energy = energy
        self.tempo = tempo
        var generator = SpectrumRandom(seed: 0x5EED_1234)
        self.barSeeds = (0..<barCount).map { _ in SpectrumBarSeed(using: &generator) }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: isPlaying ? 1.0 / 30.0 : 1.0 / 8.0)) { timeline in
            Canvas { context, size in
                drawBars(in: &context, size: size, now: timeline.date)
            }
            // 垂直遮罩：上半部几乎透明、底部最明显，让频谱像从屏底升起，
            // 不与上方的频道名 / 副标题争抢，保证文字清晰。
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.35), location: 0.5),
                        .init(color: .black, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .allowsHitTesting(false)
        .onChange(of: isPlaying) { _, _ in
            envelopeAnchor = Date()
        }
    }

    private func drawBars(in context: inout GraphicsContext, size: CGSize, now: Date) {
        guard size.width > 0, size.height > 0 else { return }

        let time = now.timeIntervalSinceReferenceDate
        // 起停包络：播放后 0→1 渐显，暂停后 1→0 渐隐。
        let ramp = min(1.0, now.timeIntervalSince(envelopeAnchor) / envelopeDuration)
        let envelope = isPlaying ? ramp : (1.0 - ramp)
        guard envelope > 0.001 else { return }

        let gap: CGFloat = 2
        let totalGap = gap * CGFloat(barCount - 1)
        let barWidth = max(1, (size.width - totalGap) / CGFloat(barCount))
        let baseline: CGFloat = 2
        let maxBarHeight = size.height * 0.55

        for index in 0..<barCount {
            let seed = barSeeds[index]
            // 每根条用各自随机的频率 / 相位组合，彼此不同步，整体律动不规律。
            let wave1 = sin(time * seed.frequencyA * tempo + seed.phaseA)
            let wave2 = sin(time * seed.frequencyB * tempo + seed.phaseB)
            let wave3 = sin(time * seed.frequencyC * tempo + seed.phaseC)
            var mixed = (wave1 * 0.5 + wave2 * 0.3 + wave3 * 0.2) * 0.5 + 0.5
            // 提高对比，制造偶发尖峰，让跳动更像真实频谱而非匀速正弦。
            mixed = pow(mixed, 1.6)

            // 两侧低、中间高，模拟真实频谱中频段更活跃。
            let distanceFromCenter = abs(Double(index) - Double(barCount - 1) / 2.0)
            let centerWeight = 1.0 - distanceFromCenter / (Double(barCount) / 2.0)
            let centerBoost = 0.55 + 0.45 * centerWeight

            let dynamic = mixed * centerBoost * energy * envelope * seed.heightScale
            let barHeight = baseline + CGFloat(dynamic) * maxBarHeight

            let x = CGFloat(index) * (barWidth + gap)
            let rect = CGRect(x: x, y: size.height - barHeight, width: barWidth, height: barHeight)
            let bar = Path(roundedRect: rect, cornerRadius: barWidth / 2)

            context.fill(
                bar,
                with: .linearGradient(
                    Gradient(colors: [
                        PlayerTheme.displayAmber.opacity(0.26),
                        PlayerTheme.displayAmberDim.opacity(0.05)
                    ]),
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                )
            )
        }
    }
}

/// 单根频谱条的随机律动参数：三组频率 / 相位 + 固有高度系数。
private struct SpectrumBarSeed {
    let frequencyA: Double
    let frequencyB: Double
    let frequencyC: Double
    let phaseA: Double
    let phaseB: Double
    let phaseC: Double
    let heightScale: Double

    init(using generator: inout SpectrumRandom) {
        frequencyA = 1.4 + generator.nextUnit() * 2.4
        frequencyB = 0.5 + generator.nextUnit() * 1.3
        frequencyC = 2.6 + generator.nextUnit() * 3.4
        phaseA = generator.nextUnit() * (.pi * 2)
        phaseB = generator.nextUnit() * (.pi * 2)
        phaseC = generator.nextUnit() * (.pi * 2)
        heightScale = 0.5 + generator.nextUnit() * 0.5
    }
}

/// 确定性伪随机发生器（LCG），保证每次启动生成的频谱参数稳定一致、不会闪跳。
private struct SpectrumRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextUnit() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 33) / Double(UInt64(1) << 31)
    }
}

private extension View {
    func controlGroupChrome() -> some View {
        self
            .background(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.20),
                        Color.white.opacity(0.04)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(PlayerTheme.brassDark.opacity(0.28), lineWidth: 0.6)
            }
            .shadow(color: .black.opacity(0.16), radius: 1.5, x: 0, y: 1)
    }
}
