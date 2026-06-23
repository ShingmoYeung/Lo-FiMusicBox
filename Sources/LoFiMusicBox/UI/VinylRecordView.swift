import SwiftUI

/// 唱片盘面主题：决定中央贴标的配色与印字。
/// 用户可通过"换盘面"按钮在多款之间循环切换——纯视觉 / 情绪化功能，不影响播放。
struct VinylFace: Identifiable, Equatable {
    let id: Int
    /// 贴标主印字（大字）。
    let title: String
    /// 贴标次印字（小字）。
    let subtitle: String
    /// 贴标圆面的渐变配色（由亮到暗）。
    let labelColors: [Color]
    let titleColor: Color
    let subtitleColor: Color

    /// 换盘按钮上"迷你碟片"中心点的代表色（取贴标主色）。
    var swatch: Color {
        labelColors.first ?? Color(red: 168 / 255, green: 138 / 255, blue: 96 / 255)
    }

    /// 奶白印字色（多数盘面通用，深色底上清晰）。
    private static let cream = Color(red: 245 / 255, green: 238 / 255, blue: 222 / 255)
    /// 香槟金印字色（黑金盘面专用）。
    private static let gold = Color(red: 214 / 255, green: 176 / 255, blue: 112 / 255)

    /// 内置盘面清单。顺序即"换盘"循环顺序。
    static let presets: [VinylFace] = [
        VinylFace(
            id: 0, title: "MUSIC", subtitle: "BOX",
            labelColors: [
                Color(red: 168 / 255, green: 138 / 255, blue: 96 / 255),
                Color(red: 128 / 255, green: 100 / 255, blue: 68 / 255),
                Color(red: 86 / 255, green: 64 / 255, blue: 42 / 255)
            ],
            titleColor: cream.opacity(0.95), subtitleColor: cream.opacity(0.7)
        ),
        VinylFace(
            id: 1, title: "NIGHT", subtitle: "WAVE",
            labelColors: [
                Color(red: 74 / 255, green: 100 / 255, blue: 154 / 255),
                Color(red: 44 / 255, green: 64 / 255, blue: 112 / 255),
                Color(red: 24 / 255, green: 34 / 255, blue: 70 / 255)
            ],
            titleColor: cream.opacity(0.95), subtitleColor: cream.opacity(0.7)
        ),
        VinylFace(
            id: 2, title: "RUBY", subtitle: "BEAT",
            labelColors: [
                Color(red: 178 / 255, green: 74 / 255, blue: 68 / 255),
                Color(red: 136 / 255, green: 46 / 255, blue: 46 / 255),
                Color(red: 92 / 255, green: 28 / 255, blue: 28 / 255)
            ],
            titleColor: cream.opacity(0.95), subtitleColor: cream.opacity(0.7)
        ),
        VinylFace(
            id: 3, title: "FERN", subtitle: "TAPE",
            labelColors: [
                Color(red: 106 / 255, green: 130 / 255, blue: 74 / 255),
                Color(red: 72 / 255, green: 96 / 255, blue: 50 / 255),
                Color(red: 46 / 255, green: 64 / 255, blue: 32 / 255)
            ],
            titleColor: cream.opacity(0.95), subtitleColor: cream.opacity(0.7)
        ),
        VinylFace(
            id: 4, title: "ROSÉ", subtitle: "GROOVE",
            labelColors: [
                Color(red: 200 / 255, green: 152 / 255, blue: 122 / 255),
                Color(red: 170 / 255, green: 116 / 255, blue: 92 / 255),
                Color(red: 120 / 255, green: 78 / 255, blue: 60 / 255)
            ],
            titleColor: cream.opacity(0.95), subtitleColor: cream.opacity(0.72)
        ),
        VinylFace(
            id: 5, title: "GOLD", subtitle: "DISC",
            labelColors: [
                Color(red: 58 / 255, green: 56 / 255, blue: 52 / 255),
                Color(red: 38 / 255, green: 36 / 255, blue: 32 / 255),
                Color(red: 20 / 255, green: 18 / 255, blue: 16 / 255)
            ],
            titleColor: gold, subtitleColor: gold.opacity(0.7)
        )
    ]
}

/// 立体唱机视图。整个机身由四部分组成，全部约束在固定 frame 内不会越界遮挡右侧文字：
/// - **木箱底座**：圆角矩形 + 木纹渐变 + 内阴影 + 顶面高光，作为机身整体外壳；
/// - **黑胶唱片**：底座左侧凹陷处的旋转盘面，含凹槽、贴标、转轴；
/// - **唱针组件**：底座右上角枢轴 + 金属臂 + 暖色针头。
///   - **播放（isPlaying = true）**：stem 顺时针 +35° 旋转，针头落到唱片中段沟槽区（外圈与中心 label 之间）；
///   - **暂停（isPlaying = false）**：stem 完全垂直向下（0°），针头笔直立在底座上、紧贴唱片右沿外的"支架位"；
///   - **切台（stationToken 变化）**：先回到 `0°`（与暂停态相同的笔直支架位）
///     模拟"取下旧片"，悬停约 0.5s 后再落回 `+35°` 完成"放上新片"，
///     整段由 spring 动画衔接。摆幅克制——stem 不会越过中性位置往右甩，
///     视觉上像是"被人轻轻提起放回支架，再放到新唱片"，符合换片的物理直觉。
/// - **桌面阴影 + 3D 透视**：让机身看起来真的"放在"桌上。
///
/// 取消了之前唱片中央的播放/暂停图标——现在 **整个唱机都是一个按钮**，鼠标悬停在机身任意位置都会变手指光标，点击切换播放/暂停。
struct VinylRecordView: View {
    var isPlaying: Bool
    /// 当前频道的稳定标识。用于驱动"切台抬针—换片—落针"的动画：
    /// SwiftUI 的 `.onChange(of:)` 监听该值的变化，每次切换频道都会触发一次完整起落。
    /// 传 `nil` 表示尚未选台（默认会按 `isPlaying` 静态摆位，不做切片动画）。
    var stationToken: String?
    /// 嵌入式模式：为 `true` 时不绘制唱机自己的木箱外壳与桌面投影，
    /// 只保留"唱盘井 + 黑胶 + 唱针"，让唱盘像是直接嵌在外层一体化木质机身的顶面上。
    /// 唱盘井/唱针的几何坐标完全不变，因此换片动画行为与独立模式一致。
    var embedded: Bool = false
    /// 当前唱片盘面主题：决定中央贴标的配色与印字。切换它会触发一次"换片"抬针-落针动画。
    var face: VinylFace = VinylFace.presets[0]
    /// 播放时的氛围动效，与盘面独立选择，避免形成固定搭配。
    var auraStyle: PlaybackAuraStyle = .notes
    var auraIntensity: PlaybackAuraIntensity = .balanced
    var action: () -> Void

