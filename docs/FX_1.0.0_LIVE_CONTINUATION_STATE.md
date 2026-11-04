# FX 1.0.0 — 实时开发续接状态

> 本文件是跨窗口的当前任务状态入口。每完成一个有意义的页面/功能批次，都应在同批代码提交中更新本文件。旧聊天和旧 SHA 不得覆盖这里的新状态。

## 当前仓库状态（2026-11-05，Asia/Tokyo）

- Repository：`vip-svip/SY`
- Branch：`fx-v1.0.0-unified-hook-integration`
- 历史功能基线 HEAD：`6d69cd05c993d041fbebe6ea85d04aeb0eb4ba1a`（历史检查点，不是本轮最新 HEAD）。
- 上一轮状态文档记录的 HEAD：`1b17e21e2ab1c3c355ab817a0c8711643d880d32`（历史检查点；本轮工作前已从分支文件重新核对）。
- Hook OBSERVE 日志页代码检查点：`28cf54337bb86a1af9a9d102be959c9e036e283e`（随后分支继续前进；当前轮次最新代码提交见下文）。
- Tasker 回执 UI 的历史检查点：`96b486cb4fe57d4add7e1539d0f2137fac2da260`；其后已补充发送方 UID 与 APK signer 固定，详见本文件下方 2026-11-05 记录。
- 本批脚本库 UI 首次提交：`7cdce9ae77d22986be39e40a2544d56099ec0005`（编辑器结果回调在后续修正提交中完成）
- 本轮最新工作主题：游龙 Tasker Root 广播发送方身份与 signer pin 已提交；Shield 白名单 parser/serializer 已统一接入三个真实消费路径和两个管理页面写入路径；当前分支 HEAD 始终以 GitHub 实时 ref 为准。
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


## 2026-11-05 — FX Hook OBSERVE 方法日志独立原生页面

- 本批代码提交：
  - `8c6bd69fdb12eb74d95f0e5ff9144b8cfcd3572c` — 新增 `FxHookObservationLogsActivity`。
  - `add7b4059ce9c0d19dccb121af78c177443596c4` — 将“查看 OBSERVE 方法日志”由 AlertDialog 改为独立 Activity。
  - `0cbe71c2db50bc2948ff17d97d6e24973966764b` — Manifest 注册页面，`exported=false`。
  - `746ebefa5ba1df508b6f91f8b7e649551edd1301` 与 `28cf54337bb86a1af9a9d102be959c9e036e283e` — 修正非零 Root 退出码被误显示为“读取完成”的错误状态，并修整失败信息格式。
- 改动路径：
  - `adhook/app/src/main/java/de/privacyguard/adhook/FxHookObservationLogsActivity.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`
  - `adhook/app/src/main/AndroidManifest.xml`
- 页面行为：从 Hook 目标详情页打开独立日志页；显示目标应用/包名、OBSERVE 记录、搜索过滤、手动刷新、空结果/读取失败/模块缺失/logcat 缺失状态；保留文本选择/复制。
- 数据读取继续使用 FX Hook 已有的 logcat 日志契约：最近 5000 条系统日志 → 固定标记 `FX Hook` + `dev-observe` → 目标包名精确 `package=... executable=` 筛选 → 最多保留 300 条。输出上限 64 KiB，屏幕显示上限 24 KiB。用户搜索词只在已读取日志的本地行中过滤，不拼接进 shell 命令。
- 目标包名在 Activity 端再次校验；模块目录解析保持与主 Activity 既有 `nativeModuleCommand` 一致。页面明确不把旧日志当作目标进程当前仍在运行的证明；无日志不显示假成功。
- 静态复核：重新读取 Activity、MainActivity 路由和 Manifest；确认新 Activity 注册、导出关闭、旧弹窗已移除、精确目标筛选、日志行数/输出上限、用户搜索不进入 Root 命令、错误状态分支、版本配置未改变。既有 Hook 自定义规则原位编辑功能仍在主界面代码中。
- 验证等级：GitHub 源码静态核对通过。未运行 Java/Android 编译、Gradle 构建、Host/Android 单元测试、UI 自动化、安装或真机 LSPosed/logcat 运行验证。
- 本批未触发整套 Actions。没有走失败路线。
- 未完成项：Hook Root、LSPosed scope、Accessibility 服务和 Android 特殊权限状态仍需在目标详情页核实真实回读；Hook API-82/API-101 仍不是 75 项全部迁移完成；当前日志页未提供清除系统 logcat 的操作（不对全局系统日志做破坏性清理）。
- 下一批直接任务：① 逐项核对 Hook 首页/应用详情中的 Root、LSPosed Manager/Scope、Accessibility 和权限状态是否来自系统实时状态，并修正显示不同步；② 若该页真实状态已覆盖，转入游龙广告 Tasker 结果广播的可见回读；③ 随后做六 Tab 切换/返回链页面级回归。
- 并行工作线：游龙广告 Tasker 回执状态 UI 与 Hook 权限状态查询是不同源码组；主 Activity/Manifest 为共享文件，按顺序整合。


## 2026-11-05 — Hook 自定义规则页并入与授权状态生命周期刷新

### 合并进来的分支最新提交（读取时已在 HEAD）

在继续工作前，实时分支 HEAD 为 `8c2a64b0e96bc6d69b645d9c6e23c526f7609cfd`。比上一份状态文档更新的三笔 Hook 提交已经读取 diff 并保留，不能回退覆盖：

- `95a1320133f4408292f0f20b5596d913d3b86aff` — 将每应用自定义 Hook 规则拆成独立原生管理页，加入语法/动作选择器、过滤与列表、统计、返回链以及页面状态恢复。
- `d63dee1da132eb35a1b694864370707c38d566c6` — 修正规则启停校验、debuggable 限制、解析器调用和编辑器回调。
- `8c2a64b0e96bc6d69b645d9c6e23c526f7609cfd` — 修复恢复目标丢失时清理自定义页面标记、编辑既有规则时正确识别签名语法，并将规则开关提示明确为“本地草稿，需发布”。
- 这些提交只证明对应源码与导航/表单实现已提交；不代表运行时注入或真机验证完成。

### 本轮代码修复

- 本批代码提交：
  - `33d225980a6848d9650bf9be023d6b0fd258b55c` — Hook Hub 与目标详情页授权状态生命周期刷新。
  - `a104430d14d1767f3aaba728818db589dd11180c` — Root 状态异步回调忽略已脱离页面的旧 View。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`。
- 从系统设置/LSPosed Manager 或其他 Activity 返回且 Hook Hub 仍可见时，自动重新读取设备端 Remote Files 状态、Root UID/FX 模块状态、LSPosed Manager 安装与 libXposed Binder 状态、Android Accessibility Secure Setting 与 FX 服务实时连接状态。
- Hook Hub 的“刷新 Root / LSPosed / 无障碍状态”按钮不再重建整个页面，而是刷新已有控件；Remote Files 有独立状态刷新。
- 从系统设置或其他 Activity 返回且目标详情页仍可见时，重新读取当前目标包的 LSPosed scope snapshot。
- 目标 scope 状态增加请求 generation、目标包名和 View 归属校验，旧目标/旧页面的异步回调不得覆盖当前页面。Root 检查回调同样忽略已经脱离界面的状态 View。
- Accessibility 状态依旧同时核验 Android Secure Setting、服务当前进程连接标志、持久化连接标志与 PID；不能仅凭用户开启了系统开关就显示 FX 服务已连接。
- 本轮静态核对：MainActivity / 当前 Manifest / Gradle 重新读取；确认 onPause 设置待刷新标志、onResume 分流刷新 Hub 或目标 scope、Remote Files/Root/LSPosed/Accessibility 四条读取路径、scope generation/package/View guard、Root View guard 均存在。Gradle 固定值仍为 `versionCode 10000`、`versionName 1.0.0`。
- 验证等级：GitHub 源码静态检查通过。未运行 Java/Android 编译、Gradle 构建、单测、UI 自动化、安装或真机权限变更返回验证；未触发 Actions。
- 当前最新代码提交（状态文件更新前）：`a104430d14d1767f3aaba728818db589dd11180c`。
- 未验证/边界：LSPosed Manager 安装检测与 Binder 状态仍不等于目标进程注入；目标作用域只代表允许模块加载。Accessibility 服务连接仍需真实设备切换开关回归。Root 运行结果未在真机核验。
- 失败路线：本批无失败路线。没有重复触发全量 Actions。
- 下一批直接任务：① 游龙广告 Tasker receiver 回执状态回读进 FX 原生页面，避免仅有动作复制入口；② 六 Tab 页切换/返回链恢复测试，尤其 Hook 独立规则管理页返回目标详情/应用列表/第五 Tab；③ 对 Dia 两个新日志页面做模块级编译验证，若编译发现问题就一次修复同页面组，不再零散提交。
- 并行工作线：Tasker result broadcast UI 与主 Tab 恢复测试可以独立分析；Manifest/主 Activity 仍需顺序整合。


## 2026-11-05 — Hook 每应用自定义规则独立原生管理页

- 本批分支代码提交：
  - `95a1320133f4408292f0f20b5596d913d3b86aff` — 自定义规则管理从目标详情内联区域拆为独立页面；按每应用既有配置和规则解析器工作。
  - `d63dee1da132eb35a1b694864370707c38d566c6` — 修正列表刷新回调、规则启停校验和非 debuggable 目标动作限制。
  - `8c2a64b0e96bc6d69b645d9c6e23c526f7609cfd` — 修正语法类型回显、无效规则统计和编辑期间目标状态处理。
  - `27f93cfd22b884f41ff7761730d23dca2dd6f393` — 补齐独立页面返回/进程重建时目标包名恢复，并在目标不可用时清理嵌套页面标记。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`。
- 页面行为：每个目标应用从 Hook 详情打开独立“自定义 Hook 规则”页面；可新增/编辑规则、筛选分组、搜索 ID/签名/动作、启停、移动分组、删除确认、管理分组、JSON 导入/导出、查看 OBSERVE 日志，并通过明确的“保存并发布 Hook 配置”按钮发布到既有 Root/LSPosed 配置通道。
- 编辑器提供 Java 精确签名、Frida `.overload()`、Smali/JVM 描述符和旧式零参数 boolean 格式选择；最终仍由 `DeveloperHookRule.parse` 解析和精确类型校验，不因选择了语法类型而绕过验证。动作使用受限下拉列表；RETURN_LITERAL 只允许已有解析器支持的基本类型/String 常量。
- 原有 per-app SharedPreferences 键、slot、优先级、分组、规则 ID 和发布格式保持不变；没有另建第二套规则存储。列表启停属于本地草稿，需显式发布后才更新设备端 Hook 配置。无效规则禁止启用；非 debuggable 目标只允许 OBSERVE，不允许启用替换动作。
- 返回链：从目标详情进入时可返回该目标详情；从 Hook 应用列表进入时返回列表；自定义规则页面标记、选中包名和返回目标意图均写入 Activity saved state。目标卸载时清除嵌套页状态。
- 静态复核：重新读取当前 `MainActivity.java`；确认独立路由、保存/恢复的 `target_custom_rules` 类型、selectedPackage 保存、嵌套返回处理、语法/动作 Spinner、分组/搜索过滤、invalid rule fail-closed、非 debuggable 替换动作保护、删除二次确认及原有发布函数调用均存在。
- 验证等级：GitHub 源码静态核对通过。未运行 Host/Android 单测、Java/Android 编译、Gradle 构建、UI 自动化、安装、LSPosed 实际加载或真机规则执行；不声称运行验收通过。
- 本批未触发完整 Actions；没有重复旧测试失败路线。
- 后续待补：规则导入采用旧 JSON 数组或 portable rule group 的完整外部流程仍需针对真实文件选择器/大文件和异常条目做测试；Hook 75 项历史开关及 API-82/API-101 全量迁移仍不视为完成。
- 下一批：游龙广告 General 页面增加 Tasker `AD_FILTER_RESULT` 实际回执可见状态，区分广告过滤与 VPN 两个控制面；随后继续六 Tab 页面恢复/返回链回归。

## 2026-11-05 — Hook 授权中心 Root / Accessibility 状态读取修正

- 本批代码提交：`900a97b1d959af84b816efc58d63273ea61208e1`。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`。
- Root 检查不再只认 `/data/adb/modules/privacyguard` 单一路径；现在按 FX 模块 ID `privacyguard` 在 `modules/privacyguard`、`modules_update/privacyguard`、`modules/privacy_guard`、`modules/pg` 候选位置查找，要求候选目录及 `module.prop` 不是符号链接，再读取版本与 disable/remove 标记，区分启用、已禁用、待卸载、版本不匹配和缺失。Root 成功依据改为精确的 `FX_ROOT_UID=0` 标记，不再依赖输出字符串是否以字符“0”开头。
- Accessibility 状态读取改为按冒号分隔系统 `ENABLED_ACCESSIBILITY_SERVICES`，解析 `ComponentName.unflattenFromString` 并与真实 `FxAccessibilityService` 组件比较；保留 Android 设置可能返回的包相对/完整组件名兼容形式。避免对任意包含组件子串的服务记录产生误判。
- 页面级核对：Hook Hub 已分别展示 KernelSU/Root、LSPosed Manager 与 Binder 服务状态、Android Accessibility 系统启用与 FX 服务连接状态；从系统设置返回时，`onResume` 通过既有 pending 标记重新读取授权状态。目标应用作用域仍单独由 libXposed bridge 查询和呈现；作用域批准不代表进程注入。
- 静态复核：重新读取本批代码；确认候选路径、module ID 精确校验、目录/文件符号链接检查、模块版本/disable/remove 状态、Root UID 精确判断、Accessibility 组件精确比较和 onResume 状态回读链均存在。
- 验证等级：GitHub 源码静态核对通过；未执行设备 Root 授权弹窗、真实模块路径检查、系统无障碍服务启停、LSPosed Manager/Binder 连接、构建、单测、安装或真机验证。当前工具环境未运行 Android Gradle 构建。
- 本批未触发完整 Actions；无失败路线。
- 下一批：游龙广告 Tasker 回执 UI 回读；然后对六 Tab 切换、从设置/Hook 子页返回、旋转/进程重建做最小页面级回归。VPN/DNS/Hosts 的设备流量路径仍需独立真实验收。


## 2026-11-05 — 游龙广告 Tasker 执行回执持久化、原生显示与外部控制授权

- 本批代码提交：
  - `0faeca0ed034227c32860acd3b13ac35e8f36c08` — General 页面加入外部自动化授权开关、最近执行回执卡片、实时回执监听与刷新。
  - `2df54b03bc98de8012723012f759208a1bde7cab` — Tasker Receiver 增加默认关闭的外部控制 opt-in、拒绝未授权请求、执行结果持久化和详情长度限制。
  - `96b486cb4fe57d4add7e1539d0f2137fac2da260` — 修正 Android lint 注解引用和回执文本换行。
- 改动路径：
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdTaskerReceiver.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdGeneralActivity.java`
- Tasker receiver 的控制授权默认关闭：外部广播在进入 Root 操作前读取 `fx_yulong_tasker/allow_external_actions`；未明确允许时以 exit code 13 拒绝，不调用 Root，并照样生成失败回执。由于该 Receiver 为兼容 Tasker 而保持 exported，页面清楚说明只有信任已安装的自动化应用时才应开启。
- 每次动作结果先同步持久化最近 action、target、requested_enabled、success、exit_code、detail 和 timestamp，再发送包名限定的 `AD_FILTER_RESULT` 广播。详情最多保存/广播 2048 字符；不会把整个 Root 输出无限扩散。
- 游龙广告 General 原生页面新增外部自动化开关和“最近执行回执”展示，包含时间、控制目标（广告过滤/VPN）、请求开关、动作、执行结果、退出码和详情。Activity onResume 读取持久化结果；页面可见期间注册非导出的动态 Receiver 实时更新，onPause 时注销。
- UI 明确区分“最近命令执行回执”和“服务当前运行状态”；成功退出码不冒充广告过滤/VPN 当前仍运行。实际运行状态仍需由对应服务状态查询确认。
- 静态复核：已重新读取 Receiver、GeneralActivity、Manifest 和 Gradle；确认 PREF key 一致、授权默认 false、拒绝分支在 Root 前、结果持久化发生在广播发送前、详情长度上限、结果广播限定本包、动态监听使用 `Context.RECEIVER_NOT_EXPORTED`、Activity 返回时回读以及版本固定值 `versionCode 10000` / `versionName 1.0.0`。
- 验证等级：GitHub 源码静态核对通过；未执行 Android 编译、Gradle 构建、单元测试、Tasker 外部应用发送广播、KernelSU Root 动作、广告过滤/VPN 真实状态联动或真机验证。未触发完整 Actions。
- 未完成/边界：当前持久化字段只保存最近一次执行结果，不是审计历史列表；执行成功只代表 Root 控制脚本返回 0，页面不将其描述为长期运行状态。Tasker 需先在 FX General 页面开启外部授权。
- 失败路线：无；没有重复尝试旧的失败测试路线。
- 本批代码最新提交（实时状态更新前）：`96b486cb4fe57d4add7e1539d0f2137fac2da260`。
- 下一批直接任务：① 六 Tab 页面切换、Hook 自定义规则页嵌套返回、Settings/Migration 返回链和旋转/进程重建的针对性检查；② 对 Dia Frida 监控事件页与原始运行日志页做模块级编译验证；③ 如果编译链不可用，改用仓库现有 Java/Android 静态构建工具检查，但不得虚报 Gradle 成功。
- 并行工作线：六 Tab 页面恢复只读审查可与 Dia 原生日志页构建链检查分开进行；修改 MainActivity 与 Manifest 时统一整合。


## 2026-11-05 — 游龙广告 Tasker 执行回执与 Root 接收路径加固

- 当前分支通用设置页/Receiver 已包含 Tasker 回执闭环；本轮核对并加固，不重复实现第二套：外部 Root 控制默认关闭；Receiver 在 Root 命令前检查授权；每次执行将动作、目标类型、请求状态、退出码、详情和时间戳写入私有 SharedPreferences，再发送包内 ACTION_RESULT；General 页面在 onResume 注册非导出接收器、onPause 注销，并回读最近一次持久化结果。
- 本轮代码提交：
  - 51c11fda2e80807a7c2792e59014805f8ce7222b — Receiver 只允许两个固定游龙控制脚本；模块查找检查 /data、/data/adb、模块目录、module.prop、scripts 目录及脚本文件的符号链接状态，并要求 module ID 为 privacyguard、版本为 1.0.0。
  - 4190f2a283308ff2bca60e8db39e6a2f7eb19c46 — General 设置明确展示外部控制授权状态，并说明开启后没有按发送方包名/签名白名单过滤。
- 改动路径：adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdTaskerReceiver.java；adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdGeneralActivity.java。
- 静态复核：最新两个源码文件确认默认关闭、Root 前授权闸门、持久化回执、包内 ACTION_RESULT 广播、非导出动态接收器、生命周期注册/注销、UI 回读、固定脚本名 allowlist、模块 ID/版本校验与符号链接检查均存在。
- 验证等级：GitHub 源码静态核对通过；未运行 Java/Android 编译、Gradle 构建、单测、UI 自动化、安装或真实 Tasker/Root 脚本执行。没有声称自动化应用联动已经真机验收。
- 广告 master 与 VPN 仍是独立控制面；原版 TASKER_START/STOP 仍映射 FX VPN；外部授权关闭时不执行 Root 命令。本批未触发整套 Actions，无失败路线。
- 下一批：① 六 Tab 主壳/底栏切换及返回链页面级核对，重点 Hook 自定义规则页返回 Hook 第五 Tab、Settings 保持第六；② 核对从系统设置返回后 Root/LSPosed/Accessibility 状态刷新；③ 若主壳无新缺陷，继续 Dia/游龙安全护盾页面迁移差异。


## 2026-11-05 — 六 Tab / Hook 子页返回链回归修正

- 本批代码提交：
  - 413d502a05a8a3b51a42fe7dc79329278abde1f4 — 用户直接切换任一主 Tab 时清除 Hook 自定义规则嵌套页的临时路由/返回目标标记；非法 Tab index 被忽略。Activity 重建时通过 saved state 恢复自定义规则页的路径仍保留。
  - 6d5f3524c45f437b55aa6a5b324811e4fd7c3406 — Android 系统返回键从 Hook 目标详情返回时保留 activePrivacySection，不再无条件返回无分类的应用列表；与页面内返回按钮的行为对齐。
- 改动路径：adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java。
- 源码核对：Compose 壳固定标签顺序 VPN / Ad / 隐私 / 脚本 / Hook / 设置；底栏 72dp，主页面预留 72dp 底部空间；Hook 对应 index 4、设置对应 index 5。MainActivity 的 selectedBottomTab / lastWebTabIndex 范围为 0–5。
- Hook 自定义规则页状态路径：Activity saved state 保存 target_custom_rules、目标包名与返回意图；恢复后先加载应用列表，再将有效目标恢复到自定义规则页；直接点任一主 Tab 会清除嵌套页标记；目标详情的系统返回与页面内返回都保留原 Privacy 分类上下文。
- 静态复核：重新读取 FxNativeAppShell.kt 与 MainActivity.java；确认六项标签、72dp 高度、内容底部留白、Hook/设置索引、custom page save/restore、Top-level 清除嵌套标记和系统返回保留 activePrivacySection 均存在。
- 验证等级：GitHub 源码静态核对通过；没有运行 Compose UI 自动化、模拟器/真机点击、旋转/进程回收测试、Java/Kotlin 编译或 Gradle 构建。视觉布局与设备实际触控尚未验收。
- 未改动六 Tab 顺序或版本号；未触发整套 Actions。
- 下一批：继续 Dia / 游龙安全护盾原生页面映射，优先查找尚未实现的关键原始页面/交互；如果没有独立页面切片可安全完成，再回 Hook 会员只读诊断与权限状态区核对。VPN、DNS、Hosts、QuickJS 的真实设备功能仍需按各自测试路径单独验收。


## 2026-11-05 — Tasker Root 发送方白名单与六 Tab / Hook 返回链修正

### Tasker 接收器 Root 身份边界

- 本轮新增/修正提交：
  - `c55a99621eae7d943e437903d62b3a7f5972da70` — 在接收器读取外部授权开关和执行任何 Root 操作之前认证真实广播发送应用。
  - `92d346d4eb1f03e5dc0c36a2c3be04bcdbf398e8` — 新增纯 Java `FxYulongTaskerCallerPolicy`，要求 Android API 34+、发送包名与用户配置的 allowlist 完全匹配、sender UID 有效且 PackageManager 的 UID 包列表确实包含授权包。
  - `3588f353b5e2fb1292675d3904b466113d3d568e` — 增加 caller policy JUnit 测试，覆盖有效发送者、API 33 fail-closed、不同发送包名、UID 包列表不匹配、缺失身份/空配置/自应用包名。
  - `168384449ae5ee7af3bf4d932ef14a91ffd01bad` — General 页面补充 PackageManager import，使已安装发送方校验能够编译引用。
  - `c13b369f10ef60b4ffd1a8ba9de61090aa44dcd7` — 回执状态文案改为展示确切的授权发送方和系统包名/UID 匹配要求，移除“所有可发送广播的应用都可执行”的旧说明。
  - `413d502a05a8a3b51a42fe7dc79329278abde1f4` — 用户直接选择六 Tab 中任一主 Tab 时，先清除 Hook 自定义规则嵌套页临时路由标记；无效 Tab index 被拒绝。
  - `6d5f3524c45f437b55aa6a5b324811e4fd7c3406` — 系统返回键从 Hook 目标详情返回时保留当前 `activePrivacySection`，不丢失隐私分类上下文。
  - 相关后续修复：`4d784fc55d9c79d61b32f640fd7e544f21c441e4`（回执持久化失败静态回归断言）、`609648c537388f39568103b0632708417ddaaa11`（未持久化实时回执使用真实换行）、`c4002929701ced81ad734a462c99c61ec471b00e`（拒绝 modules/modules_update 父目录符号链接）、`51c11fda2e80807a7c2792e59014805f8ce7222b`（固定脚本名、模块 ID/版本和路径符号链接校验）、`31d38d194fad281fcedbb81860e86cea007671e0`（回执持久化结果标志）、`f564659abc30b078e75874f61a1f940587dd5535`（持久化失败时页面显示有界的实时回执）。
- 改动路径主要为：
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdTaskerReceiver.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongTaskerCallerPolicy.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdGeneralActivity.java`
  - `adhook/app/src/test/java/de/privacyguard/adhook/imported/ad/FxYulongTaskerCallerPolicyTest.java`
  - `scripts/tests/fx-yulong-tasker-receiver-concurrency-regression.sh`
  - `adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`
- Root 外部调用顺序：先识别动作，再核实 Android 14+ 的系统实际发送包名/UID 与已保存包名一致，并确认 UID 包列表含该包；身份无法验证或 API 低于 34 时直接拒绝，不执行 Root，也不让未知发送者覆盖用户最近回执。身份有效后仍必须通过 General 页面手动开启外部 Root 自动化开关。
- General 页面要求用户填写并保存一个已安装的自动化发送应用包名；低于 Android 14 时开关禁用并明确说明 fail-closed。启用状态回执显示具体 allowlist 包名，不再声称全部广播发送者都可请求执行。
- Root 控制脚本仍限定为两个固定名字：`yulong-ad-control.sh`、`yulong-vpn-control.sh`；模块要求 `id=privacyguard`、`version=1.0.0`，并检查 /data、/data/adb、modules/modules_update、候选模块目录、module.prop、scripts 目录和脚本文件的符号链接状态。
- Tasker policy 验证：读取仓库 JUnit 文件确认 5 组断言存在；当前容器没有 Gradle 或 JUnit4 运行器，所以未执行仓库 JUnit。另将当前纯 Java policy 实现以独立 javac harness 编译运行，9 个允许/拒绝场景均 PASS。该结果只覆盖纯 Java caller policy，不代表 Android BroadcastReceiver / PackageManager API 或真实 Tasker 设备调用已验证。
- 状态/返回链静态核对：Compose 壳六 Tab 标签与 72dp 底栏、设置第六和 Hook 第五、saved state 中 selected tab / web tab / target_custom_rules / selected package / migration 层级；切换主 Tab 清除自定义 Hook 嵌套路由；Android 系统返回从 Hook 目标详情保留原隐私分类，源码检查通过。
- 固定 Gradle 版本静态核对：`versionCode 10000`、`versionName '1.0.0'`，未改版本。
- 验证边界：没有 Gradle/JUnit runner；本地 GitHub clone 失败原因是容器 DNS 无法解析 github.com。未运行 Android Gradle 构建、JUnit、Android 编译、UI 自动化、Tasker 真实广播、KernelSU Root 命令或真机测试；未触发整套 Actions。
- 当前分支最新已读取 HEAD（本状态提交前）：`fe408f2c46c164db7c0763ad4c3cbec9621d0fca`（六 Tab/Hook 返回链状态文档提交）。
- 下一批直接任务：① 转回用户要求的原应用页面迁移，优先 Dia / 游龙安全护盾未覆盖的 1–3 个原生页面组及其真实弹窗/列表/返回链；② 查证原 Manifest 组件与现有原生 Activity 路由差异，避免用已有页面重复计数；③ Android 构建可用时再进行模块级构建，不以源码检查代替构建。
- 并行工作线：Dia 页面树/原始 Manifest 对照与安全护盾页面组可分开读取；共享 MainActivity / Manifest 的修改顺序整合。


## 2026-11-05 — 安全护盾扫描风险详情与用户白名单写入闭环

- 本批代码提交：
  - `950da36441d819a3449252ce02fe52d9b56b238c` — 扫描结果打开 `FxYulongWarningActivity` 时附带真实 `finding.severity`（CERTAIN / SUSPECT）。
  - `2bd2278a0c473b226b719a3a5e5c5cf1d3781f32` — 重构风险详情页，区分确定风险、可疑风险和等级缺失；加入白名单前重新确认目标仍安装、拒绝系统应用、验证既有数据大小、去重并使用 `SharedPreferences.commit()`，只有写入成功后显示成功；卸载仍需二次确认且只打开 Android `ACTION_DELETE` 系统界面。
- 改动路径：
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongScanActivity.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongWarningActivity.java`
- 数据契约：与现有 `WhitelistActivity` 使用同一个 `shield_prefs` / `whitelist_pkgs` 存储键；白名单仅加入当前 PackageManager 仍能读取的用户应用，与列表页对系统应用的过滤规则一致。扫描 severity 来自 `FxYulongScanEngine.Finding.severity`，详情页不根据标签或文字重新推断风险等级。
- 静态复核：重新读取 ScanActivity、WarningActivity、WhitelistActivity；确认 severity 传递/显示、CERTAIN/SUSPECT/UNKNOWN 分支、包名格式校验、安装状态复核、系统应用拒绝、白名单长度上限、同步 commit 成功/失败分支和卸载确认流程均存在。
- 验证等级：GitHub 源码静态核对通过。未运行 Java/Android 编译、Gradle 构建、Host/Android 单测、UI 自动化、安装、扫描流程或真机白名单/卸载验证；不得据此声称运行验收通过。
- 本批没有更改病毒库匹配阈值、风险严重度判定或扫描完整性规则；不自动卸载/停用任何应用，不将可能命中解释为确认恶意。
- 未触发完整 Actions；无失败路线。
- 下一批：继续安全护盾的病毒库/名单/扫描三者间真实状态同步，重点核实风险详情页加入白名单后通知/扫描调度器是否立即读取同一持久化名单；随后检查扫描页在内容特征扫描超时、APK 读取失败和清单不完整时的结果 UI 是否始终显示未完成/无法判断。


## 2026-11-05 — 安全护盾白名单接入统一扫描与自动提醒

- 本批代码提交：
  - `960b09417fc174aa4871d640ffcfba63a606b96b` — 新增 `FxYulongWhitelistPolicy`，统一读取 Shield 原始 `shield_prefs` / `whitelist_pkgs`，校验包名、去重、限制原始数据 1 MiB 和最多 10,000 个条目；数据缺失/异常/超限时不信任白名单、不抑制扫描发现。
  - `ab708ad8872b9ad1f2d9c40e9201b4fd95a9a994` — 手动全量/单包扫描引擎在病毒库匹配前排除用户白名单，并在扫描结果说明实际跳过的白名单应用数量；扫描清单完整性仍以 PackageManager inventory 为准。
  - `6dc935a6643e93561c357c0f1dce7c08b3e90864` — 安装后/前台单包自动扫描在 claim cooldown 和病毒库读取前检查同一白名单，已列入用户白名单的应用不触发自动风险通知；病毒库更新后的全量自动扫描复用同一 ScanEngine，因此也会排除白名单。
  - `609d4379a5442b17eeb8296ce7e54a39b11c9c3c` — 新增 6 组 JUnit 测试：合法包名/重复、非法值、空值、原始数据大小上限、超出条目上限 fail-open、非法目标包名拒绝。
  - `8b5a747c47b4e67debf7d013e12a14f89b24e1de` — 修正最大条目边界，恰好 10,000 条仍有效；超过 10,000 条整体 fail-open，不部分信任。
  - `2c5fd641605bc8b06cbfb7fc771bbffdb43eae02` — 增加恰好 10,000 条有效白名单的边界测试，防止 off-by-one 回归。
- 改动路径：
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongWhitelistPolicy.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongScanEngine.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongRiskScanDispatcher.java`
  - `adhook/app/src/test/java/de/privacyguard/adhook/imported/shield/FxYulongWhitelistPolicyTest.java`
- 真实行为变化：扫描页加入白名单、风险详情页加入白名单、安装后自动扫描、前台自动扫描和病毒库更新后的全量扫描现在都使用同一个偏好键/解析策略。白名单应用不会继续出现在手动扫描风险结果或触发自动通知。异常/超大的白名单数据不会被部分解析成忽略名单，避免错误抑制扫描发现。
- 静态复核：重新读取 Policy、ScanEngine、RiskScanDispatcher、JUnit 文件；确认 engine 在 scanned 计数/病毒库匹配前 skip；自动 dispatcher 在 cooldown 前 skip；DB 更新全扫复用 engine；扫描结果说明排除数量；Preference 路径与 WhitelistActivity 相同；7 个 JUnit 用例（含恰好 10,000 条边界）存在。
- 验证等级：源码静态核对通过；JUnit 已添加但**未运行**；没有执行 `javac`/Gradle 构建、Android 编译、UI 自动化、安装或真机自动提醒/白名单验收。当前环境没有 Android Gradle/JUnit runner；不声称这些测试通过。
- 未更改病毒库匹配阈值、风险严重度、PackageManager 清单完整性或自动卸载/停用行为。白名单只影响是否扫描/提醒，不会卸载、停用或修改应用。
- 未触发整套 Actions；无失败路线。
- 下一批：① 检查扫描结果 UI 的内容特征扫描超时、APK 读取失败、病毒库未就绪和 PackageManager 清单不完整时，是否始终正确展示“未完成/无法判断”；② 继续安全护盾主页面与原页面树的未映射交互；③ 完成安全护盾此组后转回 Dia 原生页面映射。


## 2026-11-05 — 安全护盾扫描结果与批量清理页面状态恢复

- 本批代码提交：
  - `65c97aabb7f3fdb368f93563a7413587df50164e` — 扫描页保存/恢复上次扫描结果、风险严重度/原因和用户勾选的批量处理项目；扫描中页面重建时明确标记上次扫描未完成；为旧 Activity 回调增加 generation/lifecycle guard。
  - `bc94db31eba0510c03cc5098d56efa622f9e629d` — 修正恢复状态提示和扫描状态摘要的文本换行，避免显示字面量 `\\n`。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongScanActivity.java`。
- 真实行为：
  - 扫描完成后保留 Finding 包名、应用名、CERTAIN/SUSPECT 严重度、命中原因、扫描完整性和扫描摘要；Activity 旋转/进程状态恢复后重建结果行与选中复选框。
  - Bundle 状态恢复最多保存 128 条命中项；单次批量清理选择上限 100，与 `FxYulongBatchCleanupActivity.MAX_QUEUE_ITEMS=100` 对齐。
  - 超出恢复上限、Bundle 字段缺失/长度不一致或枚举/包名校验失败时，明确提示重新扫描并禁用批量清理；不会恢复部分列表后仍让用户误以为完整。
  - 页面重建时如果上一次扫描仍在执行，丢弃旧 Activity 回调及旧结果状态，显示“上次扫描未完成，请重新扫描”；本次扫描期间批量清理按钮禁用。
  - 每次扫描回调使用 generation 与 destroyed/finishing/destroyed 状态校验，防止旧 Activity 在新页面已打开后继续写 UI。
  - 保留原风险详情页入口、严重度和原因传递、风险详情页的用户白名单持久化与系统应用限制，以及批量清理队列逐项确认 Android 系统卸载界面。
- 同组页面当前行为核对：
  - `FxYulongWarningActivity`：CERTAIN / SUSPECT / UNKNOWN 风险等级分别展示；加入白名单前复核目标仍安装、拒绝系统应用、与 `WhitelistActivity` 共用 `shield_prefs/whitelist_pkgs`、长度上限和同步 `commit()`；卸载再次确认后只打开 Android `ACTION_DELETE`。
  - `FxYulongBatchCleanupActivity`：Package/label/reason 队列、当前索引和已不存在项目状态通过 `onSaveInstanceState` 保存；每项单独二次确认；只有系统返回后包名确实从 PackageManager 清单消失才标记移除并前进，不会自动点击系统卸载确认。
- 静态复核：重新读取 ScanActivity、WarningActivity、BatchCleanupActivity、MainActivity 路由、Manifest 和 Gradle；17 项定向源码条件全部通过，包括结果状态保存、勾选恢复、扫描中断 fail-closed、过期回调保护、结果/选择上限、批量处理禁用、白名单写入确认、逐项卸载确认、原路由/Manifest 保留和固定版本。
- 固定版本核对：`versionCode 10000`、`versionName '1.0.0'`。
- 验证等级：GitHub 源码静态核对通过。未执行 Java/Android 编译、Gradle 构建、Host/Android 单测、UI 自动化、旋转/进程回收实机测试、APK 扫描或真实系统卸载流程；未触发整套 Actions。
- 失败路线：实现时第一次批量源码替换因字符串锚点不匹配而中止，未写入仓库；改用方法边界定位后一次完成。提交后的检查发现三处新增状态文本使用了双重反斜杠，已在 `bc94db31eba0510c03cc5098d56efa622f9e629d` 一次修正，当前源码中无字面量双重 `\\n`。
- 当前分支最近已读取 HEAD（本状态提交前）：`218bf32442c3c2849381c7af91e3569b0c53dc86`（前一笔由并行工作线提交的 Shield 白名单/扫描状态文档记录）。
- 下一批立即开工：① 核对安全护盾扫描页的内容特征库未就绪、APK 读取失败、超时、PackageManager inventory 不完整和病毒库空数据的页面提示，确保“无命中”不会被误说成安全；② 检查安全护盾主页的实时守护开关、前台提醒、无障碍授权和 15 分钟恢复 Alarm 状态是否来自实际服务状态；③ 随后转回 Dia 原生页面树，继续补原始 Manifest 尚未映射的 1–3 个页面组。
- 并行工作线：安全护盾扫描完整性 UI 与 Dia 页面原始组件映射可分开只读分析；共享 MainActivity / Manifest 路由有代码改动时顺序整合。


