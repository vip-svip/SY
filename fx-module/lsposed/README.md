# PrivacyGuard LSPosed 子模块

应用层隐私防护 Hook（Xposed API 82+，LSPosed 推荐，minSdk 27 / targetSdk 34）。
读取 `/data/local/tmp/privacyguard/xposed.conf`，键名与主模块 WebUI 的 `data-key` 一致，可独立开启/关闭每类 Hook。

## 构建

```bash
cd lsposed
gradle :app:assembleRelease
# 产物: app/build/outputs/apk/release/app-release-unsigned.apk
```

或使用 Android Studio 打开本目录直接构建。APK 安装后在 **LSPosed 管理器 → 模块** 中启用，并在作用域中勾选需要防护的应用（默认仅 android 系统进程，建议手动勾选目标应用）。

## 实现的 Hook（~70 个开关键，对应 WebUI 开关）

### ⚠ 破坏性 Hook 与档位（lsposed_profile）— 先读这一段

本模块有两类 Hook，安全等级完全不同：

| 类别 | 行为 | 对宿主 App 的风险 |
|---|---|---|
| **功能屏蔽 / 伪装**（spoof_*、cam_null、mic_block、sensor_*、mock_location…） | 返回**看起来合理**的值（假机型、假坐标、静音样本） | 低。App 只是拿到不同的数据，API 契约没被破坏 |
| **破坏性拦截**（block_pm_query、block_mounts、hide_su、fs_*、usagestats_off…） | 让系统 API 返回**空 / false / 抛异常** | **高**。App 里 `list.get(0)`、`resolveActivity(...).activityInfo`、读 `/proc/mounts` 的代码会直接 NPE/IOOBE/FileNotFoundException |

破坏性拦截只有在你**把某个 App 放进 LSPosed 作用域**时才会作用于它。默认作用域只有 `android`，而 MainHook 会跳过 system_server，所以**新装状态下不会 Hook 任何进程**。

#### 三个档位

设置项 `lsposed_profile`（在 `scripts/default.conf` 顶层，随 `gen_xposed_conf.sh` 透传到 `xposed.conf`）：

| 档位 | 含义 | 破坏性 Hook |
|---|---|---|
| `compat`（**默认**） | 零破坏。勾了普通 App 也不会改变它的任何行为 | 全部关闭 |
| `standard` | 只留 root 痕迹隐藏 | 仅 `hide_su` `hide_magisk` `hide_ksu` `hide_sysfs_nodes` `hide_kernel_debug` `block_rootcheck_libs` `ad_id_unify` |
| `aggressive` | 全部打开（旧 v1.10.4 逐键全开的效果） | 全部开启 |
| `custom` | 按各逐键开关走（旧配置兼容） | 由逐键值决定 |

**档位优先于逐键开关**：选了 `compat` 时，即使 `block_pm_query=1` 也不会生效。这保证「选兼容模式」是一个真正的安全承诺，而不需要用户理解 30 多个开关。

#### 破坏性 Hook 清单（34 个键）

- **进程/包/存储/网络统计**：`block_process_list` `block_pm_query` `block_mounts` `hide_mounts` `block_netstats` `block_net_ifaces` `block_cell_info` `block_mediastore` `usagestats_off` `k_task` `app_list`
- **root/文件痕迹**：`hide_su` `hide_magisk` `hide_ksu` `block_rootcheck_libs` `hide_sysfs_nodes` `hide_kernel_debug` `block_logcat` `fs_attrs` `fs_hide` `fs_rootlist` `fs_isolate` `fs_vfs`
- **系统能力枚举**：`block_notif_listen` `hide_notif_perm` `block_ime_logging` `a11y_hide` `syssvc_hide` `clipboard` `clipboard_isolate` `ad_id_unify` `block_wifi_scan` `vpn_hide` `block_kernel_version`

#### 崩溃兜底

