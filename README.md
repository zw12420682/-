# HotspotAutoOff 1.0.0

Wi-Fi 个人热点开启后，如果连续一段时间**没有任何设备连接**，自动关闭热点。

- 只处理 **Wi-Fi 热点**（系统热点网桥 `bridge0`），暂不处理 USB / 蓝牙共享。
- 判定「无连接」= 热点网桥上没有任何 ARP 邻居（即没有设备连上），与流量无关。
- 默认 **5 分钟**，设置里可调 **1–60 分钟**。
- 每 30 秒检测一次；有设备连上立即清零计时。
- 检测不到邻居表时按「未知」处理，**不会**关闭热点（避免误关正在使用的热点）。

## 安装与开关

设置 → HotspotAutoOff：

| 项 | 默认 | 说明 |
|---|---|---|
| 启用 | 开 | 总开关 |
| 无连接多久后关闭（分钟） | 5 | 1–60 |
| 只记录不关闭 | 关 | **首次请先打开**：达到时间只写日志、不真正关闭热点 |
| 立即检测一次 | — | 立刻跑一次判定，用于调试 |

## 日志

```
/var/tmp/hotspot-autooff.log
```

（依次尝试 `/var/tmp/`、`/var/mobile/Library/Logs/`、临时目录，取第一个可写的。）

典型内容：

```
install: loaded into SpringBoard
monitor: started (poll 30s)
state: hotspot on
idle: started, no client connected
idle: 30s / 300s
idle: reset (1 client(s) connected)
action: closing hotspot after 301s idle
turnoff: starting candidate chain
turnoff/softap: set SoftAP=NO accepted=0
turnoff/prefs: set=1 commit=1 apply=1
turnoff: chain finished submitted=1
```

## 重要：关闭热点这一步需要真机确认

`bridge0` 检测和 ARP 统计用的是标准 BSD 接口，可靠性高；但**「关闭热点」是私有机制**，
不同 iOS 版本/机型可能不同。所以插件按顺序尝试多条路径，并把每一条的结果写进日志：

1. 进程内共享控制类探测（`MISManager` / `MobileInternetSharing` / `SharingManager` …）；
2. `MobileWiFi.framework` 的 `WiFiDeviceClientSetProperty(SoftAP, false)`；
3. `SCPreferences` 写 `com.apple.MobileInternetSharing` 域并 commit/apply；
4. 发送对应的 Darwin 通知。

**请先打开「只记录不关闭」跑一次**，把 `hotspot-autooff.log` 发回来，我根据日志里哪一条
`accepted/set/commit/apply` 为 1，把这套「霰弹式」尝试收敛成唯一有效路径。

## 构建

本地 Windows 无法编译 iOS 插件。上传本目录全部内容（含 `.github`）到 GitHub 仓库根目录覆盖，
由 GitHub Actions（`macos-15-intel` + RootHide Theos + iPhoneOS16.5 SDK）编译打包，
产物在 Actions 的 `HotspotAutoOff-RootHide` artifact。

## 真机验证清单

1. 装好后开热点 → 日志出现 `state: hotspot on`；关热点 → `state: hotspot off`。
2. 打开「只记录不关闭」，热点开 5 分钟无人连 → 日志出现 `idle: started` 与 `action: dry run`。
3. 连一台设备 → 日志出现 `idle: reset (1 client(s) connected)`。
4. 设备断开 → 5 分钟后出现 `action: closing hotspot`。
5. 关掉「只记录不关闭」再重复第 4 步，确认热点真的被关闭。
