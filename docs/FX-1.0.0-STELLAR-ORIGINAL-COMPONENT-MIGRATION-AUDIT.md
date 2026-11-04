# FX 1.0.0 — 原版 Stellar 组件迁移审计

> 本文以用户提供的 9.9.60 原始源码包中编译后的 Manifest/Smali 为依据，并逐项核对 FX 当前 Java、Manifest 与测试。它是迁移状态账本，不把同名类或 UI 占位算作行为等价。

## 1. 原版组件行为与 FX 状态

| 原版组件 | 原始行为（Smali 可确认） | FX 当前对应 | 状态 |
|---|---|---|---|
| `adb.AdbPairingService` | 前台服务；配对发现、配对码 RemoteInput、搜索/工作/结果通知；停止、重试、继续发现 connect 服务；成功后进入独立权限授予/启动流程 | `AdbPairingActivity`、`AdbPairingDiscovery`、`AdbPairingClient`、`PairingContext`、`AdbShellProbeClient` | **部分迁移**：原生 SPAKE2/TLS、mDNS 与 GUID connect 服务、固定只读 Shell 探测已存在；原版持久前台服务、通知 RemoteInput、停止/重试通知状态机尚未迁入 |
| `receiver.BootCompleteReceiver` | 读取 `boot_mode`：`BROADCAST` 启动 StellarReceiver；`TCPIP_PREWARM` 排入 `AdbStartWorker.prepare_tcpip`；`NONE` 与 `SCRIPT` 不由此 Receiver 直接启动 | 当前只有 Shield 的 `FxYulongBootReceiver`；无 Stellar BootMode 对应 | **未迁移** |
| `receiver.StellarReceiver` | 先 `Stellar.pingBinder()`；Binder 不可用时 `goAsync()`，在 IO Coroutine 中调用 `StellarReceiverStarter.start()` | `StellarAuthorizationService` 是 FX 内部 Messenger/Root 授权 broker，不是原版 Stellar daemon Binder | **未迁移**：不能把 FX 的授权 broker 假称原版 daemon 已恢复 |
| `receiver.StellarReceiverStarter` | 按 `last_launch_method` 选 ROOT、ADB 或 UNKNOWN；UNKNOWN 尝试 Root 后回退 ADB。ADB 启动依赖 WRITE_SECURE_SETTINGS 与 WorkManager | FX 当前有 Root 授权与只读 ADB Shell 探测 | **未迁移**：还没有等价 daemon launcher 与原版启动选择逻辑 |
| `startup.service.SelfStarterService` | 检查 `Settings.Global.adb_wifi_enabled`；Android 11+ 发现 `_adb-tls-connect._tcp`，收到端口后经 `AdbWirelessHelper.startStellarViaAdb` 启动 daemon；可按 `tcpip_port_enabled/tcpip_port` 改端口 | FX 的 ADB mDNS 只做 connect GUID 匹配、保存端点和固定只读探测 | **未迁移**：没有原版后台自动启动、端口切换与生命周期 |
| `startup.notification.BootStartActionReceiver` | 处理 `BOOT_START_CANCEL`（取消唯一 WorkManager 工作）与 `BOOT_START_RETRY`（按 BootMode 重试） | FX 无等价 Stellar 接收器/WorkManager 启动链 | **未迁移** |
| `StellarManagerProvider` | 原版配置/日志 Bundle API，以及 AIDL/Binder 相关调用 | FX 已注册受保护的 `com.youlong.hd.stellar` Provider | **部分迁移**：保存/读取配置、日志、Shizuku兼容值已实现；原版 `getBinder/sendBinder/sendUserService` 尚无等价 daemon 协议，当前明确 fail-closed，不返回假 Binder |

## 2. 原版启动模式与安全边界

原版 `StellarSettings.BootMode` 有四个值：`NONE`、`BROADCAST`、`TCPIP_PREWARM`、`SCRIPT`，默认值为 `NONE`。不能在 FX 默认启用开机启动。

原版 `StellarSettings.LaunchMethod` 有 `UNKNOWN`、`ROOT`、`ADB`。原版 Root 启动调用 `Starter.getInternalCommand()`，该命令指向 APK 的 `nativeLibraryDir/libstellar.so`；ADB 启动路径要求 WRITE_SECURE_SETTINGS 并排入 WorkManager。故必须先确认原始 `libstellar.so` 是否存在、ABI、依赖和可执行行为；不能用 FX 的 Messenger broker 或固定 echo 探测替代。

原版 `AdbStartWorker` 会写 Android Global ADB 设置（包括 `adb_enabled`、`adb_allowed_connection_time`），等待 ADB 端口，并读取 TCPIP 配置。迁入时必须满足：
- 新安装默认关闭；只有用户明确选择开机启动/预热才执行。
- 不能因扫描到 mDNS 就擅自更改开发者选项、ADB 超时或 tcpip 端口。
- 每次 Root/ADB 管理启动都要检查真实权限、记录执行结果并提供取消；失败时不能伪报成功。
- `SCRIPT` 模式应独立映射原版 Boot Script Manager 行为，不能简单等同于广播启动。
- 原版 `StellarReceiver` 检测的是远端 daemon Binder；FX 内部授权 Messenger 不构成兼容替代。

## 3. 当前已迁入的 ADB 协议能力

- 原版 `libadb.so` JNI 的 `PairingContext` 类名及 native descriptors 已核对，编译/ABI 检查接入 Actions。
- Pairing frame header、PeerInfo 固定长度、RSA 公钥与设备 GUID 类型、TLS 1.3、SPAKE2 和 host key 生命周期已有 Java 迁移实现与 host regression。
- Android NsdManager 发现 pairing/connect DNS-SD 服务；connect 端点以 GUID 精确匹配，扫描队列有硬上限和过期条目清理。
- Pairing 后有固定只读 echo Shell 探测，但这不代表原版通用 shell_v2、`root:` 管道、启动守护服务或 tcpip 管理命令已迁入。
- API 31+ 使用公开 TLS exporter API；Android 11 及更旧系统不能把系统 adb 手动配对当作 FX 独立 host key 自动配对成功。

## 4. 当前阻塞与下一步顺序

1. 检查原始源码包的 native library index，确认 `libstellar.so` 是否存在及其 ABI/依赖/哈希；只有二进制来源和行为确认后，才决定是否复用或由 FX Root 启动逻辑替代。
2. 完成原版 `AdbPairingService` 通知状态机与 RemoteInput 的行为映射，特别是前台扫描生命周期、停止、重试、配对结果、connect 服务发现。
3. 实现受用户偏好控制的 FX Stellar BootMode，并分别处理 BROADCAST、TCPIP_PREWARM、SCRIPT；默认 NONE。先实现安全的状态/取消/错误闭环，再接入 daemon launcher。
4. 实现/确认与原版 daemon 的 Binder 协议。FX 内部 Messenger Root broker 仅用于授权请求/执行，不应冒充原版跨进程 daemon。
5. 全部行为迁移后才开放 APK 构建验收输入；目前 APK build gate 保持关闭。

## 5. 审计源

- 原始源码包：`9.9.60_src` 下 `smali_classes3/roro/stellar/manager/receiver/*`、`startup/service/SelfStarterService.smali`、`startup/worker/AdbStartWorker.smali`、`startup/worker/AdbStarter.smali`、`startup/command/Starter.smali`、`adb/AdbPairingService.smali`。
- FX 对照：`adhook/app/src/main/java/roro/stellar/manager/adb/`、`.../authorization/StellarAuthorizationService.java`、`.../StellarManagerProvider.java` 与 `AndroidManifest.xml`。
