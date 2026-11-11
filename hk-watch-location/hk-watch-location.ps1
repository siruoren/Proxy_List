# hk-watch-location.ps1 - 一键脚本：通过 USB 向 iPhone 发送香港坐标（iAP2 配件定位）[Windows 版]
#
# 用途：配合华为手表"高血压管理"等地区限定功能的开通（不使用 AnyGo）
# 原理：accessory-location 通过 USB iAP2 协议完成 MFi-v3 认证后，
#       向 iPhone 发送 GGA/RMC 坐标，iPhone 将其作为外部定位源采纳。
#
# 用法（在 PowerShell 中执行）：
#   powershell -ExecutionPolicy Bypass -File .\hk-watch-location.ps1                    # 一键完整流程
#   powershell -ExecutionPolicy Bypass -File .\hk-watch-location.ps1 run 22.2810 114.1588  # 自定义坐标
#   powershell -ExecutionPolicy Bypass -File .\hk-watch-location.ps1 send               # 跳过安装步骤直接发送
#   powershell -ExecutionPolicy Bypass -File .\hk-watch-location.ps1 stop               # 停止发送并恢复真实定位
#   $env:HK_RANDOM='1' 后再运行脚本                                                     # 香港地区随机坐标
#
# AI/自动化执行说明：
#   - 脚本全程无交互，不会阻塞等待回车；任何前置条件不满足时直接退出（非 0），
#     并打印精确的修复步骤，按提示逐项完成后再重新执行即可
#   - 如确需跳过设备检查，先执行 $env:HK_SKIP_DEVICE_CHECK = '1'
#
# Windows 特有前提：
#   1. 已安装 iTunes（官网版）或 Microsoft Store 的"Apple Devices/设备"应用
#      —— 它提供 usbmuxd 服务（Apple Mobile Device Service，本地端口 27015），
#         pymobiledevice3 在 Windows 上依赖它访问 iPhone
#   2. iPhone 用数据线连接，已解锁并点击"信任此电脑"
#   3. 发送期间在手机上打开 地图/华为运动健康 触发定位请求

param(
    [Parameter(Position = 0)][string]$Command = "run",
    [Parameter(Position = 1)][double]$Latitude = 22.3193,   # 香港纬度
    [Parameter(Position = 2)][double]$Longitude = 114.1694, # 香港经度
    [int]$Duration = 900                                    # 会话时长（秒）
)

# ========================= 可配置参数 =========================
# 离线资源包：accessory-location 源码（已去除 .git）+ DiPlay v0.2.7 APK，
# 随本仓库一起提交，运行时直接下载 zip 解压，无需克隆 GitHub 仓库
$BundleUrl   = "https://raw.githubusercontent.com/siruoren/Proxy_List/main/hk-watch-location/hk-watch-location-bundle.zip"
# jsDelivr CDN 直链（国内可达性好，20MB 内文件可用；候选列表中的第一优先）
$BundleCdn   = "https://cdn.jsdelivr.net/gh/siruoren/Proxy_List@main/hk-watch-location/hk-watch-location-bundle.zip"
$BundleDir   = Join-Path $env:USERPROFILE ".cache\hk-watch-location"
$RepoDir     = Join-Path $BundleDir "accessory-location"
$ApkPath     = Join-Path $BundleDir "DiPlay-0.2.7.apk"
$IdentityDir = Join-Path $env:APPDATA "accessory-location\identity"
$PyPiMirror  = "https://pypi.tuna.tsinghua.edu.cn/simple"
# 包内 DiPlay v0.2.7 APK（含共享实验性 MFi 身份），解压后 SHA-256 必须匹配
$ApkSha256   = "27B434462DA7E78B1FF0987D129ED0A4B0A0E56BECEAF8EC221D47150D4675BD"
# GitHub 加速镜像（国内直连常 504，按顺序尝试；最后一个空串表示直连）
$GhMirrors   = @("https://ghfast.top/", "https://gh-proxy.com/", "https://ghproxy.net/", "")
$SendLog     = Join-Path $env:TEMP "send_hk.log"

# 香港地区随机坐标（覆盖港岛/九龙/新界市区：纬 22.24~22.45，经 113.95~114.30）
function Get-RandomHkPoint {
    return @(
        [math]::Round((Get-Random -Minimum 22.24 -Maximum 22.45), 4),
        [math]::Round((Get-Random -Minimum 113.95 -Maximum 114.30), 4)
    )
}

