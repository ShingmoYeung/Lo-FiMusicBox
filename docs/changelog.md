# 产品里程碑

记录 Lo-Fi Music Box 从立项到当前版本的关键决策与里程碑，便于后续维护理解"为什么这么写"。

## v1.0.0（开源稳定版）

定位：提供轻量原生的 macOS 音乐盒体验，并在频道管理、可用性检测、视觉拟物化、哔哩哔哩原生播放与检查更新上做出明确设计。

### 架构

- 选择 Swift 6 原生 + SwiftUI + AppKit 互操作，放弃 KMP 等跨端方案优先打磨 macOS 体验。
- 频道维护使用纯本地 JSON（`Bundled / custom / overrides / hidden / favorites / health` 六个文件），其他偏好走 `UserDefaults`。
- 自定义频道列表逐条解码：未知 `type` 只跳过该条，避免整份 `custom-stations.json` 加载失败。
- `MenuBarExtra` + `WindowGroup` + `Settings` 三 Scene 结构，`init()` 中手动构造服务对象解决 `ScheduledHealthChecker` 弱引用 `PlaybackCoordinator` 的依赖关系。
- 菜单栏小组件只允许一扇主窗：`CommandGroup(replacing: .newItem)` 禁用系统 ⌘N 新建；`MainWindowCoordinator` 会藏掉后来的 borderless 副本，关闭走本窗 `hideMainWindow(hostWindow)`。
- 界面只展示营销版本（如 `1.0.0`）；`CFBundleVersion` 仍写入 Info.plist，供打包/公证区分构建，不拼进关于页文案。
- 不引入第三方依赖，全部基于系统框架（AVFoundation、Combine、SwiftUI、AppKit）。

### 视觉与交互

- **frameless 圆角悬浮小组件**：通过 `WindowConfigurator` 把 `NSWindow.styleMask` 中的 `.titled` 拆掉，配合 `setFrame` + `min/maxSize` 锁死 360×248，再用 `CALayer.cornerRadius/cornerCurve` 让真实窗口边角与 SwiftUI 内容一起圆角化。期间踩过的坑：
  - `windowResizability(.contentSize)` 与 `setFrame` 互相反推，导致窗口高度在 220/248 抖动 → 移除该修饰符。
  - 移除 `.titled` 后窗口默认无法成为 key window，键盘快捷键失效 → 用 Objective-C 运行时 method swizzling 覆盖 `canBecomeKeyWindow`，仅对无 `.titled` 的窗口返回 `true`，不影响设置面板等其他窗口。
  - `ignoresSafeArea()` 必须放在所有装饰修饰符之后的最外层，否则会留下顶/底透明带。
- **3D 拟物唱机**（`VinylRecordView`）：黑胶 + 唱针 + 木箱底座，唱针角度规则——
  - 播放：+35°（贴向黑胶中心轨）；
  - 暂停：0°（垂直立在底座上）；
  - 切换频道："换片"动画 35° → 0°（停顿）→ 35°，带 spring，模拟现实换唱片。
  - 实现上使用 `Task` 管理动画序列与取消，避免快速连点切歌时动画堆叠。
- **菜单栏图标**：自绘 `MenuBarTurntableIcon`（`NSBezierPath` 唱机剪影），与应用图标主题一致；播放/暂停态用实心/线性区分。
- **顶部按钮布局**：左侧自绘 macOS 红绿灯样式 `[隐藏到菜单栏][最小化]`（实心彩色圆点 + 同色系暗描边 + 顶部柔光，符号默认隐藏、悬停整组时浮现 ×/−；红灯调用 `hideMainWindow`，不退出应用），右侧保留 `[频道列表]` 快捷入口，原系统 traffic light 完全隐藏（`isHidden + frame=.zero + alphaValue=0`）。
- **频道列表**：滑入式 `StationListOverlay`，显示来源/标签/可用性图标，按"可用性 → 名称"排序，可关闭；频道管理走设置面板（`⌘,`）。
- **主界面布局升级（复古"电台控制台"）**：窗口高度 `220 → 248`，给信息区和控制台留呼吸空间。
  - 唱机与信息区用 `mediumSpacing` 分隔，信息区顶部对齐；数显屏内频道名 / 副标题 / 标签均为单行 `MarqueeText`（过长横向滚动），避免撑高布局。
  - `FlowLayout` 仅用于频道管理编辑页的自定义标签编辑，不在主界面信息区铺胶囊。
  - 音量与传输控件合并为底部一块暗木"控制台"面板：上排黄铜调谐音量滑杆（米色刻度轨 + 黄铜旋钮，自绘取代系统 Slider），下排专注分钟胶囊 + 上一首/播放主键/下一首。播放主键为实心黄铜大圆钮、两侧为内凹金属圆钮，整体与唱机木质/黄铜质感统一（新增 `ConsoleControls.swift`）。
  - 因 `.offset` 不计入 SwiftUI 布局尺寸，唱机桌面投影自然掩于控制台面板之后，呈"唱机坐在控制台上"的观感；248 高度下各区域严丝合缝不裁切。
