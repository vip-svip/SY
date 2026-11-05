# FXhook 统一迁移矩阵（FX 1.0.0）

本清单从当前 KernelSU ZIP 内 `lsposed/app/src/main/java/de/privacyguard/hook/MainHook.java` 自动提取。它记录旧版功能开关与所属实现方法，作为迁移验收基线；**不代表这些功能已经进入 FXhook API-101 运行时**。

## 当前架构事实

- 旧版完整实现：Xposed API 82，入口 `de.privacyguard.hook.MainHook`，读取 `/data/local/tmp/privacyguard/xposed.conf`。
- 新版运行时：libxposed API 101，入口 `de.privacyguard.adhook.AdVisibilityHook`，通过 LSPosed Remote Files 读取 `fx-hook-targets.conf`。
- 两者当前仍是两个 APK；单纯改包名或把两个入口塞进一个 APK 不会兼容两种 API。
- 当前新版已实现广告 View 观察、Android ID 隐私变换、EXIF getter 读取脱敏、单包进程内剪贴板读取阻止、传感器枚举/采样率限制，以及受全局开关与每应用目标双重控制的 Wi-Fi 扫描屏蔽；旧版其余功能需逐项迁移、单测、目标进程回归后才能标记完成。
- 迁移原则：默认关闭破坏性行为；每个 Hook 独立开关；失败回退原始结果；跳过系统进程、FX 自身和 LSPosed 管理器；配置缺失/非法时不安装 Hook。

## 旧版开关基线