    @State private var isHovering = false
    /// 切台动画状态：为 `true` 时强制 stem 抬起到 `-30°`，覆盖 isPlaying 的默认摆位。
    @State private var isSwappingStation = false
    /// 当前正在执行的切台动画 Task；连续切台时通过 cancel 旧 task 防止竞争把
    /// `isSwappingStation` 提前重置为 false，确保最后一次切台后 stem 才落回。
    @State private var swapAnimationTask: Task<Void, Never>?
    /// 手动换盘面只做轻量视觉反馈，不移动唱针，避免和暂停/切台语义混淆。
    @State private var faceChangeTick = 0
    @State private var faceChangeResetTask: Task<Void, Never>?

    private let cabinetWidth: CGFloat = 132
    private let cabinetHeight: CGFloat = 112
    private let vinylDiameter: CGFloat = 90

    /// 嵌入式唱盘的俯视后倾角度（绕 X 轴）。给唱盘一点透视体量感，像实物斜摆在桌上。
    /// 数值越大越"躺平"。配合较大的 perspective 值（畸变更柔和），让唱针在倾斜盘面上
    /// 的轻微跟随显得自然，而非平面里却偏右的违和感。
    private let embeddedTiltDegrees: Double = 12

    /// 切换频道时唱针抬起后的悬停时长（秒），略大于 spring 抬起时间，
    /// 让用户清晰感受到"换片"那段静止瞬间。
    private let stationSwapHoldSeconds: Double = 0.5
    /// 唱臂停在支架上时略向唱盘内侧收一点，避免竖直停放时靠右侧换盘盒太近。
    private let tonearmRestAngle: Double = 8
    private let tonearmPlayAngle: Double = 35

    /// 唱片在底座坐标系中的圆心位置（左偏，给唱针留位置）。
    private var vinylCenter: CGPoint {
        CGPoint(x: 50, y: cabinetHeight / 2)
    }

    /// 唱针枢轴在底座坐标系中的位置（右上角）。
    private var tonearmPivot: CGPoint {
        CGPoint(x: cabinetWidth - 18, y: 16)
    }