- **一体化木质机身（消除"两块木头"割裂感）**：上一版把唱机木箱和底部木质控制台做成了两个独立盒子，浮在深靛蓝玻璃背景上，材质割裂且与主题不协调。本版改为整机一体（对齐应用图标的实物语言）：
  - 整个小组件就是一台连续的木质机身（`woodConsoleSurface`：顶亮底暗木纹 + 顶面高光 + 前面板暗带 + 细木纹）。
  - `VinylRecordView` 新增 `embedded` 模式：去掉自身木箱外壳与桌面投影，只保留唱盘井 + 黑胶 + 唱针，让唱盘像直接嵌在机身顶面（唱针几何与换片动画完全不变）。
  - 频道名与标签放进嵌入木面的深色"显示屏"（`displayScreen`，沿用深靛蓝主题 + 黄铜外框 + 下陷内描边），深靛蓝主题由此延续而非铺满背景。
  - 顶面与前面板之间用一道蚀刻接缝（`consoleSeam`：暗线 + 木色高光线）过渡；音量/专注/传输控件直接坐落在同一块机身前面板上，不再是独立盒子。
  - 移除了上一版的独立木质 deck 背景和竖向黄铜分隔线，视觉语言统一到一体化木质机身。

### 唱机与控制台交互精修

- 唱盘改为俯视后倾透视以增强体量感；为避免透视把偏右的唱针斜掉，后倾只作用于唱盘组、唱针留在未倾斜图层，保证暂停时绝对竖直。
- 播放时唱针叠加"变幅循迹微摆"（双正弦包络，约 ±0.5°…±3°，`TimelineView` 逐帧驱动），并在盘面升起淡出的飘动音符。
- 右侧信息屏改为暖色"琥珀数显"风格（深棕黑底 + 扫描线 + 琥珀发光等宽字 + 黄铜框 + `ON AIR/PAUSED` 状态行），与木质机身同属暖色、消除蓝屏割裂。
- 音量滑杆新增 `mouseDownCanMoveWindow=false` 的 AppKit 交互层（`SliderScrubLayer`），修复 `isMovableByWindowBackground` 把拖动当成"拖窗口"导致"音量只能点不能拖"的问题；音量右侧数字读数改为一键静音键（`MuteToggleButton`，⌘M）。
- 底部新增随机频道键（`shuffle`，⌘R，仅在检测可用的频道里随机、排除当前台、带回退）；专注计时胶囊改为可点击重置（番茄钟式重复计时）。
- 数显屏右上角改为简短"流类型徽标"（B 站直播标 `LIVE`，mp3/m3u8 标 `MP3`/`HLS`）；状态行新增最近一次健康检测的响应时延（ms）。
- **动态频谱**：数显屏背景新增动态频谱可视化层（`SpectrumVisualizerBackground`，Canvas + TimelineView 绘制）。按频道风格（名称/分类/标签关键字推断 `energy`/`tempo`）模拟律动；播放时律动、暂停时经淡出包络平滑落回基线。当前为风格化模拟（远程流 + AVPlayer 暂未接入实时 FFT）。
- **换盘面**：新增唱片盘面主题 `VinylFace`（6 款配色 + 印字：MUSIC / NIGHT / RUBY / FERN / ROSÉ / GOLD），通过造型独特的"迷你黑胶"按钮 `VinylFaceSwapButton` 循环切换；选择以 `@AppStorage` 持久化。

### 频道管理与健康检测

- 频道增删改的核心是"内置覆盖只保存差异"——`StationRepository` 在合并时把 `BundledStations.json` 与 `bundled-overrides.json` 字段级合并，未修改的字段始终跟随上游内置数据更新。
- 隐藏的内置频道存 ID 列表，恢复时从隐藏列表移除即可。
- `StationHealthService`：MP3/HLS 用 HEAD 探针 + Range 兜底；M3U8 用 GET 看 manifest 是否包含 `#EXTM3U`；Bilibili 走与播放一致的解析探测。
- `ScheduledHealthChecker`：`Timer` 驱动的周期性检测，频率 `5 / 10 / 30 / 60` 分钟，可选"仅播放空闲时检测"避免占用网络。

