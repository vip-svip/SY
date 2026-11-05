# FX 应用内 Hook（LSPosed）说明

## 与旧「Hook」列表的区别

- `[list:hook]` 是现有的 UID 网络阻断名单，只通过防火墙阻止应用联网；它不是应用进程内的 Xposed Hook。
- `[list:hook_targets]` 才是应用内 Hook 目标，格式为 `com.example.app,splash=1,feed=1,overlay=0,member_diag=0|FX LSPosed Hook|1`。
- `hook_ads_enabled=1` 是新功能的主开关，默认 `0`。

## 双重作用域要求

1. 在 FX 的「应用内 Hook（LSPosed）」中打开主开关，选中目标 APP 和相应类别。
2. 在 LSPosed 管理器启用 **FX Ad Hook**，并为它选择完全相同的目标 APP。两个名单必须都包含此应用。
3. FX 会把两个 Hook APK 作为普通应用安装到 `/data/app`，Hook APK 本身不依赖 metamodule 挂载；安装/升级后重启一次，再强行停止并重新打开目标 APP。若安装期 PackageManager 尚不可用，开机脚本会重试，结果见 `/data/adb/privacyguard/adhook-install.log`。
4. FX 无法读取 LSPosed 管理器的真实作用域状态，页面不会声称已验证运行；需要检查 LSPosed 日志中的 `[FXAdHook] package ready=...`。主模块会先把最小 Hook 配置写入 LSPosed Remote Files；配置文件发布失败时会在应用日志中报错，不会把“仅写入 settings.conf”当成 Hook 生效。当前内置 APK 通过 GitHub Actions 构建为 debug-signed 验证包，不是最终发布签名。

## 内置规则范围

内置分类包含开屏/启动页、信息流/原生/横幅和插屏/弹窗/悬浮窗。扫描 Activity 视图树，并覆盖 Dialog.show() 与 PopupWindow 展示的独立窗口；使用 SDK 类名、资源 ID 与强广告容器标记识别，不会仅凭「广告」文本隐藏控件。扫描限制为深度 20、单次最多 1800 个 View，并在 180/650/1500/3200ms 分批重试，避免持续轮询。内置 SDK 命名空间包含 Google Mobile Ads、穿山甲/Pangle、腾讯优量汇、快手、百度、AppLovin、Meta、Unity、Sigmob、华为 HMS Ads、小米 MiMo，以及常见 OPPO/Vivo/Honor/美数广告 SDK。小米开发者文档公开的 SDK 包名包含 `com.miui.zeus.mimo.sdk`，华为文档包含 `com.huawei.hms.ads`。这些是辅助识别信号，并非每个命中类都必然是广告；专有/混淆布局需要按具体 APP 适配，不能保证覆盖所有 APP。

## 会员功能边界

`member_diag=1` 仅记录 Google Play Billing 的方法名和结果类型，供排查购买状态/兼容性问题；不记录账户、SKU 或购买令牌，也不会改写 BillingResult、购买状态或 entitlement。它不是 VIP 解锁功能。

## 无效配置与回退

配置缺失、包名无效、目标行禁用、主开关关闭或未被 LSPosed 加载时都不执行 Hook。应用列表读取为空时，UI 会取消刷新，避免把现有目标名单误删。

## 参考与兼容边界

- LSPosed 官方模块开发说明区分 legacy Xposed API（`assets/xposed_init` 与 Manifest metadata）和 modern libxposed API（`META-INF/xposed/*`）；本轮更新的 APK 使用 modern libxposed API 101，并通过 `openRemoteFile()` 读取 LSPosed Remote Files；不会让目标 App 直接读取 `/data/local/tmp` 或 `/data/adb`。需要支持 API 101 Remote Files 的 LSPosed 版本；旧的仅支持 legacy API 的框架不会执行该子模块。
- 小米 MiMo 广告 SDK 官方文档：`https://dev.mi.com/distribute/doc/details?pId=1659`，公开包名 `com.miui.zeus.mimo.sdk`，并包含开屏/插屏等广告形态。
- Huawei HMS Ads 包参考：`https://developer.huawei.com/consumer/jp/doc/HMSCore-References-V5/package-summary-0000001050064868-V5`，列出 `com.huawei.hms.ads` 等类包。
- 其余 SDK 命名空间是适配指示，不代表对其全部版本/所有 App 的保证；只在启用的目标 APP 作用域中扫描，不影响未选择的应用。

## APK 安装方式

FXAdHook 与旧 PrivacyGuardHook 现在都从 `optional/` 目录由 `scripts/install_adhook_app.sh` 安装为普通 Android 应用，不再放在 `system/priv-app/`。安装器只调用 Android PackageManager，不修改防火墙、DNS、VPN 或路由设置；安装失败会留日志并且不会阻止 FX 核心启动。
