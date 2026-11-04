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