    var body: some View {
        ZStack {
            // 独立模式才画桌面投影；嵌入到一体化机身时不需要（机身自带阴影层次）。
            if !embedded {
                tableShadow
            }

            // 整个唱机机身作为单一按钮区域。
            ZStack(alignment: .topLeading) {
                // 嵌入模式不画自己的木箱外壳，避免"木盒套在木机身上"的割裂感；
                // 唱盘井及以上图层照常绘制，相当于唱盘直接嵌在外层机身顶面。
                if !embedded {
                    woodCabinet
                }
                // 唱盘组（井 + 黑胶）：只对这一组施加俯视后倾透视，营造实物体量感。
                // 唱针刻意不在此组内 —— 透视会把偏右的竖线斜掉（这正是"暂停时唱针偏右"
                // 的根因）。把唱针留在未倾斜的图层，它在 0° 就是真正竖直，同时唱盘照样有立体感。
                ZStack(alignment: .topLeading) {
                    turntableWell
                    spinningDisc
                        .position(vinylCenter)
                }
                .frame(width: cabinetWidth, height: cabinetHeight)
                .rotation3DEffect(
                    .degrees(embedded ? embeddedTiltDegrees : 10),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: embedded ? 0.85 : 0.7
                )

                tonearmAssembly

                // 播放时从盘面升起的氛围动效；不同盘面对应不同情绪，但不拦截整机点击手势。
                if isPlaying, auraIntensity != .off {
                    PlaybackAuraEffect(
                        style: auraStyle,
                        intensity: auraIntensity,
                        discCenter: vinylCenter,
                        discRadius: vinylDiameter / 2
                    )
                        .frame(width: cabinetWidth, height: cabinetHeight)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(width: cabinetWidth, height: cabinetHeight)
            .animation(.easeInOut(duration: 0.3), value: isPlaying)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .scaleEffect(isHovering ? 1.015 : 1.0)
            .animation(.easeInOut(duration: 0.18), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
            .pointingHandCursor()
            .onTapGesture {
                action()
            }
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isPlaying ? LocalizedStrings.text("main.turntable.playing") : LocalizedStrings.text("main.turntable.stopped"))
        // 监听频道切换：每当 stationToken 变化（且当前正在播放）就启动一次
        // "抬针—悬停—落针"的拟物动画，模拟换唱片的实际过程。
        .onChange(of: stationToken) { _, _ in
            triggerDiscSwapAnimation()
        }
        // 手动切换盘面只演"换肤"反馈：唱针不动，避免和暂停/切台混淆。
        .onChange(of: face.id) { _, _ in
            triggerFaceChangeFeedback()
        }
    }

    /// 当前 stem 应当呈现的角度。三态优先级：
    /// 1. 切台动画期间（`isSwappingStation`）→ 支架角度，和暂停态一致；
    /// 2. 正常播放 → `+35°`，针头落到唱片中段沟槽；
    /// 3. 暂停 → 轻微内收的支架角度，避免完全竖直时靠右侧换盘盒太近。
    /// 注意：暂停状态下切台时，前后角度都是支架角度，spring 不会有可见动画——
    /// 这是有意为之，因为针本就在那个位置，没必要"原地动一下"。
    private var currentStemAngle: Double {
        if isSwappingStation { return tonearmRestAngle }
        return isPlaying ? tonearmPlayAngle : tonearmRestAngle
    }

    /// 播放时叠加在基准角上的"循迹晃动"偏移（度）。
    /// 双正弦叠加：一条慢速主摆 + 一条更慢的包络，使摆幅大小持续起伏，
    /// 模拟真实唱臂随沟槽轻微摆动的机械感（约 ±0.5°…±3°），而非机械等幅抖动。
    /// 暂停或切台期间返回 0，保证唱针停在支架位、切台动画不被干扰。
    private func playbackWobble(at date: Date) -> Double {
        guard isPlaying, !isSwappingStation else { return 0 }
        let t = date.timeIntervalSinceReferenceDate
        let envelope = 1.8 + sin(t * 0.21) * 1.2
        return sin(t * 0.7) * envelope
    }

    /// 很轻的“循迹漂移”：不是歌曲进度，只是让唱臂像在沟槽里慢慢工作。
    private func trackingDrift(at date: Date) -> Double {
        guard isPlaying, !isSwappingStation else { return 0 }
        let t = date.timeIntervalSinceReferenceDate
        let progress = (sin(t * 0.018 - .pi / 2) + 1) / 2
        return progress * 2.8
    }

    /// 触发一次"抬针—悬停—落针"换片动画。切台（stationToken 变化）与换盘面（face 变化）共用。
    ///
    /// **关键**：这里不再以 `isPlaying` 作为前置条件。`PlaybackCoordinator.play()`
    /// 切台时会立即把 `state` 置为 `.loading`，于是 `isPlaying` 短暂变成 `false`，
    /// SwiftUI 下一帧触发 `onChange(stationToken)` 时该值还没回到 `true`。
    /// 之前 `guard isPlaying` 在切台瞬间总是失败，动画因此从不真正启动。
    ///
    /// 现在只靠 token 变化作为触发条件，stem 落下的目标角度由 `currentStemAngle`
    /// 在动画结束时实时取值：
    /// - 此时已 `.playing` → 落到 `+35°`（针头压在新唱片中段）；
    /// - 仍在 loading 或被用户按下暂停 → 落到 `0°`（笔直立在支架上）。
    ///
    /// 用 swapAnimationTask 串行化连续切台请求：旧 task 立即取消，
    /// 新 task 接管，确保连点切台时 stem 持续保持抬起，只有最后一次切台后才落下。
    private func triggerDiscSwapAnimation() {
        // 切台（token 变化）与切换盘面（face 变化）都复用这段"抬针—悬停—落针"动画：
        // token 从无到有（首次选台/冷启动恢复）也算一次"放上唱片"，统一演完整起落，体验更连贯。
        // 用 swapAnimationTask 串行化连续触发：旧 task 立即取消，新 task 接管，
        // 确保连点（连续切台/连续换盘）时 stem 持续保持抬起，只有最后一次后才落下。
        swapAnimationTask?.cancel()
        swapAnimationTask = Task { @MainActor in
            isSwappingStation = true
            let nanoseconds = UInt64(stationSwapHoldSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            // task 被 cancel 时不要把 stem 提前放下，让接管的新 task 来负责。
            guard !Task.isCancelled else { return }
            isSwappingStation = false
        }
    }

    private func triggerFaceChangeFeedback() {
        faceChangeResetTask?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) {
            faceChangeTick += 1
        }
        faceChangeResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.24)) {
                faceChangeTick += 1
            }
        }
    }

    // MARK: - 桌面阴影

    private var tableShadow: some View {
        Ellipse()
            .fill(Color.black.opacity(0.55))
            .frame(width: cabinetWidth * 0.94, height: 14)
            .blur(radius: 6)
            .offset(y: cabinetHeight / 2 + 4)
    }

    // MARK: - 木箱底座

