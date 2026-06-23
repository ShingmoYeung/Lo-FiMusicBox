#!/usr/bin/env bash
set -euo pipefail

# 兼容保留的图标检查脚本。
# 图标现在由 assets/AppIcon.icns 直接提供，本脚本不再从 PNG 生成或覆盖应用图标。
#
# 用法：
#   ./scripts/build-app-icon.sh [APP_ICON_ICNS]

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ICON_SOURCE="${1:-${PROJECT_ROOT}/assets/AppIcon.icns}"

if [ ! -s "${APP_ICON_SOURCE}" ]; then
    echo "错误：未找到应用图标或文件为空：${APP_ICON_SOURCE}" >&2
    echo "请把已经制作好的 AppIcon.icns 放到 assets/ 目录。" >&2
    exit 1
fi

case "${APP_ICON_SOURCE}" in
    *.icns) ;;
    *)
        echo "错误：应用图标必须是 .icns 文件：${APP_ICON_SOURCE}" >&2
        exit 1
        ;;
esac

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

if ! iconutil -c iconset "${APP_ICON_SOURCE}" -o "${WORK_DIR}/AppIcon.iconset" >/dev/null 2>&1; then
    echo "错误：应用图标不是有效的 .icns 文件：${APP_ICON_SOURCE}" >&2
    echo "请不要把 PNG 直接改名为 .icns；需要使用真正的 Apple Icon Image 文件。" >&2
    exit 1
fi

echo "应用图标已就绪：${APP_ICON_SOURCE}"
echo "  大小：$(stat -f '%z' "${APP_ICON_SOURCE}") 字节"