所有 Hook 体都跑在 `SafeHook` 里（`beforeHookedMethod`/`afterHookedMethod` 是 `final`，内部 try/catch 包住 `onBefore`/`onAfter`）。Hook 抛出的任何 `Throwable` 都只 `XposedBridge.log` 然后丢弃，**绝不会穿到宿主 App 的调用点**。所以模块最坏情况是「这条 Hook 没生效」，而不是「宿主 App 崩了」。

#### 作用域

- `NEVER_HOOK` 强制跳过：`android`(system_server)、`system`、`de.privacyguard.hook`(自身)、`org.lsposed.manager`
- 可选白名单 `[conf:lsposed_scope]`：每行一个包名 / 一行逗号分隔 / `com.example.*` 前缀通配。**留空 = 完全沿用 LSPosed 管理器里勾选的作用域**（默认行为）。
- `res/values/arrays.xml` 的 `xposed_scope` 默认只有 `android`，配合上面的跳过规则 = 默认不 Hook 任何进程。

### 设备伪装

| 开关键 | 作用 |
|---|---|
| lsposed_enabled | Hook 总开关（0 时本模块完全休眠） |
| spoof_model / spoof_manufacturer / spoof_brand / spoof_hardware | Build.MODEL/DEVICE/PRODUCT/MANUFACTURER/BRAND/HARDWARE/BOARD，值取 [conf:spoof_*] 段 |
| spoof_fingerprint | Build.FINGERPRINT |
| spoof_version | VERSION.RELEASE + SDK_INT |
| patch_spoof | VERSION.SECURITY_PATCH |
| spoof_baseband | Build.getRadioVersion() |
| spoof_serial | Build.getSerial() + Build.SERIAL 字段 |
| spoof_android_id | Settings.Secure.getString(android_id) 返回按包名派生的稳定假 ID |
| block_kernel_version | Build.KERNEL=4.14.180-perf + System.getProperty("os.version") |
| spoof_imei / spoof_sim / telephony | TelephonyManager getDeviceId/getImei/getMeid/getSimSerialNumber/getSubscriberId/getGroupIdLine1/getLine1Number/getNetworkOperator*，值取 [conf:telephony] 与 [conf:spoof_*] 段 |
| block_cell_info | getAllCellInfo() 返回空、getCellLocation() 返回 null |
| spoof_bt_mac / spoof_wifi_mac | BluetoothAdapter.getAddress / WifiInfo.getMacAddress/getBSSID |
| spoof_battery | BatteryManager.getIntProperty（容量/健康/状态），值取 [conf:spoof_battery] |
| spoof_screen | Display.getMetrics/getRealMetrics 尺寸，值取 [conf:spoof_screen] size=宽x高xDPI |
| spoof_storage | File.getTotalSpace/UsableSpace/FreeSpace + StatFs 全方法，总量取 [conf:spoof_storage] total=GB |

### 应用信息与查询