    /// 木质底座：温暖的胡桃木色调，配合内阴影和顶部高光让它看起来像实物。
    private var woodCabinet: some View {
        ZStack {
            // 主体木纹渐变
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 95 / 255, green: 60 / 255, blue: 38 / 255),
                            Color(red: 72 / 255, green: 44 / 255, blue: 26 / 255),
                            Color(red: 52 / 255, green: 30 / 255, blue: 16 / 255)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // 顶部高光带
            LinearGradient(
                colors: [.white.opacity(0.18), .white.opacity(0.0)],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .blendMode(.plusLighter)
            .opacity(0.35)

            // 边框 + 内阴影模拟硬质边缘
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 130 / 255, green: 90 / 255, blue: 56 / 255),
                            Color(red: 30 / 255, green: 14 / 255, blue: 4 / 255)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.55), radius: 10, x: 0, y: 6)
    }

    // MARK: - 凹陷的转盘井（让黑胶看起来嵌在机身里）

    private var turntableWell: some View {
        Circle()
            .fill(Color.black.opacity(0.82))
            .frame(width: vinylDiameter + 10, height: vinylDiameter + 10)
            // 外圈一道木色高光环，像是机身顶面被掏出一个圆口、口沿被光照亮（凸起的口沿）。
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                PlayerTheme.cabinetEdgeHighlight.opacity(0.55),
                                PlayerTheme.cabinetEdgeHighlight.opacity(0.0),
                                Color.black.opacity(0.5)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
            }
            // 内投影：顶部内壁更暗（被口沿挡光），强化"向下凹进木面"的纵深。
            .overlay {
                Circle()
                    .stroke(Color.black.opacity(0.65), lineWidth: 4)
                    .blur(radius: 3)
                    .offset(y: 2)
                    .mask(Circle())
            }
            // 落在木面上的外阴影，让圆口看起来真的是凹陷而非贴片。
            .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
            .position(vinylCenter)
    }

    // MARK: - 旋转的黑胶唱片

    private var spinningDisc: some View {
        TimelineView(.animation) { timeline in
            ZStack {
                vinylBase
                grooveLayer
                highlightArc
                faceChangeGlow
                recordLabel
                centerSpindle
            }
            .frame(width: vinylDiameter, height: vinylDiameter)
            .rotationEffect(.degrees(rotationDegrees(at: timeline.date)))
        }
    }

    private var isFaceChanging: Bool {
        !faceChangeTick.isMultiple(of: 2)
    }

    private var vinylBase: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 38 / 255, green: 38 / 255, blue: 38 / 255),
                        Color(red: 18 / 255, green: 18 / 255, blue: 18 / 255),
                        Color(red: 4 / 255, green: 4 / 255, blue: 4 / 255)
                    ],
                    center: .topLeading,
                    startRadius: 4,
                    endRadius: vinylDiameter
                )
            )
    }

    /// 多层同心圆凹槽，给黑胶以质感。
    private var grooveLayer: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { index in
                Circle()
                    .stroke(
                        .white.opacity(index.isMultiple(of: 2) ? 0.06 : 0.025),
                        lineWidth: index.isMultiple(of: 4) ? 0.7 : 0.4
                    )
                    .padding(CGFloat(index) * 2.4 + 4)
            }
        }
    }

    /// 黑胶反光弧带：模拟从上方光源洒下的反射，让黑胶显得光滑。
    private var highlightArc: some View {
        Circle()
            .strokeBorder(
                AngularGradient(
                    colors: [
                        .white.opacity(0.0),
                        .white.opacity(0.20),
                        .white.opacity(0.04),
                        .white.opacity(0.0)
                    ],
                    center: .center,
                    angle: .degrees(35)
                ),
                lineWidth: 2
            )
            .padding(vinylDiameter * 0.05)
            .blendMode(.screen)
    }

    private var faceChangeGlow: some View {
        Circle()
            .strokeBorder(
                AngularGradient(
                    colors: [
                        .clear,
                        PlayerTheme.warmText.opacity(isFaceChanging ? 0.34 : 0.0),
                        PlayerTheme.displayGlow.opacity(isFaceChanging ? 0.24 : 0.0),
                        .clear
                    ],
                    center: .center,
                    angle: .degrees(isFaceChanging ? 115 : 20)
                ),
                lineWidth: isFaceChanging ? 3 : 1
            )
            .padding(vinylDiameter * 0.08)
            .blur(radius: isFaceChanging ? 0.4 : 1.2)
            .opacity(isFaceChanging ? 1 : 0)
            .blendMode(.screen)
            .animation(.easeOut(duration: 0.42), value: faceChangeTick)
    }

    /// 中央贴纸标签：暖色纸质感，配色与印字随当前盘面主题 `face` 切换。
    private var recordLabel: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: face.labelColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Circle().stroke(.black.opacity(0.5), lineWidth: 0.6)
                }
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

            VStack(spacing: 1.5) {
                Text(face.title)
                    .font(.system(size: 8.2, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                    .frame(width: vinylDiameter * 0.35)
                    .foregroundStyle(face.titleColor)
                Text(face.subtitle)
                    .font(.system(size: 5.4, weight: .semibold, design: .rounded))
                    .tracking(1.1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                    .frame(width: vinylDiameter * 0.36)
                    .foregroundStyle(face.subtitleColor)
            }
            .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
        }
        .frame(width: vinylDiameter * 0.46, height: vinylDiameter * 0.46)
        .scaleEffect(isFaceChanging ? 1.08 : 1.0)
        .rotationEffect(.degrees(isFaceChanging ? 7 : 0))
        .shadow(color: PlayerTheme.warmText.opacity(isFaceChanging ? 0.28 : 0), radius: isFaceChanging ? 6 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.68), value: faceChangeTick)
    }

    /// 中央转轴：金属圆锥反光。
    private var centerSpindle: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 230 / 255, green: 230 / 255, blue: 230 / 255),
                        Color(red: 110 / 255, green: 110 / 255, blue: 110 / 255)
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 4
                )
            )
            .frame(width: 6, height: 6)
            .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 0.5)
    }

    private func rotationDegrees(at date: Date) -> Double {
        guard isPlaying else { return 0 }
        let elapsed = date.timeIntervalSinceReferenceDate
        let progress = elapsed.truncatingRemainder(
            dividingBy: PlayerTheme.vinylRotationDurationSeconds
        ) / PlayerTheme.vinylRotationDurationSeconds
        return progress * 360
    }

    // MARK: - 唱针组件（枢轴在底座右上角）

    /// 唱针组件总体：枢轴放底座右上，金属臂从枢轴向唱片方向延伸，针头落到唱片外圈。
    /// 使用 ZStack alignment .topLeading + .position 把枢轴和臂的几何控制得很精确，
    /// 整个 frame 限制在底座内部，旋转后也不会越界遮挡右侧文字区域。
    private var tonearmAssembly: some View {
        ZStack(alignment: .topLeading) {
            // 金属臂 + 针头：用一个 stem 容器，stem 顶端对齐到枢轴位置，
            // 通过围绕 .top 锚点旋转控制唱针落下/抬起。
            // 用 TimelineView 逐帧把"循迹晃动"叠加到基准角上，让播放时唱针在盘面轻摆。
            TimelineView(.animation) { timeline in
                tonearmStem
                    .frame(width: 16, height: 60, alignment: .top)
                    .rotationEffect(
                        // SwiftUI 的 rotationEffect 正角度 = 顺时针（CW，从观察者视角）。
                        // stem 默认竖直向下（朝 +y_screen），从 .top 锚点（= 底座右上角的
                        // tonearmPivot (114, 16)）旋转。stem 末端针头距 anchor 约 56.5pt。
                        // 基准角 `currentStemAngle` 覆盖播放/暂停/切台三态，
                        // 再叠加轻微循迹漂移与微摆（仅播放时非零）：
                        // - 播放：针头落在沟槽区，缓慢内向漂移并轻晃；
                        // - 暂停/切台：停在略内收的支架位，不和换盘盒挤在一起。
                        .degrees(
                            currentStemAngle
                                + trackingDrift(at: timeline.date)
                                + playbackWobble(at: timeline.date)
                        ),
                        anchor: .top
                    )
                    // 仅监听 currentStemAngle：播放/暂停切换与切台起落用 spring 衔接；
                    // 逐帧的 wobble 偏移不触发该隐式动画，因此连续平滑、不被弹簧拖拽。
                    .animation(.spring(response: 0.55, dampingFraction: 0.78), value: currentStemAngle)
                    .position(x: tonearmPivot.x, y: tonearmPivot.y + 30)
            }

            tonearmPivotKnob
                .position(tonearmPivot)
        }
        .frame(width: cabinetWidth, height: cabinetHeight, alignment: .topLeading)
        // 保证唱针不会越出底座 frame：让整个 ZStack 严格被底座 frame 裁剪。
        // （注意：clipShape 只剪 stem 视觉，不剪 .position 计算结果，但 stem 旋转后落点在底座内部，所以裁也无所谓。）
    }

    /// 唱针金属臂 + 末端针头。
    private var tonearmStem: some View {
        ZStack(alignment: .top) {
            tonearmMainTube

            tonearmCartridge
                .rotationEffect(.degrees(-10))
                .offset(x: 4.8, y: 52)
        }
    }

    private var tonearmMainTube: some View {
        ZStack {
            tonearmCurve
                .stroke(.black.opacity(0.38), style: StrokeStyle(lineWidth: 5.2, lineCap: .round, lineJoin: .round))
                .offset(x: 0, y: 1)

            tonearmCurve
                .stroke(tonearmMetalGradient, style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))

            tonearmCurve
                .stroke(.white.opacity(0.36), style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round))
                .offset(x: -0.8, y: -0.3)
        }
        .frame(width: 16, height: 56)
    }

    private var tonearmCurve: Path {
        Path { path in
            path.move(to: CGPoint(x: 8, y: 1.5))
            path.addCurve(
                to: CGPoint(x: 8.8, y: 33),
                control1: CGPoint(x: 5.8, y: 12),
                control2: CGPoint(x: 11.2, y: 22)
            )
            path.addCurve(
                to: CGPoint(x: 11.4, y: 52),
                control1: CGPoint(x: 7.5, y: 42),
                control2: CGPoint(x: 10.8, y: 47)
            )
        }
    }

    private var tonearmCartridge: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            PlayerTheme.brassLight.opacity(0.95),
                            PlayerTheme.brassDark.opacity(0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 9.5, height: 7)
                .overlay {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(.black.opacity(0.36), lineWidth: 0.5)
                }

            Capsule()
                .fill(Color.black.opacity(0.72))
                .frame(width: 2, height: 5)
                .offset(y: 4.4)
        }
        .shadow(color: .black.opacity(0.55), radius: 1.4, x: 0, y: 1)
    }

    private var tonearmMetalGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 230 / 255, green: 230 / 255, blue: 230 / 255),
                Color(red: 160 / 255, green: 160 / 255, blue: 160 / 255),
                Color(red: 90 / 255, green: 90 / 255, blue: 90 / 255)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// 枢轴金属圆按钮：silver 渐变 + 暗色描边 + 高光点。
    private var tonearmPivotKnob: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.45))
                .frame(width: 20, height: 20)
                .blur(radius: 1.2)
                .offset(y: 1.4)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 46 / 255, green: 46 / 255, blue: 46 / 255),
                            Color(red: 12 / 255, green: 12 / 255, blue: 12 / 255)
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 11
                    )
                )
                .frame(width: 18, height: 18)
                .overlay {
                    Circle().stroke(PlayerTheme.brassDark.opacity(0.55), lineWidth: 0.8)
                }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 230 / 255, green: 230 / 255, blue: 230 / 255),
                            Color(red: 130 / 255, green: 130 / 255, blue: 130 / 255),
                            Color(red: 60 / 255, green: 60 / 255, blue: 60 / 255)
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 8
                    )
                )
                .frame(width: 14, height: 14)
                .overlay {
                    Circle().stroke(.black.opacity(0.5), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1)

            // 高光点
            Circle()
                .fill(.white.opacity(0.7))
                .frame(width: 3, height: 3)
                .offset(x: -3, y: -3)
        }
    }
}

