#!/usr/bin/env bash
set -euo pipefail

# 该脚本把 SwiftPM 的 release 可执行文件组装成标准 macOS .app 程序包。
# 目前使用 ad-hoc 签名，适合本机运行和开源分发；正式公开分发时可接入 Developer ID 签名 + notarization。
#
# 打包产物：
#   dist/Lo-Fi Music Box.app          可直接双击运行的 .app
#   dist/LoFiMusicBox-macOS.zip       .app 的 zip 归档
#   dist/LoFiMusicBox-macOS.dmg       标准"拖入 Applications"式 DMG：
#                                     双击后 Finder 打开的窗口里同时有 .app 与 /Applications 快捷方式，
#                                     直接把 App 拖到 Applications 图标上完成安装。
#
# 该脚本**不会**改动 /Applications 里已有的 App 版本；安装动作留给用户在 DMG 里手动完成，
# 符合 macOS 用户对开源应用分发的通用预期，也避免脚本悄悄接管系统目录。
#
# 可选参数：
#   --no-dmg          跳过生成 dmg 镜像（本地快速迭代时使用；仍会生成 .app 和 zip）。
#   -h, --help        显示帮助后退出。

GENERATE_DMG=1
for arg in "$@"; do
    case "${arg}" in
        --no-dmg)
            GENERATE_DMG=0
            ;;
        -h|--help)
            awk '
                NR == 1 { next }
                started && !/^#/ { exit }
                /^#/ {
                    started = 1
                    sub(/^# ?/, "")
                    print
                }
            ' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *)
            echo "未知参数：${arg}" >&2
            exit 1
            ;;
    esac
done

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLEAN_SCRIPT="${PROJECT_ROOT}/scripts/clean-build-artifacts.sh"
APP_DISPLAY_NAME="Lo-Fi Music Box"
EXECUTABLE_NAME="LoFiMusicBox"
BUNDLE_IDENTIFIER="app.lofimusicbox.desktop"
APP_VERSION="1.0.0"
BUILD_VERSION="1"
BUILD_ARCHS=("arm64" "x86_64")
SWIFT_BUILD_ARGS=(-c release)
for arch in "${BUILD_ARCHS[@]}"; do
    SWIFT_BUILD_ARGS+=(--arch "${arch}")
done
RESOURCE_BUNDLE_NAME="LoFiMusicBox_LoFiMusicBox.bundle"
BUILD_DIRECTORY="${PROJECT_ROOT}/.build"
DIST_DIRECTORY="${PROJECT_ROOT}/dist"
APP_BUNDLE_PATH="${DIST_DIRECTORY}/${APP_DISPLAY_NAME}.app"
CONTENTS_DIRECTORY="${APP_BUNDLE_PATH}/Contents"
MACOS_DIRECTORY="${CONTENTS_DIRECTORY}/MacOS"
RESOURCES_DIRECTORY="${CONTENTS_DIRECTORY}/Resources"
APP_RESOURCE_BUNDLE_PATH="${RESOURCES_DIRECTORY}/${RESOURCE_BUNDLE_NAME}"
ZIP_PATH="${DIST_DIRECTORY}/LoFiMusicBox-macOS.zip"
DMG_PATH="${DIST_DIRECTORY}/LoFiMusicBox-macOS.dmg"
# 应用图标直接使用 assets/AppIcon.icns。打包脚本只复制现成图标，不再生成或改写图标素材。
APP_ICON_SOURCE="${PROJECT_ROOT}/assets/AppIcon.icns"
APP_ICON_BUNDLE_NAME="AppIcon.icns"
APP_ICON_KEY_NAME="AppIcon"

validate_app_icon() {
    local icon_path="$1"
    local work_dir

    case "${icon_path}" in
        *.icns) ;;
        *)
            echo "错误：应用图标必须是 .icns 文件：${icon_path}" >&2
            exit 1
            ;;
    esac

    work_dir="$(mktemp -d)"
    if ! iconutil -c iconset "${icon_path}" -o "${work_dir}/AppIcon.iconset" >/dev/null 2>&1; then
        rm -rf "${work_dir}"
        echo "错误：应用图标不是有效的 .icns 文件：${icon_path}" >&2
        echo "请不要把 PNG 直接改名为 .icns；需要使用真正的 Apple Icon Image 文件。" >&2
        exit 1
    fi
    rm -rf "${work_dir}"
}

if [ ! -s "${APP_ICON_SOURCE}" ]; then
    echo "错误：未找到应用图标或文件为空：${APP_ICON_SOURCE}" >&2
    echo "请先把已经制作好的 AppIcon.icns 放到 assets/AppIcon.icns。" >&2
    exit 1
fi
validate_app_icon "${APP_ICON_SOURCE}"

echo "清理旧构建中间产物和打包产物..."
bash "${CLEAN_SCRIPT}"

echo "开始构建 Universal 2 release 版本（${BUILD_ARCHS[*]}）..."
cd "${PROJECT_ROOT}"
swift build "${SWIFT_BUILD_ARGS[@]}"
RELEASE_DIRECTORY="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"

mkdir -p "${MACOS_DIRECTORY}" "${RESOURCES_DIRECTORY}"

echo "复制主程序..."
cp "${RELEASE_DIRECTORY}/${EXECUTABLE_NAME}" "${MACOS_DIRECTORY}/${EXECUTABLE_NAME}"
chmod +x "${MACOS_DIRECTORY}/${EXECUTABLE_NAME}"

