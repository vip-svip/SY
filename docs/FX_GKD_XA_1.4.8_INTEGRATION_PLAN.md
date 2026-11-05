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

## 当前状态（2026-11-05，最新代码接入）

### 已落地：选择器、单服务事件管线与本地规则首批垂直切片

1. 上游仓库以 Git submodule 锁定在 `8a6ce935da11671dac7e1a7595416ec99ee07436`（GKD-XA v1.4.8），GPL-3.0 原始许可资产及来源记录保留。
2. FX 只有一个 `:fx-gkd-selector` JVM 17 工程，编译上游 `gkd-selector` 的 `commonMain` / `jvmMain` / tests。没有导入上游 `:gkd-app`，没有第二 Launcher、第二 applicationId 或第二 AccessibilityService。
3. FX 原生适配层：
   - `FxGkdSelectorEngine.kt` 使用上游 Selector parser/compiler、属性类型模型和 NodeAdapter；不是简化正则匹配。
   - `FxGkdAccessibilitySnapshot.kt` 对窗口节点树做有上限的临时快照（最多 700 节点、32 层、每节点最多 80 子节点、文本字段最多 256 字符）；密码和可编辑节点不读取 text/description，不写日志或持久化。
   - `FxGkdRuleStore.kt` 本地存储最多 128 条手动规则，精确包名范围、selector 校验、每规则 1–60 秒 cooldown；总开关默认关闭。
   - `FxGkdAutomationRuntime.kt` 只处理明确启用的本地规则和目标包；250ms 扫描节流、最多匹配 12 个候选、动作前重新检查目标仍可见/可点击/非密码/非可编辑，并只支持 ACTION_CLICK。
4. 运行时已经接入 FX 原有 `FxAccessibilityService`：
   - 未开启 GKD 总开关或目标包没有启用规则时，不获取窗口树。
   - 开启后动态订阅 Window State / Window Content Changed / View Scrolled 事件。
   - 只使用 `getRootInActiveWindow()` 当前窗口，且必须与事件包名一致。
   - 通过单线程执行队列进行匹配，不新增 GKD 独立服务。
   - `fx_accessibility_service.xml` 允许 retrieveWindowContent 是必要能力声明；无障碍说明已明确告知用户：只有总开关和逐应用规则都启用才读取树；不读密码/可编辑文本、不截图、不上传。
5. Hook 页已增加 GKD 自动化入口。独立 `FxGkdAutomationActivity` 目前支持本地包名 + GKD 选择器 + 冷却时间规则创建、语法校验、列表查看、逐条启停与删除，并显示无障碍授权/连接状态。用户必须手动在 Android 系统设置授权无障碍，并手动开启 GKD 总开关。
6. GPL-3.0 许可和来源条目通过 FX 的开源许可证界面展示；发行法律门禁仍未解除，见下文。

### 当前垂直切片明确不包括

- GKD 上游在线/本地订阅下载、刷新/版本、规则组/分类/排除项、应用分组及导入导出。
- 完整触发条件、重复次数、复杂动作、长按/手势、规则优先级/互斥/高级场景匹配。当前只有安全边界下的 Click。
- 快照审查/生成 UI、触发历史与诊断、截图处理、AI Provider/模型与预算。
- GKD 原版 Room 数据层/迁移、Shizuku/AIDL/特权进程、后台/开机/通知/磁贴等生命周期能力。
- 五 Skin × GKD 所有页面的截图和真机验收；目前页面使用 FX 六 Tab 共享宿主，但逐项视觉验收尚未完成。

### 验证分层

- 上游 selector JVM lane 已成功：Run `41982329993` 在 pinned commit 上通过 `:fx-gkd-selector:jvmTest`（这不是 APK 构建证明）。
- 新版独立 workflow `.github/workflows/fx-gkd-selector.yml` 已增加 FX Android App Kotlin/Java compile、单测编译与 `FxGkdSelectorEngineTest`；等待当前提交的最新 run 结果。
- Host 回归 `fx-gkd-selector-integration-regression.sh` 与 `fx-gkd-automation-regression.sh` 校验单一服务身份、默认关闭、目标包范围、快照隐私、冷却与 Hook UI；Host 通过不等于 Android 编译或真机测试。
- 尚未报告当前分支 APK build / device acceptance 通过。必须等待对应 Actions 和后续真机证据，不能提前宣称完整迁移。

