# FXHook 单 APK 双入口合并审计 — FX 1.0.0

审计日期：2026-10-31（基于 GitHub Actions Run #73 产物）

## 当前已实现结构

| 项目 | 当前状态 |
|---|---|
| 安装包 | `optional/FXUnifiedHook.apk`，单一 APK |
| applicationId | `de.privacyguard.adhook` |
| 现代入口 | `de.privacyguard.adhook.AdVisibilityHook`，libxposed API 101 |
| 现代入口发现 | `META-INF/xposed/java_init.list` |
| 兼容入口 | `de.privacyguard.hook.MainHook`，legacy Xposed 入口 |
| 兼容入口发现 | `assets/xposed_init` |
| 安装方式 | PackageManager 安装一个普通应用包；LSPosed 中配置目标作用域 |
| CI 构建 | GitHub Actions Run #73 完成 Gradle APK 重建和 KernelSU ZIP 打包，状态 success |

完整旧版 `MainHook.java` 保留在 `lsposed/app/src/main/java/de/privacyguard/hook/MainHook.java`，CI 打包流程将兼容入口纳入统一 APK。当前统一的是安装包和双运行时入口，不等于 75 个历史开关已全部迁移为 API-101 原生实现。

## 迁移状态与安全边界

- 迁移基线记录 75 个旧版开关；当前已在现代配置/策略路径中覆盖 7 项传感器开关、Wi-Fi 扫描、通知监听读取、通知权限查询遮蔽和进程内剪贴板隔离。
- 其余旧版功能仍需按迁移矩阵逐项验收，不能因双入口同包就标记为 API-101 功能完全等价。
- 广告/会员相关诊断保持只读；不伪造 VIP、登录、购买、奖励或服务端授权结果。
- 未知包名、未知状态和不支持的 Hook 场景应保持 fail-open；高风险伪装和生产授权覆盖保持关闭。

## 仍需完成的验证

1. 对 75 项逐项核对 UI、配置发布、运行时 Hook 和回滚语义；区分 API-82 兼容入口与 API-101 原生迁移。
2. 验证单包升级、旧包所有权标记、签名一致性、回滚和卸载行为。
3. 在 OnePlus 12 + KernelSU + LSPosed 真机验证 APK 安装、两个入口注入、目标作用域、配置 Remote Files、实际功能和卸载回滚。

## 当前验收边界

- 已验证：CI Gradle 构建、APK 归档和 SHA-256、KernelSU ZIP 归档、聚焦回归测试。
- 未验证：OnePlus 12 真机注入与实际运行行为。
- 不宣称：75 项 API-101 全量迁移完成，或所有目标应用均兼容。