enum PlaybackAuraStyle: Int, CaseIterable, Identifiable {
    case notes
    case sparkles
    case waveRings
    case fireflies
    case bubbles
    case comets

    var id: Int { rawValue }
}

private extension PlaybackAuraIntensity {
    var particleMultiplier: Double {
        switch self {
        case .off: 0
        case .subtle: 0.65
        case .balanced: 1
        case .rich: 1.35
        }
    }

    var opacityMultiplier: Double {
        switch self {
        case .off: 0
        case .subtle: 0.55
        case .balanced: 0.85
        case .rich: 1
        }
    }
}

/// 播放时的情绪化氛围层：随当前盘面切换不同效果，保持轻量且不影响点击。
private struct PlaybackAuraEffect: View {
    var style: PlaybackAuraStyle
    var intensity: PlaybackAuraIntensity
    var discCenter: CGPoint
    var discRadius: CGFloat

    var body: some View {
        switch style {
        case .notes:
            FloatingMusicNotes(intensity: intensity, discCenter: discCenter, discRadius: discRadius)
        case .sparkles:
            FloatingSparkles(intensity: intensity, discCenter: discCenter, discRadius: discRadius)
        case .waveRings:
            FloatingWaveRings(intensity: intensity, discCenter: discCenter, discRadius: discRadius)
        case .fireflies:
            FloatingFireflies(intensity: intensity, discCenter: discCenter, discRadius: discRadius)
        case .bubbles:
            FloatingBubbles(intensity: intensity, discCenter: discCenter, discRadius: discRadius)
        case .comets:
            FloatingComets(intensity: intensity, discCenter: discCenter, discRadius: discRadius)
        }
    }
}