## 2026-11-05 — 安全护盾白名单统一接入及不完整扫描 UI 警示

- 本批新增/修正提交：
  - `960b09417fc174aa4871d640ffcfba63a606b96b` — 新增 `FxYulongWhitelistPolicy`，读取既有 `shield_prefs` / `whitelist_pkgs`，统一校验包名、去重、原始长度 1 MiB 上限、最多 10,000 条；超限/损坏时 fail-open，不用不完整白名单隐藏发现。
  - `ab708ad8872b9ad1f2d9c40e9201b4fd95a9a994` — 手动扫描引擎统一排除白名单应用，并显示排除数量；白名单应用不参与病毒库包名/名称和可选 APK 内容特征匹配。
  - `6dc935a6643e93561c357c0f1dce7c08b3e90864` — 安装后/前台单包自动扫描在 cooldown 和数据库查询前检查相同白名单；白名单应用不再触发自动风险提醒。数据库更新后的全量扫描通过 ScanEngine 同样应用该策略。
  - `609d4379a5442b17eeb8296ce7e54a39b11c9c3c` — 新增白名单策略 JUnit 测试（当时 6 项）。
  - `8b5a747c47b4e67debf7d013e12a14f89b24e1de` — 修正边界，恰好 10,000 条合法白名单可用，超过上限整体 fail-open。
  - `2c5fd641605bc8b06cbfb7fc771bbffdb43eae02` — 增加恰好达到 10,000 条边界用例；当前测试源码共 7 个 `@Test`。
  - `2cc97dc5efb00ef3efeff5ff58f09f73557ec539` — 内容特征扫描已启用但内容特征库未就绪时，扫描引擎状态改为明确“扫描未完成”，而非只写“名单扫描完成”。
  - `f6f00ceab7e3c687a4b52bb6963fea58a8f5cdb9` — 扫描页对 `scanComplete=false` 的结果状态使用警示色；进程/页面重建恢复不完整结果时继续显示警示色；仍保留风险项及用户逐项确认处置功能。
- 改动路径：
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongWhitelistPolicy.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongScanEngine.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongRiskScanDispatcher.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongScanActivity.java`
  - `adhook/app/src/test/java/de/privacyguard/adhook/imported/shield/FxYulongWhitelistPolicyTest.java`
- 真实行为变化：扫描风险详情加入白名单后，手动全量扫描、安装后/前台单包自动扫描、病毒库更新触发的全量扫描都读取同一份用户白名单；不会再出现“已加入白名单但仍持续扫描并发出自动风险提醒”的不一致。白名单异常/超限时不信任它来抑制风险发现。启用内容特征扫描但数据库未就绪、内容读取失败、预算超时或安装应用清单不完整时，页面明确显示未完成/无法判断；已有命中风险仍保留供用户核实。
- 静态复核：重新读取 WhitelistPolicy、ScanEngine、RiskScanDispatcher、ScanActivity 和测试源码；确认共享 prefs/key、包名格式、raw/entry 上限、超限 fail-open、扫描前排除、自动通知前排除、跳过数量反馈、内容库不可用明确不完整、未完成状态警示色/恢复警示色、7 个 JUnit 用例存在。
- 验证等级：GitHub 源码静态核对通过；7 个 JUnit 测试已新增但**未运行**；没有执行 Java/Android 编译、Gradle 构建、UI 自动化、安装、病毒库扫描或真机通知/白名单验证。
- 未触碰病毒库命中阈值、severity 判断、PackageManager 清单完整性或卸载/停用行为；白名单只调整扫描/提醒的适用范围，不会处理应用安装状态。
- 本批未触发整套 Actions；没有走失败路线。
- 下一批：① 核对 `FxYulongShieldActivity` 的日报/防护状态、自动安装扫描和通知权限文案与实际 dispatcher / service 状态一致；② 检查扫描页白名单切换后手动刷新及自动前台扫描是否回读新值；③ 然后回到 Dia 原始页面映射和未迁移四级入口。


## 2026-11-05 — 游龙 Tasker Root 广播发送方身份与 APK 签名固定

- 本轮起始时从实时分支读取到的 HEAD：`2df54b03bc98de8012723012f759208a1bde7cab` 之后的连续进度；本轮写入前最新代码 HEAD：`bcf5a375d60537a2d56b10c003fffb1cf4de7def`。
- 代码提交：
  - `c55a99621eae7d943e437903d62b3a7f5972da70` — Receiver 在 Root 操作前核对 API 34 实际发送包名、发送 UID 与 UID 包列表。
  - `da09e80b2830e1b0261ce545587a791780da13ff` — 通用设置新增授权自动化包名输入、验证与显式开关。
  - `92d346d4eb1f03e5dc0c36a2c3be04bcdbf398e8` / `3b2e8d4f1d399245d0572251fb0092208a365f16` — 新增并强化纯 Java `FxYulongTaskerCallerPolicy`，验证发送身份、UID 包归属和签名 SHA-256。
  - `3588f353b5e2fb1292675d3904b466113d3d568e` / `cdb5db3f1d9e6aae682788de3ef716b535775e79` — 新增身份与签名固定策略 JUnit 源码测试。
  - `8892044df0efaf4358e9c57ea7c0ad8ef532da16` / `edcc96f2f9e630c864d06bb884c14fcaec9373ee` — Receiver Root 闸门加入固定 APK signer 验证；UI 保存包名时同步保存 signer digest。
  - `43c65a2ba850192da1f38854fc576d3a8de1f459` / `bcf5a375d60537a2d56b10c003fffb1cf4de7def` — 单签名应用遵循 Android SigningInfo 当前签名历史读取，多签名应用比较完整当前 signer 集合。
  - `168384449ae5ee7af3bf4d932ef14a91ffd01bad` / `97538850597510b1c38e639ff8f139fddb0ee224` — General Activity PackageManager import 与签名固定 UI 文案。
- 改动路径：
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdTaskerReceiver.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdGeneralActivity.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongTaskerCallerPolicy.java`
  - `adhook/app/src/test/java/de/privacyguard/adhook/imported/ad/FxYulongTaskerCallerPolicyTest.java`
- Root-backed Tasker 请求现在要求同时满足：Android 14/API 34 或更高、系统返回的实际发送包名等于用户配置的授权包名、发送 UID 的 packagesForUid 列表包含该包、当前安装 APK signer SHA-256 与用户授权时固定的 digest 匹配、并且 `allow_external_actions` 显式开关开启。任何一个身份数据为空、无法读取、签名变化或身份不匹配均 fail closed；未认证广播不运行 Root、不覆盖最近回执。
- 用户在通用设置保存授权包名时，FX 验证该包当前已安装并读取证书，保存包名与 signer digest；保存后仍把 Root 自动化开关设为关闭，需用户再次手动开启。清除授权包名同时清除证书 pin 并关闭外部 Root 控制。返回页面时若签名不匹配，UI 自动关闭旧授权、禁用开关并要求重新验证。
- 单签名 APK 使用 `SigningInfo.getSigningCertificateHistory()` 最后一项（当前签名）；多签名 APK 使用 `getApkContentsSigners()` 的完整当前签名集合，摘要按排序后的 SHA-256 值组合，避免数组顺序不稳定。API 34 发送方身份方法由运行时 API guard 保护；Android 14 以下明确禁用外部 Root 广播。
- Android 官方 API 核对：`BroadcastReceiver.getSentFromPackage/getSentFromUid` Added in API 34；`PackageInfo.signingInfo` 与 `SigningInfo` 证书 API Added in API 28，与项目 minSdk 28 相容。<Cite refs={["turn505896search1","turn505896search0","turn505896search3"]} />
- 静态复核：重新读取 Receiver、GeneralActivity、helper、测试源码与 Gradle；确认两侧共享同一 Pref key、用户授权保存 package+signer digest、Root gate 在 Root 操作前、sender package/uid/uid packages/signer 全部核验、证书变化会阻止执行、JUnit 覆盖基础身份和签名变化。
- 本地验证：临时 JDK harness 编译并执行 10 项纯 Java 策略断言，10/10 通过（发送方/UID/签名匹配、API<34 拒绝、包名/UID不匹配、签名变化/缺失、多个签名排序稳定、无签名材料/自身包拒绝）。这不是仓库 JUnit 任务或 Android 构建结果；新增 JUnit 源码尚未执行。未运行 Gradle/Android 编译、Tasker 外部应用真实广播、KernelSU Root 命令或真机验收。
- 固定 Gradle 仍为 `versionCode 10000` / `versionName 1.0.0`；未生成 APK/KernelSU ZIP。
- 本批未触发完整 Actions；未采用弱化安全控制的兼容路线。
- 后续边界：API 34 以下无法从公开 BroadcastReceiver API 验证原始发送方，故有意 fail closed；这些设备上的 Tasker Root 广播不可用，用户仍可通过 FX 原生 UI 操作。
- 下一批直接任务：① Shield 用户白名单管理页统一使用 `FxYulongWhitelistPolicy` 解析，限制最多 10,000 个有效包名和 1 MiB 原始持久化字符；选择器超限时拒绝整批保存，不截断、不部分信任；② 复核 Shield 白名单和风险扫描结果恢复的列表/批量清理行为；③ 六 Tab/Hook 嵌套返回链再做最小状态审查。
 
## 2026-11-05 — 六 Tab 顶层切换清理 Hook 嵌套路由

- 代码提交：`413d502a05a8a3b51a42fe7dc79329278abde1f4`。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`。
- 顶层 Tab 选择先校验范围为 0–5，并清除 Hook 自定义规则子页返回意图，避免用户已切换到其他顶层页面后按返回键意外回到旧 Hook 子页。第五 Tab 重新进入 Hook 应用列表；第六 Tab 进入 Settings；前四 Tab 继续其对应主页/原生页面。实际页面切换依赖既有 showSettings/showAppList/showWebDashboard 状态清理逻辑。
- 静态核对了 Handler 分支、目标/Hub 标志清理及 showWebDashboard/showSettings/showAppList 的页面状态分配；未执行旋转/进程重建 UI 自动化或真机操作回归。

## 2026-11-05 — Shield 用户白名单与扫描状态恢复批次（分支最新代码）

- 当前分支已包含以下提交：
  - `960b09417fc174aa4871d640ffcfba63a606b96b` — 统一白名单解析策略，限制原始内容 1 MiB、有效包名最多 10,000；超限时不返回部分信任名单，扫描按 fail-open 继续检测。
  - `ab708ad8872b9ad1f2d9c40e9201b4fd95a9a994` — 全量/单应用手动扫描先套用用户白名单，跳过白名单应用并显示跳过数量。
  - `6dc935a6643e93561c357c0f1dce7c08b3e90864` — 前台/安装自动风险扫描分发前应用相同用户白名单，避免仍发出自动风险提醒。
  - `609d4379a5442b17eeb8296ce7e54a39b11c9c3c` / `2c5fd641605bc8b06cbfb7fc771bbffdb43eae02` — 白名单解析/异常数据 fail-open/恰好 10,000 条边界测试源码。
  - `8b5a747c47b4e67debf7d013e12a14f89b24e1de` — 修正边界逻辑，恰好 10,000 条有效条目允许，超过才整体 fail-open。
  - `65c97aabb7f3fdb368f93563a7413587df50164e` — 手动扫描页旋转/Activity 重建保存结果与批量选择；超出 128 条或状态不完整时禁用批量处理并要求重扫。
  - `bc94db31eba0510c03cc5098d56efa622f9e629d` — 修复扫描结果恢复状态中的换行显示。
- 主要改动路径：`FxYulongWhitelistPolicy.java`、`FxYulongScanEngine.java`、`FxYulongRiskScanDispatcher.java`、`FxYulongScanActivity.java` 及对应 shield tests。
- 已静态核对：扫描侧与自动通知侧使用相同 whitelist policy；解析只接受合法完整 Android 包名并去重；超出 1 MiB / 10,000 有效项时返回空集，确保不会因损坏/超限名单压制检测；Activity 恢复不完整时禁用批量操作。
- 当前尚待改进：原有 `WhitelistActivity` / `WhitelistPickerActivity` 仍自行解析和写入 `shield_prefs/whitelist_pkgs` CSV，未直接复用中央 policy，也未在写入端实施同样的有效包名/总条数/序列化字节限制。若 UI 写入过大的数据，扫描侧虽 fail-open，但用户管理页仍会展示/写入不一致；本轮后续应修复写入端而不是改变扫描 fail-open 策略。
- 固定版本不变；未生成最终包。相关 JUnit 测试源码存在，尚未声称已执行 Gradle/JUnit/真机。


## 2026-11-05 — 安全护盾首页权限/服务状态与日报口径

- 本批代码提交：`fe0332b9aae52a961375e101b69d20d24168bb12`。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongDailySummaryActivity.java`。
- 日报修正：`automatic_scan_count_today` 在单包扫描中每检查一个包 +1，在病毒库全量扫描中增加实际扫描应用数，因此不是“扫描次数”。标题改为“自动风险扫描应用数”，显示“今日检查应用 X 个”；说明统计包含前台、安装/更新及病毒库更新后的扫描来源。
- 后台状态修正：日报不再仅依赖可能过期的 `protect_service_running` SharedPreferences 标记；改为通过当前应用 `ActivityManager.getRunningServices` 检查 FX 自己的 `FxYulongProtectionService` 和 `FxYulongRescueOverlayService` 实际运行项。仍单独显示名单监测/摇动/音量的用户配置开关，并独立展示当前 Android 通知权限状态，避免将配置意图与运行状态混为一谈。
- 与此同时，重新读取到的最新 `FxYulongShieldActivity.java`（blob `f7b415c78cebba3de64f0ebd4fdd2302778f5632`）已经有 `onResume()` 权限/服务状态刷新：重新检查通知、Usage Access、无障碍、悬浮窗和实际服务运行情况；本批没有覆盖或回退该较新实现。
- 静态复核：重新读取日报和 Hub 源码；确认扫描计数单位、来源说明、两项服务实际运行检查、通知权限回读和 Hub 的 onResume 状态刷新均存在。
- 验证等级：GitHub 源码静态核对通过；未运行 Android 编译、Gradle、JUnit、UI 自动化、安装或设备服务状态测试。`getRunningServices` 属于 Android 已弃用 API，当前只用于本应用服务的可见运行状态；仍需在目标 Android 版本设备核验其实际返回行为。
- 未改自动扫描调度、权限申请策略或守护服务生命周期；未触发完整 Actions。
- 下一批：继续 Dia 原始页面映射和未实现四级页面，优先找 1–3 个可形成真实页面组的原生迁移项；安全护盾剩余需对照原始 9.9.60 页面/服务逐项验收。


## 2026-11-05 — 游龙安全护盾实时权限与服务状态回读

- 本批开始时分支 HEAD：`6723112603c04f5e97764913a76d4a4949aa95ed`；本状态提交前已读取到并行工作线 HEAD：`8a4353ca7c8ce2b529b0fca061caa5fb29241dd8`。
- 本批页面：游龙安全护盾 9.9.60 三级主页，修复从 Android 系统权限设置返回后权限开关/服务状态不刷新的问题。
- 代码提交：
  - `f68e3d8c999d2b0bca39f774669e56ade13f7bd8` — 增加 onResume 权限/服务回读、七个开关与风险处理模式/音量触发参数的状态恢复。
  - `e83ec3d92d92e56bdcdd64f5b308aed79a9f4d2e` — 修正刷新保护 listener 的 Java block lambda 语法。
  - `55db4ddcbda22ee273b9917f90b2d44b5ad0538b` — 将实时服务状态从静态“最近提醒”摘要中分离，避免用 Activity 创建时缓存的偏好标记冒充当前运行状态。
  - `34a8c5a24b90ebedcbc675fe6fe57d436d58daf6` — 修正最近提醒摘要的换行显示。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongShieldActivity.java`。
- 真实行为变化：
  - 每次 Activity onResume（包括从 Android 权限设置返回）重新读取 Usage Access、通知权限、FX Accessibility 连接状态、悬浮窗权限，以及 Protection/Rescue 两个服务是否实际出现在本应用运行服务列表。
  - 七个设置开关、direct/confirm 风险模式和音量触发按键/次数从同一 `shield_prefs` 重新同步；刷新期间 listener 被抑制，不会因 UI 回读而误写配置、重启服务或弹出权限提示。
  - 运行状态卡显示“服务运行中/未运行”及配置开关状态，并在权限已撤销时说明能力不可用；最近提醒卡只显示历史计数/时间/消息。
- 定向静态复核：最新 ShieldActivity 的 12 项源码条件通过（onResume 刷新、7 个开关恢复、8 个 listener 刷新保护、真实 Usage/Notification/Accessibility/Overlay 查询、实际服务枚举、历史提醒与实时状态分离、换行正确、无表达式 lambda 中非法 return）。
- 验证等级：仅 GitHub 源码静态复核；未运行 Java/Android 编译、Gradle 构建、JUnit、UI 自动化、模拟器/真机权限撤销与服务启停测试。没有声称运行验收通过。
- 并行工作线在本批后又提交了日报计数口径与服务状态读取修正（`fe0332b9aae52a961375e101b69d20d24168bb12`）；本批没有覆盖其文件。
- 未触碰扫描/风险判定阈值、服务启动策略、无障碍授权或系统权限；固定版本仍为 FX 1.0.0；未生成 APK/KernelSU ZIP；未触发完整 Actions。
- 下一批直接任务：① `WhitelistActivity` / `WhitelistPickerActivity` 写入端复用 `FxYulongWhitelistPolicy`，统一包名验证、1 MiB 原始存储与 10,000 条上限，超限整批拒绝而不截断；② 检查白名单变更后的扫描/通知读取回路；③ 转回 Dia 原始页面映射，按 Manifest 对照补齐尚未映射的四级页面。
- 失败/替代路线：首次 listener guard 插入后发现两个表达式 lambda 不能包含 return，已改为 block lambda；一次状态摘要替换锚点不匹配，改按方法边界定位；换行转义经源码回读后修正。没有重复旧失败路线。


## 2026-11-05 — Shield 无障碍系统授权状态二次核验

- 本批代码提交：5718c7fa31e1b260e70896ed5ac52ed63f414fcd。
- 改动路径：adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongShieldActivity.java。
- 在既有 onResume()/refreshControlsFromSystem() 上补充 Android 系统 Accessibility 组件状态核验，不再只看 FxAccessibilityService.isConnected()：
  - 解析 Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES 中的组件条目；
  - 必须匹配当前包名和精确的 FxAccessibilityService 类名；
  - 同时要求 FX 静态服务连接标志、fx_accessibility/service_connected 持久化标志和当前进程 PID 完全一致。
- 实时权限状态卡现在分别显示“无障碍系统开关”和“FX 服务连接”；若自动前台扫描或音量键触发开关已保存，但系统无障碍服务未真实连接，会明确提示当前功能不可用，不把配置保存状态冒充已启用状态。
- 服务运行状态继续采用当前应用的 ActivityManager.getRunningServices 实际 Service 查询，并把前台名单守护与摇动救援设置分开说明；不会因摇动救援使 Service 存在就声称前台名单监测已开启。最近提醒历史仍与实时服务运行状态分离。
- 静态复核：重新读取 ShieldActivity、ProtectionService、AccessibilityService、Manifest 和 Gradle；确认 onResume 状态刷新、Secure Setting 精确 ComponentName 匹配、服务连接/偏好/PID 三重核验、Usage/Notification/Overlay 权限回读、ActivityManager Service 查询、守护与摇动开关分离、历史提醒独立、listener 刷新保护均存在。
- 验证等级：GitHub 源码静态核对通过。未运行 Android 编译、Gradle、JUnit、UI 自动化、系统 Accessibility 开关真实切换、Service 进程被杀/重启或 Android 版本真机验证。getRunningServices 属 Android 已弃用 API；当前仅枚举本应用自己的 Service，仍需在目标 Android 12–16 设备验证返回结果。
- 固定版本仍为 versionCode 10000 / versionName 1.0.0。未触发整套 Actions、未生成 APK 或 KernelSU ZIP。
- 本状态提交前已读取分支 HEAD：1a00262f3cfe1fdc407df3588c0d97c587077405；本批代码提交 5718c7fa31e1b260e70896ed5ac52ed63f414fcd 已在该 HEAD 的历史中。
- 下一批直接任务：① Dia 原始 Manifest/页面映射，对照当前独立 Activity 路由，选择 1–3 个尚未独立迁移的页面实现真实页面结构与返回链；② 优先覆盖 Dia 当前显示为 pending/通用占位的原始页面，而不是继续修安全护盾边缘 UI；③ 模块构建环境可用时再跑 Android compile/Gradle，当前 DNS 阻塞仍须如实说明。
- 并行工作线：Dia 页面目录/Manifest 映射可独立只读；共享 MainActivity / Manifest 路由变更按顺序整合。


## 2026-11-05 — Shield 每日总结统计口径与实际服务状态

- 本批代码提交：`fe0332b9aae52a961375e101b69d20d24168bb12`。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongDailySummaryActivity.java`。
- 统计口径修正：`automatic_scan_count_today` 实际累计的是已检查应用数量（单包事件每包 +1；全量扫描按实际 scanned 数增加），不是“扫描触发次数”。日报标题改为“自动风险扫描应用数”，显示“今日检查应用 X 个”，并说明包含前台、安装/更新和病毒库更新后的扫描。
- 运行状态修正：日报不再通过可能过期的 `protect_service_running` SharedPreferences 作为服务实时状态；改为查询 FX 自己的 `FxYulongProtectionService` 与 `FxYulongRescueOverlayService` 运行项。用户保存的 protect/shake/volume 开关仍单独显示为配置状态；通知权限也作为实际系统权限单独回读。
- 同批复核到当前最新 `FxYulongShieldActivity.java`（blob `a5533b7078c559bac3bafce17670b46761e868e0`）：已实现 onResume 刷新全部控件，并通过 PackageManager 之外的系统权限 API 与 ActivityManager 实际检查 Usage Access、POST_NOTIFICATIONS、Accessibility、悬浮窗、两个前台服务状态；未把这部分较新的代码用旧版本覆盖。
- 静态复核：日报显示单位、扫描来源、两个 Service 运行状态检查和通知权限状态均存在；Shield Hub 的 `onResume()` 调用 `refreshControlsFromSystem()`，系统权限/服务状态改变后返回页面会刷新。
- 验证等级：GitHub 源码静态核对通过；未运行 Android/Kotlin 编译、Gradle、JUnit、UI 自动化、安装或真机服务状态测试。`ActivityManager.getRunningServices` 为 deprecated API，仅用于同应用服务检测，设备兼容性仍未验证。
- 本批未改变扫描计数的写入行为、服务生命周期、权限申请或自动扫描调度；未触发完整 Actions。
- 下一批：继续 Dia 页面迁移映射；先检查“对话框与通知/剪贴板”是否使用 per-app Hook 配置还是 FX 全局隐私设置，避免路由错位；随后核对 GPS/设备模拟页面保存与发布完整性。Dia 所有原始页面和业务逻辑仍未全量验收。


## 2026-11-05 — Shield 用户白名单管理读写与三个运行时消费者统一

- 本批代码提交：
  - `db5adc459d64d33a4b427bf5eb070060327f22fe` — 扩展 `FxYulongWhitelistPolicy`，添加公开包名校验及 bounded CSV serializer；非法包名、超过 10,000 唯一条目或超过 1 MiB 原始字符一律返回拒绝写入。
  - `90779ddd1a6ffa440355ae7b8dbc6e4f7b7a523b` — `WhitelistActivity` 使用中央 parser / serializer；移除单条保存失败恢复内存条目；超限时 UI 明确提示，不部分写入。
  - `f2a5b9ed0d3298d3fce564103d75326fd5af8c87` — `WhitelistPickerActivity` 使用相同 parser / serializer；多选合并超限时拒绝整批写入，SharedPreferences 提交失败保持原配置。
  - `e122edd5b322255cbafc2fd503838ca7522c2359` — 新增序列化测试：重复项去重/往返、非法包名整批拒绝、超过条数拒绝、超过原始字符限制拒绝。
  - `ea235c13fa28e5c8c415c938c844e7b910a62d27` — 实时 `FxYulongProtectionService.evaluateForeground()` 读取用户白名单改用中央 policy，不再自行 CSV split。
- 改动路径：
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongWhitelistPolicy.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/WhitelistActivity.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/WhitelistPickerActivity.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongProtectionService.java`
  - `adhook/app/src/test/java/de/privacyguard/adhook/imported/shield/FxYulongWhitelistPolicyTest.java`
- 当前三个运行时入口统一：手动全量/单应用扫描 (`FxYulongScanEngine`)、自动前台/安装风险通知 (`FxYulongRiskScanDispatcher`)、实时黑名单前台守护 (`FxYulongProtectionService`) 都调用 `FxYulongWhitelistPolicy.load/isWhitelisted`；管理页与全屏 picker 从同一 parser 读取并从同一 serializer 写入 `shield_prefs/whitelist_pkgs`。
- 解析规则：去空格、去重、仅接受合法 Android 包名；超过 1 MiB 原始字符或超过 10,000 个唯一合法包名时，解析返回空名单，扫描不会部分忽略风险应用。恰好 10,000 条仍然有效。
- 写入规则：`serialize()` 对非法包名、条数超限、字符数超限均返回 null；两个页面都拒绝写入任何部分数据。单项移除操作如提交失败，会把该应用恢复回 UI 列表；picker 的合并保存用同步 commit 读取结果，失败时不关闭页面或报告成功。
- UI 处理：管理页读取超限/全无效数据时显示警告；picker 显示原名单未能完整信任提示；只有用户选择新有效应用并完成 commit 后，旧无效配置才会被覆盖。
- 定向验证：本地独立 JDK harness 使用 Android Context/SharedPreferences/Log 与 JUnit 最小 stub 编译策略及测试逻辑，运行 11 项断言全部通过：合法包/去重、非法项过滤、空/null、原始输入上限、超过条数 fail-open、恰好 10,000、序列化往返、非法写入拒绝、超过条数写入拒绝、超过 1 MiB 写入拒绝、非法包查询。此 harness 不是 Android Gradle/JUnit task，也不代表 Activity/Service 已编译。
- GitHub 静态复核：重新读取 policy、两管理页面、实时 ProtectionService、测试源码；确认三个运行时消费点和两个 UI 写入点均指向同一 policy/serializer；确认 Gradle 仍为 `versionCode 10000` / `versionName 1.0.0`。
- 未执行 Android 编译、Gradle 构建、仓库 JUnit task、UI 自动化、模拟器/真机手动扫描/自动通知/前台守护流程。未触发整套 Actions。
- 未完成项：原始 Shield 9.9.60 的其他第四级页面仍需对照原应用逐页查漏；尤其风险详情、管控规则、日报与实时状态页面还需目标 ROM 验证。
- 下一批直接任务：① Dia 页面目录与 Manifest 原生路由映射，找出尚未独立迁移的 1–3 个原始四级页面；② 检查 Dia 页面返回链和权限状态；③ 构建环境可用时跑 targeted Android compile。


## 2026-11-05 — Dia 剪贴板/通知页面路由纠偏

- 本批代码提交：`c78577a75b1fb11d85f06439fc763ac91946e67b`。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`。
- 原问题：Dia 原始页面树中的“对话框与通知”和“剪贴板”两个 target-app scoped 子页都路由到 FX 全局 `notifyPanel` 隐私设置组，作用范围与页面层级不一致。
- 修正：`剪贴板` 进入每应用 Hook 详情的“剪贴板保护”部分（读取阻断/隔离两个独立真实配置）；`对话框与通知` 进入每应用 Hook 详情的“通知保护”部分（通知监听注册阻断/权限提示控制）。两个路由都保留 `markMigrationChild` 的迁移应用返回链。
- 复核依据：最新 MainActivity 存在对应 `showTarget` 控件并读写 per-app config key：`clipboard_read_block`、`clipboard_isolate`、`notification_listen_block`、`notification_permission_hide`；其发布仍通过 FX Hook 配置发布路径。全局 `notifyPanel` 保留在 FX Privacy Tab 内，未删除。
- 未完成/不得误报：Dia 原版专用的 Dialog 拦截/自动处理逻辑没有在本批迁移。现在此三级/四级入口可进入真实的 per-app 通知 Hook 配置，但不能据此标记“对话框处理完整迁移”。下一轮需对照原始 Dia APK 页面/实现，确定对话框工具实际操作对象和回调，再决定独立 Activity 还是复用自定义 Hook；不能仅添加一个假开关。
- 验证等级：GitHub 源码静态核对通过（路由与四个对应配置键存在）；未运行 Java/Kotlin 编译、Gradle、单测、UI 自动化、安装或 LSPosed 实际注入/真机验证。
- 未删除原有全局通知/剪贴板隐私配置；未改版本号；未触发完整 Actions。
- 下一批：继续 Dia GPS/设备属性模拟表单与真实 Hook 发布适配核对，重点验证 UI 声称的 fused location callback、provider enabled、lat/lon/accuracy 是否都被执行层支持；随后补上未迁移的 Dialog 功能映射。


## 2026-11-05 — Shield 白名单管理页读写端与实时守护第三消费点完成统一

- 写入前实时分支 HEAD：`00e74f28e62ea9cef7362dc022ff1175f5d79b1f`。
- 代码提交：
  - `db5adc459d64d33a4b427bf5eb070060327f22fe` — 中央策略增加 `isValidPackageName()` 和有界 `serialize()`。
  - `90779ddd1a6ffa440355ae7b8dbc6e4f7b7a523b` — 白名单管理 Activity 统一 parser/serializer，commit 失败不虚报成功，单项移除失败恢复条目。
  - `f2a5b9ed0d3298d3fce564103d75326fd5af8c87` — 全屏多选 Picker 统一 parser/serializer；超限整批拒绝、提交失败保留原配置。
  - `e122edd5b322255cbafc2fd503838ca7522c2359` — 增加 serializer 去重往返、非法包名、超过条数、超过原始字符上限的测试。
  - `ea235c13fa28e5c8c415c938c844e7b910a62d27` — 实时前台 ProtectionService 白名单读取切换到中央 policy，移除该消费点的独立 CSV parser。
- 改动路径：`FxYulongWhitelistPolicy.java`、`WhitelistActivity.java`、`WhitelistPickerActivity.java`、`FxYulongProtectionService.java`、`FxYulongWhitelistPolicyTest.java`。
- 当前三个运行时消费者统一使用中央白名单：手动全量/单应用扫描、自动前台/安装风险通知、实时前台黑名单守护；两个 UI 管理写入入口也使用相同规则。
- 写入端严格拒绝非法包名、超过 10,000 个唯一包名或 CSV 长度超过 1 MiB 的整个写入；不会截断，也不会部分保存。读取端遇到超限名单仍返回空信任集合（fail-open 扫描），不会因名单损坏隐藏风险。恰好 10,000 个唯一条目保持可用。
- 管理 UI 会显示原名单为空/全无效/超限的警告；新增应用时把有效集合重新完整序列化，只有本地 commit 成功才关闭页面。单项移除保存失败会恢复 UI 中的原条目。
- 本地验证：临时 JDK harness 使用 Android Context/SharedPreferences/Log 与 JUnit 最小 stub 编译策略/测试逻辑，11 项断言 11/11 通过。这不是仓库 Gradle/JUnit 任务；未运行 Android 编译、Gradle、Activity 真机/模拟器交互或真实扫描服务测试。
- GitHub 静态复核：重新读取 Policy、管理页、Picker、ProtectionService、测试与 Gradle；确认三个运行时消费点、两个 UI 写入点统一、限额 guard、失败恢复和测试源码均存在；版本仍为 FX 1.0.0 / versionCode 10000。
- 这一节覆盖并完成前一节“WhitelistActivity / WhitelistPickerActivity 写入端尚未采用统一 policy”的待办；不改变之前的 fail-open 安全策略。
- 未运行完整 Actions；未生成最终 APK 或 KernelSU ZIP。
- 下一批直接任务：① Dia 目录/Manifest/Activity Browser 页面路由映射，对照当前原生页面找 1–3 个未独立迁移或通用占位页面；② 补页面的导航、编辑/详情和返回链，不只增加空按钮；③ 页面完成后按对应后端能力做 targeted 检查，再更新当前分支状态。


## 2026-11-05 — Dia Activity Browser 异步应用清单、搜索与组件状态安全回滚

- 本批开始时分支 HEAD：`8e973483d0bcfb70d01696882862cc66907de4ca`。代码提交：
  - `8254414000312d6e580a5d9b8a29b42caf022385` — 应用枚举/显示名加载迁移到后台有界任务队列；应用选择器改为可按名称/包名搜索的 ListView；应用列表加入刷新入口；页面销毁时取消任务并丢弃过期回调。
  - `479434809e8c1e10ba5097a0cdc764e176ce8f21` — Activity 组件状态查询移到后台；加入组件状态/应用整体启用状态展示；修复取消/失败/队列拒绝时开关回滚触发再次监听器的问题。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaActivityBrowserActivity.java`。
- 实际变化：
  - `PackageManager.getInstalledApplications()`、应用标签读取和排序全部在后台执行；UI 显示读取/失败/空清单状态，支持手动刷新。
  - 目标选择器不再弹出超长无搜索 `setItems` 列表，改为名称/包名模糊 contains 过滤；点击后记录准确 package 和 label。
  - Activity 清单读取仍在后台，并在结果返回前验证请求代次和当前目标包名；用户快速切换目标或退出页面时旧回调不会覆盖新状态。
  - 每个 Activity 的 PackageManager 组件启用状态和应用整体 enabled 状态在后台读取；UI 不再针对每个 Activity 在主线程调用 PackageManager。
  - 启用/禁用仍保留 Root 命令和逐项确认；当前 Android user id 必须成功解析，组件参数 shell quote；取消、Root 返回非零、Root 抛错、未返回结果和任务队列满均恢复原开关状态。新增程序性回滚 guard，防止 `setChecked()` 再次触发监听器并发出相反 Root 命令。
  - Root 命令返回 0 后仍重新读取 Activity 与组件状态；状态显示“命令已执行，正在重新读取”，不直接把命令执行当成 PackageManager 已确认生效。
- 定向静态复核：重新读取 Activity、MainActivity 路由和 Manifest；确认页面仍以 `exported=false` 注册；检查异步应用枚举、label 后台读取、搜索过滤、刷新入口、Activity 读取 generation guard、组件状态后台读取、程序性 rollback guard、取消/失败/队列拒绝 rollback、当前 user id 校验、销毁取消回调共 14 项，14/14 通过。
- 验证等级：GitHub 源码静态核对通过。未运行 Java/Android 编译、Gradle、UI 自动化、模拟器或真机组件启停；不能声称该页面已在 OnePlus 12/LSPosed 设备上验收。
- 未改变原始“仅用户应用”边界、MAIN/LAUNCHER 过滤语义、Root 逐项确认或可恢复的组件启停能力；未改版本号、未打包最终 APK/KernelSU ZIP、未触发完整 Actions。
- 后续风险：PackageManager 在不同 OEM / 多用户 / 企业工作资料环境下对 `MATCH_DISABLED_COMPONENTS`、component enabled state 与 `am get-current-user` 的返回可能存在差异；须真机核验。用户若禁用自身唯一 launcher Activity，可能需要从 FX 返回此页恢复。
- 下一批直接任务：① Dia 设备属性/GPS 子页目前路由到 per-app Hook 表单；对照原 Dia 页面逐项核对 Android ID、时区、版本、GPS、provider enabled/Fused 返回位置是否有实际执行层支持，修复 UI/后端不一致；② 对话框/通知页仍只有 per-app 通知 Hook 配置映射，原版 Dialog 专用逻辑明确未迁移，继续对照旧页面/规则能力，不增加空壳开关；③ 之后审查 Dia 网络代理与 Frida 监听模式的页面级返回链。

## 2026-11-05 — Dia 结构化监控事件与 Frida 会话日志页状态恢复

- 本批起始分支 HEAD：`585303b7bb0b09b95a141c501133e36b11d9818d`；代码提交完成后读取的分支 HEAD：`cb24ba204210fafc21da579c036a3cce77a02293`。
- 本批代码提交：
  - `9b0d8e21a56ca51bda420f2e70fd1076feb20f69` — `adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaMonitorEventsActivity.java`.
  - `1eb27f788561db1db3e9ec1d32139f4beb04c3a5` — `adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaSessionLogActivity.java`.
  - `cb24ba204210fafc21da579c036a3cce77a02293` — `scripts/tests/fx-dia-monitor-event-view-regression.sh`.
- 页面行为：
  - 结构化事件页 Activity 重建后恢复搜索词、事件类型筛选、自动刷新开关和列表滚动位置。
  - 原始会话日志页恢复搜索词与滚动位置；日志内容从当前目标的 FX 日志文件重新读取，不把旧 Bundle 文本当作实时日志。
  - 搜索词恢复限制 256 字符；滚动位置只在本次有界日志读取完成后恢复，避免内容回填前被空列表截断。
  - 保留日志读取上限、Root 路径符号链接检查、事件元数据脱敏解析、15 秒自动刷新及 request-generation 过期回调保护。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaMonitorEventsActivity.java`、`adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaSessionLogActivity.java`、`scripts/tests/fx-dia-monitor-event-view-regression.sh`。
