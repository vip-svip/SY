# FX 1.0.0 — 实时开发续接状态

> 本文件是跨窗口的当前任务状态入口。每完成一个有意义的页面/功能批次，都应在同批代码提交中更新本文件。旧聊天和旧 SHA 不得覆盖这里的新状态。

## 当前仓库状态（2026-11-05，Asia/Tokyo）

- Repository：`vip-svip/SY`
- Branch：`fx-v1.0.0-unified-hook-integration`
- 历史功能基线 HEAD：`6d69cd05c993d041fbebe6ea85d04aeb0eb4ba1a`（历史检查点，不是本轮最新 HEAD）。
- 本轮提交后的最新分支 HEAD：`b25ae132405ac899cc5833b97dd199fb1d92eb4f`（本轮第二批状态文档提交；其前一代码提交为 `948dafaf5db095177d64d5acab47ae864b84ef38`）。
- 本批脚本库 UI 首次提交：`7cdce9ae77d22986be39e40a2544d56099ec0005`（编辑器结果回调在后续修正提交中完成）
- 本状态更新时的工作主题：Dia 原生 Frida 脚本库独立页面；最新 HEAD 以实时 GitHub 分支为准。
- 固定目标：FX 1.0.0，versionCode 10000（改动前仍需核实 Gradle 实际配置）
- 最终 APK / KernelSU ZIP：本状态生成时没有证据证明已完成最终构建、安装或真机验收；不得提前交付。
- 状态来源：实时读取 GitHub 分支、最近提交、`MainActivity.java`、Manifest、现有 UI/迁移文档和 Actions 列表。

## 最新提交所显示的实际推进方向

HEAD 前最近一组提交（按读取时的提交历史）：

- `f2348cd` — Package Installer 二次确认之后、真正执行 Root force-stop 之前再次读取全部安装会话；确认框打开期间如新增活动/已提交/staged 会话，或状态读取失败，则取消操作。定向回归检查二次读取路径。
- `0840c93` — Dia System Expand 的 Package Installer 重启先读取完整 Android 安装会话；会话状态未知、活动/已提交/staged 会话非零时 fail-closed；只有检测为空并二次确认后才通过 Root broker 强制停止默认安装处理程序。新增策略单测和定向回归。
- `91160a0` — 原生 Hosts/分页文件编辑器的完整 read-modify-write 事务加锁，避免并发编辑互相覆盖；新增锁 patcher 和并发/陈旧锁/活锁/符号链接回归。
- `86dc43e` — Hook overlay shell 前缀修正，并增加 patcher Python 语法预检查。
- `a40fbc0` — 游龙周计划星期映射对齐原始 Calendar 语义。
- `d712b78` — Dia System Expand 页面接入迁移 UI。
- `4b3730c` — Root Proxy 设置/测试 fixture 对齐。
- `1ef8fb4` — VPN 配置 fixture 展开与回滚验证修正。
- `94074b8` — 安全护盾 CLEAN 缓存失效和签名读取完整性要求。
- `1460643` — Hook 配置发布路径拒绝符号链接。
- `77abf8e` — Yulong Root Proxy 配置路径固定及状态父目录校验。
- `f7fa81e` — VPN 原生配置写入限制在校验过的状态目录。
- `0b96f53` — Yulong profile/schedule 状态路径符号链接防护。
- `fae15a3` — Hook 设备模拟字段序列化补齐。
- `66797f0` — Yulong 白名单状态路径符号链接防护。
- `131bd38` / `9876b71` — 防火墙路径覆盖拒绝测试和实现。
- `1d28f75` — Dia crash capture policy 与 pending report 状态串行化。
- `bb8762d` — Dia crash minidump 保留/过期测试 fixture 修正。
- `9ab8c22` — Shield volume rescue 序列在服务生命周期切换时重置。
- `287683b` — Dia backup 状态路径父目录符号链接拒绝。

这些提交证明有相应代码改动，不代表整个功能域已完成或真机验收通过。

## 重要现有工程事实