/// 播放时从黑胶盘面持续升起的飘动音符。
/// 用 `TimelineView(.animation)` 按时间相位连续驱动，每个音符独立循环：
/// 从盘面上方升起 → 左右轻摆 → 边升边淡出，营造"音乐从唱片里飘出来"的氛围。
/// 全程不依赖 `withAnimation`，因此开关播放时由父视图的 transition 负责淡入淡出。
private struct FloatingMusicNotes: View {
    var intensity: PlaybackAuraIntensity
    /// 黑胶圆心（底座坐标系），音符从其上方区域升起。
    var discCenter: CGPoint
    /// 黑胶半径，决定音符起始高度与水平散布范围。
    var discRadius: CGFloat

    /// 同时在场的音符数量。
    private let noteCount = 3
    /// 单个音符一次"升起—淡出"循环时长（秒）。
    private let cyclePeriod: Double = 2.8
    /// 不同音符的字形，交错出现更生动。
    private let glyphs = ["music.note", "music.quarternote.3", "music.note"]
    /// 每个音符的水平起始偏移（相对圆心），让它们错开而非同一竖线升起。
    private let horizontalOffsets: [CGFloat] = [-10, 6, 16]

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<activeCount(base: noteCount), id: \.self) { index in
                    note(at: index, now: now)
                }
            }
        }
    }

    @ViewBuilder
    private func note(at index: Int, now: TimeInterval) -> some View {
        // 各音符相位错开，形成连续不断地往上飘的效果。
        let phase = Double(index) / Double(noteCount)
        let progress = ((now / cyclePeriod) + phase).truncatingRemainder(dividingBy: 1)

        // 升起高度：从盘面偏上一点开始，向上飘约 0.95 个半径。
        let rise = CGFloat(progress) * discRadius * 0.95
        // 左右轻摆，越往上摆幅略大，像被气流托着。
        let sway = CGFloat(sin(progress * .pi * 2 + Double(index))) * (5 + CGFloat(progress) * 4)
        // 两端淡入淡出（sin 在 0/1 处为 0、中段为 1）。
        let fade = sin(progress * .pi)

        let x = discCenter.x + horizontalOffsets[index % horizontalOffsets.count] + sway
        let y = discCenter.y - discRadius * 0.35 - rise

        Image(systemName: glyphs[index % glyphs.count])
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [PlayerTheme.brassLight, PlayerTheme.brassDark],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: .black.opacity(0.45), radius: 1, x: 0, y: 0.5)
            .rotationEffect(.degrees(Double(sway) * 1.4))
            .scaleEffect(0.55 + 0.5 * CGFloat(fade))
            .opacity(fade * 0.95 * intensity.opacityMultiplier)
            .position(x: x, y: y)
    }

    private func activeCount(base: Int) -> Int {
        max(1, Int((Double(base) * intensity.particleMultiplier).rounded()))
    }
}

/// 星尘动效：小星点从唱盘边缘轻轻升起，适合偏夜色/梦幻的盘面。
private struct FloatingSparkles: View {
    var intensity: PlaybackAuraIntensity
    var discCenter: CGPoint
    var discRadius: CGFloat