- 针对性回归：扩展 `fx-dia-monitor-event-view-regression.sh`，覆盖两个页面的搜索/筛选/自动刷新/滚动状态恢复契约；原有 Java Host 测试与 Frida 模板 Node 语法检查保留。
- 验证：提交前对两份 Java 源码和回归脚本执行定向静态断言，全部通过。没有运行仓库 Shell 回归脚本、JDK Host 测试、Android/Gradle 编译、JUnit、UI 自动化、模拟器或真机旋转/进程回收测试；设备级页面恢复未验收。
- 未改六 Tab 顺序、原始 Frida 目标/脚本/日志数据或固定版本；未触发完整 Actions；未生成 APK 或 KernelSU ZIP。
- 失败路线：Git Data 写入接口第一次返回 GitHub 平台端错误，分支 ref 未更新；切换为 Contents API `update_file` 顺序写入，并在每个文件写入前核对 blob SHA，未覆盖并行变更。
- 下一批直接任务：
  1. Dia GPS / 设备属性模拟表单：对照目标应用配置键、数据校验和发布字段，找出 UI 与 API-101 consumer 不匹配项。
  2. Dia 原始 Dialog 功能：对照原始 APK 交互语义，区分 per-app 通知 Hook 与 Dialog 自动处理工具，不复用错误的全局隐私开关。
  3. 游龙广告 DNS / Firewall 原生页面：核对真实数据源、列表、表单及刷新/错误状态，再接通已有本地 DNS / Root Proxy 后端。
- 并行工作线：Dia 模拟表单配置键/序列化映射可独立只读核对；共享 `MainActivity.java` / Manifest 的实际修改顺序整合。


## 2026-11-05 — Dia Activity Browser / Hidden Apps 页面分页、搜索与恢复加强

- 本批开始时最新分支 HEAD：585303b7bb0b09b95a141c501133e36b11d9818d；本批后续修正提交：82bbc762d172b553c6fc085e5207c7718b68cfff。
- 改动路径：adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaActivityBrowserActivity.java。
- 本批是在既有 Activity Browser 异步枚举版本上进一步统一原生页面交互，不是新增第二套浏览器：
  - 用户应用选择器在原有后台 PackageManager 枚举基础上，增加名称/包名本地搜索和每页 50 个应用的分页控件。
  - Activity/隐藏应用组件列表增加类名、权限、导出状态和组件状态搜索，每页最多 80 项，列表不再一次创建所有组件行。
  - 页面 Bundle 保存并恢复目标包名、应用搜索、Activity 搜索、两个分页索引；恢复时重新通过 PackageManager 读取安装状态和组件状态，不用 Bundle 假造系统当前状态。
  - Activity onResume 后刷新用户应用清单；已选目标仍存在时重新读取 Activity/launcher 组件元数据与实际启用状态；若目标已卸载，保留原配置但清空当前失效目标。
  - 保留 MAIN/LAUNCHER 查询语义、仅列用户应用、launcher_only 过滤、Root 命令当前 user id 检查、shell quote 和逐组件二次确认。
  - PackageManager 组件状态正确区分 ENABLED、DEFAULT、DISABLED、DISABLED_USER、DISABLED_UNTIL_USED；Root 命令成功后仍重新查询系统状态，不将退出码 0 直接显示成已验证生效。
  - 组件查询和应用清单后台任务带 generation/目标包名校验；旧目标或页面销毁后的回调不写回新 UI。
- 本批提交：
  - 585303b7bb0b09b95a141c501133e36b11d9818d — 可搜索分页的 Activity/Hidden Apps 原生浏览器改造。
  - 82bbc762d172b553c6fc085e5207c7718b68cfff — 修正同方法重复实现、保留刷新前 Activity 页码并补齐 disabled-until-used UI 状态。
- 定向源码静态核验：搜索/分页、Bundle 目标与页码恢复、onResume 刷新、后台枚举、launcher 过滤、组件状态枚举、Root 二次确认、当前用户校验、shell package/class 验证、过期回调保护、方法唯一性和括号平衡均通过；MainActivity 原路由和 Manifest 注册未变。
- 验证等级：GitHub 源码静态核对通过；未运行 Java/Android 编译、Gradle、JUnit、UI 自动化、模拟器/真机组件启停或旋转/进程重建验收。不能声称视觉或设备验收通过。
- 原有 Activity Browser 功能和权限边界保留；未更改固定版本 1.0.0、未触发完整 Actions、未生成 APK/KernelSU ZIP。
- 下一批直接任务：① Dia 设备属性 / GPS 页面组，对照 per-app 表单保存键、Root/Remote Files 发布字段和 API-101 consumer，重点检查 Android ID、时区、应用版本、GPS 坐标/accuracy、provider enabled 与 Fused Location 回调是否一一对应；② 随后核对 Dialog 专用工具，不能把通知读取/阻断 Hook 当作 Dialog 自动处理；③ 对照原页面与现有 Activity，只补确实尚未实现的表单/详情/返回链。
- 并行工作线：设备模拟字段和 Hook config serializer/runtime consumer 可以独立只读检查；涉及 MainActivity 统一按当前 blob 顺序整合。


## 2026-11-05 — Dia 设备模拟配置发布范围收紧

- 本批代码提交：
  - `283216a8b97059f2ddadd39762466d5286c88eb9` — MainActivity 发布配置时，对 GPS 坐标模拟、GPS provider 状态模拟、Android ID 与时区模拟统一增加目标应用 `FLAG_DEBUGGABLE` 约束。
  - `ce3a91d11defd59e9cb0d26400caf47f426e94a6` — 新增 `scripts/tests/fx-dia-device-simulation-scope-regression.sh`。
- 修复原因：此前 UI 会对非 debuggable 目标禁用这些控件，但发布配置的序列化路径没有对历史残留 SharedPreferences 再次检查目标标志；应用升级后若移除 debuggable，旧配置仍可能被写入模块配置。现在发布端也执行同一边界检查，旧偏好保留但不再下发。
- 定向验证：新增脚本检查四个发布开关均受 `FLAG_DEBUGGABLE` 约束。该脚本已提交；本会话未在本地仓库运行它，也未运行 Android/Gradle 编译、安装或真机测试。
- 未改变配置键、GPS 坐标范围、目标应用偏好数据或 FX 1.0.0 版本号；未生成 APK/KernelSU ZIP，未触发整套 Actions。
- 已知限制：这是发布端范围保护，不代表 GPS/Fused Location 各 API overload 已在真机覆盖验证。
- 下一批立即任务：对照原 Dia Dialog 页面与现有通知 Hook 区分能力，核对原始 Dialog 专用处理是否存在实际执行器；若未迁移，按真实执行能力实现页面或明确标记未支持，禁止增加无后端开关。随后回到 Hook 自定义规则格式与执行适配器对照。


- 当前分支实时 HEAD（追加状态后待复核）：`ce3a91d11defd59e9cb0d26400caf47f426e94a6`。


## 2026-11-05 — Dia Activity Browser 分页重构与 Root 组件启停回滚修复

- 本批实际接续到的分支头：`82bbc762d172b553c6fc085e5207c7718b68cfff`（其前一 UI 重构为 `585303b7bb0b09b95a141c501133e36b11d9818d`）。
- 代码提交：
  - `585303b7bb0b09b95a141c501133e36b11d9818d` — Dia Activity Browser 改为完整原生双列表：应用列表每页 50 个、Activity 列表每页 80 个；两区独立搜索；保留目标包名、搜索文本、分页索引的 Activity 重建恢复。
  - `82bbc762d172b553c6fc085e5207c7718b68cfff` — 保持 selected package 与分页状态恢复，并显式处理 Activity 的 DISABLED / DISABLED_USER / DISABLED_UNTIL_USED 状态。
  - `b79e11734e3270cf58c53e18c637b6c4b6e26711` — 修复分页重构遗漏的 `submitWorker()` 编译阻断；恢复 Root 任务有界队列入口；组件取消/系统取消/队列拒绝/Root 异常/非零退出均安全回滚，程序性回滚不再触发第二次 Root 命令；加入应用整体 enabled 状态。
  - `7efb929ec5bbf5d997b22085b1fec34b21d2b438` — 清除目标选择时重复的 Activity 请求代次递增。
  - `9265e335569d45efb55373b01732747a0a1ce2e3` — 应用整体禁用优先于显式组件 enabled 标记；包被禁用时其 Activity 不显示为启用。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaActivityBrowserActivity.java`。
- 已核对的真实行为：
  - 应用清单和 Activity 声明/状态后台读取；分页搜索均在本地完成。
  - 启动器隐藏视图和全 Activity 视图使用同一 Activity Browser，分别按 MAIN/LAUNCHER intent 或完整 Activity 声明过滤。
  - 页面重建恢复当前目标、应用/Activity 搜索与分页；返回前台刷新已安装应用列表并尽量恢复目标选择。
  - 启用/禁用操作仍要求用户逐项确认，使用当前 Android user id，组件参数 shell quote；Root 任务只允许排队执行，队列拒绝回滚。
  - Dialog Back/点外部取消/显式取消都只恢复原 Switch，不会误发相反的 Root 命令；Root 执行抛错/返回非零/无结果也恢复原状态。只有命令执行后重新读 PackageManager，UI 才刷新为新组件状态。
  - PackageManager 的组件启用状态和父应用整体 enabled 状态都参与最终展示；父应用禁用时，即使组件有显式 ENABLED override，也不会显示为可实际启用。
- 定向静态复核：最新 ActivityBrowser、Manifest、MainActivity Dia 菜单路由、Gradle 重新读取；上述编译阻断、队列入口、队列拒绝回滚、监听器回滚保护、取消/系统取消、Root exception/nonzero、目标代次保护、父应用禁用边界、分页搜索、状态恢复、Manifest 注册和固定版本共 11 项检查全部通过。代码仍未运行 Java/Android 编译或 Gradle。
- 重要修复历史：分页重构 `585303b` 曾调用已删除的 `submitWorker()`，会导致编译失败；本批 `b79e117` 已恢复该方法，不再留下未定义引用。
- 同期已合入的 Dia GPS 发布范围修复（非本批重复改动）：`283216a8b97059f2ddadd39762466d5286c88eb9` 在 `publishConfig()` 再次核对 debuggable，只对 debuggable 目标发布 GPS 坐标、provider 状态、Android ID 和时区模拟；测试源码 `scripts/tests/fx-dia-device-simulation-scope-regression.sh`（提交 `ce3a91d11defd59e9cb0d26400caf47f426e94a6`）。其测试脚本本会话未运行，不能声称该脚本已执行。
- 固定 Gradle 版本仍为 `versionCode 10000` / `versionName 1.0.0`；没有触发整套 Actions，也没有生成最终 APK/KernelSU ZIP。
- 真机待验：Android 不同 OEM / 多用户 / 工作资料对 MATCH_DISABLED_COMPONENTS、pm enable/disable-user 和 PackageManager 组件缓存的表现；尤其禁用唯一 MAIN/LAUNCHER Activity 后需确认可从 FX 页面恢复。
- 下一批直接任务：① 对照 Dia 原始 Dialog 专用页面/脚本/规则，检查是否只有通知监听/阻断映射而缺少真正 Dialog 处理；② 不把通知 Hook 文案冒充 Dialog 能力，确认可迁移的真实事件/显示能力再实现页面；③ 随后回到 Frida 监听/代理页面的原生导航返回链。


## 2026-11-05 — Dia GPS 坐标页恢复、解析和 Hook 配置契约收紧

- 本批起始分支 HEAD：`e67a0bbc20631e54cf4204679b3aa2a986c90baf`；本状态更新前 HEAD：`10463057e4cc876d286237b2269b581db324de19`。
- 原始依据：从资料库 `/FX/Dia_23.11.apk` 还原并检查原始 Manifest、`mod_ex_anti_detection.xml`、`mod_ex_dialog.xml`、`mod_ex_notify_and_tips.xml`、`mod_ex_device_props.xml` 和相关 smali。确认 GPS 地图页使用高德经度/纬度顺序；FX 现有 per-app GPS 表单/Hook 已有实际发布和消费路径。
- 代码提交：
  - `8959ac1800cc73aa6bd65ca6a88053e6aaef31d1` — GPS Picker 保存/恢复输入框、状态和 WebView 导航状态；恢复失败时重新加载地图；校验经纬度范围。
  - `dd8d5a61901a53e172459613ef618a9186169a4b` — Picker 的坐标解析和返回路径统一使用纯 Java parser。
  - `c76db417da64830eaa18222ab7f088f4340dc175` — 新增 `FxDiaGpsCoordinateParser`，统一处理高德“经度,纬度”、中文逗号、空白分隔、有限数值和经纬度范围。
  - `a3ae21c06c60af81939ea59251e6f022af5a50e2` — 新增 GPS 坐标 parser JUnit 覆盖。
  - `80ead23c5e03ac230d0441c7f8cd9ddea02b97d0` — 配置解析器拒绝未开启模拟时残留的 `location_accuracy`，与经纬度字段一样 fail-closed。
  - `c51622d5821fc63f3bc37dafae70a8d183c5b41b`、`d181e2d33729aac59c01d3e86fac8d8afd9f3bad` — 修正 Hook 注释和 UI 说明：Fused 回调返回的 Location 对象只在目标读取 Location getter 时显示测试值；不声称拦截回调注册、系统 GNSS/provider 或路线。
  - `667dd09ac64ddcae5f1fef783a24d74c792101d3` — 新增 `UnifiedHookLocationConfigTest`，覆盖 per-app 坐标/精度解析、默认精度、provider 状态独立开关、序列化往返、缺字段/越界/NaN/Infinity、与 location access block 冲突及旧配置不启用模拟。
- 改动路径：`FxDiaGpsPickerActivity.java`、`FxDiaGpsCoordinateParser.java`、`FxDiaGpsCoordinateParserTest.java`、`UnifiedHookConfigParser.java`、`UnifiedHookLocationConfigTest.java`、`AdVisibilityHook.java`、`MainActivity.java`。
- 定向验证：
  - 从最新提交重新读取 Picker、parser、Hook、UI 和测试源码；检查状态 Bundle key、WebView restore fallback、GCJ-02 提示、两个坐标入口共用 parser、parser 数值/范围检查、配置 parser 的 accuracy 关联检查及 9 个 GPS config JUnit 用例声明。
  - 使用 JDK 临时 Host harness 编译与仓库当前 `FxDiaGpsCoordinateParser` 相同的纯 Java 实现，10 项运行断言通过（经纬度顺序、中文逗号、分离字段、空/缺项/多项、NaN/Infinity、纬度/经度范围）。这是临时 Host harness，不是仓库 Gradle/JUnit 任务。
  - 未运行 Android/Gradle 编译、JUnit runner、LSPosed 真机 Hook、Fused provider 真实回调或地图联网验收；设备级未验收。
- 固定版本 FX 1.0.0；没有修改系统定位权限、GNSS 或系统级定位；未打包最终 APK/KernelSU ZIP；未触发完整 Actions。
- 原始 Dialog 对照发现的明确缺口（下一批最高优先级）：
  - 原版 `mod_ex_dialog.xml` 有 `alert_close_ex`、`alert`、`alert_auto`、`disable_alert_mode`、`alert_enabled`、`alert_keyword`、`alert_id`、`toast` 等配置；原版通过 `ViewGroupHook`、`WindowManagerHook`、`KeyEventHook`、`ToastDisableHook` 执行按文本/ID 匹配的弹窗处理和 Toast 过滤。
  - 当前 FX 的 Dia 路由 `对话框与通知` 仅跳到 per-app `通知保护`，而 Hook 中的 `Dialog.show` observer 只用于广告 View 扫描，不等于原版 Dialog 自动处理；该功能尚未迁移。
  - 下一步必须实现独立 per-app Dialog/Toast 原生配置与真实 Hook 执行器，至少先支持显式文本/ID 规则、明确启停、限额/防误匹配、Toast 过滤和状态回执；不要把通知监听开关冒充 Dialog 功能。对原版按键触发模式先继续解析语义，再决定安全迁移方式。
- 并行工作线：Dialog 原版 smali/Preference XML 已定位；下一轮先实现独立纯 Java 匹配策略与配置 parser/serializer，再接 Hook 执行器和 MainActivity 页面路由。共享 `AdVisibilityHook.java` / `MainActivity.java` 修改前必须重新读取最新 blob。


## 2026-11-05 — Dia Dialog 入口纠正

- 提交：`10463057e4cc876d286237b2269b581db324de19`。
- 修复：Dia「对话框与通知」不再错误跳入逐应用「通知保护」设置，而是进入 FX 内置、按目标应用隔离的 Dia Frida 工具页，页面标题为「Dialog 观察与规则」。
- 功能边界：通知保护仍作为独立隐私 Hook 功能；Dialog 观察/弹窗规则不再被错误标记为通知功能已迁移。现有匹配弹窗移除脚本仍要求规则显式配置、目标应用 debuggable、用户手动注入；本次未启用自动移除，也未更改其规则模板。
- 核验：从最新分支读取 MainActivity，确认该路由指向 FxDiaFridaActivity 且标题正确；未运行 Android 编译、UI 自动化或真机测试。
- 未完成：Dia Dialog 页面尚未有独立规则表单/状态保存，仍依赖 Frida 页现有模板编辑器；后续继续补独立配置体验，并核验原始 Dialog 的全部语义。
- 下一步：继续 Hook 自定义规则语法和实际执行适配器核验，不把仅能编辑/保存的规则误报为已执行。

## 2026-11-05 — Dia 23.11 原始 Dialog 功能取证（实现前置审计）

- 核对分支 HEAD：`d05f7c34aa44751a80f39ce4e8ca86a803215815`；本节仅记录只读取证，不声称 Dialog 已迁移或已实现。
- 原始 APK 资料来源：GitHub Actions 历史 Artifact `fx-apk-source-intake`，Artifact ID `13184309776`，SHA-256 `5e8328d9c940d961fb49073ac9be8b2d2aac793148bafff700eed80a97851a3a`。本次实际读取 `res/xml/mod_ex_dialog.xml` 与 `smali/com/mhook/dialog/task/hook/WindowManagerHook.smali`。
- 原始页面字段：
  - `alert_close_ex`：扩展对话框关闭开关（需继续追踪其调用点，暂不推断用途）。
  - `alert`：Dialog 功能总开关。
  - `alert_auto`：自动模式开关，默认 true。
  - `disable_alert_mode`：禁用模式选项。
  - `alert_enabled`：条件选择列表。
  - `alert_keyword`：匹配关键字。
  - `alert_id`：匹配 View ID。
  - `toast`：拦截提示。
- 原始执行器观察：
  - Xposed `WindowManagerHook` 在 `WindowManager.addView` 前置拦截。
  - 先检查 `ActivityKey` 的作用域，再通过 `ViewHelper` 对传入 View 做 ID/文本匹配；匹配后将 addView 结果设为 null 以阻止挂载。
  - 当关键字和 ID 均为空时，原版存在按 WindowManager.LayoutParams 全屏宽高过滤的特殊路径；自动布局监听器也参与后续检查。
  - 原始实现依赖应用级 `XSharedPreferences`（模块包名 `dialog.box`）读取配置。
- 当前 FX 对照：
  - Dia 菜单“对话框与通知”现已路由到 Frida 观察/规则页面；这不是原始 Dialog 原生设置页。
  - FX 已有的 `Dialog.show()` observer 只在广告目标下触发广告 View 扫描，不会阻止对话框显示。
  - NotificationListener 保护是独立隐私能力，不能充当 Dialog 功能。
  - 现有 Frida ViewGroup 删除模板属于另一条执行路线，不能冒充 WindowManager.addView 的原生 Hook。
- P0 安全约束：不得照搬原版“空匹配条件 + 全屏尺寸”全局拦截；不得在未指定目标包时全局 Hook/阻止系统窗口；不得默认启用；必须按单个目标应用配置、显式启用、关键字/ID 至少一项有效匹配，并在异常/配置缺失时 fail-open。拦截提示必须限频且不能在 Hook 回调里做阻塞 I/O。
- 本批未提交代码：当前 UnifiedHookConfigParser.Target 与 Serializer 尚无独立 Dialog 规则字段；MainActivity 的现有页面配置发布接口与 Hook 配置模型需要同步扩展。直接只加 UI 将造成配置无法到达执行层，因此暂不提交空壳。
- 下一批具体实现顺序：
  1. 扩展统一配置模型：目标级 `dialog_block_enabled`、模式、条件、关键词列表、资源 ID 列表、提示开关；限制字段长度/条数并在 Parser/Serializer 做往返校验。
  2. 新增独立 `WindowManager.addView` Hook 安装器：仅在已启用且明确目标包中安装；匹配 View 的文本/资源 ID；异常 fail-open；排除 FX 自身、系统 UI 与受保护包；覆盖 addView 重载并避免重复安装。
  3. 新增 Dia 原生 Dialog 页面：按已选应用读写目标级配置；支持规则增删改、自动/手动条件、拦截提示和运行状态；不得复用 Notification 开关。
  4. 加入 Parser/Serializer、匹配器纯 JVM 单测及 Shell 回归；先运行定向测试，再进行 Android 编译。
- 失败路线记录：把“对话框与通知”直接路由到 Frida Dialog 页面无法覆盖原始 WindowManager Hook；仅靠现有 Dialog.show 广告扫描器也不具备拦截语义。下一批必须新增独立执行链，不再尝试重命名现有功能。


## 2026-11-05 — Dia Dialog 原生规则链核对与编译阻断清理

- 本批起始 HEAD：`a1edec7e7b6676f6fefad23691bf661638eadb9a`；并行工作线随后推进到 `fa56c2c8144a80628239a175da083734196335a2`，本批基于当时最新 blob 做并发安全更新。
- 本批代码提交：
  - `157226b0b7f085d8ff757add1669fd7753675a98` — 删除 `AdVisibilityHook.java` 中重复的 `FxDiaDialogMatchPolicy` 导入（复核最终只剩一条）。
  - `8a98d7dad079407c2aa2b44ad0f48e2c0e701855` — 新增 `scripts/tests/fx-dia-dialog-native-regression.sh`，覆盖 Dialog UI/配置/运行时连接、单次导入、匹配预算、fail-open、提示限频及匹配器测试契约。
- 当前已存在的 Dialog 实际链路（不是本批新造）：逐应用原生 Dialog 表单 -> SharedPreferences 持久化 -> per-app 配置发布 -> Parser/Serializer 校验 -> LSPosed `Dialog.show()` Hook -> 明确文本/资源 ID 匹配 -> 匹配时阻止原始 show 调用；异常时 fail-open；反馈 Toast 按应用 3 秒限频；日志不记录对话框正文。
- 已确认限制：当前仅覆盖 `Dialog.show()` 普通 Dialog 路径，不等于通用 `WindowManager.addView` 拦截；全屏窗口跳过；原版按键触发/自动布局监测、独立 Toast 过滤尚未迁移。不要宣称覆盖所有 Window/Toast。
- 定向静态核对：读取最新 `AdVisibilityHook.java`，确认重复 import 修复后只剩一条；读取 Dialog UI、配置 parser/serializer、匹配策略及 JUnit 测试，确认上述接线存在。新增回归脚本已提交，但本会话未在仓库工作树运行该脚本，也未运行 Gradle/JUnit/Android 编译或 LSPosed 真机测试。
- 固定版本仍为 FX 1.0.0；未打包最终 APK/KernelSU ZIP。
- 下一步具体任务：① 运行 `fx-dia-dialog-native-regression.sh` 和 Dialog/Parser JUnit；② 继续从原始 Dia smali 追踪 `ToastDisableHook`、`KeyEventHook` 和自动布局监听语义，分别实现安全的逐应用 Toast 过滤与按键模式（不可混用 Dialog 匹配开关）；③ 回到 Frida 监听/代理原生导航返回链。



## 2026-11-05 — Dialog 回归脚本收敛与最新分支续接

- 本节更新前实时 HEAD：`b1ff141799f41728c878f43353b1908c39fe7a0d`；最近提交：`b1ff141799f41728c878f43353b1908c39fe7a0d`（修正 Dialog 回归断言）。
- 最近连续提交：
  - `157226b0b7f085d8ff757add1669fd7753675a98` — 修复 `AdVisibilityHook.java` 重复导入。
  - `8a98d7dad079407c2aa2b44ad0f48e2c0e701855` — 新增 Dialog 原生链静态回归脚本。
  - `473b32c8a928dceb82590dc2aac3ad1dad4e320f` — 写入续接记录。
  - `19875fbbd7dee94bd580321aaab0581cb4be1ce7`、`b1ff141799f41728c878f43353b1908c39fe7a0d` — 校正并收紧静态回归断言。
- 最新源码复核：`AdVisibilityHook.java` 中 `FxDiaDialogMatchPolicy` import 计数为 1；回归脚本已包含匹配日志不记录正文、Hook 检查异常 fail-open 等契约。
- 本批验证结果：只完成 GitHub 最新 blob 静态检查；回归脚本尚未在检出工作树执行，Gradle/JUnit、Android 编译、LSPosed 设备行为均未执行。不得写成“测试通过”。
- 下一步优先：① 用仓库 CI/可执行工作树运行 `sh scripts/tests/fx-dia-dialog-native-regression.sh`；② 追踪原始 `ToastDisableHook` 与 `KeyEventHook`，拆成独立、逐应用、默认关闭的能力；③ 再补原始自动布局监听，最后回到 Frida 页面返回链。
- 明确禁止：不得把现有 `Dialog.show()` Hook 说成完整 WindowManager 覆盖；不得默认阻止系统/FX 自身窗口；不得将通知监听设置作为 Dialog/Toast 的替代；固定 FX 1.0.0，不打包最终 APK/KernelSU ZIP。

## 2026-11-05 — Dia Dialog 双入口拦截、逐应用原生配置与定向回归

- 本节更新前实时分支 HEAD：`78cdea7fba9f3a5c5c960b25df524683668ec558`；分支仍为 `fx-v1.0.0-unified-hook-integration`，固定版本 FX 1.0.0。
- 本节更正并取代前一节“仅覆盖 `Dialog.show()`”的旧边界描述：当前代码同时接入 `Dialog.show()` 前置检查和可用的 `WindowManagerImpl.addView()` 前置检查；设备级覆盖仍待验收，不能宣称涵盖所有 OEM / Android 版本的 Window 实现。
- 原生配置链：
  - Dia「对话框与通知」入口进入逐应用 `Dialog处理` 列表；与 NotificationListener 通知保护完全分离。
  - 目标详情页有独立启停、文本关键字、资源 ID、拦截提示开关；表单草稿支持 Activity 重建恢复。
  - 保存时由 `FxDiaDialogMatchPolicy.parseTerms` 规范化；空规则拒绝启用；非 debuggable 目标禁用编辑/发布；`publishConfig()` 再次核验目标标志位。
  - 配置字段为 `dialog_match`、`dialog_text_terms_b64`、`dialog_id_terms_b64`、`dialog_notify`；Parser / Serializer 有解析、校验及逐应用往返。
- 当前执行器：
  - API-101 对包名做二次 debuggable / 受保护包检查，要求规则启用且至少一条显式文本或 ID。
  - `Dialog.show()` 在原始 show 前检查普通 Dialog 的 View 树；匹配时取消 show，不匹配则继续原调用。
  - 反射发现 `android.view.WindowManagerImpl` 中接收 View 与 LayoutParams 的可用 `addView` 重载，在挂载前再次做有界匹配；命中后阻止 addView。
  - 文本规则是不区分大小写的字面包含（不是正则）；资源 ID 支持完整名称、entry name、十进制和十六进制精确匹配。
  - 匹配检查限制 512 节点 / 深度 16；全屏宽高均为 MATCH_PARENT 的窗口跳过；反射、树访问及 UI 检查异常均 fail-open；提示 Toast 按包名 3 秒限频；日志只记包名与匹配类型，不记录 Dialog 正文。
- 规则上限说明已纠正：文本与资源 ID 两类各最多 32 条、单条最多 96 字符；两个输入框分别最多 1 KiB。
- 本批相关提交（连续历史，含并行提交）：
  - `72bbd0e8f10d0f60a5fb46cfebda5742ceb5a522` — 逐应用 Dialog 原生表单及配置发布。
  - `a9fe52921a89d3cfdbd2553c6efd1892592c7598`、`8bdefeb462b0c9e3dcbae06ed3584baed4971f49` — `dialog_notify` Parser / Serializer 接线。
  - `8e192b83529b956220194fab08d611e9bdb4abb2`、`a1edec7e7b6676f6fefad23691bf661638eadb9a` — 逐应用运行时拦截、WindowManager addView 路径、全屏跳过和幂等安装保护。
  - `9ea5c93b72fa72cd9014838da5ac0f79046aa0a8`、`1eb3ac2100c0ef39e8e630c912b32a8a0b4408dd` — 表单草稿恢复、按应用查看匹配事件。
  - `4b9898d1c09ab1149027d2fedf341d7b3424230e`、`e51b89d473a116b1838127e11577d20aad00acd8` — 修正规则上限说明及运行状态日志标识。
  - `c2ee7c3cd394e98348783f338c57daa76ce74f7d`、`7531241a462ac6463862c93f54c733c56ebc849f` — Parser 校验与 Serializer 往返测试。
  - `0343a8744c86f3673f96b078d18f7a7466dea9b3`、`78cdea7fba9f3a5c5c960b25df524683668ec558` — 修正 Dialog 与四个既有 GPS 配置 Parser 用例的换行转义，确保构造真实多行配置。
  - `65c16bf476427c3eda1afa147d0e73cc726ae26f`、`8a98d7dad079407caa2b44ad0f48e2c0e701855`、`b1ba02536b9bec3e8c0815c3338f4f0b11542392`、`38e719830b86bfb4fe8b49688e145f885727076d` — 独立 JDK Host 测试、原生链静态回归、执行入口及断言修正。
- 改动路径：`MainActivity.java`、`AdVisibilityHook.java`、`UnifiedHookConfigParser.java`、`UnifiedHookConfigSerializer.java`、`FxDiaDialogMatchPolicy.java`、相应 Parser / Serializer / Policy 测试，以及 `scripts/tests/FxDiaDialogMatchPolicyHostTest.java`、`scripts/tests/fx-dia-dialog-native-regression.sh`。
- 验证：
  - 当前分支文件级静态契约核对 18 项全部通过，覆盖 UI 路由、逐应用/debuggable 发布、Parser/Serializer、WindowManager/Dialog 双入口、全屏排除、fail-open、提示限频及测试覆盖。
  - 从当前分支读取的纯 Java Policy 与 Host 测试源码在临时 JDK 目录执行 `javac -Xlint:all -Werror`，19 项 Host 断言通过（换行、去重、字面文本/资源 ID 匹配、空规则、UTF-8/条数/长度限制、不可变列表）。
  - **尚未**在完整仓库工作树运行 `sh scripts/tests/fx-dia-dialog-native-regression.sh`；未运行 Gradle / JUnit runner、Android 编译、模拟器或 LSPosed 真机窗口拦截。Host 测试不替代这些验收。
- 原始 Dialog 尚未完整迁移：`alert_auto`、`disable_alert_mode`、`alert_enabled` 条件 / 按键模式、`alert_close_ex` 扩展关闭行为、独立 `ToastDisableHook` 过滤、动态布局监听均未完成。当前 `dialog_notify` 只是在拦截成功后发限频提示，不能替代 Toast 过滤。
- 本批未触发整套 Actions，未生成 APK / KernelSU ZIP，未更改六 Tab 顺序和 FX 1.0.0 版本号。
- 失败路线：Git Data 写入接口平台错误后采用 Contents API 顺序提交；遇到并行分支推进时重新读取 HEAD/blob SHA，未强推或覆盖。回归脚本出现过错误字段名，已按当前 Hook 字段修正；新增 Dialog 及四个 GPS Parser 用例的字面 `\\n` 分隔符已修复。
- 下一批直接任务：
  1. 追踪 Dia 原版 `ToastDisableHook` 的 Hook 点、匹配字段、作用域和绕过条件，新增独立默认关闭、逐应用 Toast 过滤设置与执行器，不复用 Dialog 提示开关。
  2. 追踪 `KeyEventHook` 与 `alert_auto` / `disable_alert_mode` 的调用链，先复原原始模式语义，再做显式启用的安全迁移。
  3. 核对动态布局监听及 Dialog 规则的设备覆盖；随后回到 Frida 监听 / 代理页面原生导航返回链。

## 2026-11-05 — 游龙广告应用白名单页面状态恢复（UI 优先批次）

- 本批代码提交前 HEAD：4fed76d48d0f1c6b1b9a4935085d43dada1566e4。
- 本批 UI 代码提交：41f601c53b9d1b85d80a3ff8df766ff2639e8991（fix(ui): restore Yulong app whitelist list state）。
- 改动路径：adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAppWhitelistActivity.java。
- 完成：应用白名单 Activity 保存并恢复分页页码、搜索词与 ScrollView 滚动位置；异步加载应用清单完成后保留恢复页码并恢复滚动；用户主动修改搜索词时重置到第一页及顶部。白名单实际选择仍从 Root 脚本读取，开关写入仍走既有脚本链，本批未更改过滤语义或配置格式。
- 同步核对：六 Tab 原生外壳 FxNativeAppShell.kt 已用于 Dashboard native shell；MainActivity.base() 也调用 mountNativeShell(root)，Hook、设置及迁移应用主/分类页复用同一六 Tab 外壳。因此未对底栏重复造轮子。
- 定向静态核验：7 项源码断言通过，确认状态键、保存字段、重建时读回、异步加载不覆盖恢复页码、内容重绘后恢复滚动、搜索变更重置页码/位置，以及 ScrollView 被提升为 Activity 字段。
- 验证边界：未运行 Gradle / Android 编译、UI 自动化或真机旋转/进程重建；以上仅为提交源码静态核验，不是设备验收。
- 并行工作线新进展：其后分支新增 1725569d71e01afb7daacdf591a96eb59cc50328（Parser 增加 per-app Toast 规则字段和约束）与 f93aafda36277583e727c244b1ab7851fe40d4ad（Serializer 写入 Toast 规则）。仅确认 diff 触及 UnifiedHookConfigParser / Serializer；本轮尚未验证相应 UI、Hook 执行器或单测，不能视为 Toast 功能完成。
- 未完成事项：三套应用仍有部分四级页面路由到通用页或明确 pending 页；Dia 与游龙安全护盾深层页面映射/返回链仍需逐组对照原版。应用白名单页仍需 Android 生命周期实测。
- 排除路线：曾怀疑 Hook/设置页面底栏会消失；复核确认 base() 已挂载同一六 Tab Compose 外壳，故不做重复修补。
- 下一批具体任务：继续补齐游龙广告“应用管理”页面组的原生交互与恢复（白名单页已处理，Firewall 页已有分页/查询/滚动恢复；核查应用统计页）；并行工作线应把 Toast Parser/Serializer 接到独立默认关闭、逐应用 UI 与执行器，不能复用 Dialog 提示开关。

## 2026-11-05 — 游龙广告应用统计分页与页面恢复

- 本批代码提交前 HEAD：bb843fb3ec14d054b636c3b53fda697d14d58e06。
- 本批代码提交：752497bc7d8e07e7d76272671c3c855e7d1e93de（feat(ui): paginate Yulong per-app traffic statistics）。
- 改动路径：adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAppStatsActivity.java。
- 完成：应用统计列表按每页 40 项创建 View；增加加载更多入口；保存并恢复搜索词、当前页码和滚动位置；数据刷新完成后恢复滚动；搜索修改时重置到第一页和顶部。统计数据继续来自 TrafficStats 按 UID 的累计收发字节，未更改统计口径。
- 定向静态核验：7 项源码断言通过，覆盖分页上限、加载更多、搜索重置、状态保存/恢复、异步加载后恢复、翻页后保持滚动，以及 TrafficStats/唯一 UID 汇总逻辑未被替换。
- 验证边界：未运行 Gradle / Android 编译、自动化 UI 或真机测试；分页交互及屏幕旋转仍需 Android 生命周期验收。
- 当前实时分支 HEAD（本次写入状态文件前读取）：8946cb888d49b9bd7320445675c2f2c4c16f83a5。
- 最近提交：8946cb888d49b9bd7320445675c2f2c4c16f83a5 feat(privacy): add native per-app Toast filtering page；752497bc7d8e07e7d76272671c3c855e7d1e93de feat(ui): paginate Yulong per-app traffic statistics；bb843fb3ec14d054b636c3b53fda697d14d58e06 docs(fx): record Yulong whitelist UI restoration；f93aafda36277583e727c244b1ab7851fe40d4ad feat(privacy): serialize per-app Toast filter rules；1725569d71e01afb7daacdf591a96eb59cc50328 feat(privacy): parse per-app Toast filtering rules；41f601c53b9d1b85d80a3ff8df766ff2639e8991 fix(ui): restore Yulong app whitelist list state；4fed76d48d0f1c6b1b9a4935085d43dada1566e4 docs(fx): record Dialog addView runtime and regression status；78cdea7fba9f3a5c5c960b25df524683668ec558 fix(test): use real newlines in GPS config parser fixtures。
- 未完成事项：游龙广告应用管理组的应用统计和白名单页已补分页/状态恢复；Firewall 页面已有相近的分页、搜索和滚动恢复，但其用户应用/系统应用/按应用设置入口需进一步验证筛选一致性与原版导航。Dia / 游龙安全护盾深层页面仍有 pending 入口，尚未逐项完成原版对照。
- 下一批具体任务：核对 Firewall 页面按“用户应用 / 系统应用 / 按应用设置”路由是否实际过滤正确、返回栈是否完整；随后转向 Dia 原生页面，不重复改已经具备恢复链的白名单和统计页面。

## 2026-11-05 — Toast 逐应用原生配置页接入（并行批次核验）

- 本节更新前实时分支 HEAD：e66a043003bf2dd0ff21139c029b3275e8ae87c2。
- 对应并行代码提交：1725569d71e01afb7daacdf591a96eb59cc50328（Parser）、f93aafda36277583e727c244b1ab7851fe40d4ad（Serializer）、8946cb888d49b9bd7320445675c2f2c4c16f83a5（原生 UI 和 MainActivity 路由）。
- 已核验的 UI：隐私页有独立“Toast 文本过滤”入口；Dia「对话框与通知」迁移目录也有 Toast 过滤入口；目标页逐应用显示开关、关键词多行编辑器、规则限制与草稿持久化，保存后发布独立 toast_filter / toast_text_terms_b64 配置字段。系统应用页面只读，避免默认影响系统提示。
- 已核验的配置链：UnifiedHookConfigParser 解析 toast_filter 和 toast_text_terms_b64；UnifiedHookConfigSerializer 仅在启用且规则非空时写出配置，关闭但携带规则会拒绝序列化。
- 运行时边界：本节只核验上述 UI / 发布 / Parser / Serializer diff。当前读取的 AdVisibilityHook.java 仍仅有 Dialog 抑制提示和 Dialog 规则匹配路径，没有发现读取 toastFilterEnabled / toastTextTerms 并 Hook Toast.show() 的执行器证据。**Toast 过滤目前不得标为运行时完成**；用户可见设置和持久化不能代替目标进程内实际拦截。
- 测试边界：本次未读取到对应 Toast Parser / Serializer 回归用例执行结果；未运行 Gradle、Hook 运行时或 Android 设备测试。
- 下一步具体任务：实现独立 Toast 执行器，优先 Hook Toast.show() 并对可安全读取的 Toast View 文本做有界、不区分大小写字面匹配；保持默认关闭、逐应用作用域、系统/FX 自身 fail-open、异常 fail-open，不记录 Toast 正文；再补 Parser/Serializer 和执行器定向测试。不得复用 Dialog 的 dialogNotify。

## 2026-11-05 — Toast 逐应用过滤运行时、系统应用保护与回归断言修复

- 本节记录前实时分支 HEAD：98a5f0da207276361453589cbfa162703de9fbe8。
- 本节更正上一节“尚未发现 Toast Hook 执行器”的结论：该结论只适用于读取时点，随后提交 7e2247fc7127739b24bcee4cbb62264e3b195632 已将 Toast 目标进程 Hook 接入；不能继续把 Toast 记为只有 UI/Parser/Serializer。
- Toast 当前实现链：
  - MainActivity 隐私页和 Dia 迁移页均有独立 Toast 入口；逐应用开关与多行关键词输入独立于 Dialog 匹配、Dialog 命中提示和 NotificationListener。
  - UI 保存逐应用草稿与发布配置；Parser 消费 toast_filter / toast_text_terms_b64，Serializer 只在显式启用且规则非空时写入。
  - AdVisibilityHook 在启用目标进程安装独立 Toast Hook：捕获 Toast.makeText / setText / setView 元数据，在 Toast.show 前按逐应用配置匹配；可读取 View 树受 512 节点 / 16 层限制，文本匹配复用有界字面匹配策略；捕获文本按 MAX_TEXT_CHARS 截断；异常与不可读取内容 fail-open；日志不写入 Toast 正文或规则值。
  - Toast 元数据按 Toast 实例弱引用保存；自定义 View 替换会重建 payload，不沿用旧 TextView 文本。元数据改进提交：f6a692a12c454c352dbf983bf0503ce58c179abb、98a5f0da207276361453589cbfa162703de9fbe8。
- 本轮额外安全收紧：
  - Toast UI 目标选择和 publishConfig 对 FLAG_SYSTEM 与 FLAG_UPDATED_SYSTEM_APP 都不允许启用：3582c15897a7bce470f069f2f0b1e39351caaf69。
  - LSPosed onPackageReady 再次检查系统/更新系统应用标志；即使 Remote Files 含陈旧或手工构造配置也不会为系统应用安装 Toast 过滤：eb88555bc6e926c2f8b3d90ddaf0202dcb14a2e9。
- Toast 实现与测试提交：Parser 5fb50f236fbec88cea990c04610c053a7399703e；Serializer ca63fb1f1f11dd81d3bc6fed1d8ef59cd2308063；UI 8946cb888d49b9bd7320445675c2f2c4c16f83a5；LSPosed 执行器 7e2247fc7127739b24bcee4cbb62264e3b195632；静态接线断言 28e5ead494b2ed65b5b3db1b56c7ffb1f3a7185a。
- 合并回归脚本曾包含损坏的 Parser 断言缩进/循环；已在 c77faa04aa84690c06eac9c274927c45da75b07b 修正为独立 Dialog 与 Toast 两组循环，并增加 FLAG_UPDATED_SYSTEM_APP 保护断言。当前脚本路径：scripts/tests/fx-dia-dialog-native-regression.sh。
- 静态核验：最新读取确认 UI、发布器、运行时和回归脚本均包含 FLAG_UPDATED_SYSTEM_APP 防护；Parser / Serializer 测试源码包含 Toast 默认关闭、显式规则、无规则拒绝、关闭却带规则拒绝、往返序列化用例；运行时源码具有 Toast.show / makeText / setText / setView、逐应用配置、节点/深度限制、fail-open 和不记录正文路径。
- 验证边界：本轮未实际运行完整脚本、Gradle/JUnit、Android 构建、模拟器或 LSPosed 真机测试。GitHub 对静态回归脚本修复提交 c77faa04aa84690c06eac9c274927c45da75b07b 未返回可核实的 PR 关联工作流记录。以上属于源码静态检查，不得表述为测试通过或设备验收。
- 本轮 UI 批次代码：白名单页面状态恢复 41f601c53b9d1b85d80a3ff8df766ff2639e8991；应用统计每页 40 项分页和状态恢复 752497bc7d8e07e7d76272671c3c855e7d1e93de。两页均未更改其 Root/TrafficStats 业务语义；仍需 Android 生命周期和真实设备交互验收。
- 本轮最新提交（本节写入前）：98a5f0da207276361453589cbfa162703de9fbe8。当前分支固定 FX 1.0.0，未生成最终 APK 或 KernelSU ZIP。
- 尚未完成：Toast Hook 在不同 Android/OEM Toast 实现下的覆盖率和权限行为仍需设备实测；Firewall 用户/系统应用分类、原版页面链仍待逐项验收；Dia 原版 Toast/KeyEvent/Dialog 动态布局的其他行为及游龙安全护盾深层页面仍未全部迁移。
- 下一批具体任务：对照 Toast 运行时边界写独立可执行的定向回归（避免只靠字符串 grep）；之后继续完成游龙 Firewall 页面组或 Dia 原生深层页面，每批覆盖真实交互和返回链；不得把当前静态核验当作真机验收。

## 2026-11-05 — 游龙广告 Firewall 用户/系统应用筛选反向 Bug 修复

- 本节记录前实时分支 HEAD：`41c78b4ee2ca0d65ac4def1de16d48890678a2b3`；固定分支 `fx-v1.0.0-unified-hook-integration`、版本 FX 1.0.0。
- 核对原生路由后发现真实筛选逻辑反了：原实现 `appFilterMode == 1 ? systemApp : appFilterMode == 2 && !systemApp` 会让“用户应用”显示系统应用、让“系统应用”显示用户应用。不是单纯文案问题。
- 已修复：`FxYulongFirewallActivity.loadAppsAsync()` 通过纯 Java `FxYulongFirewallAppFilterPolicy.includes(mode, flags)` 判断类别；ALL 显示两类，USER 排除 `FLAG_SYSTEM` 与 `FLAG_UPDATED_SYSTEM_APP`，SYSTEM 包含这两种系统标志，未知 mode fail-closed。
- 新增 JUnit 用例 `FxYulongFirewallAppFilterPolicyTest` 与独立 JDK Host 用例 `scripts/tests/FxYulongFirewallAppFilterPolicyHostTest.java`。
- 本批提交：
  - `74d02c87f1c1f0e8ba8cc192a6ec2566e44b2533` — 修复 Firewall 用户/系统筛选方向。
  - `bcf3635e34aff34df301d0d14e84b30fb2decf01` — 抽离纯 Java 应用分类策略。
  - `7fc23618b9bc5508a9df856761737939641a4248` — 新增分类 JUnit 测试。
  - `41c78b4ee2ca0d65ac4def1de16d48890678a2b3` — 新增无 Android SDK / JUnit 依赖的 Host 测试。
- 验证：对策略与 Host 测试执行 `javac -Xlint:all -Werror`，再运行 Java 主类，11 项断言通过，覆盖 ALL/USER/SYSTEM、FLAG_SYSTEM、FLAG_UPDATED_SYSTEM_APP、双标志组合和未知 mode。尚未运行 Gradle/JUnit、Android 编译、Firewall Activity UI 或设备验收。
- 改动路径：
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongFirewallActivity.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongFirewallAppFilterPolicy.java`
  - `adhook/app/src/test/java/de/privacyguard/adhook/imported/ad/FxYulongFirewallAppFilterPolicyTest.java`
  - `scripts/tests/FxYulongFirewallAppFilterPolicyHostTest.java`