- `MainActivity.java` 保存 `selectedBottomTab`、`lastWebTabIndex`，恢复范围为 0–5，并保留 Hook/Settings/Migration 的多级返回状态。
- MainActivity 已接入安装/卸载/更新包广播刷新 Hook 应用列表，并缓存名称/图标、分页显示应用行。
- 主工程存在原生 VPN 控件、Hook UI 和三套应用的多个原生 Activity。
- Manifest 中已登记 Dia、游龙广告、安全护盾和 Stellar 内部的多个 Activity/Service/Receiver/Provider。
- 当前项目仍包含 WebViewAssetLoader/内嵌兼容运行时用于旧 WebUI 状态 API 的过渡桥接。不能把这当成最终全原生 UI；应逐页迁移，再谨慎退役旧依赖。
- 已有原生页示例：Dia Frida、代码编辑器、备份、DEX/文件浏览器、Inspector、JSON、签名、Activity 浏览器、Global Settings、System Expand、Wi-Fi Proxy、Crash Report；游龙广告 Ad/General/Summary/Stats/App Whitelist/DNS/Firewall；安全护盾 Shield/Rescue/Daily Summary/Scan/Warning/Batch Cleanup/Whitelist/Blacklist/Virus DB/Integrity/Screen Filter，以及 Stellar 子树。
- API-82/API-101 和历史 75 个 Hook 开关并非可直接标记为全部迁移完成；以 `docs/FX-API82-TO-API101-MIGRATION-PLAN.md`、`docs/FXHOOK-MIGRATION-MATRIX.md` 为逐项依据，保留有意 fail-closed 项。

## Actions 状态（本文件生成时读取）

- Actions run `41883543127` 对应 HEAD `91160a0`，读取时为 `in_progress`；不是当前 HEAD `f2348cd`，不得把它记作当前 HEAD 的完成验证。
- 最近一次已结束的旧 run `41882931385` 对应 HEAD `86dc43e`，结论 `failure`。
- 失败位于 `validate-migration` 的模块源码恢复/回归阶段，具体报错：`Root Proxy lock path is not a regular file`，随后 `FAIL: Yulong Root Proxy atomic lock regression failed`；该次静态迁移检查、完整 host regression 后续步骤和 Gradle APK 构建均被跳过。
- 该失败是下一轮需要定位的真实阻塞：核对 Root Proxy 锁路径的文件类型、目录/文件锁迁移逻辑和测试 fixture，不要简单放宽断言。不要把它误写成当前 HEAD 已验证通过。
- 生成本状态时，run 列表尚未显示 `f2348cd` 的验证结论；不得猜测当前 HEAD 的 CI 结果。
- 不要为了“再看一次 Actions”重复触发整套流程；优先本地/模块级验证和成组提交。

## 当前执行策略（用户最新要求）

**优先 UI 前端，再接后端；减少盘点、测试和零散提交。**

### UI 优先工作队列

1. **六 Tab 主壳和首页交互回归：** 对照固定顺序 VPN / Ad-Hosts / 隐私 / 脚本 / Hook / 设置；重点复核底栏高度/可见性、顶部错误横幅、按钮/开关布局、页面切换与返回恢复。只针对确实未完成的页面改动，不重复审计已核实的状态字段。
2. **迁移应用三级/四级 UI 完整度：** 三套应用各自独立；建立原始页面 → 原生路由 → Activity/控件的差异清单，按一组完整页面一起补 UI。禁止新增泛化空壳页。
3. **Dia 页面组：** Frida WAIT/RESUME/listener/message 流程；原生 JS 编辑器/脚本库；方法/类/字段 Hook 页面；扩展管理和仍缺的系统设置控件。对原始组件按 Manifest 对照，现有 Frida 模板不能被称为原生监控引擎完整迁移。
4. **游龙广告页面组：** DNS/规则订阅/General/Firewall/App Whitelist/Stats/Tasker/Widget UI；明确各页面的数据源和状态。Hosts 必须继续独立于订阅列表，且编辑真实系统文件。
5. **安全护盾页面组：** 主界面、扫描/风险详情、白黑名单、批量清理、数据库、Stellar 页面和原版内部导航。Stellar 保留在护盾内部。
6. **Hook 页面组：** 首页、应用列表/搜索、应用目标详情、会员选项、自定义 Hook 规则、日志/状态/导入导出。权限必须是实时系统查询结果。