function Write-Info { param($m) Write-Host "[信息] $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "[完成] $m" -ForegroundColor Green }
function Write-Warn2{ param($m) Write-Host "[注意] $m" -ForegroundColor Yellow }
function Write-Err2 { param($m) Write-Host "[错误] $m" -ForegroundColor Red }

# ========================= 子命令：stop =========================
function Invoke-Stop {
    Write-Info "停止所有发送进程..."
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "accessory-location send|local_mfi_v3_helper" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1

    $left = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "accessory-location send|local_mfi_v3_helper" }
    if ($left) { Write-Err2 "仍有进程残留，请到任务管理器手动结束 python 进程" }
    else { Write-Ok "发送进程已全部停止，USB 会话已断开" }

    Write-Host ""
    Write-Warn2 "恢复手机真实定位，请在 iPhone 上操作："
    Write-Host "  1. 拔掉 USB 线"
    Write-Host "  2. 设置 - 隐私与安全性 - 定位服务 - 关闭 10 秒后再打开"
    Write-Host "  3. 打开地图重新定位，确认蓝点回到真实位置"
}

# ========================= 步骤 1：环境检查 =========================
function Step-CheckEnv {
    Write-Info "步骤 1/5：检查环境"

    if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -lt 6) {
        # Windows PowerShell 5.1 没有 $IsWindows，能跑到这里即说明是 Windows
    }

    # uv 检查/安装
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Write-Warn2 "未安装 uv，正在安装..."
        Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
        $env:Path = "$env:Path;$env:USERPROFILE\.local\bin"
    }
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Write-Err2 "uv 安装失败或未加入 PATH，请关闭并重新打开 PowerShell 后再试"; exit 1
    }
    Write-Ok "uv $( (uv --version) -replace '.*?(\d[\d.]+.*)$', '$1' )"

    # usbmuxd 服务检查（Windows 必需：iTunes / Apple Devices 应用提供）
    # AI/自动化友好：检查失败不阻塞，直接退出并给出修复步骤；HK_SKIP_DEVICE_CHECK=1 可跳过
    $usbmuxd = Get-NetTCPConnection -LocalPort 27015 -State Listen -ErrorAction SilentlyContinue
    if ($usbmuxd) {
        Write-Ok "usbmuxd 服务已就绪（本地端口 27015）"
    } elseif ($env:HK_SKIP_DEVICE_CHECK -eq "1") {
        Write-Warn2 "HK_SKIP_DEVICE_CHECK=1，已跳过 usbmuxd 检查（发送阶段可能失败）"
    } else {
        Write-Err2 "未检测到 usbmuxd（端口 27015）。请先完成以下操作，然后重新运行本脚本："
        Write-Host "  1. 安装 iTunes（官网版）或 Microsoft Store 的 Apple Devices 应用"
        Write-Host "  2. 安装后重启电脑（确保 Apple Mobile Device Service 已启动）"
        Write-Host "  3. 重新执行本命令"
        Write-Host "  （确需跳过此检查：`$env:HK_SKIP_DEVICE_CHECK='1' 后再运行）"
        exit 1
    }

    # iPhone USB 检测（失败不阻塞：直接退出并给出修复步骤）
    $iphone = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match "iPhone|iPad|Apple Mobile Device" }
    if ($iphone) { Write-Ok "检测到 iPhone 已通过 USB 连接" }
    elseif ($env:HK_SKIP_DEVICE_CHECK -eq "1") {
        Write-Warn2 "HK_SKIP_DEVICE_CHECK=1，已跳过 iPhone 检查（发送阶段可能失败）"
    } else {
        Write-Err2 "未检测到 iPhone。请先完成以下操作，然后重新运行本脚本："
        Write-Host "  1. 用数据线把 iPhone 连接到这台电脑"
        Write-Host "  2. 解锁 iPhone；如弹出'信任此电脑'，点'信任'并输入锁屏密码"
        Write-Host "  3. 重新执行本命令"
        exit 1
    }
}