- Dia 按键控制入口已核对：当前 `FxDiaFridaActivity` 的 `key` 模板只监听 `Activity.dispatchKeyEvent` 并记录 keyCode/action 后调用原方法，属于 Frida 观察模板，不是原版 `KeyEventHook` / `alert_auto` 拦截语义；不能据此冒充按键拦截迁移完成。下一步须定位原版 KeyEventHook 的实际源码或可核验字节码，再按真实条件迁移。
- Toast 逐应用过滤已有后续并行提交与独立状态记录；当前分支 HEAD 已包括 Toast.show Hook、默认关闭逐应用配置、系统/更新系统应用保护及静态回归检查。仍未完成 Android/OEM Toast 真机覆盖验收。
- 下一批具体任务：
  1. 检查 Firewall 用户/系统/按应用设置三条导航入口、返回栈和刷新后的筛选模式；避免重复重写已有分页/搜索/滚动恢复。
  2. 为 Firewall 分类策略补入现有定向回归入口，并检查 UID/包名过滤与系统应用标志是否在数据加载和规则保存两侧一致。
  3. 继续 Dia 23.11 原生页面，定位 KeyEventHook 原始实现证据；若仓库缺失原始实现，先从已导入 APK/资源文件中检索，不能猜测 alert_auto 行为。
- 本批未触发整套 Actions，未生成 APK / KernelSU ZIP，未更改六 Tab 顺序或 FX 1.0.0 版本号。

## 2026-11-05 — Firewall 筛选回归入口与导航复核

- 本节开始时实时 HEAD：`17c9609edac22c8cbc97d30f3c270733aebee5d8`。
- 复核三条主导航：`用户应用`、`系统应用`、`按应用设置` 均通过 `suite_page` 传入 `FxYulongFirewallActivity`；`应用网络拦截` 走默认页。Activity 顶部返回调用 `finish()`，回到发起它的 MainActivity；Activity 重建继续使用 Intent 中的 suite_page，搜索/页码/滚动位置按现有 Bundle 状态恢复。
- 已新增独立定向入口 `scripts/tests/fx-yulong-firewall-filter-regression.sh`（提交 `17c9609edac22c8cbc97d30f3c270733aebee5d8`），同时检查导航、状态恢复与策略接线，并编译运行 Firewall Host 测试；不触发整套 Actions。
- 当前已执行 Host 测试 11/11 通过。脚本本身刚提交，尚未在完整仓库工作树执行；其静态导航断言仍需实际跑脚本确认。
- Firewall 数据刷新仍按当前 `appFilterMode` 过滤，不会把用户应用页和系统应用页混在一起；包变化时重新读取 Root 防火墙规则，再异步刷新应用列表。没有改动 Root 规则格式、UID 流量统计口径、每应用计划任务或 VPN 路由。
- 相关提交仍以本节前一节列出的 74d02c8 / bcf3635 / 7fc2361 / 41c78b4 为准；本节新增脚本提交如上。未生成 APK/ZIP。
- 下一批：检查 `persistRule(packageName, uid, ...)` 的 UID 与包名绑定是否在写入脚本和 Root 端再次核验，避免应用卸载/重装后旧 UID 规则误套到新包；再检查列表刷新失败时是否保留旧列表且不错误恢复总开关。然后继续 Dia 原生页面原始 KeyEventHook 溯源，不以 Frida 观察模板替代。

## 2026-11-05 — Firewall Root 侧 UID 重新解析复核 / Dia KeyEvent 原始实现溯源

- 本节检查时实时 HEAD：`5d5ec6c098201782aa0c6e264214fba5354d087a`（检查期间分支有并行提交，以上一节记录的 Firewall 筛选修复为基础继续核验）。
- 已检查 `scripts/yulong-app-firewall.sh` 的 `apply_rules()`：每次应用规则前重新执行 `cmd package list packages -U` 取得当前包 UID 快照，再由 `resolve_uid(packageName, snapshot)` 按包名解析当前 UID；卸载包会从活动规则中排除，无法解析 UID 时保留旧防火墙并报错。构建 iptables/ip6tables 规则使用解析出的当前 UID，而非直接信任 UI 传来的旧 UID。因此当前脚本已有防止卸载/重装后沿用旧 UID 的 Root 侧保护；UI 传入 UID 不是最终生效依据。
- 防火墙更新采用双链 staging：先构建 IPv4/IPv6 新链、再安装两侧 OUTPUT 跳转、最后切换活动标记并清理旧链；中间步骤失败会清理新链并保留旧链。刷新 Root 列表失败时 UI 保留上次应用列表，并按 appsLoaded 状态恢复总开关可用性；不将失败响应当作空规则覆盖。
- Dia 原始按键实现溯源：在当前仓库代码搜索 `KeyEventHook alert_auto`、`disable_alert_mode alert_enabled`、`ToastDisableHook`、`alert_close_ex` 未找到可核验的原始实现文件。现有 `FxDiaFridaActivity` 的 `key` 模板只是 Frida 的 `Activity.dispatchKeyEvent` 观察器，日志后继续调用原方法，不能等同于拦截 Hook。没有 APK / 字节码证据前不实现猜测版 alert_auto。
- 下一批：优先从已导入 Dia APK / 资源 / DEX 中找到原始 KeyEventHook、ToastDisableHook 和 alert 规则实现证据；若仓库当前没有对应二进制文件，标记为外部源缺失并继续做其它可完成的 Dia 原生页面，不重复对 KeyEvent 语义猜测。Firewall 这批筛选方向 Bug 与 11 项 Host 断言已完成；真实设备仍需验收用户/系统应用分类、Root 规则切换及 IPv4/IPv6 流量行为。

## 2026-11-05 — Firewall 包名/UID 写入校验与过期应用列表只读保护

- 本节更新前实时 HEAD：`59565158641e29885e1dbb5cd5a48976a269a225`；分支 `fx-v1.0.0-unified-hook-integration`，版本固定 FX 1.0.0。
- 根因：防火墙最终应用规则时原本会通过 `cmd package list packages -U` 按包名重新解析 UID，因此卸载后旧 UID 不会直接继续进入 iptables；但 UI 的 `rule` / `set` 写入入口仍接受调用方传来的任意正整数 UID。若列表快照过期，旧 UID 仍可能覆盖该包名的持久化行，造成错误状态和不可预期的重装继承行为。
- 已修复 Root 写入边界：
  - 新增 `validate_package_uid()`，写入前重新读取 PackageManager UID 快照。
  - 包已卸载、UID 快照读取失败/为空、包名当前 UID 与调用 UID 不一致时，拒绝写入并返回明确错误；不改配置、不触发规则重应用。
  - `set` 与 `rule` 两个入口都调用校验。实际 iptables 规则仍在 apply 阶段再次按当前包名解析 UID，保留重装后使用新 UID 的既有语义。
- 已修复 Activity 过期快照行为：
  - 新增 `inventoryReady` 状态；只有 Root 配置列表读取和 PackageManager 应用列表读取均成功后才设为 true。
  - 刷新开始即进入只读状态；Root 列表刷新失败不再使用 `appsLoaded` 重新启用总开关。
  - 刷新失败仍保留上次应用列表供查看，但总开关、逐应用启停和 Wi-Fi/移动数据/计划编辑均禁用；规则保存入口也有二次 UI 状态保护。
  - 成功完成两侧刷新后恢复操作能力。旧列表不清空、不用空列表覆盖，避免刷新故障造成页面数据丢失。
- 提交：
  - `e52a8ad1ed1cbec55b72cb68614905be1d737550` — Root rule 写入前校验当前 package UID。
  - `349884740d4fe7debd2bf00bfa2e36c17599555f` — 增加 UID 不匹配、应用已卸载、PackageManager 快照失败的回归场景。
  - `4b4236036a99d1313d7c8dc1b077617d39880e23`、`ddc53d482aa7ade372124cf7d7f6b76d8151e7be` — Activity 过期应用列表只读保护及编辑按钮状态。
  - `3fe1e9a18ceb8b0b75fd97d12c9320e8a664f8e9` — 增加 Root / Activity 静态接线断言。
  - `7fc7994e0255a560e422602c2a6c503ac35ea279`、`59565158641e29885e1dbb5cd5a48976a269a225` — 修正回归测试 fixture 与 UID 输出换行。
- 改动路径：
  - `scripts/yulong-app-firewall.sh`
  - `scripts/tests/fx-yulong-app-firewall-regression.sh`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongFirewallActivity.java`
  - `scripts/tests/fx-yulong-firewall-filter-regression.sh`
- 验证边界：
  - 已重新读取最新 HEAD 中上述四个文件，静态核对 Root 两个写入入口均执行 UID 校验；Activity 在刷新失败路径保持只读，成功后才恢复编辑；静态回归入口包含相应断言。
  - 本批未实际执行完整 Shell 集成回归：当前执行环境无法解析 github.com，Git clone 失败；也未触发整套 Actions。最近可见的自动工作流尝试集中在更早提交且已取消，不能作为本批测试通过证据。
  - 因此 UID mismatch / missing package / failed snapshot 的运行时测试仍标记为待执行；Android UI 生命周期及设备行为也未验收。
- 本批未生成 APK / KernelSU ZIP，未改变六 Tab 或 FX 1.0.0 版本号。
- 下一批：
  1. 在可执行仓库工作树中运行 `sh scripts/tests/fx-yulong-app-firewall-regression.sh` 和 `sh scripts/tests/fx-yulong-firewall-filter-regression.sh`；若失败先定位本批断言/Root mock 环境，不触发全量 Actions。
  2. 对照 Dia 23.11 导入 APK / 资源继续查找原版 `KeyEventHook` 的真实字节码或源码；当前 Frida key 模板只是观察器，不能猜测 `alert_auto` / `disable_alert_mode`。
  3. 回到 UI 主线继续完成游龙安全护盾原生深层页面与导航返回链。

## 2026-11-05 — 游龙广告独立应用管理页统一六 Tab 导航

- 本批代码提交前 HEAD：a48755dda21c0f2400509e99e8c63a40895ba1e0。
- 发现并纠正之前导航检查的范围问题：MainActivity 内部通过 base() 创建的页面已有六 Tab；但独立 Activity 使用自己的 setContentView(root)，不在 MainActivity.base() 的 Compose 外壳内，实际打开后没有固定底栏。
- 新增共享容器：
  - `adhook/app/src/main/java/de/privacyguard/adhook/FxNativeTabActivity.java`
  - 提交 15b73a52a2219b06082dbff7f184e3086da23022。
  - 基类复用现有 FxNativeAppShell 与 fx_ui.mode，向 ComposeView 设置 Lifecycle / ViewModelStore / SavedStateRegistry owners；底栏点击时通过 CLEAR_TOP + SINGLE_TOP 将选中的 0–5 Tab 交给栈中的 MainActivity，并结束当前独立页。
- 已接入三个游龙广告应用管理页：
  - `FxYulongAppStatsActivity.java` — bda906739db5c3fd4a4c30dd71eefcff156d709f。
  - `FxYulongAppWhitelistActivity.java` — f8c25ab10a568af30d8490d95107601cd1064383。
  - `FxYulongFirewallActivity.java` — 5d5ec6c098201782aa0c6e264214fba5354d087a。
  - 三页仍使用各自原有标题、返回按钮、列表、搜索、分页、编辑器及 Root 操作；本批只把根 View 放入六 Tab 外壳，初始选中“设置”Tab。
- MainActivity 路由提交 e6f08048a88147edd4b7b5023cea58881a61cda6：外部独立页以前只能请求 0–3；现改为 0–5 全部走 handleNativeTabSelection，因此 VPN / Ad / 隐私 / 脚本 / Hook / 设置均可从独立页返回主导航。
- 定向脚本更新：
  - 3f8a8ab5cd06555e34b54401a4fb9d126a79756b：`scripts/tests/fx-yulong-firewall-filter-regression.sh` 增加共享基类、三个 Activity 和 MainActivity 六 Tab 回跳接线断言。
  - 3a101556123a1e156c53186f9022e6f378ec39e1：修正旧 Firewall 集成回归中已废弃的反向筛选表达式断言。
  - 3fe1e9a18ceb8b0b75fd97d12c9320e8a664f8e9：回归脚本增加 stale inventory 只读状态和 Root 包/UID 写入校验。
- 已在本轮本地执行独立 JDK Host 测试：从当前 GitHub 文件内容取得的 FxYulongFirewallAppFilterPolicy.java 与 FxYulongFirewallAppFilterPolicyHostTest.java，以 `javac -Xlint:all -Werror` 编译并运行；11 项断言全部通过。六 Tab 静态接线脚本尚未在完整仓库工作树执行；未运行 Android / Gradle 编译、模拟器或真机导航验收。
- 同期并行 Firewall 安全修复：
  - e52a8ad1ed1cbec55b72cb68614905be1d737550：Root 写入 set / rule 前重新解析当前包 UID；包不存在、快照不可读或 UID 变化都拒绝修改。
  - 349884740d4fe7debd2bf00bfa2e36c17599555f：新增 stale UID、已卸载包与 Root 快照失败回归。
  - 4b4236036a99d1313d7c8dc1b077617d39880e23：Root/PackageManager 清单刷新未成功时防火墙编辑控件只读，总开关保持禁用。
  - ddc53d482aa7ade372124cf7d7f6b76d8151e7be：合并设置按钮的只读状态，避免创建后未被挂载的重复按钮。
  - 7fc7994e0255a560e422602c2a6c503ac35ea279：修正 Root UID 验证函数输出换行。
  - 59565158641e29885e1dbb5cd5a48976a269a225：修正 stale UID 测试中的包清单换行 fixture。
  - a48755dda21c0f2400509e99e8c63a40895ba1e0：同步记录上述 Firewall UID / stale inventory 防护。
- 未完成：其他独立 Activity（Yulong Ad 主页、DNS、证书/日志页、Dia 编辑器/Frida/Inspector、Shield 扫描/救援等）仍需按主入口优先级接入相同六 Tab 外壳；本批只覆盖三个高频广告应用管理页。外层六 Tab 固定结构仍需全页面验收。
- 下一批具体任务：继续接入游龙广告主功能 Activity（FxYulongAdActivity、FxYulongDnsActivity、FxYulongAdSummaryActivity 或 General Activity）中优先的 1–3 个页面；随后为 Dia 与 Shield 的核心页面复用同一基类。逐个验证 Tab 点击回跳、Activity 返回和滚动/编辑状态，不改 FX 1.0.0 版本，不提前打包。

## 2026-11-05 — 游龙安全护盾主 Hub 页面滚动状态恢复

- 本节更新前实时 HEAD：`d026623bdf019d7595d58ec8a62528911f9b1857`；固定分支 `fx-v1.0.0-unified-hook-integration`、版本 FX 1.0.0。
- UI 问题：安全护盾 Hub 是长列表，进入四级页面后返回正常保留 Activity 实例，但系统回收/旋转导致 Activity 重建时会回到列表顶部，丢失用户所在功能区位置。
- 已修复：`FxYulongShieldActivity` 将 ScrollView 提升为 Activity 字段，新增 `fx_yulong_shield_scroll_y` 状态键；`onSaveInstanceState` 保存当前纵向位置，`onCreate` 在视图布局后通过 `post()` 恢复位置。没有重建页面或更改任何安全功能开关默认值。
- 提交：
  - `c99ee9a7158b469002348281ab65c01c258a3641` — 安全护盾 Hub 滚动位置保存与恢复。
  - `9658496e1d68fbe8cc4af09c4a6380950e897ee4` — 安全护盾原生回归脚本增加滚动状态断言。
- 改动路径：
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongShieldActivity.java`
  - `scripts/tests/fx-yulong-shield-native-regression.sh`
- 验证：从当前分支重新读取两个文件，静态核对 ScrollView 字段、状态键、保存、恢复以及回归断言全部存在。尚未运行完整 Shell 回归、Gradle/JUnit、Android 编译、旋转/进程回收模拟器测试或真机验收；不可将源码断言等同于运行测试。
- 本批未改变六 Tab、原生页面功能、FX 1.0.0 版本号，未生成 APK / KernelSU ZIP。
- 下一批继续安全护盾原生 UI：逐项核对病毒库管理、扫描结果、白名单/管控列表、救援中心之间的返回链和筛选/搜索状态恢复；然后继续补全 Dia 23.11 按键原始实现证据，不凭 Frida 观察模板推断 KeyEventHook。

## 2026-11-05 — 游龙广告主控制、DNS 日志与每日总结页统一六 Tab 导航

- 本批代码开始前 HEAD：d026623bdf019d7595d58ec8a62528911f9b1857（期间最新并行提交 43682f20962886988873d0fb6761b73ac02f6793 只修正 Dia ActivityKey 测试断言，不改本批页面）。
- 复用上批新增的 `FxNativeTabActivity`，把三个独立 Activity 的 root View 放入原 FX 六 Tab Compose 外壳，初始选中 Settings=5：
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java` — 60f7b122a85bf82de170266856da44245ed06267。
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongDnsActivity.java` — 19fba759646dbd16a97334c0c6a351ed2f9f8125。
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdSummaryActivity.java` — edd2a00fb579596aee5fd69f4d89aa17284404fe。
- 每页保留既有标题、返回按钮、ScrollView、搜索/日志、表单、Root 执行和异步数据工作队列；本批只替换 Activity 宿主类型和根 View 安装入口，不改 Ad/DNS/统计业务逻辑及配置协议。
- 页面通过上批 `FxNativeTabActivity` 统一六个底栏目的与返回主 Activity 行为；主 Activity 外部 Tab 接收器已经支持 0–5，不新增第二套导航。
- 静态核验：三文件各只有一个根 setContentView(root)，更新后均 extends FxNativeTabActivity、调用 setContentViewWithNativeTabs(root, 5)，且不再直接 setContentView(root)。未运行 Android/Gradle 编译、六 Tab 脚本、模拟器或真机点击验收。
- 最新并行 Dia/Shield 工作线（本轮读取确认）：
  - 2a58a386752fcc560e0677b51889b19fb73adafe：增加有界 ActivityKey 手势策略。
  - d026623bdf019d7595d58ec8a62528911f9b1857：ActivityKey Host 覆盖。
  - c99ee9a7158b469002348281ab65c01c258a3641：修复安全护盾 Hub ScrollView 状态恢复。
  - 9658496e1d68fbe8cc4af09c4a6380950e897ee4：补充 Hub 滚动状态静态断言。
  - 43682f20962886988873d0fb6761b73ac02f6793：修正 ActivityKey 手势 Host 测试断言。以上为并行提交，本批未重复修改。
- 当前独立 Activity 六 Tab 覆盖已扩展到 Yulong App Stats / App Whitelist / Firewall / Ad Controls / DNS Logs / Daily Summary 六页；尚未覆盖 General settings、Dia Browser/Frida/Script/Inspector、Shield Scan/Integrity/Rescue 等独立 Activity。
- 验证边界：没有运行 Android 编译、JUnit/Gradle 或设备导航；静态接线核对不等于 Activity 运行验收。上一批 Firewall 纯 Java Host 用例 11 项已执行通过，但与本批壳接线不同。
- 下一批具体任务：接入游龙广告 General Settings 页面；随后把 Dia 的核心深层独立 Activity（Frida/脚本库/Activity Browser）与 Shield Scan/Integrity/Rescue 中优先的 1–3 页接上同一六 Tab 壳。保留它们原有返回/结果 Intent 及滚动状态，不改固定六 Tab 顺序或 FX 1.0.0 版本。
- 本批和此前均未生成最终 APK / KernelSU ZIP。

## 2026-11-05 — 安全护盾白名单 / 管控列表页面状态恢复

- 本节更新前实时 HEAD：`d3bdba1fcd938c4eaffc1c1e63bb272718274309`；固定分支 `fx-v1.0.0-unified-hook-integration`，固定版本 FX 1.0.0。
- 核对安全护盾四级页面发现：Hub 已恢复滚动位置；扫描页已有完整扫描结果 / 选择状态保存；白名单管理和管控列表则未保存自身列表位置，白名单搜索词也会在 Activity 重建后丢失。
- 已修复白名单管理：
  - 将列表 ScrollView 提升为 Activity 字段。
  - 保存并恢复搜索词与纵向滚动位置；恢复搜索词走原 TextWatcher / 列表刷新路径，不引入另一份搜索状态。
  - 保持原有白名单 SharedPreferences 键、异步标签加载、原生添加选择器和移除行为不变。
- 已修复管控列表：
  - 将列表 ScrollView 提升为 Activity 字段。
  - 保存并恢复当前分页与纵向滚动位置，重建后继续显示同一批列表区域。
  - 保持原有管控名单数据键、分页大小、异步应用加载和系统应用排除逻辑不变。
- 提交：
  - `a04630b0ec1cd000784fd024bf0df6b7ab59e005` — 白名单搜索词与滚动状态恢复。
  - `e5181c4262fd52d53d55cf675932d000ce6ce9d9` — 管控列表分页与滚动状态恢复。
  - `9f6d52a07ae7ffe8bf835dbe79c4793dd0189624` — 安全护盾回归脚本增加两页状态恢复断言。
- 改动路径：
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/WhitelistActivity.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/BlacklistActivity.java`
  - `scripts/tests/fx-yulong-shield-native-regression.sh`
- 验证：当前分支重新读取 Hub、白名单、管控列表和回归脚本，静态核对 7 项：Hub 保存/恢复、白名单查询/滚动恢复、管控分页/滚动恢复、回归断言、旧 ScrollView 局部变量引用清理，全部通过。尚未运行完整 Shield Shell 回归、Gradle/JUnit、Android 编译、旋转或进程回收模拟器测试、真机验收。
- 未改变六 Tab 顺序、任何名单语义或 FX 1.0.0 版本号；未生成 APK / KernelSU ZIP。
- 下一批：检查白名单选择器和管控应用选择弹窗在 Activity 重建 / 搜索后是否保留暂存勾选与列表位置；再继续游龙安全护盾病毒库、扫描结果与救援中心的导航返回链。Dia 原版 KeyEventHook 仍需从导入资源/原始 APK 证据溯源，不能把 Frida 观察模板当成拦截实现。

## 2026-11-05 — 游龙安全护盾病毒库、完整性与救援页面统一六 Tab 外壳

- 本批更新前实时 HEAD：`303b5db69ddf09b89d76af2df3f98657d58e723d`；固定分支 `fx-v1.0.0-unified-hook-integration`，版本固定 FX 1.0.0。
- 已把三个此前仍使用独立 Activity 根布局的核心页接入既有 `FxNativeTabActivity`，底栏初始选中“设置”（索引 5），页面本身的标题、返回按钮、ScrollView、表单、Root/系统设置跳转和业务流程保留：
  - `FxYulongVirusDatabaseActivity.java` — `257e0955d5b3cf4b3b85bd99102845742ca7e81e`。
  - `FxYulongRescueActivity.java` — `d3bdba1fcd938c4eaffc1c1e63bb272718274309`。
  - `FxYulongIntegrityActivity.java` — `afa7a1e679ea61ce1d747804776701e240270b42`。
- 对照当前实时 HEAD，扫描页 `FxYulongScanActivity` 已在先前并行提交中接入同一宿主；本批未重复修改。安全护盾 Hub、病毒库、扫描、完整性、救援中心现在均可显示 FX 六 Tab 外壳。
- 新增定向回归入口 `scripts/tests/fx-yulong-shield-six-tab-regression.sh` — `931c3953bf08504a4ab860b303b67129ea652f24`。检查 Manifest 声明、四个独立页面的共享宿主与单一根 View 安装点，并保护扫描结果状态保存、系统确认卸载路径、Hub 子页面路由。
- 最新 HEAD 文件级静态核验 10 项全部通过：数据库/扫描/完整性/救援页宿主、无绕过壳的旧 `setContentView(root)`、扫描结果状态保存、系统确认卸载入口、Hub 路由、Manifest 声明及回归脚本覆盖。
- 验证边界：本批没有完整仓库工作树，未实际运行新增 Shell 回归脚本、Gradle/JUnit、Android 编译、模拟器或真机六 Tab 点击/返回验收。静态契约通过不代表 Android 编译或设备验收通过。
- 未更改六 Tab 顺序、原始业务逻辑、FX 1.0.0 版本号；未生成 APK / KernelSU ZIP。
- 下一批具体任务：
  1. 检查白名单选择器 / 管控应用选择器在 Activity 重建、搜索后暂存勾选和滚动位置是否保留；继续修复 Shield 页面组的返回链和状态恢复。
  2. 核对病毒库页与扫描页的状态提示、后台任务旋转后回执及重复触发保护，避免 Activity 销毁后丢失任务结果。
  3. 继续接入 Dia 核心独立 Activity 的六 Tab 外壳；原版 `KeyEventHook` 没有可靠字节码证据前，不实现猜测版 `alert_auto`。

## 2026-11-05 — 白名单选择器暂存勾选、搜索与列表位置恢复

- 本节更新前实时 HEAD：`8d9a2738b9a5aedd94c1b56826e5b7c9b0d9e46b`；固定分支 `fx-v1.0.0-unified-hook-integration`，版本 FX 1.0.0。
- 问题：白名单全屏选择器使用 ListView + 异步应用枚举，旋转或 Activity 重建会清空尚未提交的多选集合，并丢失搜索词和滚动位置；用户可能误以为选择已保存。
- 已修复 `WhitelistPickerActivity`：
  - 保存/恢复暂存选择包名集合（仅 Bundle 暂存，不提前写入正式白名单）。
  - 保存/恢复搜索词，沿原有 TextWatcher / applyFilter 路径刷新。
  - 保存首个可见行位置及 top offset；异步应用加载与筛选完成后恢复 ListView 位置。
  - 保持正式白名单只在用户点击“加入所选”后写入，取消仍不会提交暂存选择。