### 后端接通队列（按 UI 页面完成顺序）

- Dia Frida server/injector/gadget 会话状态与脚本执行；LSPosed scope 的真实实现与状态回读。
- Yulong 规则格式兼容、订阅/缓存、Root Proxy/DNS 实际路径和外部 VPN 设备验证。
- Shield Stellar 原始授权/命令运行时差异、KeepAliveAlarm/watchdog 和权限降级恢复。
- Hook API-82/API-101 逐项迁移；75 历史开关按矩阵区分已迁移/旧入口保留/有意停用。
- VPN/DNS/Hosts 共享流量路线、真实 hosts 文件读写、配置原子替换和回滚。
- QuickJS API 兼容、沙箱、请求桥、超时/取消和偏好持久化。

## 不能遗漏的约束

- 固定六 Tab；设置第六。
- 三套应用各有独立三级入口，原生页面保持四级及更深层。
- Hook 是第五 Tab，单 APK、单入口、单配置/生命周期。
- Android 每个用户/配置文件只有一个活动 VPN 槽位；必须共享 TUN ingress，不得多个 VpnService 抢占。
- 本地 Hosts 文件与订阅规则分开；外部编辑后可重新读取/同步。
- 不得用按钮、日志、WebView 外观、外部 APK 启动、假数据或假运行状态冒充功能。
- 安全关键修复可并行优先；其余按 UI 页面批次向后端推进。
- 三套应用和最终整合验收未完成前，不生成最终 APK/KernelSU ZIP。

## 每次批次后必须更新本文件

把以下字段更新为真实值，并与本批代码一起提交：

- 更新时间（Asia/Tokyo）
- 最新 HEAD / 本批 commit SHA
- 本批完成的页面和真实行为
- 改动文件路径
- 验证等级与结果（静态/单测/UI 自动化/构建/安装/真机分开）
- 未运行、未验证和已知阻塞
- 下一批立即开工的 1–3 个页面/功能
- 并行推进的独立工作线


## 本轮新增批次 — Dia Frida 脚本库独立页面（2026-11-05，Asia/Tokyo）

- 将 Dia“JS 脚本列表”路由改为独立的原生 `FxDiaScriptLibraryActivity`；“脚本编辑器”入口打开新建脚本流程。
- 脚本库复用原 `fx_dia_frida/frida_script_library_v1` 私有 SharedPreferences 键和 `FX-DIA-FRIDA-SCRIPTS-1` JSON schema，不另建数据副本。
- 页面提供名称搜索、新建、全屏 JavaScript 源码编辑、删除、JSON 文件导入/导出；导入时展示同名覆盖数量并要求用户确认。
- 新增 64 个脚本、64 字符名称、单脚本 128 KiB、总 JSON 1 MiB 限制；校验失败不会覆盖现有脚本。读改写在进程内串行，保存使用 SharedPreferences commit 确认。
- 编辑器回传使用 Dia 自定义 resultCode 和 `EXTRA_CODE`，不带 SAF Uri；回调必须先处理自定义编辑器协议，再检查导入/导出所需 Uri。
- 验证：新增 host JVM 策略测试和模块静态回归脚本；真机编辑/导入/导出尚未验证。Android Gradle 构建尚未运行。
- 改动路径：`MainActivity.java`、Manifest、`FxDiaScriptLibraryActivity.java`、`FxDiaScriptLibraryStore.java`、`FxDiaScriptLibraryPolicy.java`、脚本库回归测试与 Host test。
- 下一批：Dia Frida 页的运行日志/monitor templates 独立页展示；游龙广告原生主页剩余统计/General/Tasker 与 Widget UI；随后接通对应后端。

## 2026-11-05 — UI-first acceleration prompt persisted