| 开关 | 旧版实现方法 | API-101 迁移状态 |
|---|---|---|
| `Camera disabled by PrivacyGuard` | `cameraNull` | 待迁移与验证 |
| `Permission denied` | `rootHide, fsHooks` | 待迁移与验证 |
| `a11y_hide` | `a11yHide` | 待迁移与验证 |
| `ad_id_unify` | `adIdUnify` | 部分能力需重构（仅 Android ID 有新版对应实现） |
| `app_list` | `appListHide` | 待迁移与验证 |
| `audio_fp_block` | `audioFpBlock` | 待迁移与验证 |
| `block_cell_info` | `telephonySpoof` | 待迁移与验证 |
| `block_ime_logging` | `secureSettingsSpoof, imeHide` | 待迁移与验证 |
| `block_kernel_version` | `kernelVersionHide` | 待迁移与验证 |
| `block_logcat` | `rootHide` | 待迁移与验证 |
| `block_mediastore` | `mediastoreHide` | 待迁移与验证 |
| `block_mounts` | `rootHide, collectFsPaths` | 待迁移与验证 |
| `block_net_ifaces` | `netIfacesHide` | 待迁移与验证 |
| `block_netstats` | `netStatsHide` | 待迁移与验证 |
| `block_notif_listen` | `notifHide` | API-101 已迁移：全局 `notification_listen_enabled` + per-app `notification_listen_block`；仅屏蔽活动通知读取 API，通知发送/显示不变，共享进程失败放行 |
| `block_pm_query` | `pmQueryHide` | 待迁移与验证 |
| `block_process_list` | `procListHide` | 待迁移与验证 |
| `block_rootcheck_libs` | `rootHide` | 待迁移与验证 |
| `block_wifi_scan` | `wifiScanHide` | API-101 已迁移（`wifi_scan_enabled` + per-app `wifi_scan_block`；共享进程失败放行） |
| `cam_hw_hide` | `cameraNull` | 待迁移与验证 |
| `cam_null` | `cameraNull` | 待迁移与验证 |
| `clipboard` | `clipboardGuard` | 部分迁移：API-101 提供独立 `clipboard_read_block` 只读拦截；旧版 fake 模式未迁移 |
| `clipboard_isolate` | `clipboardGuard` | API-101 源码、配置与 UI 已接通，GitHub CI APK 构建通过并已回填工作包；实现进程本地 ClipData shadow，仅单包进程启用，共享进程 fail-open；与 `clipboard_read_block` 互斥。不是 OS 级跨应用隔离，仍待真机验证 |
| `disable_passive_loc` | `passiveLocHide` | 待迁移与验证 |
| `exif_strip` | `exifStrip` | 部分迁移：框架/AndroidX ExifInterface 读取时脱敏；不改写图片文件且不覆盖所有第三方解析器 |
| `fs_attrs` | `sysPropsHide, rootHide` | 待迁移与验证 |
| `fs_hide` | `rootHide, collectFsPaths` | 待迁移与验证 |
| `fs_isolate` | `collectFsPaths` | 待迁移与验证 |
| `fs_rootlist` | `rootHide` | 待迁移与验证 |
| `fs_vfs` | `collectFsPaths` | 待迁移与验证 |
| `gnss_spoof` | `gnssSpoof` | 待迁移与验证 |
| `gps` | `fakeLocation` | 待迁移与验证 |
| `gps_accuracy` | `fakeLocation` | 待迁移与验证 |
| `hide_face_hw` | `bioHide` | 待迁移与验证 |
| `hide_fingerprint_hw` | `bioHide` | 待迁移与验证 |
| `hide_kernel_debug` | `rootHide` | 待迁移与验证 |
| `hide_ksu` | `rootHide` | 待迁移与验证 |
| `hide_magisk` | `rootHide` | 待迁移与验证 |
| `hide_mounts` | `rootHide, collectFsPaths` | 待迁移与验证 |
| `hide_notif_perm` | `notifPermHide` | API-101 已接通 UI、apply 发布门、Remote Files global/per-target 字段和 parser/runtime；仅屏蔽目标 APP 查询通知访问状态的返回值，不改变 Android 实际授权 |
| `hide_su` | `rootHide` | 待迁移与验证 |
| `hide_sysfs_nodes` | `collectFsPaths` | 待迁移与验证 |
| `k_task` | `procListHide` | 待迁移与验证 |
| `mic_block` | `micBlock, audioFpBlock` | 待迁移与验证 |
| `mic_hw_hide` | `micBlock` | 待迁移与验证 |
| `mock_location` | `fakeLocation, locationMock` | 待迁移与验证 |
| `patch_spoof` | `buildSpoof` | 待迁移与验证 |
| `perapp_mock` | `fakeLocation, locationMock` | 待迁移与验证 |
| `sensor_accel` | `sensorHide` | API-101 已迁移：按类型隐藏 `getSensorList/getDefaultSensor`；仅单包进程生效，未知类型 fail-open |
| `sensor_gyro` | `sensorHide` | API-101 已迁移：按类型隐藏 `getSensorList/getDefaultSensor`；仅单包进程生效，未知类型 fail-open |
| `sensor_light` | `sensorHide` | API-101 已迁移：按类型隐藏 `getSensorList/getDefaultSensor`；仅单包进程生效，未知类型 fail-open |
| `sensor_magnet` | `sensorHide` | API-101 已迁移：按类型隐藏 `getSensorList/getDefaultSensor`；仅单包进程生效，未知类型 fail-open |
| `sensor_pressure` | `sensorHide` | API-101 已迁移：按类型隐藏 `getSensorList/getDefaultSensor`；仅单包进程生效，未知类型 fail-open |
| `sensor_prox` | `sensorHide` | API-101 已迁移：按类型隐藏 `getSensorList/getDefaultSensor`；仅单包进程生效，未知类型 fail-open |
| `sensor_rate_limit` | `sensorHide` | API-101 已迁移：`registerListener` 采样周期下限 100ms（最高 10Hz）；仅单包进程生效，Hook 不可用时 fail-open |
| `spoof_android_id` | `secureSettingsSpoof` | 部分能力需重构（仅 Android ID 有新版对应实现） |
| `spoof_baseband` | `buildSpoof` | 待迁移与验证 |
| `spoof_battery` | `batterySpoof` | 待迁移与验证 |
| `spoof_brand` | `buildSpoof` | 待迁移与验证 |
| `spoof_bt_mac` | `btWifiMacSpoof` | 待迁移与验证 |
| `spoof_fingerprint` | `buildSpoof` | 待迁移与验证 |
| `spoof_hardware` | `buildSpoof` | 待迁移与验证 |
| `spoof_imei` | `telephonySpoof` | 待迁移与验证 |
| `spoof_manufacturer` | `buildSpoof` | 待迁移与验证 |
| `spoof_model` | `buildSpoof` | 待迁移与验证 |
| `spoof_screen` | `screenSpoof` | 待迁移与验证 |
| `spoof_serial` | `serialSpoof` | 待迁移与验证 |
| `spoof_sim` | `telephonySpoof` | 待迁移与验证 |
| `spoof_storage` | `storageSpoof` | 待迁移与验证 |
| `spoof_version` | `buildSpoof` | 待迁移与验证 |
| `spoof_wifi_mac` | `btWifiMacSpoof` | 待迁移与验证 |
| `syssvc_hide` | `sysSvcHide` | 待迁移与验证 |
| `telephony` | `telephonySpoof` | 待迁移与验证 |
| `usagestats_off` | `usageHide` | 待迁移与验证 |
| `vpn_hide` | `vpnHide` | 待迁移与验证 |