- 提交：
  - `303b5db69ddf09b89d76af2df3f98657d58e723d` — 选择器暂存勾选、搜索与滚动状态恢复。
  - `d7bd8a1f0bdf62efcf160a2e3a8d4cd8fb606588` — 安全护盾回归脚本增加选择器状态断言。
- 改动路径：
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/WhitelistPickerActivity.java`
  - `scripts/tests/fx-yulong-shield-native-regression.sh`
- 验证：从最新分支重新读取 WhitelistActivity、BlacklistActivity、WhitelistPickerActivity 和回归脚本，静态核对两列表页及选择器的查询/分页/勾选/滚动保存恢复断言 6 项全部通过。未运行完整 Shield Shell 回归、Gradle/JUnit、Android 编译或旋转/进程回收设备测试。
- 管控应用添加流程目前仍使用 Activity 内 AlertDialog，暂存选择只存在弹窗闭包中；若系统在弹窗打开期间销毁 Activity，该草稿尚未持久化。本批未伪称这部分已解决。
- 未更改名单格式、正式写入时机、六 Tab 顺序或 FX 1.0.0 版本号；未生成 APK / KernelSU ZIP。
- 下一批：将管控应用选择弹窗迁为可恢复的 DialogFragment 或等价 Activity 状态模型，保留搜索、分页、暂存多选和确认/取消语义；随后继续检查病毒库/扫描/救援页面返回链。

## 2026-11-05 — 最新并行提交接管记录（Shield 六 Tab 与 Dia ActivityKey）

- 本节更新前实时 HEAD：`c2d2725ba1da4df678f15c0c91f60ad6eecdba08`；分支 `fx-v1.0.0-unified-hook-integration`，固定 FX 1.0.0。
- 接管时发现其他并行工作线已在本批之后继续提交，以下改动均以最新分支源码复核，不重复覆盖：
  - `70863a9ca71ffd574835c1ed5b7c22e96e60dab7` — Shield 白名单管理页接入六 Tab 宿主。
  - `8d9a2738b9a5aedd94c1b56826e5b7c9b0d9e46b` — Shield 白名单选择器接入六 Tab 宿主。
  - `ded04cea3d0c49d0a4a5fe85006282e9e2ea6915` — Shield 管控列表接入六 Tab 宿主。
  - `a21864178c71b97458ef1e09fd3fc9e00e726093` — Shield 白名单/管控页六 Tab 回归覆盖。
  - `a2254ac15d4ed3660d02c824d37c666b5fd503d4` — Dia ActivityKey 触发链接入应用与 Dialog 动作。
  - `ebf7ee32c650c5f6856e7e7acbff8eb8076a57f1` — ActivityKey 手势状态按包隔离。
- 最新源码核对：`FxYulongShieldActivity`、`WhitelistActivity`、`WhitelistPickerActivity`、`BlacklistActivity` 均继承 `FxNativeTabActivity`；Shield Hub 使用 `setContentViewWithNativeTabs(root, 5)`，未新增底栏或改变设置 Tab 的索引。之前完成的滚动/查询/分页/选择暂存状态保存仍在最新文件中。
- Dia ActivityKey 已从“仅观察模板”的旧阶段继续演进到独立策略接线；仍需检查其原始调用条件、按包隔离边界、手势误触保护和目标进程实际触发，不能把静态接线直接等同于真机行为完成。
- 本批没有对上述并行提交做重复修改；未触发整套 Actions。先前网络环境无法解析 github.com，无法在本执行容器克隆仓库运行 Shell 回归；最新源码仅完成文件级静态核对。
- 下一批：优先将管控应用选择 AlertDialog 的暂存勾选/搜索/分页状态纳入 Activity 重建恢复；随后对 Dia ActivityKey 逐项核验触发策略与目标包边界，再继续 Shield 病毒库、扫描、救援页面返回链。
- 未生成 APK / KernelSU ZIP，未改变六 Tab 顺序与 FX 1.0.0 版本。

## 2026-11-05 — 游龙广告通用设置与安全护盾核心页统一六 Tab 导航；Dia ActivityKey 包隔离

- 本节开始前实时分支 HEAD：1ddbbdcdc1d3f12662bdf9dad4bbaa60fa1d2141。
- 本批新增三个独立 Activity 的六 Tab 接线：
  - `FxYulongAdGeneralActivity.java` — 649a3b491211e7e3e53ab490fe4d94c13ab2434d。
  - `FxYulongShieldActivity.java` — 3ff7164c61ce420f99ac1d911bc3b43576bdfc22。
  - `FxYulongScanActivity.java` — 280bfd5f9cf78668402bfe8fe1f277c63df3a928。
  - 复用 `FxNativeTabActivity` 与 `setContentViewWithNativeTabs(root, 5)`；保留 General 原生设置/导入导出/Root 逻辑、Shield Hub scrollY 恢复、Scan 扫描状态/结果/选中项目 Bundle 状态。
- 并行 Shield 页面接线：
  - `257e0955d5b3cf4b3b85bd99102845742ca7e81e` — Virus Database。
  - `d3bdba1fcd938c4eaffc1c1e63bb272718274309` — Rescue Center。
  - `afa7a1e679ea61ce1d747804776701e240270b42` — Integrity。
  - `70863a9ca71ffd574835c1ed5b7c22e96e60dab7`、`8d9a2738b9a5aedd94c1b56826e5b7c9b0d9e46b`、`ded04cea3d0c49d0a4a5fe85006282e9e2ea6915` — Whitelist Manager / Picker / Blacklist Manager。
  - `a21864178c71b97458ef1e09fd3fc9e00e726093`、`931c3953bf08504a4ab860b303b67129ea652f24` — Shield 页面六 Tab 接线测试覆盖。
  - `a04630b0ec1cd000784fd024bf0df6b7ab59e005`、`e5181c4262fd52d53d55cf675932d000ce6ce9d9`、`9f6d52a07ae7ffe8bf835dbe79c4793dd0189624`、`8a0657128f53c4d50b064342dc90e22cb6c21911`、`d7bd8a1f0bdf62efcf160a2e3a8d4cd8fb606588`、`f610a5379b3eea7882097a4a3046f9b550c7e3d7`、`e62dec847a6761fe4ed8fdb6a88036c02832231e`、`9048fe0f05634a8f82af5a266b224c6afc6bd6d7`、`7994c04103190bf248ef96b5284bc59cc6200f5f` — 白名单/管控列表查询、分页、暂存多选、滚动、选择器恢复与关闭清理逐步补齐。
- 六 Tab 独立 Activity 当前覆盖 Yulong Stats / Whitelist / Firewall / Ad Controls / DNS Logs / Daily Summary / General Settings / Shield Hub / Scanner / Virus Database / Rescue Center / Integrity / Whitelist Manager / Whitelist Picker / Blacklist Manager；仍有 Dia Browser / Frida / Script Library / Inspector、Shield Batch Cleanup / Screen Filter 未覆盖。
- Dia ActivityKey 按包隔离修复：
  - 原 `AdVisibilityHook` 所有目标包共享一个 `FxDiaKeyGesturePolicy`，多包共享进程时按键时间戳会跨包污染。
  - 新增 `FxDiaKeyGesturePolicyRegistry.java`，按包名创建独立策略实例；目标包移除 ActivityKey 规则时清理对应对象。
  - `AdVisibilityHook.java` 的 dispatchKeyEvent / onKeyLongPress 按当前 Activity 包名取策略，保留 `chain.proceed()` 与异常 fail-open。
  - 提交：`ebf7ee32c650c5f6856e7e7acbff8eb8076a57f1`（Registry）、`b0d45ad13db3f6c45b9d73e7b145adb8b1a81594`（运行时接线）、`acc41a616ad53b1484ea9c0f0050f5b3063cb5d8`（交错包测试）、`b752832e0dbb47a77bc6910dafc09f99538e0b75`（定向回归脚本）。
  - 本地 JDK `javac -Xlint:all -Werror` 编译 policy、Registry、Host 测试；运行输出 `PASS: 21 Dia key gesture host assertions`。这验证纯 Java 手势与按包隔离，不代表 LSPosed 真机。
- ActivityKey 完整配置链并行进展：
  - `2a58a386752fcc560e0677b51889b19fb73adafe` 手势策略；`f22b012b8763bd827074e354ff03781e00bb8f02` Parser；`6c0b5974330296e5d9c52c812f83e6db4e1e8320` Serializer；`c2d2725ba1da4df678f15c0c91f60ad6eecdba08` 原生逐应用 UI；`424b1edb836c4b635f7b95c4ea4e019e5f7fea6a` 发布配置；`a2254ac15d4ed3660d02c824d37c666b5fd503d4` 目标 Activity Hook。
  - `5a4757722b294b02d9e70e7f1692193add6636aa` / `fa29f7112ab9c3740112866570d28f04633f9a7e` 修复两个动作 trigger 冲突；`f359c1538a03de532742cb451cbea757a50ac3a6` 与 `d0fa825d3510620070bc2b1c016ee7c5ab58fd34` 补充 Parser/Serializer 验证、默认值和往返测试。
  - 仍待真机验证音量/返回手势触发、目标应用行为与 Dialog toggle 反馈。
- 验证边界：本批 Activity shell 仅做源码接线断言；未运行六 Tab 脚本、Android 编译、模拟器或设备导航。ActivityKey 21 项纯 Java Host 测试已运行；未运行 LSPosed 设备测试。Firewall 纯 Java Host 测试 11 项另已在前批通过。
- 下一批：接入 Dia Activity Browser / Frida / Script Library 中 1–3 个核心 Activity；审查 ActivityKey 触发时间窗与原版一致性、Dialog toggle 状态是否同步；继续接入 Shield Batch Cleanup / Screen Filter。
- 固定 FX 1.0.0；未生成 APK / KernelSU ZIP。

## 2026-11-05 — Shield 六 Tab 七页覆盖与管控选择弹窗重建恢复

- 本节更新前实时 HEAD：`122b870223dfa2bb4a0416e5d7d4886a20d29bd8`；指定分支与 FX 1.0.0 未改变。
- 纠正上一节“管控应用添加弹窗状态仍未保存”的旧记录：已完成等价 Activity 状态模型，不改名单持久化协议：
  - 保存弹窗是否打开、搜索词（最多 256 字符）、加载分页、暂存包名集合、弹窗内 ScrollView 纵向位置。
  - Activity 重建后等待后台应用清单加载成功，再恢复同一个选择弹窗、筛选词、页数、暂存勾选和滚动位置。
  - 旋转 / 配置变化时旧 Dialog 的 dismiss 回调不清除恢复草稿；用户主动取消或关闭时清除草稿；只有“确定加入”回调才把暂存包名合并到正式管控名单。
  - 应用清单尚未加载时用户点击添加不会错误标记为“弹窗已打开”，避免加载完成后出现意外自动弹窗。
- 代码提交：
  - `f610a5379b3eea7882097a4a3046f9b550c7e3d7` — 保存管控选择弹窗打开状态、搜索词、分页和暂存勾选。
  - `e62dec847a6761fe4ed8fdb6a88036c02832231e` — 加入弹窗内滚动位置恢复。
  - `9048fe0f05634a8f82af5a266b224c6afc6bd6d7` — 从 savedInstanceState 恢复弹窗滚动位置。
  - `7994c04103190bf248ef96b5284bc59cc6200f5f` — 主动关闭/无候选应用时清理暂存状态。
  - `1ddbbdcdc1d3f12662bdf9dad4bbaa60fa1d2141` — 定向回归增加弹窗状态恢复、取消不提交与确认才提交断言。
- 当前最新 HEAD 静态核对 10 项全部通过：五个状态键；Bundle 保存；Bundle 恢复；后台清单完成后重开弹窗；弹窗内滚动恢复；配置变化保留暂存；主动关闭清理暂存；正式名单只在确认回调更新；Shield 七个 Activity 六 Tab 壳接线；回归脚本包含新断言。
- Shield 七个独立页面覆盖（病毒库、扫描、完整性、救援、白名单管理、白名单选择器、管控列表）均使用 `FxNativeTabActivity`，并由 `fx-yulong-shield-six-tab-regression.sh` 检查；Hub 另保留六 Tab 宿主及各子页面路由。
- 验证边界：只完成最新 GitHub 源码静态核对；没有完整仓库工作树，未实际运行 Shell 回归、Gradle/JUnit、Android 编译、旋转/进程回收模拟器或真机验收。不可将静态断言称为运行测试通过。
- 未改变名单格式、确认/取消语义、六 Tab 顺序、FX 1.0.0 版本号；未生成 APK / KernelSU ZIP。
- 下一批直接任务：检查病毒库同步按钮在旋转/重建时是否可能重复提交、结果回执是否丢失；随后检查 Shield 子页面返回链和 Dia 核心独立 Activity 六 Tab 接入。

## 2026-11-05 — Dia Activity Browser / Frida / Script Library 原生页统一六 Tab

- 本批开始前实时 HEAD：122b870223dfa2bb4a0416e5d7d4886a20d29bd8。
- 三个 Dia 独立原生 Activity 接入既有 `FxNativeTabActivity` 共享六 Tab 壳：
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaActivityBrowserActivity.java` — 7f5de8f020811675405e057f4633872e537ca3a0。
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java` — 761a370b5b6f64d5f4dfbb175fd58b467b514418。
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaScriptLibraryActivity.java` — 1492f47b0024f5c85211f064cba8e1bd73dad748。
- 只替换 Activity 宿主和 `setContentView(root)` 为 `setContentViewWithNativeTabs(root, 5)`；不改三页原有包/Activity 查询分页、Frida Gadget 工具表单、脚本库编辑与存储、异步工作队列和返回行为。
- 新增定向回归入口：`scripts/tests/fx-dia-native-tab-regression.sh` — 1871003c5ccfc0a402f84c984249310e3cb1fd19。脚本核对共享 Compose 壳的 Lifecycle/ViewModel/SavedState owner、0–5 Tab 范围、MainActivity 返回路由和三页 Activity 接线。
- 静态源码核对：3 个目标页均继承 FxNativeTabActivity、调用共享壳、无旧 setContentView(root)；保留原 onCreate 与页面 View 构建。脚本已提交，但本轮未从完整仓库工作树执行。
- 并行最新进度：`e0f79afacf9d8c8b7af8b1ad25ef6ef624b48699` 将 Dia Inspector Activity 接入六 Tab。当前 Dia 独立原生页的六 Tab 覆盖至少包括 Activity Browser、Frida、Script Library、Inspector。
- 仍未完成：Dia Crash Report / Monitor Events / Dex Browser / Code Editor / Backup / Global Settings 等独立页面尚需按原版使用频率逐组迁移；游龙安全护盾的 Batch Cleanup / Screen Filter 等仍待接入。
- 验证边界：无 Android Gradle 编译、模拟器/真机点按、Activity 结果回传和状态旋转验收；本批只做源码断言。ActivityKey 另有 21 项纯 Java Host 测试通过，但不代表 LSPosed 按键行为验收。
- 当前分支 HEAD（本节记录时）：4f9be614e7776e3c31776de300d48831a11b3dba。HEAD 前最近提交：4f9be614e7776e3c31776de300d48831a11b3dba feat(dia): add six-tab shell to native code editor；e0f79afacf9d8c8b7af8b1ad25ef6ef624b48699 feat(dia): add six-tab shell to inspector；1871003c5ccfc0a402f84c984249310e3cb1fd19 test(dia): add native six-tab page integration regression；1492f47b0024f5c85211f064cba8e1bd73dad748 feat(ui): keep six-tab shell on Dia script library；761a370b5b6f64d5f4dfbb175fd58b467b514418 feat(ui): keep six-tab shell on Dia Frida tools；7f5de8f020811675405e057f4633872e537ca3a0 feat(ui): keep six-tab shell on Dia Activity Browser；67d40827a19d6de6ce1b1022210c213d9ace8c32 docs(shield): record picker restoration and six-tab coverage；122b870223dfa2bb4a0416e5d7d4886a20d29bd8 docs(fx): record ActivityKey isolation and Shield UI progress；1ddbbdcdc1d3f12662bdf9dad4bbaa60fa1d2141 test(shield): cover blacklist picker state restoration；d0fa825d3510620070bc2b1c016ee7c5ab58fd34 test(dia): cover ActivityKey Serializer validation and round trip。
- 下一批具体任务：继续接入 Dia Crash Report / Monitor Events / Dex Browser 里 1–3 个核心页；逐一保留 Activity Result、文件选择、导出、返回栈。之后核对 Inspector 的 LSPosed Hook 权限与状态展示不误导，再推进 Shield Batch Cleanup / Screen Filter。
- 固定 FX 1.0.0；未生成 APK / KernelSU ZIP。

## 2026-11-05 — Dia 原生工具页面继续统一六 Tab

- 本节更新前实时 HEAD：`f19251d7559fb5350f6781d6de969aa466dfcf43`；固定分支与 FX 1.0.0 未改变。
- 在复核并行工作线已经接入的 Activity Browser / Frida / Script Library / Inspector 后，本批继续接入：
  - `FxDiaInspectorActivity.java` — `e0f79afacf9d8c8b7af8b1ad25ef6ef624b48699`。
  - `FxDiaCodeEditorActivity.java` — `4f9be614e7776e3c31776de300d48831a11b3dba`。
  - `FxDiaJsonActivity.java` — `609b6933fb1c36112cd53b806a857c4fc79ffd97`。
  - `FxDiaMonitorEventsActivity.java` — `90cd90db665716b5a567c3a9b8ba653c8a92c784`。
- Activity Browser、Frida 与 Script Library 已由并行提交接入，不重复修改：`7f5de8f020811675405e057f4633872e537ca3a0`、`761a370b5b6f64d5f4dfbb175fd58b467b514418`、`1492f47b0024f5c85211f064cba8e1bd73dad748`。
- 新增 `scripts/tests/fx-dia-six-tab-regression.sh` — `fcd6442434850780270088d89b629d9ae234c3b8`，检查上述七个 Dia 页面 Manifest 声明、共享 `FxNativeTabActivity`、单一根壳安装点，以及 Browser → Inspector、Script Library → Code Editor、Frida → Script Library 的既有路由。
- 当前 HEAD 静态核对 5 项全部通过：七页共享宿主、无旧根布局绕过、Manifest 七项声明、回归脚本七页覆盖、原有核心路由断言。
- 本批只替换 Activity 宿主与根 View 安装入口，不改编辑器内容、脚本存储、Frida 工具、Activity 查询、事件查看器、导出/文件选择或现有 Intent 路由。
- 验证边界：没有完整仓库工作树，未实际执行新 Shell 回归脚本、Gradle/JUnit、Android 编译、模拟器/真机导航与 Activity Result 验收；5 项为 GitHub 最新源码静态核对。
- 下一批：继续接入 Dia Crash Report / Dex Browser / Backup 相关页面（每批 1–3 个），检查文件选择和导出回传；之后推进游龙安全护盾 Batch Cleanup / Screen Filter 独立页面。
- 未更改六 Tab 顺序或 FX 1.0.0；未生成 APK / KernelSU ZIP。

## 2026-11-05 — Dia Crash Report / Monitor Events / DEX Browser 原生页统一六 Tab

- 本批开始前实时 HEAD：35e87cff56023f421a47535279469e392fefe784。
- 新增 Dia 三个独立页面六 Tab 接线：
  - `FxDiaCrashReportActivity.java` — 2860443d753ecbf11fed11ae2e0624f7d331ce0d。
  - `FxDiaMonitorEventsActivity.java` — 90cd90db665716b5a567c3a9b8ba653c8a92c784。
  - `FxDiaDexBrowserActivity.java` — 3b925b73aaa3e7ff146f3617a34c4d8e2cc0d1d4。
  - 统一复用 `FxNativeTabActivity` / `setContentViewWithNativeTabs(root, 5)`，保留原 Activity 页面与结果行为。
- Dex Browser 接线后的关键检查：`Intent.ACTION_OPEN_DOCUMENT` 仍存在；`startActivityForResult` 与 `onActivityResult` 仍存在；`setResult(RESULT_OK, result)` 仍存在，未改文件选择、DEX 索引或结果回传路径。
- Monitor Events 页面仍有原有 `STATE_SEARCH`、`STATE_CATEGORY`、`STATE_AUTO_REFRESH`、`STATE_SCROLL_Y` 状态键与滚动恢复；本批仅换 Activity 宿主及 root View 安装点。
- 扩展 `scripts/tests/fx-dia-native-tab-regression.sh`，提交 `33fade6bb740c4e3a254b2a8a3b36cd78f4f1abe`：覆盖九个 Dia 独立页（Activity Browser / Frida / Script Library / Inspector / Code Editor / Crash Report / Monitor Events / Dex Browser / JSON Editor），并断言共享壳的 Lifecycle、ViewModel、SavedState owner 与 0–5 Tab 回跳路由。脚本已提交但本轮未在完整工作树执行。
- 本节写入前最新分支 HEAD：1f54c999cc9e0db406e381856ee69fc569b5c528；最近提交：1f54c999cc9e0db406e381856ee69fc569b5c528 fix(dia): detect overlapping ActivityKey action triggers；dd2511b3d6338290709fc9a81161e18fe142fb22 feat(dia): add six-tab shell to backup and restore；33fade6bb740c4e3a254b2a8a3b36cd78f4f1abe test(dia): cover all migrated native pages in tab regression；97cd140b278e0815350fe5b3f3e5ed83df1e7840 docs(dia): record seven native tool pages on six tabs；3b925b73aaa3e7ff146f3617a34c4d8e2cc0d1d4 feat(ui): keep six-tab shell on Dia DEX browser；f19251d7559fb5350f6781d6de969aa466dfcf43 test(dia): include ActivityKey in native regression；fcd6442434850780270088d89b629d9ae234c3b8 test(dia): assert six-tab shell on core tools；2860443d753ecbf11fed11ae2e0624f7d331ce0d feat(ui): keep six-tab shell on Dia crash reports；90cd90db665716b5a567c3a9b8ba653c8a92c784 feat(dia): add six-tab shell to monitor event viewer；609b6933fb1c36112cd53b806a857c4fc79ffd97 feat(dia): add six-tab shell to JSON editor。
- 当前 Dia 六 Tab 覆盖还包括 Inspector（`e0f79afacf9d8c8b7af8b1ad25ef6ef624b48699`）、Code Editor（`4f9be614e7776e3c31776de300d48831a11b3dba`）、JSON Editor（`609b6933fb1c36112cd53b806a857c4fc79ffd97`）。Activity Browser / Frida / Script Library 在上一批已接入。
- 验证边界：本批做代码级断言，未运行 Android/Gradle 构建、模拟器、文件选择器、Activity Result 真机回传或旋转/进程回收测试。不要把共享底栏存在误记为原版 Dia 全部功能完成。
- 未覆盖 Dia File / Backup / Global Settings / GPS Picker / Wi-Fi Proxy / Session Log 等更多独立页面；这些仍需依据原路由优先级逐组接入。Shield Batch Cleanup / Screen Filter 亦未覆盖。
- 下一批：先将 Dia File / Backup / Global Settings 选 1–3 页接入六 Tab，并核验 FileProvider/Document URI 的读写持久权限；随后处理 GPS Picker / Wi-Fi Proxy / Session Log，再完成 Shield Batch Cleanup / Screen Filter。
- 固定 FX 1.0.0；未生成 APK / KernelSU ZIP。

## 2026-11-05 — Dia 九个核心独立 Activity 统一六 Tab

- 本节更新前实时 HEAD：`5161b42ce192e514c05e7d7228867e08b2eae231`；固定分支、FX 1.0.0 不变。
- 在上一批七个工具页面基础上，继续接入：
  - `FxDiaBackupActivity.java` — `dd2511b3d6338290709fc9a81161e18fe142fb22`。
  - `FxDiaGlobalSettingsActivity.java` — `f74e6f9ccce768162fd5caa59c35894863b1a863`。
- 同期并行工作线已接入 Crash Report 与 Dex Browser（最新源码确认已继承 `FxNativeTabActivity`），本批不重复修改。
- 更新 `scripts/tests/fx-dia-six-tab-regression.sh`：`af3f2fe9371c58e36db37c3c5748df2f53a44221`，现在覆盖九个 Dia Activity：Activity Browser、Frida、Script Library、Inspector、Code Editor、JSON、Monitor Events、Backup、Global Settings。
- 当前 HEAD 静态核对 5 项全部通过：九页共享六 Tab 宿主、无旧根布局绕过、Manifest 九项声明、回归脚本九页覆盖、Browser/Inspector 与 Library/Editor/Frida 既有路由仍在。
- Backup 页保留原有两个 Activity Result 文件选择请求；本批未改文件导入/导出逻辑，只更换宿主根 View。仍需设备验证文件选择器返回与 Activity 重建行为。
- 未运行完整 Shell 回归、Gradle/JUnit、Android 编译、模拟器/真机导航及文件选择器结果回传；5 项为当前 GitHub 源码静态核验。
- 下一批：继续接入 Dia Session Log / Crash Report / Dex Browser 的剩余深层页面（若最新并行分支未完成则复用），核对文件与导出回传；随后接入 Shield Batch Cleanup / Screen Filter。
- 未改变六 Tab 顺序、FX 1.0.0 版本号；未生成 APK / KernelSU ZIP。


## 2026-11-05 — Dia DEX Browser / File & ELF 页面统一六 Tab

- 本批开始时目标分支 HEAD：`33fade6bb740c4e3a254b2a8a3b36cd78f4f1abe`；提交期间检测到并行提交推进，后续均以最新 HEAD 为父提交追加，没有强推或覆盖。
- Dia DEX Browser 已由并行工作线接入 `FxNativeTabActivity`（本批复核时已存在，未重复修改）；其原有 SAF 文档选择、DEX 检查、详情与导出工作队列保持原样。
- 本批将 `FxDiaFileActivity.java` 从普通 Activity 宿主切换为 `FxNativeTabActivity`，根页面改由 `setContentViewWithNativeTabs(root, 5)` 安装六 Tab 外壳；页面内部的用户授权 SAF 目录管理、导入/导出、目录浏览、文件预览/删除及 SO 库只读检查逻辑未删改。
- 提交记录：
  - `fda4b980504f514998f02dbea443eaa90dc6a255` — File/ELF 页面六 Tab 宿主接入。
  - `8733d6d6b1f74817ccf7620dedf8893cf662b261` — 扩展 Dia 原生页回归脚本，纳入 DEX Browser 与 File/ELF，并检查 SAF 授权、文档创建、Activity Result、目录加载和 IO worker 锚点。
- 静态验证：类继承、共享壳唯一安装点、移除旧 `setContentView(root)`、DEX/File 回归条目及 SAF/worker 关键锚点均通过源码断言。未在完整工作树执行 Shell 脚本，未执行 Gradle 编译、模拟器/真机 Activity Result 与旋转验收。
- 仍未完成：Dia Global Settings / GPS Picker / Wi-Fi Proxy / Session Log 等独立页面；Shield Batch Cleanup / Screen Filter；六 Tab 全局返回栈与实际设备验收。
- 下一步：继续迁移 Dia Global Settings / GPS Picker 中最常用的 1–2 页；随后处理 Shield Batch Cleanup / Screen Filter。固定 FX 1.0.0，不生成 APK / KernelSU ZIP。

## 2026-11-05 — Dia GPS Picker 与 Session Log 统一六 Tab

- 本批开始前分支 HEAD：0bec1ffaca6a3aa9a1ed0a1d5df2db7522ded04d。
- 两个独立 Activity 接入现有 `FxNativeTabActivity`：
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaGpsPickerActivity.java` — `4bf46f5ad58379ca69c6021e272e59f8a69fcfe2`。
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaSessionLogActivity.java` — `6aaf833a613ec3e9aa060ccd71d98fe3c6a6d90c`。
- 仅修改 Activity 宿主和根布局安装点：使用 `setContentViewWithNativeTabs(root, 5)`；GPS Picker 原有经纬度输入、AMap HTTPS WebView、禁止 JS bridge、状态 Bundle 保存/恢复未改；Session Log 的搜索/分类/自动刷新/滚动状态与原日志读取未改。
- 同批复核：Dia File/ELF 页面已由并行提交 `fda4b980504f514998f02dbea443eaa90dc6a255` 接入六 Tab，Backup 与 Global Settings 也已在最新分支继承共享宿主，未重复修改。
- 本轮并行 Shield 页面也接入六 Tab：
  - `9e634c561d492a93874b11209ac9676d5d085b63` — Batch Cleanup。
  - `239b1e6358147cb1159b6e7b717cdd4d5920dbb1` — Screen Filter。
- 文件访问边界复核：Dia File 通过用户显式选择 SAF 目录，调用 `takePersistableUriPermission` 保存读/写授权；Backup 的 ACTION_CREATE_DOCUMENT / ACTION_OPEN_DOCUMENT 结果链仍存在；本批没有扩大存储权限或更改授权范围。
- 静态核验：GPS Picker 与 Session Log 均继承 FxNativeTabActivity、安装共享壳、无旧 `setContentView(root)`；Bundle 状态键和页面根视图仍存在。未运行 Android/Gradle、SAF/AMap 设备测试。
- 当前 Dia 六 Tab 覆盖进一步包括 Activity Browser / Frida / Script Library / Inspector / Code Editor / Crash Report / Monitor Events / DEX Browser / JSON Editor / File & ELF / Backup / Global Settings / GPS Picker / Session Log。Wi-Fi Proxy Activity 当前不使用常规 setContentView，需单独检查其弹窗/启动器型 UI 形态后再决定是否需要容器，不得直接强行套壳。
- 当前 Shield 独立页覆盖已扩展到 Batch Cleanup / Screen Filter；仍需确认所有这些新页面的 Tab 点击回跳、返回栈和授权对话框在设备上正常。
- 验证边界：本批只有源码级接线与保留标记核对；未执行六 Tab Shell 回归脚本、Android 编译、GPS WebView、SAF 文件选择器、模拟器或真机测试。
- 本节写入前 HEAD：7d4d136d964a7ba4aea9ae40010159540d8d546d。最近提交：7d4d136d964a7ba4aea9ae40010159540d8d546d test(dia): cover overlapping ActivityKey gesture conflicts；239b1e6358147cb1159b6e7b717cdd4d5920dbb1 feat(shield): add six-tab shell to screen filter；6aaf833a613ec3e9aa060ccd71d98fe3c6a6d90c feat(ui): keep six-tab shell on Dia session logs；4bf46f5ad58379ca69c6021e272e59f8a69fcfe2 feat(ui): keep six-tab shell on Dia GPS picker；9e634c561d492a93874b11209ac9676d5d085b63 feat(shield): add six-tab shell to batch cleanup；65821e8c007fdd44917154b38c09e6c134e53336 test(dia): cover overlapping ActivityKey gestures in Serializer；0bec1ffaca6a3aa9a1ed0a1d5df2db7522ded04d docs(fx): record Dia File six-tab integration；8733d6d6b1f74817ccf7620dedf8893cf662b261 test(dia): cover File and ELF six-tab integration；b82e8933636b3fabb652d5e391e9f3337ff0ec38 test(dia): cover overlapping ActivityKey gestures in Parser；fda4b980504f514998f02dbea443eaa90dc6a255 feat(dia): keep File and ELF page in six-tab shell；149ea8cd08bbe2a412ebb9c8a67f3cc33f12c2a2 docs(dia): record nine core pages on six tabs；e2f3fb4a0bf9e8f8e85db764f31d7796263c63bf fix(dia): prevent overlapping ActivityKey assignments in UI。
- 下一批：检查 Dia Wi-Fi Proxy 的 UI 启动方式与系统代理恢复链，决定如何挂载导航；然后核对 Dia Crash Capture/Session/Monitor 页面所有按钮实际后端动作，以及 Shield Batch Cleanup/Screen Filter 的服务与权限状态真实性。
- 固定 FX 1.0.0；未生成 APK / KernelSU ZIP。


## 2026-11-05 — Dia GPS Picker / Session Log 原生页统一六 Tab

- 本批复核时，GPS Picker 与 Session Log 已由并行工作线先行接入 `FxNativeTabActivity`，本轮不重复修改页面实现；当前源码确认两页均使用 `setContentViewWithNativeTabs(root, 5)`，不再直接安装裸根布局。
- GPS Picker 保留 `STATE_PAIR`、`STATE_LATITUDE`、`STATE_LONGITUDE`、`STATE_STATUS` 和 `onSaveInstanceState`；Session Log 保留 `STATE_SEARCH`、`STATE_SCROLL_Y` 与滚动/搜索恢复。
- 提交 `71a063097136579e9bbe63c08bc9eea83e98fe32` 扩展 `scripts/tests/fx-dia-native-tab-regression.sh`，把 GPS Picker、Session Log 纳入页面集合并断言上述状态恢复锚点。
- 静态核验：两页共享宿主接线和状态键均存在；回归脚本已纳入两页。未运行完整 Shell、Gradle/Android 编译、模拟器/真机点按与旋转验收。
- 下一步：检查尚未迁移的 Dia Signature / System Expand / Wi-Fi Proxy 页面；同时推进 Shield Batch Cleanup / Screen Filter。固定 FX 1.0.0，不生成 APK / KernelSU ZIP。

## 2026-11-05 — Shield Batch Cleanup / Screen Filter 与 Dia Session Log 六 Tab 接入

- 本节更新前实时 HEAD：`9c57dbb1f3ef01cea3146a4df72e358f06668b14`。
- 新接入三个独立 Activity：
  - `FxYulongBatchCleanupActivity.java` — `9e634c561d492a93874b11209ac9676d5d085b63`。
  - `FxYulongScreenFilterActivity.java` — `239b1e6358147cb1159b6e7b717cdd4d5920dbb1`。
  - `FxDiaSessionLogActivity.java` — `6aaf833a613ec3e9aa060ccd71d98fe3c6a6d90c`（由并行工作线先提交，当前源码已复核）。
- 更新回归入口：
  - `scripts/tests/fx-yulong-shield-six-tab-regression.sh` — `fca6e7ee36b468d30f28b61b1b54214e8a718655`，增加 Batch Cleanup / Screen Filter 两页。
  - `scripts/tests/fx-dia-six-tab-regression.sh` — `a76f4324d78110ff7976c8cd10b403dc8d05083e`，增加 Session Log。
- 当前 HEAD 静态核验 6 项通过：三页继承共享 `FxNativeTabActivity`、使用唯一六 Tab 根安装点、Manifest 有声明、两个回归脚本包含目标页面。Shield 七页原有六 Tab 与管控弹窗状态恢复检查仍在。
- 同步接管并行 Dia ActivityKey 冲突检查：`e2f3fb4a0bf9e8f8e85db764f31d7796263c63bf`、`b82e8933636b3fabb652d5e391e9f3337ff0ec38`、`65821e8c007fdd44917154b38c09e6c134e53336`、`7d4d136d964a7ba4aea9ae40010159540d8d546d`、`9fb7e8a28454a335fd320c8827aeafa0eb22249c` 已连续处理 UI/Parser/Serializer/Host 中重叠 ActivityKey 触发配置；不重复修改。该逻辑仍需检查实际目标进程触发与误触边界。
- 未运行完整 Shell 回归、Gradle/JUnit、Android 编译、模拟器或真机 Tab 点击/返回验收；本批 6 项是从最新 GitHub 文件读取后的静态检查。
- 未更改六 Tab 顺序、FX 1.0.0 版本号；未生成 APK / KernelSU ZIP。
- 下一批继续：Dia Signature / System Expand / Wi-Fi Proxy 的原生入口与返回链；并检查 Shield Batch Cleanup 的系统确认结果回传及 Screen Filter Accessibility 服务状态是否准确反映真实连接状态。


## 2026-11-05 — Dia GPS Picker / Session Log 六 Tab 回归覆盖

- 本批期间并行工作线已先后将 `FxDiaGpsPickerActivity` 与 `FxDiaSessionLogActivity` 接入 `FxNativeTabActivity`，复核最新 HEAD 后不重复改动页面代码。
- 本批提交 `cc825166105ad72751522da35ebb5b85637caa1a`：扩展 `scripts/tests/fx-dia-native-tab-regression.sh`，将 GPS Picker 与 Session Log 加入页面集合，并加入坐标/配对状态、搜索条件、滚动位置状态保存锚点检查。
- 验证：最新分支源码确认两页均使用共享六 Tab 宿主；回归脚本文本断言已加入。尚未在完整 checkout 环境实际运行脚本，未运行 Gradle、模拟器或真机测试。
- 并行冲突记录：旧文件 SHA 更新返回 409；重新读取最新分支后确认两页已由并行工作线完成，因此不覆盖页面实现。
- 下一步：检查 Dia Global Settings 与剩余独立页面导航；随后处理 Shield Batch Cleanup / Screen Filter，并做统一六 Tab 返回链与恢复验收。固定 FX 1.0.0，不打包最终 APK / KernelSU ZIP。


