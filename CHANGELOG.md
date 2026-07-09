# Changelog

本文件记录 Lo-Fi Music Box 面向用户的每个版本变化。更细的产品/技术决策档案见 [`docs/changelog.md`](docs/changelog.md)。

约定：格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

---

## [1.0.0] - 2026-07-01

Lo-Fi Music Box 的首个**开源稳定版**：确定"轻量原生 macOS 音乐盒"的边界，把音源收敛到系统 AVFoundation 能直接稳定播放的三类，并配套完成频道管理、可用性检测、专注计时、多语言、一体化复古 UI、Universal 2 打包与自动化安装脚本。

### ✨ 新增

- **开源发布**：仓库以 MIT 协议开源，新增根级 `LICENSE`、`CHANGELOG.md`，README 重写为面向社区的 v1.0.0 版本，加入下载/构建说明与赞赏支持入口。
- **检查更新**：从 GitHub Releases 查询最新版本；可在设置 → 关于中配置关闭 / 启动时检查 / 周期性检查（日 / 周 / 月），菜单栏提供同级「检查更新」入口。发现新版本时通知或弹窗提示，并引导打开 Releases；不提供应用内自动安装。网络不可达时给出诚实的自助说明。
- **拖入 Applications 式 DMG**：`scripts/package-macos-app.sh` 生成的 dmg 内同时包含 `.app` 和指向系统 `/Applications` 的软链接，用户双击 dmg 后把 App 拖到 Applications 图标上即可完成安装——这是 macOS 用户对开源应用分发的通用预期。脚本不再自动接管 `/Applications`；`--no-dmg` 保留给本地快速迭代使用。
- **频道支持组件总览**：设置面板 → 通用页新增"频道支持组件总览"表，一目了然告诉用户"这一版承诺的三类音源都无需外部依赖"。

### 📚 文档

- 重写 `README.md`：功能亮点 / 截图 / 下载与安装 / 从源码构建 / 数据与偏好 / 快捷键 / 项目结构 / 开发约定 / 路线图 / 赞赏支持 / MIT 协议。
- 新增 `LICENSE`（MIT）。
- 新增 `docs/images/donate/README.md` 作为微信赞赏码占位与命名说明，方便你把 `wechat.png` 直接放进去覆盖。
- `docs/changelog.md` 保留为面向开发者的详细里程碑档案，本文件（根级 `CHANGELOG.md`）面向用户。

### 📦 打包

- 打包脚本已就位：`scripts/package-macos-app.sh [--no-dmg]`，产物包含 `.app` / zip / 拖入 Applications 式 dmg。
- 打包前通过 `scripts/clean-build-artifacts.sh` 清理 `.build/` 与 `dist/`；也可单独用 `--build-only` / `--dist-only` 清理。
- ad-hoc `codesign` 用于本机 / 开源分发；正式公开分发建议切换 Developer ID 签名 + notarization（列在 Roadmap）。

---

## 关于预研阶段

开源首发前的内部预研没有单独对外发版号。哔哩哔哩直播原生播放、复古一体化 UI、频道健康检测、动态频谱等演进细节保留在 [`docs/changelog.md`](docs/changelog.md) 的 **v1.0.0** 里程碑分节中，供想要理解"为什么这么写"的贡献者参考。GitHub Release / tag 约定为 `v1.0.0`。
