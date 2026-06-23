# 产品里程碑

记录 Lo-Fi Music Box 从立项到当前版本的关键决策与里程碑，便于后续维护理解"为什么这么写"。

## v1.0.0（首个稳定版）

定位：提供轻量原生的 macOS 音乐盒体验，并在频道管理、可用性检测、视觉拟物化上做出明确设计。

### 架构

- 选择 Swift 6 原生 + SwiftUI + AppKit 互操作，放弃 KMP 等跨端方案优先打磨 macOS 体验。
- 频道维护使用纯本地 JSON（`Bundled / custom / overrides / hidden / health` 五个文件），其他偏好走 `UserDefaults`。
- `MenuBarExtra` + `WindowGroup` + `Settings` 三 Scene 结构，`init()` 中手动构造服务对象解决 `ScheduledHealthChecker` 弱引用 `PlaybackCoordinator` 的依赖关系。
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
- **菜单栏图标**：从最初的 `music.note / speaker.slash` 换成 `radio.fill / radio`，与应用图标的复古唱机主题保持一致；播放/暂停态用实心/线性区分。
- **顶部按钮布局**：左侧自绘 macOS 红绿灯样式 `[关闭][最小化]`（实心彩色圆点 + 同色系暗描边 + 顶部柔光，符号默认隐藏、悬停整组时浮现 ×/−，与系统行为一致），右侧保留 `[频道列表]` 快捷入口，原系统 traffic light 完全隐藏（`isHidden + frame=.zero + alphaValue=0`）。
- **频道列表**：滑入式 `StationListOverlay`，显示来源/标签/可用性图标，按"可用性 → 名称"排序，可关闭、可跳转到频道管理。
- **主界面布局升级（复古"电台控制台"）**：窗口高度 `220 → 248`，给信息区和控制台留呼吸空间。
  - 唱机与信息区间距 `12 → 18`，中间加一道上下渐隐的黄铜接缝竖线，信息区改为顶部对齐（修正之前标题居中"浮空"）。
  - 频道名支持最多两行 + `minimumScaleFactor(0.85)`；次级信息精简为"分类 · 协议类型"。
  - 标签下沉到主界面，用共享的 `FlowLayout`（SwiftUI `Layout` 协议，自动换行）铺成可换行胶囊，超过 `maxInlineTags(5)` 汇总为 `+N`；同时把 `StationManagementView` 里原有的私有 FlowLayout 合并到该共享组件。
  - 音量与传输控件合并为底部一块暗木"控制台"面板：上排黄铜调谐音量滑杆（米色刻度轨 + 黄铜旋钮，自绘取代系统 Slider），下排专注分钟胶囊 + 上一首/播放主键/下一首。播放主键为实心黄铜大圆钮、两侧为内凹金属圆钮，整体与唱机木质/黄铜质感统一（新增 `ConsoleControls.swift`）。
  - 因 `.offset` 不计入 SwiftUI 布局尺寸，唱机桌面投影自然掩于控制台面板之后，呈"唱机坐在控制台上"的观感；248 高度下各区域严丝合缝不裁切。
- **一体化木质机身（消除"两块木头"割裂感）**：上一版把唱机木箱和底部木质控制台做成了两个独立盒子，浮在深靛蓝玻璃背景上，材质割裂且与主题不协调。本版改为整机一体（对齐应用图标的实物语言）：
  - 整个小组件就是一台连续的木质机身（`woodConsoleSurface`：顶亮底暗木纹 + 顶面高光 + 前面板暗带 + 细木纹）。
  - `VinylRecordView` 新增 `embedded` 模式：去掉自身木箱外壳与桌面投影，只保留唱盘井 + 黑胶 + 唱针，让唱盘像直接嵌在机身顶面（唱针几何与换片动画完全不变）。
  - 频道名与标签放进嵌入木面的深色"显示屏"（`displayScreen`，沿用深靛蓝主题 + 黄铜外框 + 下陷内描边），深靛蓝主题由此延续而非铺满背景。
  - 顶面与前面板之间用一道蚀刻接缝（`consoleSeam`：暗线 + 木色高光线）过渡；音量/专注/传输控件直接坐落在同一块机身前面板上，不再是独立盒子。
  - 移除了上一版的独立木质 deck 背景和竖向黄铜分隔线，视觉语言统一到一体化木质机身。

