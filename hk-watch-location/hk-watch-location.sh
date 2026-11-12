#!/usr/bin/env bash
#
# hk-watch-location.sh — 一键脚本：通过 USB 向 iPhone 发送香港坐标（iAP2 配件定位）
#
# 用途：配合华为手表"高血压管理"等地区限定功能的开通（不使用 AnyGo）
# 原理：accessory-location 通过 USB iAP2 协议完成 MFi-v3 认证后，
#       向 iPhone 发送 GGA/RMC 坐标，iPhone 将其作为外部定位源采纳。
#
# 用法：
#   ./hk-watch-location.sh                       # 一键完整流程（默认香港坐标，15 分钟会话）
#   ./hk-watch-location.sh 22.2810 114.1588      # 自定义坐标
#   ./hk-watch-location.sh run 纬度 经度 时长秒    # 完整流程（时长可省略，默认 900）
#   ./hk-watch-location.sh send [纬度] [经度] [时长秒]   # 只发送（跳过已完成的安装步骤）
#   ./hk-watch-location.sh stop                  # 停止发送，恢复手机真实定位
#
# AI/自动化执行说明：
#   - 脚本全程无交互，不会阻塞等待回车；任何前置条件不满足时直接退出（非 0），
#     并打印精确的修复步骤，按提示逐项完成后再重新执行即可
#   - 如确需跳过设备检查，设置环境变量 HK_SKIP_DEVICE_CHECK=1
#
# 运行前提：
#   1. macOS + 已安装 uv（无则脚本自动安装）
#   2. iPhone 通过 USB 连接 Mac，已解锁并"信任此电脑"
#   3. 发送期间在手机上打开 地图/华为运动健康 触发定位请求
#
set -euo pipefail

# ========================= 可配置参数 =========================
DEFAULT_LAT=22.3193          # 香港纬度
DEFAULT_LON=114.1694         # 香港经度
DURATION=1800                 # 会话时长（秒），留足蓝点到香港后在健康里开通功能的时间
# 离线资源包：accessory-location 源码（已去除 .git）+ DiPlay v0.2.7 APK，
# 随本仓库一起提交，运行时直接下载 zip 解压，无需克隆 GitHub 仓库
BUNDLE_URL="https://raw.githubusercontent.com/siruoren/Proxy_List/main/hk-watch-location/hk-watch-location-bundle.zip"
# jsDelivr CDN 直链（国内可达性好，20MB 内文件可用；候选列表中的第一优先）
BUNDLE_CDN="https://cdn.jsdelivr.net/gh/siruoren/Proxy_List@main/hk-watch-location/hk-watch-location-bundle.zip"
BUNDLE_DIR="${HOME}/.cache/hk-watch-location"
REPO_DIR="${BUNDLE_DIR}/accessory-location"
APK_PATH="${BUNDLE_DIR}/DiPlay-0.2.7.apk"
IDENTITY_DIR="${HOME}/Library/Application Support/accessory-location/identity"
PYPI_MIRROR="https://pypi.tuna.tsinghua.edu.cn/simple"
# 包内 DiPlay v0.2.7 APK（含共享实验性 MFi 身份），解压后 SHA-256 必须匹配
APK_SHA256="27b434462da7e78b1ff0987d129ed0a4b0a0e56beceaf8ec221d47150d4675bd"
EXPECTED_BUNDLE_VERSION="v3"  # 资源包版本标记：CDN/镜像可能缓存旧包，版本不匹配自动换渠道
# GitHub 加速镜像（国内直连常 504，按顺序尝试；最后一个空串表示直连）
GH_MIRRORS=("https://ghfast.top/" "https://gh-proxy.com/" "https://ghproxy.net/" "")
SEND_LOG="/tmp/send_hk.log"

c_info()  { printf '\033[1;34m[信息]\033[0m %s\n' "$*"; }
c_ok()    { printf '\033[1;32m[完成]\033[0m %s\n' "$*"; }
c_warn()  { printf '\033[1;33m[注意]\033[0m %s\n' "$*"; }
c_err()   { printf '\033[1;31m[错误]\033[0m %s\n' "$*"; }

