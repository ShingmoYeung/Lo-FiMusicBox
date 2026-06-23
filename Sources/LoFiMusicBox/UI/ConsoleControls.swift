import AppKit
import SwiftUI

/// 黄铜"调谐"风格音量滑杆：米色凹槽轨 + 等距刻度 + 黄铜已填充段 + 黄铜旋钮。
/// 取代系统 `Slider`，与左侧唱机的木质/黄铜质感统一；保留拖动调节的精度。
struct BrassVolumeSlider: View {
    /// 取值范围固定 0...1，由外部用 `Binding` 绑定播放音量。
    @Binding var value: Double
    /// 刻度数量（含首尾），仅作视觉点缀，与取值无强绑定。
    var tickCount: Int = 11

    private let knobDiameter: CGFloat = 16
    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // 旋钮中心可移动的有效行程：两端各留半个旋钮，避免旋钮溢出轨道。
            let usableWidth = max(0, width - knobDiameter)
            let clampedValue = min(max(value, 0), 1)
            let knobOffsetX = usableWidth * CGFloat(clampedValue)

            ZStack(alignment: .leading) {
                // 底轨：米色凹槽 + 内描边。
                Capsule()
                    .fill(PlayerTheme.creamTrack.opacity(0.22))
                    .overlay {
                        Capsule().stroke(Color.black.opacity(0.35), lineWidth: 0.5)
                    }
                    .frame(height: trackHeight)

                // 刻度：等距细线，整十处略高，营造调谐盘的细节。
                tickMarks(usableWidth: usableWidth)

                // 已填充段：从最左到旋钮中心，黄铜渐变。
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [PlayerTheme.brassDark, PlayerTheme.brassLight],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: knobOffsetX + knobDiameter / 2, height: trackHeight)

                // 黄铜旋钮。
                knob
                    .offset(x: knobOffsetX)
            }
            .frame(height: knobDiameter)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            // 用 AppKit 交互层接管按下/拖动，而非 SwiftUI DragGesture：
            // 窗口设了 isMovableByWindowBackground=true，SwiftUI 手势在指针一移动时
            // 就会被系统的"拖动背景移动窗口"抢走，表现为"只能点击、拖不动"。
            // SliderScrubLayer 的 NSView 覆盖 mouseDownCanMoveWindow=false，
            // 从源头阻止窗口拖拽，于是按下与连续拖动都能稳定调音量。
            .overlay {
                SliderScrubLayer(knobDiameter: knobDiameter) { ratioX in
                    guard usableWidth > 0 else { return }
                    let location = ratioX - knobDiameter / 2
                    value = min(max(Double(location / usableWidth), 0), 1)
                }
            }
        }
        .frame(height: knobDiameter)
    }

    private func tickMarks(usableWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(0..<tickCount, id: \.self) { index in
                let progress = tickCount > 1 ? CGFloat(index) / CGFloat(tickCount - 1) : 0
                let isMajor = index % 5 == 0
                Rectangle()
                    .fill(PlayerTheme.creamTrack.opacity(isMajor ? 0.5 : 0.3))
                    .frame(width: 1, height: isMajor ? 8 : 5)
                    // +knobDiameter/2 让刻度与旋钮行程对齐（旋钮中心从半径处起算）。
                    .offset(x: usableWidth * progress + knobDiameter / 2 - 0.5)
            }
        }
    }

    private var knob: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [PlayerTheme.brassLight, PlayerTheme.brassDark],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: knobDiameter
                )
            )
            .frame(width: knobDiameter, height: knobDiameter)
            .overlay {
                Circle().stroke(Color.black.opacity(0.4), lineWidth: 0.5)
            }
            .overlay(alignment: .topLeading) {
                // 左上高光点，增强金属球面反光感。
                Circle()
                    .fill(Color.white.opacity(0.65))
                    .frame(width: 4, height: 4)
                    .offset(x: 3, y: 3)
            }
            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
    }
}

