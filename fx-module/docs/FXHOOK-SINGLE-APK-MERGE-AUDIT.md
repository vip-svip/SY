# FXHook 单 APK 合并审计 — FX 1.0.0

审计日期：2026-10-30

## 当前事实

| 项目 | API-82 旧模块 | API-101 新模块 |
|---|---|---|
| applicationId | `de.privacyguard.hook` | `de.privacyguard.adhook` |
| Gradle namespace | `de.privacyguard.hook` | `de.privacyguard.adhook` |
| Hook API | `de.robv.android.xposed:api:82` | `io.github.libxposed:api:101.0.1` |
| 入口 | `de.privacyguard.hook.MainHook` | `de.privacyguard.adhook.AdVisibilityHook` |
| 入口发现 | `assets/xposed_init` | `META-INF/xposed/java_init.list` |
| minSdk | 27 | 28 |
| 配置通道 | `/data/local/tmp/privacyguard/xposed.conf` | LSPosed Remote Files `fx-hook-targets.conf` |
| 安装包 | `optional/PrivacyGuardHook.apk` | `optional/FXAdHook.apk` |

安装脚本当前安装两个独立 package。API-101 是当前统一配置/新功能方向，但还没有覆盖 API-82 的完整功能集。

## 为什么不能直接合并

1. API-82 的 `XposedBridge` / `IXposedHookLoadPackage` 入口不能直接当作 libxposed API-101 的入口。
2. API-101 采用 `XposedModule` 生命周期、`onModuleLoaded` / `onPackageReady` 和 Remote Files；旧模块依赖 `handleLoadPackage` 和旧文件配置。
3. 两个 applicationId 改成同一个值不会合并入口，反而会造成 PackageManager 更新冲突；同包升级还要求签名一致并保留数据。
4. API-101 `minSdk=28`，旧模块 `minSdk=27`。统一包若保留 API-101 运行时，必须明确放弃 Android 8.1/API 27 支持或为旧系统提供独立兼容路径。
5. 两个模块当前 scope、配置格式和初始化时机不同。未经迁移的旧功能可能在合并后静默失效。

## 迁移分级决策

### 可评估迁移（逐项独立开关、默认关闭、失败放行）

- 相机/麦克风访问阻止：只迁移明确的访问阻止语义；不迁移“硬件不存在”伪装。
- EXIF 读取脱敏：仅限已明确支持的解析器，不宣称覆盖全部第三方解析器。
- 传感器读取限制：按类型、按目标应用控制，并保持未知类型 fail-open。
- 通知访问状态查询隐私：只改变目标应用可见的查询结果，不更改系统真实授权。
- 剪贴板进程本地隔离：仅进程内 shadow，不宣称系统级跨应用隔离。

### 不原样迁移

- Root/KernelSU/Magisk 痕迹隐藏、文件系统/挂载伪装、系统属性伪装。
- VPN 可见性隐藏、应用列表/PackageManager 查询隐藏、进程列表隐藏。
- IMEI/SIM/序列号/MAC 等硬件身份伪造。
- 假定位/GNSS 伪造、无障碍/使用情况/通知权限伪装。

这些能力可能破坏系统安全边界、误导目标应用安全判断或造成设备/应用异常。若确有隐私需求，应改为透明、可审计的权限控制，而不是隐蔽或伪造检测结果。

## 单 APK 合并路线

1. API-101 保留为唯一未来入口；逐项把允许迁移的功能改写为 libxposed interceptor。
2. 把旧 `xposed.conf` 的可迁移设置映射到版本化 Remote Files schema；转换必须可回滚，未知键不得静默丢弃。
3. 在目标应用配置 UI 中明确区分“已迁移”“仅旧版支持”“不再支持”，不允许未迁移功能看似生效。
4. 建立旧包到新包的升级策略：先核对签名、备份两边私有配置、安装统一 APK、迁移配置、验证 LSPosed scope，再清理旧包。任何一步失败均保留旧 APK 和配置。
5. 最后才统一 applicationId 和安装脚本；不能在功能迁移前删除 `PrivacyGuardHook.apk`。
6. 统一包的 minSdk、签名密钥、LSPosed module metadata、scope 和卸载清理行为必须有自动化升级回归。

## 当前未完成项

- API-82 的大部分功能尚未迁移。
- 两个 APK 仍然独立安装；唯一 applicationId / 唯一入口尚未实现。
- 尚未完成签名兼容性与真实设备升级演练。
- 尚未在 OnePlus 12 + KernelSU + LSPosed 上验证新旧模块注入与配置迁移。

## 验收门槛

- 单 APK、单 applicationId、单 libxposed API-101 入口。
- 所有迁移功能有 parser/publisher/runtime 测试，明确失败放行策略。
- 对未迁移/拒绝迁移功能有 UI 标记与文档，不伪称兼容。
- 旧版升级、回滚、卸载不丢失用户数据；签名不兼容时不强制卸载。
- OnePlus 12 真机完成安装、启用、目标作用域、功能回归、卸载/回滚测试。