| 开关键 | 作用 |
|---|---|
| app_list | getInstalledPackages/getInstalledApplications 三模式（[conf:app_list] mode=empty/custom/allowlist + hide/keep 名单；custom 时 getPackageInfo/getApplicationInfo 抛 NameNotFoundException） |
| block_pm_query | queryIntentActivities/Services/Receivers/Providers + queryContentProviders 返回空 |
| block_process_list | ActivityManager.getRunningAppProcesses/Services/Tasks/RecentTasks 返回空 |
| block_mediastore | ContentResolver.query(content://media/*) 返回空 MatrixCursor |
| block_net_ifaces | NetworkInterface.getNetworkInterfaces 返回空枚举 |
| vpn_hide | **隐藏 VPN/节点**（8 类检测全覆盖）：① NetworkInterface getNetworkInterfaces/getNetworkInterfacesList 过滤 tun/ppp/ipsec/wg/vpn/tap 虚拟网卡（保留物理网卡）；② NetworkCapabilities hasTransport(TRANSPORT_VPN)=false / hasCapability(NOT_VPN)=true / toString 去 VPN 字样；③ ConnectivityManager.getNetworkCapabilities 传输类型改写为 WIFI；④ VpnService.prepare 返回 null；⑤ /proc/net/tcp|udp|tcp6|udp6 读取时删除代理客户端本地端口（7890/1080/8080/9090… + [conf:vpn] local_port）所在行；⑥ /proc/net/route|ipv6_route 删除 Iface 列为虚拟网卡的行（默认路由痕迹）；⑦ PackageManager getInstalledPackages/getInstalledApplications 过滤已知代理客户端包名（clash/mihomo/v2ray/xray/singbox/sing-box/shadowsocks/surfboard/surge/trojan/hysteria/naiveproxy/nekoray/v2rayng/ssr）；⑧ SystemProperties.get("http.proxyHost"/"https.proxyHost") 返回空 + TrafficStats getUidRxBytes/getUidTxBytes 对 uid≥10000 归零。shell 侧配合见主 README「隐藏强度分级」（hide_level L0/L1/L2） |
| block_netstats | TrafficStats 全部 10 个计数方法返回 0 |
| ad_id_unify | GMS AdvertisingIdClient$Info.getId + 华为 OAID 返回按包名派生的稳定 UUID |
| usagestats_off | UsageStatsManager.queryUsageStats 返回空列表 |
| a11y_hide | AccessibilityManager.getEnabled/InstalledAccessibilityServiceList 返回空 |
| hide_notif_perm | NotificationManager.areNotificationsEnabled 返回 false（应用误以为通知权限被拒） |

### 剪贴板与输入

| 开关键 | 作用 |
|---|---|
| clipboard | getPrimaryClip 返回 null / hasPrimaryClip false（block）；或返回 [conf:clipboard] fake_text 文本（fake 模式） |
| clipboard_isolate | 进程级剪贴板隔离：每个应用只能读到自己写入的内容 |
| block_ime_logging | InputMethodManager getEnabledInputMethodList/getInputMethodList 返回空 + Settings.Secure default_input_method 清空 |

### 定位与传感器

| 开关键 | 作用 |
|---|---|
| mock_location | getLastKnownLocation/getCurrentLocation/requestLocationLocations 投递 [conf:mock_location] 坐标（lat/lng/acc）；isFromMockProvider 返回 false |
| perapp_mock | [conf:perapp_mock] 行 `包名=纬度,经度` 按应用单独伪造坐标 |
| gps_accuracy | 假坐标精度取 [conf:gps_accuracy] accuracy（米） |
| gnss_spoof | registerGnssMeasurements/NavigationMessage/StatusCallback 返回 false + getGnssHardwareModelName=""/YearOfHardware=2016/BatchSize=1 |
| disable_passive_loc | LocationManager.getProviders/getAllProviders 剔除 passive，getBestProvider 降级为 gps |
| block_wifi_scan | getScanResults 空 + startScan false + isScanAlwaysAvailable false |
| sensor_accel / sensor_gyro / sensor_light / sensor_magnet / sensor_pressure / sensor_prox | 对应类型 getSensorList 空 + getDefaultSensor null |
| sensor_rate_limit | registerListener 采样率钳制到 ≥100000µs（10Hz） |

### 相机 / 麦克风 / 生物识别

| 开关键 | 作用 |
|---|---|
| cam_null | CameraManager.openCamera 抛 CameraAccessException(CAMERA_DISABLED) |
| cam_hw_hide | getCameraIdList 返回空数组 |
| mic_block | AudioRecord.startRecording 返回错误（[conf:mic_block] mode=error/silence/noise：read 返回静音或加噪数据） |
| mic_hw_hide | AudioManager.getMicrophones 返回空 |
| audio_fp_block | AudioRecord.read 后对样本加微扰动，破坏声纹指纹（mic_block=silence 时自动跳过） |
| hide_fingerprint_hw | FingerprintManager(+Compat) isHardwareDetected/hasEnrolledFingerprints=false |
| hide_face_hw | FaceManager isHardwareDetected/hasEnrolledFaces=false |
| （两者任一） | BiometricManager.canAuthenticate 返回 12(BIOMETRIC_ERROR_NO_HARDWARE) |

### 通知 / 通知监听

| 开关键 | 作用 |
|---|---|
| block_notif_listen | NotificationManager+NotificationListenerService getActiveNotifications 返回空 + Settings.Secure enabled_notification_listeners 清空 |

### 媒体元数据

| 开关键 | 作用 |
|---|---|
| exif_strip | android.media.ExifInterface + androidx.exifinterface 的 getAttribute*(GPS*/Make/Model/DateTime*) 返回 null、getLatLong 返回 false；[conf:exif_strip] strip=gps,device,time 可选范围 |

### Root / 文件系统遮蔽

| 开关键 | 作用 |
|---|---|
| hide_su / hide_magisk / hide_ksu / block_rootcheck_libs | 内置 26 条 Root 路径 + [conf:fs_rootlist]；File.exists/canRead/isDirectory/isFile/length 全拦 |
| hide_magisk 另含 | Runtime.exec/ProcessBuilder.start 拒绝 su/magisk/ksu/apd/busybox 等命令 |
| fs_hide | [conf:fs_hide] 路径同上拦截 + listFiles 过滤 |
| fs_isolate | [conf:fs_isolate] 路径 listFiles 返回空数组（目录存在但看不到内容） |
| fs_vfs / block_mounts / hide_mounts | FileInputStream/FileReader 构造器对 /proc/mounts、/proc/self/mountinfo 等抛 FileNotFoundException + File.listFiles 过滤 + exec 拒绝 mount |
| hide_sysfs_nodes | /sys/fs/selinux、/sys/kernel/debug 等路径同上拦截 |
| fs_attrs | SystemProperties.get 对 [conf:fs_attrs] 中属性返回伪造值（默认 ro.debuggable=0/ro.secure=1），exec 拒绝 getprop |
| hide_kernel_debug | SystemProperties ro.debuggable=0/ro.secure=1（应用进程内） |
| block_logcat | Runtime.exec/ProcessBuilder 拒绝 logcat 命令 |

### 系统服务

| 开关键 | 作用 |
|---|---|
| syssvc_hide | Context.getSystemService 对 [conf:syssvc_hide] 中列出的服务返回 null（默认 clipboard/location） |

## 配置流转

主模块 `scripts/gen_xposed_conf.sh` 在每次 apply 时把 `settings.conf` 同步到 `/data/local/tmp/privacyguard/xposed.conf`（chmod 644 + shell_data_file:s0，应用可读）：
顶层开关区全量透传（`lsposed_profile` 做合法值校验，非法值统一落 `custom`）+ 指定 `[conf:段]`（clipboard/app_list/telephony/mock_location/perapp_mock/gps_accuracy/spoof_*/mic_block/exif_strip/fs_*/syssvc_hide/patch_spoof/vpn/lsposed_scope 等 37 段；`vpn` 段透传供 `vpn_hide` 读取 local_port 生成 /proc/net 过滤端口集）。
WebUI 修改开关 → 点击「应用」→ 应用层 Hook 下次启动目标应用时生效（Xposed Hook 在进程启动时装载）。

## 已知限制

- Hook 在目标应用进程内生效，需重启目标应用才会装载新配置。
- system_server（"android" 包）、`system`、LSPosed 管理器与 PrivacyGuard 自身进程不加载 Hook（`NEVER_HOOK`）。
- 无 LSPosed 时这些键仅由 shell 层处理或只持久化（详见主 README 功能矩阵）。
- 破坏性 Hook 的行为是「改变宿主看到的系统 API」，**不是**「让 App 更安全」——把它勾到一个正常 App 上只会破坏该 App。请只在明确需要对抗检测的目标 App 上使用 `standard`/`aggressive`。