## 2026-11-05 — Dia Signature / System Expand 原生页统一六 Tab

- 本批最新目标分支 HEAD（追加前）：`b65381d6406d997d95328cad545e04ad0ea5a685`。
- 将 `FxDiaSignatureActivity` 与 `FxDiaSystemExpandActivity` 接入既有 `FxNativeTabActivity`，两页根布局均通过 `setContentViewWithNativeTabs(root, 5)` 安装六 Tab；不改签名读取或系统设置业务逻辑。
- 保留签名页只读 PackageManager 签名信息、SigningInfo / SHA 摘要与应用选择；保留 System Expand 的 PackageInstaller 会话检查、安装来源设置入口、Root 操作及确认弹窗。
- 提交：`876901027c99025a637c989b87b15eeb14adffbe`（Signature Viewer）；`ea67992db756c77c4eb481208023e515b181f89d`（System Expand）；`45c0cb122fbe087c1ae723a9e86ddcb72b871a30`（回归脚本覆盖）。
- 静态核验：两页共享宿主与唯一根安装点、签名信息读取锚点、System Expand 安装来源/PackageInstaller/Root 确认锚点均通过源码断言。未运行 Shell 回归、Gradle/Android 编译、模拟器/真机权限与 Root 行为验收。
- 仍未完成：Dia Wi-Fi Proxy 原生独立页六 Tab 接入与 Root 代理运行验收；全局返回链设备验收。Shield Batch Cleanup / Screen Filter 已由并行工作线接入，仍需执行设备验收。
- 下一步：迁移 Dia Wi-Fi Proxy 页面并检查 Root 操作状态回执、失败回滚和页面销毁时后台任务行为；随后转入六 Tab 导航返回链和设备级验证。固定 FX 1.0.0，不生成 APK / KernelSU ZIP。


## 2026-11-05 — Dia Wi-Fi Proxy 六 Tab 与 Root 恢复安全回归

- 本轮复核时，`FxDiaWifiProxyActivity` 已由并行工作线接入 `FxNativeTabActivity`；本轮未重复改页面实现。
- 源码确认代理页保留 `FxDiaWifiProxyState.mayRestore/evaluate` 冲突保护、Root 命令结果处理、恢复确认弹窗、busy 状态门控，以及 `onDestroy()` 中 `worker.shutdownNow()`。
- 提交 `6022096bc97ee368de26733a8a2ec5b28c4c740a` 扩展 Dia 原生页回归脚本，覆盖 Wi-Fi Proxy 六 Tab 页面与受保护恢复/后台线程销毁锚点。
- 静态核验已完成；尚未运行 Shell 脚本、Gradle/Android 编译或真机 Root HTTP 代理写入/恢复验证。不得将静态锚点视为真实系统代理验收。
- Dia 23.11 主要独立工具页面目前大部分已接入共享六 Tab；下一阶段重点转为六 Tab 返回栈、页面状态恢复、VPN/Root 真实行为和设备级验证。固定 FX 1.0.0，不生成最终 APK / KernelSU ZIP。

## 2026-11-05 — Dia / Shield 独立页面六 Tab 覆盖扩展

- 本节更新前实时 HEAD：`d2c0aecaec9e34df43512826a58fddd2eeb4fed0`。
- 最新源码核对确认 Dia 目录中以下 17 个独立 Activity 均使用 `FxNativeTabActivity` 并调用 `setContentViewWithNativeTabs(root, 5)`，不再绕过底部导航：
  1. Activity Browser
  2. Frida 工具
  3. Script Library
  4. Inspector
  5. Code Editor
  6. JSON Editor
  7. Monitor Events
  8. Backup / Restore
  9. Global Settings
  10. Session Log
  11. Crash Report
  12. DEX Browser
  13. SAF File / ELF
  14. Signature Inspector
  15. System Expand
  16. Wi-Fi Proxy
  17. GPS Picker
- System Expand 与 Signature / Wi-Fi Proxy 的宿主接入由并行工作线推进；本批没有重复改写已接入页面。Batch Cleanup / Screen Filter 已在前节接入 Shield 六 Tab。
- 更新 `scripts/tests/fx-dia-six-tab-regression.sh`：`29c35b5f3495df64def5c51cad1edfd6b8bff732`，将上述 17 个页面纳入逐页 Manifest / 宿主 / 根安装点检查；原有 Browser→Inspector、Script Library→Code Editor、Frida→Script Library 路由断言保留。
- 最新 HEAD 静态核验 6 项通过：17 页共享宿主、无旧裸根绕过、回归脚本列全、Backup 文件选择 Activity Result 入口保留、Wi-Fi Proxy 共享壳、System Expand 共享壳。
- Shield Batch Cleanup / Screen Filter 页面也已使用共享宿主；对应 `fx-yulong-shield-six-tab-regression.sh` 已增加两页。未改变原服务逻辑、权限开关或危险操作默认值。
- 验证边界：未实际运行 Shell 脚本、Gradle/JUnit、Android 编译、模拟器/真机六 Tab 点击与返回栈验收；本节仅记录最新 GitHub 源码静态核验。
- 下一批继续：核对独立 Activity 的 Tab 点击回跳与 CLEAR_TOP 返回链是否对所有页面一致；检查 Backup / SAF / GPS Picker 的 Activity Result 在重建后的状态恢复；随后处理 Shield 的服务状态与权限真实性。
- 固定 FX 1.0.0；未生成 APK / KernelSU ZIP。


## 2026-11-05 — Shield 每日摘要 / 安全告警原生页六 Tab 接入

- 本批起始目标分支 HEAD：`6022096bc97ee368de26733a8a2ec5b28c4c740a`。
- 将 `FxYulongDailySummaryActivity` 与 `FxYulongWarningActivity` 接入现有 `FxNativeTabActivity`，根视图使用 `setContentViewWithNativeTabs(root, 5)`；未更改页面业务布局与数据/操作流程。
- 每日摘要仍读取本机 `shield_prefs` 的扫描/事件计数、后台服务运行态与通知权限状态；告警页仍保留包名长度/格式校验、风险说明、白名单写入、AlertDialog 用户确认及 Android 系统卸载确认 Intent。
- 提交：
  - `d2c0aecaec9e34df43512826a58fddd2eeb4fed0` — 每日摘要页接入六 Tab。
  - `79c731cfba23304bcc8bd34418d56155c27759b6` — 安全告警页接入六 Tab。
  - `0785f9ccae93bace2d2d4b2c326ef17cbc58a2b2` — 扩展 `scripts/tests/fx-yulong-shield-six-tab-regression.sh`，增加两页 Manifest/宿主/数据源/确认卸载锚点断言。
- 静态验证：两个类共享壳安装点与旧根视图移除通过；每日摘要本地数据与后台服务状态锚点、告警页输入边界/白名单/用户确认/系统卸载锚点通过。未运行脚本、Gradle 编译、模拟器或真机权限/卸载验收。
- 下一步：审计其余 Shield/Ad 独立页是否全部从真实入口可达、返回栈是否回到正确父页；然后对六 Tab 与状态恢复做一次完整可运行测试。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — 最新 HEAD 同步与 Shield / Ad 页面宿主抽查

- 本次复核时 GitHub 最新 HEAD：`78c0a84ef523153767ea55f42727c46457077409`。最近提交包含并行工作线的 Dia ActivityKey validation policy 修复（`d52a2e19b0e921588da3d6a26d4bdab2a25f5b81`）；未覆盖该改动。
- 按当前 HEAD 对 Shield 12 个 Activity 与 Ad 7 个 Activity 做源码宿主抽查：全部均继承 `FxNativeTabActivity` 并调用 `setContentViewWithNativeTabs(root, 5)`；未发现仍裸用 Activity 根视图的页面。Shield 12 页包括 Hub、Scan、Integrity、Rescue、Batch Cleanup、Screen Filter、Virus Database、Daily Summary、Warning、Whitelist、Whitelist Picker、Blacklist；Ad 7 页包括主页、General、Summary、Stats、App Whitelist、DNS、Firewall。
- 本轮仅为源码静态核验，不能据此认定页面视觉、返回栈、业务后端或真机交互已验收。
- 本地资料库检查：当前 `/FX` 目录内实际存在并已完整读取《FX_1.0.0_UI优先自主推进与中断续接执行总指令.md》及《FX_1.0.0_UI优先提速与自主开工提示词.md》；用户指令中另两份《FX_1.0.0_项目接管总档_自主开发与查漏补缺.md》《FX_1.0.0_快速推进与主动修复执行档.md》在当前 `/FX` 目录清单中不存在，故无法读取，不以旧聊天内容冒充文件读取。
- 下一步：继续核对 Dia 页面实际路由/父子返回链与原始 Manifest 组件映射；优先处理跨 Activity 六 Tab 点击后的回跳一致性与页面恢复。之后进入 Hook UI 与主 Tab 的实际交互验收。固定 FX 1.0.0，不生成最终包。

## 2026-11-05 — 本轮接管补充：资料库可用文档与最新页面覆盖

- 本轮已完整读取资料库 /FX 中实际存在的两份 UI 开发文件：
  - FX_1.0.0_UI优先自主推进与中断续接执行总指令.md
  - FX_1.0.0_UI优先提速与自主开工提示词.md
- 对 /FX 执行目录列表核验后，以下两份用户要求的长期交接文件当前不在资料库清单中：FX_1.0.0_项目接管总档_自主开发与查漏补缺.md、FX_1.0.0_快速推进与主动修复执行档.md。已尝试按完整名称与简化标题搜索，仍无结果；不能声称已读取或以旧聊天替代文件内容。
- 当前真实分支 HEAD 以本节写入前实时读取为准：e421e9726559092cbf129171b586275fad115197。本轮页面代码继续按最新 HEAD 复核，没有使用旧 SHA 覆盖并行工作。
- 最新并行提交已将 Shield Daily Summary / Warning 接入六 Tab；其真实入口分别是 Hub → Daily Summary、Scan 结果 → Warning。回归脚本曾错误地把 Warning 归到 Hub，已在 ca55a6f6afa6b87a2004b9c69e67668dda75f89d 改为从 Scan 检查 Warning 路由。
- 目前源码静态核对的页面覆盖：Dia 已有 17 个独立 Activity 接入共享六 Tab 壳；Shield 已覆盖 Hub、Scan、Integrity、Rescue、Batch Cleanup、Screen Filter、Virus Database、Daily Summary、Warning、Whitelist、Whitelist Picker、Blacklist 等 12 个 Activity；Yulong Ad 主页面、General、Summary、Stats、App Whitelist、DNS、Firewall 等 7 个页面已有共享宿主记录。以上只代表源码接线，不代表视觉/设备验收或业务后端全部完成。
- 当前最重要的未完成项仍是：六 Tab 全页面实际回跳/返回栈设备验收；Dia 原始页面与 Manifest 全量映射；Hook 页面实际权限/注入状态；VPN/DNS/Hosts/隐私/脚本真实后端闭环；Shield 服务权限状态与批量清理回执。
- 下一批直接任务：核对 FxNativeTabActivity 对所有独立 Activity 的 Tab 回跳行为，确认 CLEAR_TOP | SINGLE_TOP 到 MainActivity 后实际选中请求 Tab；再核对 Activity Result/SAF 在旋转后的回传。优先源码可验证的导航状态，不启动整套 Actions。
- 未运行完整 Shell 回归、Gradle/JUnit、Android 编译、模拟器或真机导航；不生成 APK / KernelSU ZIP。


## 2026-11-05 — Shield 每日摘要返回栈与状态文本修正

- 本批前最新 HEAD：`a79e8798d335c9bb7578f0ffb89439576554b29b`；提交过程中未覆盖并行分支更新。
- 修复 `FxYulongDailySummaryActivity` 的“返回安全护盾首页”动作：由重新启动一个新的 `FxYulongShieldActivity` 改为结束摘要页并返回原调用者，避免 Hub 重复入栈、再次按返回键又回到摘要页。
- 修复后台服务、救援服务、名单监测、摇动/音量触发与通知权限状态之间的换行显示：将误写成字面 `\\n` 的分隔符改成实际换行转义 `\n`。
- 清理 `fx-yulong-shield-six-tab-regression.sh` Activity 映射中的重复 DailySummary / Warning 键；新增返回栈语义与换行格式断言。
- 提交：
  - `d281089df32679a7fa3e3cdfbc7f30d88e18f925` — 修复摘要页返回栈与实际换行。
  - `e421e9726559092cbf129171b586275fad115197` — 回归脚本覆盖返回语义、换行显示并清理重复映射键。
- 验证：已重新读取修改前文件并对修改后源码执行本轮静态断言（返回动作、五处换行、唯一映射键、回归断言）；未执行完整仓库 Shell 脚本、Gradle 编译、模拟器或真机导航。
- 下一步：继续检查 Shield 警告详情由服务/扫描打开时的任务栈与返回目标；随后核对三套迁移应用首页到深层页面的真实入口和取消/返回行为。固定 FX 1.0.0，不打包最终 APK / KernelSU ZIP。

## 2026-11-05 — 独立 Activity 六 Tab 回跳链静态契约补齐

- 本节更新前实时 HEAD：c58667777b6681701c32fa7af0aeb09464ed19ba。
- 核对共享宿主 FxNativeTabActivity：ComposeView 显式绑定 LifecycleOwner / ViewModelStoreOwner / SavedStateRegistryOwner；Tab 点击校验 0–5；通过 CLEAR_TOP | SINGLE_TOP 向 MainActivity 发送 fx_open_native_tab 后结束当前独立 Activity。
- 核对 MainActivity：onNewIntent 消费 native tab intent；handleImportedNativeTabIntent 限定 0–5；handleNativeTabSelection 对 0–3 更新 lastWebTabIndex 并 renderNativePage，对 4 返回 Hook 应用列表，对 5 返回 Settings。
- 更新 scripts/tests/fx-dia-native-tab-regression.sh：c58667777b6681701c32fa7af0aeb09464ed19ba，新增 MainActivity 六 Tab 分发和返回链断言，防止只检查底栏组件存在却遗漏真实路由。
- 当前 HEAD 文件级静态核验 9 项全部通过：三类 Compose 生命周期 owner、Tab 范围、CLEAR_TOP/SINGLE_TOP intent、MainActivity onNewIntent、intent 0–5 限制、Settings=6、Hook=5、前四 Tab 更新与渲染、回归脚本包含相应断言。
- 未运行 Shell 回归脚本、Gradle/JUnit、Android 编译、模拟器或真机点按；静态核验不等于实际返回栈验收。尚需真机验证：主 Activity 不在栈中时新建行为、深层 Activity 多次快速点 Tab、页面含未保存表单时切 Tab 的退出提示/草稿保存。
- 下一批：检查 Backup / SAF / GPS Picker 的 Activity Result 在旋转重建后的状态恢复；然后进入 Hook 首页与应用详情 UI 的真实权限状态闭环。固定 FX 1.0.0，不打包。


## 2026-11-05 — Dia Hook 的 Dialog / 通知 / Toast 原生入口拆分

- 本批开始前实时 HEAD：`4f6bab4b8804626e1ef8a00506662a6a9c7d448b`。
- 问题：Dia 的“Hook 功能”原页面目录只显示一个“对话框与通知”入口，但实际路由只打开 Dialog 过滤编辑器；Toast 文本过滤已有独立原生编辑器但不在 Dia 页面树中，通知监听与权限提示虽有现成逐应用配置控件也没有独立 Dia 入口。
- 修改 `MainActivity.java` 的 Dia Hook 功能目录，拆分为三个独立四级页面入口：
  - `对话框处理` → 既有 `showDiaDialogTarget`；
  - `通知监听与权限提示` → 既有逐应用 `通知保护` 配置与原生 Hook 发布路径；
  - `Toast 文本过滤` → 既有 `showDiaToastTarget`。
- 保留旧 `对话框与通知` 路由别名，避免恢复旧导航状态时断路；未复制或替换现有规则/发布后端。
- 提交：
  - `b0a7490e296c81dd0c4662d1db783b85f83b6886` — 增加独立 Dialog、通知与 Toast 页面入口和路由。
  - `1bfc59b45dc0d67f1f76d9a2ff5599e2787cd3a4` — Dia 原生页回归脚本增加三个入口及真实控件锚点断言，并清除重复 DEX Browser 测试条目。
- 验证：本批静态断言确认目录项、三条路由、Dialog/Toast 专用目标编辑器、通知两个真实配置键均存在；回归脚本内容已更新。未在完整工作树执行脚本，未运行 Gradle/Android 编译、UI 自动化或真机 Hook/通知行为。
- 下一步：检查 Dia 目录内其余 Hook/隐私入口是否出现同类“菜单命名与落地页面不一致”；之后回到 FX Hook 主 Tab 的首页/应用列表/应用详情状态闭环。固定 FX 1.0.0，不打包最终 APK / KernelSU ZIP。


## 2026-11-05 — Dia Dialog 页面未发布规则草稿恢复

- 本批起始实时 HEAD：`5306744c3c00366da927119b6291fddd50c01757`。
- 修复 `MainActivity.showDiaDialogTarget`：启用开关、文本关键词、资源 ID 规则、拦截提示开关分别写入独立 draft preference；页面重建/重新进入时优先恢复草稿，未发布输入不再被已发布值覆盖。
- 只有规则校验通过且正式配置 `commit()` 成功时才清理四个草稿键；校验失败或本地持久化失败时保留草稿。未改变 `FxDiaDialogMatchPolicy` 匹配规则、目标 debuggable 限制、空规则拒绝或发布路径。
- 提交：`56c5e586a7808483d6204521e55c45a9fc82cd55`（Dialog 草稿恢复实现）；`4493a0489d806bef2d4e7764b1da50d183550d28`（回归脚本检查四类草稿键、输入监听与成功后清理）。
- 静态验证：当前 HEAD 源码逐项确认四个草稿键、输入监听、恢复优先级、成功提交后清理和原规则解析路径均存在；回归脚本已增加相应断言。尚未在完整 checkout 中运行 Shell/Host 测试、Gradle、模拟器或真机旋转测试。
- 失败路线记录：本批没有发生代码更新冲突；以分支最新 HEAD 逐文件获取 SHA 后提交，未使用旧文件 SHA 覆盖并行修改。
- 下一步：同样审计 Dia 页面中其他未发布表单（ActivityKey、Wi-Fi 模拟、GPS 配对/代理配置）的草稿与旋转恢复；随后做统一页面状态恢复与跨 Activity 六 Tab 回跳测试。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — Dia Wi-Fi 环境模拟表单草稿恢复

- 本批起始实时 HEAD：`bbbbc0a4c40a1317416c063d4e107afa417bed5a`。
- 修复主 Hook 应用详情中的 Wi-Fi 环境模拟表单：SSID、BSSID 与启用开关各自持久化未发布草稿；页面重建/再次进入时优先恢复草稿，防止用户输入丢失。
- 保存时保留原 SSID UTF-8 字节数/字符限制、BSSID 格式校验及 debuggable 目标限制；改为同步 `commit()`，成功才清除草稿并调用 `publishConfig()`，存储失败时明确提示且不发布。
- 提交：`f9f4b15365938afbe723e3b7eb645683eed6ca04`（草稿恢复和原子保存）；`2aa9bc0a8eeff1e857020ec39bd63b6b6d1fee8b` 与 `5a17af62ba990b9c00cf8921c52b2b89c6e824ec`（回归脚本覆盖草稿恢复、输入监听、成功清理及失败处理）。
- 静态验证：当前 HEAD 重新读取 MainActivity 与回归脚本，确认三类草稿字段、实时监听、恢复、成功清理、失败不发布路径全部存在。尚未运行完整 Host/Shell 测试、Gradle、模拟器或真机旋转测试。
- 下一步：检查 GPS Picker / GPS 配对、Wi-Fi Proxy、备份/恢复页面的 Activity Result 与未提交表单恢复；再统一执行可用 Host 回归及跨页面六 Tab 返回链静态验证。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — Dia 系统 HTTP 代理表单草稿与失败回滚保护

- 本批起始实时 HEAD：`aa66b718cee4eab8b4c8899237835fce9c925cbc`。
- `FxDiaWifiProxyActivity` 的代理主机/端口现在独立保存非敏感草稿，重建后优先恢复；未保存的草稿不会被误当成当前已生效代理。密码/令牌不在该页持久化。
- 应用系统代理成功后，FX 本地所有权状态以同步 `commit()` 写入并清理草稿；若本地提交失败，执行条件回滚：仅当系统当前值仍等于 FX 刚写入的目标值时，才恢复此前系统代理，并核对回滚结果；检测到外部更改时不覆盖。
- 提交：`0aff802f3931276f0d6b08963f7ded25805f031c`（表单草稿与本地状态同步提交）；`526da0a1ea32e02027461b085e56a87da1ffbc7d`（本地状态提交失败时条件回滚）；`46af965d01f97d36d5093c139c40e3940a6b665d`（代理回归脚本增加草稿恢复、清理和失败回滚断言）。
- 静态验证：当前 HEAD 源码确认草稿恢复、输入监听、成功提交清理、条件回滚与冲突保护均存在；回归脚本包含对应断言。未执行 `fx-dia-wifi-proxy-regression.py`、Java Host 测试、Gradle、模拟器或 Root 真机验证。
- 下一步：继续审计备份页 SAF Activity Result 重建与临时文件清理，GPS Picker 状态恢复已存在 `onSaveInstanceState`，还需验证调用方 result contract；随后做一次可运行的 Dia Host 回归。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — Dia GPS 选点 Activity Result 旋转恢复

- 本批起始实时 HEAD：`32b0d5a5050a0db08bc550d9269f1e60c4212b51`。
- 修复 `MainActivity` 在高德 GPS Picker 打开期间发生 Activity 重建后丢失 `pendingDiaGpsTargetPackage` 的问题：现在在 `onSaveInstanceState` 写入 `fx_pending_dia_gps_target`，在 `onCreate` 恢复；原有 Activity Result 包名一致性校验保持不变，坐标仍只回写原始目标应用。
- 已核对 `FxDiaGpsPickerActivity` 自身保存/恢复配对输入、经纬度和状态文本；`FxDiaBackupActivity` 也已核对会在重建时恢复待导出暂存文件名，清理其他陈旧暂存文件，取消/失败时删除本次暂存文件。备份密码与 GitHub/WebDAV 凭据不写入状态或偏好，避免明文持久化。
- 提交：`829326a84c235924c5ff6f66c1c58820abaef767`（保存/恢复 GPS 目标包名）；`6f06af1dbd9cc1058b8934359884b2dbe251750f`（Dia 六 Tab 回归脚本检查目标包名状态与返回结果归属）。
- 静态验证：当前 HEAD 对主 Activity 的状态保存/恢复、Picker 状态字段、Activity Result 目标包名校验及回归断言全部通过。未运行 Shell/Python/Java Host 测试、Gradle、模拟器或真机旋转/SAF 结果验收。
- 下一步：完成一次集中 Dia Host 回归可运行性检查；随后转到 Hook 自定义规则页的草稿、导入导出与页面返回状态。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — Dia GPS Picker Activity Result 重建竞态补强

- 本批基于实时 HEAD `d502dd68f98b71b0b7da5e384ffbdac0caf7c52c` 继续；此前已提交的 `fx_pending_dia_gps_target` 状态保存/恢复保持不变。
- 发现并修复第二层时序问题：MainActivity 重建后通过异步应用列表恢复目标应用时，GPS Picker 的 Activity Result 可能先于列表加载完成返回。旧代码仅接受 `selectedPackage`，会把合法结果丢弃。
- 现在允许结果目标匹配 `selectedPackage` 或 `pendingRestorePackage`；若目标仍在异步恢复中，先写入该目标独立的 GPS 偏好，再由原有 app-list restore callback 打开目标，避免重复打开页面。原包名隔离、经纬度范围校验和“仅保存、需用户再次发布”行为不变。
- 提交：`3c458f1f30d04ab8ceed4a12e222c541ece6ac23`（处理异步恢复竞态）；`3617d84a64f8c8c9da9dfacccb74d4e2b39f0996`（回归脚本断言目标恢复期间接收结果且延迟打开目标）。
- 本批改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`；`scripts/tests/fx-dia-native-tab-regression.sh`；本状态文件。
- 验证：从当前 HEAD 重新读取源码和测试脚本，静态断言通过：pending target 保存/恢复、接受 pendingRestorePackage、延迟打开避免重复导航、测试覆盖均存在。未运行 Shell/Python/Java Host 测试、Gradle、模拟器或真机旋转与 SAF 交互。
- 失败路线：第一次基于旧 MainActivity blob SHA 更新时遇到 GitHub 409（并行提交已更新同一路径）；已重新读取分支最新 HEAD 和 blob SHA 后重放补丁成功。以后不得复用旧 SHA。
- 下一步：核对 MainActivity 的 SAF 导入/导出回调中暂存 payload 的重建恢复，特别是脚本 JSON 导出；随后进行 Dia 页面组一次针对性 Host 回归可运行性检查。固定 FX 1.0.0，不生成最终 APK / KernelSU ZIP。


## 2026-11-05 — FX Hook 应用列表搜索 / 分页 / 滚动状态恢复

- 本批起始 HEAD：`32b0d5a5050a0db08bc550d9269f1e60c4212b51`；期间并行分支推进到最新 HEAD 后，重新读取并确认修改已基于最新源码提交，没有强推或覆盖。
- 修复 Hook 应用列表状态丢失：
  - Bundle 保存/恢复搜索词（最大 256 字符）、列表滚动位置和已展开可见数量（限制 40–10000）。
  - 搜索词在创建 TextWatcher 之前恢复；用户修改搜索词时重置滚动位置与分页数量。
  - 点击应用进入 Hook 详情前记录当前列表状态；返回同一筛选类别时恢复搜索、分页和滚动位置；切换到不同类别则清空旧筛选上下文。
  - “加载更多”更新持久化可见数量；异步读取应用清单完成后恢复分页数量和滚动位置。
  - 滚动恢复回调检查当前 Hook 列表可见且 ScrollView 实例未变化，避免旧页面异步回调滚动到新页面。
  - `base()` 将实际 ScrollView 保存到 `nativeScroll`，使既有详情页按分类定位的 `focusPendingPrivacySection()` 使用真实滚动容器。
- 提交：
  - `2a9f9a1eb36952678476247cc3fac4c132243ee0` — `fix(hook): restore app list search paging and scroll state`。
  - `aa3462f0b44b0ba1ab367297d58ba993cebac1bf` — `test(hook): cover app list state restoration`。
- 静态验证：最新 HEAD 确认三个状态键、Bundle 保存/恢复、搜索恢复、分页恢复、滚动恢复实例保护和进入目标前状态捕获均存在；Dia 回归脚本包含对应断言。未执行完整 Shell 脚本、Gradle 编译、模拟器/真机旋转与多页实际点按测试。
- 并行接管：已保留并复核随后提交的 GPS Picker 目标包名在 MainActivity 重建后的恢复与结果归属检查（`829326a84c235924c5ff6f66c1c58820abaef767`、`6f06af1dbd9cc1058b8934359884b2dbe251750f`、`3c458f1f30d04ab8ceed4a12e222c541ece6ac23`），不重复覆盖。
- 下一步：检查 Hook 自定义规则页草稿、规则对话框、导入/导出、分组弹窗与 OBSERVE 日志页的返回状态；然后集中执行可运行的 Dia/Hook Host 回归。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — FX Hook 自定义规则编辑器与 JSON 导入草稿恢复

- 本批开始时分支 HEAD：`dbeaff3c30f40bcd0c5dfbb50cebf3b29a9af3d1`；开发期间分支出现并行提交，已重新读取最新 HEAD/文件 SHA 后重放变更，没有强推或覆盖。
- `MainActivity.showCustomRuleDialog`：新增规则和编辑既有规则时，分别按目标包名与编辑槽位保存草稿；保留规则 ID、语法类型、方法签名、动作、RETURN_LITERAL 常量、分组、优先级。仅当编辑草稿的原规则指纹匹配时恢复，避免把旧草稿套到已被外部修改的规则；正式规则 `commit()` 成功后才清除草稿，保存失败/取消时保留。
- `showCustomRuleImportDialog`：JSON 输入文本按目标应用独立保存并在重新打开时恢复；导入写入改为同步 `commit()`，成功后才清理导入草稿并显示成功，避免 `apply()` 异步写入失败时仍提示导入成功。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`；`scripts/tests/fx-dia-custom-hook-literal-regression.sh`；本状态文件。
- 提交：`6039e12f030086edbc26d21535f62a859ad4f689`（规则编辑草稿）；`8cf9e1d7e5fa37fbbf9e54fd6eff18e80662a3ba`（JSON 导入草稿与同步提交）；`c714074ad04464bf4a306386e1f66a23975dcc24`（回归断言）。并行提交后当前最新 HEAD 以本记录更新提交为准。
- 验证等级：从当前分支 HEAD 重新读取源码与回归脚本，静态确认编辑草稿身份/字段/监听/成功清理、导入草稿恢复/监听/同步提交及回归断言均存在。未在完整 checkout 执行该 Shell/Python 回归脚本，未运行 Gradle、UI 自动化、模拟器或真机旋转/导入操作。
- 失败路线：一次 GitHub Contents API 409，原因是并行提交更新了同一 `MainActivity.java`；按流程重新读取最新分支 HEAD 与文件 blob SHA 后重放成功。不要复用旧 SHA。
- 下一批：将 Hook 自定义规则编辑/导入对话框提升为可恢复的原生页面状态（含弹窗重建与返回链）；随后核对 OBSERVE 日志 Activity 的筛选/滚动状态与结果回跳。再集中运行 Dia/Hook Host 回归。固定 FX 1.0.0，不打包最终 APK / KernelSU ZIP。


## 2026-11-05 — Dia 脚本 SAF 导出载荷跨 Activity 重建

- 本批起始实时 HEAD：`17304ea5ec1b37c0763a3b3f2c584316f41adb0c`；提交期间有并行更新，均按最新 blob SHA 顺序重放，没有强推。
- 修复 MainActivity 脚本 JSON SAF 导出：完整 JSON 不再只存在 Activity 内存字段；先通过同步 SharedPreferences `commit()` 暂存，再启动 `ACTION_CREATE_DOCUMENT`。载荷上限 512 KiB，超过上限明确拒绝。
- `onSaveInstanceState` 保存待导出标记，`onCreate` 仅在标记与持久化载荷同时存在时恢复；没有有效恢复状态时清理孤立暂存数据。SAF 返回后从持久化载荷读取，成功写出后清理；取消、启动失败、写出失败也清理。避免把大 JSON 放进 Bundle。
- GPS Picker 同步补强：Activity Result 可在目标应用仍由异步列表恢复时接收，并延迟打开目标，避免合法坐标被丢弃或重复导航。
- 提交：`48e246ae2f557f51f971ebe241b797a62cce3144`（脚本 SAF 载荷持久化）；`8637887abb2288adcce7ac78467b27944a2d0dab`（清理孤立暂存）；`5b42462011cf119c2e4d8def4152c70209d3fffc`（回归断言）；`9e6c4937e68df9df1de92c7a4bcad5974f2b9e1f`（512 KiB 上限断言）。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`；`scripts/tests/fx-dia-native-tab-regression.sh`；本状态文件。
- 静态验证：当前 HEAD 重新读取源码和测试脚本，确认载荷同步持久化、512 KiB 上限、状态标记保存/恢复、取消/失败/成功清理、GPS 目标恢复竞态断言存在。未执行完整 Shell 脚本、Gradle/JUnit、模拟器或真机 SAF 交互。
- 失败路线：两次基于过期 MainActivity blob SHA 更新时遇到 409；均重新读取最新 HEAD 与 blob SHA 后仅重放缺失改动，没有覆盖并行提交。一次静态核验把文件大小常量误限定在方法代码片段内，已改为检查类常量本身并补上回归断言。
- 下一步：检查 Hook 自定义规则页的未提交编辑器草稿、导入/导出与返回链；随后执行 Dia 页面组 Host 测试可运行性检查。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — FX Hook 自定义规则筛选与滚动状态恢复

- 本批起始 HEAD：`dbeaff3c30f40bcd0c5dfbb50cebf3b29a9af3d1`；更新期间并行分支有推进，所有写入均基于重新读取的最新文件 SHA。
- 修复自定义 Hook 规则页重建后筛选条件与位置丢失：
  - 按当前目标应用保存分组筛选、搜索关键词（最多 256 字符）和纵向滚动位置。
  - Activity 重建后恢复三个状态；分组不存在时安全回退到“全部分组”，不会显示空白错误筛选。
  - 规则新增/编辑/导入/分组变更触发目标页重建时，先从当前 Spinner、EditText 与 ScrollView 捕获状态，再重建规则列表并恢复筛选和滚动。
  - 目标应用变化时清空上一目标的筛选，避免跨包复用 UI 状态。
  - 滚动恢复回调校验目标包与当前 ScrollView 实例，阻止旧页面异步回调影响新页面。
- 提交：
  - `67b61259ad25d26192b4972e8aff4b492d2dc792` — `fix(hook): restore custom rule filters and scroll state`。
  - `c6c23ace7c5ec7e95a34b1a7946b77d447e4e693` — `test(hook): cover custom rule filter and scroll restoration`。
- 静态验证：已检查三个 Bundle 状态键、保存/恢复路径、分组 Spinner 还原、搜索输入还原、编辑后重建捕获、滚动恢复以及目标/ScrollView 实例保护；回归脚本已加入对应断言。未执行完整 Shell 回归、Gradle 编译、UI 自动化或真机旋转与规则编辑测试。
- 未改变规则 schema、解析器、动作白名单、规则 ID 唯一性、发布协议、LSPosed 授权或目标进程注入语义。
- 下一步：检查规则新增/编辑和 JSON 导入弹窗在配置变化期间的未提交草稿保留；然后统一执行可用的 Hook/Dia Host 回归。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — FX Hook 自定义规则编辑/导入草稿与 OBSERVE 日志状态恢复

- 本批实时起点：`dbeaff3c30f40bcd0c5dfbb50cebf3b29a9af3d1`；最终代码和测试已重新核对到本记录提交的父 HEAD。
- 自定义规则编辑器（`MainActivity.showCustomRuleDialog`）：新增/编辑草稿按目标包名和槽位隔离，保存规则 ID、语法类型、方法签名、动作、RETURN_LITERAL 值、分组和优先级；编辑时校验原规则指纹；正式规则同步提交成功后清理草稿，取消/失败保留。
- JSON 导入对话框：按目标包名恢复未完成 JSON 输入；导入使用同步 `commit()`，仅成功后清除导入草稿并报告成功，不再以异步 `apply()` 的未核验结果提示成功。
- OBSERVE 日志原生 Activity：保存/恢复搜索词和日志 ScrollView 纵向位置；首次刷新渲染优先应用恢复位置，后续筛选/刷新尽量保持用户位置；保留原有 Root 读取限制、目标包精确筛选、日志输出上限及 Activity 销毁时取消 worker。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`；`adhook/app/src/main/java/de/privacyguard/adhook/FxHookObservationLogsActivity.java`；`scripts/tests/fx-dia-custom-hook-literal-regression.sh`；本状态文件。
- 提交：`6039e12f030086edbc26d21535f62a859ad4f689`（编辑草稿）；`8cf9e1d7e5fa37fbbf9e54fd6eff18e80662a3ba`（导入草稿/同步提交）；`c714074ad04464bf4a306386e1f66a23975dcc24`（编辑与导入回归断言）；`cea857d66ac5287c81a7c62501eb769d666e0eaa`、`80632e56d05209669f9b8f1125deb0bf84bdd369`（OBSERVE 搜索/滚动恢复）；`e954a5dee4c53e125681c6616ef076635ca537fa`（日志状态回归断言）。
- 验证等级：最新分支源码静态检查通过，确认编辑器七类字段、草稿身份校验、监听、成功后清理、JSON 导入草稿和同步提交、日志 Bundle 保存/恢复、首次 render 恢复及测试断言均存在。尚未在完整 checkout 运行 Shell/Python 回归，未运行 Gradle、UI 自动化、模拟器或真机旋转/编辑/导入操作。
- 失败路线：一次 GitHub Contents API 409，因并行提交更新了 MainActivity；重新读取最新 HEAD/blob SHA 后重放成功。后续继续避免复用旧 SHA。
- 下一步：将 Hook 编辑/导入弹窗的打开状态与未提交文本纳入 Activity 重建恢复；核对 OBSERVE 日志返回后目标 Hook 页面/筛选状态；随后集中执行 Hook/Dia Host 回归。固定 FX 1.0.0，不打包最终 APK / KernelSU ZIP。


## 2026-11-05 — FX Hook 规则编辑弹窗旋转恢复