echo "复制 SwiftPM 资源包..."
# App 运行时通过 AppResourceBundle 从 Contents/Resources 查找该资源包；
# 不放在 .app 根目录，避免 codesign 报 unsealed contents。
cp -R "${RELEASE_DIRECTORY}/${RESOURCE_BUNDLE_NAME}" "${APP_RESOURCE_BUNDLE_PATH}"

echo "复制应用图标..."
cp "${APP_ICON_SOURCE}" "${RESOURCES_DIRECTORY}/${APP_ICON_BUNDLE_NAME}"

echo "校验 SwiftPM 资源包..."
if [ ! -d "${APP_RESOURCE_BUNDLE_PATH}" ]; then
    echo "错误：未找到 SwiftPM 资源包：${APP_RESOURCE_BUNDLE_PATH}" >&2
    exit 1
fi

BUNDLED_STATIONS_PATH="${APP_RESOURCE_BUNDLE_PATH}/BundledStations.json"
if [ ! -f "${BUNDLED_STATIONS_PATH}" ]; then
    BUNDLED_STATIONS_PATH="${APP_RESOURCE_BUNDLE_PATH}/Contents/Resources/BundledStations.json"
fi

if [ ! -f "${BUNDLED_STATIONS_PATH}" ]; then
    echo "错误：SwiftPM 资源包缺少 BundledStations.json" >&2
    exit 1
fi

echo "校验 Universal 2 架构..."
LIPO_INFO="$(lipo -info "${MACOS_DIRECTORY}/${EXECUTABLE_NAME}")"
echo "  ${LIPO_INFO}"
for arch in "${BUILD_ARCHS[@]}"; do
    if [[ "${LIPO_INFO}" != *"${arch}"* ]]; then
        echo "错误：主程序缺少 ${arch} 架构" >&2
        exit 1
    fi
done

echo "生成 Info.plist..."
cat > "${CONTENTS_DIRECTORY}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh-Hans</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_DISPLAY_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>${APP_ICON_KEY_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_IDENTIFIER}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>zh-Hans</string>
        <string>zh-HK</string>
        <string>zh-Hant</string>
        <string>en</string>
    </array>
    <key>CFBundleName</key>
    <string>${APP_DISPLAY_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

echo "执行 ad-hoc 签名..."
codesign --force --deep --sign - "${APP_BUNDLE_PATH}"

echo "生成 zip 包..."
ditto -c -k --keepParent "${APP_BUNDLE_PATH}" "${ZIP_PATH}"

if [ "${GENERATE_DMG}" -eq 1 ]; then
    echo "生成 dmg 安装镜像（拖入 Applications 式布局）..."
    # 用一个临时 stage 目录组装 DMG 内容：
    #   Lo-Fi Music Box.app          待安装的 App 本体
    #   Applications                 指向 /Applications 的软链接（Finder 会把它显示成系统应用目录的快捷方式）
    # 用户双击 DMG 后，把左边的 App 拖到右边的 Applications 图标上即可完成安装，
    # 这是 macOS 开源应用的通用分发姿势，比脚本自动 ditto 到 /Applications 更符合用户预期。
    DMG_STAGE_DIRECTORY="$(mktemp -d)"
    trap 'rm -rf "${DMG_STAGE_DIRECTORY}"' EXIT
    ditto "${APP_BUNDLE_PATH}" "${DMG_STAGE_DIRECTORY}/${APP_DISPLAY_NAME}.app"
    ln -s /Applications "${DMG_STAGE_DIRECTORY}/Applications"
    # -ov 覆盖旧文件；UDZO 是压缩只读镜像，安装完可直接推出
    hdiutil create \
      -volname "${APP_DISPLAY_NAME}" \
      -srcfolder "${DMG_STAGE_DIRECTORY}" \
      -ov \
      -format UDZO \
      "${DMG_PATH}" >/dev/null
    rm -rf "${DMG_STAGE_DIRECTORY}"
    trap - EXIT
fi

echo ""
echo "打包完成："
echo "  程序：${APP_BUNDLE_PATH}"
echo "  压缩包：${ZIP_PATH}"
if [ "${GENERATE_DMG}" -eq 1 ]; then
    echo "  安装镜像：${DMG_PATH}"
    echo ""
    echo "==> 安装方式：双击 ${DMG_PATH##*/}，把「${APP_DISPLAY_NAME}」拖到弹出窗口里的 Applications 图标即可。"
else
    echo ""
    echo "==> 已跳过 dmg 生成（--no-dmg）。如需分发，去掉该参数重跑脚本。"
fi

INSTALLED_APP_PATH="/Applications/${APP_DISPLAY_NAME}.app"
if [ -d "${INSTALLED_APP_PATH}" ]; then
    INSTALLED_MTIME="$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "${INSTALLED_APP_PATH}/Contents/MacOS/${EXECUTABLE_NAME}" 2>/dev/null || echo "未知")"
    DIST_MTIME="$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "${MACOS_DIRECTORY}/${EXECUTABLE_NAME}" 2>/dev/null || echo "未知")"
    echo ""
    echo "==> 提示：检测到 ${INSTALLED_APP_PATH} 已存在（不会被脚本自动覆盖）。"
    echo "    /Applications 中的版本时间：${INSTALLED_MTIME}"
    echo "    刚打包的 dist 版本时间    ：${DIST_MTIME}"
    echo "    若要替换旧版，请用上面提示的 DMG 拖拽方式重装。"
fi