- Added `docs/FX_1.0.0_UI优先提速与自主开工提示词.md` in this repository; the same document is saved in the Library at `/FX/FX_1.0.0_UI优先提速与自主开工提示词.md`.
- New document commit: `f38d8500c544fdd364c249fee85c7897ec1c9ced`.
- The new instruction measures progress by original-page mapping, completed native page groups, real interactions and backend-connected controls—not by test count, patch count, or commit count.
- Default execution: complete six-tab shell and page hierarchy, then UI page groups of 1–3 related screens, then wire backends page-by-page. P0 safety/network/data-loss risks may proceed in parallel.
- Verification/Actions status at this update: do not infer a pass for a newer HEAD from older Actions runs. The latest observed workflow run before this documentation update was still in progress for an earlier commit; read current Actions only when the next functional batch reaches its verification point.
- Documentation-only change: no new app behavior, APK build, install test, UI automation, or device validation is claimed.



### Frida 脚本库存储统一（2026-11-05）

- 新旧 Frida 页面现在共用 `FxDiaScriptLibraryStore`；原 Frida 页面保存、删除、JSON 导入/导出不再绕过共享校验和串行写入。
- 导入 JSON 时严格拒绝非字符串的脚本值，防止类型强制转换吞掉错误格式。
- 脚本库定向回归会在 JDK 可用时编译并执行 Host JVM 策略测试。
- 已执行的本地 Host JVM 策略测试：PASS（脚本名、控制字符、UTF-8 字节大小、空源码、64 条上限和同名替换）。
- Android Gradle 构建、安装及真机 SAF/编辑流程：未运行/未验证。


## 2026-11-05 — 游龙广告通用设置：系统快捷磁贴引导

- 本批代码提交：`690d3d5b49297e42d41cec1778013a324b34ee4a`。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdGeneralActivity.java`。
- 通用设置新增“系统快捷开关”区域，分别调用 Android 13+ `TileService.requestAddTileService` 请求添加游龙广告过滤磁贴与 FX VPN 磁贴；由系统弹窗确认，不会在添加时自动启动网络服务。
- Android 12 及以下明确提示从系统快捷设置编辑器手动添加；磁贴重复添加、用户取消和系统失败均有不同结果提示。
- 验证：源码静态核对完成；确认 Manifest 已声明 `FxYulongAdTileService` 与 `FxYulongVpnTileService`，类路径/系统 API 需通过 Android 编译进一步确认。Gradle 构建、Host tests、安装和真机磁贴添加流程本批未运行/未验证。
- 未声称 VPN/广告磁贴的运行时服务功能在本批得到验证；本批只完善系统添加入口。
- 下一批优先：Dia Frida “运行日志/结构化监控事件”页面独立呈现；随后游龙广告 Tasker/Widget 页面与后端状态联动。并行工作线：Hook 自定义规则 UI、六 Tab 页面恢复回归。


## 2026-11-05 — 游龙广告 Tasker / 桌面 Widget 原生入口

- 本批代码提交：`948dafaf5db095177d64d5acab47ae864b84ef38`。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdGeneralActivity.java`。
- 通用设置新增桌面小组件固定入口：调用 Android `AppWidgetManager.requestPinAppWidget`，检测桌面启动器是否支持；不支持时提示通过桌面小组件列表添加。没有声称桌面启动器一定接受请求。
- 新增 Tasker/自动化动作复制入口：广告过滤 enable/disable 与 VPN start/stop 分开，另提供原版 TASKER_START/STOP 兼容动作；动作值直接引用现有 `FxYulongAdTaskerReceiver` 常量，接收器组件名和结果广播也在页面说明。
- 验证：静态源码核对；确认 receiver 已实现上述动作常量、广告过滤与 VPN 两条独立控制路径，Widget Provider 已实现状态刷新和点击切换；Gradle 构建、Host tests、Tasker 外部应用联动、桌面固定请求和真机 Widget 点击未运行/未验证。
- 本批不更改版本号，不生成 APK/KernelSU ZIP。
- 下一批：Dia Frida 运行日志/结构化监控事件页面按原始导航拆分；并行工作线：Hook 自定义规则 UI 和六 Tab 页面恢复。游龙广告后续重点为验证广播回执状态在 FX 页面可见，避免只靠剪贴板动作配置。


