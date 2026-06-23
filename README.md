# Lo-Fi Music Box（macOS）

Lo-Fi Music Box 是一个轻量原生的 macOS 桌面音乐盒小组件，围绕 Lo-Fi 电台播放、频道管理、可用性检测和专注计时打造。

## 项目目标

- **内置氛围频道**：内置 Lo-Fi / Chill / Loficafe 等频道，保留菜单栏入口、播放/暂停、专注时长统计等核心体验。
- **新增频道管理**：在不破坏内置频道数据的前提下，支持自定义新增、隐藏内置、覆盖内置（仅保存差异字段）的频道维护方式。
- **新增可用性检测**：单频道按需检测 + 全量批量检测 + 后台周期性自动检测，结果会反映在频道列表的可用性排序上。
- **macOS 原生体验**：复古唱机 3D 拟物交互、frameless 圆角悬浮小组件、菜单栏常驻入口、`Cmd+,` 偏好设置面板。

## 功能亮点

- **3D 拟物唱机**：黑胶旋转、唱针带 3D 透视的"抬-落"动画，播放时唱针贴向黑胶中央、暂停时垂直立在底座上。
- **切歌"换片"动画**：上一首/下一首/切换频道时，唱针先抬到垂直中位、停顿，然后落回播放姿态——模拟现实换唱片体验。
- **frameless 悬浮小组件**：360×248 圆角窗口，无系统 titlebar、无底部透明带、整窗可拖拽，自绘 macOS 红绿灯按钮收纳到顶部，与系统习惯一致。
- **一体化复古木质唱机**：整个小组件是一台连续的木质机身（对齐应用图标的实物语言）——唱盘嵌在机身顶面、频道名与标签显示在嵌入木面的深色"显示屏"上（深靛蓝主题延续于此）、黄铜音量调谐与播放/切台控件做在同一台机身的前面板上。
- **菜单栏常驻**：`MenuBarExtra` 固定一个复古收音机图标（`radio.fill` / `radio` 区分播放/暂停），下拉菜单可一键切到任意频道。
- **频道管理面板**：`Cmd+,` 打开设置面板，集中管理通用、频道、数据、可用性检测与关于信息。
- **健康检测**：HEAD/GET 探针 + HLS manifest 校验；可选 `5 / 10 / 30 / 60 分钟` 自动间隔，可选"仅播放空闲时检测"。
- **专注时长统计**：每分钟 tick 累计今日/历史专注分钟数，菜单栏直接显示当日时长，保留近 90 天历史。

## 技术栈

| 维度 | 选型 | 备注 |
| --- | --- | --- |
| 主语言 | Swift 6 | 使用 Swift 6 并发检查 |
| Package 工具 | SwiftPM tools-version `6.0` | 不锁死过新的包描述能力 |
| 集成开发 | Xcode 26.x | 仅 IDE 调试需要，命令行 `swift build` 也能完整构建 |
| 部署目标 | macOS 14+ | 覆盖 SwiftUI、`MenuBarExtra`、AVFoundation 等原生能力 |
| UI | SwiftUI + AppKit 互操作 | SwiftUI 主体，AppKit 用于 `NSWindow` 自定义、菜单栏 |
| 播放 | AVFoundation | MP3/HLS 直接走 `AVPlayer`，Bilibili 直播先解析为 HLS 再走 `AVPlayer` |
| 第三方依赖 | 无 | 仅依赖系统框架，便于打包、签名和产出 Universal 2 |

## 目录结构

```
LoFiMusicBox/
├── Package.swift
├── README.md                          # 本文档
├── docs/                              # 详细设计与流水线文档
│   ├── icon-pipeline.md               # 应用图标资源约定
│   └── changelog.md                   # 产品里程碑
├── scripts/
│   ├── build-app-icon.sh              # 校验 assets/AppIcon.icns 是否就绪
│   └── package-macos-app.sh           # Universal 2 SwiftPM build + .app + zip + dmg
├── assets/                             # 已定稿的 AppIcon.icns（不随 SwiftPM 资源包分发）
├── dist/                              # 打包产物（打包脚本会清空重建）
└── Sources/LoFiMusicBox/
    ├── LoFiMusicBoxApp.swift       # @main 入口，组装服务和 Scene
    ├── Models/
    │   └── Station.swift              # Station / 来源 / 健康状态模型
    ├── Persistence/
    │   └── StationRepository.swift    # 多 JSON 文件合并与持久化
    ├── Playback/
    │   ├── StationPlayer.swift        # 播放器协议
    │   ├── AVStationPlayer.swift      # MP3 / HLS / Bilibili 解析后 HLS 播放
    │   └── PlaybackCoordinator.swift  # UI 与菜单栏共享的播放协调器
    ├── Services/
    │   ├── AppDelegate.swift           # AppKit 生命周期桥接
    │   ├── AppSettingsStore.swift     # UserDefaults 偏好（音量、上次频道、检测设置）
    │   ├── BilibiliStreamResolver.swift # Bilibili 直播间解析为 HLS 直链
    │   ├── FocusTimeService.swift     # 专注时长统计
    │   ├── MainWindowCoordinator.swift # 主窗口显示/隐藏与菜单栏模式协调
    │   ├── StationHealthService.swift # 单频道可用性检测
    │   └── ScheduledHealthChecker.swift # 周期性自动检测
    ├── Support/
    │   ├── AppConstants.swift         # 全部业务/UI 常量集中地
    │   ├── AppResourceBundle.swift    # SwiftPM 资源包运行时定位
    │   └── LocalizedStrings.swift     # 本地化字符串读取
    ├── Resources/
    │   ├── BundledStations.json       # 内置频道（只读）
    │   ├── en.lproj/                  # 英文本地化
    │   ├── zh-Hans.lproj/             # 简体中文本地化
    │   ├── zh-HK.lproj/               # 香港繁体本地化
    │   └── zh-Hant.lproj/             # 繁体中文本地化
    └── UI/
        ├── PlayerTheme.swift          # 颜色、圆角、阴影、黄铜/木质控制台主题
        ├── WindowConfigurator.swift   # NSWindow frameless / borderless 自定义
        ├── ContentView.swift          # 主小组件视图
        ├── VinylRecordView.swift      # 3D 唱机 + 唱针动画
        ├── ConsoleControls.swift      # 黄铜音量滑杆 + 传输圆钮 + 播放主键
        ├── FlowLayout.swift           # 自动换行的流式布局（标签胶囊共用）
        ├── InteractiveCursor.swift    # 交互控件手形光标修饰器
        ├── StationListOverlay.swift   # 频道切换覆盖层
        ├── SettingsView.swift         # `Cmd+,` 五页设置（通用/频道/数据/可用性/关于）
        ├── StationManagementView.swift # 频道增删改 / 检测
        └── HealthCheckSettingsView.swift # 可用性检测开关 / 频率 / 立即检测
```

