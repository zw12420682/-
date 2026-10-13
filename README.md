# HotspotAutoOff 1.1.0

Wi-Fi 个人热点开启后，如果连续一段时间**没有任何设备连接**，自动关闭热点。

- 只处理 **Wi-Fi 热点**，暂不处理 USB / 蓝牙共享。
- 判定「无连接」= 热点网桥上没有任何 ARP 邻居（即没有设备连上），与流量无关。
- 默认 **5 分钟**，设置里可调 **1–60 分钟**。
- 自适应轮询：热点关着 **60 秒**一次（只 1 次系统调用），热点开着 **30 秒**一次。
- 检测不到邻居表时按「未知」处理，**不会**关闭热点（避免误关正在使用的热点）。

## 热点网桥的识别（1.1.0 修正）

热点网桥的**编号不是固定的**：真机日志显示 iOS 16 上叫 **`bridge100`**，而不是常说的
`bridge0`。旧版本写死 `bridge0`，导致永远检测不到热点、插件从未触发。

现在改为动态识别：**任何持有 IPv4 地址且处于 UP 状态的 `bridge*` 接口**就是热点网桥
（其地址通常是热点网关 `172.20.10.1`）。ARP 邻居也改为在该网桥上统计。

## 关闭热点的实现（1.1.0 修正）

从真机类清单里找到了系统自己的入口：

| 类 | 关键方法 | 说明 |
|---|---|---|
| `WFPersonalHotspotStateMonitor` | `-setMISDiscoveryState:immediateDisable:` | **实际改热点状态的 API**（MIS = MobileInternetSharing） |
| `CCUIConnectivityHotspotViewController` | `-_toggleState` / `-setPhStateMonitor:` | SpringBoard 控制中心的热点按钮，持有上面那个 monitor |

插件现在**优先**用 `setMISDiscoveryState:NO immediateDisable:YES` 关闭（并 hook `-init` 与
`-setPhStateMonitor:` 来复用系统已创建的 monitor 实例）。只有这条路径不可用时，才退回
旧的兜底链：类探测 → SCPreferences → Darwin 通知 → MobileWiFi SoftAP（SoftAP 放最后，
因为它只停 Wi-Fi 层的 AP、不同步守护进程状态，可能留下「功能已停但开关还显示开」）。

## 安装与开关

设置 → HotspotAutoOff：

| 项 | 默认 | 说明 |
|---|---|---|
| 启用 | 开 | 总开关 |
| 无连接多久后关闭（分钟） | 5 | 1–60 |
| 只记录不关闭 | 关 | **建议先打开**：达到时间只写日志、不真正关闭热点 |
| 立即检测一次 | — | 立刻跑一次判定 |
| 导出诊断信息 | — | 把网卡/偏好/进程/相关类转储到日志 |

## 日志

```
/var/tmp/hotspot-autooff.log
```

（依次尝试 `/var/tmp/`、`/var/mobile/Library/Logs/`、临时目录，**只写第一个可写的**。）

正常一轮的样子：

```
install: loaded into SpringBoard
monitor: started (poll 30s active / 60s dormant)
state: hotspot on (bridge100)
idle: started, no client connected
idle: reset (1 client(s) connected)
idle: started, no client connected
action: closing hotspot after 301s idle
turnoff: starting candidate chain
turnoff/monitor: hooked monitor=WFPersonalHotspotStateMonitor controller=CCUIConnectivityHotspotViewController
turnoff/monitor: setMISDiscoveryState=NO immediateDisable=YES sent
turnoff: chain finished via state monitor
state: hotspot off
```

`state: hotspot off` 就是成功标志：网桥消失了。

## 构建

本地 Windows 无法编译 iOS 插件。上传本目录全部内容（含 `.github`）到 GitHub 仓库根目录覆盖，
由 GitHub Actions（`macos-15-intel` + RootHide Theos + iPhoneOS16.5 SDK）编译打包，
产物在 Actions 的 `HotspotAutoOff-RootHide` artifact。

## 真机验证清单

1. 开热点 → 日志出现 `state: hotspot on (bridge100)`；关热点 → `state: hotspot off`。
2. 连一台设备 → `idle: reset (1 client(s) connected)`。
3. 设备断开 → 到点出现 `action: closing hotspot` 与 `turnoff/monitor: ...`。
4. 紧跟着应出现 `state: hotspot off`，且**设置里的开关自己变成关**。
5. 若开关没变，把日志里 `turnoff/...` 那几行发回，据此再收敛。