## 2026-11-05 — Dia Frida 结构化监控事件独立原生页面

- 本批开始时读取的最新续接提交：`1b17e21e2ab1c3c355ab817a0c8711643d880d32`。本批代码提交：
  - `f9c6d7848bb42afb981686e7536bae3e8ed2fb4f` — 新增独立 `FxDiaMonitorEventsActivity`。
  - `600568172227eb98be1bc28b5fce795e7e82b5a5` — Dia Frida“结构化监控事件”入口改为打开独立页面。
  - `45e4315b1e4b622b0891e5576b733d19212bf078` — Manifest 注册该原生 Activity。
- 改动路径：
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaMonitorEventsActivity.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java`
  - `adhook/app/src/main/AndroidManifest.xml`
- 页面行为：按目标包名校验后读取 FX 自己的 Dia Frida 会话日志；Root 读取命令检查日志文件不是符号链接；继续使用 `FxDiaMonitorEventParser` 白名单解析，只展示内置 `[DIA_*]` 允许的元数据字段，不展示 SQL 文本、网络正文/请求头、命令内容、调用栈或自定义脚本原文。
- 原弹窗替换为独立原生页面，支持事件类型筛选、关键词搜索、事件详情、手动刷新、用户主动开启的 15 秒自动刷新；区分加载中、读取失败、无事件和无匹配结果。自动刷新默认关闭。
- 静态复核：已重新读取新 Activity、Frida 路由和 Manifest；确认 Activity 注册、路由目标、目标包名正则校验、日志路径由固定目录+包名构成、文件非符号链接检查、512 KiB Root 输出上限、白名单 parser、筛选/搜索和手动/自动刷新入口均存在。
- 本批验证等级：GitHub 源码静态核对通过。未运行 Java/Android 编译、Gradle 构建、Host/Android 单测、UI 自动化、安装或真机测试；不得据此宣称页面已运行验收。
- 仍未完成：Dia“运行日志”原始会话日志入口仍使用旧弹窗；应继续迁为独立日志页面或与监控页整合，但保留原始日志查看和清空确认行为。Frida monitor 模板是否在目标应用实际生成事件尚未真机验证。
- 失败路线：本批没有遇到工具/实现路线失败；没有触发整套 Actions。
- 下一批直接任务：① Dia Frida 原始运行日志独立查看页（复用同一目标包名与 FX 私有日志路径，保留清空确认）；② Hook 自定义 Hook 页面原生编辑/规则格式切换与当前执行适配器对照；③ 若前两批完成，转向六 Tab 切换/返回链的最小回归。
- 可并行工作线：Hook 规则 UI 与游龙广告 Tasker 结果状态回读分别使用独立源码；修改 MainActivity/Manifest 等共享文件时顺序整合。


## 2026-11-05 — Dia Frida 原始运行日志独立原生页面

- 本批代码提交：
  - `be268a1d72830abb53265d6c03fee7c089a919da` — 新增 `FxDiaSessionLogActivity`。
  - `f443eba59289415c7acded2cef4482287d841b27` — Frida “运行日志/查看当前目标注入日志”路由改为独立页面。
  - `592dae26c96864f25caf2e01efb5e0ca0d9c84d4` — Manifest 注册该页面。
- 改动路径：
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaSessionLogActivity.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java`
  - `adhook/app/src/main/AndroidManifest.xml`