# ========================= 子命令：stop =========================
do_stop() {
    c_info "停止所有发送进程..."
    pkill -f "accessory-location send" 2>/dev/null || true
    pkill -f "local_mfi_v3_helper"    2>/dev/null || true
    sleep 1
    # 兜底：按 PID 强杀
    local pids
    pids=$(ps aux | grep -E "accessory-location send|local_mfi_v3_helper" | grep -v grep | awk '{print $2}' || true)
    if [ -n "$pids" ]; then
        kill -9 $pids 2>/dev/null || true
        sleep 1
    fi
    if ps aux | grep -E "accessory-location send|local_mfi_v3_helper" | grep -v grep >/dev/null; then
        c_err "仍有进程残留，请手动检查: ps aux | grep accessory"
    else
        c_ok "发送进程已全部停止，USB 会话已断开"
    fi
    echo
    c_warn "恢复手机真实定位，请在 iPhone 上操作："
    echo "  1. 拔掉 USB 线"
    echo "  2. 设置 → 隐私与安全性 → 定位服务 → 关闭 10 秒后再打开"
    echo "  3. 打开地图重新定位，确认蓝点回到真实位置"
}

# ========================= 步骤 1：环境检查 =========================
check_env() {
    c_info "步骤 1/5：检查环境"

    if [ "$(uname)" != "Darwin" ]; then
        c_err "此脚本仅支持 macOS"; exit 1
    fi

    if ! command -v uv >/dev/null 2>&1; then
        c_warn "未安装 uv，正在安装..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="${HOME}/.local/bin:${PATH}"
    fi
    c_ok "uv $(uv --version | awk '{print $2}')"

    # 检查 iPhone 是否通过 USB 连接（失败不阻塞：直接退出并给出修复步骤）
    if system_profiler SPUSBDataType 2>/dev/null | grep -qi "iphone"; then
        c_ok "检测到 iPhone 已通过 USB 连接"
    elif [ "${HK_SKIP_DEVICE_CHECK:-0}" = "1" ]; then
        c_warn "HK_SKIP_DEVICE_CHECK=1，已跳过 iPhone 检查（发送阶段可能失败）"
    else
        c_err "未检测到 iPhone，请先完成以下操作，然后重新运行本脚本："
        echo "  1. 用数据线把 iPhone 连接到这台 Mac"
        echo "  2. 解锁 iPhone；如弹出'信任此电脑'，点'信任'并输入锁屏密码"
        echo "  3. 重新执行: $0 ${*:-}"
        echo "  （确需跳过此检查：HK_SKIP_DEVICE_CHECK=1 $0 ...）"
        exit 1
    fi
}