    private let sparkleCount = 5
    private let cyclePeriod: Double = 3.2
    private let symbols = ["sparkle", "sparkles", "plus"]

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<activeCount(base: sparkleCount), id: \.self) { index in
                    sparkle(at: index, now: now)
                }
            }
        }
    }

    private func sparkle(at index: Int, now: TimeInterval) -> some View {
        let phase = Double(index) / Double(sparkleCount)
        let progress = ((now / cyclePeriod) + phase).truncatingRemainder(dividingBy: 1)
        let angle = Double(index) * 1.25 + progress * 0.8
        let radius = discRadius * (0.35 + CGFloat(progress) * 0.55)
        let drift = CGFloat(sin(progress * .pi * 2 + Double(index))) * 5
        let x = discCenter.x + CGFloat(cos(angle)) * radius + drift
        let y = discCenter.y - discRadius * 0.15 - CGFloat(progress) * discRadius * 0.9
        let fade = sin(progress * .pi)

        return Image(systemName: symbols[index % symbols.count])
            .font(.system(size: 8 + CGFloat(index % 2) * 2, weight: .semibold))
            .foregroundStyle(PlayerTheme.brassLight.opacity(0.95))
            .shadow(color: PlayerTheme.brassLight.opacity(0.5), radius: 3)
            .rotationEffect(.degrees(progress * 180))
            .scaleEffect(0.45 + CGFloat(fade) * 0.55)
            .opacity(fade * 0.9 * intensity.opacityMultiplier)
            .position(x: x, y: y)
    }

    private func activeCount(base: Int) -> Int {
        max(1, Int((Double(base) * intensity.particleMultiplier).rounded()))
    }
}

/// 声波环动效：从唱盘中心向外扩散的薄环，像低频节拍在黑胶上泛开。
private struct FloatingWaveRings: View {
    var intensity: PlaybackAuraIntensity
    var discCenter: CGPoint
    var discRadius: CGFloat

    private let ringCount = 3
    private let cyclePeriod: Double = 2.6

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<activeCount(base: ringCount), id: \.self) { index in
                    ring(at: index, now: now)
                }
            }
        }
    }

    private func ring(at index: Int, now: TimeInterval) -> some View {
        let phase = Double(index) / Double(ringCount)
        let progress = ((now / cyclePeriod) + phase).truncatingRemainder(dividingBy: 1)
        let fade = 1 - progress
        let diameter = discRadius * (0.65 + CGFloat(progress) * 1.15)

        return Circle()
            .stroke(PlayerTheme.brassLight.opacity(0.55 * fade), lineWidth: 1)
            .frame(width: diameter, height: diameter)
            .shadow(color: PlayerTheme.displayGlow.opacity(0.3 * fade), radius: 4)
            .opacity(fade * intensity.opacityMultiplier)
            .position(x: discCenter.x, y: discCenter.y)
    }

    private func activeCount(base: Int) -> Int {
        max(1, Int((Double(base) * intensity.particleMultiplier).rounded()))
    }
}

/// 萤光点动效：细小光点绕盘面漂移，适合偏自然/放松的盘面。
private struct FloatingFireflies: View {
    var intensity: PlaybackAuraIntensity
    var discCenter: CGPoint
    var discRadius: CGFloat

    private let dotCount = 6
    private let cyclePeriod: Double = 4.4

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<activeCount(base: dotCount), id: \.self) { index in
                    dot(at: index, now: now)
                }
            }
        }
    }

    private func dot(at index: Int, now: TimeInterval) -> some View {
        let phase = Double(index) / Double(dotCount)
        let progress = ((now / cyclePeriod) + phase).truncatingRemainder(dividingBy: 1)
        let angle = Double(index) * 1.7 + now * 0.55
        let radius = discRadius * (0.55 + CGFloat(sin(progress * .pi)) * 0.45)
        let x = discCenter.x + CGFloat(cos(angle)) * radius
        let y = discCenter.y + CGFloat(sin(angle * 0.8)) * radius * 0.58 - CGFloat(progress) * 10
        let glow = sin(progress * .pi)
        let diameter = 3.5 + CGFloat(index % 2)
        let fillOpacity = 0.35 + glow * 0.5
        let finalOpacity = (0.25 + glow * 0.7) * intensity.opacityMultiplier

        return Circle()
            .fill(PlayerTheme.successGreen.opacity(fillOpacity))
            .frame(width: diameter, height: diameter)
            .shadow(color: PlayerTheme.successGreen.opacity(0.7), radius: 4)
            .opacity(finalOpacity)
            .position(x: x, y: y)
    }

    private func activeCount(base: Int) -> Int {
        max(1, Int((Double(base) * intensity.particleMultiplier).rounded()))
    }
}

/// 气泡动效：透明小圆从唱片边缘漂起，适合轻松、空气感强的频道。
private struct FloatingBubbles: View {
    var intensity: PlaybackAuraIntensity
    var discCenter: CGPoint
    var discRadius: CGFloat

    private let bubbleCount = 5
    private let cyclePeriod: Double = 3.6

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<activeCount(base: bubbleCount), id: \.self) { index in
                    bubble(at: index, now: now)
                }
            }
        }
    }

    private func bubble(at index: Int, now: TimeInterval) -> some View {
        let phase = Double(index) / Double(bubbleCount)
        let progress = ((now / cyclePeriod) + phase).truncatingRemainder(dividingBy: 1)
        let fade = sin(progress * .pi)
        let lateral = CGFloat(sin(progress * .pi * 2 + Double(index))) * (5 + CGFloat(index % 2) * 2)
        let x = discCenter.x - discRadius * 0.3 + CGFloat(index) * discRadius * 0.15 + lateral
        let y = discCenter.y + discRadius * 0.15 - CGFloat(progress) * discRadius * 1.08
        let diameter = 4 + CGFloat(index % 3) * 1.5 + CGFloat(progress) * 2

        return Circle()
            .stroke(PlayerTheme.displayAmberDim.opacity(0.25 + fade * 0.45), lineWidth: 0.8)
            .background(Circle().fill(PlayerTheme.displayGlow.opacity(0.05 + fade * 0.10)))
            .frame(width: diameter, height: diameter)
            .shadow(color: PlayerTheme.displayGlow.opacity(0.25 * fade), radius: 3)
            .opacity((0.2 + fade * 0.65) * intensity.opacityMultiplier)
            .position(x: x, y: y)
    }

    private func activeCount(base: Int) -> Int {
        max(1, Int((Double(base) * intensity.particleMultiplier).rounded()))
    }
}

