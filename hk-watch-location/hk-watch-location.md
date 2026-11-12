# hk-watch-location：通过 USB 向 iPhone 发送香港坐标，开通华为手表高血压管理

## 原理

accessory-location 通过 USB iAP2 协议完成 MFi-v3 认证后，向 iPhone 发送 GGA/RMC 坐标，
iPhone 将其作为外部定位源采纳，地图蓝点显示为香港，随后在华为运动健康里开通地区限定功能
（高血压管理 + 即时通知）。

所需资源（accessory-location 源码 + DiPlay v0.2.7 APK）已打包为 hk-watch-location-bundle.zip
随本仓库提交，脚本运行时自动下载解压，无需克隆 GitHub 仓库或手动下载 APK。

## 一键执行（推荐）

脚本全程无交互，任何 AI/自动化都可以直接执行。前置条件不满足时脚本会直接退出（退出码非 0），
并打印精确的修复步骤——按提示逐项完成后重新执行即可。

macOS（bash）：
```bash
./hk-watch-location/hk-watch-location.sh          # 一键完整流程（默认香港坐标，30 分钟会话）
./hk-watch-location/hk-watch-location.sh stop     # 停止发送，恢复真实定位
```

Windows（PowerShell，在仓库根目录）：
```powershell
powershell -ExecutionPolicy Bypass -File .\hk-watch-location\hk-watch-location.ps1          # 一键完整流程
powershell -ExecutionPolicy Bypass -File .\hk-watch-location\hk-watch-location.ps1 stop     # 恢复真实定位
```

可选参数（两个脚本一致）：`run|send` 后可跟 `纬度 经度 时长秒`，默认 `22.3193 114.1694 1800`（30 分钟，固定坐标）。

## 完整流程分步说明

### 步骤 0：人工准备（AI 提示用户完成）
1. iPhone 用数据线连接电脑，解锁，弹出"信任此电脑"时点信任并输入锁屏密码
2. Windows 额外要求：已装 iTunes（官网版）或 Microsoft Store 的 Apple Devices 应用并重启过电脑

### 步骤 1：环境检查（脚本自动）
- macOS：检查系统、自动安装 uv、检测 iPhone 是否通过 USB 连接
- Windows：检查/安装 uv、检测 usbmuxd 服务（端口 27015）、检测 iPhone USB 连接
- 失败退出码非 0，输出含修复步骤，处理完重跑即可

### 步骤 2：下载资源包 + 安装依赖（脚本自动）
- 按 jsDelivr CDN → ghfast.top → gh-proxy.com → ghproxy.net → GitHub 直连 的顺序下载
  hk-watch-location-bundle.zip（约 12MB），解压到 `~/.cache/hk-watch-location`（Windows：`%USERPROFILE%\.cache\hk-watch-location`）
- 解压后校验包内 DiPlay APK 的 SHA-256，再用 uv + 清华镜像安装依赖并验证导入
- x86_64 Mac 自动锁定 cryptography<49（49+ 无 x86_64 macOS wheel）

### 步骤 3：导入 MFi 身份（脚本自动）
- 从包内 DiPlay APK 提取共享实验性 MFi 证书/私钥（不安装 APK），
  保存到 `~/Library/Application Support/accessory-location/identity`（Windows：`%APPDATA%\accessory-location\identity`）
- 身份已存在时自动跳过

### 步骤 4：发送坐标（脚本自动 + 需手机配合）
- 脚本启动 USB 会话（默认 900 秒），实时输出 JSON 事件，日志写入 `/tmp/send_hk.log`（Windows：`%TEMP%\send_hk.log`）
- **此期间必须提示用户在 iPhone 上依次操作**：
  1. 打开地图并点击定位按钮（触发定位订阅）
  2. 打开 设置 → 隐私与安全 → 定位服务，关闭定位，等 10 秒后再打开
  3. 再去健康里设置（健康核对清单 → 高血压管理 → 开通）
- 成功标志：地图蓝点移动到香港；蓝点不动时重复操作 2 再重新定位

### 步骤 5：结果解读（脚本自动）
- `authentication_succeeded` → MFi 认证成功
- `location_requested` → 手机已发起定位请求
- `location_link_acknowledged` 计数 > 0 → 手机确认收到坐标包（送达≠采纳，以地图蓝点为准）

### 步骤 6：开通功能（人工，蓝点到香港后立刻做）
1. iPhone 打开华为运动健康 → 右上角用户图标 → 打开健康核对清单 → 高血压管理 → 开通
2. 按引导开启即时通知
3. 完成后执行 `stop` 子命令停止发送，并按脚本提示恢复手机真实定位：
   拔掉 USB 线 → 设置 → 隐私与安全性 → 定位服务 → 关闭 10 秒再打开 → 地图确认蓝点回到真实位置

## AI 执行指引

1. 直接运行一键命令，逐步读取输出；脚本失败退出时，按其打印的修复步骤提示用户操作，
   完成后重新运行同一命令（脚本幂等，已完成的步骤自动跳过）
2. 会话进行中（步骤 4）脚本会阻塞最多 `时长秒`，期间 AI 应提示用户做手机端操作并观察蓝点
3. 结束后读取日志判断认证/订阅/确认包状态：`grep -E "authentication_succeeded|location_requested|location_link_acknowledged" /tmp/send_hk.log`
4. 蓝点到香港后提醒用户立即开通高血压管理；完成后运行 `stop` 恢复真实定位
5. 如需在未连接设备时测试流程，可设置环境变量 `HK_SKIP_DEVICE_CHECK=1` 跳过设备检查

## 常见问题

- **未检测到 iPhone**：换数据线（需支持数据传输）、重新插拔、点信任、重启手机后再试
- **Windows 认证/订阅异常**：确认 iTunes/Apple Devices 已安装并重启过电脑（usbmuxd 就绪的标志）
- **所有下载渠道失败**：检查网络/代理；或手动把 hk-watch-location-bundle.zip 放到
  `~/.cache/hk-watch-location/` 后重跑
- **认证失败（无 authentication_succeeded）**：DiPlay 共享身份可能已被苹果吊销，属预期风险
- **蓝点不动**：手机定位服务开关一次再触发；确认手机插着 USB 线且脚本在运行中
- **蓝点到香港但功能打不开（需多次重试）**：开通必须在会话进行中完成（默认 30 分钟）；
  保持 USB 连接重跑 `send`，期间重做定位服务开关；检查华为运动健康的定位权限
  （设置 → 隐私与安全 → 定位服务 → 华为运动健康 → 使用 App 期间）；
  多次重试无效时换一组固定坐标（如尖沙咀 22.2988 114.1722、中环 22.2810 114.1588）
- **资源包版本过旧（uv sync 报 README.md 缺失）**：CDN 缓存未刷新（约 12 小时）。
  脚本会校验包内 BUNDLE_VERSION（当前 v3），不匹配自动换渠道；全部渠道都旧时按提示手动下载放置
