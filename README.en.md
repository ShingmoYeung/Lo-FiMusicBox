# Lo-Fi Music Box

> English · [中文](README.md)

<p align="center">
  <img src="docs/images/lo-fi-music-box-icon.png" alt="Lo-Fi Music Box" width="180" />
</p>

<p align="center">
  A tiny retro-turntable music box that lives on your macOS desktop.
</p>

<p align="center">
  <a href="#-download--install"><img alt="Version" src="https://img.shields.io/badge/version-1.0.0-c48a5b?style=flat-square"></a>
  <a href="#-license"><img alt="License" src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square"></a>
  <a href="#"><img alt="macOS" src="https://img.shields.io/badge/macOS-14%2B-lightgrey.svg?style=flat-square"></a>
  <a href="#"><img alt="Swift" src="https://img.shields.io/badge/Swift-6-orange.svg?style=flat-square"></a>
  <a href="#"><img alt="Universal 2" src="https://img.shields.io/badge/Universal%202-arm64%20%2B%20x86__64-brightgreen.svg?style=flat-square"></a>
</p>

Lo-Fi Music Box is a macOS widget built with SwiftUI + AppKit for focus-friendly ambient radio: bundled Lo-Fi / Chill stations, custom MP3 streams / HLS / Bilibili live rooms, a 3D turntable, a menu bar entry, station health checks, and a pomodoro-style focus timer.

Zero third-party dependencies — AVFoundation + SwiftUI + AppKit only. The packaged result is a double-clickable `.app`.

---

## Contents

