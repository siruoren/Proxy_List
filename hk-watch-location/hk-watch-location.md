accessory-location 的 iPhone USB/iAP2 定位数据传输测试

本工具用于自有设备或明确获批的测试设备，在受控环境中验证 accessory-location 的数据传输。它会发送 GGA/RMC 模拟坐标；这不是设备的真实 GPS 位置，也不是 Apple 提供的授权定位测试接口，设备或应用可能会暂时收到模拟位置。

工具使用公开共享的实验性 MFi 身份。身份可用或设备确认收到坐标包，不代表 Apple 或任何应用服务已授权此用途。不得用于冒充真实位置、获取地区受限功能或资格、绕过服务规则或反欺诈检测。生产环境应使用设备真实位置及平台提供的正式测试接口。

macOS（在仓库根目录执行；仅用于获批测试设备）：
```sh
./hk-watch-location/hk-watch-location_sh run <测试纬度> <测试经度>
./hk-watch-location/hk-watch-location_sh send <测试纬度> <测试经度>
./hk-watch-location/hk-watch-location_sh stop
```





Windows PowerShell（在仓库根目录执行；仅用于获批测试设备）：

```powershell
powershell -ExecutionPolicy Bypass -File .\hk-watch-location\hk-watch-location.ps1 run <测试纬度> <测试经度>
powershell -ExecutionPolicy Bypass -File .\hk-watch-location\hk-watch-location.ps1 send <测试纬度> <测试经度>
powershell -ExecutionPolicy Bypass -File .\hk-watch-location\hk-watch-location.ps1 stop
```

设备需解锁并信任连接的电脑。仅在获批的测试应用中触发定位请求；会话结束后运行 `stop`，断开 USB，并在设备上确认定位已恢复。日志中的坐标包确认只表示传输送达，不表示系统或应用采纳，也不构成任何服务资格证明。Windows 若连接异常，可检查是否安装 iTunes/Apple Devices 并重启电脑。