## 2026-10-30 API-101 CI snapshot

- Successful CI run: `41074509939` (source commit `024c9ce6`).
- API-101 debug APK SHA-256: `3a113bcecedd203f7aab32f1b84803a85cd11282b4ec47d4ddbec1b819bf8822`.
- CI passed parser/policy tests, APK build/signature checks, Xposed resource checks, and bounded member/reward-flow DEX marker checks.
- `hide_notif_perm` now maps to the API-101 `notification_permission_hide_enabled` master and per-target `notification_permission_hide` bit. The runtime only masks the selected app's permission-status query; it does not grant/revoke notification access or alter OS permission state.
- The two application IDs remain separate. No OnePlus 12 LSPosed runtime verification has been performed.

## 合并验收门槛

1. 唯一安装包、唯一 applicationId、唯一 LSPosed 模块入口。
2. 75 个旧版开关键逐项完成映射；未迁移项在 UI 明确标记，不得静默丢弃。
3. 统一配置生成器与 Remote Files schema，含版本、长度、重复键、非法值校验和原子替换。
4. 旧 API Hook 全部改写为 API-101 interceptor；不得在 API-101 APK 内依赖 API-82 `XposedBridge` 运行时。
5. 通过 parser 单测、方法级回归、安装/升级/卸载回归，再进行 OnePlus 12 + KernelSU + LSPosed 真机验证。
6. 广告奖励与 VIP 仅做合法广告流程/只读状态诊断，不伪造奖励回调或购买权益。


## 剪贴板隔离迁移验收（历史审计条件；已由下方实现状态更新）

旧 API-82 `clipboardGuard()` 的 `clipboard_isolate` 行为并非“阻止读取”：它在 `setPrimaryClip()` 后缓存当前进程写入的 `ClipData`，并让 `getPrimaryClip()` / `hasPrimaryClip()` 返回进程本地缓存。该语义只能近似隔离同一进程内的读取，不能宣称为 Android 系统级跨应用剪贴板隔离。

API-101 迁移必须满足以下条件后才可将矩阵标记为完成：

1. 独立 `clipboard_isolate` per-target 配置，不复用 `clipboard_read_block`；两者同时启用时必须在解析阶段拒绝或采用明确且有测试的优先级。
2. 单包进程内缓存由线程安全引用保存；`setPrimaryClip()` 先执行原始系统写入，成功后再更新缓存；失败时不更新缓存。
3. `getPrimaryClip()`、`hasPrimaryClip()` 和受支持的旧版 `getText()` 读取本地缓存；缓存为空时按明确策略返回空值，不伪造内容。
4. 共享包名/共享进程、配置缺失、Hook 不可用时 fail-open，继续调用原始系统 API；不得影响未选择的同进程应用。
5. 不修改系统剪贴板服务、剪贴板写入权限、系统剪贴板内容或 Android 隐私提示；不宣称阻止系统级剪贴板访问。
6. 增加 parser/publisher/UI/运行时端到端测试：开关关闭、开关开启、写入成功、写入异常、空缓存、读写并发、共享进程、受保护包名及与 `clipboard_read_block` 冲突。

历史状态记录：本节最初编写时仅完成语义审计。下方 2026-10-30 实现状态为当前状态：API-101 已实现配置、运行时和发布链路；仍未进行设备验证。


### Clipboard isolation implementation status (2026-10-30)

- API-101 config parser/serializer accepts `clipboard_isolate`; conflicting `clipboard_read_block=1` + `clipboard_isolate=1` is rejected transactionally.
- Runtime hooks `setPrimaryClip`, `getPrimaryClip`, `hasPrimaryClip`; stores only successful single-process writes in process-local shadow state. Shared-package processes pass through unchanged.
- FX target editor and Remote Files publisher emit the distinct `clipboard_isolate` field. Privacy master switch gates the feature.
- Host parser tests added. This is not device-verified; Android clipboard service behavior and API-level overload compatibility remain a real-device test item.


## 单 APK 合并审计

详见 `docs/FXHOOK-SINGLE-APK-MERGE-AUDIT.md`。当前两个 APK 的 applicationId、Hook API、入口生命周期、配置通道和最低 Android 版本均不同。不得仅改包名或在安装器中删除旧 APK；必须先完成允许迁移功能的 API-101 实现、配置迁移、签名/升级/回滚演练。对 root/VPN/app-list/identity spoof 等隐蔽或伪造型功能不原样迁移。
