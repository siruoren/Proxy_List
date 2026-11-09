hk-watch-location.sh — 已整合本次全部执行记录，内置 5 个完善步骤：

步骤 内容 内置的踩坑修复 1. 环境检查 macOS / uv（无则自动安装）/ USB 检测 iPhone — 2. 仓库依赖 克隆 +`uv sync` 清华镜像 + 600s 超时； x86_64 Mac 自动锁 cryptography<49 （49+ 无 x86_64 wheel，源码编译必失败） 3. MFi 身份 下载 APK → SHA-256 校验 → 提取证书私钥 ghfast.top 等 3 个加速镜像轮询 （直连 504）；已有身份则跳过；APK 用后即删 4. 发送坐标 默认香港 (22.3193, 114.1694)，15 分钟会话 自动创建`~/.pymobiledevice3` （缺失会 PermissionError）；实时输出 JSON 事件；日志存`/tmp/send_hk.log` 5. 结果解读 自动分析认证/订阅/确认包数量，指导开通高血压功能+即时通知 —

用法：

`./hk-watch-location.sh            # 一键完整流程
./hk-watch-location.sh 22.2810 114.1588   # 自定义坐标
./hk-watch-location.sh send       # 跳过安装步骤，直接发送
./hk-watch-location.sh stop       # 停止发送，恢复真实定位`

运行时手机需解锁并已信任电脑；发送阶段打开地图触发定位订阅，蓝点到香港后立刻在华为运动健康里开通高血压功能和即时通知。





用法（Windows PowerShell 中）：

`powershell -ExecutionPolicy Bypass -File .\hk-watch-location.ps1        # 一键完整流程
powershell -ExecutionPolicy Bypass -File .\hk-watch-location.ps1 run 22.2810 114.1588
powershell -ExecutionPolicy Bypass -File .\hk-watch-location.ps1 send   # 直接发送
powershell -ExecutionPolicy Bypass -File .\hk-watch-location.ps1 stop   # 恢复真实定位`

提醒：Windows 上若认证或订阅异常，优先检查是否装了 iTunes/Apple Devices 并重启过电脑（USB 驱动就位的标志是“是否信任此电脑”弹窗正常出现）。