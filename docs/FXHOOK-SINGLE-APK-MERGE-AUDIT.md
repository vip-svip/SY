"# FX Hook 单 APK 合并结果 — FX 1.0.0

状态：源码与安装包迁移已实现；CI/打包回归待本次工作流完成；OnePlus 12 真机升级验证仍待执行。

## 统一架构

- 唯一安装包：optional/FXAdHook.apk
- 唯一 applicationId：de.privacyguard.adhook
- 唯一 API-101 运行时：libxposed
- 唯一入口：de.privacyguard.adhook.AdVisibilityHook
- 唯一配置通道：LSPosed Remote Files fx-hook-targets.conf
- API-82 PrivacyGuardHook.apk 不再打入新的 FX ZIP，也不再由安装器安装。

## 旧模块迁移边界

旧 MainHook 的实际功能是从 PackageManager 查询结果中隐藏一组 VPN/系统应用。它没有可迁移的普通隐私策略或独立配置功能。该应用隐匿逻辑不移植到统一运行时；不伪称旧模块的应用隐藏功能仍然存在。

新安装器先安装并确认 API-101 APK 成功，再根据旧版 FX 所有权标记清理 API-82 包。若缺少 .fx-owned 所有权标记，则保留该包，避免卸载用户原有应用。签名不兼容时不强制卸载，也不清除应用数据。

## 已迁移并保留的 API-101 功能

广告视图观察/过滤、按目标应用配置的隐私策略、剪贴板进程隔离、EXIF 脱敏、传感器/麦克风/相机/位置访问策略、Wi-Fi 扫描和通知相关隐私策略，以及只读会员/计费诊断仍由统一 API-101 模块提供。购买结果、会员权益和服务端授权状态不会被伪造或改写。

## 验收状态

- [x] 单 APK / 单 applicationId / 单 libxposed API-101 入口。
- [x] 新 ZIP 不再包含 API-82 APK。
- [x] 安装器只安装一个 APK。
- [x] 仅清理有 FX 所有权标记的旧 API-82 安装。
- [x] 卸载时保留所有权不明或用户预先安装的应用。
- [x] 固定版本 1.0.0。
- [ ] 本次 GitHub Actions 完成单 APK 构建和回归测试。
- [ ] OnePlus 12 + KernelSU + LSPosed 真机安装、scope、升级、卸载与回滚验证。

签名不兼容时不卸载用户现有包，不删除用户数据。未完成真机验证前，不宣称设备端整合已验证。
