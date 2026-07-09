#!/usr/bin/env bash
set -euo pipefail

# 清理仓库内的构建产物和中间产物。
# 默认同时清理：
#   .build/    SwiftPM 构建缓存、编译产物、中间文件
#   dist/      打包脚本生成的 .app / zip / dmg
#
# 可选参数：
#   --build-only     仅清理 .build/
#   --dist-only      仅清理 dist/
#   -h, --help       显示帮助后退出

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIRECTORY="${PROJECT_ROOT}/.build"
DIST_DIRECTORY="${PROJECT_ROOT}/dist"

CLEAN_BUILD=1
CLEAN_DIST=1

print_help() {
    awk '
        NR == 1 { next }
        started && !/^#/ { exit }
        /^#/ {
            started = 1
            sub(/^# ?/, "")
            print
        }
    ' "${BASH_SOURCE[0]}"
}

for arg in "$@"; do
    case "${arg}" in
        --build-only)
            CLEAN_BUILD=1
            CLEAN_DIST=0
            ;;
        --dist-only)
            CLEAN_BUILD=0
            CLEAN_DIST=1
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo "错误：未知参数：${arg}" >&2
            exit 1
            ;;
    esac
done

clean_project_path() {
    local path="$1"
    local label="$2"

    case "${path}" in
        "${PROJECT_ROOT}/.build"|\
        "${PROJECT_ROOT}/dist")
            if [ -e "${path}" ]; then
                echo "清理 ${label}：${path}"
                rm -rf "${path}"
            else
                echo "跳过 ${label}：${path} 不存在"
            fi
            ;;
        *)
            echo "错误：拒绝清理非预期路径：${path}" >&2
            exit 1
            ;;
    esac
}

if [ "${CLEAN_BUILD}" -eq 1 ]; then
    clean_project_path "${BUILD_DIRECTORY}" "SwiftPM 构建目录"
fi

if [ "${CLEAN_DIST}" -eq 1 ]; then
    clean_project_path "${DIST_DIRECTORY}" "打包产物目录"
fi

echo "清理完成。"
