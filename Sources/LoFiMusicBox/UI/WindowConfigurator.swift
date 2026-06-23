import AppKit
import ObjectiveC
import SwiftUI

/// borderless 窗口 key window 覆盖逻辑的容器。
///
/// 封装到 enum 里是为了在 Swift 6 严格并发检查下能合法访问 `NSWindow` 这类 `@MainActor`
/// 隔离的 AppKit API：把 `installIfNeeded()` 标记为 `@MainActor`，由 `App.init`（也在主线程上）调用即可。
/// 内部用 `nonisolated(unsafe)` 静态变量保存一次性状态（原 IMP、是否已安装），
/// 因为这些状态的读写完全发生在主线程，并发环境下不会被多线程交错访问。
private enum LofiBorderlessKeyWindowOverride {
    /// 保留 NSWindow.canBecomeKeyWindow 的原 IMP，覆盖逻辑里对 titled 窗口仍委托回它。
    nonisolated(unsafe) static var originalCanBecomeKeyWindowIMP: IMP?

    /// 是否已经完成方法覆盖的安装。`installIfNeeded` 用它做一次性守卫。
    nonisolated(unsafe) static var hasInstalled: Bool = false

    /// 安装覆盖逻辑：让 styleMask 中拆掉了 `.titled` 的 borderless 窗口仍然能成为 key window。
    /// 否则 widget 主窗口拆掉 `.titled` 后会无法接收键盘事件，空格/左右键等失效。
    /// 其它仍含 `.titled` 的窗口（如 Settings、系统 panel 等）走原始实现，行为不变。
    @MainActor
    static func installIfNeeded() {
        guard !hasInstalled else { return }
        hasInstalled = true

        let cls = NSWindow.self
        let selector = NSSelectorFromString("canBecomeKeyWindow")
        guard let originalMethod = class_getInstanceMethod(cls, selector) else { return }
        originalCanBecomeKeyWindowIMP = method_getImplementation(originalMethod)

        let overrideBlock: @convention(block) (NSWindow) -> Bool = { window in
            if !window.styleMask.contains(.titled) {
                return true
            }
            guard let originalIMP = originalCanBecomeKeyWindowIMP else { return false }
            typealias OriginalFunctionType = @convention(c) (AnyObject, Selector) -> Bool
            let originalFunction = unsafeBitCast(originalIMP, to: OriginalFunctionType.self)
            return originalFunction(window, selector)
        }
        let overrideIMP = imp_implementationWithBlock(overrideBlock as Any)
        method_setImplementation(originalMethod, overrideIMP)
    }
}

/// 显式触发入口，由 `LoFiMusicBoxApp.init()`（主线程）调用一次即可装配覆盖逻辑。
@MainActor
@inline(__always) func ensureLofiBorderlessKeyWindowOverrideInstalled() {
    LofiBorderlessKeyWindowOverride.installIfNeeded()
}

/// 把 SwiftUI 窗口改造成无标题栏、透明背景、圆角的悬浮小组件外观。
/// 通过插入一个零尺寸的 NSView 抓取宿主 NSWindow，做必要的样式设置，
/// 同时把窗口引用通过回调传回 SwiftUI 层，便于自定义关闭/最小化按钮直接操作宿主窗口。
struct WidgetWindowConfigurator: NSViewRepresentable {
    /// 上层接收宿主窗口的回调。会在窗口可用时及更新时调用。
    var onResolveWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let proxyView = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = proxyView.window else { return }
            applyWidgetStyle(to: window)
            onResolveWindow(window)
        }
        return proxyView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            applyWidgetStyle(to: window)
            onResolveWindow(window)
        }
    }

    /// 让窗口看起来彻底像悬浮小组件：
    /// - 完全透明、无标题栏、无系统按钮；
    /// - **直接从 styleMask 移除 `.titled`** —— 这是消除底部 28pt 透明带的根因修复：
    ///   只要 styleMask 还含 `.titled`，AppKit 就会强制 NSWindow.frame.height
    ///   = contentSize.height + titlebar 高度（约 28pt），即便 `fullSizeContentView`
    ///   让 contentView 撑满 frame，SwiftUI view（按 widgetWindowHeight=248 设计）
    ///   也只能填满 248 区域，剩下的 28pt 就在底部漏出窗口透明背景。拆掉 `.titled`
    ///   后，NSWindow.frame.height 严格 = contentSize.height，contentView 与
    ///   SwiftUI view 完全重合，顶/底都不会再有透明带；
    /// - borderless 窗口默认无法 becomeKey，文件顶部已通过 ObjC runtime 覆盖
    ///   让 borderless window 仍可成为 key，确保空格/左右键等键盘快捷键继续可用；
    /// - 把 NSWindow.frame 锁死为 widget 设计尺寸，避免被系统或 SwiftUI 再撑大；
    /// - 整个窗口背景可拖拽。
    private func applyWidgetStyle(to window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        // 关键：拆掉 .titled，让 NSWindow.frame.height 不再被 AppKit 自动追加 titlebar 高度。
        window.styleMask.remove(.titled)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true

        let targetSize = NSSize(
            width: AppConstants.UserInterface.widgetWindowWidth,
            height: AppConstants.UserInterface.widgetWindowHeight
        )

        // 同步 NSWindow 真实 frame 到目标尺寸：macOS 的 frame.origin 在左下角，
        // 调整高度时把 origin.y 上移相同差值，让窗口顶边视觉位置稳定不抖动。
        if window.frame.size.width != targetSize.width
            || window.frame.size.height != targetSize.height {
            var newFrame = window.frame
            newFrame.origin.y += newFrame.size.height - targetSize.height
            newFrame.size = targetSize
            window.setFrame(newFrame, display: true)
        }

        // 锁死窗口尺寸，避免 SwiftUI 或系统再次 resize。
        // 注意：拆掉 .titled 后绝不可再 setContentSize —— 否则 AppKit 会按
        // “没有 titlebar 的逻辑”重新计算并把 frame 重设为 contentSize（看似没影响），
        // 但与 fullSizeContentView 配合容易触发 layout 抖动，统一只用 setFrame 控制。
        window.minSize = targetSize
        window.maxSize = targetSize

        // 给 NSWindow.contentView 自己的 CALayer 也加上同样的圆角，否则窗口的
        // 实际承载层仍是矩形：SwiftUI 端 clipShape 只裁剪了像素显示，但 AppKit
        // 计算窗口阴影、点阵采样、bounds 时依然按矩形 contentView 处理，外侧四个角
        // 就会漏出直角的阴影/边缘痕迹。把 cornerRadius / masksToBounds / cornerCurve
        // 同步到 layer 后，窗口本体也变成连续圆角矩形，与 SwiftUI 视觉完全对齐。
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            if let layer = contentView.layer {
                layer.cornerRadius = AppConstants.UserInterface.widgetCornerRadius
                layer.cornerCurve = .continuous
                layer.masksToBounds = true
                layer.backgroundColor = NSColor.clear.cgColor
            }
        }
        // 让窗口阴影按新的圆角形状重新生成，避免遗留矩形阴影残影。
        window.invalidateShadow()

        // borderless 窗口理论上已不渲染红绿灯，这里仍兜底处理一次：
        // frame 清零 + alpha 归零，杜绝任何残留命中区域。
        for button in [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ] {
            guard let button else { continue }
            button.isHidden = true
            button.alphaValue = 0
            button.frame = .zero
        }
    }
}
