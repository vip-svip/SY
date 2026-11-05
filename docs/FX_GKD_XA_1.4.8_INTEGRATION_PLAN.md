# GKD-XA 1.4.8 — FX 单 APK 融合接管记录

本文件锁定用户指定的 GKD-XA 1.4.8 源码来源与融合边界。锁定源码不等于其运行时已经进入 FX APK。

## 来源与许可

- 仓库：`https://github.com/84593320z/GKD-XA`
- Release：`v1.4.8`，2026-10-31 发布。
- 固定上游 commit：`8a6ce935da11671dac7e1a7595416ec99ee07436`。
- 许可证：GPL-3.0。
- FX submodule 路径：`vendor/GKD-XA`。
- 必须保留版权、GPLv3 文本、来源与修改记录；组合程序分发时必须满足 GPLv3 对应源代码、许可和交互式法律声明要求。不得将 GKD-XA 代码重新标成 FX 独有或闭源。

## 必须迁入的实际功能域

GKD-XA 是一套完整的辅助自动化运行时，不是一个普通无障碍开关。必须逐项移植并验证：

1. 高级选择器语法、解析/编译、节点关系和属性匹配、快速查询及全量查询回退。
2. 订阅源、本地订阅、规则组、分类、应用范围、排除项、导入导出、刷新、并发保存和恢复。
3. 自动点击/跳过流程、触发条件、次数/冷却/延迟、动作与运行模式。
4. 快照采集/审查、手动规则生成、AI 加强模式、截图隐私处理。
5. 多 AI 服务商、模型管理、连接测试、协议、预算/重试；凭据只保存在 FX 安全存储中。
6. 触发历史、事件日志、应用列表、每应用规则、状态与诊断。
7. 无障碍/自动化授权、特权通信、后台保活、开机恢复、通知、快捷设置磁贴、外部调用、备份恢复。
8. 原版业务页面及交互；最终 UI 改由 FX 五 Skin 与六个业务 Tab 承载。

## 上游模块

| 模块 | 职责 | FX 融合方向 |
| --- | --- | --- |
| `gkd-app` | UI、ViewModel、订阅/权限、无障碍运行时、服务/Receiver | 拆分为 FX Hook 与脚本内部路由；不保留第二 Launcher 或第二 APK |
| `gkd-aidl` | 特权进程 AIDL | 审计后统一接入 FX 特权桥 |
| `gkd-db` | Room 数据、订阅配置 | 评估沿用/迁移 schema，统一备份恢复 |
| `gkd-hidden-api` | 隐藏 API 适配 | 按 Android 版本、Root 授权和 SELinux 单独审计 |
| `gkd-selector` | Kotlin Multiplatform 选择器引擎 | 优先独立迁入并保留上游测试；禁止用简化正则代替 |

## 不能直接把上游 app 模块当普通 Activity 加入

源码检查确认，`gkd-app` 使用自己的 `li.gkd.app.App` Application、`MainActivity`、`AppRoot`、`MainViewModel` 和运行时初始化。其 Manifest 还声明无障碍服务、前台服务、JobService、BootReceiver、TileService、FileProvider、`gkd://` 入口和多项权限。FX 已有自己的 Application、`de.privacyguard.adhook.MainActivity`、Root/LSPosed/Accessibility 与服务生命周期。

融合必须：
- 保留 FX 的 applicationId、版本 1.0.0 和唯一 Launcher；不安装第二个 GKD-XA 包。
- 合并 GKD 的服务、Receiver、Provider、权限与生命周期，不能机械复制 Manifest 导致 authority、组件身份和权限冲突。
- 设计统一 Accessibility 事件/动作管线，避免两个服务重复匹配、重复点击、重复截图和后台耗电；不能仅仅同时启用两个 AccessibilityService 就宣称融合。
- 保留订阅/数据库数据迁移、并发写入保护、备份恢复和回滚。
- 将 GKD 页作为 FX Hook / 脚本 / 设置子路由，并显示 FX 六 Tab 主导航。

## 构建兼容性冲突

| 项目 | AGP | Kotlin | Java/JVM | SDK |
| --- | --- | --- | --- | --- |
| FX 当前 `adhook` | 9.1.1 | 2.4.21 | 17 | compile 37 / min 28 |
| GKD-XA v1.4.8 | 9.4.1 | 2.4.20 | 21 | compile 37 / min 26 |

GKD-XA 根工程把 Kotlin JVM target 设为 21，并依赖 Compose、Room 3、Ktor、Shizuku、priv-kit、MIUIX 与 selector 模块。当前 FX 的 Java 17/Gradle 构建不能直接认定兼容。先做唯一 Gradle 构建图兼容 spike，确认 AGP/Kotlin/JDK/Gradle wrapper，再纳入模块与 Manifest。不要提前开启 `migration_complete=true`。

## 目标页面映射

- Hook：应用列表、每应用规则、选择器、触发记录、快照、运行状态与自定义规则。
- 脚本：规则脚本/编辑工作流；与 FX QuickJS、Surge/Loon 脚本明确区分。
- Ad：只有明确属于广告跳过的规则及统计进入 Ad；不能把 GKD 全部规则默认当广告规则。
- 设置：全局工作模式、权限、通知与备份等系统级偏好归入设置。
- 用户不可见“打开 GKD-XA”来源应用启动器、第二入口或第二 APK。

## 验收门槛

- 单 APK、单 applicationId、单 Launcher；没有 GKD-XA 第二安装包。
- selector/parser/engine 与订阅解析/匹配测试进入 CI。
- 订阅、规则组拖拽/删除、排除项、备份恢复、并发保存和崩溃恢复测试。
- 无障碍授权/撤销、服务崩溃恢复、开机恢复、特权模式和保活在 AOSP 与 ColorOS/HyperOS 设备实测。
- 同一事件不得重复执行同一规则；加入去重、互斥、冷却和耗电测量。
- 五种 Skin × Hook 核心页面 UI 自动化/截图验收。
- GPLv3 对应源代码、版权/许可、修改标记和界面法律声明完整。

## 当前状态

本批只固定了 GKD-XA v1.4.8 来源，并确认模块、许可和构建兼容性边界。**GKD-XA 的运行时、服务、UI、数据库和选择器尚未合并进 FX APK。**下一批必须先完成 Gradle/Manifest compatibility spike，再迁入 selector engine 与 subscription repository，之后才迁入 Compose 子路由和统一 Accessibility runtime。
