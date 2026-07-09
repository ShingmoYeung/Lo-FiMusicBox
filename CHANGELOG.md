# Changelog

本文件记录 Lo-Fi Music Box 面向用户的每个版本变化。更细的产品/技术决策档案见 [`docs/changelog.md`](docs/changelog.md)。

约定：格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

---

## [1.0.0] - 2026-07-01

Lo-Fi Music Box 的首个**开源稳定版**：确定"轻量原生 macOS 音乐盒"的边界，把音源收敛到系统 AVFoundation 能直接稳定播放的三类，并配套完成频道管理、可用性检测、专注计时、多语言、一体化复古 UI、Universal 2 打包与自动化安装脚本。

### ✨ 新增

- **开源发布**：仓库以 MIT 协议开源，新增根级 `LICENSE`、`CHANGELOG.md`，README 重写为面向社区的 v1.0.0 版本，加入下载/构建/贡献路径与赞赏支持入口。
- **检查更新**：从 GitHub Releases 查询最新版本；可在设置 → 关于中配置关闭 / 启动时检查 / 周期性检查（日 / 周 / 月），菜单栏提供同级「检查更新」入口。发现新版本时通知或弹窗提示，并引导打开 Releases；不提供应用内自动安装。网络不可达时给出诚实的自助说明。
- **拖入 Applications 式 DMG**：`scripts/package-macos-app.sh` 生成的 dmg 内同时包含 `.app` 和指向系统 `/Applications` 的软链接，用户双击 dmg 后把 App 拖到 Applications 图标上即可完成安装——这是 macOS 用户对开源应用分发的通用预期。脚本不再自动接管 `/Applications`；`--no-dmg` 保留给本地快速迭代使用。
- **频道支持组件总览**：设置面板 → 通用页新增"频道支持组件总览"表，一目了然告诉用户"这一版承诺的三类音源都无需外部依赖"。
- **旧数据向后兼容**：`Station.init(from:)` 遇到旧版 `custom-stations.json` 里的 `type: "youtube"` 时不再解码失败——自动降级为 `mp3` 并在健康状态里附一条中文说明，提示用户在【频道管理】里删除或改成其他协议，避免整份 JSON 无法加载导致用户丢失全部自定义频道。

### 🔄 变更

- **移除 YouTube 频道支持**（详见下方"⚠️ 破坏性变更"）。
- **HLS / MP3 / 哔哩哔哩** 三类频道保持原有交互，全部通过系统 `AVPlayer` 原生播放，不需要任何外部工具。
- 【频道管理】的 URL 帮助文字与设置面板的说明文案统一收敛到"三类系统原生可播音源、无需外部依赖"。
- Localizable.strings（4 种语言）全量清理 YouTube / yt-dlp / ffmpeg 相关键，并新增 `station.health.message.deprecated_youtube` 说明。

### ⚠️ 破坏性变更

- **移除 YouTube 频道类型 (`StationType.youtube`) 及其解析/健康检测/设置 UI**：
  - 删除 `Services/YouTubeStreamResolver.swift`；
  - 从 `PlaybackCoordinator` 中移除 `loadYouTube` 与 `youtubeResolver`；
  - 从 `StationHealthService` 中移除 `checkYouTube` 与配套的重试请求；
  - `AVStationPlayer.load` 不再需要 `httpHeaders` / `waitUntilReady`，`load(url:fadeIn:)` 回到最小可用形态；
  - 设置面板不再有"YouTube 支持"区块、安装帮助 popover、yt-dlp 状态检测；
  - 依赖矩阵从 4 行收敛为 3 行（HLS / MP3 / Bilibili）；
  - `AppConstants.YouTube.*`、`YouTube` 枚举、`dashContainerMarker`、`itemReadyTimeoutSeconds` 全部删除。
- **移除的原因**：v0.x 曾以"用户本机安装 `yt-dlp`，App 通过 `yt-dlp --print '%(url)s'` 解析出 googlevideo CDN 音频直链、再喂给 AVPlayer 流播"实现 YouTube 支持。多轮实测发现：
  1. googlevideo 常返回 **DASH 分片式音频容器（`m4a_dash`）**，AVFoundation 无法直接解封装，`AVPlayerItem.status` 会长时间卡在 `.unknown`；
  2. 命中"AVPlayer 原生可播"的 HLS / progressive MP4 格式在打包 App（相对独立进程 / 沙箱 / CFNetwork）内的行为不如命令行进程稳定，独立 `swift run` 探针能起播，同一 URL 在应用内会长期停留在"LOADING TAPE"；
  3. `ffmpeg` 在 App 的"边解析边流播"架构下**不会**被 `yt-dlp` 调用（仅在下载 + remux 流程里生效），装了 `ffmpeg` 也无法救场——这是我们上一版曾误导过用户的地方，本版一并纠正；
  4. 稳定地播 YouTube 要走"App 内 `yt-dlp` 全量下载 → `ffmpeg` remux → 本地文件喂给 AVPlayer"的方案，起播延迟从秒级变成分钟级，与"氛围电台"的核心体验不符，也丢失了直播/长视频价值。
- 综合以上，v1.0.0 决定收敛到"AVFoundation 直接稳定可播"的能力边界；YouTube 支持不算被"放弃"，而是列在 Roadmap 里、留待后续以完全不同的架构（本地缓冲 + remux + 播放器）重新评估。旧的 `type: "youtube"` 自定义频道会被自动降级并给出明确提示，不会导致 crash 或数据丢失。

### 📚 文档

- 重写 `README.md`：功能亮点 / 截图 / 下载与安装 / 从源码构建 / 数据与偏好 / 快捷键 / 项目结构 / 开发约定 / 路线图 / 赞赏支持 / MIT 协议。
- 新增 `LICENSE`（MIT）。
- 新增 `docs/images/donate/README.md` 作为二维码占位与命名说明，方便你把 `alipay.png` / `wechat.png` 直接放进去覆盖。
- `docs/changelog.md` 保留为面向开发者的详细里程碑档案，本文件（根级 `CHANGELOG.md`）面向用户。

### 📦 打包

- 打包脚本已就位：`scripts/package-macos-app.sh [--no-dmg]`，产物包含 `.app` / zip / 拖入 Applications 式 dmg。
- 打包前通过 `scripts/clean-build-artifacts.sh` 清理 `.build/` 与 `dist/`；也可单独用 `--build-only` / `--dist-only` 清理。
- ad-hoc `codesign` 用于本机 / 开源分发；正式公开分发建议切换 Developer ID 签名 + notarization（列在 Roadmap）。

---

## 关于预研阶段

开源首发前的内部预研没有单独对外发版号。哔哩哔哩直播原生播放、复古一体化 UI、频道健康检测、动态频谱等演进细节保留在 [`docs/changelog.md`](docs/changelog.md) 的 **v1.0.0** 里程碑分节中，供想要理解"为什么这么写"的贡献者参考。GitHub Release / tag 约定为 `v1.0.0`。