- 本批起始 HEAD：`99eca521fe195b475604c37fe33df89e0c3086b5`；编辑期间分支多次前进，提交均以最新 HEAD 和文件 SHA 为准。
- 现状核对：规则编辑器此前已经把输入字段实时保存到按目标包/编辑槽隔离的 SharedPreferences 草稿（规则 ID、方法签名、动作、常量、分组、优先级、语法选择和动作选择），但 Activity 重建后只恢复规则页，没有重新打开此前可见的编辑弹窗。
- 修复：
  - Bundle 保存编辑弹窗是否打开、编辑槽和现有规则快照；规则快照长度超过 4096 字符时不自动恢复，避免异常状态数据。
  - Activity 重建并重新恢复目标应用自定义规则页后，自动重新打开同一新增/编辑弹窗；现有字段从原有按目标/编辑槽隔离的草稿键读取。
  - 用户明确取消、按返回/外部关闭或点击保存时清除“弹窗打开”标记；未提交的输入草稿不被自动提交，保留给用户再次手动打开编辑器恢复。
  - 不修改规则验证、目标包校验、动作白名单、签名冲突检查或原子提交语义。
- 提交：
  - `56bcee860cd6354d90a30a5d67e0958642b9bf29` — `fix(hook): reopen custom rule editor after recreation`。
  - `fff554492b88983e0616b7c18a2b283e8f8027aa` — `test(hook): cover custom rule dialog recreation`。
- 验证：最新源码静态检查确认打开状态/槽位/快照 Bundle 保存与恢复、恢复后自动打开、取消/关闭/保存清除标记、既有草稿身份键仍保留；回归脚本已加入断言。未执行完整 Shell 回归、Gradle 编译、模拟器/真机旋转与输入实测。
- 下一步：检查 JSON 导入弹窗是否也能保留未提交文本草稿；随后运行集中 Hook/Dia Host 回归并处理真实失败。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — FX Hook 自定义规则 JSON 导入失败回滚

- 本批起始实时 HEAD：`f466c9ad774f4c5fce856d166e31b69e8a36c698`。
- 修复 `showCustomRuleImportDialog` 的 SharedPreferences 提交失败处理：导入前快照当前目标包 64 个规则槽、base action、group、Hook 启用标志、分组集合及导入草稿；导入提交失败时先恢复原内存规则映射，再尝试同步回滚持久化。
- 用户可见错误现在区分“原规则已恢复”和“回滚写盘也未确认成功”；后一种情况明确要求不要退出应用并重新核对，不再笼统声称原有规则未变。
- 不改变规则语法、目标包映射、debuggable 替换限制、64 条上限、规则 ID 唯一性或发布协议。
- 提交：`9be657d5cf736069af94c391d94233b0eb9faf8a`（导入失败时恢复规则快照）；`42b27efbded2aac1182e41e77d8b21b2591c91b0`（Hook 原生 UI 回归脚本覆盖快照/回滚锚点）。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`；`scripts/tests/fx-hook-native-ui-regression.sh`；本状态文件。
- 静态验证：当前 HEAD 重新读取导入方法和回归脚本，确认规则槽/动作/分组/启用标记/导入草稿快照、失败回滚提交及用户提示均存在。未执行 Shell 回归、Gradle/JUnit、模拟器或真机存储故障注入。
- 失败路线：一次 MainActivity 更新因并行提交返回 409；重新获取最新 HEAD/blob SHA 后重放成功，没有覆盖并行的 Hook 观察日志和编辑器恢复提交。
- 下一步：核对自定义规则新增/编辑弹窗旋转时的草稿身份隔离与保存冲突；然后运行一次可执行的 Hook/Dia Host 回归（只读失败日志，不重复触发整套 Actions）。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — FX Hook JSON 导入弹窗重建与 OBSERVE 日志返回状态

- 本批起始分支 HEAD：`9e6c4937e68df9df1de92c7a4bcad5974f2b9e1f`；期间并行完成自定义规则编辑器弹窗重建和导入失败快照回滚，本批基于每次重新读取的最新文件 SHA 合并，保留了并行修改。
- JSON 导入弹窗：新增打开/待恢复状态，写入 Activity Bundle；目标应用自定义规则页恢复完成后自动重开导入弹窗，输入内容由此前新增的目标包级草稿恢复；取消、返回取消和提交时清理弹窗恢复标记。
- OBSERVE 日志页：保存/恢复搜索关键词和滚动位置；第一次异步刷新结果渲染也优先应用恢复位置，避免刷新先于滚动恢复时跳回顶部。保留原 Root 命令、目标包精确过滤、输出大小限制与 Activity 销毁时取消 worker。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`；`adhook/app/src/main/java/de/privacyguard/adhook/FxHookObservationLogsActivity.java`；`scripts/tests/fx-dia-custom-hook-literal-regression.sh`；本状态文件。
- 本批提交：`cea857d66ac5287c81a7c62501eb769d666e0eaa`、`80632e56d05209669f9b8f1125deb0bf84bdd369`（OBSERVE 日志状态恢复）；`e954a5dee4c53e125681c6616ef076635ca537fa`（日志状态回归）；`00c68b31361886fb174aaceec04a924080a9d0b2`（导入弹窗自动恢复）；`f7d0095a1b00e2be69f22b7fe4d4397421be307a`（导入弹窗恢复回归）。并行提交 `56bcee860cd6354d90a30a5d67e0958642b9bf29` / `fff554492b88983e0616b7c18a2b283e8f8027aa`（编辑器弹窗恢复）和 `9be657d5cf736069af94c391d94233b0eb9faf8a` / `42b27efbded2aac1182e41e77d8b21b2591c91b0`（导入失败快照回滚）均已保留。
- 验证等级：最新 HEAD 静态检查确认导入弹窗 Bundle 保存/恢复、目标页恢复后重开、取消/提交清标记、OBSERVE 搜索/滚动保存恢复和首轮 render 位置保护，以及对应回归断言均存在。未运行完整 Shell/Python 回归、Gradle、UI 自动化、模拟器或真机旋转/导入/Root 日志交互。
- 未解决：规则分组管理/重命名/移动等多级弹窗尚未统一做旋转恢复；导出弹窗可重新生成但复制交互未作旋转状态恢复。下一批先核对并修复分组对话框状态/持久化，再做 Hook/Dia Host 回归可运行性检查。固定 FX 1.0.0，不打包最终 APK / KernelSU ZIP。


## 2026-11-05 — FX Hook OBSERVE 日志页固定六 Tab 与导入回滚复核

- 本批开始时分支实时 HEAD：`f7d0095a1b00e2be69f22b7fe4d4397421be307a`。
- 将 `FxHookObservationLogsActivity` 从普通 `Activity` 改为 `FxNativeTabActivity`，通过 `setContentViewWithNativeTabs(root, 4)` 固定显示六 Tab 并选中 Hook；原有标题、返回按钮、目标包名、Root 日志读取/过滤、搜索、状态提示、搜索词与滚动恢复均保留。
- 回归脚本 `scripts/tests/fx-dia-custom-hook-literal-regression.sh` 增加日志页使用共享六 Tab 宿主、第五 Tab 和状态恢复锚点。导入失败回滚相关锚点位于独立 `scripts/tests/fx-hook-native-ui-regression.sh`，已复核其检查规则快照和 `rollback.commit()`；未重复把相同断言复制到错误的测试脚本。
- 本批关联提交：
  - `f466c9ad774f4c5fce856d166e31b69e8a36c698` — `feat(hook): keep observation log viewer in six-tab shell`。
  - `b08ce2fe6c24667d97706062a5514b3e92b30471` — `test(hook): require six-tab shell for observation logs`。
  - 同期并行工作线：`9be657d5cf736069af94c391d94233b0eb9faf8a` 修复 JSON 导入提交失败时恢复原规则；`42b27efbded2aac1182e41e77d8b21b2591c91b0` 在 `fx-hook-native-ui-regression.sh` 加入快照/回滚检查。
- 静态核验：最新源码确认日志页继承共享宿主、选中索引 4、保留返回动作和 Root 日志通路；确认导入前规则状态快照和失败回滚提交；两套回归脚本分别覆盖日志宿主/状态恢复与导入回滚。未在完整 checkout 运行脚本，未运行 Gradle/Android 编译、模拟器、UI 自动化或真机日志/故障注入验证。
- 下一步：继续检查自定义 Hook 规则分组新增/重命名/删除/移动后筛选与滚动恢复；随后集中评估 Hook/Dia Host 回归脚本能否在当前仓库测试链路直接运行。固定 FX 1.0.0，不提前打包最终 APK / KernelSU ZIP。


## 2026-11-05 — FX Hook JSON 导入草稿生命周期与输入上限

- 本批起始 HEAD：`00c68b31361886fb174aaceec04a924080a9d0b2`。重新读取后确认 JSON 导入弹窗的打开状态/草稿恢复已由并行工作线实现：Activity state 保存打开标记；自定义规则页恢复后重开导入弹窗；文本草稿使用目标包隔离的 SharedPreferences 键，明确取消不导入，成功提交后清除草稿。
- 本批针对发现的无界输入问题补齐限制：
  - 导入多行文本框限制最多 16,384 个 UTF-16 字符，避免任意大粘贴内容被每次输入变更复制进 SharedPreferences。
  - JSON 验证入口再检查 UTF-8 编码长度，超过 64 KiB 时明确拒绝，提示用户拆分导入。
  - 保留原有 JSON 格式版本、来源包校验、目标包描述符重映射、规则 ID 唯一性、动作 allowlist、最大 64 条规则、原子提交与失败回滚。
- 提交：
  - `574a9863b6ccd51def47f5a962033ac076ab32ac` — `fix(hook): bound custom rule JSON import drafts`。
  - `d4fdcfeef552f2805fcb63db6d3dd80ea9098e92` — `test(hook): cover bounded custom rule JSON drafts`。
- 静态验证：确认文本长度过滤、UTF-8 字节数拒绝路径、目标包隔离草稿写入及回归断言；未运行 Shell/Java Host 测试、Gradle、模拟器或真机输入/旋转测试。
- 下一步：复核 Hook 规则编辑器与 JSON 导入恢复合并后的状态路径；然后尝试运行集中 Host 回归（只运行本批所需测试，不重复整套 Actions）。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — FX Hook 规则分组新增/重命名/移动的草稿与持久化

- 本批实时起点：`574a9863b6ccd51def47f5a962033ac076ab32ac`；以最新 HEAD/blob SHA 写入，保留同期 JSON 导入 16,384 字符草稿上限和 64 KiB UTF-8 校验提交。
- 规则分组新增、重命名输入分别按当前目标包保存草稿；Activity 重建时根据 Bundle 恢复正在编辑的分组对话框，并从偏好恢复文本。取消/返回取消只清除弹窗恢复标记，不误清除用户尚未保存的文字。
- 分组新增从异步 `apply()` 改为同步 `commit()` 并检查结果；只有提交成功才提示创建成功。分组重命名沿用原子 `commit()`；规则移动到其他分组也改为同步提交，失败时提示且不重建页面。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`；`scripts/tests/fx-dia-custom-hook-literal-regression.sh`；本状态文件。
- 提交：`1e1fdf3c9053ed1b60b45cc9db840d14a91a1ac7`（分组草稿/同步保存）；`79a10d0842ba966b769031cf10fc0a5ebccfefe8`（新增/重命名/移动回归断言）。
- 验证等级：从最新 HEAD 重新读取 MainActivity 与回归脚本，静态确认新增/重命名状态保存恢复、输入草稿、同步新增提交、重命名提交、移动提交和测试断言存在；未运行完整 Shell/Python 脚本、Gradle、模拟器或真机旋转/存储故障测试。
- 未完成：规则组列表/动作/删除确认/移动选择器自身尚未完整保存弹窗层级与选中项；新增/重命名文本输入过滤尚未做 UI 交互验证。下一批继续完成剩余分组弹窗恢复，再做 Hook/Dia Host 回归可运行性检查。固定 FX 1.0.0，不打包最终 APK / KernelSU ZIP。


## 2026-11-05 — FX Hook 规则分组弹窗层级恢复与事务回滚

- 本批起始 HEAD：`99e7452621a0f1dbda39561c04b152f4dd24b0cb`；期间有并行 Hook 变更，已在最新 MainActivity 上顺序整合。
- 规则分组管理列表、分组动作、删除确认和规则移动选择器均记录 Bundle 状态；重建后按原弹窗层级重开。移动选择器另外保存/恢复当前选中项和目标规则槽位，分组列表变化时将选中索引限制在有效范围。
- 分组新增、重命名输入草稿按目标包隔离并可恢复；新增/重命名/移动均通过统一 `commitCustomRuleGroupUpdate` 事务写入。该事务在 SharedPreferences commit 失败时恢复原分组集合和逐规则分组映射，并再次同步提交回滚；页面区分分组冲突与本地写入/回滚失败，避免显示未经确认的成功状态。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`；`scripts/tests/fx-dia-custom-hook-literal-regression.sh`；本状态文件。
- 提交：`1e1fdf3c9053ed1b60b45cc9db840d14a91a1ac7`（分组草稿/初始同步写入）；`9afea97346485793816e41985ab2b3f3d779681c`（分组弹窗/选择器状态恢复）；`c23124dbb81f621c327d3ffb7e306f68f616178d`（事务失败回滚）；`aa615e5feeaa5ed0375a40e64ba04dcc5bb234d3`（冲突与写入失败状态区分）；`d1def1b6e0f1ddeb09933c8d6543c008fd03d8bd`、`f23781e7ebb702554219fa2b5745fceea91a9bef`（分组弹窗/事务回归断言）。
- 验证等级：最新 HEAD 静态检查确认 Bundle mode/value/slot/choice、列表/actions/delete/picker 恢复分支、选择索引恢复、目标包草稿、统一事务 commit 与失败回滚路径及测试断言存在。未运行完整 Shell/Python 回归、Gradle、UI 自动化、模拟器或真机旋转/写盘故障注入。
- 失败路线：一次测试断言仍检查旧的直接 `putString().commit()`，而并行实现已统一到 `commitCustomRuleGroupUpdate`；已根据实际源码契约更新断言，不改变产品逻辑。没有重复触发完整 Actions。
- 下一步：核对分组新增/重命名输入长度过滤与删除/移动冲突提示；随后在可用环境执行 Hook/Dia Host 回归脚本并读取具体失败日志。固定 FX 1.0.0，不打包最终 APK / KernelSU ZIP。


## 2026-11-05 — FX Hook 规则分组名称输入边界

- 在新增/重命名分组的原生 EditText 上添加 24 字符长度过滤器，与现有 `validCustomRuleGroupName` 校验上限一致；目标包级草稿恢复仍然生效，超长输入不会持续写入偏好。
- 回归脚本增加新增与重命名两个输入框的长度过滤断言。
- 提交：`cebf81ff65f0ed7005fbe8dc32999e42b5f33df5`（输入过滤）；`811ebbc1839c3e28bef5a56126a06e349b188e1b`、`d4913ae9bada8fd4d513f751ae673a4e63c1ea63`（回归断言及结果提示）。
- 验证：最新 HEAD 静态确认两个编辑框均有 24 字符限制，现有规则分组事务/回滚和 Bundle 恢复保持存在；未运行完整 Shell 回归或 Android UI/真机输入测试。
- 下一步：检查 Hook 自定义规则/分组相关脚本的 Host 测试执行入口与可用性，修复测试实际失败而非继续堆叠静态断言；之后转向 Hook 页面真实状态/权限显示或下一组 UI。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — Hook 规则分组事务回滚与输入边界补齐

- 本批接管时最新分支 HEAD：1e1fdf3c9053ed1b60b45cc9db840d14a91a1ac7；当前续接依据已跟随分支并行提交更新。
- 复核此前并行完成的分组对话框恢复后，发现分组新增/重命名/删除/移动的 SharedPreferences 写入虽集中在单次 Editor，却缺少失败后的显式旧值恢复；并统一补齐：
  - 新增 commitCustomRuleGroupUpdate，同时更新分组集合和受影响的逐规则分组键。
  - 保存前快照旧分组集合、受影响映射键是否存在及其旧值；初次 commit 失败时恢复内存值并再次同步提交回滚。
  - 分别记录回滚提交是否成功；若保存失败，区分“原值已回滚”和“保存/回滚均未确认”，避免显示假成功。
  - 新增、重命名、删除和移动四条路径均改走同一事务 helper；重命名名称重复等写盘前拒绝与真实提交失败分开提示。
- 分组弹窗恢复复核：列表、动作、删除确认、添加/重命名输入与规则移动选择器均可按 Bundle 恢复；移动选择器保存目标规则槽位和暂存选项。输入草稿按目标包/分组键持久化，取消不提交。
- 新增/重命名输入由并行提交加入 24 字符 LengthFilter；本批扩展 fx-hook-native-ui-regression.sh，明确断言两个输入均应用相同长度上限。
- 提交：
  - c23124dbb81f621c327d3ffb7e306f68f616178d — 失败时恢复原分组集合和规则映射。
  - aa615e5feeaa5ed0375a40e64ba04dcc5bb234d3 — 区分重命名冲突与事务失败提示。
  - 9afea97346485793816e41985ab2b3f3d779681c — 分组层级和移动选择器状态恢复。
  - cebf81ff65f0ed7005fbe8dc32999e42b5f33df5 — 新增/重命名输入 24 字符限制。
  - d231eecbd2ca1a3644f9674b8532266690adbe4a — 回归脚本覆盖分组事务、层级恢复和输入长度上限。
- 静态验证：最新源码确认统一 helper 的旧值快照、回滚 commit、四条调用路径、分组弹窗状态恢复、选择器 slot/choice 恢复以及两个 24 字符过滤器；回归脚本包含对应静态断言。未执行 Shell 脚本、Gradle、模拟器/真机旋转或 SharedPreferences 故障注入。
- 下一步：集中核对 Hook/Dia 的 Host 测试脚本与仓库可运行测试入口，确认哪些可在当前 Actions 结果中读取、哪些必须在有完整工作树的环境运行；不重复启动整套 Actions。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — FX Hook 自定义规则编辑器输入边界

- 本批起始 HEAD：`811ebbc1839c3e28bef5a56126a06e349b188e1b`。
- 自定义规则编辑器原先已有目标包/编辑槽隔离的 SharedPreferences 草稿自动保存、Activity 重建恢复和提交成功清理，但输入框没有应用与解析器一致的最大长度限制，粘贴极长文本会在每次 TextWatcher 事件中持续写入草稿。
- 修改 `MainActivity.showCustomRuleDialog`，对编辑器字段加入硬输入上限：
  - 规则 ID：32 字符（匹配 DeveloperHookRule 的 1–32 字符 ID 约束）。
  - Java/Frida/Smali 方法描述符：512 字符（匹配描述符规范化器上限）。
  - RETURN_LITERAL 值：256 字符（匹配字面值解析器上限；字符串 UTF-8 字节限制仍由解析器继续校验）。
  - 分组名称：24 字符（匹配分组校验）。
  - 优先级：5 字符（足以输入 -1000 至 1000 的有效范围，数值范围仍由规则解析器校验）。
- 保留现有草稿 identity、字段恢复、文本变更自动保存、取消保留草稿、验证/原子 commit 以及成功提交清理；没有更改规则动作白名单、签名解析、目标包隔离或发布语义。
- 提交：
  - `e8788db45a430cb055a5b2ea168447434a9a78e0` — `fix(hook): bound custom rule editor draft fields`。
  - `8a01389a36ec22c8408ecdf6bc36297c59ed41e6` — `test(hook): enforce custom rule editor input bounds`。
- 最新 HEAD 静态复核：五项 InputFilter 上限、编辑器草稿保存/清理及原规则解析调用均通过源码断言；回归脚本包含五项上限断言。未运行 `fx-dia-custom-hook-literal-regression.sh`、Gradle/Android 编译或设备旋转/输入测试。当前容器无法解析 github.com，因此未在本地完整 checkout 执行脚本。
- 下一步：继续核对自定义规则新增/编辑提交后分组筛选与滚动定位是否稳定，之后检查日志页返回后 Hook 目标页的实例/视图状态；尝试通过已有仓库 CI 状态读取可用的测试结果，但不触发整套 Actions。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — Hook 移动规则选择器新增分组后的返回链修复

- 本批代码提交基于最新 MainActivity blob SHA；期间实时文档发生并行更新，第一次文档写入因 expected SHA 过期返回 409，已重新读取最新文档后仅追加本批记录，未覆盖并行内容。
- 修复四级交互断链：在规则“移动分组”选择器中点击“新增分组”后，原逻辑会转去普通分组管理消息页，导致用户丢失当前目标规则槽位和选择器上下文。
- 新增目标包内存状态标记 `customRuleGroupReturnToPicker`，并写入/恢复 Bundle。通过移动选择器打开“新增分组”时保留原规则槽位与当前选择索引；新增成功后重新打开原移动选择器，并优先选中新建分组；取消/外部关闭也回到原选择器；名称无效或写入失败时，重试入口保留原选择器上下文与草稿。
- 普通分组管理列表打开新增分组时仍使用原管理流程，不误导向移动选择器。分组提交继续沿用既有同步提交/失败回滚事务，不改变规则 schema 或发布协议。
- 提交：
  - `efca312d39bb1505af2298f9212667cecb20995c` — `fix(hook): return to rule picker after adding a group`。
  - `474749b65b61f96ebddf6a03664aadab17ec3397` — `test(hook): cover new group return to move picker`。
- 源码静态验证：重新读取当前 HEAD 后确认返回标记声明、Bundle 保存/恢复、选择器新增入口、取消回跳、新分组索引选择、失败重试上下文均存在；`scripts/tests/fx-hook-native-ui-regression.sh` 包含对应断言。未在完整 checkout 执行 Shell 脚本，未运行 Gradle、模拟器、UI 自动化或真机旋转/写盘故障注入。
- 下一步：运行可用的 Hook Native UI 回归（若当前没有完整 checkout，则先核对 Host 测试依赖与可运行入口）；随后进入 Hook 目标页 Root/LSPosed/Accessibility 实际状态显示和授权回读闭环。固定 FX 1.0.0，不提前打包最终 APK / KernelSU ZIP。


## 2026-11-05 — Dia Frida 脚本库页面状态恢复