# ========================= 步骤 2：下载资源包 + 安装依赖 =========================
setup_repo() {
    c_info "步骤 2/5：准备资源包与依赖"

    if [ ! -f "${REPO_DIR}/pyproject.toml" ] || [ "$(cat "${BUNDLE_DIR}/BUNDLE_VERSION" 2>/dev/null || echo missing)" != "${EXPECTED_BUNDLE_VERSION}" ]; then
        c_info "下载资源包 hk-watch-location-bundle.zip（约 12MB，自动尝试 CDN 与加速镜像）..."
        mkdir -p "${BUNDLE_DIR}"
        local zip_path="${BUNDLE_DIR}/hk-watch-location-bundle.zip"
        # 候选顺序：jsDelivr CDN → 加速镜像 → GitHub 直连
        # CDN/镜像可能缓存旧版资源包：下载后校验 BUNDLE_VERSION，不匹配则换下一个渠道
        local candidates=("${BUNDLE_CDN}")
        local m u ok=1 ver
        for m in "${GH_MIRRORS[@]}"; do candidates+=("${m}${BUNDLE_URL}"); done
        for u in "${candidates[@]}"; do
            c_info "  尝试: ${u}"
            curl -sL --connect-timeout 15 --max-time 600 \
                 -o "$zip_path" -H "User-Agent: hk-watch-location" \
                 "${u}" || continue
            [ "$(stat -f%z "$zip_path")" -gt 5000000 ] || { c_warn "  下载不完整，换下一个渠道"; continue; }
            c_ok "  下载成功 ($(stat -f%z "$zip_path") 字节)"
            unzip -oq "$zip_path" -d "${BUNDLE_DIR}"
            ver="$(cat "${BUNDLE_DIR}/BUNDLE_VERSION" 2>/dev/null || echo missing)"
            if [ "$ver" != "${EXPECTED_BUNDLE_VERSION}" ] || [ ! -f "${REPO_DIR}/pyproject.toml" ]; then
                c_warn "  该渠道资源包版本过旧（${ver}），换下一个渠道"
                rm -rf "${REPO_DIR}" "$zip_path"
                continue
            fi
            ok=0; break
        done
        if [ "$ok" -ne 0 ]; then
            c_err "所有渠道均未获取到 v${EXPECTED_BUNDLE_VERSION} 资源包（CDN 缓存可能未刷新）"
            echo "  1. 稍等几分钟后重试（jsDelivr 缓存约 12 小时刷新）"
            echo "  2. 或手动下载 hk-watch-location-bundle.zip 解压到 ${BUNDLE_DIR} 后重跑"
            exit 1
        fi
        rm -f "$zip_path"
        c_ok "资源包已解压：${BUNDLE_DIR}（版本 ${EXPECTED_BUNDLE_VERSION}）"
    else
        c_ok "资源包已存在：${BUNDLE_DIR}（版本 ${EXPECTED_BUNDLE_VERSION}）"
    fi

    # 校验包内 APK 的 SHA-256
    if [ -f "${APK_PATH}" ]; then
        local apk_hash
        apk_hash=$(shasum -a 256 "${APK_PATH}" | awk '{print $1}')
        if [ "$apk_hash" != "${APK_SHA256}" ]; then
            c_err "APK SHA-256 不匹配！期望 ${APK_SHA256}，实际 ${apk_hash}"; exit 1
        fi
        c_ok "APK SHA-256 校验通过"
    else
        c_err "资源包中缺少 APK：${APK_PATH}"; exit 1
    fi
    cd "${REPO_DIR}"

    # 兼容性修复（本次实测踩坑）：
    # cryptography>=49 只有 macOS arm64 wheel；x86_64 Mac 会走源码编译且本机无 Rust 必失败。
    # 因此 x86_64 机器将依赖锁定为 <49（48.0.1 是最后带 universal2 wheel 的版本）。
    if [ "$(uname -m)" = "x86_64" ]; then
        if grep -q 'cryptography>=43"' pyproject.toml; then
            c_info "x86_64 Mac：锁定 cryptography<49（49+ 无 x86_64 macOS wheel）"
            sed -i '' 's/"cryptography>=43",/"cryptography>=43,<49",/' pyproject.toml
            UV_HTTP_TIMEOUT=600 UV_INDEX_URL="${PYPI_MIRROR}" uv lock
        else
            c_ok "cryptography 版本约束已适配"
        fi
    fi

    c_info "安装依赖（使用清华镜像，超时 600 秒）..."
    UV_HTTP_TIMEOUT=600 UV_INDEX_URL="${PYPI_MIRROR}" uv sync
    uv run python -c "import cryptography, pymobiledevice3" \
        && c_ok "依赖安装并导入验证通过"
}

# ========================= 步骤 3：导入 MFi 身份 =========================
setup_identity() {
    c_info "步骤 3/5：准备 MFi 身份证书"

    if [ -f "${IDENTITY_DIR}/certificate.p7b" ] && [ -f "${IDENTITY_DIR}/identity.pk8" ]; then
        c_ok "身份已存在：${IDENTITY_DIR}"
        return
    fi

    local apk="${APK_PATH}"
    if [ ! -f "$apk" ]; then
        c_err "资源包 APK 不存在：${apk}，请删除 ${BUNDLE_DIR} 后重新运行以重新下载资源包"
        exit 1
    fi

    c_info "校验 APK SHA-256..."
    local actual
    actual=$(shasum -a 256 "$apk" | awk '{print $1}')
    if [ "$actual" != "${APK_SHA256}" ]; then
        c_err "SHA-256 不匹配！期望 ${APK_SHA256}，实际 ${actual}"; exit 1
    fi
    c_ok "SHA-256 校验通过"

    c_info "提取身份文件（只提取证书和私钥，不安装 APK）..."
    cd "${REPO_DIR}"
    uv run python tools/import_diplay_identity.py --apk "$apk"
    c_ok "身份已保存到 ${IDENTITY_DIR}（0700 目录 / 0600 文件）"
    c_info "说明：这是 DiPlay 公开的共享实验性身份，非你的个人凭证；设备是否接受需实测"
}

