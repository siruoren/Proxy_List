hk-watch-location.sh 
指导开通高血压功能+即时通知 —

所需资源（accessory-location 源码 + DiPlay v0.2.7 APK）克隆 GitHub 仓库或下载 APK。

用法(macos bash)（在仓库根目录执行）：
```
./hk-watch-location/hk-watch-location.sh            # 一键完整流程
./hk-watch-location/hk-watch-location.sh 22.2810 114.1588   # 自定义坐标
./hk-watch-location/hk-watch-location.sh send       # 跳过安装步骤，直接发送
./hk-watch-location/hk-watch-location.sh stop       # 停止发送，恢复真实定位
```
运行时手机需解锁并已信任电脑；发送阶段打开地图触发定位订阅，蓝点到香港后立刻在华为运动健康里开通高血压功能和即时通知。





用法（Windows PowerShell 中，在仓库根目录执行）：

```
powershell -ExecutionPolicy Bypass -File .\hk-watch-location\hk-watch-location.ps1        # 一键完整流程
powershell -ExecutionPolicy Bypass -File .\hk-watch-location\hk-watch-location.ps1 run 22.2810 114.1588
powershell -ExecutionPolicy Bypass -File .\hk-watch-location\hk-watch-location.ps1 send   # 直接发送
powershell -ExecutionPolicy Bypass -File .\hk-watch-location\hk-watch-location.ps1 stop   # 恢复真实定位
```
提醒：Windows 上若认证或订阅异常，优先检查是否装了 iTunes/Apple Devices 并重启过电脑（USB 驱动就位的标志是“是否信任此电脑”弹窗正常出现）。