/// 流星动效：短促的斜向光痕划过唱片上方，适合更有节奏感的频道。
private struct FloatingComets: View {
    var intensity: PlaybackAuraIntensity
    var discCenter: CGPoint
    var discRadius: CGFloat

    private let cometCount = 4
    private let cyclePeriod: Double = 3.0

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<activeCount(base: cometCount), id: \.self) { index in
                    comet(at: index, now: now)
                }
            }
        }
    }

    private func comet(at index: Int, now: TimeInterval) -> some View {
        let phase = Double(index) / Double(cometCount)
        let progress = ((now / cyclePeriod) + phase).truncatingRemainder(dividingBy: 1)
        let fade = sin(progress * .pi)
        let startX = discCenter.x - discRadius * 0.65 + CGFloat(index % 2) * 14
        let x = startX + CGFloat(progress) * discRadius * 1.45
        let y = discCenter.y - discRadius * 0.75 + CGFloat(index) * 7 - CGFloat(progress) * 12

        return Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        PlayerTheme.brassLight.opacity(0.0),
                        PlayerTheme.brassLight.opacity(0.85 * fade),
                        PlayerTheme.brassDark.opacity(0.25 * fade)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 18, height: 2.2)
            .shadow(color: PlayerTheme.brassLight.opacity(0.45 * fade), radius: 4)
            .rotationEffect(.degrees(-22))
            .opacity(fade * 0.9 * intensity.opacityMultiplier)
            .position(x: x, y: y)
    }

    private func activeCount(base: Int) -> Int {
        max(1, Int((Double(base) * intensity.particleMultiplier).rounded()))
    }
}

/// "换盘面"按钮：贴在唱机侧边的小唱片匣，拟物但不进入唱盘/唱针运动路径。
struct VinylFaceSwapButton: View {
    /// 当前盘面（决定中心贴标点的颜色）。
    let face: VinylFace
    let action: () -> Void

    @State private var isHovering = false
    @State private var clickTick = 0
    @State private var clickResetTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            cartridgeBody

            miniRecord
                .rotationEffect(.degrees(Double(clickTick % 4) * 22))
                .offset(x: isPressed ? -2.2 : 0, y: isPressed ? -3.5 : 0.8)
                .scaleEffect(isPressed ? 1.05 : 1.0)

            Circle()
                .fill(face.swatch)
                .frame(width: 6, height: 6)
                .overlay { Circle().stroke(.black.opacity(0.45), lineWidth: 0.5) }
                .shadow(color: face.swatch.opacity(0.7), radius: 2.5)
                .offset(x: 10, y: -10 + (isPressed ? -1.5 : 0))
        }
        .frame(width: 34, height: 34)
        .scaleEffect(isHovering ? 1.055 : 1)
        .offset(y: isPressed ? 0.8 : 0)
        .shadow(color: .black.opacity(0.48), radius: isHovering ? 4 : 3, x: 0, y: isHovering ? 2.5 : 2)
        .overlay {
            PhysicalClickLayer {
                triggerCartridgeClick()
                action()
            }
        }
        .help(LocalizedStrings.text("main.vinyl.change.current", face.title, face.subtitle))
        .accessibilityLabel(LocalizedStrings.text("main.vinyl.change.current", face.title, face.subtitle))
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeInOut(duration: 0.14), value: isHovering)
        .animation(.spring(response: 0.24, dampingFraction: 0.66), value: clickTick)
    }

    private var isPressed: Bool {
        !clickTick.isMultiple(of: 2)
    }

    private func triggerCartridgeClick() {
        clickResetTask?.cancel()
        withAnimation(.spring(response: 0.24, dampingFraction: 0.66)) {
            clickTick += 1
        }
        clickResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                clickTick += 1
            }
        }
    }

    private var cartridgeBody: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        PlayerTheme.cabinetWoodTop.opacity(isHovering ? 0.98 : 0.9),
                        PlayerTheme.cabinetWoodMid.opacity(0.92),
                        PlayerTheme.cabinetWoodBottom.opacity(0.96)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.black.opacity(0.26))
                    .frame(height: 8)
                    .blur(radius: 1.2)
                    .offset(y: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                PlayerTheme.cabinetEdgeHighlight.opacity(isHovering ? 0.66 : 0.42),
                                Color.black.opacity(0.38)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.9
                    )
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(isHovering ? 0.18 : 0.12))
                    .frame(width: 23, height: 1.2)
                    .offset(y: 4)
            }
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.black.opacity(0.28))
                    .frame(width: 5, height: 24)
                    .blur(radius: 0.4)
                    .offset(x: 4)
            }
    }

    private var miniRecord: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 52 / 255, green: 48 / 255, blue: 44 / 255),
                            Color(red: 14 / 255, green: 13 / 255, blue: 12 / 255)
                        ],
                        center: .topLeading,
                        startRadius: 1,
                        endRadius: 15
                    )
                )
                .frame(width: 22, height: 22)
                .overlay { Circle().stroke(PlayerTheme.brassDark.opacity(0.65), lineWidth: 0.8) }

            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    .frame(width: 10 + CGFloat(index) * 4, height: 10 + CGFloat(index) * 4)
            }

            Circle()
                .fill(
                    LinearGradient(
                        colors: face.labelColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 8, height: 8)
                .overlay { Circle().stroke(.black.opacity(0.35), lineWidth: 0.5) }
        }
    }
}