### 频道管理与健康检测

- 频道增删改的核心是"内置覆盖只保存差异"——`StationRepository` 在合并时把 `BundledStations.json` 与 `bundled-overrides.json` 字段级合并，未修改的字段始终跟随上游内置数据更新。
- 隐藏的内置频道存 ID 列表，恢复时从隐藏列表移除即可。
- `StationHealthService`：MP3/HLS 用 HEAD 探针 + Range 兜底；M3U8 用 GET 看 manifest 是否包含 `#EXTM3U`；Bilibili 走与播放一致的解析探测（见 v1.0.1）。
- `ScheduledHealthChecker`：`Timer` 驱动的周期性检测，频率 `5 / 10 / 30 / 60` 分钟，可选"仅播放空闲时检测"避免占用网络。

### 应用图标流水线

- 用 Pillow 实现“保留原图 alpha 柔边 + 整图等比缩放 + 暖米色 macOS squircle 背景 + iconset PNG 无损压缩”的端到端脚本（`scripts/build-app-icon.sh`），见 [`docs/icon-pipeline.md`](icon-pipeline.md)。
- 关键决策：不再裁剪或二值化原图边缘，避免图标主体出现硬边/锯齿；自己画完整 squircle 背景，避免 macOS 自动叠加灰色容器。
- 当前打包流程已改为直接使用 `assets/AppIcon.icns` 中的定稿图标，`build-app-icon.sh` 只保留为图标文件校验入口。

### 打包

- `scripts/package-macos-app.sh`：Universal 2 `swift build -c release --arch arm64 --arch x86_64` → 组装 `.app` → ad-hoc `codesign` → `ditto` zip + `hdiutil create` UDZO dmg。
- 打包前会清理 `.build/` 和 `dist/`，并要求 `assets/AppIcon.icns` 已存在且非空；脚本不会自动生成或覆盖图标。
- 当前为 ad-hoc 签名，仅适合本机/内部分发。正式公开分发需切换 Developer ID 签名 + notarization。

## v1.0.1（哔哩哔哩直播原生播放 + 交互精修）

### 哔哩哔哩直播：从离屏 WebView 改为原生解析 HLS

- **问题根因**：B 站直播是网页里 flv.js(MSE) 播的 HTTP-FLV 流，而 native 版用离屏 `WKWebView(frame:.zero)`（从未加入视图层级）跑它——WebKit 离屏不启动媒体管线、且对 flv.js 兼容差，导致"能加载页面但没声音"。旧健康检测又只对页面发 GET 看 200，造成"检测正常却播不了"的假阳性。
- **方案（B+D）**：新增 `BilibiliStreamResolver`，用官方网页接口把直播间解析成 HLS 直链，交给 `AVPlayer` 原生播放，彻底移除 WebView。
  - 链路：`room_init`（入口号 → 真实 `room_id` + `live_status`）→ `getRoomPlayInfo(protocol=0,1&format=0,1,2&codec=0,1)` → 在 `http_hls` 里优先 `fmp4+avc`、回退 `ts+avc`、再回退任意 HLS → 拼 `host+base_url+extra`。
  - 实测确认：上述接口与解析出的 m3u8、init/媒体分片均无需登录 / cookie / wbi 签名 / Referer 即可获取；并用独立 Swift 脚本验证 `Decodable`(`convertFromSnakeCase`) 解析链路在运行期正确。