### 下一阶段

1. 修正规则存储/事件队列并发与异常恢复测试，验证服务解绑、关闭总开关、撤销单条规则的即时停止。
2. 加入应用选择器（已安装用户应用列表）和规则导入/导出，保持本地数据有版本、有校验、有备份。
3. 移植订阅源/规则组/排除项/规则刷新，并与现有 FX Hosts/Ad 数据域严格区分：GKD 规则不默认视为广告规则。
4. 加入触发历史/诊断，且只记录规则 ID、包名、动作结果与时间，不记录页面原始文本。
5. 评估上游 Room schema 与 FX 备份恢复，再考虑 AI/快照与特权桥；每一项分别做权限、隐私、耗电、兼容测试。
6. 逐一测试 AOSP、ColorOS/HyperOS 的服务启动/停止、撤销授权、锁屏/恢复、窗口变化与重复事件；进行五 Skin × Hook 页面 UI 验收。

### GPL-3.0 许可资产与发行门禁（2026-11-05 更新）

- 已将上游 pinned commit 的 `vendor/GKD-XA/LICENSE` 原文复制到 APK 资源 `adhook/app/src/main/assets/licenses/GKD-XA-GPL-3.0.txt`；原文长度 35,148 bytes，与上游文件保持一致。
- `THIRD_PARTY_NOTICES.txt` 已记录仓库、commit、selector source path、FX wrapper path、许可和未迁移边界。
- 设置中的“开源许可”查看器新增 `GKD-XA v1.4.8 选择器 · GPL-3.0` 条目；文件读取限制 48 KiB，高于该许可正文大小。
- `fx-open-source-licenses-regression.sh` 检查许可原文资产、设置查看入口、来源 commit 和完整文本。
- **发行法律门禁仍未解除**：FX 仓库根目录目前没有项目级 LICENSE。GKD 选择器源码现在编译进单 APK，是否构成需要将整个组合程序按 GPLv3 兼容方式授权/分发，必须由项目权利人确认并完成对应源代码、版权和修改声明安排。不能只因为 APK 内附了 GPL 文本就声称整个 FX 发行合规；在权利与许可范围没有确认前，不得发布为闭源/专有产品，也不得把上游 GKD 代码重新标成 FX 独有。
- 独立选择器 CI 已覆盖 upstream `:fx-gkd-selector:jvmTest`；FX 集成工作流正在增加 Android App 编译和 `FxGkdSelectorRuntimeTest`。应分别报告 upstream JVM 测试、FX App 编译/单测与真机服务验收，不能合并成一个“全部通过”。


## 2026-11-05 — FX 单服务本地规则 Click 试点（覆盖前述“只读、尚无 Hook UI”状态）

> 本节是当前最新实现状态。此前“FxGkdSelectorRuntime 只读匹配”“Hook UI 尚未接入”等状态描述属于更早阶段，现由本节修正。只完成本节列明的功能，不代表 GKD-XA 1.4.8 全量迁移。

### 已落地的源码

1. **上游选择器引擎**
   - FX 工程：`adhook/fx-gkd-selector`，JVM 17，直接编译仓库固定的 GKD-XA v1.4.8 `gkd-selector` 源码；不复制一个简化 selector 实现来替代上游。
   - FX 适配：`FxGkdSelectorEngine.kt`，完成 parse/compile、默认类型模型校验、属性与关系查询，并将 FX 自有节点快照适配到上游 `NodeAdapter`。
   - 选择器输入限制 512 字符；匹配结果最多 12 项。

2. **FX 本地规则存储**
   - `FxGkdRuleStore.kt` 使用独立的 `fx_gkd_automation` SharedPreferences；不与 FX QuickJS 脚本、Ad 订阅规则或旧 GKD 数据库混用。
   - 规则最大 128 条，目标包名必须符合包名格式；UI 新建规则要求目标是已安装的普通用户应用，不能选 FX 自身或系统应用。
   - 冷却限制 1–60 秒；规则默认关闭全局总开关，必须由用户单独启用。
   - 支持新增、逐条启用/停用、删除，以及执行前重新确认当前规则仍启用。