- [Features](#-features)
- [Screenshots](#-screenshots)
- [Download & install](#-download--install)
- [Build from source](#-build-from-source)
- [Data & preferences](#-data--preferences)
- [Keyboard shortcuts](#-keyboard-shortcuts)
- [Project layout](#-project-layout)
- [Development notes](#-development-notes)
- [Roadmap](#-roadmap)
- [Support the project](#-support-the-project)
- [License](#-license)

---

## ✨ Features

- **One-piece retro turntable**: the whole window is a continuous wood chassis — platter on top, amber display for station info, brass console on the front panel.
- **3D cue / change animation**: vinyl spin plus a lift–pause–drop tonearm when switching stations.
- **Menu bar presence**: a `MenuBarExtra` radio icon with quick station switching; the main window stays frameless and floating.
- **Station manager**: `Cmd+,` opens Settings — add/edit custom stations, edit or hide bundled ones. Bundled edits store diffs only so upgrades keep your changes.
- **Health checks**: per-station, batch, and scheduled background checks (`5 / 10 / 30 / 60` minutes; optional “only when idle”). Results drive station sorting.
- **Native Bilibili live playback**: paste a live room URL; the app resolves an HLS URL for AVPlayer. Offline rooms are marked unavailable honestly.
- **Focus minutes**: per-minute ticks for today / history; menu bar shows today’s total; ~90 days retained; the capsule resets like a pomodoro timer.
- **Vinyl face themes**: six platter looks (`MUSIC / NIGHT / RUBY / FERN / ROSÉ / GOLD`) with the same lift–change–drop animation.
- **Localization**: Simplified Chinese, Traditional Chinese (Taiwan / Hong Kong), and English — switch live.
- **Check for updates**: queries GitHub Releases for the latest tag. Configure off / on launch / periodic (daily / weekly / monthly) under **Settings → About**, or use the menu bar item. Newer versions notify or alert and open Releases — no in-app auto-install. Network failures get honest self-help copy.

## 📸 Screenshots

<p align="center">
  <img src="docs/images/menubar-turntable-preview.png" alt="Menu bar turntable preview" width="720" />
</p>

(More main UI / station manager / Settings shots welcome — put them under `docs/images/preview/` in a PR.)

## 📦 Download & install

Builds use **ad-hoc signing** (`codesign -`) and are not notarized. On first open you may need **System Settings → Privacy & Security → Open Anyway**. That is normal for open-source macOS apps until Developer ID + notarization lands.

- Download `LoFiMusicBox-macOS.zip` or the `.dmg` from [GitHub Releases](https://github.com/ShingmoYeung/Lo-FiMusicBox/releases), then drag `Lo-Fi Music Box.app` into `/Applications`.
- Or [build from source](#-build-from-source); artifacts land in `dist/`.

**Requirements:** macOS 14+ (Universal 2 — Apple Silicon and Intel).

## 🛠 Build from source

Requirements:

- macOS 14+
- Xcode 26.x (Swift 6 toolchain); `swift build` works from the CLI without opening Xcode.

```bash
git clone https://github.com/ShingmoYeung/Lo-FiMusicBox.git
cd LoFiMusicBox

./scripts/clean-build-artifacts.sh

swift run

./scripts/package-macos-app.sh
./scripts/package-macos-app.sh --no-dmg
```

The package script:

1. Checks that `assets/AppIcon.icns` exists and is non-empty.
2. Runs `./scripts/clean-build-artifacts.sh` to clear `.build/` and `dist/`.
3. Builds Universal 2 release: `swift build -c release --arch arm64 --arch x86_64`.
4. Assembles the `.app` (Info.plist + `CFBundleIconFile=AppIcon`) and copies the icon.
5. Ad-hoc signs with `codesign --force --deep --sign -`.
6. Zips with `ditto`.
7. Creates a drag-to-Applications UDZO DMG (`.app` + symlink to `/Applications`).

Clean artifacts alone:

```bash
./scripts/clean-build-artifacts.sh
./scripts/clean-build-artifacts.sh --build-only
./scripts/clean-build-artifacts.sh --dist-only
```

The package script does **not** overwrite an existing app in `/Applications` — install by dragging from the DMG.

## 💾 Data & preferences

Stations are plain JSON (easy to back up and diff; no SQLite):

| File | Location | Contents |
| --- | --- | --- |
| `BundledStations.json` | App resources (read-only) | Bundled stations |
| `custom-stations.json` | `~/Library/Application Support/Lo-Fi Music Box/` | Your custom stations |
| `bundled-overrides.json` | same | Field-level diffs for bundled stations |
| `hidden-bundled-ids.json` | same | Hidden bundled station IDs |
| `favorite-station-ids.json` | same | Favorites |
| `station-health.json` | same | Last health-check result per station |

Lightweight prefs use `UserDefaults`: last station, volume, health-check settings, ~90 days of focus history.

**Settings → Data** can open the folder in Finder, copy the path, and export/import custom station JSON.

## ⌨️ Keyboard shortcuts

When the main widget is key (the menu bar extra does not steal focus; `canBecomeKeyWindow` is swizzled for the frameless window):

| Key | Action |
| --- | --- |
| `Space` | Play / pause |
| `←` | Previous |
| `→` | Next |
| `⌘ M` | Mute / unmute |
| `⌘ R` | Random available station |
| `⌘ ,` | Preferences |
| `⌘ N` | New custom station (in station manager) |
| `⌘ W` | Close dialog |

## 🗂 Project layout

```
LoFiMusicBox/
├── Package.swift
├── README.md                     # Chinese (primary)
├── README.en.md                  # This file
├── CHANGELOG.md
├── LICENSE
├── docs/
│   ├── changelog.md              # Detailed product / tech milestones
│   ├── icon-pipeline.md
│   └── images/
├── scripts/
│   ├── build-app-icon.sh
│   ├── clean-build-artifacts.sh
│   └── package-macos-app.sh
├── assets/                       # Final AppIcon.icns
├── dist/                         # Package output
└── Sources/LoFiMusicBox/
    ├── LoFiMusicBoxApp.swift
    ├── Models/
    ├── Persistence/
    ├── Playback/
    ├── Services/                 # Health, Bilibili resolve, focus, updates, …
    ├── Support/
    ├── Resources/
    └── UI/
```

## 🧭 Development notes

- Prefer meaningful names over opaque abbreviations.
- Keep magic values out of business code — add constants in `Support/AppConstants.swift`.
- Non-obvious logic gets comments explaining *why* (e.g. `canBecomeKeyWindow` swizzle, reusing one `AVPlayer` via `replaceCurrentItem`).
- Milestone archive: [`docs/changelog.md`](docs/changelog.md). User-facing notes: [`CHANGELOG.md`](CHANGELOG.md). Release tag: `v1.0.0`.

## 🛣 Roadmap

- [ ] Developer ID signing + notarization for public DMG distribution
- [ ] System-wide hotkeys for play / pause / skip without focusing the window
- [ ] Richer bundled station pool (more Lo-Fi / study / sleep / Bilibili presets)
- [ ] Revisit YouTube via local download + remux into AVPlayer — removed in v1.0.0 due to DASH / AVFoundation limits; see [`CHANGELOG.md`](CHANGELOG.md)
- [ ] Longer term: extract a KMP / Rust core for iOS / Linux / Windows

## ❤️ Support the project

If the music box brightens your workday, a coffee helps keep maintenance, station pools, and notarization moving. Donation QR codes (Alipay / WeChat) live in the [Chinese README](README.md#-赞赏支持) and under [`docs/images/donate/`](docs/images/donate/).

## 📄 License

Lo-Fi Music Box is released under the **MIT License** — see [`LICENSE`](LICENSE). Use it personally or commercially; keep the original copyright notice.

---

<p align="center">
  Built with SwiftUI · AppKit · AVFoundation.<br/>
  If you like it, please ⭐️ the repo — it truly helps.
</p>