/// 透明的 AppKit 交互层，覆盖在 `BrassVolumeSlider` 之上，专门接管鼠标按下与拖动。
///
/// 为什么不用 SwiftUI 的 `DragGesture`：主窗口开启了 `isMovableByWindowBackground = true`，
/// 指针一旦移动，系统就把后续事件当作"拖动背景移动窗口"，SwiftUI 拖动手势随之失效，
/// 用户观感就是"音量只能点、拖不动"。这里用一个 `mouseDownCanMoveWindow` 返回 `false`
/// 的 NSView 命中滑杆区域，从根上阻止窗口被拖走；按下/拖动均回调命中点的本地 x 坐标。
struct SliderScrubLayer: NSViewRepresentable {
    /// 旋钮直径，用于把本地 x 坐标换算成 0...1 时与视觉行程对齐。
    var knobDiameter: CGFloat
    /// 命中点在视图内的本地 x 坐标（左 0、右 bounds.width）回调。
    var onScrub: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrubNSView {
        let view = ScrubNSView()
        view.onScrub = onScrub
        return view
    }

    func updateNSView(_ nsView: ScrubNSView, context: Context) {
        nsView.onScrub = onScrub
    }

    /// 实际承接事件的 NSView。
    final class ScrubNSView: NSView {
        var onScrub: ((CGFloat) -> Void)?

        /// 关键：声明本视图区域不可用于拖动窗口，避免与音量拖动相互抢夺事件。
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) { scrub(with: event) }
        override func mouseDragged(with event: NSEvent) { scrub(with: event) }

        private func scrub(with event: NSEvent) {
            let localPoint = convert(event.locationInWindow, from: nil)
            onScrub?(localPoint.x)
        }
    }
}

/// 透明的 AppKit 点击层，给小尺寸实体控件使用。
/// 主窗口允许拖拽背景移动；小按钮如果只依赖 SwiftUI `Button`，在某些区域会被窗口拖拽抢走事件。
/// 这个层显式声明 `mouseDownCanMoveWindow=false`，并在鼠标抬起时触发动作。
struct PhysicalClickLayer: NSViewRepresentable {
    var action: () -> Void

    func makeNSView(context: Context) -> ClickNSView {
        let view = ClickNSView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: ClickNSView, context: Context) {
        nsView.action = action
    }

    final class ClickNSView: NSView {
        var action: (() -> Void)?

        override var mouseDownCanMoveWindow: Bool { false }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }

        override func mouseUp(with event: NSEvent) {
            let localPoint = convert(event.locationInWindow, from: nil)
            guard bounds.contains(localPoint) else { return }
            action?()
        }
    }
}

/// 前面板小型圆形功能键：复用传输键的金属语言，并用 AppKit 点击层保证不被窗口拖拽抢事件。
struct PhysicalRoundButton: View {
    var systemName: String
    var accessibilityLabel: String
    var diameter: CGFloat
    var isHighlighted: Bool = false
    var indicatorColor: Color?
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(isHovering ? 0.16 : 0.10),
                            Color.black.opacity(isHighlighted ? 0.30 : 0.36)
                        ],
                        center: .top,
                        startRadius: 1,
                        endRadius: diameter
                    )
                )

            Image(systemName: systemName)
                .font(.system(size: diameter * 0.38, weight: .bold))
                .foregroundStyle(isHighlighted ? PlayerTheme.warmText : PlayerTheme.creamTrack.opacity(isHovering ? 1 : 0.82))

            if let indicatorColor {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: diameter * 0.18, height: diameter * 0.18)
                    .overlay { Circle().stroke(Color.black.opacity(0.42), lineWidth: 0.5) }
                    .shadow(color: indicatorColor.opacity(0.65), radius: 2)
                    .offset(x: diameter * 0.25, y: -diameter * 0.25)
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay {
            Circle().stroke(
                isHighlighted
                    ? PlayerTheme.warmText.opacity(isHovering ? 0.82 : 0.62)
                    : PlayerTheme.brassDark.opacity(isHovering ? 0.8 : 0.55),
                lineWidth: isHighlighted ? 1.1 : 1
            )
        }
        .scaleEffect(isHovering ? 1.06 : 1.0)
        .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
        .overlay {
            PhysicalClickLayer(action: action)
        }
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}