3. **Hook 页面**
   - 新增 `FxGkdAutomationActivity`，作为 FX Hook 第五 Tab 下的内部页面；MainActivity Hook 中有“GKD 选择器自动化”入口。
   - UI 提供系统无障碍授权状态、FX 服务连接状态、GKD 总开关、本地规则新增/编辑（当前支持新增/启停/删除）和规则冷却信息。
   - 刷新规则列表会保留总开关和“添加规则”控件；该行为纳入静态回归。

4. **唯一 AccessibilityService 的事件链**
   - 沿用 FX 原有 `FxAccessibilityService`，没有注册第二个 GKD AccessibilityService、Application、Launcher 或 APK。
   - `canRetrieveWindowContent=true` 是 Android 无障碍能力声明；实际读取树仍由 GKD 总开关和指定包名的启用规则双重门控。
   - 总开关关闭时仅订阅前台窗口变化；启用并存在规则时才动态加入 window-content-changed / view-scrolled 事件。
   - 服务只处理当前事件包名与活动窗口 root 包名一致的树；单线程、单任务并发门、最小事件间隔、节点数/深度/子节点/文本上限，避免并发扫描与无限遍历。
   - Snapshot 不读取密码或可编辑输入框的文本/描述；不截图、不上传、不记录页面文本。
   - 首批动作仅执行用户配置选择器命中的、可见、可点击且非密码/非编辑节点的 `ACTION_CLICK`；不执行手势、不长按、不自动滑动。每规则冷却限制，并在点击前重新检查总开关、规则状态、服务连接和前台包名；目标应用切换或用户关闭后会取消排队动作。

### 第一阶段验收与边界

- 新增 `FxGkdSelectorEngineTest.kt`：覆盖上游属性选择器、Widget 类名、节点关系、无效语法/类型和结果数量上限。
- 新增 `fx-gkd-automation-regression.sh`：检查单 FX AccessibilityService、Hook 子页注册、manifest 无第二 Launcher、总开关/逐应用范围、隐私与树遍历上限、点击前撤销/前台复核。
- `.github/workflows/fx-gkd-selector.yml`：JDK 17 下执行上游 selector JVM 测试、FX App Kotlin/Java 编译、FX GKD selector 单测和上述静态安全回归。
- `.github/workflows/build-fx-adhook.yml` 的静态 Host lane 也执行 GKD 自动化回归脚本。
- 当前 GitHub Actions run `41983507306` 曾在该分支开始运行；后续提交会触发更新 run。必须读取最新 run 的最终结果后，才可报告 compile/test 通过。
- **尚未完成 GKD-XA 全量迁移**：上游订阅下载/导入/刷新、规则组/分类/排除项、完整规则语法与动作模型、快照审查/AI、历史/日志、AI Provider、Room 数据迁移、备份/恢复、Shizuku/AIDL、开机/通知/Tile/后台服务生命周期均仍未接入。
- **未做真机验收**：AOSP/ColorOS/HyperOS 的无障碍授权、跨应用事件行为、节点有效期、ACTION_CLICK 成功率、切换前台后的取消时序、耗电与内存仍需要实机验证。
- GPL-3.0 分发/项目整体许可边界仍须权利人确认；附带 LICENSE 不能自动视作闭源发行合规。

### 下一阶段

1. 先让当前 Android App compile + GKD selector tests + automation regression 全部通过；修复实际日志暴露的问题。
2. 增加事件去重键、每窗口处理预算、每节点动作结果记录与崩溃/撤销恢复；真机验证动作只触发一次。
3. 实现本地规则组、应用范围/排除项和版本化仓库；再审计上游订阅格式与合法性。
4. 之后再迁移 GKD snapshot/history/AI providers、权限/备份/特权能力，逐项映射到 Hook/脚本页面。不得把 GKD 所有规则默认归入 Ad。