## 数据持久化

频道维护使用本地 JSON 文件（不引入 SQLite，原因是数据量小、便于调试和备份）：

| 文件 | 位置 | 内容 |
| --- | --- | --- |
| `BundledStations.json` | App 资源（只读） | 内置频道原始数据 |
| `custom-stations.json` | `~/Library/Application Support/Lo-Fi Music Box/` | 用户新增的自定义频道 |
| `bundled-overrides.json` | 同上 | 用户对内置频道的字段级修改（仅保存差异） |
| `hidden-bundled-ids.json` | 同上 | 用户隐藏的内置频道 ID 列表 |
| `favorite-station-ids.json` | 同上 | 用户收藏的频道 ID 列表 |
| `station-health.json` | 同上 | 各频道最近一次可用性检测结果 |

轻量偏好走 `UserDefaults`：上次频道 ID、音量、可用性检测开关/频率/空闲条件、近 90 天专注历史等。

## 键盘快捷键

主小组件聚焦时（`MenuBarExtra` 不抢焦点，主窗口需要 `WindowConfigurator` 中的 `canBecomeKeyWindow` swizzle 才能接收键盘事件）：

| 按键 | 行为 |
| --- | --- |
| `Space` | 播放 / 暂停 |
| `←` | 上一首 |
| `→` | 下一首 |
| `Cmd+,` | 打开偏好设置（频道管理 / 健康检测 / 关于） |
| `Cmd+N` | 频道管理面板内新建自定义频道 |
| `Cmd+W` | 关闭弹出对话框 |

## 应用图标

打包直接使用 `assets/AppIcon.icns` 中已经定稿的应用图标，不再通过脚本从 PNG 生成或覆盖图标文件。`scripts/build-app-icon.sh` 仅作为兼容入口保留，用来校验 `assets/AppIcon.icns` 是否存在且非空。

图标资源约定见 [`docs/icon-pipeline.md`](docs/icon-pipeline.md)。

```bash
# 校验默认图标
./scripts/build-app-icon.sh
```

## 运行

```bash
cd LoFiMusicBox
swift run
```

## 打包

```bash
cd LoFiMusicBox
./scripts/package-macos-app.sh
```

打包产物（每次打包前会清空 `.build/` 和 `dist/` 后重新生成）：

- 程序：`dist/Lo-Fi Music Box.app`
- 压缩包：`dist/LoFiMusicBox-macOS.zip`
- 安装镜像：`dist/LoFiMusicBox-macOS.dmg`

打包流程：

1. 校验 `assets/AppIcon.icns` 已存在且非空；
2. 清理 `.build/` 和 `dist/`，确保中间产物、缓存和上次包产物不会复用；
3. `swift build -c release --arch arm64 --arch x86_64` 产出 Universal 2 release 二进制；
4. 组装 `.app` bundle（含 `Info.plist`、`CFBundleIconFile=AppIcon`），并复制 `assets/AppIcon.icns`；
5. 通过 `lipo -info` 校验主程序同时包含 `arm64` 与 `x86_64`；
6. `codesign --force --deep --sign -` 进行 ad-hoc 签名（适合本机分发，正式公开分发时需要换成 Developer ID 签名 + notarization）；
7. `ditto` 输出 zip、`hdiutil create` 输出 UDZO 压缩 dmg。

## 开发约定

- 变量与方法命名要表达业务含义，不使用含糊缩写。
- 业务代码不直写魔法值，新常量统一进 `Support/AppConstants.swift`。
- 不直观的逻辑加中文注释（例如 Bilibili 用静音替代真正暂停的原因、`canBecomeKeyWindow` swizzle 的必要性、唱针角度选择背后的视觉考量）。
- Markdown 文档使用中文编写，便于持续记录产品与技术决策。

## 后续工作（参考）

- Developer ID 签名 + notarization 公证，支持 dmg 公开分发；
- 增加 macOS 全局快捷键（系统级 Hotkey 触发播放/暂停/切歌）；
- 把内置频道扩到 BiliBili 直播之外的更多可定制源（用户已经能自行添加，只是默认池可以更丰富）；
- 长期：考虑共享业务逻辑层到 KMP / Rust core，为后续 iOS / Linux / Windows 拓展打底。