/// 控制台一键静音切换键：黄铜圆钮，静音时字形转为告警红并底色更深（下陷感），状态一目了然。
struct MuteToggleButton: View {
    var isMuted: Bool
    var diameter: CGFloat = 22
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: diameter * 0.34, weight: .bold))
                .foregroundStyle(glyphColor)
                .frame(width: diameter, height: diameter)
                .background(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(isHovering ? 0.16 : 0.10),
                                    Color.black.opacity(isMuted ? 0.46 : 0.36)
                                ],
                                center: .top,
                                startRadius: 1,
                                endRadius: diameter
                            )
                        )
                )
                .overlay {
                    Circle().stroke(PlayerTheme.brassDark.opacity(isHovering ? 0.8 : 0.55), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMuted ? LocalizedStrings.text("main.unmute") : LocalizedStrings.text("main.mute"))
        .help(isMuted ? LocalizedStrings.text("main.unmute") : LocalizedStrings.text("main.mute"))
        .onHover { hovering in
            isHovering = hovering
        }
        .pointingHandCursor()
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }

    private var glyphColor: Color {
        if isMuted {
            return PlayerTheme.dangerRed.opacity(0.9)
        }
        return PlayerTheme.creamTrack.opacity(isHovering ? 1 : 0.82)
    }
}

/// 控制台两侧的圆形传输按钮（上一首 / 下一首）：内凹金属质感 + 黄铜描边。
struct TransportButton: View {
    var systemName: String
    var accessibilityLabel: String
    var diameter: CGFloat
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: diameter * 0.36, weight: .bold))
                .foregroundStyle(PlayerTheme.creamTrack.opacity(isHovering ? 1 : 0.82))
                .frame(width: diameter, height: diameter)
                .background(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(isHovering ? 0.16 : 0.10),
                                    Color.black.opacity(0.36)
                                ],
                                center: .top,
                                startRadius: 1,
                                endRadius: diameter
                            )
                        )
                )
                .overlay {
                    Circle().stroke(PlayerTheme.brassDark.opacity(isHovering ? 0.8 : 0.55), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
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

/// 控制台中央的播放/暂停主键：实心黄铜圆钮 + 顶部高光 + 深色字形，体量大于两侧传输键。
struct PlayDeckButton: View {
    var isPlaying: Bool
    var diameter: CGFloat
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: diameter * 0.4, weight: .heavy))
                .foregroundStyle(PlayerTheme.brassGlyphDark)
                .frame(width: diameter, height: diameter)
                .background(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [PlayerTheme.brassLight, PlayerTheme.brassDark],
                                center: .topLeading,
                                startRadius: 1,
                                endRadius: diameter
                            )
                        )
                )
                .overlay {
                    Circle().stroke(PlayerTheme.brassLight.opacity(0.9), lineWidth: 1)
                }
                .overlay(alignment: .top) {
                    // 顶部一抹柔光，模拟实体按钮的反光。
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.4), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .padding(1)
                }
                .scaleEffect(isHovering ? 1.06 : 1.0)
                .shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? LocalizedStrings.text("main.pause") : LocalizedStrings.text("main.play"))
        .help(isPlaying ? LocalizedStrings.text("main.pause") : LocalizedStrings.text("main.play"))
        .onHover { hovering in
            isHovering = hovering
        }
        .pointingHandCursor()
        .animation(.easeInOut(duration: 0.14), value: isHovering)
    }
}