- 页面读取当前目标的 FX 私有 Frida 日志最近 500 行，提供文本筛选、可选择/复制文本、手动刷新、明确的空日志/读取失败状态。页面提示原始日志可能含自定义脚本输出或应用调试信息，分享前应检查敏感内容。
- 保留原“清空当前目标注入日志”操作及二次确认；执行前检查 `/data/adb`、`/data/adb/privacyguard`、`dia-frida`、`logs` 目录存在且均非符号链接，再检查目标日志为普通非符号链接文件，清空后恢复权限为 0600。路径不可用或不安全时拒绝操作，不报告清空成功。
- 静态复核：重新读取 SessionLogActivity、Frida 路由和 Manifest；确认两个 Dia 页面均已注册为 `exported=false`、入口已改为原生 Activity、目标包名校验、Root 输出 512 KiB 上限、目录/文件符号链接检查、搜索、清空确认和权限恢复代码存在。Gradle 配置仍为 FX 1.0.0 / versionCode 10000。
- 验证等级：GitHub 源码静态核对通过。未运行 Java/Android 编译、Gradle 构建、单测、UI 自动化、安装或真机 Root/日志/清空验证；不得声称运行验收通过。
- 已知边界：此页仍依赖模块在 `/data/adb/privacyguard/dia-frida/logs` 创建日志目录；目录未创建时会明确拒绝读取/清空。清空操作是不可恢复的用户主动操作，故保留二次确认。
- 本批无失败路线；未触发整套 Actions。
- 下一批直接任务：① Hook 自定义 Hook 页面——按现有实际规则执行适配器支持的格式实现编辑/校验/应用/错误回读 UI，未支持语法明确拒绝；② 检查 Hook 逐应用详情中的会员选项页面与配置持久化；③ 后续回到六 Tab 切换/返回链的 UI 回归。
- 可并行工作线：游龙广告 Tasker 广播执行结果 UI 回读；主 Tab/页面恢复只读核对，修改 MainActivity/Manifest 时统一顺序提交。


## 2026-11-05 — FX Hook 自定义规则原位编辑

- 本批代码提交：
  - `c4afb9da3149a915eb0eace22b554d46b18e4ee5` — 为每条自定义 Hook 规则增加“编辑规则”入口，并复用现有解析/校验/保存表单。
  - `a4b8c5585b5be4bd8ad0853655a7daa911eca70b` — 增加编辑期间陈旧数据保护，避免覆盖其他入口修改的同一规则。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`。
- 规则列表现在保留启用开关、分组移动、删除，同时可编辑规则 ID、Java/Frida overload/Smali 方法描述符、动作、RETURN_LITERAL 常量、分组和优先级；保存时继续调用 `DeveloperHookRule.parse`，不支持或签名不匹配的动作仍拒绝保存。
- 编辑直接更新原有 slot，不复制/重排其他规则；编辑前后检查规则 ID 唯一性；保留该规则原启停状态以及应用级 Hook 总开关状态；新增分组与规则使用同一个 SharedPreferences commit，提交失败显示错误，不刷新为成功。
- 目标应用在保存前重新确认仍可用；行为替换动作继续只允许 debuggable 目标。编辑窗口打开期间原规则若被其他入口改动，因存储值与编辑初始值不一致而拒绝覆盖，要求重新打开编辑器。
- 静态复核：已重新读取 MainActivity 和提交 diff；确认编辑入口、同 slot 写回、duplicate ID 排除当前 slot、暂停状态保留、陈旧编辑拒绝、同步 commit 失败处理均在分支代码中。既有 `DeveloperHookRuleTest.java` 存在并保留；本批没有运行该测试。
- 验证等级：GitHub 源码静态核对通过；未运行 Host/Android 单测、Java/Android 编译、Gradle 构建、UI 自动化、安装或真机 LSPosed 注入测试。
- 未改变规则语法、运行时执行器、API-82/API-101 能力范围或会员诊断边界；没有增加绕过真实会员授权的功能。
- 本批没有失败路线；未触发 Actions。
- 下一批直接任务：① 把“查看 OBSERVE 方法日志”从 AlertDialog 改为独立原生页面，增加目标应用、筛选和刷新状态；② 对 Hook 首页/应用详情中真实 Root、LSPosed、Accessibility 授权状态做一次页面级回读并修复 UI 与实际状态不一致项；③ 再推进六 Tab 页面恢复/返回链针对性回归。
- 可并行工作线：游龙广告 Tasker 广播结果回读 UI 与 Hook 原生观察日志页面分属独立文件；MainActivity 共享文件改动顺序整合。