# ========================= 步骤 4：发送坐标 =========================
do_send() {
    local lat="${1:-${DEFAULT_LAT}}" lon="${2:-${DEFAULT_LON}}" dur="${3:-${DURATION}}"

    c_info "步骤 4/5：发送坐标 (${lat}, ${lon})，会话 ${dur} 秒"

    # pymobiledevice3 需要此目录（本次实测：不存在时会 PermissionError）
    mkdir -p "${HOME}/.pymobiledevice3"

    # 确认 iPhone 连接（失败不阻塞：直接退出并给出修复步骤）
    if system_profiler SPUSBDataType 2>/dev/null | grep -qi "iphone"; then
        c_ok "iPhone 已连接，可以发送"
    elif [ "${HK_SKIP_DEVICE_CHECK:-0}" = "1" ]; then
        c_warn "HK_SKIP_DEVICE_CHECK=1，已跳过 iPhone 检查（发送可能失败）"
    else
        c_err "未检测到 iPhone。请先完成以下操作，然后重新运行："
        echo "  1. 用数据线把 iPhone 连接到这台 Mac"
        echo "  2. 解锁 iPhone；如弹出'信任此电脑'，点'信任'并输入锁屏密码"
        echo "  3. 重新执行本命令"
        exit 1
    fi

    export ACCESSORY_MFI_CERT_FILE="${IDENTITY_DIR}/certificate.p7b"
    export ACCESSORY_MFI_KEY_FILE="${IDENTITY_DIR}/identity.pk8"

    cd "${REPO_DIR}"
    c_info "启动 USB 会话，日志：${SEND_LOG}（进程超时或 Ctrl-C 自动结束）"
    echo "-----------------------------------------------------------"
    c_warn "【手机操作 0】检查定位权限：设置 → 隐私与安全 → 定位服务 → 华为运动健康，选'使用 App 期间'"
    c_warn "【手机操作 1】打开 地图 点定位，触发定位订阅"
    c_warn "【手机操作 2】打开 设置 → 隐私与安全 → 定位服务，关闭定位，等 10 秒后再打开"
    c_warn "【手机操作 3】再去 健康里设置（健康核对清单 → 高血压管理 → 开通）"
    c_warn "【成功标志】地图蓝点移动到香港；蓝点不动时重复操作 2 再重新定位"
    echo "-----------------------------------------------------------"

    # 从日志读取最新 ACK 计数
    read_ack() {
        grep -o '"location_link_acknowledged", "count": [0-9]*' "${SEND_LOG}" 2>/dev/null | tail -1 | grep -o '[0-9]*$' || echo 0
    }

    # 后台发送 + 循环检查 ACK：每 15 秒轮询日志，实时提示认证/订阅/ACK；
    # 会话结束仍无 ACK 时自动重发（最多 3 次），期间提示手机端重做定位开关
    set +e
    trap 'kill "${send_pid:-0}" 2>/dev/null; exit 130' INT TERM
    local attempt=1 max_attempts=3 ack notified_ack=0 seen_auth=0 seen_req=0
    while :; do
        rm -f "${SEND_LOG}"
        c_info "第 ${attempt}/${max_attempts} 次发送会话（每 15 秒检查一次 ACK），日志：${SEND_LOG}"
        uv run accessory-location send --transport usb \
            --auth-helper tools/local_mfi_v3_helper.py \
            --latitude "$lat" --longitude "$lon" --duration "$dur" > "${SEND_LOG}" 2>&1 &
        send_pid=$!
        notified_ack=0; seen_auth=0; seen_req=0
        while kill -0 "${send_pid}" 2>/dev/null; do
            sleep 15
            if [ "${seen_auth}" -eq 0 ] && grep -q "authentication_succeeded" "${SEND_LOG}" 2>/dev/null; then
                seen_auth=1; c_ok "MFi 认证成功"
            fi
            if [ "${seen_req}" -eq 0 ] && grep -q "location_requested" "${SEND_LOG}" 2>/dev/null; then
                seen_req=1; c_ok "手机已发起定位请求（订阅 GGA+RMC）"
            fi
            ack=$(read_ack)
            if [ "${ack:-0}" -gt "${notified_ack}" ]; then
                notified_ack=${ack}
                c_ok "收到 ACK：手机已确认 ${notified_ack} 个坐标包（送达≠采纳，以地图蓝点为准）"
            fi
        done
        wait "${send_pid}" 2>/dev/null
        ack=$(read_ack)
        if [ "${ack:-0}" -gt 0 ]; then
            c_ok "本次会话共收到 ${ack} 个 ACK，蓝点确认在香港后立刻去健康开通"
            break
        fi
        if [ "${attempt}" -ge "${max_attempts}" ]; then
            c_warn "连续 ${max_attempts} 次会话均无 ACK（坐标已发出但 iPhone 未确认采纳）"
            break
        fi
        attempt=$((attempt + 1))
        c_warn "本次会话未收到任何 ACK，即将自动重发。手机端请重做："
        echo "  设置 → 隐私与安全 → 定位服务，关闭 10 秒再打开 → 回地图点定位"
        sleep 10
    done
    trap - INT TERM
    set -e
}