- `FxDiaScriptLibraryActivity` 现在保存/恢复脚本名称搜索词和列表滚动位置；异步脚本库重载完成并重新渲染列表后再恢复滚动，避免先恢复空列表位置造成跳回顶部。
- 修复 `open_new_script` 一次性入口在 Activity 重建时从原始 Intent 重复读取的问题：初始新建请求现在以 Bundle 状态为准，已消费后保存为 false，避免从编辑器返回时再次弹出新建对话框。
- 保留当前编辑脚本名称，确保编辑器 Activity Result 返回时仍能关联原脚本；SAF 导入/导出仍走原系统文档选择器和既有大小/校验限制。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaScriptLibraryActivity.java`；`scripts/tests/fx-dia-frida-script-library-saf-regression.sh`；本状态文件。
- 验证等级：源码静态确认搜索/滚动保存恢复、异步重载后恢复位置、初始新建意图消费状态和编辑器回传名称均存在；回归脚本增加对应断言。未运行 Shell/Python 回归、Gradle、UI 自动化、模拟器或真机 SAF/旋转交互。
- 下一步：检查 Frida 管理主页面的脚本编辑器草稿、目标/脚本导航返回和多个 SAF request 的重建恢复；随后执行 Dia Frida 页面组针对性 Host 回归。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — Hook Root 授权检查并发竞态保护

- 本批开始时最新 HEAD：`651b4b1163c9dd1a74dd50698843af5003e460c1`。
- 发现 Hook 授权首页的“刷新 Root 状态”“申请/重新检查 Root”和组合刷新都直接创建独立线程；快速连续刷新时，较慢的旧 `su` 结果可能在新结果之后抵达并覆盖界面，造成 Root/模块状态倒退。
- 修复 `MainActivity.checkRoot`：
  - 每次请求递增 `hookRootCheckGeneration`，记录当前 Root 检查线程。
  - 新请求启动前中断前一个 Root 检查线程；`RootAccess.execute` 已处理 `InterruptedException` 并尽力终止/回收当前 `su` 客户端。
  - UI 回调只有在请求代次仍是最新、Activity 未销毁、目标 TextView 仍附着时才能更新 Root 状态或调用后续回调。
  - Activity 销毁时递增代次、清空线程引用并中断正在运行的 Root 检查，阻止旧页面回调。
  - 不改变 Root UID、FX 模块路径与 id 校验、1.0.0 版本检查、disable/remove 标志、KSU 工具存在性判断和权限拒绝提示。
- 提交：
  - `e91e8cd18911b43b3fe0e38a3f6b1a656b7ed4d1` — `fix(hook): ignore stale Root authorization checks`。
  - `2a53917ef0911a0528c9690d5cc47ff7424b55bb` — `test(hook): cover Root authorization request generations`。
- 同批已落地移动规则选择器新增分组返回链修复：
  - `efca312d39bb1505af2298f9212667cecb20995c` — 新分组成功后返回原选择器并选中新组，取消/旋转/重试保留槽位与选择上下文。
  - `474749b65b61f96ebddf6a03664aadab17ec3397` — 回归断言。
- 静态验证：最新 MainActivity 与 `fx-hook-native-ui-regression.sh` 确认 Root 请求代次、旧线程中断、过时代次丢弃、Activity 销毁取消和分组返回链锚点均存在。未执行完整 Shell/Python 回归、Gradle 编译、Android UI 自动化、模拟器、Root 权限/竞态故障注入或真机验证。
- 下一步：检查逐应用 LSPosed 作用域刷新请求是否也存在过期回调覆盖、请求超时后状态悬挂；然后核对三种授权（Root/LSPosed/Accessibility）在 Hook Hub 与目标详情页的状态文案一致性。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — Hook LSPosed 作用域异步回调过期保护

- 本批起始实时 HEAD：`78567966113edd224be56e9a566483a982b5a52d`；编辑期间并行工作线推进，已基于更新后的 MainActivity SHA 顺序重放，保留并行提交。
- 发现目标应用页的 LSPosed 作用域申请和移除回调没有与页面/目标包绑定：用户切换目标、离开页面或触发更新的状态刷新后，较晚返回的 Binder 回调仍可能覆盖旧 TextView；移除线程也不是 daemon。
- 修改 `MainActivity.java`：
  - 申请、移除操作启动时递增共享 `hookTargetScopeGeneration`，回调只在代次仍有效时更新 UI。
  - 新增 `isCurrentHookScopeOperation`，同时检查 Activity 生命周期、代次、当前 TextView 实例、当前目标包、选中包和 View 附着状态。
  - 申请成功/失败、移除成功/失败以及同步异常均使用同一有效性检查；申请成功后再触发最新状态读取。
  - 移除工作线程设为 daemon，避免页面关闭后非关键线程滞留进程。
  - 旧状态读取本身已有代次/目标包/View 检查，继续保留；不把作用域批准误报成目标进程已注入。
- 提交：
  - `06a64f5fc5a06fbe52832e617bb61d0b332b23bf` — `fix(hook): ignore stale LSPosed scope operation callbacks`。
  - `bdf289305edea28d6d5c1eb370a85894abc08912` — `test(hook): cover stale LSPosed scope callbacks`。
- 验证等级：从最新分支读取 MainActivity 和 Hook Native UI 回归脚本；静态断言确认请求/移除回调代次保护、目标包与 View 实例校验、daemon worker，以及测试脚本新增断言。未执行 Shell 回归、Gradle 编译、LSPosed Binder 真机批准/移除或页面切换竞态测试。
- 未完成：仍需检查 Hook Hub 的 Remote Files 状态刷新和 Accessibility 状态刷新是否存在旧页面回调；随后优先进入 UI 页面覆盖率更高的 Dia Frida 管理主页面/编辑器批次，而不是继续无止境修边缘状态。固定 FX 1.0.0，不打包最终 APK / KernelSU ZIP。


## 2026-11-05 — Dia Frida 管理页滚动位置恢复

- 本批起始 HEAD：`d25dbc4e4104570fc2265c11388a2e537aceb3fe`。
- Frida 管理页已经保存工具路径、脚本草稿、目标包和进程选择，但主页面 ScrollView 是局部变量，Activity 重建后滚动位置丢失；页面很长，用户在 Gadget/进程/脚本/监控模板区域操作时会被送回顶部。
- 修改 `FxDiaFridaActivity.java`：
  - 将 ScrollView 保存在 Activity 的 `pageScroll` 字段。
  - Bundle 保存滚动 Y 值；创建完整页面并恢复瞬态表单状态后，再 post 恢复滚动位置。
  - 恢复回调验证 Activity 未销毁、当前 ScrollView 实例仍一致且仍附着，避免过期回调影响其他页面。
  - 保留目标包 debuggable/非系统校验、PID 重新校验、脚本 48 KiB 限制、导入/导出 SAF 与 Gadget 生命周期逻辑。
- 提交：
  - `2881ba552415b2b3a5da5550e34fb6fe28767aa0` — `fix(dia): restore Frida manager page scroll position`。
  - `8bc15023fa5da276363e2d3d9efacb12dd126f49` — `test(dia): cover Frida manager scroll restoration`。
- 验证等级：源码静态断言确认滚动容器引用、Bundle 保存、页面创建后恢复和实例/附着保护；`fx-dia-frida-page-navigation-regression.sh` 增加相应断言。未在完整工作树运行 Shell/Python 回归、Gradle、模拟器或真机旋转/滚动测试。
- 并行已保留：同一阶段 Hook LSPosed 作用域申请/移除过期回调保护提交 `06a64f5fc5a06fbe52832e617bb61d0b332b23bf` 与测试 `bdf289305edea28d6d5c1eb370a85894abc08912`；状态文档此前记录提交 `b3d02e3a820ca08034a09ab2f4008fda3c3d8cc4`。
- 下一批：检查 Dia Frida 脚本库与全屏编辑器之间的草稿/名称/取消返回闭环，以及 Frida 管理页当前脚本是否在打开脚本库、编辑器后按预期恢复；优先补完整用户可见编辑流程。固定 FX 1.0.0，不打包最终 APK / KernelSU ZIP。


## 2026-11-05 — Dia Frida 脚本库新建弹窗草稿/旋转恢复

- 本批起始 HEAD：`a8f9e3feabadeed07d0c9cba1d35d93b1362efda`。
- 发现脚本库“新建脚本”弹窗没有生命周期状态：输入名称后旋转/Activity 重建会丢失草稿；从外部入口自动打开新建弹窗时，重建期间也不能可靠恢复当前输入。
- 修改 `FxDiaScriptLibraryActivity.java`：
  - 保存新建弹窗是否待恢复，以及脚本名称草稿；Activity 重建后先异步重载脚本库，再恢复原弹窗和输入。
  - 名称输入限制 64 字符，与 `FxDiaScriptLibraryPolicy` 校验一致。
  - 显式取消/提交后清除弹窗恢复状态；配置变更触发的 Dialog cancel 不清除草稿。
  - 保留初始 `open_new_script` 意图消费、编辑器回传目标名称、脚本库搜索和滚动恢复、JSON SAF 导入/导出逻辑。
- 提交：
  - `e3e973e70835ad4b21e3261cbcbe234c403e5de0` — `fix(dia): restore Frida script create dialog draft`。
  - `9517b39b7fed6d09b5f44e66b74bd834061c62c7` — `test(dia): cover Frida script create dialog restoration`。
- 验证等级：源码静态断言确认弹窗 pending 状态、名称草稿 Bundle 保存/恢复、异步 reload 后重开、64 字符限制及配置变更取消保护；`fx-dia-frida-script-library-saf-regression.sh` 增加对应断言。未执行 Shell/Python 回归、Gradle、模拟器或真机旋转/编辑器回传。
- 下一步：Frida 主页面“保存脚本到库”名称弹窗仍需同样的草稿恢复/输入上限核对；之后把 Frida 管理页、脚本库、全屏编辑器的返回链作为一个页面组做一次 Host 回归。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — Hook 自定义规则 CRUD 后保持原生管理页

- 本批起始 HEAD：`a8f9e3feabadeed07d0c9cba1d35d93b1362efda`。
- 复核确认：自定义 Hook 规则页本来已有分组筛选、搜索、滚动位置、编辑器草稿和 Activity 重建恢复字段；本批没有重复实现已有能力。
- 实际导航缺陷：规则新增/编辑成功、规则删除、分组重命名/删除、规则移动分组成功后调用 `showTarget(target)`，会把用户从自定义规则管理页踢回普通应用 Hook 配置页。
- 修复：五条 CRUD/分组刷新路径改为 `showCustomHookRulesPage(target, targetDebuggable)`，保留同一目标的规则管理上下文；页面入口原有 `captureCustomHookRuleFilters()` 继续保存分组、搜索和滚动状态。显式“返回”仍走 `leaveCustomHookRulesPage()`，返回目标不变。
- 提交：
  - `bfa0d8f9b0b5320b4c62c934e8284e76468ae592` — `fix(hook): keep custom rule manager open after edits`。
  - `5ea20984f647c86fd04987af29f0a9e28e58b63a` — `test(hook): cover custom rule manager refresh navigation`。
- 验证：静态核对五条 CRUD/分组刷新路径均回到自定义规则管理页；回归脚本增加分组/规则刷新、保存后停留、删除后停留、显式返回断言。尚未执行完整 Shell/Python 回归、Gradle 编译或 Android 真机操作。
- 未完成/风险：JSON 导入成功后的页面停留、OBSERVE 日志 Activity 返回后的目标包/筛选上下文仍需单独实测；分组弹窗层级及编辑器验证失败时草稿保留仍需 UI 自动化/真机检查。
- 下一步：检查 Hook 目标详情页的 Hook 开关、LSPosed 作用域/权限状态刷新是否丢失详情滚动位置；随后运行针对性回归。固定 FX 1.0.0，不打包最终 APK / KernelSU ZIP。


## 2026-11-05 — Dia Frida 主页面“保存到脚本库”名称弹窗恢复

- 本批起始 HEAD：`a709aa0d65f1d451542d2ad1825a51028250c863`。
- 与脚本库新建弹窗相同，Frida 管理主页面的“保存到 Frida 脚本库”名称对话框此前没有草稿恢复；旋转会丢失输入名称。
- 修改 `FxDiaFridaActivity.java`：
  - Bundle 保存待恢复标记与脚本名称草稿；主页面创建并恢复原脚本后重新打开名称弹窗。
  - 输入框增加 64 字符限制，和脚本库命名策略一致。
  - 显式取消/保存后清除恢复标记；配置变更期间 Dialog cancel 不清除草稿。
  - 保留脚本内容 128 KiB 限制、脚本库原子存储入口和“保存不自动注入”语义。
- 提交：
  - `33e05a8bbbe6998b9cd3a951c82a64698f6283a1` — `fix(dia): restore Frida save-script dialog draft`。
  - `d334b41dfc2a4a058e8396f3696776a02a531976` — `test(dia): cover Frida save-script dialog restoration`。
- 验证等级：源码静态断言确认 Dialog pending/name Bundle 状态、恢复后重开、64 字符过滤和旋转期间取消保护；`fx-dia-frida-page-navigation-regression.sh` 增加对应断言。未运行 Shell/Python 回归、Gradle、模拟器或真机旋转/保存流程。
- 下一步：完成 Frida 管理页与脚本库/全屏编辑器返回链的一次集中 Host 回归，随后优先推进 Dia 其余原生页面映射，不继续把主工时消耗在弹窗边缘问题。固定 FX 1.0.0，不打包最终 APK / KernelSU ZIP。


## 2026-11-05 — API-101 位置隐私专用控件迁移检查误报修复

- 本批起始 HEAD：`67aaf8a13e76b358241c89d9752050aa83059dcc`；提交期间持续重读指定分支，未使用旧聊天 SHA 强推。
- CI 真实失败：Actions run `41904329514` 在 “Restore module sources, merge Hook entrypoints, and stage WebUI” 阶段退出，错误为 `API-101 privacy migration incomplete; missing fields: location_access_block native UI toggle`。后续 run `41905085852`、`41905215804` 因分支继续推进被自动取消，不能当作成功验收。
- 根因不是功能缺失，而是迁移脚本 `fx-patches/patch_hook_privacy_controls.py` 将位置访问控件硬编码成通用 `toggle(...)` 文本。实际 `MainActivity` 使用独立 `addLocationAccessBlockToggle(locationConflictStatus)`，它具备：
  - “限制位置访问”原生 Switch；
  - 目标包隔离的 `location_access_block` SharedPreferences 键；
  - 同步 `commit()`，提交失败恢复 UI 原值；
  - 打开位置阻断时拒绝已有 GPS 坐标/服务模拟；
  - 保存 GPS 模拟时反向拒绝已启用的位置访问阻断。
- 修复 `patch_hook_privacy_controls.py`：新增 `has_conflict_aware_location_control(source)`，按真实方法边界识别专用控件；在迁移完成判定和最终 postcondition 都接受此受保护控件，不再要求不适用的 generic `toggle()`。同时严格验证本地两个互斥方向、包级存储及同步提交。修复了 helper 方法边界查找的转义层级，避免把字面 `\\n` 当作代码换行。
- 扩展 `scripts/tests/fx-app-webui-migration-regression.sh`：验证专用控件挂载、方法、标签、包级保存、同步提交、GPS 双向冲突保护、迁移器方法边界和识别契约。
- 提交：
  - `60399161c08e4c4f4c423865581c8b1af15f6deb` — 初次迁移识别调整；后续检查发现其 helper guard marker 过严，已继续修正，不作为最终实现。
  - `c83802867775b1759bc018163f9704cfe7e4fb2e` — 修正方法边界查找。
  - `c868250ad91c8bf7588b49d5287117d827287296` — 分开验证“位置开关拒绝 GPS 模拟”与“GPS 保存拒绝位置阻断”两个方向。
  - `d25dbc4e4104570fc2265c11388a2e537aceb3fe`、`2056a66eb49c82c391f37c917f2c256e3d35b54f`、`9ba322ea7103d202e71c58cfd8f7a4a65554b37d` — 增加位置控件及双向互斥测试断言。
- 最新源码静态复核（当前 HEAD `a709aa0d65f1d451542d2ad1825a51028250c863`）：专用控件挂载、helper 边界、开关侧冲突、GPS 保存侧冲突、目标包同步保存、迁移器接纳逻辑、回归测试契约共 7 项全部通过。未在本地完整 checkout 执行 Shell 测试（容器无法解析 github.com）；当前相关 Actions 尚无已完成且成功的迁移验证记录，不能宣称 CI/编译通过。
- 并行接管：同一分支后续已完成 Hook 自定义规则编辑/删除/分组移动后继续停留在规则管理页（`bfa0d8f9b0b5320b4c62c934e8284e76468ae592`，测试 `5ea20984f647c86fd04987af29f0a9e28e58b63a`）；Dia Frida 脚本库新建对话框名称草稿在重建后恢复（`e3e973e70835ad4b21e3261cbcbe234c403e5de0`，测试 `9517b39b7fed6d09b5f44e66b74bd834061c62c7`）。均已读取并保留。
- 下一步：检查现有 Actions run `41905243917` 是否已实际跑到 API-101 迁移 postcondition 和静态回归步骤；若它也被取消，则不重复触发整套 Actions，转向可独立运行的现有测试路径与其他 UI 页面批次。固定 FX 1.0.0，不发布或交付最终 APK / KernelSU ZIP。


## 2026-11-05 — 本窗口续接索引
- 读取时实时 HEAD：`bed790d5ed12f00c91ce7fe400b9f95993071be4`。Frida 脚本库新建弹窗草稿恢复提交 `33e05a8` / `d334b41` 已在分支；下一步核对 Frida 主页面保存脚本弹窗与脚本库/编辑器返回链。
- Hook 自定义规则管理导航修复：`bfa0d8f9b0b5320b4c62c934e8284e76468ae592`；回归断言：`5ea20984f647c86fd04987af29f0a9e28e58b63a`。Hook 列表状态恢复：`2a9f9a1eb36952678476247cc3fac4c132243ee0` / `aa3462f0b44b0ba1ab367297d58ba993cebac1bf`。Dia Dialog/通知/Toast 分流：`b0a7490e296c81dd0c4662d1db783b85f83b6886` / `1bfc59b45dc0d67f1f76d9a2ff5599e2787cd3a4`。
- 验证仅为源码静态检查与回归断言审阅；Shell/Python、Gradle、UI 自动化、安装和真机均未执行。
- 固定 FX 1.0.0；三套应用与六 Tab 完整验收前不打包最终 APK / KernelSU ZIP。


## 2026-11-05 — API-101 位置访问保护 UI 与迁移检查器修复核验

- 追查 Actions 运行 `41904387432`：该运行基于旧提交 `474749b65b61f96ebddf6a03664aadab17ec3397`，在 workflow 的“Restore module sources, merge Hook entrypoints, and stage WebUI”步骤失败；错误为 `API-101 privacy migration incomplete; missing fields: location_access_block native UI toggle`。静态迁移检查、完整 Host 回归和 APK 编译均被跳过，不能作为构建/测试通过证据。
- 后续运行 `41904923257` 基于 `c83802867775b1759bc018163f9704cfe7e4fb2e`，同一阶段仍失败。读取原始 Actions job log 后确认：该提交上的 `patch_hook_privacy_controls.py` 在 helper 检查中错误要求 `if (locationAccessBlocked && (enabled || provider)`，但实际专用开关使用局部变量 `coordinates` / `provider`，因此把已有控件误判为缺失。
- 当前分支 UI 已有专用 `addLocationAccessBlockToggle(locationConflictStatus)`，位于所选应用的“位置隐私”区：
  - 读取并写入 `selectedPackage + ":location_access_block"`；
  - 禁止与 `location_simulate` 或 `location_provider_enabled_simulate` 同时启用；
  - 使用同步 `commit()`，失败时恢复 Switch 原状态并提示；
  - 随后的 `publishConfig()` 将字段写进目标配置；Parser、Serializer 和 `AdVisibilityHook` 运行时均已有对应字段及消费逻辑。
- 当前分支 `patch_hook_privacy_controls.py` 已修正检查锚点为 helper 实际使用的 `if (coordinates || provider)`，并保留对保存、回滚、UI 安装点及 GPS 模拟互斥的检查。当前 HEAD 静态复算确认 helper 所有 marker、目标页调用、发布字段、Parser/Serializer、Hook 消费链存在。
- 相关提交：`60399161c08e4c4f4c423865581c8b1af15f6deb`（接受冲突感知位置控件）；`c83802867775b1759bc018163f9704cfe7e4fb2e`（迁移检查器 helper 边界调整）；`9ba322ea7103d202e71c58cfd8f7a4a65554b37d`（双向 GPS/位置互斥回归覆盖）。后续当前分支检查器已把错误变量名改为真实变量名。
- 最新可见自动运行：`41905358248` 对当前 HEAD `95f53f94f81dfa7b4158cfca42b53ec62bbd6fe9` 仍处于 pending；`41905243917` 对稍早提交处于 in_progress；更早运行因 `concurrency.cancel-in-progress: true` 被取消。当前没有证据证明最新 HEAD 的 Host 回归或 Android 编译已通过。
- 下一步：等待/读取当前自动运行的结果；若该步骤通过，再确认静态迁移与 Host 回归阶段是否真正执行。随后将位置保护控件的同一契约加入 `fx-hook-native-ui-regression.sh`，与下一批 Hook UI 测试一起提交，避免单独触发重复的 300 项 workflow。固定 FX 1.0.0，不生成最终 APK / KernelSU ZIP。


## 2026-11-05 — Dia Frida 大脚本草稿旋转恢复

- 发现 Frida 主页面允许从 SAF 导入最大 512 KiB 的脚本，但 Activity Bundle 只保存不超过 48 KiB 的源码；较大导入脚本在旋转/Activity 重建时会丢失。
- 修复：48 KiB 以内继续使用 Bundle；48–512 KiB 使用应用私有 cache 中的 `AtomicFile` 暂存，Bundle 只保存布尔标记。写入采用 `startWrite/finishWrite/failWrite` 原子流程，恢复时执行 512 KiB 上限检查；首次无恢复状态时清理陈旧草稿，Activity 正常结束时清理暂存文件。
- 不降低原 SAF 导入 512 KiB 上限、不改变全屏编辑器 48 KiB 上限、不把大型脚本源码塞入 Activity Bundle。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java`；`scripts/tests/fx-dia-frida-script-library-saf-regression.sh`；本状态文件。
- 提交：`43b9c74a8d9c22f3ab06826e30e0d6cf14d15a26`（AtomicFile 草稿保存/恢复）；`952863f0e82f8b932f5baf65df8a9176bd7dfb5a`（回归断言）。
- 验证等级：源码静态确认 Bundle/AtomicFile 双路径、512 KiB 限制、原子写入失败回滚、恢复读取和 Activity finish 清理，以及回归断言。未运行 Shell/Python 回归、Gradle、模拟器或真机 48–512 KiB 脚本旋转测试。
- 下一步：复核 Frida 页面状态恢复中的目标进程 PID 过期校验、编辑器返回与 SAF 并发请求；随后集中运行 Frida 页面组 Host 回归。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — Dia Frida 大脚本暂存文件孤儿清理

- 本批起始 HEAD：`9e3870ff4c8bc3b9a2c8285387f15a26779160dc`。
- 已有大脚本恢复：48 KiB 以内使用 Bundle；48–512 KiB 使用应用私有 `AtomicFile`，Bundle 仅保存归属标记；正常 Activity finish 删除暂存。
- 本批发现的边界：前一次重建可能留下 AtomicFile；如果后续脚本变为超过 512 KiB，或新的 AtomicFile 写入失败，Bundle 不再带文件标记，但旧缓存原先会留到下次正常退出。损坏/超限读取也可能反复尝试同一文件。
- 修复 `FxDiaFridaActivity.java`：
  - 仅当当前恢复 Bundle 明确包含 `STATE_SCRIPT_DRAFT_FILE` 时保留缓存；冷启动或无归属标记时删除孤儿文件。
  - 读取缓存发生格式/长度/IO 异常时删除失效缓存，避免反复重试。
  - 当前脚本超过 512 KiB或暂存失败时，删除可能由 AtomicFile 回滚留下的旧版本；不会把旧脚本误当成新脚本恢复。
  - 继续保留 `AtomicFile.startWrite/finishWrite/failWrite` 原子写流程、512 KiB上限、Bundle 48 KiB阈值和 finish 清理。
- 提交：
  - `c185a21f6a9fc8dbfcb489673f49b519498c16a4` — `fix(dia): clear orphaned large Frida draft cache`。
  - `7363392523239c13530ad1241292236b46b687c6` — `test(dia): cover orphaned large Frida draft cleanup`。
- 静态验证：最新 HEAD 确认 Bundle 归属标记、冷启动/无标记删除、恢复失败删除、超限/写入失败删除、AtomicFile 回滚和 finish 删除各项契约均通过；回归脚本增加三项孤儿清理断言。未在设备运行 48–512 KiB 脚本旋转、进程死亡、损坏缓存或并发 Activity 测试。
- 并行接管：Frida“保存到脚本库”名称对话框已具备 Bundle pending 状态、草稿恢复、64 字符限制及配置变更取消保护；脚本库“新建脚本”同样具备名称草稿与弹窗恢复。未重复修改。
- 下一步：检查 Frida 目标进程多选 PID 的恢复后过期状态处理和全屏编辑器结果返回；然后核对 SAF 文件 picker 与后台 Worker 并发结束时的请求归属/生命周期。固定 FX 1.0.0，不提前交付最终 APK / KernelSU ZIP。


## 2026-11-05 — Root Proxy 旧版目录锁迁移与 CI 失败修复

- 读取 Actions 失败日志后定位：`fx-module/scripts/tests/v1.0.0-yulong-root-proxy-lock-regression.sh` 明确验证旧版 PID 目录锁的安全迁移；但 `yulong-root-proxy.sh` 顶层预检只允许“缺失/普通文件”，在进入 `with_lock()` 的兼容迁移逻辑前就拒绝了真实旧版目录，导致 CI 报 `Root Proxy lock path is not a regular file`。
- 修复 `fx-module/scripts/yulong-root-proxy.sh` 顶层预检：允许缺失、普通文件或真实目录；路径组件仍先经过 `_reject_symlink_components`，锁逻辑仍拒绝锁路径/ PID 符号链接。目录锁必须经过既有 owner PID 检查、存活状态复核和原子 quarantine rename，不能绕过锁所有权验证。
- 不放宽 FIFO/设备节点等特殊文件；不允许符号链接；不改变新版本 noclobber 普通文件锁和原子 rename 释放流程。保留已有测试对过期 PID 目录、活跃 PID 目录、无 PID 目录、符号链接及并发 stop 的覆盖。
- 改动路径：`fx-module/scripts/yulong-root-proxy.sh`；本状态文件。现有 `fx-module/scripts/tests/v1.0.0-yulong-root-proxy-lock-regression.sh` 是复现该问题的回归测试，无需放宽断言。
- 提交：`16f41027ea2c7120853e57d0cf1149e7e202f114`。
- 验证等级：源码静态确认预检允许目录进入迁移逻辑，同时保留路径组件 symlink guard 和 with_lock owner/rename 检查。CI 失败日志已定位到本行；修复后的自动 Actions 尚待完成，未声称回归通过。
- 下一步：等待该提交触发的唯一 Actions 结果；若锁回归通过，继续 Frida 目标进程选择回调的代次/包名/UID 过期保护；若失败，读取具体新日志，不重跑无关 Actions。固定 FX 1.0.0，不提前打包最终 APK / KernelSU ZIP。


## 2026-11-05 — Root Proxy 锁迁移修复纳入 CI 触发范围

- 补充发现：原 `build-fx-adhook.yml` 的 push paths 只包含 `fx-module/scripts/tests/**`，没有包含被测试的模块脚本源码；因此单独修改 `fx-module/scripts/yulong-root-proxy.sh` 不会触发验证，不能用 CI 证明修复。
- 已增加 `fx-module/scripts/**` 路径过滤，使 apply/subfetch/DNS/Root Proxy 等模块脚本源码变更都会触发同一验证工作流；仍保留 concurrency cancel-in-progress，只验证最新树，不堆叠旧 Actions。
- 提交：`16f41027ea2c7120853e57d0cf1149e7e202f114`（允许安全迁移旧目录锁）；`2a6c35d5c73ff852761546f1c429ffae5b7f6343`（模块脚本源码纳入 CI 路径过滤）。
- 验证状态：工作流文件静态确认新增 `fx-module/scripts/**` 触发路径；该路径更新已触发最新验证，等待结果。此前 952863 提交对应的完整工作流失败于 Root Proxy 旧目录锁预检，已定位并修复；未把该旧失败记作通过。
- 下一步：读取新 Actions 的 Root Proxy lock regression 结果；通过后回到 Frida 目标进程选择的异步回调竞态保护。固定 FX 1.0.0，不提前打包最终 APK / KernelSU ZIP。


## 2026-11-05 — Shield 救援中心按启动来源返回，避免重复 Hub 入栈

- 本批起始实时 HEAD：`44aac26b13ce19f44a1add529ff77441e6f8b2f3`；提交期间遇到并行更新后，均从最新分支重新读取文件再追加，没有强推。
- 查明 `FxYulongRescueActivity` 有两类入口：
  - Shield Hub 内的“打开救援中心”按钮；
  - `FxYulongRescueOverlayService` 常驻通知的 PendingIntent。悬浮气泡本身仍直接打开 Shield Hub。
- 修复返回行为：
  - 通知 PendingIntent 增加 `EXTRA_OPENED_FROM_NOTIFICATION` 来源标记；
  - 从通知启动时，“返回安全护盾主页”使用 `CLEAR_TOP | SINGLE_TOP` 打开/复用 Shield Hub，再结束 Rescue Activity；
  - 从 Shield Hub 进入时不新建 Hub，只 `finish()` 返回原 Hub，避免 Hub → Rescue → 新 Hub 的重复任务栈。
  - 悬浮气泡直达 Hub 的行为不变。
- 提交：
  - `4345517a79541af7c4f0163c93afab0de4675000` — 通知入口写入启动来源标记。
  - `043c514704513ac24cc85c8c24f6abfd2891ebe8` — Rescue Activity 按来源选择返回路径。
  - `1c286a95db52dd12ef403b6476bda5701c48d32d` — Shield 六 Tab 回归脚本覆盖两种入口及返回栈契约。
- 静态验证：当前分支复核到通知来源 extra、Hub 内入口、悬浮气泡仍直达 Hub、通知路径使用 CLEAR_TOP/SINGLE_TOP、Hub 路径结束当前 Activity，以及新增回归断言。未执行完整 Shell 回归、Gradle、模拟器/真机通知点击与多次返回测试。
- 下一步：审计剩余 Shield 页从通知/悬浮服务打开时的任务栈；再检查三套应用的跨 Activity Result 与表单取消/返回行为。固定 FX 1.0.0，不打包最终 APK / KernelSU ZIP。


## 2026-11-05 — FX Hook 目标详情 / 自定义规则返回滚动位置恢复

- 本批起始实时 HEAD：`44aac26b13ce19f44a1add529ff77441e6f8b2f3`；执行期间并行分支继续推进，写入均先重新读取最新文件 SHA。
- 发现 Hook 应用列表状态虽已能恢复搜索/分页/滚动，但目标应用详情页没有自己的滚动状态键：旋转/Activity 重建后会回到详情顶部；从目标详情进入“自定义 Hook 规则管理”再返回时，也会丢失原详情所在位置。
- 修复：
  - 新增 `STATE_HOOK_TARGET_SCROLL_Y` / `hookTargetScrollY`，目标页 Activity 保存时记录当前 ScrollView 纵向位置，重建时按目标包恢复。
  - 同一目标页被刷新/重建前先捕获旧位置；不同目标或离开详情列表时重置，避免把 A 应用的滚动偏移套用到 B 应用。
  - 进入自定义规则管理页前保存目标详情位置；规则页使用自己的独立滚动状态；用户返回目标页时再恢复原详情位置。
  - 普通 Hook 详情、Dialog、Toast、按键控制三个逐应用原生子页都走带目标/ScrollView 实例保护的恢复 helper。
  - 将隐私分类自动定位改为一次性 `pendingPrivacySection` 请求，而不再每次目标页重建都根据 `activePrivacySection` 重新定位；Activity 从 Bundle 恢复目标时不重放初始分类定位，避免覆盖已保存的滚动位置。
  - 若 Activity 重建时原目标包已卸载，清除过期目标滚动值和恢复标记，防止下一次打开其他应用时沿用旧位置。
- 提交：
  - `094846ee01a9e876b1d343fca9d100099cf95999` — 目标详情、三个专用逐应用页及自定义规则往返的滚动状态恢复。
  - `036ae8aec8c8c5c968e90096d0285a74e36eb494` — 增加目标页 Bundle/滚动/分类焦点/自定义规则往返回归断言。
  - `8700c58ab8343798ba8f9aef43fd96edb79ea2e6` — 清理已卸载目标导致的过期滚动恢复状态。
  - `79d132ebf8385beefbd8fac029903b333fecc734` — 增加目标已卸载时状态清理断言。
- 验证：当前最新源码静态核对目标滚动状态键、Bundle 保存/恢复、首次分类焦点与重建焦点分离、普通/专用详情页恢复、目标包与 ScrollView 实例保护、进入/离开自定义规则页的滚动保留，以及原目标卸载时清理；回归脚本包含对应断言。未执行 Shell/Python 回归、Gradle 构建、UI 自动化、旋转或真机点按。
- 下一步：继续核对 Hook 详情页权限/作用域异步状态回读是否会覆盖当前目标或留下过期 Loading 状态；随后在可运行环境执行 Hook 原生 UI 回归和相关 Host 测试。固定 FX 1.0.0，不提前打包最终 APK / KernelSU ZIP。


## 2026-11-05 — 安全护盾救援通知直接进入 Rescue 并恢复调用来源返回链

- 本批起始 HEAD：`632a6dc9a8b4683cd769a0e1881e36207133fbf8`。
- 已有 RescueActivity 的通知来源返回分支，但 ProtectionService 的通知 PendingIntent 实际仍指向 Shield Hub，未设置 `EXTRA_OPENED_FROM_NOTIFICATION`，导致来源分支不可达。
- 修改：
  - 救援通知现在直接打开 `FxYulongRescueActivity`，携带 `EXTRA_OPENED_FROM_NOTIFICATION=true`；通知点击不再先落到 Hub。
  - Rescue 顶部返回、页面底部“返回安全护盾主页”和 Android 系统 Back 统一调用 `returnToShieldHub()`。
  - 通知来源：显式启动/回到 Hub（`CLEAR_TOP | SINGLE_TOP`）再结束 Rescue；Hub 内部打开：仅结束 Rescue，回到原有 Hub 实例，不创建重复 Hub。
  - 保留原有救援操作、权限和确认流程。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongProtectionService.java`、`adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongRescueActivity.java`、`scripts/tests/fx-yulong-shield-native-regression.sh`、本状态文件。
- 验证等级：源码静态检查确认 PendingIntent 目标/来源标记、顶部/底部/系统 Back 共用调用来源路由，以及 Shield Host 回归脚本对应断言。未运行 Host 脚本、Gradle、UI 自动化、通知点击或真机返回栈测试。
- 当前 Actions：HEAD `1c286a95db52dd12ef403b6476bda5701c48d32d` 对应运行 `41906293213` 在提交时 pending；更早运行因同一工作流并发取消而 cancelled，不计为通过。
- 其他已接管并保留的并行提交：Dia Frida 目标/进程选择恢复与回归（`162adce548ae62c1e6edb50b5261cec1f34972a5`、`9802250e0d969e5b369e50456913fa8cc8146a98`）、脚本库导出请求串行保护测试（`a22aedf7b9ee7f6baa8fcc8c965f246c1f6a453c`）、本批之前的 Rescue 来源返回修复（`043c514704513ac24cc85c8c24f6abfd2891ebe8`）。
- 未完成：第一、二份长期交接文件在资料库 `/FX` 当前目录列表中不存在，本窗口未能读取；已完整读取现存的 UI 总指令和提速补充档。不得用推测补写缺失文件内容。
- 下一步：继续安全护盾扫描结果详情/清理队列的页面返回和状态回显；随后接回 Dia Frida 主页面/脚本库/全屏编辑器的页面组回归。固定 FX 1.0.0，不提前打包最终 APK / KernelSU ZIP。


## 2026-11-05 — Frida 进程扫描回调的安装身份复核

- 本批起始实时 HEAD：`397e5307ae57b86a4bd13a6566f915689badbbea`。
- 现有机制已具备：目标/进程扫描异步请求代次、目标切换时废弃旧进程请求、过程弹窗暂存勾选与旋转恢复、注入前重新读取目标 UID，以及 Shell 侧对 PID 的进程名和 UID 二次校验。
- 本批补齐扫描快照与当前安装之间的竞态：Root 枚举结束后、显示 PID 选择器之前，重新通过 PackageManager 获取当前目标应用；如果目标已卸载、UID 与扫描前不同、debuggable 标记被移除或变为系统应用，则关闭进程选择、清空已固定与暂存 PID，并提示用户重新选择。
- 未改变注入流程的权限边界；PID 仍需在实际注入命令中再次满足目标包名与 UID，失效 PID 不会交给 frida-inject。
- 提交：
  - `632a6dc9a8b4683cd769a0e1881e36207133fbf8` — `fix(dia): revalidate target identity after Frida process scan`。
  - `397e5307ae57b86a4bd13a6566f915689badbbea` — `test(dia): cover stale Frida process picker identity`。
- 最新 HEAD 静态验证：回调请求代次/目标包、扫描后 PackageManager 重新获取、UID/debuggable/system 状态核验、失效时清空 PID、既有注入侧 UID 检查，以及回归脚本新断言共 7 项通过。未在 Root 真机或模拟器中制造卸载/重装并发、UID 变化、PID 复用或多进程注入；源码静态通过不等于设备验收。
- 下一步：检查 Sora 全屏编辑器结果回传是否绑定发起编辑时的目标与脚本版本，避免编辑过程中切换目标后把旧代码覆盖到新脚本；随后检查 Frida SAF 文件选择请求与 Worker 在 Activity 重建/快速连续操作时是否串单。固定 FX 1.0.0，不提前发布最终 APK / KernelSU ZIP。


## 2026-11-05 — Dia Frida 目标/进程选择器旋转恢复、PID 选择保真与目标身份复核

- 本批开始前分支 HEAD：9e3870ff4c8bc3b9a2c8285387f15a26779160dc；后续并行推进至 HEAD 397e5307ae57b86a4bd13a6566f915689badbbea。提交前后均按实时 branch HEAD 和文件 blob SHA 操作，无强推。
- 修复 Frida 管理页目标/进程选择器重建丢失：
  - Bundle 保存/恢复 debuggable 目标选择器是否打开；Activity 重建后重新读取已安装 debuggable 用户应用，再恢复目标选择列表。
  - Bundle 保存/恢复进程选择器是否打开；重建后针对恢复的目标重新执行 Root 进程扫描，不复用旧 PID 列表作为实时结果。
  - 多选对话框逐项暂存 PID；旋转时保存暂存 PID，重建后根据当前进程扫描结果重建勾选状态。
  - 区分“从未做过选择（默认全选当前进程）”和“用户明确取消全部勾选（恢复后仍为空）”，避免空集合被误当作默认全选。
  - 恢复回调尚未执行时，pending 标记仍写入 Bundle，避免 View.post 排队后再次旋转造成选择器状态丢失。
  - 切换目标应用时递增进程请求代次、关闭旧进程选择状态并清空旧 PID 暂存；旧 Root 回调同时校验请求代次和目标包名，不能覆盖当前目标。
  - Root 进程扫描完成后再次通过 PackageManager 校验目标仍存在、UID 未变化、仍是 debuggable 且非系统应用；身份变化时丢弃旧 PID 快照。
  - Activity 销毁时使目标/进程查询代次失效，清除当前 Activity 的 pending UI 状态。
- 修复 Frida 脚本库 SAF 导出暂存冲突：只允许一个脚本库 JSON 导出请求等待系统文件选择器返回，避免并行导出覆盖单一 pending staging filename。
- 提交：
  - 04ef55dcd7612a37bef2fb9f98f305fc9d193c20 — Frida 目标/进程选择器状态恢复。
  - 8305b1044691c0546b8ae286506174bf0a7582ac — 明确全不选状态与恢复回调排队期间的 pending 标记。
  - 61113e197529983b96306ad89fe246e482c428ac — 切换目标时取消旧进程选择请求，避免旧 busy 标记阻止新目标操作。
  - 632a6dc9a8b4683cd769a0e1881e36207133fbf8 — 进程扫描完成后复核目标包名/UID/debuggable/system 状态。
  - 9802250e0d969e5b369e50456913fa8cc8146a98 — 选择器重建与暂存 PID 回归断言。
  - a22aedf7b9ee7f6baa8fcc8c965f246c1f6a453c — 防止重叠 Frida 脚本库 SAF 导出。
  - ab9642cdb61d61874ecb1753ca5ee6ce84a0a3d8、4730cd11d71a566d2467f57003f5f1b92ae3e2c2 — 目标切换失效回归及修正源码换行匹配断言。
  - 397e5307ae57b86a4bd13a6566f915689badbbea — 并行工作线增加目标身份过期快照回归测试。
- 最新文件静态核验（HEAD 397e5307ae57b86a4bd13a6566f915689badbbea）：目标/进程选择器 Bundle 保存/恢复、暂存 PID 列表、明确空选择保真、延迟恢复状态继续保存、进程请求代次/目标包名校验、目标切换时取消旧请求、目标 UID/debuggable 复核、单一 SAF 导出保护，以及两份回归脚本对应断言全部存在。
- 测试状态：本批未在完整 checkout 执行 Shell/Python 回归；未运行 Gradle、Android 编译、模拟器、UI 自动化、Root 权限注入故障或真机旋转/进程选择测试。GitHub Actions 最新自动运行 41906545883（Validate FX APP migration and build Hook APK，HEAD 397e5307...）状态为 pending，不能计为通过；同工作流前面的 push 运行多次被 concurrency 取消，也不计为通过。没有手动重新触发整套 Actions。
- 失败/修正记录：本轮测试断言一度把 Java 源码换行匹配写成双重转义，静态检查发现无法按源码实际换行匹配，已改成单转义并提交 4730cd11d71a566d2467f57003f5f1b92ae3e2c2；未为通过测试而放宽产品逻辑。
- 下一步：核对 FxDiaCodeEditorActivity 的 Activity Result 返回目标/脚本内容归属，确保全屏编辑器返回时不会覆盖用户切换后的 Frida 脚本；然后查 SAF 文件 picker 返回与后台 Worker 取消/Activity 销毁的请求归属。固定 FX 1.0.0，不提前打包最终 APK / KernelSU ZIP。


## 2026-11-05 — 安全护盾扫描结果列表滚动位置恢复

- 本批起始 HEAD：`67bd883a0697d8f2477753a7b0b67bcb913e6a01`。
- 扫描 Activity 已保存风险项、严重度、原因、完整性状态和批量选择，但未保存结果 ScrollView 的滚动位置；风险详情往返或 Activity 重建后会回到列表顶部。
- 修改 `FxYulongScanActivity.java`：保存真实扫描 ScrollView 引用；Bundle 保存 `fx_shield_scan_scroll_y`（无结果时也保存）；恢复风险项/选择状态后通过 post 恢复滚动，并校验 Activity 未结束、ScrollView 仍是当前页面实例。
- 修改 `fx-yulong-shield-native-regression.sh`：覆盖状态键、真实 ScrollView 绑定、保存/恢复、过期回调实例保护。
- 验证等级：源码静态断言通过；未运行 Shell 回归、Gradle、UI 自动化或真机风险详情往返/旋转测试。
- 最近并行提交：Frida 目标包/进程扫描后重新验证目标身份（`632a6dc9a8b4683cd769a0e1881e36207133fbf8`）、目标切换清理旧 PID（`4730cd11d71a566d2467f57003f5f1b92ae3e2c2`）、过期进程选择身份断言（`397e5307ae57b86a4bd13a6566f915689badbbea`），以及对应状态记录（`6c506066769547604157f7b0d9cad13af6823692`）。安全护盾通知来源直达救援页（`d4ee58b8be644037170a4467c4ebde0373aef4b7`）。
- 下一步：核对扫描结果详情页与批量清理队列 Activity 的回退后状态回显/系统卸载结果回读；随后检查病毒库管理页错误/缓存回滚 UI。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — 安全护盾批量清理队列完整性与恢复 fail-closed

- 本批基于分支最新文件检查后发现：批量清理页 `FxYulongBatchCleanupActivity.restoreQueue()` 之前使用三个数组长度的最小值并静默截断；包名格式错误/重复项目也会被跳过后继续处理剩余队列。若队列 Bundle/Intent 字段不匹配，页面可能展示一个不完整的清理队列，而用户无法从页面判断被省略的项目。
- 修复 `FxYulongBatchCleanupActivity.java`：
  - packages / labels / reasons 必须全部存在、数量完全一致、非空且不超过 100 项；不再按最短数组静默截断。
  - 全队列预检每个包名格式、唯一性、label/reason 长度；任一项目异常则拒绝整个队列，不部分执行。
  - 已移除项目必须属于原队列；恢复 index 必须在 0 到队列长度范围内。
  - 无效队列状态和原因写入 Bundle；Activity 重建后继续保持无效状态。
  - 无效队列页面明确显示拒绝原因并禁用“打开系统卸载确认”和“跳过当前项”，要求返回扫描页重新选择。
  - 保留逐项 Android 系统卸载确认流程；没有增加静默卸载、Root force-stop 或冻结行为。
- 改动路径：
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongBatchCleanupActivity.java`
  - `scripts/tests/fx-yulong-shield-native-regression.sh`
  - `docs/FX_1.0.0_LIVE_CONTINUATION_STATE.md`
- 提交：
  - `67bd883a0697d8f2477753a7b0b67bcb913e6a01` — fail-closed 队列恢复与状态保存。
  - `9c108c193e7a36d0ccf86da593a215c08a43cecc` — Shield 回归脚本覆盖字段数量、大小上限、包名唯一性、已移除项目归属、index 范围和无效状态禁用操作。
- 最新 HEAD 复核：`a102de7565271c44c0cfcf468fa88b8d574ef963`。静态检查确认实现与回归脚本均包含上述契约；本轮没有执行 Shell 回归脚本、Host 单测、Gradle 构建、UI 自动化、安装或真机卸载流程。不得把静态断言审阅表述为运行测试通过。
- 中断恢复注意：资料库 `/FX` 当前目录列表未包含《FX_1.0.0_项目接管总档_自主开发与查漏补缺.md》和《FX_1.0.0_快速推进与主动修复执行档.md》，本窗口已完整读取现存的 UI 总指令、提速补充档和旧版 Library 实时状态；缺失两份文件不以推测补写。
- 下一批直接任务：① 核对 Shield 批量清理从系统卸载页返回后的当前项状态和队列滚动/返回链；② 检查风险详情页对卸载结果、包卸载广播和通知入口的状态回显；③ 然后继续 Dia Frida 目标进程选择与脚本编辑器的结果归属回归。固定 FX 1.0.0，不生成最终 APK / KernelSU ZIP。


## 2026-11-05 — 安全护盾风险详情的实时状态与卸载入口保护

- 本批发现：风险详情页收到无效风险等级时仍显示可用的系统卸载入口；目标应用在页面打开期间被卸载后，返回详情页也没有刷新包状态。
- 修改 `FxYulongWarningActivity.java`：
  - 增加目标包实时查询状态，并在 `onResume()` 刷新。
  - 白名单和卸载按钮只有在包名有效且应用当前可查询/已安装时启用。
  - 卸载按钮还要求风险等级为 `CERTAIN` 或 `SUSPECT`；缺失/未知等级时不允许从警告页启动卸载确认。
  - 用户确认后、启动 Android 卸载 Intent 前再次查询目标包，避免确认弹窗停留期间目标已卸载。
  - 查询失败或目标不存在时显示明确状态，不伪造卸载/白名单成功。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongWarningActivity.java`、`scripts/tests/fx-yulong-shield-native-regression.sh`、本状态文件。
- 提交：`a811426055e000aec62bb5e56f902a93b6cde30d`（风险等级/安装状态门控及启动前二次查询）；`c97e28296c491f2cf3e1f706631aae192e1eacbc`（对应静态回归契约）。
- 最新源码静态复核：确认前台恢复时查询、按钮启用条件、未知风险等级禁用、启动卸载前二次查询和 Shield 回归断言。未运行 Shell 回归、Host 单测、Gradle 构建、UI 自动化、安装或真机卸载流程。
- 当前本批前序队列修复也已纳入当前分支：`67bd883a0697d8f2477753a7b0b67bcb913e6a01`（批量清理队列 fail-closed）及 `9c108c193e7a36d0ccf86da593a215c08a43cecc`（队列完整性回归断言）。
- 最新 HEAD（本状态写入前）：`c97e28296c491f2cf3e1f706631aae192e1eacbc`。当前对话读取到的旧实时状态文档比实际分支 HEAD 落后；本节以 GitHub 实时分支和文件 SHA 为准。
- 下一批：继续 Dia Frida 目标进程多选/编辑器结果回传的异步请求归属；然后回到游龙广告 Tasker/Widget 的动作执行回执可见性。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — 批量清理队列返回后扫描状态失效保护

- 本批起始 HEAD：`c97e28296c491f2cf3e1f706631aae192e1eacbc`。
- 扫描页原先通过普通 `startActivity()` 打开批量清理队列；返回后仍保留旧风险勾选和可用的批量处理按钮，扫描数据可能已因系统卸载而过期。
- 修改 `FxYulongScanActivity.java`：改用 `REQUEST_BATCH_CLEANUP` 接收队列返回；返回时清空旧选择、设置 `restoreRequiresRescan=true`、标记扫描不再完整有效、显示“原扫描结果可能已过期”，并禁用再次批量处理，直到用户重新扫描。没有把卸载器的返回码当成应用确已卸载。
- 修改 `fx-yulong-shield-native-regression.sh`：增加请求码、Activity Result、清空选择、重新扫描门禁和状态提示断言。
- 提交：
  - `457526851701b46281533d9d50e393acd8adec01` — 扫描页接收批量清理队列返回并失效旧结果。
  - `86cd3530f759a5a2bb4b3d152489878152d51d7c` — 对应回归断言。
- 验证等级：源码静态检查；未运行 Host Shell、Gradle、UI 自动化或真机卸载确认流程。
- 同页面组并行提交已接管：`67bd883a0697d8f2477753a7b0b67bcb913e6a01` 批量清理队列数据缺失/长度不一致/重复包名/非法索引时 fail-closed；`cf39f274e81b1e853a70e27d6367ac0f06e5edd0` 扫描结果列表滚动位置恢复；`a811426055e000aec62bb5e56f902a93b6cde30d` 救援警告操作前实时校验包是否仍安装及风险状态；`c97e28296c491f2cf3e1f706631aae192e1eacbc` 对应警告页回归覆盖。
- 并行 Frida 页面修复：`78a57d9831c7180e0803e88f2cc552b66cd52bc6` 将全屏编辑器返回结果绑定到打开时的脚本源快照，防止过期结果覆盖后来修改的脚本；对应后续测试需以最新分支为准。
- 下一步：检查安全护盾病毒库管理页的网络失败、空响应、校验失败是否会覆盖旧缓存，以及 UI 是否区分“本地缓存可用/在线更新失败/数据库未就绪”；固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。
