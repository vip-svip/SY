# FXHook 单 APK 双入口合并审计 — FX 1.0.0

审计日期：2026-10-31

## 当前交付结构

| 项目 | 状态 |
|---|---|
| 安装包 | `optional/FXUnifiedHook.apk`，安装器只安装一个 APK |
| applicationId | `de.privacyguard.adhook` |
| modern 入口 | `de.privacyguard.adhook.AdVisibilityHook`，libxposed API 101 |
| legacy 兼容入口 | `de.privacyguard.hook.MainHook`，由同一 APK 的 `assets/xposed_init` 暴露 |
| modern 入口发现 | `META-INF/xposed/java_init.list` |
| 安装脚本 | 根目录和 KernelSU 模块目录的安装器保持一致，只安装统一 APK |
| 旧包升级 | 统一 APK 安装成功后，仅清理带 FX 所有权标记的旧独立 legacy 包；预先存在的用户包不卸载 |

本轮修复了安装脚本仍安装 `PrivacyGuardHook.apk` + `FXAdHook.apk` 两个 APK 的实质性缺陷。此前文档声称单 APK，但安装器仍为双 APK，这是实现与审计记录不一致。本次统一为 `FXUnifiedHook.apk` 单包安装。

单 APK 双入口不代表 75 个历史开关全部迁移成 API-101 原生功能。旧版兼容入口保留以承接尚未迁移的允许功能；现代入口的功能覆盖必须按迁移矩阵逐项验收。

## 安全与回滚边界

- 安装前校验 APK SHA-256；签名不匹配时不卸载旧包、不清除应用数据。
- 仅对首次由 FX 安装的包写入所有权标记；卸载时只移除有 FX 所有权证明的包。
- 广告/会员诊断保持只读；不伪造 VIP、登录、购买、奖励或服务端授权。
- 未知包名、共享进程和不支持的 Hook 场景保持 fail-open。

## 未完成验收

1. 75 项历史开关仍需逐项核对 UI、配置发布、运行时 Hook 和回滚语义。
2. 必须执行安装/升级/签名冲突/卸载自动化回归及完整 Gradle 构建。
3. 必须在 OnePlus 12 + KernelSU + LSPosed 真机验证两个入口注入、目标作用域和配置 Remote Files。
