import SwiftUI

/// 播放器界面主题，围绕深靛蓝、木质和黄铜质感组织视觉语言。
enum PlayerTheme {
    static let warmText = Color(red: 255 / 255, green: 218 / 255, blue: 185 / 255)
    static let primaryText = Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255)
    static let secondaryText = Color(red: 203 / 255, green: 213 / 255, blue: 225 / 255)

    /// 健康状态语义色：绿/红/黄/灰，用于频道列表小圆点和管理页徽标。
    static let successGreen = Color(red: 74 / 255, green: 222 / 255, blue: 128 / 255)
    static let dangerRed = Color(red: 248 / 255, green: 113 / 255, blue: 113 / 255)
    static let warningYellow = Color(red: 250 / 255, green: 204 / 255, blue: 21 / 255)
    static let neutralGray = Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255)

    /// 频道来源徽标用的两种主题色：内置（柔蓝）vs 自定义（暖橘）。
    static let bundledBadgeColor = Color(red: 96 / 255, green: 165 / 255, blue: 250 / 255)
    static let customBadgeColor = Color(red: 251 / 255, green: 146 / 255, blue: 60 / 255)

    /// macOS 标准红绿灯按钮配色（关闭红 / 最小化黄）。
    /// fill 为按钮主体色，border 为同色系更暗一档的描边，glyph 为悬停时符号的暗色。
    static let trafficCloseFill = Color(red: 255 / 255, green: 95 / 255, blue: 87 / 255)
    static let trafficCloseBorder = Color(red: 224 / 255, green: 68 / 255, blue: 62 / 255)
    static let trafficMinimizeFill = Color(red: 254 / 255, green: 188 / 255, blue: 46 / 255)
    static let trafficMinimizeBorder = Color(red: 222 / 255, green: 161 / 255, blue: 35 / 255)
    static let trafficGlyph = Color.black.opacity(0.55)
    static let trafficButtonDiameter: CGFloat = 12
    static let trafficButtonSpacing: CGFloat = 8

    /// 复古"电台控制台"用色：黄铜（亮/暗）、米色刻度盘、暗木面板。
    /// 与左侧唱机的木质+黄铜质感呼应，让音量与传输控件成为统一的控制台。
    static let brassLight = Color(red: 222 / 255, green: 178 / 255, blue: 110 / 255)
    static let brassDark = Color(red: 138 / 255, green: 92 / 255, blue: 42 / 255)
    static let creamTrack = Color(red: 232 / 255, green: 216 / 255, blue: 184 / 255)
    /// 播放主键上深色字形（暗黄铜），落在亮黄铜底上保证对比度。
    static let brassGlyphDark = Color(red: 46 / 255, green: 28 / 255, blue: 10 / 255)

    /// 一体化木质机身（与唱机木箱同色系，顶面亮、机身底部暗）：
    /// 整个小组件就是这一台连续的复古唱机，唱盘嵌在顶面、控件做在前面板上。
    static let cabinetWoodTop = Color(red: 104 / 255, green: 67 / 255, blue: 42 / 255)
    static let cabinetWoodMid = Color(red: 80 / 255, green: 50 / 255, blue: 30 / 255)
    static let cabinetWoodBottom = Color(red: 52 / 255, green: 31 / 255, blue: 17 / 255)
    /// 木面转折处的高光木色，用于蚀刻接缝的高光线和边缘反光。
    static let cabinetEdgeHighlight = Color(red: 152 / 255, green: 106 / 255, blue: 64 / 255)

    /// 复古数显屏（VFD/LED 风格）配色。
    /// 之前的深靛蓝屏与暖木+黄铜机身割裂；改成"深色暖底 + 琥珀色发光字"，
    /// 与机身同属暖色家族，呈现老式电子时钟/收音机数显的实物质感。
    static let displayPanelTop = Color(red: 28 / 255, green: 19 / 255, blue: 11 / 255)
    static let displayPanelBottom = Color(red: 12 / 255, green: 8 / 255, blue: 4 / 255)
    static let displayAmber = Color(red: 255 / 255, green: 179 / 255, blue: 77 / 255)
    static let displayAmberDim = Color(red: 198 / 255, green: 122 / 255, blue: 52 / 255)
    static let displayGlow = Color(red: 255 / 255, green: 150 / 255, blue: 44 / 255)

    static let stationRowCornerRadius: CGFloat = 12
    static let vinylRotationDurationSeconds: TimeInterval = 8
}