# ========================= 步骤 2：下载资源包 + 安装依赖 =========================
function Step-SetupRepo {
    Write-Info "步骤 2/5：准备资源包与依赖"

    if (-not (Test-Path (Join-Path $RepoDir "pyproject.toml"))) {
        Write-Info "下载资源包 hk-watch-location-bundle.zip（约 12MB，自动尝试 CDN 与加速镜像）..."
        New-Item $BundleDir -ItemType Directory -Force | Out-Null
        $zipPath = Join-Path $BundleDir "hk-watch-location-bundle.zip"
        # 候选顺序：jsDelivr CDN -> 加速镜像 -> GitHub 直连
        $candidates = @($BundleCdn) + ($GhMirrors | ForEach-Object { "$_$BundleUrl" })
        $ok = $false
        foreach ($u in $candidates) {
            Write-Info "  尝试: $u"
            curl.exe -sL --connect-timeout 15 --max-time 600 -o $zipPath $u
            if ((Test-Path $zipPath) -and ((Get-Item $zipPath).Length -gt 5000000)) {
                $ok = $true
                Write-Ok "  下载成功 ($((Get-Item $zipPath).Length) 字节)"; break
            }
        }
        if (-not $ok) { Write-Err2 "所有下载渠道均失败，请检查网络后重试"; exit 1 }

        Write-Info "解压资源包..."
        Expand-Archive -Path $zipPath -DestinationPath $BundleDir -Force
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path (Join-Path $RepoDir "pyproject.toml"))) {
            Write-Err2 "资源包解压异常，缺少 accessory-location 源码"; exit 1
        }
        Write-Ok "资源包已解压：$BundleDir"
    } else { Write-Ok "资源包已存在：$BundleDir" }

    # 校验包内 APK 的 SHA-256
    if (-not (Test-Path $ApkPath)) { Write-Err2 "资源包中缺少 APK：$ApkPath"; exit 1 }
    $actual = (Get-FileHash $ApkPath -Algorithm SHA256).Hash
    if ($actual -ne $ApkSha256) {
        Write-Err2 "APK SHA-256 不匹配！期望 $ApkSha256，实际 $actual"; exit 1
    }
    Write-Ok "APK SHA-256 校验通过"

    Write-Info "安装依赖（清华镜像，超时 600 秒）..."
    $env:UV_HTTP_TIMEOUT = "600"
    $env:UV_INDEX_URL    = $PyPiMirror
    Push-Location $RepoDir
    try {
        uv sync
        # 注：Windows 有 cryptography 的 win_amd64 预编译 wheel，无需 macOS 的 <49 版本锁定
        uv run python -c "import cryptography, pymobiledevice3"
        Write-Ok "依赖安装并导入验证通过"
    } finally { Pop-Location }
}

# ========================= 步骤 3：导入 MFi 身份 =========================
function Step-SetupIdentity {
    Write-Info "步骤 3/5：准备 MFi 身份证书"

    $cert = Join-Path $IdentityDir "certificate.p7b"
    $key  = Join-Path $IdentityDir "identity.pk8"
    if ((Test-Path $cert) -and (Test-Path $key)) {
        Write-Ok "身份已存在：$IdentityDir"; return
    }

    $apk = $ApkPath
    if (-not (Test-Path $apk)) {
        Write-Err2 "资源包 APK 不存在：$apk，请删除 $BundleDir 后重新运行以重新下载资源包"; exit 1
    }

    Write-Info "校验 APK SHA-256..."
    $actual = (Get-FileHash $apk -Algorithm SHA256).Hash
    if ($actual -ne $ApkSha256) {
        Write-Err2 "SHA-256 不匹配！期望 $ApkSha256，实际 $actual"; exit 1
    }
    Write-Ok "SHA-256 校验通过"

    Write-Info "提取身份文件（只提取证书和私钥，不安装 APK）..."
    Push-Location $RepoDir
    try {
        uv run python tools/import_diplay_identity.py --apk $apk --output-dir $IdentityDir
    } finally { Pop-Location }
    Write-Ok "身份已保存到 $IdentityDir"
    Write-Info "说明：这是 DiPlay 公开的共享实验性身份，非你的个人凭证；设备是否接受需实测"
}