- **播放整合**：`PlaybackCoordinator` 对 `bilibili` 类型先解析再用 `AVStationPlayer.load(url:)` 播放，与 m3u8/mp3 共用同一播放器；加 `loadTask` 串行化，连续切台时取消上一个解析，避免旧台结果回灌。
- **健康检测升级（消除假阳性）**：`checkBilibili` 走与播放完全相同的解析链路——能解析出 HLS 才算"可用"；主播未开播明确标记"不可用 · 未开播"，其他解析失败也判不可用。
- **自动重连**：`AVStationPlayer` 增加播放进度看门狗 + 失败通知监听——直播流 `expires` 过期断流、网络停滞或播放失败时，回调 `PlaybackCoordinator` 重新走 `play`（B 站重新解析出新 HLS 直链，普通流重新拉起），带最小重连间隔防抖、仅在播放态触发。
- **显示与配置**：数显屏右上角不再显示平台名，改为简短"流类型徽标"（B 站直播标 `LIVE`，mp3/m3u8 标 `MP3`/`HLS`）；状态行新增最近一次健康检测的响应时延（ms）。频道管理"基础信息"补充三类音源说明（含哔哩哔哩直播间地址示例）。
- **动态频谱**：数显屏背景新增动态频谱可视化层（`SpectrumVisualizerBackground`，Canvas + TimelineView 绘制）。按频道风格（名称/分类/标签关键字推断 `energy`/`tempo`）模拟律动，中频段更活跃；播放时律动、暂停时经淡出包络平滑落回基线。为保证文字清晰，频谱条透明度下调并叠加顶部渐隐遮罩（只在屏底律动）；各条采用随机化的频率/相位组合，彼此不同步，律动更自然不规律。当前为风格化模拟（远程流 + AVPlayer 暂未接入实时 FFT）。
- **换盘面**：新增唱片盘面主题 `VinylFace`（6 款配色 + 印字：MUSIC / NIGHT / RUBY / FERN / ROSÉ / GOLD），通过造型独特的"迷你黑胶"按钮 `VinylFaceSwapButton` 循环切换。中央贴标随主题换色换字，切换时复用"抬针—换片—落针"动画，选择以 `@AppStorage` 持久化。纯视觉 / 情绪化功能，不影响播放。
- **直播流自动重连与平滑恢复**：`AVStationPlayer` 用“进度看门狗 + 失败通知”检测直播流过期 / 停滞 / 失败并回调 `PlaybackCoordinator` 重连；复用同一个 `AVPlayer`（`replaceCurrentItem`）换流、不再重建播放器（避免音频管线重置的爆音与延迟）；重连走无感路径（不切 `.loading`、显示屏不闪、不触发换片动画）；新流真正进入 `playing`（开始出声）后才以 0.6s 把音量从 0 淡入到目标（缓冲期间保持静音），把“卡顿→突兀全音量”变成平滑渐入；用 `targetVolume` 修掉重连后音量被重置的问题；开启 `automaticallyWaitsToMinimizeStalling` 并把停滞阈值调大到 16s 减少误重连，重连失败保持 `.playing` 交看门狗下周期重试。
- **已知限制**：B 站接口若改版（字段/签名要求变化）需同步更新解析逻辑。

### 唱机与控制台交互精修

- 唱盘改为俯视后倾透视以增强体量感；为避免透视把偏右的唱针斜掉，后倾只作用于唱盘组、唱针留在未倾斜图层，保证暂停时绝对竖直。
- 播放时唱针叠加"变幅循迹微摆"（双正弦包络，约 ±0.5°…±3°，`TimelineView` 逐帧驱动），并在盘面升起淡出的飘动音符。
- 右侧信息屏改为暖色"琥珀数显"风格（深棕黑底 + 扫描线 + 琥珀发光等宽字 + 黄铜框 + `ON AIR/PAUSED` 状态行），与木质机身同属暖色、消除蓝屏割裂。
- 音量滑杆新增 `mouseDownCanMoveWindow=false` 的 AppKit 交互层（`SliderScrubLayer`），修复 `isMovableByWindowBackground` 把拖动当成"拖窗口"导致"音量只能点不能拖"的问题；音量右侧数字读数改为一键静音键（`MuteToggleButton`，⌘M）。
- 底部新增随机频道键（`shuffle`，⌘R，仅在检测可用的频道里随机、排除当前台、带回退）；专注计时胶囊改为可点击重置（番茄钟式重复计时）。

## 后续可能的版本方向

- v1.1：全局快捷键（系统级 Hotkey 触发播放/切歌），不需要主窗口聚焦。
- v1.2：内置频道扩充（更多 BiliBili 直播 / 流行 Lofi 源），并引入更细的"频道分类"。
- v2.0：把业务核心抽到 KMP / Rust core，做 iOS / Linux / Windows 端拓展。