# ========================= 步骤 5：结果解读 =========================
report() {
    c_info "步骤 5/5：会话结果解读"
    echo
    if grep -q "authentication_succeeded" "${SEND_LOG}" 2>/dev/null; then
        c_ok "MFi 认证成功"
    else
        c_err "未见认证成功事件，检查证书与 USB 连接"
    fi
    if grep -q "location_requested" "${SEND_LOG}" 2>/dev/null; then
        c_ok "手机已发起定位请求（订阅 GGA+RMC）"
    else
        c_warn "未收到定位请求 → 需要在手机上打开地图/运动健康触发"
    fi
    local ack
    ack=$(grep -o '"location_link_acknowledged", "count": [0-9]*' "${SEND_LOG}" 2>/dev/null | tail -1 | grep -o '[0-9]*$' || echo 0)
    if [ "${ack:-0}" -gt 0 ]; then
        c_ok "手机确认收到 ${ack} 个坐标包（送达≠采纳，以地图蓝点为准）"
    else
        c_warn "无确认包，检查手机端操作"
    fi
    echo
    c_info "验证与后续操作："
    echo "  1. 地图蓝点移到香港 -> 立即打开健康 -> 右上角用户图标 -> 打开健康核对清单-> 打开高血压通知 -> 开通"
    echo "  2. 开通后按引导开启即时通知"
    echo "  3. 操作完成或会话结束后：本脚本 stop 恢复真实定位"
    echo
    c_warn "蓝点已到香港但功能仍打不开时（需多次重试的常见原因排查）："
    echo "  1. 保持 USB 连接不断开，直接重跑本脚本 send 子命令重新发送坐标（幂等，跳过安装）"
    echo "     会话期间重做定位服务开关（关 10 秒再开），蓝点确认在香港后立刻去健康开通"
    echo "  2. 检查定位权限：设置 → 隐私与安全 → 定位服务 → 华为运动健康 → 允许'使用 App 期间'"
    echo "  3. 会话时长默认 30 分钟；会话已结束时蓝点会恢复真实位置，开通必须在会话进行中完成"
    echo "  4. 多次重试仍无效时，换一组固定香港坐标重试（如尖沙咀 22.2988 114.1722、中环 22.2810 114.1588）"
}

# ========================= 主流程 =========================
main() {
    case "${1:-}" in
        stop)
            do_stop
            exit 0
            ;;
        send)
            mkdir -p "${HOME}/.pymobiledevice3"
            do_send "${2:-}" "${3:-}" "${4:-}"
            report
            exit 0
            ;;
        ""|run)
            local lat="${2:-${DEFAULT_LAT}}" lon="${3:-${DEFAULT_LON}}" dur="${4:-${DURATION}}"
            check_env
            setup_repo
            setup_identity
            do_send "$lat" "$lon" "$dur"
            report
            ;;
        *)
            echo "用法: $0 [run|send|stop] [纬度] [经度] [时长秒]"
            echo "  run  (默认) 完整流程：环境检查 → 资源包/依赖 → MFi 身份 → 发送 → 结果解读"
            echo "  send        直接发送（跳过安装步骤，适合二次执行）"
            echo "  stop        停止发送并指导恢复真实定位"
            echo "环境变量: HK_SKIP_DEVICE_CHECK=1 跳过 iPhone 连接检查"
            exit 1
            ;;
    esac
}

main "$@"