# ========================= 步骤 4：发送坐标 =========================
function Invoke-Send {
    Write-Info "步骤 4/5：发送坐标 ($Latitude, $Longitude)，会话 $Duration 秒"

    New-Item (Join-Path $env:USERPROFILE ".pymobiledevice3") -ItemType Directory -Force | Out-Null

    if (-not (Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.FriendlyName -match "iPhone|iPad|Apple Mobile Device" })) {
        Write-Err2 "未检测到 iPhone，请连接 USB 后重试"; exit 1
    }

    $env:ACCESSORY_MFI_CERT_FILE = Join-Path $IdentityDir "certificate.p7b"
    $env:ACCESSORY_MFI_KEY_FILE  = Join-Path $IdentityDir "identity.pk8"

    Write-Info "启动 USB 会话，日志：$SendLog"
    Write-Host "-----------------------------------------------------------"
    Write-Warn2 "【手机操作 1】打开 地图 点定位，触发定位订阅"
    Write-Warn2 "【手机操作 2】打开 设置 - 隐私与安全 - 定位服务，关闭定位，等 10 秒后再打开"
    Write-Warn2 "【手机操作 3】再去 健康里设置（健康核对清单 - 高血压管理 - 开通）"
    Write-Warn2 "【成功标志】地图蓝点移动到香港；蓝点不动时重复操作 2 再重新定位"
    Write-Host "-----------------------------------------------------------"

    Push-Location $RepoDir
    try {
        # 前台运行，实时输出 JSON 事件；Ctrl-C 或超时自动结束
        uv run accessory-location send --transport usb `
            --auth-helper tools/local_mfi_v3_helper.py `
            --latitude $Latitude --longitude $Longitude --duration $Duration 2>&1 |
            Tee-Object -FilePath $SendLog
    } finally { Pop-Location }
}

# ========================= 步骤 5：结果解读 =========================
function Step-Report {
    Write-Info "步骤 5/5：会话结果解读"
    Write-Host ""

    if (-not (Test-Path $SendLog)) { Write-Err2 "无日志文件"; return }
    $log = Get-Content $SendLog -Raw

    if ($log -match "authentication_succeeded") { Write-Ok "MFi 认证成功" }
    else { Write-Err2 "未见认证成功事件，检查证书与 USB 连接" }

    if ($log -match "location_requested") { Write-Ok "手机已发起定位请求（订阅 GGA+RMC）" }
    else { Write-Warn2 "未收到定位请求 -> 需要在手机上打开地图/运动健康触发" }

    $ack = 0
    foreach ($m in [regex]::Matches($log, '"location_link_acknowledged", "count": (\d+)')) {
        $ack = [int]$m.Groups[1].Value
    }
    if ($ack -gt 0) { Write-Ok "手机确认收到 $ack 个坐标包（送达≠采纳，以地图蓝点为准）" }
    else { Write-Warn2 "无确认包，检查手机端操作" }

    Write-Host ""
    Write-Info "验证与后续操作："
    Write-Host "  1. 地图蓝点移到香港 -> 立即打开健康 -> 右上角用户图标 -> 打开健康核对清单-> 打开高血压通知 -> 开通"
    Write-Host "  2. 开通后按引导开启即时通知"
    Write-Host "  3. 操作完成或会话结束后：.\hk-watch-location.ps1 stop 恢复真实定位"
}

# ========================= 主流程 =========================
# 随机定位模式：$env:HK_RANDOM='1' 且未显式传坐标时，随机生成香港坐标
if ($env:HK_RANDOM -eq "1" -and $Latitude -eq 22.3193 -and $Longitude -eq 114.1694) {
    $p = Get-RandomHkPoint
    $Latitude = [double]$p[0]; $Longitude = [double]$p[1]
    Write-Info "随机定位模式（HK_RANDOM=1）：本次坐标 ($Latitude, $Longitude)；固定坐标请显式传参"
}
switch ($Command) {
    "stop"  { Invoke-Stop }
    "send"  { Invoke-Send; Step-Report }
    "run"   {
        Step-CheckEnv
        Step-SetupRepo
        Step-SetupIdentity
        Invoke-Send
        Step-Report
    }
    default {
        Write-Host "用法: .\hk-watch-location.ps1 [run|send|stop] [纬度] [经度]"
        Write-Host "  run  (默认) 完整流程：环境检查 -> 依赖 -> 身份 -> 发送"
        Write-Host "  send        直接发送（跳过安装步骤）"
        Write-Host "  stop        停止发送并指导恢复真实定位"
        Write-Host "环境变量: HK_SKIP_DEVICE_CHECK='1' 跳过设备检查；HK_RANDOM='1' 香港随机坐标"
    }
}
