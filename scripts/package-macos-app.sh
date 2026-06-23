#!/usr/bin/env bash
set -euo pipefail

# 该脚本把 SwiftPM 的 release 可执行文件组装成标准 macOS .app 程序包。
# 目前使用 ad-hoc 签名，适合本机运行和开发验证；正式分发时再接入 Developer ID 签名和 notarization。

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

clean_project_path() {
    local path="$1"
    case "${path}" in
        "${PROJECT_ROOT}/.build"|\
        "${PROJECT_ROOT}/dist")
            rm -rf "${path}"
            ;;
        *)
            echo "错误：拒绝清理非预期路径：${path}" >&2
            exit 1
            ;;
    esac
}

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
clean_project_path "${BUILD_DIRECTORY}"
clean_project_path "${DIST_DIRECTORY}"

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

echo "生成 dmg 安装镜像..."
hdiutil create \
  -volname "${APP_DISPLAY_NAME}" \
  -srcfolder "${APP_BUNDLE_PATH}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" >/dev/null

echo "打包完成："
echo "  程序：${APP_BUNDLE_PATH}"
echo "  压缩包：${ZIP_PATH}"
echo "  安装镜像：${DMG_PATH}"