### 哔哩哔哩直播：原生解析 HLS

- **问题根因**：B 站直播是网页里 flv.js(MSE) 播的 HTTP-FLV 流，而早期 native 版用离屏 `WKWebView` 跑它——WebKit 离屏不启动媒体管线、且对 flv.js 兼容差，导致"能加载页面但没声音"。旧健康检测又只对页面发 GET 看 200，造成"检测正常却播不了"的假阳性。
- **方案**：新增 `BilibiliStreamResolver`，用官方网页接口把直播间解析成 HLS 直链，交给 `AVPlayer` 原生播放，彻底移除 WebView。
  - 链路：`room_init`（入口号 → 真实 `room_id` + `live_status`）→ `getRoomPlayInfo` → 在 `http_hls` 里优先 `fmp4+avc`、回退 `ts+avc`、再回退任意 HLS。
  - 实测确认：上述接口与解析出的 m3u8、init/媒体分片均无需登录 / cookie / wbi 签名 / Referer 即可获取。
- **播放整合**：`PlaybackCoordinator` 对 `bilibili` 类型先解析再用 `AVStationPlayer.load(url:)` 播放，与 m3u8/mp3 共用同一播放器；加 `loadTask` 串行化，连续切台时取消上一个解析。
- **健康检测**：`checkBilibili` 走与播放完全相同的解析链路——能解析出 HLS 才算"可用"；主播未开播明确标记"不可用 · 未开播"。
- **自动重连与平滑恢复**：`AVStationPlayer` 用进度看门狗 + 失败通知检测直播流过期 / 停滞 / 失败并回调重连；复用同一个 `AVPlayer`（`replaceCurrentItem`）换流；重连走无感路径；新流真正进入 `playing` 后音量淡入；开启 `automaticallyWaitsToMinimizeStalling`。
- **已知限制**：B 站接口若改版（字段/签名要求变化）需同步更新解析逻辑。

### 检查更新（GitHub Releases）

- 仅查询 GitHub Releases `latest` API（`api.github.com/.../releases/latest`），解析 `tag_name` 与当前 `CFBundleShortVersionString` 比较；不提供应用内自动安装。
- 策略：关闭 / 启动时检查 / 周期性（日 / 周 / 月，默认每周）；后台发现新版本时用 `UserNotifications` 通知，手动检查用 `NSAlert`。
- 播放中不打断：有更新提示时延后到空闲再展示。
- 网络失败给出诚实自助文案（代理 / 重试 / 打开 Releases 页），不假装已检查成功。
- 全部更新相关 UI 收在 **设置 → 关于**；菜单栏保留系统「关于」同级的「检查更新」入口。

### 应用图标流水线

- 早期曾用 Pillow 做「原图 alpha 柔边 + 等比缩放 + squircle 背景 + iconset」生成；现已废弃该生成路径。
- 当前约定：定稿图标直接放在 `assets/AppIcon.icns`；`scripts/build-app-icon.sh` 与打包脚本只做存在性/非空校验，见 [`docs/icon-pipeline.md`](icon-pipeline.md)。

### 打包与清理

- `scripts/package-macos-app.sh`：Universal 2 `swift build -c release --arch arm64 --arch x86_64` → 组装 `.app` → ad-hoc `codesign` → `ditto` zip + `hdiutil create` UDZO dmg。
- 打包前通过 `scripts/clean-build-artifacts.sh` 清理 `.build/` 和 `dist/`，并要求 `assets/AppIcon.icns` 已存在且非空；脚本不会自动生成或覆盖图标。
- 清理脚本也可单独使用：`--build-only` / `--dist-only` / `--help`。
- 当前为 ad-hoc 签名，仅适合本机/内部分发。正式公开分发需切换 Developer ID 签名 + notarization。

## 后续可能的版本方向

- v1.1：全局快捷键（系统级 Hotkey 触发播放/切歌），不需要主窗口聚焦。
- v1.2：内置频道扩充（更多 BiliBili 直播 / 流行 Lofi 源），并引入更细的"频道分类"。
- v2.0：把业务核心抽到 KMP / Rust core，做 iOS / Linux / Windows 端拓展。
