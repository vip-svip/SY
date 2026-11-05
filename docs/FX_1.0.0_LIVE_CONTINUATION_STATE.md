# FX 1.0.0 — 实时开发续接状态

> 本文件是跨窗口的当前任务状态入口。每完成一个有意义的页面/功能批次，都应在同批代码提交中更新本文件。旧聊天和旧 SHA 不得覆盖这里的新状态。

## 当前仓库状态（2026-11-05，Asia/Tokyo）

- Repository：`vip-svip/SY`
- Branch：`fx-v1.0.0-unified-hook-integration`
- 历史检查点：`775de347ec98c98c0b58428c1fa8627164ba5ff1`（仅为旧状态记录，不是本轮当前 HEAD；本轮实际新提交见文末）。
- 最近 Dia Host 回归：run `41915416366`，HEAD `6a99665a29b18406360a5e5df4e1d2e795d1d030`，SUCCESS；不是当前 HEAD 的 Gradle/设备验证。
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

- `MainActivity.java` 保存 `selectedBottomTab`、`lastWebTabIndex`，恢复范围为 0–5；保留 Hook 目标/规则编辑栈、Settings 状态和 VPN 分应用路由恢复。旧来源应用 Migration 多级导航已从 MainActivity 移除。
- MainActivity 已接入安装/卸载/更新包广播刷新 Hook 应用列表，并缓存名称/图标、分页显示应用行。
- 主工程存在原生 VPN 控件、Hook UI，以及按 FX 业务域承载的原来源 Activity；来源 Activity 不构成独立产品入口。
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

1. **六 Tab 主壳和首页交互回归：** 对照固定顺序 VPN / Ad / 隐私 / 脚本 / Hook / 设置；第二 Tab 只能显示 Ad，Hosts 只能是 Ad 的内部工具页。复核底栏高度/可见性、顶部错误横幅、按钮/开关布局、页面切换与返回恢复。
2. **来源功能的业务域页面完整度：** 将 Dia、游龙广告、安全护盾、GKD 的具体功能拆入 Ad/VPN/隐私/脚本/Hook 的真实页面；只维护研发映射表，不新增迁移应用页、来源应用启动器或独立三级菜单。按完整页面组补齐 UI 和真实操作，禁止新增泛化空壳页。
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
- 旧来源项目只作为源码和功能证据；最终 UI 不保留任何独立来源应用三级入口。每个子页面必须按所属业务 Tab 高亮，并使用 FX 的返回路径。
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


## 2026-11-05 — 并行续接：批量清理返回后使扫描结果失效

- 本轮状态写入期间分支继续前进至最新 HEAD `e1357a6c5e5368113826bb925d1319507d06c743`；以下记录基于重新读取的分支文件，没有覆盖并行提交。
- `457526851701b46281533d9d50e393acd8adec01`：批量清理页改用 `startActivityForResult`；返回扫描页后清空旧选择、标记旧扫描结果可能过期并禁用再次批量处理，要求重新扫描，避免卸载/跳过后继续使用旧风险列表。
- 并行提交 `8bc76b72aa33f05de692010c4fd390617a61ed93`：LSPosed 作用域读取/申请/移除增加超时、线程中断和目标切换/离页时过期回调取消。
- 并行提交 `78a57d9831c7180e0803e88f2cc552b66cd52bc6`：Frida 全屏编辑器返回结果绑定目标包名与源脚本 SHA-256，避免旧编辑结果覆盖已变化的脚本/目标。
- 最新 HEAD 静态复核：批量清理结果请求码与返回后扫描失效逻辑存在；Shield 回归脚本包含队列完整性断言；Hook LSPosed 超时/取消入口存在。未运行 Shell/Host 测试、Gradle、UI 自动化或真机测试。
- 下一批：复核 Dia Frida 进程选择/编辑器的目标身份与请求归属边界；随后处理游龙广告 Tasker/Widget 动作回执 UI。固定 FX 1.0.0，不生成最终 APK / KernelSU ZIP。


## 2026-11-05 — Frida 全屏编辑器返回结果绑定目标与源版本

- 本批代码起始 HEAD：`a102de7565271c44c0cfcf468fa88b8d574ef963`；提交期间因并行工作导致状态文档先后推进至当前 HEAD `7b499d052809385335262deb514374803aef3ace`，已重读最新源码与测试后追加，不覆盖并行内容。
- 原问题：Frida 主页面通过原有 `0x3039` Activity Result 打开全屏 Sora 编辑器；返回时只检查结果码和 48 KiB 长度，未验证当前目标包与打开编辑器时的目标相同，也未验证主页面脚本是否在编辑期间被其他动作更新。
- 修改 `FxDiaFridaActivity`：
  - 打开编辑器前冻结目标包名和当前源码 SHA-256 指纹，并拒绝同时打开第二个全屏编辑器请求。
  - 将 pending 标记、目标包和指纹写入 Activity Bundle；旋转/重建后可继续接收原编辑器结果。
  - 返回时消费并清理 pending 状态；若没有有效请求、目标包已改变、当前脚本指纹已改变、编辑器返回空值或超过 48 KiB，则不覆盖当前脚本。
  - 只有请求仍归属于同一目标、脚本源版本未变化且结果合法时才写回编辑结果；不执行脚本、不自动注入。
  - 保持原 Activity Result 常量 `REQUEST_CODE_FULL_EDITOR = 0x3039`、编辑器代码 extra、JavaScript 纯文本模式及保存/放弃交互。
- 提交：
  - `78a57d9831c7180e0803e88f2cc552b66cd52bc6` — `fix(dia): bind Frida editor result to source snapshot`。
  - `bdd719d25df57404d71ce7be54bc791d236b8292` — `test(dia): cover Frida editor result ownership`。
- 最新 HEAD 静态复核：SHA-256 源指纹、目标包快照、Bundle pending 恢复、返回时目标与源版本双重比较、pending 清理、0x3039 兼容及回归断言共 12 项通过。未运行 Sora Android UI、双窗口切换/进程重建、Gradle 编译或真机编辑返回测试。
- 并行续接：已确认同一工作线后续修复批量清理返回后必须重新扫描、LSPosed 作用域读取/申请/移除增加超时与过期回调取消；保留并未覆盖。
- 下一步：审计游龙安全护盾病毒库管理页的网络失败、空响应、校验失败是否会覆盖旧缓存，以及 UI 是否区分本地缓存可用、在线更新失败、数据库未就绪。随后检查 Frida SAF 导入/导出请求并发与文件暂存清理。固定 FX 1.0.0，不提前发布最终 APK / KernelSU ZIP。


## 2026-11-05 — 病毒库同步结果区分完整 / 部分 / 失败与旧缓存可用

- 本批起始 HEAD：`4279495ad32f3affa0c7aeddfe4f05784f5ff4ad`。
- 已发现 UI 误报：内容特征库刷新失败时，旧缓存仍可能 `ready=true`，旧 Toast 会因此显示“同步完成”；五类远程名单只要有一项成功，旧 Toast 也会显示全部同步完成。
- 修改 `FxYulongVirusDatabaseActivity.java`：
  - 五类远程名单按 `ListStatus.ok` 统计成功数，Toast 区分完整同步、部分同步（列出成功数/总数）和全部失败且保留旧缓存。
  - APK 内容库必须同时满足“缓存可用”与“本次刷新后 lastSuccess 严格增加”才报告同步成功；304/内容未变化仍会按成功处理。若刷新失败但旧缓存可用，明确提示“本次同步未成功；旧版 APK 特征缓存仍可用”；缓存未就绪时明确提示未覆盖旧缓存。
  - 自动触发扫描仅在本次内容库成功，或至少一个名单列表成功后触发。
- 修改 `fx-yulong-shield-native-regression.sh`：增加完整/部分/全失败状态、每名单统计、内容库本次成功时间和旧缓存可用失败提示断言。
- 提交：`4685a61500f20d68bd1c5c0a5a7a14f04310fd01`（实现）；`0de50f0bc9b08adc29baff03a14bf11f60fe57e7`（回归断言）。
- 验证等级：源码静态检查；未运行 Shell/Python 回归、Gradle、UI 自动化、网络断开/HTTP 304/损坏响应实测。
- 下一步：检查病毒库页面本身的滚动恢复与同步中断/Activity 销毁状态，随后回到 Dia Frida 编辑器结果归属和 SAF Worker 生命周期。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — LSPosed 作用域读取 / 申请 / 移除超时与离页取消

- 当前目标分支 HEAD（本节开始时）：a54008ea5eae58823535a63f86a5e8b2e766fbfe。
- 复核 FxLsposedScopeBridge.snapshot() 直接同步调用 libXposed Binder 的 getScope()；旧 UI 只把调用放到 daemon worker，没有超时。如果 Binder 不返回，目标页会一直显示“正在读取”。
- 新增共享有界操作生命周期：
  - LSPosed 作用域状态读取 12 秒超时；
  - 作用域移除 15 秒超时；
  - 向 LSPosed Manager 申请作用域等待 30 秒回执；
  - 超时使本次 generation 失效、中断关联 worker 并显示“状态未确认”，不会把未知结果显示成批准/移除成功；
  - 成功/失败回调清除对应 timeout；旧 generation 不能移除更新操作的 timeout 或覆盖新页面状态；
  - 切换到应用列表、Hook Hub、自定义规则页或 Activity 销毁时取消超时回调并中断 worker；保留目标包、TextView 实例和 generation 三重校验。
- 代码提交：8bc76b72aa33f05de692010c4fd390617a61ed93 — fix(hook): bound LSPosed scope operations and stale callbacks。
- 回归提交：7b499d052809385335262deb514374803aef3ace — test(hook): cover bounded LSPosed scope operations，覆盖 12/15/30 秒界限、timeout handler、旧回调失效和离页/销毁取消。
- 验证：当前 HEAD 静态复核确认三条路径使用同一 timeout/generation helper、对应 postDelayed、finish 清理、目标页面切换/Activity 销毁 cancel 及现有目标包/View 身份检查；测试脚本已增加同一契约的断言。未执行 Shell 回归、Gradle 编译、模拟器、Manager 审批回调或 Binder 故障注入。
- 注意：Binder 调用可能在底层不响应中断；当前实现保证 UI 不会永久显示 Loading，超时状态说明结果未知。重复手动重试仍应以实际刷新状态核对结果，不能把超时视为操作未执行。
- 下一步：核对 Hook Hub 的 Root / LSPosed / Accessibility 三种授权状态是否采用同一“配置状态与真实运行态分离”口径；随后按现有 Hook/Dia 测试入口执行能运行的 Host 与静态检查。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — 病毒库管理页滚动状态恢复

- 本批起始 HEAD：`38a05fa53b2a10a3663ebed3d3f46b9cb753b216`。
- 病毒库管理页包含多类名单明细和高级 APK 内容库状态，原 ScrollView 未保存位置；Activity 重建后回到页面顶部。
- 修改 `FxYulongVirusDatabaseActivity.java`：保存真实 ScrollView 引用；Bundle 保存 `fx_shield_virus_db_scroll_y`；页面完成名单/内容库状态渲染后恢复滚动；恢复回调检查 Activity 生命周期及 ScrollView 实例，避免旧页面回调滚动新页面。
- 修改 `fx-yulong-shield-native-regression.sh`：增加状态键、真实容器、保存/恢复和实例保护断言。
- 提交：`a54008ea5eae58823535a63f86a5e8b2e766fbfe`（实现）；`38a05fa53b2a10a3663ebed3d3f46b9cb753b216`（回归断言）。
- 验证等级：源码静态检查；未运行 Shell/Python、Gradle、UI 自动化或真机旋转/滚动测试。
- 下一步：回到 Dia Frida 编辑器返回归属和 SAF Worker 生命周期，随后按页面批次继续游龙安全护盾剩余风险详情/告警/名单原生页面。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — Dia DEX 浏览器来源 / SAF / 搜索与滚动状态恢复

- 本批起始实时 HEAD：`a102de7565271c44c0cfcf468fa88b8d574ef963`；提交期间检测到并行提交，所有后续修改均重新读取最新分支文件后追加，没有强推。
- 修复 `FxDiaDexBrowserActivity` 旋转/Activity 重建后丢失当前 DEX 来源的问题：
  - Bundle 保存来源类型（已选应用、已解析 APK、Framework DEX、独立文档）、目标包名、文档 URI/名称、持久化授权标记、搜索词和结果 ScrollView 位置。
  - 重建后按来源重新读取：应用 APK 重新从当前安装路径解析；Framework DEX 从应用资产重读；独立 DEX 文件从 URI 重新打开并走有界只读解析。
  - 不把 `classes` / DEX 索引集合写入 Bundle，避免大型索引引发 TransactionTooLarge。
  - 独立文档选择通过 `ACTION_OPEN_DOCUMENT` 获取 READ grant；提供方授予 persistable flag 时调用 `takePersistableUriPermission`；切换来源或 Activity 最终结束时释放已持久化 grant；配置变更期间保留。
  - 不支持持久授权的提供方仍尝试使用当前 URI 恢复；若系统/提供方已撤销临时授权，解析错误会回显，用户可重新选择文件。
  - 异步解析完成后恢复结果滚动位置；用户切换 APK/Framework/文档来源或修改搜索词时清除旧滚动恢复，避免旧结果位置跳到新列表。
  - 应用清单读取 Worker 与 DEX 解析 Worker 竞争时，迟到的应用清单回调只更新应用索引，不覆盖当前 DEX 解析状态文本。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaDexBrowserActivity.java`；`scripts/tests/fx-dia-dex-document-browser-regression.sh`；本状态文件。
- 提交：
  - `5bb212b65f00c02e8ba8f87ff92872f3eb2b797b` — 保存/恢复来源、URI、筛选和滚动状态，恢复后重新解析。
  - `120ff9cf95f06201893e0e8174ad312a3b4c8643` — 对未授予 persistable flag 的文档提供方保留尝试恢复路径，失败时提示重新选择，而不直接丢弃 URI。
  - `81161c1ea360456e8fcb33ba8f8d3778b405f8f0` — 切换来源/搜索时清理旧滚动恢复。
  - `e6c639436a8b4354d5557420e954a33f0fe32133` — 增加 DEX 来源、SAF grant、Bundle、异步恢复及滚动状态回归断言。
  - `3a04d775d0f208bc86dad93193467bdcee35c4f1` — 防止应用清单迟到回调覆盖当前 DEX 加载状态。
  - `1d68d0cb7198fd810695eaec42a6c54d40293390` — 回归脚本增加 Worker 状态归属断言。
- 静态验证：最新 HEAD 源码与回归脚本检查 10 项均通过：SAF grant 获取/释放、Bundle 来源字段、四种来源恢复、非持久授权 fallback、滚动恢复及实例保护、切换来源/搜索清理旧滚动、DEX 索引不序列化、应用清单回调不覆盖 DEX 状态。未在完整 checkout 执行 Shell 回归脚本，未运行 Gradle、模拟器或真机 SAF/旋转测试。
- 下一步：检查 Dex Hook picker 返回 MainActivity 时的目标包名/规则编辑器草稿在 MainActivity 重建期间是否归属稳定；之后集中运行 Dia DEX Browser / Hook picker 两条针对性回归。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — Hook Hub 三类授权状态口径复核与 Dia DEX 浏览器状态恢复接管

- 本批起始 HEAD：`0b870cce4b4a06755183aea50ed060c386136e92`。
- Hook Hub 复核结果（无需改动产品逻辑）：
  - Root：执行实际 `su -c` 命令读取 UID 0、FX KernelSU 模块 enable/disable/remove-pending/version-mismatch 状态和 KSU 工具存在状态；失败/拒绝/超时不显示已授权。
  - LSPosed：分别显示 Manager 安装状态与 libXposed Binder 连接状态，并明确“作用域批准不等于目标进程注入”。
  - Accessibility：分别读取 Android 系统启用状态、FX 服务 Binder 连接和当前进程 PID 标记；系统开关已开但服务未连接时显示等待连接。
  - `onPause()` 对 Hook Hub 设置 `hookAuthorizationRefreshPending`，返回 `onResume()` 自动刷新 Root / LSPosed / Accessibility / Remote Files；无需额外增加重复刷新路径。
- 并行 Dia DEX 页面改动已接管：
  - `81161c1ea360456e8fcb33ba8f8d3778b405f8f0` — 切换查询/来源时清除旧结果滚动恢复状态，避免旧 DEX 页异步回调把新来源滚回旧位置。
  - `120ff9cf95f06201893e0e8174ad312a3b4c8643` — Activity 重建时对未持久化的 SAF URI 授权先尝试重新读取；只有 URI 本身无效才立即清空来源。
  - `e6c639436a8b4354d5557420e954a33f0fe32133` — DEX 页面 SAF 授权、来源/目标/查询/滚动恢复与异步解析回调回归断言。
- 以上 Hook Hub 仅为源码行为复核；DEX 回归脚本为新增静态断言，未执行完整 Host 回归、Gradle、模拟器或真机 SAF 提供方授权撤销测试。
- 本窗口本地实现提交：救援通知路由 `d4ee58b8be644037170a4467c4ebde0373aef4b7`；扫描滚动恢复 `cf39f274e81b1e853a70e27d6367ac0f06e5edd0`；扫描页清理队列返回后失效旧结果 `457526851701b46281533d9d50e393acd8adec01`；病毒库同步状态准确反馈 `4685a61500f20d68bd1c5c0a5a7a14f04310fd01`；病毒库页滚动恢复 `a54008ea5eae58823535a63f86a5e8b2e766fbfe`。对应测试/状态提交均已记录在本文件相邻条目。
- 下一步：检查 Dia Frida SAF 文件 picker 与后台 Worker 的请求归属/取消生命周期；随后对游龙安全护盾风险详情、告警和名单编辑页面做一组集中 UI 状态闭环。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — Hook Hub Root / LSPosed / Accessibility 真实状态口径核验

- 当前核验目标分支 HEAD：9ed8c3ede0d799386f437a2f4cacb33652ae8618。
- Hub 的三种授权状态由不同真实来源组成，未将某个配置开关或偏好值冒充系统授权：
  - Root：通过 RootAccess 执行 su 命令，必须返回 UID 0 才显示 Root 已授予；同时区分 FX KernelSU 模块启用/禁用/待卸载/版本异常与 KSU 工具存在性。RootAccess 默认命令上限 20 秒并回收 su 客户端。
  - LSPosed Hub：分别显示 Manager 是否安装与 libXposed Service Binder 是否连接；逐应用详情另通过 snapshot(packageName) 读取具体包是否在作用域，文案明确说明作用域批准不代表目标进程已注入。
  - Accessibility：读取 Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES 并匹配 FX AccessibilityService 组件；“服务已连接”还要求 FxAccessibilityService.isConnected()、service_connected 偏好及 service_pid 等于当前应用进程 PID。
- 本批未新增重复状态控件；扩展 fx-hook-native-ui-regression.sh，静态保护 Root UID 0、LSPosed Manager/Binder/逐包作用域以及 Accessibility 系统/服务/PID 四个契约点。
- 回归提交：f776f0c7348f458d49b0dc071c22ef769e6c9e27 — test(hook): assert real Root LSPosed and accessibility state。
- 静态验证：当前 HEAD 的 MainActivity 与回归脚本匹配上述状态源；未运行 Shell 脚本、Gradle 编译、模拟器或真机 Root/LSPosed Manager/Accessibility 授权切换。
- 下一步：回到 Hook 原生主页面/目标详情 UI 的可用性与生命周期测试；有真实 checkout 环境后运行 fx-hook-native-ui-regression.sh 与相关 Host 测试。固定 FX 1.0.0，不提前打包最终 APK / KernelSU ZIP。


## 2026-11-05 — Dia DEX 浏览器：恢复目标应用标题换行修正

- 本批起始分支检查点：`1d68d0cb7198fd810695eaec42a6c54d40293390`（GitHub 分支比较读取；不是沿用旧聊天 SHA）。
- 发现：`FxDiaDexBrowserActivity.restoreSourceAfterRecreation()` 在恢复已选应用时把两个反斜杠和 n 写入标题字符串，运行时会显示字面量 `\\n`，而不是将应用名称与包名分行，导致旋转/进程重建后的目标信息可读性错误。
- 修复：将恢复标题改为真实 Java 换行转义 `"\\n"`；不改动目标选择、DEX 解析、来源状态或权限生命周期。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaDexBrowserActivity.java`；`scripts/tests/fx-dia-dex-document-browser-regression.sh`；本状态文件。
- 提交：
  - `1bae397ae197d8d39a589cfd238c105e2b595cc2` — 修复恢复目标标题换行。
  - `5f309372b7298c4cfdc9c62aab5736ad82bf8fa3` — 增加针对性静态回归断言。
- 验证等级：已读取提交后的源码与测试脚本并核对目标字符串；未在完整 checkout 执行 Shell 回归脚本，未运行 Gradle、UI 自动化、模拟器或真机旋转/进程重建测试。不得标记为运行测试通过。
- 未完成：DEX picker 返回主界面时，目标包名/规则编辑器草稿在 MainActivity 重建期间的请求归属稳定性；SAF 提供方授权恢复仍需设备验证。
- 下一步直接任务：① 检查 Dia DEX picker 与 MainActivity 的 Activity Result 目标归属；② 检查游龙 Tasker/Widget 操作回执页面的状态呈现；③ 继续推进六 Tab 主壳与剩余原生页面批次。固定 FX 1.0.0，不打包最终 APK / KernelSU ZIP。


## 2026-11-05 — Dia Frida JS 脚本 SAF 导出回调生命周期保护

- 本批起始 HEAD：`d5858a8bda3718aced02d7b643b760f10ad2f1f0`。
- `exportScript(Uri)` 的文件写入成功/失败回调此前直接调用 `setStatus()`，未检查 Activity 是否已结束；用户在系统文件选择器返回后关闭页面，或导出后台任务晚于 Activity 生命周期结束时，旧 Activity 仍可能更新已脱离页面的 View。
- 修改：成功和失败两个 UI 回调均检查 `isFinishing()` / `isDestroyed()`，页面结束后不再触碰旧状态 View；不改变 SAF 写入、512 KiB 限制和用户选定文件行为。
- 修改 `fx-dia-frida-script-library-saf-regression.sh`：新增成功/失败两个回调的 Activity 生命周期断言。
- 提交：`9317a8a61efc45da9d26ff79a6f0c98872050349`（实现）；`d866f72f93512257d96f67b3676f4a8ccf85a0e3`（回归断言）。
- 验证等级：源码静态检查；未运行 Shell/Python、Gradle、UI 自动化或真实 SAF 提供方在 Activity 结束期间的写入测试。
- 下一步：继续核对 Frida 二进制导入与脚本库导出 Worker 在 Activity 结束时的取消/暂存文件清理边界；随后完成游龙安全护盾风险详情/告警/名单页面组。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — LSPosed 手动作用域操作改为有界后台执行

- 审计发现 Hook 目标详情的手动 `requestScope()` 直接在点击回调/UI 线程调用 libXposed Binder；虽然设置了 Handler 超时，但若 Binder 同步调用阻塞主线程，超时本身也无法执行。刷新/移除虽使用后台 Thread，却每次操作都创建新 Thread；若 Binder 长时间不响应，反复重试可能累积线程。
- 修复：申请、刷新、移除统一经由 Activity 级单线程 `ThreadPoolExecutor(1,1)`，队列容量 1、AbortPolicy；请求 Binder 调用移出 UI 线程。当前操作以 FutureTask 记录，取消/超时会 cancel 并尝试从队列移除；队列繁忙明确提示“状态未确认”，不显示虚假成功。Activity 销毁时取消操作并 shutdown executor。
- 保留原有 Manager 明确审批语义、系统应用二次确认、12/15/30 秒超时、目标包与 View generation 检查；不把“作用域已批准”误报为“进程已注入”。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`；`scripts/tests/fx-dia-lsposed-scope-regression.py`；本状态文件。
- 提交：`c3d7e52d6d1e966416fd07ee455c4852161c5c61`（有界后台执行）；`d5858a8bda3718aced02d7b643b760f10ad2f1f0`、`4b36849fead32ac0e1b2b34498497ece7c9e4e1b`（执行线程、队列、取消和移除路径回归断言）。
- 验证等级：最新 HEAD 静态检查确认 request/refresh/remove 都通过有界 executor，Binder 申请不在 UI 线程执行，FutureTask 超时/取消、队列满处理和 onDestroy shutdown 存在；回归脚本断言同步更新。未运行 Python Host 测试、Gradle、LSPosed Manager 或真机 Binder 阻塞测试。
- 下一步：等待当前 Actions；继续核对 DEX 文档 URI 权限释放与 Frida 导出 worker 销毁处理，随后做一次集中的 Dia/Hook/Shield Host 回归。固定 FX 1.0.0，不提前打包最终 APK / KernelSU ZIP。


## 2026-11-05 — Dia Frida SAF 与二进制导入 Worker 的 Activity 销毁取消

- 本批起始 HEAD：`5038c3294ac39ab884c861ba48cca4b9af34ba43`。
- 问题：Frida Activity 的单线程 Worker 在 `onDestroy()` 调用 `shutdownNow()`，但长文件读取循环本身不检查中断；正在导入 80/150 MiB ARM64 ELF 时，页面销毁后仍可能继续读取并推进到 Root 安装步骤。SAF 脚本/JSON 导入和脚本库导出也有同类循环。
- 修改 `FxDiaFridaActivity.java`：
  - 新增 volatile Activity 销毁标记和统一 `ensureFridaWorkerActive()` 检查（销毁或线程中断即抛出取消信号）。
  - JS 脚本导入、脚本库 JSON 导入、脚本库 SAF 导出和 Frida ELF 二进制读取循环逐块检查取消。
  - 二进制校验完成后、执行 Root 安装命令前再次检查；页面销毁后未开始的 Root 安装不会启动。
  - `onDestroy()` 先设置销毁标记，再递增请求代次、清理选择器状态并中断 Worker；二进制私有暂存文件仍由 finally 删除。
- 修改 `fx-dia-frida-script-library-saf-regression.sh`：断言销毁标记、线程中断检测以及至少五个后台读取/写入/安装检查点。
- 提交：`bb79a47200723c6435c77c5924c649318f2e09d7`（实现）；`99abdab26a4df70b054539dcfd73a344c87a5d72`（回归断言）。
- 验证等级：源码静态断言；未运行 Host Shell、Gradle、UI 自动化、真实 SAF 长文件读取取消或 Root 安装中断故障注入。
- 下一步：继续核对 Frida Server / Inject 运行生命周期是否在页面离开时仅停止本页发起的会话、不误停用户手动启动的实例；随后检查安全护盾名单管理页面编辑/保存/返回状态。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — Dia DEX picker 请求归属与 Activity 重建保护

- 本批基于最新实时文件读取；MainActivity 原始 Blob：`cba332fd957a10a952fd173a36379ce9d706705b`。
- 发现：DEX picker 的 Activity Result 处理仅校验返回数据中的目标包/方法签名，没有验证当前 MainActivity 是否确实仍有一个待完成的 DEX picker 请求。Activity 重建后，缺少可恢复的请求归属标记。
- 修复：新增 `pendingDiaDexHookPicker`；启动 picker 时置为 true；保存到 `Bundle`，重建时恢复；结果回调首先消费并清除标记，只有原请求仍待处理且结果成功时才进入既有目标应用、debuggable 用户应用及方法签名校验。未放宽任何 Hook 安全边界。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`；`scripts/tests/fx-dia-dex-document-browser-regression.sh`；本状态文件。
- 提交：
  - `8c1ea1269fea15631a09930a5cdea8592bce41a1` — 请求生命周期实现。
  - `1e1ebd30fe75379b9865bb5ee37eb87ef71cb941` — 增加请求保存、恢复、消费的静态回归断言。
- 验证：重新从指定分支读取 MainActivity 与回归脚本，逐项核对启动标记、Bundle 保存、Bundle 恢复、结果消费和脚本断言，均匹配。尚未执行完整 Shell 回归、Gradle 编译、模拟器或真机 Activity 重建测试；不标记为运行测试通过。
- 未完成/风险：若系统在启动内部 picker 时抛出 ActivityNotFoundException 或其他启动异常，当前请求标记需要异常回滚；需补充启动失败回滚与测试。还需在设备上验证进程回收后 picker 返回的 Activity Result 行为。
- 下一批：优先补齐 picker 启动异常回滚，然后转入游龙安全护盾风险详情/告警/名单编辑页面组的真实页面状态闭环；继续推进六 Tab 主壳。固定 FX 1.0.0，不打包最终 APK / KernelSU ZIP。


## 2026-11-05 — Frida Server 启停归属复核

- 本批起始 HEAD：`e57d1bc7e96512cffc243ef8b4a64ea46d72b502`。
- 复核 `FxDiaFridaActivity.startServer()/stopServer()` 与 `fx-dia-frida-server-lifecycle-regression.sh`：
  - 启动前枚举已有匹配进程；发现无 FX PID 记录的手动/外部 Server 时返回 `already-running-unmanaged`，不重复启动、不接管。
  - FX 自己启动时记录 PID、可执行文件路径、端口和进程 starttime；原子写 PID 文件。
  - 停止只读取 FX PID 文件，并校验 PID、starttime、可执行文件身份；只发送 TERM，等待上限 5 秒；PID 重用/记录冲突时 fail-closed。
  - 无 FX PID 记录时返回 `no-fx-owned-server`，不会按进程名批量杀掉用户手动运行的 Server。
  - 已有 Host 回归脚本覆盖未登记实例不重复启动、PID/starttime/可执行文件身份检查、只 TERM 和记录删除顺序。
- 结论：该工作线当前实现符合“只停止本页/FX 拥有的会话”的边界，本次无需改动代码；这是源码复核，不代表真机多实例/权限故障注入已验收。
- 下一步：集中检查安全护盾扫描结果详情、风险警告、白名单/黑名单管理的编辑、保存、返回与缓存刷新闭环；固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — 病毒库缓存状态与远端响应完整性并行修复接管

- 本批起始 HEAD：`fcd4859bbb22e695cbdcad597efe77c43c4d7ff3`。
- 并行工作线新增两项关键修复：
  - `bb23a4b70252ca075fcc4f20677de2883cc126a6`：病毒名单解析拒绝 HTML/JSON 错误对象/网关错误/空或不可解析包名列表；不再把代理错误页清洗成貌似合法的包名，失败时保留旧缓存。
  - `e57d1bc7e96512cffc243ef8b4a64ea46d72b502`：病毒库 UI 将“本地缓存可用”“最近尝试时间”“最近成功更新时间”“本次可达状态”分开显示；每个名单单独显示最近尝试结果与旧缓存是否沿用。
- 与本窗口改动衔接：UI 同步 Toast 仍按当前刷新中每项 `ListStatus.ok` 统计完整/部分/全失败；内容库以本次 `lastSuccessAt` 是否增加作为成功判据，旧缓存 ready 不会冒充本次同步成功。病毒库管理页滚动位置 Bundle 恢复仍保留。
- 并行 DEX Picker 修复：`7eedfc52a10064abef7de4a6a75bbd3f02f0fa1e` 在 Activity Result 启动失败时清除 pending picker 状态，避免下一次选择器结果被旧请求错误消费；`1e1ebd30fe75379b9865bb5ee37eb87ef71cb941` 覆盖 pending 请求恢复断言。
- 当前验证限制：源码/脚本断言已提交，但最新 GitHub Actions 工作流运行 `41907967627` 当时为 pending；并发 push 触发的旧运行多次 cancelled，尚无本窗口改动对应的绿色完整 CI 结果。不得将 cancelled/pending 计为通过。
- 下一步：继续游龙安全护盾风险详情/告警/白名单与黑名单编辑返回闭环；同时保留 Dia Frida SAF Worker 生命周期修复。固定 FX 1.0.0，不提前打包最终 APK / KernelSU ZIP。


## 2026-11-05 — DEX picker 异常回滚与安全护盾白名单写入保护

- 按当前分支实时文件重新核对：MainActivity Blob `12c174208851a0a9314a995a0b92b609b89a819e`；WarningActivity Blob `981dfd56983b2268412f87f4e739e1c34b5e723d`。并发提交已更新 MainActivity，已确认本批 DEX 状态字段仍在最新版本中。
- DEX picker：启动内部 Activity 若抛出 RuntimeException，立即清除 pending 标记并提示错误，防止残留请求状态；Bundle 保存/恢复及结果回调消费保护仍保留。
- 安全护盾风险详情：旧逻辑会在写入白名单时跳过无法识别的非空旧条目，导致这些条目静默丢失；包信息查询也未覆盖 RuntimeException。
- 修复：对非空非法旧条目 fail-closed，提示用户先核实原始内容并完全不写入；包查询运行时异常时显示明确错误并保持白名单不变。没有更改白名单存储键、系统应用排除规则或用户确认卸载流程。
- 改动文件：`MainActivity.java`、`FxYulongWarningActivity.java`、`scripts/tests/fx-dia-dex-document-browser-regression.sh`、`scripts/tests/fx-yulong-shield-native-regression.sh`。
- 提交：`7eedfc52a10064abef7de4a6a75bbd3f02f0fa1e`（DEX 启动失败回滚）；`28162c254edd12c9ea0eb662677ed98fdfa8ed7d`（DEX 回归断言）；`16a772632643d35ce699d47725d071f8a8847ca2`（白名单数据保护）；`1b9504b8147b0cc5b957a2e3869c0f7528cc3e1a`（Shield 回归断言）。
- 静态核验：重新读取最新分支源码和两份测试脚本，确认启动失败回滚、Bundle 状态、非法条目保护、异常捕获及对应断言均存在。未执行 Shell/Python/Gradle、模拟器或真机测试；不计为运行测试通过。
- 剩余事项：确认白名单管理器与风险详情页对历史非法条目的策略一致；验证大名单、权限可见性与旋转恢复；继续检查黑名单分页选择/暂存/取消/保存是否存在跨页丢选。
- 下一步：检查安全护盾黑名单编辑器的分页选择与状态恢复，再推进六 Tab 原生页面导航。固定 FX 1.0.0，不打包最终 APK / KernelSU ZIP。


## 2026-11-05 — DEX Hook ActivityResult 请求归属与 Dia 返回层级

- 本批开始时实时 HEAD：`09528a3a8fa5cc18b08c94b95586e19b5c267df6`；本批提交时重新读取最新 MainActivity、DEX Activity 和回归脚本，未覆盖并行工作。
- 接管并复核并行工作线已落地的 `pendingDiaDexHookPicker`：
  - 从 Dia “Dex 查找与解析”入口启动选择器前置为 pending；
  - MainActivity Bundle 保存/恢复该请求标记；
  - 只有仍有对应 pending 请求且返回 `RESULT_OK` 的结果才进入 Hook 编辑器；取消/无结果/无对应请求均丢弃。
  - 启动失败会清除 pending，防止下次无关 ActivityResult 被当作 DEX 方法结果。
- 本批修复：
  - 成功导入精确方法后置 `migrationChildActive=true`；退出 Hook 自定义规则页/应用列表时返回原 Dia “开发与监控 → Dex 查找与解析”分类，而不是跳过分类回到套件首页。
  - MainActivity 对返回包名增加 255 字符和包名格式校验；方法描述符限制 4096 字符；再次从 PackageManager 读取目标应用并校验仍安装、debuggable、非系统应用及 `DeveloperHookRule.parse`。
  - MainActivity 与 DEX 子页面都排除 `FLAG_UPDATED_SYSTEM_APP`，不只排除基础系统应用；更新系统应用不能作为 Hook 目标导入。
  - DEX 选择器启动异常时清理 pending 并给出可见错误。
- 提交：
  - `f9bca2493017a4b7e48efb6044a47eeebae5fbd8` — ActivityResult 返回 Hook 后保留 Dia 分类返回链，并增加目标包/描述符边界。
  - `fcd4859bbb22e695cbdcad597efe77c43c4d7ff3` — DEX 子页不向 updated-system app 提供 Hook 方法选择。
  - `8f95edf7a8e00cf94cb81f0cfd20640e75c7160d` — 回归脚本覆盖 pending 请求保存/恢复、结果归属、Dia 返回层级与输入边界。
- 验证：最新 HEAD 静态核对 10 项通过（pending 字段/Bundle/结果门控、启动路由、成功后 migration child、包名格式/长度、描述符长度、系统/更新系统应用排除、回归断言）。未运行完整 Shell 脚本、Gradle、模拟器或真机选择器取消/重建/返回测试。
- 下一步：继续补齐三套原生页面的返回栈/ActivityResult 测试，再集中运行 DEX Hook picker 与 DEX browser 两条针对性脚本；随后继续 Hook 主 Tab 运行态页面。固定 FX 1.0.0，不提前打包最终 APK / KernelSU ZIP。


## 2026-11-05 — 四个原生主 Tab 独立滚动位置恢复

- 本批开始时目标分支 HEAD：e57d1bc7e96512cffc243ef8b4a64ea46d72b502。
- renderNativePage() 重建 VPN / Ad-Hosts / 隐私 / 脚本页面树时此前不保存各 Tab 的滚动偏移；进入 Hook / 设置再返回也会重建主页面 ScrollView，长页面因此跳回顶部。
- 修复：为前四个主 Tab 建立独立滚动位置槽；切换主 Tab、进入 Hook Hub / Hook 应用列表 / Settings、Activity 保存状态前捕获位置；renderNativePage() 在页面布局后恢复目标 Tab 的偏移；Activity Bundle 保存/恢复四槽数组，值限制在 0–5,000,000；恢复回调以 render generation、当前 selectedBottomTab、ScrollView 实例防止过期页面回调。
- 提交：47b7b2e63a00b33ae46059619ebac27bff0de302 — fix(ui): preserve native primary tab scroll positions；8114b9a26a9cfd2fd758f61277c50069be9f852c — test(ui): cover native primary tab scroll restoration。
- 静态验证：当前分支已复核四槽数组、Bundle 保存/恢复、切换/离页捕获、generation 与 Tab/ScrollView 身份保护及 scrollTo 恢复；回归脚本包含同一契约。未执行 Shell 脚本、Gradle、UI 自动化或真机长列表/旋转测试。
- 下一步：检查 VPN 状态轮询和节点/订阅异步列表刷新是否覆盖用户当前页面状态；然后核对 Hosts 分页编辑器与 Script 列表在 Tab 切换后的滚动/搜索持久化。固定 FX 1.0.0，不提前打包最终 APK / KernelSU ZIP。


## 2026-11-05 — 安全护盾黑名单选择器跨页暂存上限与重建一致性

- 本批读取指定分支当前文件后定位到状态边界：选择器允许跨页累计勾选，但只有 `pickerStaged.size() <= 100` 才写入 Activity Bundle；原 UI 未限制选择数量，超过 100 后旋转/系统重建会静默丢失全部暂存选择。
- 修复：明确单次最多暂存 100 个应用；达到上限时立即撤销当前勾选并提示用户，已选项目不丢失；保存/恢复统一使用 `MAX_PICKER_STAGED` 常量；原有跨页累积、搜索、取消、确认加入和弹窗重建恢复链保留。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/BlacklistActivity.java`；`scripts/tests/fx-yulong-shield-native-regression.sh`；本状态文件。
- 提交：`ec7ac4610fb7c21c879a1f46c192b470c5489d18`（选择器限制实现）；`802f759ff271582a82af82aa530b7ba0e1367830`（回归断言）。
- 验证：重新读取最新源码和测试脚本，核对 100 项上限、超限拒绝/提示、Bundle 暂存、异步应用清单完成后重开 picker 及脚本断言，均匹配。未运行 Shell/Python/Gradle 或设备旋转、多页勾选测试；不计为运行测试通过。
- 仍需完成：真机测试 99/100/101 项选择边界、搜索切换和翻页时暂存不丢、取消不写入、确认一次性写入；检查白名单/黑名单数据异常时 fail-closed 策略一致。
- 本次读取到的 GitHub 分支 HEAD：`bbd261b7c3abae65b3d65dcccfe5e643f0b28f94`。实时状态文件在本条提交后将更新到新 HEAD。
- 下一步：继续安全护盾告警与名单编辑返回链；然后检查六 Tab 固定导航在 Dia / 游龙原生 Activity 之间的选中态和返回恢复。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — 四个原生主页面独立滚动位置真正恢复

- 本批起始 HEAD：`b010f60b7f21be1beb1c4ac20fa7520c5f54fd5d`。
- 并行提交 `47b7b2e63a00b33ae46059619ebac27bff0de302` 已加入四个原生主页面的滚动位置保存与切换时捕获，但源码复核发现 `renderNativePage()` 尚未读取数组并恢复位置；因此原实现只有保存、没有恢复。
- 修复 `MainActivity.renderNativePage()`：
  - 每次渲染新 Tab 先把 ScrollView 归零，防止继承上一个 Tab 的滚动位置；
  - 新页面布局完成后读取 `nativeTabScrollPositions[pageIndex]` 并 post 恢复；
  - 用 render generation、当前 page index 和 content-parent 三重检查拒绝过期页面回调。
- 修改 `fx-dia-native-tab-regression.sh`：覆盖四页独立位置、Bundle 保存、切换捕获、切换前归零、页面重建后恢复和旧回调失效。
- 提交：`bbd261b7c3abae65b3d65dcccfe5e643f0b28f94`（实现）；`b010f60b7f21be1beb1c4ac20fa7520c5f54fd5d`（回归断言）。
- 验证等级：源码静态检查；未运行 Shell 回归、Gradle、UI 自动化或真机四个主 Tab 长页面切换/旋转测试。
- 下一步：继续对四个原生主 Tab 的页面恢复与滚动锚点做一次成组回归；随后核对 Hook/Settings 与主 Tab 互相切换时是否错误保留/清除子页面状态。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — 安全护盾风险详情页滚动恢复

- 发现：`FxYulongWarningActivity` 风险详情页使用局部 ScrollView，Activity 重建后无法恢复用户正在阅读的风险原因/处理说明位置；页面此前没有保存滚动状态。
- 修复：将详情 ScrollView 纳入 Activity 字段；新增 Bundle 滚动位置键；在 `onSaveInstanceState` 保存，并在视图布局后恢复；保留 onResume 对目标安装状态的实时复核，不保存/恢复过期的安装状态。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongWarningActivity.java`；`scripts/tests/fx-yulong-shield-native-regression.sh`；本状态文件。
- 提交：`2d3de0cff52d550103e268dc4503a1c8095d94ae`（UI 状态恢复）；`6010d23759d4698ffc82678a611043cc700eee43`（回归断言）。
- 与本批上一项合并验收：黑名单多页 picker 选择暂存已限制为 100 项，超限明确拒绝并提示，确保可被 Bundle 完整保存；提交 `ec7ac4610fb7c21c879a1f46c192b470c5489d18`，测试 `802f759ff271582a82af82aa530b7ba0e1367830`。
- 静态核验：最新 WarningActivity、BlacklistActivity 和 Shield 回归脚本均重新读取，滚动字段/保存/恢复、暂存上限/提示、相应断言均存在。未运行 Shell/Python/Gradle、模拟器或真机旋转测试。
- 仍需完成：设备上验证风险详情长内容滚动恢复；黑名单选择器 99/100/101 项边界、搜索/翻页/取消/确认操作；名单管理器与扫描页返回后的刷新一致性。
- 本批读取时分支 HEAD：`6010d23759d4698ffc82678a611043cc700eee43`。状态文件提交后将更新分支 HEAD。
- 下一步：检查白名单选择器和黑名单选择器是否在列表内容变化后保留无效暂存项，接着检查六 Tab 选中态与 Activity 返回链。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — 六个主 Tab 固定契约与原生页面返回路由回归保护

- 复核实时实现：`FxNativeAppShell.kt` 的主标签固定为 VPN、Ad、隐私、脚本、Hook、设置，玻璃模式使用相同 `labels.size`；`FxNativeTabActivity` 将选中索引限制在 0..5；原生页面通过 CLEAR_TOP/SINGLE_TOP 返回 MainActivity，并由 `handleImportedNativeTabIntent` 分派到对应主 Tab。
- 复核 MainActivity 路由：索引 0..3 回到对应功能页面，4 打开 Hook，5 打开设置；直接选择顶层 Tab 会清理嵌套 Hook 编辑路由，避免错误保留旧详情页。
- 本批没有改动运行时代码，避免对已正确的六 Tab 行为制造重复补丁；新增测试保护，防止未来页面迁移改变六个标签顺序、玻璃模式数量、原生返回索引或 MainActivity 分派范围。
- 改动路径：`scripts/tests/fx-yulong-shield-six-tab-regression.sh`。
- 提交：`a399034c2ee22d77da69d9f36a629c9171b9191f` — 固定六 Tab 标签/索引/返回路由断言。
- 同批已完成的 Shield UI 修复：黑名单 picker 最多暂存 100 项（`ec7ac4610fb7c21c879a1f46c192b470c5489d18`）；风险详情页滚动恢复（`2d3de0cff52d550103e268dc4503a1c8095d94ae`）；对应回归测试分别为 `802f759ff271582a82af82aa530b7ba0e1367830` 与 `6010d23759d4698ffc82678a611043cc700eee43`。
- 静态核验：重新读取 MainActivity、FxNativeTabActivity、FxNativeAppShell.kt 和新测试脚本，核对标签顺序、数量、索引边界和返回路由，均匹配。未执行 Shell/Gradle/Compose UI 自动化或真机六 Tab 点击/返回测试。
- 当前分支 HEAD（状态文件提交前）：`a399034c2ee22d77da69d9f36a629c9171b9191f`。
- 下一步：检查 Dia 与游龙原生页面在系统返回键、顶部返回按钮和主 Tab 切换时的返回栈一致性；然后继续原生页面 UI 批次，优先未完成的 Dia / 游龙广告插件页面。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — 白名单全量格式校验与选择器防覆盖保护

- 复核并发更新后的 `WhitelistPickerActivity`：中央 `FxYulongWhitelistPolicy.isWellFormed(raw)` 会对整份 CSV 原子校验；只要存在一个非法条目、条数超限或原始文本超限，解析即整体拒绝。选择器新增 `whitelistDataCorrupt` 标记，并在 `saveSelected()` 前阻止写入，避免用户新增一个应用时覆盖掉损坏/不完整的旧白名单。
- 本轮未重复改写已存在的实现；新增 `fx-yulong-shield-native-regression.sh` 断言，保护全量格式检测与写入拦截。
- 改动路径：`scripts/tests/fx-yulong-shield-native-regression.sh`；实现已存在于 `WhitelistPickerActivity.java`（本轮复核 Blob `b0851d34fc8baa4ee1c5a31c227857f20babf5ed`）。
- 提交：`9a729f2ffd9477b495340b58c06defadc2b4690e` — 白名单异常源数据写入保护回归断言。
- 验证：最新源码与脚本静态核对全量格式检测、损坏标记、保存拦截和测试断言，均匹配；未执行 Shell/Gradle/设备测试。
- 仍需完成：确认白名单列表主页面对损坏数据同样不做部分写入；对黑名单现有 CSV 做同等级完整性审计；真机验证名单管理器从扫描详情返回后的刷新与提示。
- 当前读取的分支 HEAD：`0b01cb741db766102f38c76ee8f0d32c631dfc75`。
- 下一步：审计 `WhitelistActivity` 的“移除/清理系统应用”写入路径是否在原始数据损坏时 fail-closed，再检查黑名单数据写入路径。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — 白名单管理主页面写入路径审计（无重复补丁）

- 复核最新 `WhitelistActivity.java`：主页面使用中央 `FxYulongWhitelistPolicy.isWellFormed(raw)` 对整份旧数据校验；异常时设置 `whitelistDataCorrupt`，`saveWhitelist()` 拒绝覆盖；移除单项后若磁盘 commit 失败，会将该包恢复到内存集合。因此本轮没有重复修改已具备保护的代码。
- 静态核验：损坏标记、保存前拒绝、删除失败回滚三项均存在。未执行运行时测试。
- 关联白名单选择器已增加同样的异常源数据写入拦截，并在 `fx-yulong-shield-native-regression.sh` 增加回归断言（提交 `9a729f2ffd9477b495340b58c06defadc2b4690e`）。
- 本次读取的分支 HEAD：`42527280ac17ecf4f4c280e9f33d00bcc8899706`；此后应继续以 GitHub 分支最新 HEAD 为准。
- 下一步：审计黑名单 CSV 读取/写入是否存在超大数据、非法包名或部分写入风险；之后回到 Dia / 游龙广告插件原生页面批次。固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — Dia DEX picker 请求回滚与 Shield 白名单损坏数据保护

- 本批状态追加时实时分支 HEAD：`0885b7e3089a47ed8f660b77860c33006df4f206`；实时状态文件 Blob：`0f134018727d1ea36f691c006d7d42bd63d68c39`。并发推进时重新读取后追加，未覆盖此前记录。
- Dia DEX picker：MainActivity 新增待处理请求状态；启动时登记、Activity Bundle 保存/恢复、结果返回时先消费请求标记；若启动 Activity 抛出运行时异常则回滚待处理状态并显示错误。只有真实待处理请求的成功结果才进入原有目标包、debuggable 用户应用与完整方法签名校验。
- Shield 白名单：共享 `FxYulongWhitelistPolicy` 新增整份 CSV 格式校验；存在非法包名、空字段、超条数或超原始文本上限时整体拒绝，而不是丢弃坏条目后继续信任剩余部分。扫描端因解析返回空集合继续 fail-open，不用损坏白名单压制风险结果。
- 名单管理器、全屏选择器、风险详情页均接入同一完整性判断；原白名单数据损坏时阻止增删/新增写入，避免将旧数据静默覆盖成局部列表。Picker 同时禁用最终提交入口并显示警告。
- 改动路径：
  - `adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`
  - `scripts/tests/fx-dia-dex-document-browser-regression.sh`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongWhitelistPolicy.java`
  - `adhook/app/src/test/java/de/privacyguard/adhook/imported/shield/FxYulongWhitelistPolicyTest.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/WhitelistActivity.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/WhitelistPickerActivity.java`
  - `adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongWarningActivity.java`
  - `scripts/tests/fx-yulong-shield-native-regression.sh`
  - 本状态文件。
- 提交：
  - `8c1ea1269fea15631a09930a5cdea8592bce41a1` — DEX picker 请求生命周期保存/恢复/消费。
  - `7eedfc52a10064abef7de4a6a75bbd3f02f0fa1e` — DEX picker 启动失败回滚。
  - `1e1ebd30fe75379b9865bb5ee37eb87ef71cb941` — DEX picker 请求生命周期断言。
  - `ed9e8901ce04bfa1af2b68b51166e802de1e250a` — 白名单 CSV 整体格式校验。
  - `efaf477726704a125dbefe64a1b8fb1aea4fabc8` — Policy Host 测试覆盖任意非法条目与空 CSV 项。
  - `4df4163c57cc693fce978b1fce1ef97be4cd10e6` — 白名单管理页损坏数据写入保护。
  - `b05a40016fb1e9881e50fb3062c84fa9ac41c56c` — 白名单 Picker 损坏数据写入门禁。
  - `e85605d790900f2e860065b9b1246e6e332749b2` — 风险详情页共用 Policy 完整性校验。
  - `816ea665e874237a80d000e92db03f88aeb940d6` — Shield 回归脚本保护上述完整性门禁。
- 静态复核：从最新分支重新读取 MainActivity、DEX 回归脚本、Policy、Policy Host 测试、WhitelistActivity、WhitelistPickerActivity、WarningActivity 和 Shield 回归脚本；请求标记/恢复/消费/异常回滚、CSV 整体校验、损坏标记、写入拒绝和回归断言全部匹配。未运行 Shell/Host JUnit/Gradle/UI 自动化/设备测试；不声称运行测试通过。
- 未完成：黑名单 CSV 仍使用宽松分割与异步 `apply()`，需检查原始数据损坏时的覆盖风险；白名单/黑名单页面的真实 Android 返回链与重建流程仍需设备验证。
- 下一批直接任务：① 为黑名单增加有界完整性解析与写入失败回显，防止损坏条目被静默覆盖；② 检查安全护盾名单页面在切换/返回后的数据刷新；③ 继续未迁移的 Dia/游龙广告原生页面批次。固定 FX 1.0.0，不打包最终 APK / KernelSU ZIP。


## 2026-11-05 — 安全护盾黑名单 CSV 完整性与写入原子性修复

- 本批起始依据是实时分支最新状态；发现黑名单 UI 与前台守护服务分别宽松分割 CSV，非法条目会被部分接受；UI 写入使用异步 `apply()`，且删除/清空/批量加入操作没有检查持久化是否成功，可能出现界面显示已变更但磁盘未确认、或后续保存时覆盖异常原始名单。
- 新增 `FxYulongBlacklistPolicy`：统一 1 MiB 原始文本上限、10,000 条上限、255 字符包名限制；整份 CSV 任一条目无效即整体拒绝，不返回部分名单；序列化拒绝非法条目/超限集合。
- 修改 `BlacklistActivity`：加载时识别损坏数据并在页面显示警告；损坏状态禁止新增、清空和移除；持久化改为检查 `commit()` 结果；批量加入、单项移除、清空在保存失败时回滚内存集合。
- 修改 `FxYulongProtectionService`：前台守护改用同一原子解析策略；遇到损坏/超限名单时不部分执行，安全地不触发名单提醒，避免误报/错误拦截。
- 新增 `FxYulongBlacklistPolicyTest`，覆盖合法解析/去重、整表拒绝、空字段、null/空值、超大输入、条数上限、序列化拒绝非法项和往返一致性；扩展 `fx-yulong-shield-native-regression.sh` 保护 UI、服务和策略一致性。
- 改动路径：`FxYulongBlacklistPolicy.java`、`BlacklistActivity.java`、`FxYulongProtectionService.java`、`FxYulongBlacklistPolicyTest.java`、`scripts/tests/fx-yulong-shield-native-regression.sh`、本状态文件。
- 提交：`8b6ca25d4bb5b139fa715c9fb5df5724c4a413e8`（新增策略）；`c7b9fff2fb7be3e13f6168d43e2766a6db09f3ed`（UI 完整性与 commit 写入）；`97c31af840245bbcdd2498f1d7ed8e2cbb6dc8c5`（失败回滚/损坏写入门禁）；`9103e1f909c899ac81ddda204f5ddb72a53b7bce`（守护服务统一解析）；`3d0566c8eebf4b80e494466c57c24d896f0db692`（Policy Host 测试）；`1bd9ae1485c541176173f71d67ddbb49335a316e`（Shield 回归断言）；`c65d230cd5249f0d683bf3035fd098672a6c0946`（null 偏好值保护）。
- 静态核验：重新读取策略、Activity、Service、JUnit 测试与 Shell 回归脚本，确认有界解析、整表拒绝、损坏提示、写入 commit、失败回滚及服务共用解析均匹配。未运行 JUnit/Gradle/Shell/模拟器/真机测试；不可宣称运行测试通过。
- 剩余事项：检查黑名单数据从旧版迁移时的真实格式兼容；设备验证损坏名单 fail-open 的用户提示和恢复流程；测试 commit 失败故障注入与 10,000/10,001 条边界。
- 本次读取时分支 HEAD：`c75e31229f4dd8cedd904ec0442f7b5cefb6410e`。
- 下一批：回到 Dia / 游龙广告插件原生页面，优先修复页面导航、列表/表单状态恢复和真实交互闭环；固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — Shield 黑名单数据完整性与原子保存

- 追加前实时 HEAD：`48ba69881d62a3b60d796e93024de6ff7f07a4ba`；状态文件 Blob：`cdfac6c7aec812f0d36647ed94e5ad247b54167f`。
- 复核更正：黑名单独立策略 `FxYulongBlacklistPolicy` 已存在，具备 1 MiB/10,000 项上限、整份 CSV 校验及拒绝坏条目序列化；扫描服务复用该策略。旧状态中“黑名单仍宽松解析”的描述已过时。
- 本批修改：`BlacklistActivity` 对 SharedPreferences 类型/读取异常 fail-closed；原始 CSV 损坏时阻止新增、移出、清空；写入采用同步 `commit()` 并检查结果；失败时提示用户并回滚新增/移出/清空的内存状态。保持原 `shield_prefs/blacklist_pkgs` 数据兼容。
- 路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/BlacklistActivity.java`、`scripts/tests/fx-yulong-shield-native-regression.sh`、本文件。
- 提交：`c75e31229f4dd8cedd904ec0442f7b5cefb6410e`（读取异常保护）；`49f2d1096d0c676c91944aee2422216ec4b9e004`（回归断言）。
- 最新 Blob：Activity `c8b0ac25118aa1c906bc01b3771be7c58fa5a697`；Policy `ce5b5e50bd52317f295132138cff92d1d88cce8d`；Host tests `01f5ae7286f26f0bdfd714209aabaa7967dc12cb`；regression `7ecae19785738b95f2c5bf0c7ebbd226fbdbc3b9`。
- 静态复核通过：整份校验、损坏门禁、commit 结果检查、失败提示和新增/移出/清空回滚、Host 测试及脚本断言均存在。未运行 Shell/JUnit/Gradle/设备测试，不宣称运行通过。
- 未完成：黑白名单页面真实 Android 重建/返回刷新及持久化故障注入仍需设备验证。下一批检查 Dia 23.11 与游龙广告插件原生页面的导航、编辑器和状态恢复。固定 FX 1.0.0，不打包最终 APK/KernelSU ZIP。


## 2026-11-05 — 黑名单偏好读取异常的服务端兜底

- 追加前实时 HEAD：c680303993c7ec854d448f62ee00c606dd7c89ef；状态文件 Blob：acfd698ce6efc34332877bc09934935a90f79a7d。
- 在已有黑名单完整校验/原子写入基础上，FxYulongProtectionService 的前台提醒读取现在通过 split(SharedPreferences) 统一读取并调用 FxYulongBlacklistPolicy.parse；若读取字符串时出现 RuntimeException（如偏好值类型不匹配），记录诊断并返回空集合，本轮不执行黑名单提醒，服务不会因该异常退出。
- fx-yulong-shield-native-regression.sh 同步改为检查真实的 SharedPreferences 守护读取入口、RuntimeException 捕获与 fail-open 返回。
- 提交：48ba69881d62a3b60d796e93024de6ff7f07a4ba（服务读取保护）；7d1a707bdd0e628fd7ce60b493fbe98ac5116eea（对应回归断言）。
- 静态复核：当前 Service 使用 guarded helper；测试脚本断言与实现匹配。未运行 Shell/JUnit/Gradle/模拟器/真机故障注入。
- 下一批按 UI 优先策略回到 Dia / 游龙广告原生页面批次；固定 FX 1.0.0，不提前打包 APK / KernelSU ZIP。


## 2026-11-05 — CI 分层：推送只跑受影响 Host 回归，完整构建改为 PR/手动

- 发现本分支短时间内连续提交会反复取消完整 Actions，完整测试与 Gradle APK 验证长期停留在准备/恢复步骤；这既没有形成有效验收，也与“每批只做必要针对性测试”冲突。
- 调整 `build-fx-adhook.yml`：移除每次 push 自动执行的完整验证/构建；完整迁移验证保留 PR 与手动触发。原有 `migration_complete` 手动门控继续保留，默认 false；迁移/验收未完成时不会启用 APK 构建。
- 新增 `fx-targeted-regression.yml`：推送只按改动路径运行对应 Host 回归，不运行 Gradle、不打包 APK/KernelSU ZIP。覆盖 Dia Frida/脚本库、Hook/六 Tab/自定义 Hook、VPN/DNS/隐私、GPS/备份/代理、DEX SAF、游龙 Shield/黑白名单/扫描，以及 Root Proxy 原子锁。对同一批次重叠命中的测试做路径去重；变更 Shell/Python 文件时先做语法检查。
- 新工作流使用独立 concurrency group，只取消被更新提交替代的旧 targeted run；完整构建不再与每次小提交争抢。
- 改动路径：`.github/workflows/build-fx-adhook.yml`、`.github/workflows/fx-targeted-regression.yml`、本状态文件。
- 提交：`f3dd5c07a3a7f37f22c225d641ff9154f5246d96`（完整构建转 PR/手动）；`69a5ae3770ff0d04c9eb799e6ca5f0839157bc90`（新增 targeted Host workflow）；`4ff94da29318b24190a1537855f2e52c98ded63d`（回归去重）；`87ded6c3fb1d0cf1b70d50c4fd204c86bc878a92`（补齐 Dia 表单、VPN/DNS/隐私测试映射）。
- 静态验证：最新 HEAD 确认完整 workflow 不再有 push trigger，PR/manual 保留；targeted workflow 有 push path filters、去重、Shell/Python 语法检查和对应页面测试映射。新增工作流的实际执行结果仍需读取 Actions；不把工作流文件静态检查当成测试通过。
- 下一步：确认首个 targeted run 能完整执行；继续修复 Frida SAF 导入在 Activity 重建时丢失 URI/任务的问题，并补足 Shield Rescue 系统返回键回归。固定 FX 1.0.0，不提前打包最终 APK / KernelSU ZIP。


## 2026-11-05 — Dia Frida 主页面日志清空的父目录符号链接防护

- 追加前实时分支 HEAD：d254787c86d005f785c16473dedc9a291907f6e5；实时状态文件 Blob：40614a4fb9385cb113e67590cc09d1a57e667f3b。并发更新时重新读取并追加，没有覆盖其他工作线记录。
- 发现 Frida 管理页的“清空当前目标注入日志”操作只检查目标文件 `-f` / `! -L`，但没有检查 `/data/adb`、`privacyguard`、`dia-frida` 和 `logs` 父目录；父目录若被替换为符号链接，Root 截断操作可能偏离 FX 预期日志目录。独立 SessionLogActivity 已有更严格目录检查，两条入口不一致。
- 修改 FxDiaFridaActivity：新增 `checkedSessionLogDirectoryPrefix()`，逐层要求上述目录存在且不是符号链接；目标文件必须存在、为普通文件且不是符号链接；截断后 chmod 600 并输出明确成功标记。命令退出失败、目录异常、文件缺失或无成功标记时，UI 显示未确认清空及截断后的错误详情，不再显示模糊退出码/假成功。
- 修改 `fx-dia-monitor-event-view-regression.sh`：增加父目录逐层保护、实际命令使用 guard、缺失/符号链接拒绝、成功标记和失败 UI 回显断言。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java`、`scripts/tests/fx-dia-monitor-event-view-regression.sh`、本状态文件。
- 提交：`1ff69f240be9df537041fbabefdf7afb29cfbb38`（实现）；`9d3291f0f467e97939fac36255fe49076c47d4bc`（回归断言）。
- 静态复核：重新从分支读取 Frida Activity 与回归脚本，确认目录 guard、目标文件 no-symlink 条件、截断成功标记、仅成功后显示已清空、失败详情回显以及全部回归断言存在。未运行 Shell 回归、Root 故障注入、Gradle、UI 自动化或真机测试。
- 后续：统一检查 Frida Gadget/Server 产生的其余日志写入路径是否采用同一目录安全契约；然后继续未完成的 Dia 原生页面与游龙广告插件页面。固定 FX 1.0.0，不生成最终 APK / KernelSU ZIP。


## 2026-11-05 — 游龙广告通用设置 SAF 备份请求生命周期

- 状态文件追加前分支 HEAD：`b39e57a1e0ffb6945d9569594f51166b5006df60`。
- 修复 `FxYulongAdGeneralActivity` 的 JSON 导入/导出文件选择器状态：保存/恢复 pendingExport（并限制恢复长度不超过 1 MiB）、分别保存导入/导出请求标记；拒绝没有对应未完成请求的迟到 Activity Result；选择器启动异常时回滚 pending 状态；用户取消时清理待导出数据并明确提示未写入/未修改配置。
- 改动：`adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdGeneralActivity.java`；`scripts/tests/fx-yulong-ad-general-import-regression.sh`。
- 提交：`4617aabb31006bd215007240e984127ebd138851`（Activity 生命周期修复）；`3915ce2436521d7a58a4506d6518869cfcd23b0e`（回归断言）。
- 回归脚本增加 pending 标记、Bundle 保存/恢复、迟到结果拒绝、启动失败/取消清理断言，并保留既有 JSON 字段验证断言。尚未执行该脚本、javac/Java、Gradle、模拟器或真机验证；不能宣称测试通过。
- 下一步：继续游龙广告原生页面与 Dia 原生页面导航/状态闭环；先查同类 SAF 生命周期问题，再做页面交互回归。固定 FX 1.0.0，不生成最终 APK / KernelSU ZIP。


## 2026-11-05 — Frida 脚本库导入覆盖预览与回归测试同步

- 首次 targeted Host run `41909724439` 在 Frida SAF 回归脚本第一项失败：测试仍要求旧的 Activity 内联 schema 字符串和 `writeFridaScriptLibrary(merged)`，而实现已拆分为 `FxDiaScriptLibraryStore` / `FxDiaScriptLibraryPolicy`。这是回归断言过期，不是 schema 校验缺失；当前 Store 仍校验导入 schema，Policy 仍限制单脚本 128 KiB、脚本数 64 和 JSON 1 MiB。
- 同时修复真实的导入覆盖风险：文件导入与剪贴板导入现在都先调用 `previewImport`，显示导入数量及最多 8 个同名覆盖项，必须再次点击“确认覆盖并导入”才写入。Store 的默认 `mergeImport(context,json)` 不再允许静默覆盖；确认版在写锁内重新检查重叠名称，预览后出现的新同名项会拒绝写入并要求重新预览。
- 回归脚本改为分别读取 Activity、ScriptLibraryStore 和 ScriptLibraryPolicy，验证 schema、大小/数量限制、覆盖预览、确认列表与锁内复核；不再依赖已废弃的旧实现字符串。
- 改动路径：`FxDiaScriptLibraryStore.java`、`FxDiaFridaActivity.java`、`scripts/tests/fx-dia-frida-script-library-saf-regression.sh`、本状态文件。
- 提交：`c5bdbec5b81c7acfe1f7973a49762904b5a32896`（默认禁止未确认覆盖）；`b39e57a1e0ffb6945d9569594f51166b5006df60`（文件/剪贴板双路径预览确认）；`c1fe04977f622669d0fa4443ebbdeb8a51b22f1b`（更新 Store/Policy 回归断言）。
- 静态验证：最新 HEAD 确认默认合并拒绝覆盖、确认名单二次校验、文件与剪贴板都走预览、UI 显示同名项；回归脚本所有新增关键断言与当前源码一致。修复后的 targeted Actions 结果待读取，未声称测试通过。
- 下一步：确认 Frida SAF 回归通过；继续保存/恢复文件选择返回后的 pending import URI，避免 Activity 旋转取消后台导入后丢失本次选择。固定 FX 1.0.0，不提前打包最终 APK / KernelSU ZIP。


## 2026-11-05 — 游龙广告原生页面底部导航选中项修正

- 发现游龙广告套件的 7 个原生页面均调用 `setContentViewWithNativeTabs(root, 5)`，但 FX 六个主 Tab 的索引定义为 VPN=0、Ad=1、隐私=2、脚本=3、Hook=4、设置=5，导致用户进入广告过滤页面时错误高亮“设置”。
- 已将以下 7 个页面统一改为选中 Ad（索引 1）：`FxYulongAdActivity.java`、`FxYulongAdGeneralActivity.java`、`FxYulongAdSummaryActivity.java`、`FxYulongAppStatsActivity.java`、`FxYulongAppWhitelistActivity.java`、`FxYulongDnsActivity.java`、`FxYulongFirewallActivity.java`。
- 对应实现提交：`6dc3bbb6a7277ac12c6d259af8b3b846d23835db`、`d80fb0684f7425d89b22376f327739808bb6ada0`、`7f9528033fa9310b3c589e09f601006b4fdf318b`、`eaa2c2792da034424b63ccde900a7872bd5ffc3e`、`5fa94990e1c1d01d56977f692cee04526fb6782d`、`e3ed70055737dc48df4dc542167ccb38e0c296c6`、`5797f316836174f20d3882089d6ec87f7001cffb`；回归断言提交：`f7409a7e8237b67500fd722a51679ff39998e9cc`。
- 更新 `scripts/tests/fx-imported-suite-native-routing-regression.sh`：逐一检查上述 7 个页面必须选择索引 1，并禁止仍使用索引 5。
- 静态复读源码确认 7 个页面均已改为索引 1，回归脚本包含对应断言。尚未运行 Shell 回归、Gradle、模拟器或真机测试；不宣称测试通过。
- 下一步：继续修复 FX 原生页面的导航/状态恢复问题，优先 Dia / 游龙插件实际页面体验；固定 FX 1.0.0，不打包最终 APK / KernelSU ZIP。


## 2026-11-05 — 游龙广告主页面滚动位置恢复

- 修复前分支 HEAD：`a42e04a5647dbf34c67e133ebbe4f21d91efe7f5`。
- 修复 `FxYulongAdActivity` 原生页面 Activity 重建时滚动位置丢失：将 ScrollView 提升为 Activity 字段；保存 `scrollY` 到 Bundle；重建后等待设备端配置读取及列表绑定完成，再通过 ScrollView.post 恢复位置；用户主动切换游龙子页面时清零待恢复位置并回到页面顶部，避免把旧页面位置带到新页面。
- 改动：`adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java`；`scripts/tests/fx-yulong-ad-activity-state-regression.sh`。
- 提交：`0a8b4d978429cc5fde75e7dbe0d1d6c28f2b7bac`（页面滚动恢复）；`15cd96f8df02cf7d088aa25fc5ea4b236bbcba30`（回归断言）。
- 已重新从 GitHub 读取源码与回归脚本，并逐项确认 Bundle 保存/恢复、异步配置加载后恢复、页面切换清零等断言均存在。仅做远端源码静态核对；尚未实际执行 shell 回归脚本、Gradle、模拟器或真机测试。
- 当前最新 HEAD（写入本记录前）：`15cd96f8df02cf7d088aa25fc5ea4b236bbcba30`。
- 下一步：继续游龙原生子页面状态与交互检查，优先检查列表搜索/分页/批量编辑的重建行为；不打最终包，不改变 FX 1.0.0 版本号。


## 2026-11-05 — 六 Tab 原生套件快捷入口回归断言修正

- Targeted run `41910532515` 失败于 `fx-imported-suite-native-routing-regression.sh`：测试仍要求旧四页范围 `0..3` 和旧 `openImportedNativeTab` 路由；当前实现已固定六 Tab，快捷入口应允许 `0..5` 并统一调用 `handleNativeTabSelection(tab)`。
- 核对 `MainActivity.handleImportedNativeTabIntent` 后确认当前代码已对六个 Tab 做边界检查并走统一选择器；因此修正过期测试断言，不回退六 Tab 功能。
- 提交：`31aefc8bd9a5bcc1584fd02edb5dae3883e831d5`。
- 验证等级：静态核对 MainActivity 的 0..5 边界、统一路由与测试断言一致；修复后的 targeted run 待读取。
- 下一步：确认六 Tab/Shield/Frida targeted Host 回归完成；继续 Frida SAF 导入 URI 重建恢复。固定 FX 1.0.0，不提前打包最终 APK / KernelSU ZIP。


## 2026-11-05 — 游龙广告子页面切换时保留未保存编辑草稿

- 修复前分支 HEAD：`887475ac5eaff7c5cd21ee83aee679e476e1c549`。
- 发现并修复一个 UI 数据丢失问题：游龙广告子页面通过 `open()` 重建视图时会清空 `draftFields`，导致用户在过滤列表、DNS、域名名单、计划任务或配置档等页面输入但尚未提交的内容，在切换子页面后丢失。新增统一 `captureDrafts()`，页面切换前先快照当前 EditText，再重建目标页面并按稳定字段 key 恢复草稿；Activity 保存状态也复用同一快照方法。
- 改动：`adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java`；`scripts/tests/fx-yulong-ad-activity-state-regression.sh`。
- 提交：`0d8decfd3514ed4e91feeb5e221c1d05e275ec9d`（页面切换保留草稿）；`b4ab67ec2618c03a25337e4507b3e984cbda5a68`（回归断言）。
- 静态复核已从 GitHub 重新读取源码与脚本，确认快照发生在 `render()` 之前、恢复发生在新控件创建之后，并确认滚动位置 Bundle 恢复仍保留。尚未实际运行回归脚本、Gradle、模拟器或真机测试。
- 当前最新 HEAD（写入本记录前）：`b4ab67ec2618c03a25337e4507b3e984cbda5a68`。
- 下一步：检查游龙原生 UI 其余可编辑页面的草稿/列表/返回行为，并开始 Hook 主页面与应用详情页面的端到端导航整合；不打最终包，不改变 FX 1.0.0 版本号。


## 2026-11-05 — Hook OBSERVE 日志刷新单飞与队列保护

- 修复前分支 HEAD：`50ffef52dc9d20e4fd96cf1994acf3ccbefe0c71`。
- 修复 `FxHookObservationLogsActivity` 连续点击“刷新日志”可能向单线程 Executor 的无界队列累积多个 Root/logcat 任务的问题。新增 AtomicBoolean 单飞门闩；任务执行期间禁用刷新按钮，重复触发会明确提示等待；RootAccess RuntimeException 转为可见失败结果；完成、提交被拒绝、Activity 销毁均释放门闩；保留 generation 防止过期结果覆盖页面。
- 改动：`adhook/app/src/main/java/de/privacyguard/adhook/FxHookObservationLogsActivity.java`；新增 `scripts/tests/fx-hook-observation-logs-regression.sh`。
- 提交：`68dd9fbd4c930a4aabf3e4aa1ec462870faa9106`（刷新队列保护）；`d3a3fae410bf6fe1148363ecb02d98300a58a234`（回归脚本）。
- 从 GitHub 重新读取 Activity 和脚本，静态确认单飞获取早于 worker.execute、完成/拒绝/销毁路径释放门闩、按钮状态恢复、RuntimeException 处理和 generation 保护均存在。尚未实际运行该脚本、Gradle、模拟器或真机测试。
- 当前最新 HEAD（写入本记录前）：`d3a3fae410bf6fe1148363ecb02d98300a58a234`。
- 下一步：继续 Hook 应用列表/详情/自定义规则页面的状态和交互闭环，优先修复可复现的数据丢失或导航错误；不打最终包，不改变 FX 1.0.0 版本号。


## 2026-11-05 — 游龙广告编辑页状态回归断言更新

- Targeted run `41910874212` 在 `fx-yulong-ad-activity-state-regression.sh` 失败：脚本仍要求旧版不保留草稿的 `open(String p)` 单行实现；当前实现已在切页前 `captureDrafts()`，重置新页滚动位置，渲染后 `restoreDrafts(drafts)` 并重新绑定。
- 已移除过期的旧实现断言，改为验证操作顺序：先捕获草稿，再切页/重置滚动，渲染后恢复草稿，最后绑定控件；避免测试把已修复的状态保留行为误判为失败。
- 提交：`72d731d6146415ae427a330d439777fbf2dd474b`（更新页面切换状态断言）；`2659ab7adf7aaed127e5d3a1c60ab460f7ab4efb`（修正测试方法边界换行）。
- 当前分支后续还增加 Hook OBSERVE 日志刷新串行化：防止重复 Root logcat 请求，刷新期间禁用按钮，异常/队列满明确显示状态。提交 `68dd9fbd4c930a4aabf3e4aa1ec462870faa9106`。
- 验证等级：源码与断言静态一致；修正后的 targeted run 仍需读取最终结果。
- 下一步：完成 Frida SAF 导入 URI 的重建恢复与覆盖预览回归；继续核对六 Tab/Shield/Hook 导航返回链。固定 FX 1.0.0，不提前打包最终 APK / KernelSU ZIP。


## 2026-11-05 — Hook 授权中心往返保留应用列表视口

- 修复前分支 HEAD：`c7c7a94ec6e762fcb7ed68ae8756fe06a443afce`。
- 修复 Hook 应用列表进入“授权状态与系统设置”（Root / LSPosed / 无障碍 Hub）再返回时，未捕获当前列表滚动位置的问题。现在 `showHookHub()` 在切换界面前检测当前是否为 Hook 应用列表，并调用现有 `captureHookAppListState()`，保留搜索词、滚动位置和已展开分页数量；返回应用列表时由既有加载/渲染逻辑恢复。
- 改动：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`；`scripts/tests/fx-hook-native-ui-regression.sh`。
- 提交：`9e9336ae3a8ea17bb513642b6548a39b9f16a897`（状态捕获）；`be7d6e656485536859b248bc1dd66905e695450b`（回归断言）。
- 已重新读取源码与测试脚本，确认状态捕获在取消 Hook scope 操作和重建 Hub 视图之前执行，且回归脚本包含该约束。尚未执行脚本或 Android 构建/真机测试。
- 当前最新 HEAD（写入本记录前）：`be7d6e656485536859b248bc1dd66905e695450b`。
- 下一步：继续检查 Hook 列表、详情和自定义规则编辑器的往返路径；不打最终包，不改变 FX 1.0.0 版本号。


## 2026-11-05 — 游龙广告草稿跨多个子页面持续保留（修正前一批的不足）

- 本次修复前 HEAD：`d3a3fae410bf6fe1148363ecb02d98300a58a234`。
- 复查前一批的草稿实现后发现其不足：只捕获当前页面草稿并立即恢复到新页面；由于新页面的字段 key 通常不同，离开原页面后草稿仍会丢失，不能算真正跨页面保留。本次改为 Activity 级 `retainedDrafts` Bundle：恢复时先装入已保存草稿；每次切换页面前将当前页面字段合并进既有草稿；新页面仅恢复自己拥有的字段，但其他页面草稿继续留在 Bundle；Activity 重建时保存全部页面草稿。
- 源码提交：`dfb82bc55803a6411bcd23b62eda06503cc2469d`，文件 `adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java`。
- 回归断言提交：`c4eabe5add01dc96e40ef8d4e23809f2b3b51b78`，文件 `scripts/tests/fx-yulong-ad-activity-state-regression.sh`。断言检查 retained bundle 初始化、Activity 恢复、捕获时合并既有数据、页面切换前捕获、页面切换后恢复和保存全部草稿。
- 已从 GitHub 重新读取源码及脚本，逐项静态检查以上断言存在；尚未执行该 Shell/Python 回归脚本、Gradle、模拟器或真机测试。此前“切换页面保留草稿”的描述仅在同 key 字段/当前页面范围成立，本条记录明确更正为真正的跨页面累计保存。
- 当前 HEAD（本记录写入前）：`1f1460566ef61fa79fa06fc7a1f6edc14e69600c`。
- 下一步：继续 Hook 原生页面和游龙插件交互验证，避免重复只做状态变量修补；固定 FX 1.0.0，不生成最终 APK / KernelSU ZIP。


## 2026-11-05 — Dia Frida 脚本库 SAF 导入预览 URI 重建恢复

- 修复前分支 HEAD：`6a841278428fe58e141e889b7c4927dbc68197d4`。
- 修复 Dia Frida 脚本库从 SAF 选择 JSON 后，Activity 若在后台读取/覆盖预览对话框期间重建，局部变量中的 URI 与预览流程会丢失的问题。导入选择器请求持久化读取授权；若 provider 返回可持久化 read grant，则调用 `takePersistableUriPermission`；将待确认导入 URI 与 grant 标记保存到 Bundle；Activity 重建后先重新读取脚本库，再从该 URI 重新校验并显示预览；用户取消、确认导入、校验失败或页面正常结束时清理 URI 状态并释放已持久化授权。若 provider 不支持持久授权，则保留当前临时授权路径，不伪称已持久化。
- 改动：`adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaScriptLibraryActivity.java`；`scripts/tests/fx-dia-script-library-regression.sh`。
- 提交：`03d8664929bb84af9d7429359db1bc363c189bc7`（URI 状态恢复与权限管理）；`935ccf74dbc5480cc59a222235d622f2295a2122`（兼容不可用的持久授权）；`d968ce74b7f28234e3e108733c8ed7e00dd31caf`（回归断言）。
- 已从 GitHub 重新读取源码和测试脚本，静态确认 URI Bundle 保存/恢复、选择器持久授权请求、恢复后重新生成预览、取消/确认清理及授权释放断言均存在。尚未执行 Shell/Python/JVM 回归脚本、Gradle、模拟器或真机测试。
- 当前 HEAD（本记录写入前）：`d968ce74b7f28234e3e108733c8ed7e00dd31caf`。
- 下一步：继续检查 Dia 原生页面的 SAF/编辑器返回链及覆盖确认对话框重建；固定 FX 1.0.0，不提前打包最终 APK / KernelSU ZIP。


## 2026-11-05 — Hook 自定义规则页面筛选交互补齐

- 本批开始时分支 HEAD：`b5064e83e649c3ed7b4306884708be1808628fdc`。
- 页面组：Hook 第五 Tab → 应用详情 → 自定义 Hook 规则页。
- 修改：新增“清除分组和搜索筛选”原生控件；同时清空分组与搜索条件，不删除规则或草稿；规则搜索现在包含 RETURN_LITERAL 常量值，搜索提示同步说明常量字段。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`、`scripts/tests/fx-custom-hook-passthrough-regression.sh`、`docs/FX_1.0.0_LIVE_CONTINUATION_STATE.md`。
- 验证：源码静态核对；回归脚本新增筛选重置控件、分组重置和常量搜索断言。Shell 回归、Android 单元测试、Gradle 构建、UI 自动化、安装和真机测试尚未运行。
- 不涉及 Root/权限/服务执行逻辑；固定 FX 1.0.0；未生成 APK 或 KernelSU ZIP。
- 失败路线：此前首次提交遇到分支前进冲突，已重新读取 HEAD 与全部目标文件并基于新 HEAD 重放；不重复使用旧 SHA。
- 下一批：① Hook 自定义规则编辑器多语法输入与验证回显；② Dia SAF/编辑器返回链；③ 六 Tab 页面返回链定向回归。
- 可并行工作线：游龙广告 Tasker 回执状态回读；安全护盾名单/扫描详情 UI 核对。共享文件修改顺序整合。


## 2026-11-05 — Hook 自定义规则编辑器实时签名校验反馈

- 本批开始时分支 HEAD：`72fd49ce44be6fd98a20c4d2fa76057ec07c26e8`。
- 页面组：Hook 第五 Tab → 应用详情 → 自定义 Hook 规则编辑器。
- 修改：签名输入时实时调用现有 `DeveloperHookRule.normalizeDescriptor`，对当前目标包执行与保存路径一致的语法/包范围校验；显示有效 JVM 描述符或具体的未通过校验状态。覆盖 Java、Frida `.overload()`、Smali/JVM 和旧式签名，不另造解析规则，不改变保存/执行语义。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`、`scripts/tests/fx-custom-hook-passthrough-regression.sh`、本状态文件。
- 验证：源码静态核对；targeted 回归脚本新增实时规范化、有效结果和无效反馈断言。Shell 回归、Android 单元测试、Gradle 构建、UI 自动化、安装及真机测试尚未运行。
- 失败路线：无；沿用现有解析器而非新增第二套 parser。
- 下一批：① 检查 Hook 编辑器保存/旋转/返回后草稿与预览一致；② Dia SAF URI 恢复后的导入确认/取消回归；③ 六 Tab 页面返回链定向回归。


## 2026-11-05 — Hook 自定义规则编辑器实时校验回显

- 本批基于最新分支 HEAD：`d04c631e27e44fd0a18fcc15e384f576c6af67bd`。
- 页面：Hook → 应用详情 → 自定义 Hook → 新增/编辑规则对话框。
- 修改：编辑器新增实时校验状态。规则 ID、Java/Frida/Smali/旧式签名、动作、优先级或 RETURN_LITERAL 常量变化时即时调用现有 DeveloperHookRule.parse；显示未通过提示、目标不可用提示，或解析后的 JVM 描述符与动作；非 debuggable 应用即使签名解析成功，也明确显示仅允许 OBSERVE。该反馈不替代保存时的最终校验，不放宽运行时限制。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`、`scripts/tests/fx-custom-hook-passthrough-regression.sh`、`docs/FX_1.0.0_LIVE_CONTINUATION_STATE.md`。
- 验证：源码锚点唯一性检查；回归脚本新增实时校验回调、成功回显和编辑变更触发断言。尚未执行 Shell、JUnit、Gradle、模拟器或真机测试。
- 固定 FX 1.0.0；不改变 Hook 动作白名单、Root 权限、目标包范围或运行时门禁；不生成最终 APK / KernelSU ZIP。
- 下一步：Dia 原生脚本编辑器返回/覆盖链；游龙安全护盾名单和扫描详情；随后执行对应 targeted 回归脚本并修复失败项。


## 2026-11-05 — Hook 应用列表分页回归契约更新

- 失败 Actions：`41911585851`（HEAD `72fd49ce44be6fd98a20c4d2fa76057ec07c26e8`），失败步骤 `fx-hook-native-ui-regression.sh`，报错旧断言要求 `appendAppRows(0, Math.min(MAX_APP_ROWS_PER_PAGE, filtered.size()))`。
- 根因：当前实现为保留用户展开数量/Activity 恢复状态，先将 `hookAppListVisibleCount` 限制在 40–10000，再用 `initialEnd = min(requestedCount, filtered.size())` 渲染首屏；后续“加载更多”每次追加最多 40 行。旧测试只匹配早期固定首屏表达式，未覆盖现有恢复分页行为，属于过期断言，不是取消分页。
- 修复：回归脚本改为验证恢复后的可见数量边界、首屏 `appendAppRows(0, initialEnd)`、以及加载更多每次最多 40 行；保留原有分页、后台索引和图标异步检查。
- 改动路径：`scripts/tests/fx-hook-native-ui-regression.sh`、本状态文件。
- 验证：已对照当前 MainActivity 源码确认四个新断言表达式真实存在；尚未重跑 Actions，等待本提交触发的定向 Host 回归。不得把源码对照记为测试通过。
- 失败路线：不再使用固定首屏表达式的旧 grep 断言；若修复后再次失败，读取新的失败步骤/源码证据，不重复放宽断言。


## 2026-11-05 — Hook 原生 UI 回归脚本变量初始化修复

- 失败 Actions：`41911812059`（HEAD `1aab5145f518e66c5f83015b1ac31f2a8019f62c`），`fx-hook-native-ui-regression.sh` 已通过更新后的分页断言，随后在第 70 行失败：`main_activity: unbound variable`。
- 根因：脚本在第 70 行开始使用 `$main_activity`，却直到第 346 行才赋值；`set -u` 会在首次引用时直接终止。属于回归脚本自身的变量初始化顺序错误，与应用源码无关。
- 修复：将 MainActivity 源码路径变量初始化移到脚本顶部 `ROOT` 计算之后，后续所有断言复用同一路径；保留分页恢复断言修复。
- 改动路径：`scripts/tests/fx-hook-native-ui-regression.sh`、本状态文件。
- 验证：源码静态确认变量赋值现在早于首次引用；尚未重跑 Actions。下一次定向运行将继续执行该脚本余下断言，不能预先记为通过。
- 失败路线：不要在脚本中再次把变量定义留在首次使用之后；不需要修改 MainActivity 来绕过此错误。


## 2026-11-05 — 修复 Hook 原生 UI 回归脚本变量未绑定

- 失败 Actions：`41911812059`，HEAD `1aab5145f518e66c5f83015b1ac31f2a8019f62c`；失败步骤 `fx-hook-native-ui-regression.sh`，报错 `line 70: main_activity: unbound variable`。
- 复核：脚本顶部已有路径变量定义，但执行在授权 Hub 断言处仍触发 nounset。为避免测试包装/可选 APK 检查路径影响该段变量可用性，在 Hub 断言块前显式重新绑定到仓库内 MainActivity 路径；不修改产品源码，不放宽任何断言。
- 改动：`scripts/tests/fx-hook-native-ui-regression.sh`、本状态文件。
- 验证：已从 Actions 日志确认失败发生于 Hub 授权状态断言前，非应用代码断言失败；修复后由本提交触发 targeted Host 回归，结果待读取。
- 失败路线：不重复假设脚本顶部变量必然有效；改为在使用点重新绑定。
- 下一步：读取新 Actions run；若通过，继续 Dia 编辑器/导入对话框重建与覆盖确认闭环；若失败，按新的第一条错误定位，不运行整套 Actions。


## 2026-11-05 — Hook 原生 UI 回归修正 OBSERVE 默认值契约

- 基于分支最新 HEAD：`abaa722f31798bf683b3d8ae87639675a2f70405`。
- 失败 Actions：`41911919358`（HEAD `a28930fcc20af37e733af71e8737f0e5e2e372a9`），分页与脚本变量初始化断言已通过，随后因测试仍查找 `action.setText("OBSERVE")` 而失败。
- 根因：自定义 Hook 编辑器使用 Spinner，OBSERVE 是 actionOptions 第一项；旧断言仍按早期 EditText 版本查找 setText，和当前原生控件类型不一致。
- 修复：新建规则时显式调用 `action.setSelection(0)`，使 OBSERVE 默认行为在 UI 代码中明确；编辑已有规则与恢复草稿仍在后续代码按持久化动作/草稿覆盖该默认值。回归脚本改为验证显式首项选择及 OBSERVE 位于动作选项首位，不放宽行为门禁。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`、`scripts/tests/fx-hook-native-ui-regression.sh`、本状态文件。
- 验证：源码锚点唯一性静态检查；本地未执行 Android Gradle/JUnit/真机测试，等待 push 后 Actions 定向回归。
- 失败路线：不再使用旧 EditText 的 `setText("OBSERVE")` 断言；若后续失败，依据新日志定位实际断言，不通过删除安全限制绕过。
- 下一步：修复后继续执行 Hook/Dia targeted 回归；然后集中处理游龙安全护盾白名单/扫描详情交互。


## 2026-11-05 — Hook 隐私分类导航回归断言跟进

- Actions：`41912130500` 失败于 `fx-hook-native-ui-regression.sh`，首个失败：`per-app editor rebuilds do not restore the active privacy section`。
- 根因：当前 MainActivity 已将分类定位请求从长期导航上下文 `activePrivacySection` 拆分为一次性 `pendingPrivacySection`；`focusPendingPrivacySection()` 只消费 pending 值并执行滚动定位，长期来源分类仍由 `activePrivacySection` 单独保存。测试继续要求旧局部变量名，误把导航状态拆分判为丢失。
- 修复：将断言改为检查 `pendingPrivacySection` 被捕获、清空并用于 section tag 定位；保留其它关于 activePrivacySection Bundle 保存和返回链的独立断言。仅修正测试，不改导航实现。
- 改动路径：`scripts/tests/fx-hook-native-ui-regression.sh`、本状态文件。
- 下一步：本提交后继续读取 targeted Host Actions 第一条失败；如果出现实际导航错误再修 MainActivity，不通过删除断言绕过。


## 2026-11-05 — Hook 原生 UI Host 回归区分源码与 APK 验收

- Actions：`41912283951`（HEAD `c7667e0072b204a6fb54af84d80f135ca4d168a3`）已越过导航源码断言，随后失败于 `built Hook APK missing`。
- 根因：`fx-hook-native-ui-regression.sh` 同时包含源码 Host 断言和实际 APK/DEX/aapt 检查；当前 `FX Targeted Host Regression` 工作流只执行 Host 脚本，不构建 debug APK，因此把缺少 APK 当成源码回归失败。
- 修复：将 APK/DEX/aapt 检查改为条件段：提供 debug APK 时仍完整执行全部真实制品检查；Host-only 作业没有 APK 时明确打印 SKIP，不把未执行冒充通过。源码/导航/权限/运行时门禁断言仍无条件执行。
- 改动路径：`scripts/tests/fx-hook-native-ui-regression.sh`、本状态文件。
- 下一步：本提交触发的 targeted Host Actions 应执行全部源码断言并跳过仅限 APK 的检查；之后单独安排一次真实 Gradle debug APK 构建来执行制品验收，不生成最终交付包。


## 2026-11-05 — Hook 分组名称长度回归断言覆盖新增编辑器字段

- Actions：`41912409974` 已通过 MainActivity 导航/权限等源码断言，并明确 SKIP 了 Host-only job 未构建的 APK 制品检查；随后失败于 `rule group add/rename inputs must enforce their 24-character name limit`。
- 根因：当前源码共有三个 24 字符限制输入：规则编辑器分组字段、分组新增、分组重命名；旧测试只要求恰好两个，未把新增规则编辑器字段纳入计数。
- 修复：断言调整为至少三个受限输入，并更新失败说明；保留新增/重命名与编辑器三处的长度约束，不更改产品代码。
- 改动：`scripts/tests/fx-hook-native-ui-regression.sh`、本状态文件。
- 下一步：读取本次 targeted Actions 的新首错；若 Hook UI Host 回归通过，再切换到 Dia/Shield 页面批次。APK/DEX 检查需另行提供 debug APK 后执行。


## 2026-11-05 — Hook LSPosed 作用域任务所有权断言跟进

- Actions：`41912530483` 已通过 APK 条件跳过及分组输入约束，随后在 Hook 原生 UI 脚本中因旧方法签名检查而以无显式 FAIL 文本的状态退出。
- 定位：对照当前 MainActivity，`finishHookTargetScopeOperation` 已从旧版 `(int request, Thread worker)` 改为只接收 generation，并由 `FutureTask<Void> hookTargetScopeFuture` 统一追踪、清理任务；测试仍匹配旧线程参数签名。
- 修复：回归脚本改为检查当前单参数完成方法及 FutureTask 所有权字段/赋值，保留 generation 超时、取消和过期回调断言。未删除任务保护。
- 改动：`scripts/tests/fx-hook-native-ui-regression.sh`、本状态文件。
- 下一步：重跑 targeted Host 回归；若仍退出，继续定位第一个不匹配的源断言。


## 2026-11-05 — Hook 原生 UI 回归脚本 Host-only 后半段失败定位

- 基于分支 HEAD：`889297fe626278ddc50adbedf1803f3722c2e8a0`。
- Actions：`41912530483` 已通过 APK 条件跳过并打印 Host-only SKIP，但脚本仍以 exit 1 结束，没有 FAIL 文本；故障位于后续未附错误消息的裸 grep / Python 检查之一。
- 修改：为隐私传感器分类、通知/剪贴板分类、VPN DNS 分类和 Settings 界面模式四项裸 grep 添加明确失败信息，并改用固定字符串匹配，避免静默退出和正则解释差异。
- 改动路径：`scripts/tests/fx-hook-native-ui-regression.sh`、本状态文件。
- 验证：目标源码块的对应字符串已静态核对存在；本次是诊断性回归改进，尚未执行成功的 Actions。
- 下一步：读取下一次 Actions 第一条明确错误；修复后继续检查剩余 Hook/Dia/Shield 页面。


## 2026-11-05 — 修正 Hook 作用域 FutureTask 字段断言修饰符

- Actions：`41912691652` 通过源码前段与 APK 检查分流（APK 明确 SKIP），随后无显式错误文本退出。
- 静态逐项对照定位：新加的 FutureTask 所有权断言少写了源码实际存在的 `volatile` 修饰符，导致 grep 不匹配；实际字段为 `private volatile java.util.concurrent.FutureTask<Void> hookTargetScopeFuture;`。
- 修复：测试断言按真实字段声明更新，不更改并发实现。
- 改动：`scripts/tests/fx-hook-native-ui-regression.sh`、本状态文件。
- 下一步：继续 targeted Host 回归，检查下一个失败断言；本轮多次失败均是过期/不精确测试契约，不能记录为源码功能通过。


## 2026-11-05 — 安全护盾风险详情页白名单写入上限保护

- 修改前分支 HEAD：`e35e9f223b84ee53dd5f52a3a1b51a4d09950cc4`。
- 页面组：游龙安全护盾 → 扫描风险详情 → 加入白名单。
- 发现真实缺陷：`FxYulongWarningActivity.trust()` 先验证现有白名单格式，但新增条目后使用手写 StringBuilder 保存，没有调用共享 `FxYulongWhitelistPolicy.serialize()`。当旧名单已达到 10,000 条或接近 1 MiB 时，单次添加可能越过安全上限，导致后续解析器拒绝整份名单，原有白名单条目因此无法被正常读取。
- 修复：风险详情页改用中央有界序列化器；若新增后超过条目数/字符数限制，显示明确原因并停止写入，旧配置不变。成功时只提交经过中央策略验证的规范字符串。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongWarningActivity.java`、`scripts/tests/fx-yulong-shield-native-regression.sh`、本状态文件。
- 提交：源码 `a1aafd5622deff31855a5df14b51027a0006854b`；定向回归断言 `1dc9343b2f2186a62f01272a9280d88ce3c065fb`；本状态文件由后续提交同步。
- 验证：源码与测试锚点更新；尚未运行 Shield 回归脚本、Android 单测、Gradle、模拟器或真机。
- 失败路线：不采用手写 CSV 拼接；以后白名单写入统一使用 `FxYulongWhitelistPolicy.serialize()`，不允许调用方绕过条目/长度上限。此前 create_blob/create_tree 接口连续出现 GitHub GraphQL 错误，改用 Contents API 逐文件提交；未强推或回滚分支。
- 未完成：风险详情页尚未展示病毒库来源/版本/命中规则 ID（Finding 当前模型字段需先核实原始数据库结构）；扫描和批量清理的 Android 系统确认仍未真机验收。
- 下一批：① 检查 `FxYulongScanEngine.Finding` 到风险详情页的字段映射并补齐可信命中证据展示；② 完成 Shield 名单编辑页搜索/筛选状态的定向交互回归；③ 定位 Hook 原生 UI Host 回归中的 `built Hook APK missing` 调用链，不重复修改产品断言。


## 2026-11-05 — Dia 通知页路由回归修正（保持原生功能不变）

- 修改前 HEAD：`d911b6dd898e4f109a25731e82ac658ab24c65ba`。
- Actions：`41912872925` 已运行到游龙安全护盾定向回归脚本，失败于脚本第 156 行：`Dia feature has lost its matching native settings panel: notifyPanel`。
- 根因：回归脚本错误地要求 Dia 通知页也调用全局 `notifyPanel`。当前真实设计中，Dia 的“通知监听与权限提示”有独立 per-app 通知策略，正确路由是 `showAppList("通知保护")`；`notifyPanel` 是通用 FX 隐私页的共享设置分类，不是 Dia 通知页的目标页面。传感器和网络页面则分别走 `sensorPanel`、`netPanel`。
- 修复：把过时的三项统一面板断言改为逐项验证真实路由：通知→按应用通知策略；传感器→sensorPanel；网络→netPanel。没有删除功能，也没有更改 MainActivity 的产品行为。
- 改动路径：`scripts/tests/fx-yulong-shield-native-regression.sh`、本状态文件。
- 验证：已从当前 MainActivity 确认三条路由均存在；更新后的 Actions 尚未完成。不得将源码对照视为回归通过。
- 下一步：读取新 Actions 首个失败；若通过，继续 Shield 风险详情证据字段与名单搜索/筛选状态恢复。Hook Host 回归仍需独立追踪，不能把 APK-only 检查的 SKIP 记为 APK 验收。
- 固定 FX 1.0.0；不生成最终 APK 或 KernelSU ZIP。


## 2026-11-05 — Shield 原生回归修正最近提醒文案断言

- Actions：`41913036376` 通过此前 Dia 通知路由检查，随后失败于 Shield Hub 文案断言 `Shield status must retain a Java newline escape`。
- 核对：当前 `FxYulongShieldActivity` 的累计提醒首行是 `"累计提醒：" + warningCount`，其后时间戳才以 `"\n最近提醒："` 开始新行；并不存在 `"\n累计提醒："`。因此原断言要求了并不存在的前导换行。
- 修正：保留累计提醒标签断言，改为核验最近提醒时间戳确实使用 Java 换行转义；未修改产品文案或布局。
- 改动：`scripts/tests/fx-yulong-shield-native-regression.sh`，提交 `e7feee9401b1cedebcaef5fb5f070ed1d69b10a9`。
- 验证：已对照 Shield Hub 当前源码逐行确认字符串布局；等待本次 Actions 结果。未执行 Gradle/Android 单测/真机。
- 失败路线：不要求累计提醒首行添加空白换行；后续如调整文案，断言应检查实际信息层级而非旧字符串字面形态。


## 2026-11-05 — Shield 病毒库缓存错误持久化断言修正

- Actions：`41913137273` 通过 Shield Hub 提醒换行检查后，失败于病毒库缓存安全契约断言，要求 `editor.putString(K_LAST_ERROR, lastError)`。
- 核对：`FxYulongVirusDb.save()` 使用链式初始化：`SharedPreferences.Editor editor = sp.edit().putString(...).putString(K_LAST_ERROR, lastError);`。实际逻辑存在，旧断言错误要求在赋值后再次调用 editor.putString。
- 修正：回归断言改为匹配真实链式调用的 `.putString(K_LAST_ERROR, lastError);`；没有改变病毒库缓存实现或安全语义。
- 改动：`scripts/tests/fx-yulong-shield-native-regression.sh`，提交 `7c4d135316f7383337d0cb6c68723890e2c009e8`。
- 验证：已读取 `FxYulongVirusDb.save()` 真实代码行并对照测试表达式；等待下一次定向 Actions。未执行 Android 单测、Gradle、模拟器或真机。
- 失败路线：不再匹配 `editor.putString(K_LAST_ERROR, lastError)` 独立调用；实现使用 Editor 链式构造。


## 2026-11-05 — 安全护盾风险详情页防止白名单偏好类型损坏导致崩溃

- 基于当前分支新增批次，风险详情页此前直接调用 `SharedPreferences.getString("whitelist_pkgs", "")`。若偏好项被外部写成非 String 类型，Android 会抛出 RuntimeException/ClassCastException，导致风险详情页崩溃。
- 修复：读取白名单时增加 RuntimeException 保护；读取失败显示“无法按文本读取”，立即返回且不修改任何白名单数据。后续格式检查、中央有界序列化和 commit 仍使用同一套安全流程。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongWarningActivity.java`、`scripts/tests/fx-yulong-shield-native-regression.sh`、本状态文件。
- 提交：源码 `6d041e7790027c61a6087473e0163abd3b607b7d`；回归断言 `2da33f19f9f33abab5cdf729a5d7486bf04149cb`。
- 验证：源码与测试断言已提交；尚未执行 Shield 定向脚本、Android 单测、Gradle、模拟器或真机。
- 不改变扫描白名单语义，不静默清空损坏数据，不执行卸载/强停。
- 下一步：继续读取 Shield targeted Actions 的最新首错并完成名单/扫描 UI 页面组；然后切换 Dia Frida 脚本库/编辑器或 Hook 页面组，避免长期停留在同一测试脚本。


## 2026-11-05 — Shield 病毒库 JSON 错误数组正则断言修复 Python 转义层

- Actions：`41913246366` 通过链式 `last_error` 持久化断言后，失败于病毒库解析器 JSON 对象数组拒绝正则。
- 根因：测试脚本由 Python 读取 Java 源码。普通 Python 字符串中的反斜杠被解释，导致测试 token 与 Java 源文件保留的双反斜杠字节文本不一致；实现中的 `lower.matches("(?s)^\\\\[\\\\s*\\\\{.*")` 已存在，并在解析入口拒绝对象数组。
- 修复：测试脚本两处正则源码断言改用 Python raw string，确保比较 Java 源码原样文本；保留拒绝对象数组的安全门禁。
- 改动：`scripts/tests/fx-yulong-shield-native-regression.sh`，提交 `65c953fbcef21bced0b39b30a48246a439a3ff50`；本状态文件待同步。
- 验证：已对比 GitHub 返回的 Java 源码行和测试脚本字面量；raw string 能保留源码中的双反斜杠。尚未有本修复对应的 Actions 结果。
- 失败路线：不修改解析器、不移除 JSON 错误对象拦截；不再用普通 Python 字符串表达含多层反斜杠的 Java 正则。
- 下一步：继续读取 Shield 定向回归第一条失败；通过后检查 Finding 的可信命中证据映射和名单筛选状态恢复。


## 2026-11-05 — Shield 扫描页滚动回调生命周期断言对齐

- Actions：`41913381189` 已越过病毒库缓存/解析器断言，失败于扫描页滚动回调断言。
- 根因：`FxYulongScanActivity` 的延迟滚动恢复实际同时检查 Activity 未 finishing、未 destroyed、当前 `scanScroll` 仍是同一容器且容器仍挂载；测试只匹配旧版以 `if (scanScroll == scroll...)` 开头的条件，未包含前置生命周期保护。
- 修复：测试改为匹配完整的生命周期 + 容器身份保护条件；保留防止旧页面回调移动新页面的约束。
- 改动路径：`scripts/tests/fx-yulong-shield-native-regression.sh`；测试提交 `a2bf288a40a15c0409eda2e2c2bc07fa7ca2019c`。本状态文件待同步。
- 验证：对照 `FxYulongScanActivity` 第 104–108 行确认恢复 Runnable 的实际条件；本次 Actions 尚待执行。
- 失败路线：不删生命周期保护，不弱化为仅检查容器引用；测试按当前更严格的实现契约精确匹配。
- 下一步：继续追踪 Shield 定向脚本下一条失败；后续切换实际页面功能，不无限停留在测试断言。


## 2026-11-05 — Shield 黑名单策略公开校验方法签名断言修正

- Actions：`41913466096` 已通过扫描页滚动回调、病毒库解析器和白名单读取相关断言，随后在黑名单策略检查第 443 行失败。
- 根因：测试要求 `isWellFormed(String raw)`，源码真实声明为 `public static boolean isWellFormed(String raw)`；方法及其全量输入校验实现均存在。
- 修复：测试精确匹配公开静态布尔方法签名，并添加明确失败原因；不修改黑名单校验实现。
- 改动：`scripts/tests/fx-yulong-shield-native-regression.sh`，提交 `62c70f64dc496cb7ea3309f5846219c76a283e4a`。
- 验证：已读取 `FxYulongBlacklistPolicy.java` 全文件，确认 1 MiB/10,000 条限制、包名校验、原子拒绝和不可变 parse 返回均存在；尚未得到本修复 Actions 结果。
- 下一步：继续定位 Shield 定向回归下一条失败；待脚本通过后转实际扫描详情与名单页面 UI 功能。


## 2026-11-05 — Shield 扫描风险证据贯通至详情页

- 基于分支 HEAD：`f3f94bf43ec8aa1035b549a92a0d0fc274f0c461`。
- 页面批次：游龙安全护盾 → 已安装应用扫描 → 风险结果卡片 → 风险警告详情。
- 核实发现：旧 Finding 只保存 severity/reason；病毒库真实列表可辨认包名、名称、关键字匹配来源，但扫描卡片和详情页没有展示来源或实际命中条目。旧格式没有稳定 rule ID/DB 版本字段，不应编造。
- 修改：病毒库新增 MatchEvidence，返回真实列表来源和实际匹配值；扫描 Finding 保留 sourceLabel/matchedEntry；确定/可疑包名、名称、关键字命中分别标明 safe1/safe2/mingcheng+mian 合并/key；APK 内容特征命中标明本地内容库及 family。扫描列表和风险详情展示证据；Activity 重建时同步保存/恢复来源和匹配值。
- 安全约束：不改变匹配优先级、白名单、风险等级、卸载确认或批量清理限制；不伪造规则 ID 或数据库版本。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongVirusDb.java`、`adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongScanEngine.java`、`adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongScanActivity.java`、`adhook/app/src/main/java/de/privacyguard/adhook/imported/shield/FxYulongWarningActivity.java`、`adhook/app/src/test/java/de/privacyguard/adhook/imported/shield/FxYulongVirusDbTest.java`、`scripts/tests/fx-yulong-shield-native-regression.sh`。
- 验证：新增 VirusDb JUnit 证据断言和 Shield targeted 静态回归断言；尚未运行 Gradle/JUnit、Actions、模拟器或真机。
- 下一步：执行 Shield 定向回归；核对名单编辑页搜索/筛选状态与分页恢复；处理 Hook Host regression 静默退出。


## 2026-11-05 — Shield 黑名单损坏状态累计断言修正

- Actions：`41913547735` 已越过黑名单策略方法签名、病毒库缓存/正则、扫描页滚动保护检查；随后在黑名单读取损坏状态断言处失败。
- 根因：测试要求旧的单表达式赋值 `blacklistDataCorrupt = !raw.isEmpty() && ...`；当前实现先在 SharedPreferences 类型读取失败时置 `blacklistDataCorrupt = true`，随后通过 `blacklistDataCorrupt || (...malformed...)` 累计损坏状态，避免后续正常化空字符串掩盖读取失败。
- 修复：回归改为同时验证读取失败标记和格式校验 OR 累计；保留“损坏时不修改原始名单”的安全门禁。
- 改动路径：`scripts/tests/fx-yulong-shield-native-regression.sh`，提交 `e7ad99e5b77f1ed36d0cdc1e366a56c604d09397`。
- 验证：对照 `BlacklistActivity.loadBlacklist()` 第 272–286 行；未执行真机，等待本轮 Actions。
- 下一步：继续定位 Shield 回归后续断言，避免将静态核对误报为完整通过。


## 2026-11-05 — Shield 风险证据回归脚本补齐源码读取变量

- 基于当前分支 HEAD：`4b1b5d181ba5bec4da103441c7aae329c405640a`。
- Actions：`41913734663` 已通过黑名单损坏状态累计断言，随后在新增风险证据断言处失败：`NameError: name 'virus_db' is not defined`。
- 根因：风险证据功能和断言已加入脚本末尾，但 Python 测试前置变量块仍只读取 blacklist_activity / blacklist_policy / protection_service，没有读取 virus_db、scan_activity、warning_activity 与 VirusDb JUnit 测试文件。属于测试脚本初始化缺项，不是产品源码运行失败。
- 修复：在同一前置变量块中从 Shield 源码字典绑定病毒库、扫描页、风险详情页源码，并从 repo_root 读取 `FxYulongVirusDbTest.java`；末尾证据断言继续保持，不删除测试。
- 改动路径：`scripts/tests/fx-yulong-shield-native-regression.sh`、本状态文件。
- 验证：确认所需四个文件在当前 HEAD 均存在且名称与读取路径一致；等待本次 Actions 执行。尚未运行 Gradle/JUnit/真机。
- 下一步：读取新 Actions 第一条失败；通过后切到白名单/黑名单列表页真实搜索、分页和返回状态检查，不继续无限修测试断言。


## 2026-11-05 — Shield 风险详情证据回归变量绑定补齐

- Actions：`41913734663` 已越过黑名单策略及名单损坏保护断言，随后因新增证据回归段引用未定义的 Python 名称 `virus_db` 以 NameError 退出。
- 根因：此前新增了真实命中来源/匹配条目检查，但未把已有源码读取变量映射到新检查段；属于测试脚本装配错误，不是产品运行错误。
- 修复：将 `virus_db` 绑定到已读取的 `db`，`scan_activity` 绑定到 `scan_page`，并显式读取 `FxYulongWarningActivity.java` 与 `FxYulongVirusDbTest.java`。
- 改动：`scripts/tests/fx-yulong-shield-native-regression.sh`，提交 `42a0b1e8bda8bf761c002ad3b3876a7f0e21781a`。
- 验证：已确认测试引用的源文件均存在；实际证据字段已在 `FxYulongVirusDb.MatchEvidence`、扫描状态保存/恢复、风险详情 UI 与单测中实现。等待本轮 Actions。
- 下一步：执行完证据字段回归后，继续修复下一条真实首错；不把测试脚本成功等同于 Android UI/真机验收。


## 2026-11-05 — Shield 六 Tab 返回导航断言对齐

- Actions `41913864161` 中 Shield 原生主回归已输出 PASS，随后六 Tab 回归失败于 Rescue Center 返回导航的旧注释断言。
- 当前 `FxYulongRescueActivity.returnToShieldHub()` 在 Hub 启动场景调用 `finish()` 返回既有调用者；源码注释为 `Hub-launched rescue screens simply finish to the existing caller.`。通知启动场景仍使用 `FLAG_ACTIVITY_CLEAR_TOP | FLAG_ACTIVITY_SINGLE_TOP` 返回 Shield Hub。
- 仅更新测试注释断言，未更改产品导航行为；改动文件 `scripts/tests/fx-yulong-shield-six-tab-regression.sh`，提交 `5dad0d655baca72478430e0cffd681c1e9451d5f`。
- 已对照 RescueActivity 第 141–148 行及 OverlayService 两个启动入口；新 Actions 尚待执行。
- 下一步读取六 Tab 与 Shield worker-bound 回归的首个失败。Shield 主回归在 `41913864161` 中实际 PASS；六 Tab 尚未通过。


## 2026-11-05 — Shield 三项定向 Host 回归通过

- Actions：`41913976722`，HEAD `5dad0d655baca72478430e0cffd681c1e9451d5f`，结论 SUCCESS。
- 实际通过：
  - `fx-yulong-shield-native-regression.sh`：主 UI/数据库/扫描/安全删除/白名单边界/扫描证据字段断言。
  - `fx-yulong-shield-six-tab-regression.sh`：Shield 原生页面六 Tab 壳、返回导航与页面注册。
  - `fx-yulong-shield-worker-bounds-regression.sh`：病毒库和完整性工作线程有界、过载拒绝及 Activity 生命周期回调保护。
- 这属于 GitHub Host 静态/脚本回归通过；不代表 Android Gradle 编译、JUnit、设备安装或真机操作已验收。
- 下一步：检查 WhitelistActivity / WhitelistPickerActivity / BlacklistActivity 的搜索、筛选、分页、选择状态与返回恢复；之后回到 Hook Host 回归，确认剩余静默失败是否已随最新断言修正。


## 2026-11-05 — Hook 自定义规则筛选与签名预览回归覆盖

- 本批基于分支 HEAD：`2f7d3ff50447a13fa117f88412ce583da916598a`。
- 将本轮已提交的两个 Hook UI 改动纳入 `fx-hook-native-ui-regression.sh`：筛选重置、分组/搜索清空、RETURN_LITERAL 常量值搜索、搜索提示、复用共享 parser 的实时签名校验、有效 JVM 描述符预览及无效签名反馈。
- 改动路径：`scripts/tests/fx-hook-native-ui-regression.sh`、本状态文件。
- 验证：已从同一分支 MainActivity 逐条核对 8 个断言目标全部存在；此提交用于触发 targeted Hook Host 回归，尚未把静态对照记为通过。
- 下一步：读取 Actions 首个失败并按真实源码修正；通过后转到 Dia 页面导航/返回链，之后完成 Shield 列表页搜索/筛选状态回归。


## 2026-11-05 — Shield 白名单大列表分页

- WhitelistActivity 原先会把全部匹配条目一次性创建为 View；白名单策略允许最多 10,000 项，可能导致 UI 卡顿。
- 已改为每批 50 行并提供加载更多；搜索回到第一页；保存/恢复页码、查询和滚动位置；名单缩减时页码夹到有效范围。
- 恢复状态时先 setText(query)，再恢复页码，避免 TextWatcher 将保存页码重置为 1。
- 改动：WhitelistActivity.java；fx-yulong-shield-native-regression.sh。
- 提交：59eb23e68297f42d0c947b5749676e95f0d00ffe；fa6f412a37b78309bda48108021e3ea70daf67ec；2f7d3ff50447a13fa117f88412ce583da916598a。
- 验证：Shield Host 定向回归 run 41914246428 SUCCESS；未执行 Android UI 自动化或真机旋转/滚动验收。
- 未完成：白名单排序/过滤仍在 UI 线程；黑名单已加入列表缺少搜索。下一步为黑名单列表搜索与分页状态恢复，再继续 Hook/Dia 页面组。固定 FX 1.0.0，不打最终包。


## 2026-11-05 — Shield 管控名单搜索与分页
- BlacklistActivity 已加入当前管控名单名称/包名搜索、50 行渐进显示、加载更多、无匹配空状态，以及查询/页码/滚动位置保存恢复。
- 搜索变化重置第一页；恢复时先 setText(query) 再恢复页码，避免 TextWatcher 覆盖已保存页码。原有管控存储和服务语义不变。
- 产品代码提交：74531c472c25dd2ea9c8c5f4601a26538e886202。测试断言待补；该提交的 Actions 被后续并发提交取消，未记为通过。
- 未验证：Android UI 自动化、Gradle、模拟器和真机。下一步补定向断言并检查 Actions，然后继续 Dia UTF-8 导入与 Hook UI 页面批次。

- 管控名单回归断言补齐提交：0e473322396d1908e67fdb777f1aa6d8f154d4cf；检查搜索字段、标签/包名匹配、50 项分页、查询/页码/滚动恢复和 watcher 恢复顺序。等待该提交 Actions 结果。


## 2026-11-05 — Dia/Hook 自定义规则字面量回归脚本语法修复

- 失败 Actions：`41914328874`（HEAD `2a95b195f1189b8c4de4a2b7608f59508d6a1e94`），Hook 原生 UI 与 Dia 六 Tab 回归均通过；`fx-dia-custom-hook-literal-regression.sh` 的 Python heredoc 在多行 assert 处因双反斜杠续行报 SyntaxError。
- 修复：将 `commitCustomRuleGroupUpdate` 持久化/回滚断言改为括号包裹的多行布尔表达式；保留原断言语义。
- 改动路径：`scripts/tests/fx-dia-custom-hook-literal-regression.sh`、本状态文件。
- 验证：脚本语法修复已提交 `802b279a892f49548ece036f782d8404f127df4e`；等待对应 Actions 结果。
- 失败路线：不依赖易错的反斜杠续行；用括号明确表达多行条件。


## 2026-11-05 — Dia 自定义 Hook 分组移动回归定位修正

- 失败 Actions：`41914691387`（HEAD `802b279a892f49548ece036f782d8404f127df4e`），Python 语法修复后，literal regression 失败于“moving a rule between groups must use the checked atomic persistence path”。
- 根因：测试只提取 `showCustomRuleGroupPicker(int slot)` 的单参数委托方法；实际移动操作位于重载 `showCustomRuleGroupPicker(int slot, int restoreChoice)` 中，委托方法只有一行转发，自然不含提交调用。
- 修复：测试改为提取包含真实单选、取消、新建分组与“移动”回调的双参数重载；保留 `commitCustomRuleGroupUpdate(...)` 原子持久化断言。
- 改动路径：`scripts/tests/fx-dia-custom-hook-literal-regression.sh`。
- 验证：已核对 MainActivity 的移动回调先构造 assignments，再检查 `commitCustomRuleGroupUpdate(...)` 返回值；测试只调整方法提取范围。下一轮 Actions 结果待读取。
- 失败路线：不把原子提交调用移回仅作委托的单参数方法；按实际重载实现检查。


## 2026-11-05 — Dia ActivityKey 手势冲突回归断言对齐

- Actions：`41914822688` 中 Hook 原生 UI、Dia 六 Tab、Dia 自定义 Hook 分组操作回归均通过；随后 `fx-dia-dialog-native-regression.sh` 在 ActivityKey 手势冲突断言失败。
- 根因：MainActivity 实际通过全限定类名调用 `FxDiaKeyGesturePolicy.hasOverlappingTriggers(finishTrigger, dialogTrigger)`；测试却要求无限定的 `hasOverlappingTriggers(...)` 子串。业务实现存在，断言漏掉限定调用形式。
- 修复：回归断言改为匹配实际的 `.hasOverlappingTriggers(finishTrigger, dialogTrigger)`，并明确验证 ActivityKey 页仍使用共享策略拒绝重叠手势；不更改产品逻辑、不删除门禁。
- 改动：`scripts/tests/fx-dia-dialog-native-regression.sh`。
- 验证：已对照 MainActivity 保存回调第 6184–6188 行；修复后 Actions 待执行。此前失败导致该脚本之后的 Wi-Fi、VPN、Dia SAF/Frida 脚本尚未在该 run 中执行。
- 下一步：读取新 Actions 首错；继续完成 Dia 原生页面组与 SAF 导入严格 UTF-8 校验；Host 回归不代表 Android Gradle/JUnit/真机验收。


## 2026-11-05 — Dia Dialog / ActivityKey 文案断言对齐

- 失败 Actions：`41914822688`（HEAD `d5f0a7673e233bb6fb11e573fdac0a6bc6d8e178`），Hook 原生 UI、Dia 六 Tab、Hook literal/group drafts 均通过；随后 `fx-dia-dialog-native-regression.sh` 在 ActivityKey UI 文案断言失败。
- 根因：测试期待旧文案“需要先有有效的 debuggable Dialog 规则”，当前原生 UI 已更新为“需要先配置有效的 debuggable Dialog 规则。”，语义一致但字面不同。
- 修复：测试断言更新为当前 UI 文案，不改产品文案或安全条件。
- 改动路径：`scripts/tests/fx-dia-dialog-native-regression.sh`。
- 验证：已对照 `MainActivity.showDiaKeyControlTarget()` 确认该文案在无有效 Debug Dialog 规则时触发；等待下一次 Actions。


## 2026-11-05 — Dia 备份恢复回滚路径回归脚本 Python 转义修复

- Actions：`41915034668` 已通过 Hook 原生 UI、Dia 六 Tab、Hook 分组操作和 Dialog/Toast/ActivityKey 规则检查，随后执行 `fx-dia-backup-restore-preflight-regression.sh` 时在 Python heredoc 第 95 行发生 SyntaxError。
- 根因：Python 双引号字符串中使用了双反斜杠再接内嵌双引号，Python 将反斜杠对解析成字面反斜杠，导致字符串提前结束；不是 Java 事务回滚实现失败。
- 修复：对 PG 与 Stellar 目录替换保护断言使用 Python raw 单引号字符串，按 Java 源码中实际的反斜杠转义引号匹配：`if [ ! -d \\"$PG\\" ]` 与 `if [ ! -d \\"$DIR\\" ]`。保留两项防止回滚穿越被替换目录的安全断言。
- 改动：`scripts/tests/fx-dia-backup-restore-preflight-regression.sh`。
- 验证：已核对 Java 事务生成器第 519–520 行的实际 shell 检查及 Actions 报错位置；修复后 Actions 待执行。尚未做设备级恢复/回滚测试。
- 下一步：检查新 Actions 是否越过备份预检脚本；继续执行 Dia Frida SAF 严格 UTF-8 导入回归，并优先验证恢复中断/目录符号链接拒绝行为。不得把 Host 断言当作数据恢复真机验收。


## 2026-11-05 — Dia 备份回滚目录守卫断言转为显式反斜杠构造

- 基于最新 HEAD：`cb2ddcf4a477a6ac362cc2380b4fc96b6594e1f4`。
- Actions `41915194221`：上次 Python SyntaxError 已消除，脚本继续执行至 rollback 的 Stellar 目录守卫断言，因预期字符串反斜杠层级不匹配而失败。
- 根因：测试字面量仍然包含多层转义，匹配结果不等于 Java 拼接生成的 shell 片段；前次修复只消除了语法错误，没有保证字节级匹配。
- 修复：两条 PG / Stellar rollback 断言统一通过 `q = chr(92) + '"'` 构造 Java 源码的反斜杠双引号，避免手写反斜杠数量；保留对两条路径守卫的严格检查。
- 改动路径：`scripts/tests/fx-dia-backup-restore-preflight-regression.sh`、本状态文件。
- 验证：尚待 Actions；静态核对 Java 源码生成片段为 `[ ! -d \"$PG\" ] || [ -L \"$PG\" ]` 和 `[ ! -d \"$DIR\" ] || [ -L \"$DIR\" ]`。不宣称产品回滚已真机验证。
- 下一步：读取新 Actions 首错；通过后继续 Dia SAF/Frida 页面批次，不再把测试脚本修复作为产品功能完成。


## 2026-11-05 — Dia Frida 共享脚本库导入回归断言对齐
- 当前 FridaActivity 的导入路径先调用 previewImport，再通过用户确认的 confirmedOverwrites 调用三参数 mergeImport；测试原先匹配旧的二参数重载，错误报告为未走共享校验。
- 修正脚本断言匹配当前带确认覆盖名单的真实调用，不更改产品行为。
- 改动：scripts/tests/fx-dia-script-library-regression.sh；提交 5a773e952d952a7066fc83c462208b858a308829。
- 验证：等待本提交 Actions；不代表 Android Gradle/JUnit/真机已验证。


## 2026-11-05 — Dia 回滚 Stellar 路径断言匹配复合条件的实际结构

- 基于最新 HEAD：`271c5cd596762378c7c2cba4de41897115c91ea7`。
- Actions `41915290629` 仍使用上一提交的测试脚本，失败点为 Stellar 目录守卫断言；PG 守卫断言已经通过。
- 根因：产品 rollback 将 PG、TXN、Stellar DIR、STXN 四个目录检查合并在同一个 `if` 条件中。DIR 守卫前面是 `||`，不是第二个独立的 `if`。测试错误地要求 `if [ ! -d "$DIR" ]`，属于结构预期不准确。
- 修复：保留同一目录拒绝 symlink 的条件，只将 DIR 断言匹配片段修正为 `[ ! -d "$DIR" ] || [ -L "$DIR" ]`；PG 断言仍检查首个 `if`。
- 改动路径：`scripts/tests/fx-dia-backup-restore-preflight-regression.sh`、本状态文件。
- 验证：等待本提交 Actions；目前仅完成源码结构对照，不宣称测试通过。
- 下一步：读取本提交 Actions；通过后回到 Dia SAF/Frida 原生页面批次，避免继续把回归脚本修复当作产品功能交付。


## 2026-11-05 — Dia Frida / 备份恢复 Host targeted 回归通过

- Actions：`41915342024`，触发提交 `5a773e952d952a7066fc83c462208b858a308829`，Host regression job SUCCESS。
- 本次实际执行并通过：`fx-dia-backup-restore-preflight-regression.sh`（备份恢复事务、PG/Stellar 目录替换与符号链接守卫、部分旧备份缺失文件时不误删）；`fx-dia-script-library-regression.sh`（共享 Frida 脚本库校验/序列化、覆盖确认名单、严格 UTF-8 与名称/源码/数量限制）。日志明确输出 Frida store 与 limits 两条 PASS，整个 Host job 成功。
- Shield 主 UI、六 Tab、worker bounds 的 Host 回归此前在 `41913976722` 成功；Hook 原生 UI 的单独完整回归仍需从最新变更后再跑一次，不能把单个脚本前段 PASS 记作整套通过。
- 仍未完成 Android Gradle/JUnit、APK/DEX 实际制品、模拟器/真机、备份实际恢复及系统权限验收。Host-only APK 制品检查为 SKIP，不是 APK 通过。
- 下一批：① Hook/Dia 原生 UI 合并回归复跑；② Shield 白名单/黑名单分页和选择页状态恢复 targeted 回归；③ Dia SAF 文件选择与覆盖确认旋转/进程恢复的设备级验收。固定 FX 1.0.0，不生成最终 APK 或 KernelSU ZIP。


## 2026-11-05 — Dia Frida 两条 SAF 导入路径启用严格 UTF-8 解码

- 基于分支最新 HEAD：`f76fb0ba81356a7946c4158f4e1f16ee244d4fcc`。
- 页面组：Dia 23.11 → Frida 脚本库 JSON 文件导入、独立 JS 文件导入。
- 发现真实数据完整性问题：`FxDiaScriptLibraryPolicy.decodeUtf8()` 已使用 UTF-8 Decoder 的 REPORT 模式并有 Host 测试覆盖，但两个 SAF 读取入口仍用 `new String(bytes, UTF_8)` 的替换解码行为。遇到截断/非法 UTF-8 时，损坏字节会被替换为 U+FFFD，随后仍可能进入 JSON 预览或编辑器。
- 修复：JSON 脚本库导入和独立 JS 导入均改用共享 `FxDiaScriptLibraryPolicy.decodeUtf8()`。非法 UTF-8 会抛出明确导入错误，不再静默篡改文件内容；原有大小限制、后台读取、取消检查和不自动执行行为保持不变。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java`、`scripts/tests/fx-dia-frida-script-library-saf-regression.sh`、本状态文件。
- 验证：保留已有 Host 测试对有效多字节 UTF-8 和非法字节拒绝的覆盖；新增静态回归断言，要求两条 SAF 入口实际调用严格解码器。等待 Actions。
- 下一步：复跑 SAF/Frida 页面回归；核对文件选择取消、Activity 重建时 SAF URI/确认弹窗状态；随后推进 Frida Server/Gadget 页面生命周期与返回链。未做真机 SAF 文件提供器验收。


## 2026-11-05 — Dia SystemExpand 页面滚动状态恢复

- 基于分支 HEAD：`efef72b3f947a088c57cfe38dc796153e612f951`。
- 问题：SystemExpand 原生页有独立 ScrollView 与多项系统设置入口，但没有 `onSaveInstanceState`，旋转/Activity 重建会回到页面顶部。
- 修改：保存 `fx_dia_system_expand_scroll_y`；重建时在布局完成后恢复 scrollY，并检查 Activity 未销毁、ScrollView 仍是当前实例且仍挂在页面树上，避免旧回调移动新页面。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaSystemExpandActivity.java`、`scripts/tests/fx-dia-system-expand-navigation-regression.sh`、本状态文件。
- 验证：targeted 回归新增 7 个状态保存/恢复锚点；当前仅源码静态核对，尚未执行 Actions/Android 构建/设备旋转测试。
- 下一步：读取本提交 Actions；随后继续 Dia 原生页面的 Activity 浏览器/系统扩展返回链，并复跑 Hook 原生 UI回归。


## 2026-11-05 — Frida libXposed loader 回归断言对齐

- 基于分支最新 HEAD：`d8774c8c55d19a77b9c684464225270a73b0ad1d`。
- Actions `41915672051` 中 SAF 严格 UTF-8 新增断言及 Frida 脚本库页面回归均 PASS；二进制导入、Gadget 配置/部署/会话 mock 也已执行。随后 libXposed wiring 脚本因旧早退条件字符串不存在而失败。
- 根因：当前 `AdVisibilityHook.onPackageReady()` 已将早退条件扩展为 Dialog、Toast、ActivityKey、隐私和自定义 Hook 多个功能开关；旧测试硬编码早期 `if (!adsForPackage && !memberDiagForPackage)`，不再对应当前结构。
- 修复：测试改为验证 Gadget loader 调用早于读取可选 per-app remote config 的位置，继续保证 Gadget 独立于远程隐私配置加载；不修改产品运行逻辑。
- 改动路径：`scripts/tests/fx-dia-frida-libxposed-wiring-regression.py`、本状态文件。
- 验证：已对照当前源码 loader 调用位置早于 `UnifiedHookConfigParser.Target` 获取；等待 Actions 复跑 Frida 页面组。
- 下一步：读取当前 Actions 后续首错；继续 Frida Server/Gadget 会话页的目标进程、取消、停止、错误与 Activity 重建返回链。


## 2026-11-05 — SystemExpand 导航回归 XML 解析修复

- Actions `41915871403`（触发提交 `b6d487838aa51a0ba711f233a2109c4287880f5e`）在 `fx-dia-system-expand-navigation-regression.sh` 的 Manifest 检查处失败：`ET.parse()` 把已读取的 XML 内容字符串误当作文件路径，产生 `OSError: File name too long`。
- 修复：将 `ET.parse(manifest_path).getroot()` 改为 `ET.fromstring(manifest_path)`；上游 shell 已将 Manifest 读成文本，直接解析文本才符合数据类型。
- 改动路径：`scripts/tests/fx-dia-system-expand-navigation-regression.sh`。
- 验证：修复后将重新执行 SystemExpand 页面状态恢复与 Manifest private/exported 断言；本轮还未有新 Actions 结果。

 
## 2026-11-05 — Dia System Expand 安装来源选择器原生搜索与空状态

- 页面：Dia 23.11 → 系统扩展 → 未知来源安装授权。
- 原缺陷：安装来源通过无搜索的 `AlertDialog.setItems()` 展示；应用数量较多时只能滚动查找，也没有筛选无匹配状态。
- 实现：原生 EditText + ListView 搜索弹窗，ArrayAdapter Filter 按显示名称/包名匹配；空结果显示提示；选择结果仍只打开 Android 对应应用的 `ACTION_MANAGE_UNKNOWN_APP_SOURCES`，不代替系统授权；取消无副作用。
- 改动：`FxDiaSystemExpandActivity.java`、`fx-dia-system-expand-installer-regression.sh`、本状态文件。产品代码提交：`049d503cedb29a051380ed9e788160a0142dca40`；定向断言提交：`f0922170e5b6fb37f219e553b132eb9a71d1a0bd`。
- 验证：源码锚点与唯一替换检查；回归新增搜索、过滤、空状态、行点击路由、旧无搜索列表移除断言。Actions 待执行；尚未运行 Android Gradle、UI 自动化、模拟器或真机。
- 未完成：筛选查询在 Activity 重建后不恢复；System Expand 滚动恢复已由前一批补入，尚未做设备旋转验收。
- 失败路线：不再使用不可搜索的固定 `setItems(labels,...)`；不绕过 Android 逐应用授权页面。
- 下一批：补选择器查询状态恢复，并完成 System Expand / Wi-Fi Proxy 返回链交互检查；随后进入 Dia 原生文件/备份页面批次。固定 FX 1.0.0，不打最终包。


## 2026-11-05 — SystemExpand 安装器安全回归改为检查实际事务链

- 基于分支最新 HEAD：`6e1a57ac5d65faf6ce530b44c8781682142142de`。
- Actions `41916036762` 在 SystemExpand 导航脚本通过 XML 文本解析后，失败于过时的固定文案断言 `不会强制停止或重启系统安装器`。
- 源码核对：当前页面真实行为不是“永不重启”，而是先读取 PackageInstaller 全部会话，使用 `FxDiaInstallerRestartPolicy.isSafeToRestart()` 判断活动/已提交/staged 会话，再经二次确认并在执行前重读会话，最后才调用 Root force-stop。固定旧文案断言不符合现实现实。
- 修复：回归改为检查“会话预检说明”、`getAllSessions()`、共享安全策略、二次确认入口和 Root 命令链；保留对风险控制行为的强断言，不修改产品代码。
- 改动路径：`scripts/tests/fx-dia-system-expand-navigation-regression.sh`、本状态文件。
- 验证：已对照 `FxDiaSystemExpandActivity` 中会话初检、确认回调前复检和 Root 命令执行顺序；等待 Actions。
- 下一步：读取当前 Actions 后续首错；继续 Dia SystemExpand/Activity Browser 页面返回与状态恢复。设备安装、系统会话竞争场景未真机验收。


## 2026-11-05 — Dia Frida 脚本库导入冲突完整预览

- 产品 UI 提交：`ab73418e35fd62780ce2720d4bc014f2741dbfae`；回归提交：`76e42fd1dac0b35c5c500478aa24962af2969498`。
- 导入预览原先只展示最多 5 个同名脚本，其余仅显示“等”，但确认回调会授权本次预览发现的全部同名项。现在改为逐行展示全部冲突名称，再由用户确认；仍传入完整 `preview.overwrittenNames`，Store 在写入锁内重新校验并拒绝预览后新增的冲突。
- 回归增加完整名单展示及不截断检查。脚本库导入确认闭环此前由 Actions `41915795756` SUCCESS；完整冲突名单 UI 对应回归提交被后续提交取消，待后续合并回归。
- 同期确认 libXposed wiring regression 已改为稳定检查 Gadget loader 在读取 per-app remote config 前运行；未更改产品逻辑。
- 未验证：Android Gradle、真实 SAF DocumentsProvider、设备旋转/视觉效果和真机。
- 下一批：继续 Dia Frida installer source picker 搜索/选择状态与安装来源校验；再检查 Frida JS 编辑器保存返回和会话状态。Host 静态回归不等于真实 Frida 注入验收。


## 2026-11-05 — Dia 崩溃报告页旋转恢复与损坏记录保留

- 基于 FX 分支当前状态，补齐 `FxDiaCrashReportActivity` 的页面恢复。
- 修复一：保存/恢复崩溃报告 ScrollView 位置；恢复回调要求 Activity 仍有效且 ScrollView 仍是当前页面实例。
- 修复二：此前 `hadPendingReport` 为 true 但 `record == null` 时仍立即清除 pending flag，旋转/进程重建后会把损坏报告误显示为“没有崩溃记录”。现在仅在成功读取 record 时清除 pending flag，并把 `unreadablePendingReport` 写入/恢复 Bundle，损坏提示在重建后保留。
- 改动路径：`adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaCrashReportActivity.java`、`scripts/tests/fx-dia-crash-report-regression.sh`、本状态文件。
- 验证：回归新增 scrollY、pending unreadable marker、仅成功读取后清标记、旧 ScrollView 回调防护等断言；尚未运行新 Actions/Gradle/JUnit/模拟器/真机。
- 下一步：读取本提交 Actions；随后检查 Dia CrashReport 清理确认/分享返回链，以及 Frida SAF 导入旋转/进程恢复；固定 FX 1.0.0，不打最终包。


## 2026-11-05 — CrashReport 回归脚本 Manifest XML 文本解析修复

- Actions `41916353780` 在 `fx-dia-crash-report-regression.sh` 的 Manifest 检查处失败：`ET.parse(manifest_path)` 将已经由 `Path.read_text()` 读取的 XML 内容当作路径，触发 `OSError: File name too long`。
- 修复：改用 `ET.fromstring(manifest_path)` 解析内存中的 XML 文本；产品代码未变。
- 改动路径：`scripts/tests/fx-dia-crash-report-regression.sh`。
- 验证：等待新 Actions 继续执行 CrashReport 状态恢复、JNI/Breakpad host tests；不把 XML parser 修复本身记为产品验收。


## 2026-11-05 — Dia 文件浏览器搜索、嵌套导航与重建状态恢复

- 修改前 HEAD：`79684b9a55c5d834e640aaf8f77301a0663bc6ff`。
- 页面：Dia 23.11 → 文件与 SO 库浏览（SAF 授权目录）。
- UI 完成：增加当前目录名称/MIME 类型搜索；过滤结果继续使用 100 项分页与 5,000 项读取上限；匹配数/显示数实时反馈。
- 页面恢复：保存并恢复 SAF 授权树内的嵌套 document ID 路径、搜索查询、已展开分页深度和 ScrollView 位置；恢复前验证路径首项仍与当前 SAF tree root 相同、路径长度最多 64；用户改选目录或授权失效时清除旧分页/滚动状态，防止把旧目录状态套到新授权树。
- 主要改动：`FxDiaFileActivity.java`、`fx-dia-file-browser-io-regression.sh`。相关提交：`cef36e68d53b6e9970b7a9c087e7294b987f7aed`（搜索/恢复）、`4ab8ab4622b5f3e2a6d8ef530fb2ebc07b976de2`（先恢复分页再恢复滚动）、`875a0d4696ebc1528f9804f188c31276fc99f1cf`（更换/失效树时清除旧状态）、`1d803dae7603af668a933b0e328dd812ae8817c4`、`baaefe17eea592cf7121892ad5128c22234c3bc1`（回归覆盖）。
- 验证：静态源码检查确认搜索过滤、路径/query/分页/滚动保存恢复和有界 SAF path 校验均存在。Actions `41916426607` 正在执行；较早 run `41916386132` 在 Dia Crash Report 回归处失败，日志显示测试脚本把内存 XML 文本传给 `ElementTree.parse` 当文件路径；当前分支脚本已使用 `ElementTree.fromstring`，该失败不属于 FileActivity 产品代码，等待当前 run 确认。
- 未验证：Android Gradle/JUnit、SAF 提供器兼容、旋转/进程重建视觉、真实文件读写真机验收。
- 下一批：读取当前 Actions 结果；随后集中处理 Dia 文件浏览器的 SAF URI 读写取消/权限撤销交互，或转到备份页面导入/导出弹窗的恢复链。固定 FX 1.0.0，不打最终包。


## 2026-11-05 — CrashReport encrypt_stack 偏好所有者断言修正

- Actions `41916475490` 在 CrashReport Host 回归中失败：`crash store invariant missing: "encrypt_stack"`。
- 根因：`encrypt_stack` 是 Dia 崩溃报告展示格式偏好，由 `FxDiaCrashReportActivity` 从原版 `digXposed` SharedPreferences 读取/写入；`FxDiaCrashStore` 负责崩溃捕获与持久化，不拥有该展示开关。测试错误地要求 Store 也包含该键。
- 修复：从 Store 的 token 列表移除 `encrypt_stack`，保留 `digXposed` 旧偏好读取断言及 Activity 对 `encrypt_stack` 的实际读写断言。
- 改动路径：`scripts/tests/fx-dia-crash-report-regression.sh`。
- 验证：已对照 Activity 和 Store 的职责边界；下一次 Actions 将继续执行 CrashReport Host/JNI/导出格式测试。


## 2026-11-05 — Dia 备份/恢复表单旋转状态与凭据隔离

- 页面：Dia 23.11 → 数据备份与恢复。
- UI 问题：Activity 重建后 GitHub Owner/Repo/路径/分支、WebDAV 地址/用户名等非敏感配置会丢失，用户需要重新填写；远程表单较长，滚动位置也不保留。
- 实现：把远程端点非敏感字段提升为 Activity 字段，保存/恢复 GitHub Owner、Repo、文件路径、分支、WebDAV URL/用户名与页面滚动位置；继续沿用现有 pending encrypted export 临时文件状态。
- 凭据保护：备份密码、GitHub Token、WebDAV 密码不写入 Bundle/恢复状态；页面新增明确提示，重建后需重新输入。未把秘密写入 SharedPreferences 或其他持久化存储。
- 改动：`FxDiaBackupActivity.java`、`fx-dia-backup-restore-preflight-regression.sh`。提交：`ace0a2e06b80c74e9643d1026c43604b6c6c001f`、`00aa62e44f7d06fc50f219619ad1b38d3ea24172`。
- 验证：源码静态检查确认非敏感字段与滚动状态保存/恢复，且没有凭据 Bundle 写入；定向 Actions `41916691767` 已触发/排队，结果待确认。Android UI 自动化、旋转与进程重建真机测试未执行。
- 相关页面组：Dia 文件浏览器搜索/路径/分页/滚动恢复的 Host Actions `41916426607` SUCCESS；System Expand 安装来源搜索回归 `41916108180` SUCCESS。
- 下一批：读取备份页 Actions；检查 GitHub/WebDAV 表单字段在旋转后的恢复顺序与键盘遮挡；继续推进 Dia 文件/备份与 Frida 原生页面，不提前最终打包。


## 2026-11-05 — Dia Frida debuggable 目标应用搜索选择器

- 产品代码提交：`8f243413ed12e326b6aff1c68dccc29055fe2cf6`；目标标签显示修正：`93e86173d19af2e8860490d6907f387b69deacee`；定向回归提交：`96160ae18e522608bda95fb998ba3541de899b74`、`068e5a28f4e8e1fc295f272d1d70348394f1fa89`。
- Dia Frida 的 debuggable 用户应用选择器从不可搜索的 `setItems` 改为原生 EditText + ListView + ArrayAdapter，支持按应用名称/包名过滤、无匹配空状态；目标对象的显示同时保留包名，避免同名应用混淆。
- Activity 重建时保存并恢复搜索词；选定目标仍执行原有进程选择失效、旧请求 generation 递增、持久化和目标状态重置流程。仅允许 debuggable 非系统用户应用的既有筛选保持不变。
- 回归扩展：检查搜索过滤、空状态、包名身份、查询保存恢复、选择目标时旧进程请求失效。
- 验证等级：源码静态对照和定向 Host 回归脚本更新；对应最新 Actions 尚待结果。未运行 Android Gradle、设备 UI、旋转和真机 Frida 注入。
- 下一步：继续 Frida 进程多选器的搜索/排序/选择状态恢复（保留 PID/UID/进程名复核）；随后验证 JS 编辑器保存返回、会话连接/停止和日志页面。


## 2026-11-05 — Dia SystemExpand 安装来源选择器状态恢复

- 页面：Dia 23.11 → System Expand → 未知来源安装授权选择器。
- 实现：保存选择器显示状态和最多 256 字符搜索词；Activity 重建后重新枚举安装来源并恢复搜索词。仅在 Dialog 显示时保存；取消或选择后清理引用。原页面滚动恢复与 Android 逐应用授权路径不变。
- 产品提交：`c058c64a5918e3e25aebb56f4dbb482a692e851b`；回归提交：`17f9d94001c7a802e06164d8ac52bba408a430f1`。
- 验证：源码及定向断言已提交；Actions 尚待读取。Android Gradle/JUnit、旋转 UI 自动化和真机授权流程未验证。
- 下一步：检查本批 Actions；继续 Dia Activity Browser 搜索/详情/返回链及 Frida Server/Gadget 会话状态恢复。


## 2026-11-05 — Dia Frida 进程身份回归断言适配 package snapshot

- Actions `41916591419` 在 `fx-dia-frida-process-identity-regression.py` 失败，断言要求 `getApplicationInfo(targetPackage, 0)`。
- 根因：Frida 进程选择器先将目标包名快照为 `requestedPackage`，再读取 ApplicationInfo/UID；这是避免异步 UI 期间目标包名变化的正确做法。旧测试仍要求直接读取可变字段 `targetPackage`。
- 修复：初始身份检查改为断言 `getApplicationInfo(requestedPackage, 0)` 与 `targetUid = targetInfo.uid`，保留回调时再次校验 requestedPackage/UID 的断言。
- 改动路径：`scripts/tests/fx-dia-frida-process-identity-regression.py`。
- 验证：已对照当前 `chooseTargetProcesses()` 真实实现；Actions 重跑结果待读取。


## 2026-11-05 — Dia Activity Browser 搜索/分页后滚动位置恢复

- 基于实时分支连续提交：产品代码 `c83a92d2d0ce0c885dac66aa73cda43a7e85d4bb`；回归 `28c5d3a8ed7eec3fec603eccaf1e7da437e59182`。
- 页面组：Dia 23.11 → Activity 入口与禁用 / 隐藏应用。
- 已有实现保存目标包名、应用搜索、Activity 搜索和两个分页索引，但未保存整个页面 ScrollView 的垂直位置；Activity 重建后视口跳回顶部。
- 修复：增加 `fx_dia_browser_scroll_y`，保存/恢复 ScrollView 的 scrollY；恢复回调在布局后执行，并检查 Activity 未销毁、仍为当前 ScrollView 实例且仍挂在页面树中。
- 改动路径：`FxDiaActivityBrowserActivity.java`、`fx-dia-native-tab-regression.sh`、本状态文件。
- 验证：新增静态回归断言覆盖保存键、恢复读取、视图实例绑定、布局后滚动和父节点检查；尚未执行 Android 旋转/真机 UI 验收。
- 下一步：检查 Activity Browser 刷新目标/卸载时搜索与分页夹取；继续 Dia 文件/备份页面组。


## 2026-11-05 — Frida 目标进程身份回归按捕获包名变量对齐

- Actions `41916591419` 已通过 Gadget session mock 和 libXposed wiring，随后 `fx-dia-frida-process-identity-regression.py` 在进程选择器首轮身份读取断言失败。
- 根因：Activity 在启动进程枚举前把当前目标包名快照到 `requestedPackage`，随后用 `getApplicationInfo(requestedPackage, 0)` 读取 UID；测试仍要求旧的 `targetPackage` 字段引用。捕获快照是正确的并发隔离行为，后续回调也会重新读取并核对 UID/调试标记。
- 修复：回归断言改为匹配 `requestedPackage` 快照；保留 UID 绑定、`/proc/<pid>/status` 核验、目标重装后 UID 变化丢弃旧 PID、generation 取消保护等全部门禁。
- 改动：`scripts/tests/fx-dia-frida-process-identity-regression.py`，提交 `17268d7dc6a19494057e750f3ed636905b1acaad`。
- 尚待：新 Actions 结果；未执行设备上的真实 Root 进程枚举或注入。


## 2026-11-05 — Frida 进程扫描回归匹配实际异步 Root 执行路径

- Actions `41916867551`：libXposed wiring 与 Gadget session mock 已通过；进程身份回归继续失败于测试期待 `runRoot(command)`。
- 核对实现：`chooseTargetProcesses()` 先读取 `requestedPackage` 对应 ApplicationInfo/UID，再把 `RootAccess.execute(command, 15000L, 256 * 1024)` 放入 worker，结果回主线程后重新读取包信息并核验 UID、debuggable 和非系统标记。该异步路径是实际实现，不使用 `runRoot()`。
- 修复：回归顺序断言改为检查 `RootAccess.execute(command, 15000L)`，同时保留包身份读取必须先于 Root 进程扫描的约束。
- 改动：`scripts/tests/fx-dia-frida-process-identity-regression.py`，提交 `7ce67b44201095adc4b290cda20874990e78a10e`。
- 尚待新 Actions；未做真机 Root 进程枚举和 Frida 注入。


## 2026-11-05 — Dia Frida Gadget 配置/部署偏好写入顺序修复

- 页面：Dia 23.11 → Frida → Gadget 监听配置与目标部署。
- 发现问题：`saveGadgetListenConfig()` 和 `deployGadgetToTarget()` 在 Root 命令执行前就写 SharedPreferences；Root 写配置/部署失败时，重开页面仍显示未生效的新值，造成 UI 配置与真实系统文件/部署状态不一致。
- 修复：将 `gadget_path`、`gadget_port`、`gadget_on_load_wait` 与 `gadget_process` 的持久化移动到 Root 成功且确认输出标记之后；改为 `commit()` 并检查返回值。Root 失败不污染旧偏好；偏好写入失败时明确显示“系统文件/部署已成功，但本机 UI 索引保存失败”，不冒充完整成功。修正新状态提示的换行显示。
- 产品提交：`11108db8a2fa840f5dcccf31a027f955414f5118`；状态文案修正：`c372bf22b71a41a2f3de51d2d9aec11332ecdcc3`。
- 回归提交：`6d7cd760886d4b808e1fbebef295ea82bd6c0fc4`（检查 Root 与偏好写入顺序及 commit）；`d73cbed5da0e1332427e4acffcbcf2ae1614ed0c`（检查用户状态提示换行）。
- 验证：源码顺序已复核；定向回归脚本已增加契约断言。Actions 尚待读取；Android Gradle/JUnit、设备真实 Root 写入/部署未验证。
- 下一步：读取本批 Frida Gadget config/deploy/session Actions；继续 Frida 目标进程/会话 UI 的取消、停止和生命周期回显，不将 Root 文件写入成功等同于 LSPosed 已注入。


## 2026-11-05 — 游龙广告 DNS 查询日志原生分页

- 页面：游龙广告插件 → DNS 查询日志。
- 原问题：页面说明本地读取最近 500 条，但 UI 固定只渲染前 200 条，余下最多 300 条无法浏览；搜索仅在加载到的 500 条中筛选，列表没有渐进加载入口。
- 实现：50 条/页渐进显示；支持对当前加载的最近 500 条按域名/查询类型/拦截原因搜索；显示匹配总数和已显示数量；搜索变化回到第一页；加载更多后保留当前滚动位置；Activity 重建保存/恢复当前页、搜索词与滚动位置。后端日志仍保持原有本地读取范围与隐私策略，不新增上传或客户端 IP 展示。
- 改动：`FxYulongDnsActivity.java`、`fx-yulong-dns-cache-regression.sh`。提交：`2a0fc45d98423c6cb20f441c8a916b796e7ba9d4`、`6abe8006fe003789045d2de5162cdd309f4b5dcd`。
- 验证：源码静态检查确认分页、过滤、查询重置、页码恢复与计数 UI；定向 Actions 等待本轮结果。Android UI 自动化/真机滚动与旋转未验证。
- 下一批：读取 DNS 页面回归结果；随后检查游龙广告 Firewall/Whitelist/Stats 页的空状态、筛选与返回恢复，继续补齐三套应用原生页面覆盖。固定 FX 1.0.0，不打最终包。


## 2026-11-05 — Dia Frida server 启动路径偏好写入顺序修复

- 页面：Dia 23.11 → Frida → frida-server 启动/状态检查。
- 发现同类状态一致性缺陷：`startServer()` 在 Root 执行前就把新 `server_path` 写入 SharedPreferences；若 Root 授权失败、二进制不可执行、PID/目录守卫拒绝或启动失败，页面重开仍会显示这条未成功验证的路径。
- 修复：将 `server_path` 持久化移动到 Root 返回成功之后，使用 `commit()` 检查结果；Root 失败不改变旧路径。偏好索引写入失败时明确说明 Root 操作结果与本机索引状态，不冒充完整保存成功。显式“保存路径”按钮仍保留原有独立保存语义。
- 产品提交：`04c95d7f0af69338ea061c6987fee295a9c8d228`；回归提交：`4f507a2f48855ad607dbe2965a9e6f747a182931`。
- 验证：源码回读确认 Root 调用先于偏好提交；回归脚本新增顺序、同步提交和错误提示断言。Actions 尚待读取；Android Gradle/JUnit/Root 真机未验证。
- 下一步：读取 Frida server/Gadget targeted Actions；继续目标进程选择、server 状态回读、Gadget 会话取消/停止与页面重建的 UI 闭环。


## 2026-11-05 — Frida log regression path

- Updated the host regression to read `FxDiaSessionLogActivity.java` because the parent activity only routes to that page. The dedicated activity owns the file validation checks.
- Test commit: `7f58c5c302cde657cb2e7e2a8fc9677dc294dc20`. Awaiting Actions.


## 2026-11-05 — Frida target-loader 回归匹配可搜索 Adapter

- Actions `41917255787` 已通过 Gadget session mock、libXposed wiring、进程 UID 身份、server lifecycle 和 Frida page navigation；随后 target-loader 回归仍期待旧 `targets.get(which)` 列表选择。
- 现在目标选择器通过 `ArrayAdapter<Target>` 过滤，点击回调使用 `adapter.getItem(position)`，再以 `selected.packageName` 更新目标；该行为保留包名身份且支持搜索。
- 修复：回归断言匹配 Adapter 选择路径，未改变 PackageManager 后台枚举、generation 丢弃、目标状态保存或 worker 约束。
- 改动：`scripts/tests/fx-dia-frida-target-loader-regression.py`，提交 `705107a3b1fe32b77acde22c7e5bee88f43de75c`。新 Actions 待验证。


## 2026-11-05 — 游龙广告 DNS 查询日志异常记录显式诊断

- 页面：游龙广告插件 → DNS → 本地查询日志。
- 发现 UI 数据透明度问题：解析器遇到 JSON 行损坏或缺少域名字段时直接静默跳过；页面只显示有效解析条数，用户无法知道展示数据是否不完整。
- 修复：新增 malformed 计数；非法 JSON 与缺少域名的记录都会计数，并在页面状态中显示“无法解析/缺少域名 N 条”，提示检查本地日志格式。有效记录的拦截/放行计数和原始日志不被修改。
- 改动路径：`FxYulongDnsActivity.java`、`fx-yulong-ad-activity-state-regression.sh`、本状态文件。
- 提交：产品逻辑 `a7e1170318ebe63a901213d57f047be4ae602cd0`；格式修正 `b8eb881cd1828bbdcce9befb1553ad50e4da6081`；回归 `ef9a5aa898f2b73d1821cdf0c0f40b045b60fa11`。
- 验证：源码已复核计数路径与状态文案；回归脚本新增 malformed 计数断言。待 Actions；未做真实 AdGuard Home querylog 注入损坏行的设备验证。
- 下一步：检查游龙广告 Firewall/Whitelist 页面对应用卸载、包替换、UID 变化时的配置关联与状态刷新；然后继续安全护盾名单/扫描 UI 页面组。


## 2026-11-05 — Frida process picker search

- Added searchable multi-select UI and query/selection restoration.
- The pending PID set is retained across filters; Root UID/debuggable checks remain unchanged.
- Host regression and device validation are pending.


## 2026-11-05 — 本轮 UI 定向回归状态补记

- DNS 日志分页及搜索状态竞态回归：Actions `41917559211` SUCCESS；执行脚本 `fx-yulong-dns-cache-regression.sh`，DNS cache flush 的已有后端契约也一并通过。
- File Browser 搜索取消过期路径/分页/滚动恢复：源码修复和测试断言已提交；为确保测试精确覆盖 TextWatcher 代码块，新增 `cb19c4f30f4de94bd14384e1e484b58cd351cc59`，等待本次 Actions。
- Backup 表单非敏感字段/滚动恢复：产品与测试断言已提交，但之前对应 Actions 因 Frida 并行提交被取消；目前仅静态源码断言，不标记为 CI 通过。下一轮需单独触发其测试脚本。
- 仍未执行 Android Gradle 构建、模拟器 UI、真实 SAF/旋转/进程重建或真机网络验收。


## 2026-11-05 — Dia Frida 统一 Root 调用异常与空结果处理

- 页面组：Dia 23.11 → Frida server、Gadget、部署/移除、会话管理等共享 Root 操作。
- 发现问题：统一 `runRoot()` 直接调用 `RootAccess.execute()`，没有捕获运行时异常，也没有检查空结果；Root broker 异常会让后台任务结束而 UI 不收到状态回调，空结果则可能传入回调并被解引用。
- 修复：统一包装 Root 调用，捕获 RuntimeException 并向当前页面状态区显示异常类型/消息；若 broker 返回 null，显示明确失败状态并停止回调，避免任何调用方误判成功。Activity 已销毁时仍丢弃迟到 UI 更新。
- 产品提交：`775de347ec98c98c0b58428c1fa8627164ba5ff1`；回归提交：`50bbd21d9bb0e18e550ac8340df828bbd823ac40`。
- 验证：源码与回归脚本已提交；Actions 尚待读取。未运行 Android Gradle/JUnit/Root 真机故障注入。
- 下一步：检查最新 Frida server/Gadget Actions；继续页面级运行状态回读与会话停止后的 UI 同步。不能将 Root 命令发出或配置写入等同于目标进程已注入。


## 2026-11-05 — 本轮续接增量记录

- 本轮开始时按实时分支读取的 HEAD：`775de347ec98c98c0b58428c1fa8627164ba5ff1`；后续分支有并行提交，不能把该 SHA 当作当前最终 HEAD。
- Dia SAF JSON/JS 导入改为严格 UTF-8 解码：`efef72b3f947a088c57cfe38dc796153e612f951`；该提交 Actions 的 SAF 脚本库回归 PASS，后续在 libXposed 旧测试契约处失败，已记录对应测试对齐。
- Dia Activity Browser 新增 scrollY 状态恢复：产品 `c83a92d2d0ce0c885dac66aa73cda43a7e85d4bb`、回归 `28c5d3a8ed7eec3fec603eccaf1e7da437e59182`；对应 Actions 被并行提交取消，当前只记录源码/回归静态核对，不标记 CI PASS。
- 游龙广告 DNS 查询日志新增 malformed 计数与诊断文案：产品 `a7e1170318ebe63a901213d57f047be4ae602cd0`，格式修正 `b8eb881cd1828bbdcce9befb1553ad50e4da6081`，回归 `ef9a5aa898f2b73d1821cdf0c0f40b045b60fa11`；相关回归提交被并行 Actions 取消，未做真实 querylog 注入验收。
- 本轮确认的回归路线：不要再使用旧 EditText 的 OBSERVE setText 断言、旧 privacy 局部变量断言、旧 libXposed early-return 字符串、旧 SystemExpand 文案、把已读取 XML 文本交给 ET.parse()，或要求 Activity Browser 测试不存在的 scroll key；这些分别已按现有控件/路由/实现契约处理或记录。
- 下一批 UI：继续游龙广告 Firewall/Whitelist 包更新/UID 关联的真实回读；随后安全护盾名单/风险详情与 Dia 文件/备份页面。P0 检查优先，但不得用 UI 状态或静态测试替代 Root/真机验收。


## 2026-11-05 — Dia Frida 会话日志页面后台队列限流

- 页面：Dia 23.11 → Frida 会话日志查看/清空。
- 缺陷：日志 Activity 使用 `Executors.newSingleThreadExecutor()`，底层任务队列无界；用户连续刷新/清空时，过期 Root 读取请求仍可无限排队，requestGeneration 只能丢弃迟到 UI 回调，不能限制队列内存。
- 修复：改为单线程 `ThreadPoolExecutor` + `ArrayBlockingQueue<>(1)` + `AbortPolicy`；队列满时沿用页面现有拒绝处理，明确提示任务未执行；Activity 销毁时继续 `shutdownNow()`。
- 产品提交：`d74ff8eda54e68a12c0627f491583c0e630f0a05`；回归提交：`ef612178a46ffa25bde7d111ea1817cca5bad979`。
- 验证：源码及回归断言已提交；Actions 尚待读取。未运行 Android UI 压力测试或真机连续点击验证。
- 下一步：检查 Frida server/Gadget 回归链；继续检查 Dia 原生页面后台任务是否有无界执行器，并优先完成 UI 状态/返回链，而不是重复全仓扫描。


## 2026-11-05 — Frida Gadget log special-file guard retained

- Restored the Gadget log reader's explicit checks after reviewing the searchable process-picker change: missing file returns an empty-state message; existing targets must be regular readable files; symlinks, directories and special files are rejected before `tail`.
- Product commit: `30068f1e71aaf20951726a737e0a8e5d23207b9b`.
- Added regression coverage for the `FX_GADGET_LOG_TYPE_REJECTED` marker and regular/readable file guards. Test commit: `8fce550edb02a95681086062996d0cb364d1f9bf`.
- The searchable multi-select process picker retains the pending PID set across filters and restores query/selection after Activity recreation. Selecting a different target clears the previous process query and pending selection.
- Actions and device validation pending; do not claim real Root/FIFO/symlink device tests.

## 2026-11-05 — Continuation state history restored

- Reinstated the missing historical records for Gadget log special-file rejection and File Browser/DNS stale search-scroll restoration so the live state remains a complete continuation log after a concurrent state-file rewrite.
- File Browser/DNS changes remain committed in `b9eb001ecdc03fd299685866bb1fd080d3365e5c`, `836ff829d7891f0b948dd3c2d6281c64416e69af`, `b7c30f5fa66a79c878647c12ef286f353bd50b0f`, and `5bd0768644562c9747dedb6be8676551cbb156ad`.


## 2026-11-05 — File Browser / DNS 搜索取消过期恢复值（续接补记）

- 代码提交已在当前分支：File Browser `b9eb001ecdc03fd299685866bb1fd080d3365e5c`，回归 `836ff829d7891f0b948dd3c2d6281c64416e69af`；DNS `b7c30f5fa66a79c878647c12ef286f353bd50b0f`，回归 `5bd0768644562c9747dedb6be8676551cbb156ad`。
- File Browser 用户修改搜索词时清除旧的 pending page/scroll restore；Activity 重建时先回填 query，再恢复分页深度和 scrollY。
- DNS 日志用户修改搜索词时清除旧 scroll restore 标记并回到第一页。
- DNS 定向回归 Actions `41917559211` SUCCESS；File Browser 回归 run `41917657584` 多次因分支并行 push 被 concurrency 取消，源码和测试断言均已提交，尚未获得该修复对应的 CI 成功结果。
- 本状态条目用于恢复此前并行状态合并时未带入的续接记录；当前最新 HEAD 以分支实时 ref 为准：`1bb1c3557d99fcea95acef2903f8923f8b37a7d1`。


## 2026-11-05 — Frida Gadget 日志读取队列回归契约对齐

- Actions `41917868626` 在前序 Frida 二进制导入与 Gadget config/deploy 测试 PASS 后，失败于 session regression 要求 `showGadgetSessionLog()` 方法体内有一个独立 1 项 ThreadPoolExecutor。
- 当前实现实际使用 Activity 级单线程、容量 12、AbortPolicy 的共享 Root worker；`runRoot()` 统一经过 `submitWorker()`，所有 Root 操作串行执行，队列满时显示失败提示，Activity 销毁时 `shutdownNow()`。日志读取通过同一 `runRoot(command, 12000L)`，不会另起并发 Root worker。
- 修复：测试改为验证共享 Root worker 的单线程/有界队列/AbortPolicy、Root 命令统一入口、队列饱和提示、Activity 生命周期关闭，以及 Gadget log 读取走同一 Root worker。没有为通过测试而增加第二个并发 Root worker。
- 改动路径：`scripts/tests/fx-dia-frida-gadget-session-regression.sh`、本状态文件。
- 验证：已对照 `FxDiaFridaActivity` 当前 `worker`、`submitWorker`、`runRoot`、`showGadgetSessionLog` 与 `onDestroy` 实际实现；等待 Actions。
- 下一步：查看 session regression 后续首错；再继续 Frida server/Gadget UI 的状态同步和取消返回链。


## 2026-11-05 — Dia Frida/CrashReport 定向回归断言修正

- Actions `41917868626` 首错：新增会话日志线程池检查把 `ThreadPoolExecutor` 构造函数误按单行匹配，源码实际按多行格式化；已改为分别检查构造调用和参数/单项队列，保留容量为 1 的强约束。提交：`1bb1c3557d99fcea95acef2903f8923f8b37a7d1`。
- Actions `41917824964` 首错：CrashReport 测试错误要求 `FxDiaNativeCrashCapture` 内出现调用表达式 `clearMinidumps(context)`，实际类定义的是 `clearMinidumps(Context context)` API；同时有多处测试期望旧变量名/旧布尔表达式，与 `FxDiaCrashDumpDirectory` 现行 `directory.equals(...)` 和失败即返回 false 的实现不一致。已按当前实际 API/路径守卫重写断言，不改变产品代码。提交：`66b34177b24a5fa8ff8edca216d86c60f85bdf70`。
- 未验证：两项测试修正均等待新 Actions；不宣称 CrashReport 或 Frida 回归通过。
- 下一步：读取新 Actions 首错；若通过，再继续处理 Frida SessionLog bounded worker 和 Gadget/Server 偏好一致性。CI 中 `FxDiaSessionLogActivity` 路径断言来源矛盾仍需追踪。


## 2026-11-05 — 最新 Frida CI 阻塞记录（非本轮 UI 页面回归）

- Actions `41917868626` 在 Frida Gadget Session 回归处失败：`fx-dia-frida-gadget-session-regression.sh` 报 `Frida session log worker must use a single bounded worker`。Gadget config writer/deploy 检查此前通过；该失败发生在 Frida session log worker 契约，不是 DNS/File Browser/System Expand UI 断言。
- Actions `41917824964` 的 Dia Crash Report 回归另有失败：`native dump directory has no explicit cleanup path`。需对照当前 `FxDiaNativeCrashCapture` 与 `FxDiaCrashDumpDirectory` 的实际职责，确认是产品缺口还是旧测试引用过期；不得删除安全清理检查来换绿灯。
- 本轮 UI 证据：System Expand 安装来源搜索 Actions `41916108180` SUCCESS；File Browser 基础分页/SAF Host 回归 `41916426607` SUCCESS；DNS cache/log UI 定向回归 `41917559211` SUCCESS。File Browser 搜索与 DNS 旋转恢复竞态的后续回归多次被并行 push 的 concurrency 取消；Backup 表单状态回归也曾取消，已通过单 job rerun 继续执行，需核实最终结果。
- 下一批：优先读取 File Browser/Backup rerun 结果；随后按真实代码核实 Frida session worker 和 Crash Report cleanup 两个 CI 阻塞。不要重复触发整套 Actions。


## 2026-11-05 — Session log worker regression

- The Activity already uses a one-thread `ThreadPoolExecutor`, one-item `ArrayBlockingQueue`, `AbortPolicy`, queue-full feedback and lifecycle shutdown. The old test expected a constructor string without accounting for line breaks.
- Replaced the literal with a whitespace-tolerant regular expression and retained the overload/lifecycle checks.
- Test commit: `2d45d8b193983f4ff986902bc7ce0b5d8c2e81e0`. Actions pending.


## 2026-11-05 — Gadget status refresh

- Added a session status refresh action and its regression checks.
- Android device validation is pending.


## 2026-11-05 — 游龙安全护盾白名单选择提交前复核

- 页面组：安全护盾 → 白名单管理 → 添加应用选择器。
- 发现缺陷：选择器在 Activity 重建时恢复 `selected` 包名；用户可能在后台卸载应用或该包在恢复后不可见。原 `saveSelected()` 只调用 `isSystemPackage()`，而该方法在 `getApplicationInfo()` 失败时返回 false，导致已卸载/不可用包被当作普通用户应用写入白名单。成功提示也直接显示 `selected.size()`，可能把未实际新增的条目计入。
- 修复：保存前通过 PackageManager 重新验证每个暂存包仍已安装、不是 FX 自身、且符合用户应用条件；失效项跳过，不产生写入。只在实际新增数大于零时保存，成功文案显示真实新增数并提示跳过数量。管理页和选择器的系统应用判断统一允许 `FLAG_UPDATED_SYSTEM_APP`，与应用列表筛选一致。
- 产品提交：`d4b6127c7dcbe5f0c279a92736c41928b4ce7682`（WhitelistActivity）、`23b97b2b8d2929c0f6d9541181dc890f6bf6d815`、`05dee9be090c5c559ffafb23a50dfbbb94c43f69`、`809bc08d23e3f56d99d05c9e3dc7bdad5a6466d5`（WhitelistPickerActivity）。
- 回归提交：`60ce61cd2d041968c86b876593c50754f4512fae`，覆盖 PackageManager 复核、失效项拒写、真实新增计数和更新系统应用策略。
- 验证：源码与静态回归断言已提交；Actions 尚待读取。未执行 Android Gradle/JUnit、应用卸载并旋转的 UI 自动化或真机。
- 下一步：读取安全护盾名单/扫描定向回归；继续风险详情、批量清理和扫描不完整状态 UI 的真实错误回显。



## 2026-11-05 — Yulong app list scroll restore update

- Firewall, App Whitelist and App Stats now invalidate older posted scroll callbacks when a search changes and when an Activity is destroyed. A newer scroll restore is applied only when its generation is still current.
- Product commits: `ce2d7caccaecaca1a7919065b4b0717491daea69`, `1973aa04c83131fc0da656d08062781550eede03`, `bfacd24b4e7d51076c3b61bd579fe784d6eada4c`.
- Regression commits: `6c63c5e56762efd965faccf4c0071ca0ef99aaed`, `b73aee4ea771c81dd3d7fc20255576dabf07396e`, `2e40c1e25bb0f990fb9b411bd535ae6cd3e53687`.
- Actions and device UI/rotation tests pending.


## 2026-11-05 — Yulong app-list scroll tests status

- `fx-yulong-app-whitelist-activity-regression.sh`: Actions `41918782161` SUCCESS.
- `fx-yulong-app-stats-regression.py`: Actions `41918827421` SUCCESS.
- `fx-yulong-firewall-activity-regression.sh`: Actions `41918758162` was cancelled by a later push before a final result; source/test changes are committed, but CI is not marked passed.
- No Android rotation or real package install/remove device test has run.


## 2026-11-05 — 六 Tab 原生页面底部导航栏适配 Android 系统导航区

- 页面组：共享壳 `FxNativeAppShell.kt`，覆盖继承 `FxNativeTabActivity` 的 Dia/游龙广告/安全护盾页面。
- 风险：AndroidView 页面与玻璃/经典/MIUIX 两种底栏直接贴齐 Box 底部，没有显式避让 Android 手势/三键导航 inset；edge-to-edge 或特定导航模式下可能压入系统导航区。
- 修复：页面内容先应用 `navigationBarsPadding()` 再预留 72dp 底栏；玻璃底栏与经典/MIUIX 底栏分别应用 `navigationBarsPadding()` 后再设置 72dp 内容高度。六 Tab 数量、顺序、回调和样式不变。
- 产品提交：`dea52536b27d265e0436d44def250884f37322ce`；回归提交：`5caa09cc96312d0a41f545f3219aec9d264fd67e`。
- 验证：静态检查确认页面内容和两种底栏各有 inset 处理；Actions 尚待读取。未执行 Compose UI 截图、手势/三键导航设备测试或旋转测试。
- 下一步：读取本批六 Tab/Shield 回归；继续检查 MainActivity 六 Tab 主壳的 edge-to-edge、软键盘和返回状态，再转回 Shield 风险详情/批量清理 UI。


## 2026-11-05 — 六 Tab classic 底栏 inset 回归补齐

- 首次 `41919031554` 失败暴露实现漏项：页面内容与 Glass 底栏已加 `navigationBarsPadding()`，classic/Miuix `Row` 底栏仍未加。不是放宽测试；按日志补齐 classic/Miuix 底栏的系统导航区避让。
- 修复提交：`8a18767b0786b5f90448279d0269f0b8279dee49`。当前共享壳应包含三处 inset：AndroidView 页面、Glass 底栏、classic/Miuix 底栏。
- 验证：最新源码回读统计到 3 处 `navigationBarsPadding()`，Glass/classic 两个底栏各 1 处；新 Actions 尚未完成。设备导航模式与 edge-to-edge 视觉仍未验收。


## 2026-11-05 — 六 Tab 共享壳回归映射接入 Actions

- Actions `41919196015` 已确认：产品源码的三处 navigation inset 已存在；失败根因不是测试断言，而是 `.github/workflows/fx-targeted-regression.yml` 的 changed-path 路由没有包含 `FxNativeAppShell.kt`，因此源码变更进入“无对应 Host regression mapping”退出分支。
- 修复：将 `FxNativeAppShell` 加入 Dia 原生页面回归映射，并在该映射内明确运行 `fx-dia-six-tab-regression.sh`。不会放宽 Host 测试，也不会让共享壳改动绕过回归。
- Workflow 提交：`760e3f9280861f4e0f88d0188f5457b3f7b48722`。
- 下一步：读取新 Actions；若六 Tab regression 通过，再继续 MainActivity 主壳 edge-to-edge/软键盘状态；否则按新首错定位。


## 2026-11-05 — Frida Gadget session regression Python 引号语法修复

- Actions `41919397802` 的首错发生在 `fx-dia-frida-gadget-session-regression.sh` Python here-doc 第 77 行：新增“状态检查只读”断言中的双引号/反斜杠转义使 Python 解析失败，尚未执行该脚本后续产品断言。
- 修复：改用单引号 Python 字符串表达 `kill "$` 搜索片段，避免双引号与反斜杠嵌套。没有删除只读状态检查。
- 测试提交：`ef0d4b38442dbb129d0a3e3edab1813814d5ec06`。
- 下一步：读取新 Actions；同时复核 `FxNativeAppShell.kt` 的六 Tab inset 变更是否通过映射后的专用回归。当前仅有源码/测试静态检查，未做 Android 视觉与真机验收。


## 2026-11-05 — 六 Tab 原生共享壳软键盘避让

- 页面组：共享原生 Tab 容器 `FxNativeAppShell.kt`，覆盖通过 `FxNativeTabActivity` 使用该容器的迁移原生页面。
- 发现问题：共享壳为 Android 系统导航栏预留空间并固定底部六 Tab，但根 `Box` 未处理 IME inset。页面中的输入框/编辑器打开软键盘时，底部导航可能被键盘遮挡，页面可视区域也没有统一收缩；这会影响 Dia 脚本/代码编辑器、Hook 规则编辑和其他迁移页面的键盘交互。
- 修复：在共享根容器增加一次 `.imePadding()`，使页面视口与六 Tab 底栏一起避让软键盘；未改变六 Tab 顺序、72dp 底栏高度、导航回调或页面业务逻辑。
- 改动路径：
  - `adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt`
  - `scripts/tests/fx-dia-six-tab-regression.sh`
  - 本状态文件。
- 提交：
  - 产品修复：`eee2d14a005f05f8841c0f5e8f57bac2e0a23f20`
  - 定向回归：`f44ba981fabe3dd84a6e12adff15cf4828834000`
- 静态验证：从目标分支重新读取两个文件；确认 IME import、共享根 Box 唯一 `.imePadding()`、修饰符位于背景之前；回归脚本新增 IME import、唯一调用和根容器范围断言。读取回验全部 6 项静态条件通过。
- 验证等级：GitHub 源码静态核对通过。未运行本地 Host shell regression（当前未建立仓库工作树）、Kotlin/Compose 编译、Gradle 构建、UI 自动化、软键盘截图、旋转或真机测试；不声称键盘视觉行为已设备验收。
- 未触发完整 Actions；无失败路线。没有删除功能或改变 FX 版本。
- 本批提交前最新代码/回归 HEAD：`f44ba981fabe3dd84a6e12adff15cf4828834000`；本状态文件随后单独提交，提交 SHA 由 GitHub 返回。
- 下一批直接任务：
  1. 核对 MainActivity 主应用六 Tab 与共享原生迁移壳是否存在不同的 IME/系统栏适配路径；只修真实缺口，避免重复添加 inset。
  2. 继续 Hook 编辑器、Dia 脚本编辑器的键盘遮挡/滚动/保存状态恢复页面级核对。
  3. 若上述共享 UI 回归无缺陷，转入安全护盾扫描结果/风险详情的原始页面映射差异。
- 失败路线：本批未遇到失败路线；下一轮不要重复全量盘点或重跑整套 Actions。


## 2026-11-05 — Gadget session regression script duplicate-tail repair

- Actions `41919397802` and `41919533754` failed before completing the Gadget session regression because a duplicated Python assertion block had been appended after the first complete shell fixture; the duplicate contained malformed shell syntax.
- Restored the original full source-contract checks and local process/UID/FIFO lifecycle fixture, retaining a single copy. No fixture behavior or product code was removed.
- Repair commit: `b9b130309ee808533dd47e15c58db268618269de`. Targeted Actions pending.


## 2026-11-05 — Frida session 与六 Tab 回归断言对齐

- Actions `41919894854` 首错：会话日志线程池回归的 Python 正则把括号/空白转义成双反斜杠，导致正则本身无法编译；已改成单层正则转义，仍检查单线程、单项队列和 `ThreadPoolExecutor` 构造。修复提交：`a3d0ad3a2eb13aca86faf54b28339a2570d89a7e`。
- Actions `41919804590` 首错：六 Tab 页面路由测试仍要求 `FxDiaFridaActivity` 启动 `FxDiaScriptLibraryActivity.class`，但当前真实实现把脚本库原生界面集成在 Frida Activity 内，由 `showFridaScriptLibrary()` 打开。已把断言改为检查用户可见入口按钮和原生实现方法，保留页面功能验证。修复提交：`c88ff46b6cb4e2b0dc3fd094d96e4b61488357cb`。
- 说明：两项都是测试契约与当前源码实现不一致；没有删除产品页面或降低六 Tab/脚本库功能要求。
- 下一步：读取新 Actions；若通过，回到 MainActivity 主壳和 Hook/Dia 编辑器的软键盘遮挡与返回状态，避免继续陷入测试补丁循环。


## 2026-11-05 — Gadget session 与 Dia Inspector 回归契约二次修正

- Actions `41920295990` 首错：状态检查只读断言把布尔表达式放进 `(label, needle)` 元组，循环随后执行 `needle in check`，触发 TypeError。已将只读条件改为独立 if，继续检查 `rm -f` 和 `kill "$` 均不出现在状态查询命令中。提交：`bfb148197093cc94415cceb97c94da02d359a0a0`。
- Actions `41920329579` 首错：六 Tab 回归仍把 `FxDiaInspectorActivity` 错误归到 Activity Browser 页面；当前 Inspector 是 MainActivity 的独立 Dia 原生路由，Activity Browser 是组件清单浏览页。已将脚本输入增加 MainActivity，改为检查 Inspector 主导航入口，同时检查 Browser 仍读取 `PackageManager.GET_ACTIVITIES`。提交：`f5fd00bdb14e7fe2aa1fae5b37e96aef799e63b2`。
- 下一步：读取新 Actions；不再把 Inspector 页面路由强行要求放在 Activity Browser 内。


## 2026-11-05 — 产品重构总方案与跨 AI 接管提示词

- 新增需求基线：`docs/FX_1.0.0_PRODUCT_RESTRUCTURE_AND_AI_HANDOFF.md`。
- 文档提交：`3801390df82d93aa61ab8976c67bdcdea9a02180`。
- 新增三种可切换 UI 模式：游龙工具 10.0.2 经典网页模式、原生液态玻璃模式、Miuix/澎湃风格模式；三者共用业务层、服务、状态和数据。
- 新增壁纸选择/预览/模糊/遮罩/持久授权/失效回退要求；新增 Ad 多层架构、VPN/防泄漏/MITM/证书、隐私/安全护盾、Dia/GKD/Hook、QuickJS/Loon/Shadowrocket/浏览器脚本需求矩阵。
- 新文档明确技术边界：Android VPN 不能承诺 iOS 同等生命周期/零耗电；系统证书不保证所有应用无警告；Root/LSP 与位置模拟不能承诺绝对隐身；浏览器扩展按浏览器真实 API 支持；不得绕过付费授权。
- 本次仅提交需求与接管提示词，不代表新增功能已实现、构建或真机验证。游龙工具 10.0.2 APK 原件是否可访问、五份源码 intake 是否成功解压，仍须按文档 P0 步骤核实。
- 下一步：先读取新 HEAD 与 intake workflow run/artifact；核实 10.0.2 APK 原件。随后开始 P1 三 Skin/壁纸框架和六 Tab 适配，按页面组提交代码。


## 2026-11-05 — 多脚本生态与可切换网络内核需求补充

- 用户明确要求脚本支持不能局限于 Loon/Shadowrocket；已扩展兼容目标：Surge、Quantumult X、Loon、Shadowrocket、Stash、Egern、Clash/Clash.Meta/Mihomo、sing-box、UserScript 和未来可插拔格式。
- 新增核心要求：FX 必须内置至少一个经过测试的默认网络内核，并支持知名内核（如 sing-box、Mihomo、Xray-core）适配，以及用户上传/自定义内核导入、校验、能力探测、切换、更新和失败回滚。
- 明确分离网络内核 Provider、脚本 Runtime、规则解析器；不能把内核名称切换当成真实切换，也不能把格式解析当成脚本执行兼容。
- 新增内核能力发现、生命周期、配置转换、事件桥接、资源隔离、ABI/许可证/哈希/签名校验和逐内核防泄漏/耗电验收要求。
- 文档提交：`a4c116e75f5d64c39cb2942be86da7e4811e3fb4`；AI 接管提示词同步提交：`00282fb0370923c1678bdc5f189ff00b88f1aa02`。
- 以上为需求文档更新，未声称各内核已集成或各脚本平台已实现。具体内核纳入版本须根据 ABI、许可证、构建来源、维护状态和设备测试决定。
- 下一步：以当前最新 HEAD 为准，读取现有 VPN/TUN 实现和 Gradle/NDK 构建结构，设计 Core Provider 接口并先接入默认内核；同时盘点现有配置格式和脚本 runtime，按平台建立兼容矩阵。


## 2026-11-05 — 扩展补齐其他脚本、过滤规则与内核生态

- 用户要求不能只列举少数脚本平台和代理内核；已补充 Surfboard、Tampermonkey、Violentmonkey、Greasemonkey，以及 AdGuard、uBlock Origin、Adblock Plus、Hosts、PAC、DNS blocklist、URL Rewrite 等规则生态。
- 内核候选扩展为 sing-box、Mihomo、Xray-core、V2Fly/v2ray-core、dae、Leaf、Brook，并将 Hysteria 2、TUIC、VLESS/VMess、Trojan、Shadowsocks、SOCKS、HTTP(S) 明确分类为协议能力，而非独立内核。
- 增加过滤规则 parser/validator、内核类型分类（完整代理核心/协议插件/TUN 组件/规则运行时）和逐版本能力矩阵要求。候选项目不代表已集成，纳入前必须核对维护状态、Android/ARM64、许可证和构建来源。
- 产品方案更新提交：`2cba7819fe4fdf1f5bec6d1ea001e4f0460f8511`；AI 接管提示词同步提交：`bcda2e0638c9acc3538d404cb225ed4862d2f4b1`。
- 下一步仍是实际工程接入：读取现有 VPN/TUN/Gradle/NDK 代码，确定首个默认内核和 Core Provider 接口；再逐步增加其他 provider，避免一次性塞入未经验证的多个二进制。


## 2026-11-05 — 明确 FX 必须采用内核级代理并与应用 VPN 共存

- 用户明确要求：FX 代理是内核级代理，必须能够与第三方应用 VPN 同时使用，不冲突。
- 已将 FX 主代理定义为 Root/系统网络栈级数据面，按设备能力使用 policy routing、iptables/nftables、TPROXY/REDIRECT、受控 tun2socks 或等效后端；FX 自身 VpnService 仅作为无 Root/不支持时的备用兼容后端。
- 明确禁止 FX 主代理抢占 Android VPN 槽、停止第三方 VPN、flush 全局防火墙规则或覆盖第三方路由；保存并只撤销 FX 自己创建的路由/防火墙/DNS 规则。
- 将“FX 代理 + 第三方应用 VPN 同时运行”列为核心验收目标，要求识别 VPN 接口/路由/UID 策略，避免回环、重复加密、DNS 泄漏和路由黑洞；支持官方链式集成，并对封闭 VPN 的兼容限制如实分级，不能声称所有第三方 VPN 无条件兼容。
- 产品方案提交：`4ae83e4102560110cc55bfebba4555636a30a250`。这是需求/架构基线更新，尚未代表内核级代理代码已实现或真机验证。


## 2026-11-05 — 三种全局 Skin 的源码实现

- 用户要求三种可切换全局界面模式必须将实现方案和源码写入仓库，不能只写概念文档。
- 已新增 `adhook/app/src/main/java/de/privacyguard/adhook/FxUiMode.kt`：定义 ClassicWebCompat / FXLiquidNative / MiuixStyle，保留既有存储 ID（classic/glass/miuix），兼容旧 web 值，统一读写 `fx_ui/mode`。
- 已更新 `FxDesignModePanel.kt`：三模式选择器改为明确产品名称，并声明换肤不得重启网络、Hook、脚本服务。
- 已更新 `MainActivity.java`：统一模式 ID 规范化；ClassicWebCompat 显示 APK 内置 WebUI 并由底部 Tab 导航；FXLiquidNative/MiuixStyle 隐藏 WebView、使用原生页面；切换逻辑仅调整展示层。
- 已更新产品重构方案，记录源码路径、全局路由、状态保留、安全边界和三模式验收矩阵。
- 提交：`2f450063134e9d0b2a98598a2f0d63f46e5a1e12`（FxUiMode）；`8f8fab0529575c811c4b2bdbaa7da64ac31eaf7a`（模式选择器）；`60b691a441f37cfb61aa27c223254efc59747753`（MainActivity 路由）；`a7a640e0d22dcc2f7eb3b7ff1e42a7b3dbbb12a2`（产品方案）。
- 当前状态：源码已提交，尚未完成 Gradle 编译、自动化 UI 测试和真机三模式切换验收；不得标记为已完全验收。


## 2026-11-05 — 三种全局界面模式源码接入（进行中）

用户要求三种可切换全局界面模式必须有实现方案和源码，不接受只写概念。已开始写入应用源码：

- 新增 `FxUiMode.kt`：集中定义 `ClassicWebCompat/classic`、`FXLiquidNative/glass`、`MiuixStyle/miuix`；兼容旧存储 ID；提供统一 read/write。
- 更新 `FxDesignModePanel.kt`：设置页显示三种正式模式名称、模式职责和切换不重启服务的约束。
- 更新 `FxNativeAppShell.kt`：三种模式使用不同背景、导航圆角、表面配色；Liquid 模式使用 Kyant LiquidBottomTabs，Miuix 使用 MiuixTheme 色彩，Classic 使用低圆角兼容导航样式。
- 更新 `MainActivity.java`：启动通过 FxUiMode 读取；切换通过统一模型同步保存，失败不继续切换；换肤只更新界面，不调用 VPN/DNS/代理/Hook/脚本启停接口。
- 源码提交：`2f450063134e9d0b2a98598a2f0d63f46e5a1e12`、`8f8fab0529575c811c4b2bdbaa7da64ac31eaf7a`、`41a9474c7acd74f5306bb4bf48ef647e24351922`、`761f1093fe780ea2d9c8adea8293495ba9302c72`。
- 方案文档提交：`892c2b8b626061d94315db78a32fb05e32a52053`。

当前边界：已落地统一模式模型、设置面板、Shell 差异化外观和持久化入口；尚未完成 Gradle 编译、安装运行、所有页面逐页视觉验收及服务运行期间换肤测试。ClassicWebCompat 目前采用现有 native 页面容器与兼容外观，尚不能宣称已完整恢复旧 WebUI 的全部页面行为。下一步先编译并修正 Kotlin/Java/Compose 集成错误，再补全各页面的模式差异与运行中无中断验收。

- 补充修正：ClassicWebCompat 的实际可见 WebUI 页面范围明确为 VPN、Ad/Hosts、隐私、脚本四个业务页；Hook 与设置由同一原生宿主承载并采用 Classic 外观，避免文档夸大为六页全部来自旧 WebUI。
- 新增单元测试 `adhook/app/src/test/java/de/privacyguard/adhook/FxUiModeTest.kt`，覆盖三种枚举、稳定存储 ID、旧 `web` 别名迁移、未知值回退和显示名称映射。
- 单元测试源码已提交：`7c31f43e7086eccc7b0587f38578d81d50275e8b`；文档准确性修订提交：`b0c85901437b2a7e4144958efbbc76c87b877534`。


## 2026-11-05 — 三模式界面增加自动回归门禁

- 新增 `scripts/tests/fx-global-ui-modes-regression.sh`，检查统一模式枚举/旧 ID 兼容、三个模式选择入口、Liquid/Miuix/Classic Shell 分支、统一持久化调用。
- 将该回归脚本加入 `.github/workflows/build-fx-adhook.yml` 的静态迁移检查步骤，避免后续改动静默移除三模式接线。
- 测试脚本提交：`5e9121fa6b0c26e072c4f520f14afce7b67f1d8e`；CI 接入提交：`b9db142c5ce27ce1a0088566812311b7a51bee7f`。
- 当前未能从本轮连接器触发 Actions，也没有 Gradle 编译结果；此处只确认源码和工作流配置已写入，不能报告 CI 通过。下一步应获取该分支 PR 触发的 workflow run，读取具体 job 日志，先修复编译/静态回归失败，再做安装和运行中切换验证。

- 回归脚本复核发现原断言引用了不存在的 `RoundedCornerShape(when (mode)` 写法，且错误地要求模式标题字面量出现在选择器文件。已修正为检查真实 enum 选择入口、Liquid/Miuix/Classic 分支、Classic WebView 挂载及 Tab 路由，避免静态门禁自身误报。
- 修正回归脚本提交：`aaf22d600fbf80d31fd40f39ee8f6c2ce20dc94a`。工作流已接入该脚本，但本轮未执行 Actions/Gradle，不能标记测试通过。


## 2026-11-05 — 新增 HUAWEI 与 iOS 全局界面模式接管要求

- 用户要求在跨 AI 接管提示词中加入 HUAWEI 和 iOS 界面模式及实现方法。
- 全局 Skin 目标由三种扩展为五种：ClassicWebCompat、FXLiquidNative、MiuixStyle、HUAWEI HarmonyStyle、iOS CupertinoStyle。
- HUAWEI 模式定义为 Android APK 内的 HarmonyOS 风格 Skin：通过 Jetpack Compose 独立 Design Tokens 与组件 Renderer 实现卡片层级、服务卡片式信息组织、留白、图标/字号网格、动效和系统栏适配；不得依赖 HMS/HarmonyOS 私有 API，不得伪称 HarmonyOS 原生应用。
- iOS 模式定义为 Android APK 内的 Cupertino 风格 Skin：通过 Compose 自有组件实现导航栏、标签栏、分组列表、Form、Toggle、Sheet、ActionSheet 和层级模糊；遵循公开 HIG 的交互原则，不调用 Apple 私有 API，不分发未经许可的 SF Symbols/字体/系统资源，不得伪称 iOS 原生客户端。
- 两种新模式须加入统一 FxUiMode 稳定 ID（建议 huawei/ios）、统一 Skin Host、tokens、六 Tab 页面适配、深浅色/字体缩放/无障碍/WindowInsets/返回手势和截图回归；换肤不能重启 VPN、内核级代理、DNS、Hook 或脚本服务。
- 本次仅更新产品方案与 AI 接管提示词，不代表 HUAWEI/iOS Skin 已有源码实现。现有 FxUiMode.kt、FxDesignModePanel.kt、FxNativeAppShell.kt 当前仍只有 ClassicWebCompat、FXLiquidNative、MiuixStyle 三模式，后续必须继续修改源码、测试和编译。
- 产品方案提交：8c0ec08a52c1d54d9b1e5e4825c627c7a33ec835。
- 验证：已从 GitHub 读取更新响应；尚未完成新增两种模式源码、Gradle 编译、截图/UI 自动化或设备验收。



## 2026-11-05 — 跨 AI 接管提示词补齐 HUAWEI 与 iOS Skin 实施细则

- 用户要求把 HUAWEI 和 iOS 界面模式及实现方法写进可复制给其他 AI 的接管提示词，而不只保留在产品概述正文。
- 修正 `docs/FX_1.0.0_PRODUCT_RESTRUCTURE_AND_AI_HANDOFF.md` 的完整接管提示词：明确五种模式；新增 HarmonyStyle 与 CupertinoStyle 的独立 tokens、Compose renderer、组件覆盖、平台能力边界、资源许可约束、六 Tab 逐页适配、统一 storage ID、服务生命周期隔离和分层验收。
- 同步修正实施阶段 P1、架构 Skin 清单和逐页验收要求，防止接管 AI 仍按“三 Skin”推进。
- 当前实际源码状态不变：FxUiMode.kt、FxDesignModePanel.kt、FxNativeAppShell.kt 仍只有 ClassicWebCompat、FXLiquidNative、MiuixStyle 三种模式。HUAWEI/iOS 是提示词和需求基线，不代表已实现；下一步必须继续源码迁移、单测、编译和 UI/设备验收。
- 本批只更新接管提示词和状态记录；不声称五种模式已完成，不声称 Gradle/设备验证通过。


## 2026-11-05 — 整体重构导航纠偏与独立 AI 接管提示词

- 用户指出旧方案仍保留“设置下的迁移应用”，并将第二 Tab 显示为“Ad/Hosts”，与单产品整体重构目标冲突。
- 当前有效六 Tab 固定为：VPN、Ad、隐私、脚本、Hook、设置；第二 Tab 只显示“Ad”，Hosts 是 Ad 内部功能页。
- “迁移应用”入口、来源 APK 启动器和来源应用平行导航必须从最终 UI 删除。Dia、游龙广告插件、游龙安全护盾、GKD 等只作为研发来源，其实际功能按 Ad/VPN/隐私/脚本/Hook 归并；不得以删除入口为由丢失功能。
- 设置只保留外观/五种模式/壁纸/主题/动效、权限中心、备份恢复、通知与诊断偏好、关于；不得保留迁移应用或业务功能。
- 更新产品重构文档并新增独立提示词 `docs/FX_1.0.0_MASTER_AI_TAKEOVER_PROMPT.md`，可单独交给其他 AI 接管。提示词包括五种 Skin、游龙 10.0.2 旧界面和壁纸、Ad 六层/游龙广告插件全功能、VPN/内核级代理与第三方 VPN 共存、防泄漏/MITM/证书边界、隐私/安全护盾、Hook/Dia/GKD、脚本生态、功能归属、执行阶段和真实验证纪律。
- 明确技术限制：不能承诺所有应用无感信任 MITM CA、零耗电、绕过 VIP 授权或位置模拟通过所有真实性校验；必须按设备/应用/权限实测分级。
- 本批更新的是重构方案与接管提示词，尚未修改导航源码；下一步立即检查 MainActivity、FxNativeAppShell、设置页面、路由和测试，真正删除迁移入口并将第二 Tab 改为 Ad。


## 2026-11-05 — 移除设置迁移入口并统一 Ad 页面标题

- 检查最新 MainActivity 后确认：设置页已经没有“迁移应用”可见入口，设置说明和五种模式文案也已更新；但 Ad 业务页标题仍显示“广告与 Hosts”，与用户要求不一致。
- 已将 Ad 业务页标题改为 `Ad`，并把介绍文案改为“Hosts 是 Ad 内部的一个功能”，明确 Hosts 不再作为主 Tab 并列名称。
- 当前 `FxNativeAppShell.kt` 六个底部标签已核实为 VPN、Ad、隐私、脚本、Hook、设置；设置始终第六。
- 当前 `MainActivity.java` 中未发现 `section("迁移应用")`，也未发现从设置页调用 `showImportedSuite(...)` 的入口；旧来源目录方法仍保留为迁移过程中的遗留代码/功能映射，不代表所有来源功能已完成归并或运行时迁移。后续应按功能真实落地情况逐步退役遗留路由，不可直接删除未迁移的后端功能。
- 源码提交：`f411510dc43c0b7583365eafddf94fc97e43405e`。
- 回读静态验证：旧 Ad 标题不存在、新 Ad 标题存在、设置迁移入口不存在、五模式文案存在；Shell 六 Tab 标签符合目标。
- 未运行 Gradle 编译、Host 回归、UI 自动化或真机测试；不能声称构建/设备验证通过。
- 功能完整性说明：游龙广告插件、Dia、游龙安全护盾/GKD 的所有原始功能并未因此自动完成迁移。仍需逐项核对来源源码、对应 FX 业务页、真实后端和验收记录；不得把保留的旧功能目录当成已整合完成。
- 下一批：检查 Ad 页面原功能目录与规则/统计/计划任务真实后端差异；将仍可用的来源功能逐项归并到 Ad/隐私/Hook/脚本页面，避免出现来源应用启动器。


## 2026-11-05 — 实际移除设置页“迁移应用”入口并固定 Ad 主导航

- 用户再次指出设置下仍显示“迁移应用”，且主 Tab 名称必须是 Ad。
- 已修改 `adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`：
  - 从 `showSettings()` 删除 Dia 23.11、游龙广告插件 7.0.1、游龙安全护盾 9.9.60 三张来源应用卡片和“迁移应用”分组。
  - 设置说明文案改为外观/壁纸/主题/授权/备份恢复/诊断等全局配置。
  - 旧版 Activity 状态若仍保存了迁移应用页面，恢复时现在回到设置页，不再恢复来源套件页面。
  - 不再向新 Activity state 保存旧迁移套件导航字段。
- 新增 `scripts/tests/fx-unified-navigation-regression.sh`，检查设置页不含迁移应用入口/来源应用卡片、旧状态恢复回设置、原生六 Tab 标签精确为 VPN、Ad、隐私、脚本、Hook、设置。
- 已将该回归脚本接入 `.github/workflows/build-fx-adhook.yml` 的静态迁移检查。
- 提交：
  - MainActivity：`6392d8ffd95f7b14d97fdc81a6b73235dc57b78e`
  - 回归脚本：`f78b40162f903c35c326dd005ba24cbb77fcec6d`
  - CI 接入：`62eea8ed6b37906b2616f05790de2ba5db870e6f`
- 验证边界：本轮完成源码写入和 CI 接入；当前会话没有执行本地 Gradle/Android 构建，也没有 GitHub Actions run 结果，不能宣称回归已通过。
- 尚未完成：来源应用功能仍有内部迁移页面/导航代码，必须逐项接入 Ad/VPN/隐私/脚本/Hook 对应业务页后再退役；本轮只移除了设置中的来源应用入口，不代表来源功能已全部迁移。五种 Skin 中 HUAWEI/iOS 的真实 renderer 仍未完成。


- 追加 UI 诚实状态修正：设置页不再把五种 Skin 描述成全部可切换；明确当前只有 ClassicWebCompat、FXLiquidNative、MiuixStyle 三种可选，HUAWEI HarmonyStyle 与 iOS CupertinoStyle 尚未接入 Renderer。回归脚本同步检查这一边界，避免“计划中”被误报为“已上线”。
- 本次新增状态修正提交：`b64c400366ce82bc4691ea445af235ea2b0dee3c`；回归断言提交：`1e88a747c94f03ff636bfdaeca1d869eff6e34da`。


## 2026-11-05 — HUAWEI HarmonyStyle 与 iOS CupertinoStyle 首批源码接入

- 将全局 Skin 从三项扩展为五项：
  - `huawei` / `HUAWEI HarmonyStyle`
  - `ios` / `iOS CupertinoStyle`
- 修改 `FxUiMode.kt`：新增两种稳定 storage ID、Renderer 类型、显示名称、说明和导入别名；旧 classic/glass/miuix ID 保持兼容。
- 修改 `FxDesignModePanel.kt`：五种模式全部显示在全局模式选择器。
- 修改 `FxNativeAppShell.kt`：新增 Harmony 与 Cupertino 的全局背景、底栏表面、圆角和选中态视觉分支；没有使用 HarmonyOS/iOS 私有 API。
- 修改 `MainActivity.java`：设置说明准确区分已接入的全局导航/表面 Skin 与仍在进行的逐页组件适配；模式选择区域增加可滚动高度。
- 修改 `FxUiModeTest.kt`：断言五种模式数量、ID 和别名。
- 更新 `scripts/tests/fx-global-ui-modes-regression.sh` 与 `scripts/tests/fx-unified-navigation-regression.sh`，覆盖五种模式及迁移入口删除要求。
- 相关提交：
  - `9fe04d05557e3b108042834dfd8cb1a77b9c2c2d` FxUiMode
  - `448b0ef97eeb551f2e945c1abb395853b447eb78` 模式选择器
  - `32cc683d6d70f414175294414c7302b83fc6a9eb` 全局导航 Skin
  - `9ef319549fa32eae4e714ed8b0f3d91783e11d33` 单元测试
  - `a8887983951f2fbbd8f5e9d023ad8c8346bb5693` 设置状态与面板高度
  - `3eb168192fd4be9924eab55222ee8ecd0f0b009d` 五模式回归脚本
- 当前边界：本批实现的是模式持久化、选择器和全局导航/表面 Skin，不等于六个 Tab 内所有页面已完成 HUAWEI/iOS 逐页视觉重构；尚未执行 Gradle 编译、单测或真机验证。不能报告构建通过。


- 追加完成原生业务页面基础表面适配：`MainActivity.uiSurfaceColor()`、`roundedDrawable()`、`uiPanelDrawable()` 现在对 HUAWEI/iOS 使用独立表面色、圆角和细边框，不再回落到 Classic 的默认卡片外观。提交 `ffd27e991328043b4a46771d48b1c7aa57a909c0`。
- 五模式回归脚本增加 MainActivity 页面表面断言，提交 `921a37d3f732b176c21caeb2d9205f825b9f80a0`。


## 2026-11-05 — 将游龙广告插件核心功能入口并入 FX 的 Ad 页面

- 修改 `MainActivity.buildNativeHostsPage()`，在 Ad 页面内新增“广告过滤完整功能”分组，提供 FX 内部入口：
  - 广告过滤控制中心（`FxYulongAdActivity`）
  - 通用设置与备份恢复（`FxYulongAdGeneralActivity`）
  - 拦截统计与每日摘要（`FxYulongAdSummaryActivity`）
  - 应用网络防火墙（`FxYulongFirewallActivity`）
  - 应用广告过滤白名单（`FxYulongAppWhitelistActivity`）
- 上述 Activity 均已在同一 FX APK Manifest 内声明；本次让这些功能从 Ad 业务页可达，不再依赖“设置→迁移应用”入口。
- 提交：`dfb66743da8d83480c51859cadd69ec122b0905f`；导航回归增加功能可达性断言：`a5ec96960a3abb7708585a7f06199e068d1e34d8`。
- 边界：这批完成的是五个既有原生功能页的 Ad 内入口整合；不代表游龙广告插件所有功能已经全部迁移完成，也不代表这些 Activity 已全部合并成同一 Compose 页面。后续继续把独立 Activity 的业务状态和页面逐步收敛到 Ad 页面栈。


## 2026-11-05 — 游龙工具 10.0.2 壁纸功能首批迁移与回归修正

### 原 APK 核验
- 从资料库根目录找到并读取 `/游龙工具_10.0.2.apk`（不在 /FX 子目录）。
- 文件大小：92,008,250 bytes；SHA-256：`c2d7bb1b8e688232888a927d5b81affcf5c28832f9e6420e27e800e54f5fee75`。
- 从 APK Manifest/DEX 核实：package `com.youlong.tool`，versionName `10.0.2`，versionCode `1234567901`。
- 原版壁纸对照为 Native Wallpaper Dialog：标题“壁纸随心换”；上传本地图片、恢复默认壁纸、关闭；使用 `native_wallpaper_prefs / wallpaper_path`；选中图片复制到私有 files 目录，最长边 1920 px，JPEG quality 85，文件名 `native_wallpaper_<timestamp>.jpg`。未把未经证实的裁剪/模糊控件冒称为原版功能。

### FX 源码落地
- 新增 `FxWallpaperStore.kt`：应用私有目录存储、原 10.0.2 SharedPreferences key 兼容、图片分辨率上限、1920px 缩放、JPEG 85、原子发布、旧壁纸安全清理、预览/显示位图有界解码、恢复默认。
- 修改 `MainActivity.java`：设置页新增“壁纸与背景 → 壁纸随心换”；有预览、当前状态文案、系统 ACTION_OPEN_DOCUMENT 图片选择、“处理中...”后台保存、失败保留原图、恢复默认。壁纸存储/解码不在 UI 线程执行。
- 修改 `FxNativeAppShell.kt`：壁纸作为共享 Presentation 背景加载；覆盖六个主 Tab 及共享原生 Activity 壳；导入页面根容器透明以露出壁纸；Bitmap 在 IO dispatcher 解码并在 Compose dispose 时释放。
- Classic Web 兼容页通过透明 WebView/页面根背景显示共享 Shell 壁纸；关闭自定义壁纸时恢复原主题背景。
- 新增 `FxWallpaperStoreTest.kt`：横图/竖图比例、1920px 长边、采样大小、非法尺寸单测。
- 新增 `scripts/tests/fx-wallpaper-regression.sh`，并接入 `.github/workflows/build-fx-adhook.yml` 与 `.github/workflows/fx-targeted-regression.yml` 的定向检查。

### 定向 Actions 失败与修复
- 旧定向测试未给 `FxWallpaperStore.kt` 增加路径映射，曾报“changed source path has no targeted Host regression mapping”；已在 `fx-targeted-regression.yml` 增加 WallpaperStore、NativeAppShell、MainActivity 和 wallpaper test 的映射。
- Dia crash dump 既有测试错误要求目录重建代码必须是无 `create` 参数的字符串；实际 `checkedDirectory(filesRoot, true)` 已对 missing directory 执行 guarded mkdir，Host JVM 用例本来就覆盖创建行为。已把静态断言改为匹配真实的 guarded-create 实现，不改变生产逻辑。
- 修复提交：`f09bf024934b3b6eaefd76a4e2acc2dedd04d672`（修正 crash dump 静态断言）；`82b72af33ba5f3ae810752720b7ac299bef74a55`（壁纸 Store/Shell 测试映射）；`d1eabc29c87951208a9829f33db570f463809839`（MainActivity 壁纸入口映射）。
- 回归补充提交：`2820475a845b48ffff430e80daec0bf336ccc0a6`（WallpaperStore tests）；`aaf4b2d5d5a19907d26cffd3ec930df88ccb98bc`（wallpaper host regression）；`8c8e8d82704071dfdc5e029e87e6ae993eca087b`（build workflow 接入）；`de5b5ba9bfc27ae76f2f58ea3d58e5078f3ac408`（竖图缩放期望修正）。
- 其他壁纸代码提交：`1f7a1922fb6e4dbb8eb022a41dc7879691d12d9c`（Store 初版）；`090e1b726e15b2da5d8354a977aa73c6c738ccc1`（按目标长边限制采样）；`26fc3149aa899c14b7b8b383110c547fd6023f9e`（设置入口/选择器/预览/恢复）；`fe210098d9e36907ba1cc7724bdb2470e903068b`（共享 Shell 壁纸渲染）；`ee7217890227022e6eb936b925953aac91bc15f7`、`03da7263a3259678b82075234dea821409b81b66`（页面容器透明与 Bitmap 生命周期修复）。
- 当前最新观测的目标回归 Run：`41936402322`，commit `d1eabc29c87951208a9829f33db570f463809839`，当时状态 pending；还没有可确认的最终 job 结果。
- 验证边界：已核对 GitHub 代码、文档、测试脚本和 CI 接线；尚未取得成功 Actions 完成结果、Gradle build、安装运行、壁纸切换截图或华为/非华为真机验证。不得标记设备验收完成。


## 2026-11-05 — MainActivity 动态原生页面补齐统一 Skin 注入

- 复核发现一个真实覆盖缺口：此前 `FxNativeSkin.apply(this, pageContent)` 只在 `FxNativeTabActivity` 生效，而 FX 主 Activity 中的原生页面由 `MainActivity.mountNativeShell()` 动态构建，原先没有对已建成的页面树应用统一 Skin palette。
- 已在 `MainActivity.mountNativeShell(View pageContent)` 创建 Compose 壳前调用 `FxNativeSkin.apply(this, pageContent)`，确保 VPN/Ad/隐私/脚本/Hook/设置及其原生二级页面在挂载时将已存在的旧背景色/文字色转换成当前 Skin token；自定义告警色和未知背景仍由适配器保留。
- 新增回归断言：
  - `fx-global-ui-modes-regression.sh` 检查 MainActivity 与迁入 Activity 两个宿主都调用 Skin adapter。
  - `fx-wallpaper-regression.sh` 检查 MainActivity 的 Shell mount path 执行 Skin 注入，保证有壁纸时页面树背景透明逻辑不只覆盖来源 Activity。
- 提交：
  - MainActivity：`317879d3f2a38b6c96962986268d7bd9be9ca5e2`
  - 五模式回归：`40f950b58af77628892221ae4caa66e2d06cbf33`
  - 壁纸回归：`9a7cb4e3550f1a880148f1aab3df68509909a600`
- 验证限制：已完成 GitHub 源码回读和回归脚本/CI 接线核对；未在本执行环境运行 Android Gradle 编译或真机截图测试，不能标记五套 Skin 逐页视觉验收完成。


## 2026-11-05 — 原生页面动态控件的 Skin 实时补齐

- 复核 MainActivity.base() 发现页面壳先被挂载，标题/卡片/列表随后才逐步添加；单次 FxNativeSkin.apply() 会漏掉后创建的 UI 控件。因此将单次应用改为持续观察页面布局。
- FxNativeSkin.watch(Activity, View) 先立即转换现有视图，再为页面根 View 注册唯一的 ViewTreeObserver.OnGlobalLayoutListener。布局变化、异步列表加载和后续控件插入时重新应用已知旧色值到当前 Skin palette；替换只针对明确的旧背景/文字颜色，未知用户内容及警告颜色保持原样。
- MainActivity.mountNativeShell() 与 FxNativeTabActivity.setContentViewWithNativeTabs() 都使用 watch，覆盖 FX 主页面及迁入来源 Activity 的动态页面。
- 回归更新：fx-global-ui-modes-regression.sh 断言两个宿主都启用 watch，且 Skin adapter 使用全局布局观察器；fx-wallpaper-regression.sh 断言主页面/迁入页都使用同一实时 Skin 适配器。
- 本次实现仍属于 Android View 旧色值适配层；Harmony/iOS 的每个页面专属交互布局、复杂表格/图表/编辑器视觉尚需逐页设计与验收。此回归不能替代 Gradle 构建和真机截图。


## 2026-11-05 — 来源功能入口归并、子页 Tab 归属修正与旧品牌清理

### 已提交的源码改动
- MainActivity.buildNativePrivacyPage() 新增“安全防护中心”卡片，直接打开已迁入 FX APK 的安全防护总页。
- MainActivity.showHookHub() 新增 Hook 工具与调试入口：Frida 环境、DEX 类/方法选择、Activity 入口、文件/so、JSON、内存/数据库检查、运行事件监控、签名信息、崩溃诊断、系统扩展和 Hook 工具设置。应用列表页入口文案改为“Hook 授权中心与高级工具”。
- MainActivity.buildNativeScriptPage() 新增 Frida JavaScript 脚本库入口；脚本库继续使用 Script Tab（索引 3）。
- MainActivity.showSettings() 新增统一备份恢复入口；FxDiaBackupActivity 作为全局备份页归 Settings（索引 5），不再重复出现在 Hook 工具页。
- FxDiaWifiProxyActivity 归 VPN（索引 0）；Dia 的 Frida/DEX/Activity/文件/JSON/Inspector/监控/签名/系统扩展/工具设置归 Hook（索引 4）。
- 安全护盾主页面及 12 个 Shield 子页统一归隐私（索引 2），并由隐私页面直达安全防护中心。
- Ad 子页面标题和用户可见文案统一改为 FX Ad/Ad；DNS、Firewall、App Whitelist 不再显示“游龙广告插件”品牌名。安全防护中心与 Dia 相关用户页面也清理了旧来源版本标题/提示。
- 修订独立导航回归，覆盖 Settings 删除迁移应用、六 Tab 固定、Ad/Privacy/Hook/Script/VPN/Settings 页面入口和子页 selectedIndex、旧品牌文案清理。

### 相关提交
- MainActivity 增加 Privacy/Hook 入口：8ee77b4d3a36c7dbe2381c43da8b91e6be050061
- Settings 备份与 Script 页面脚本库归属：fde87fc57a9943a4b6e1180c6b08e1d8d1b8ec80
- Ad/Shield/Dia 主页面来源标题调整：77a53ce2df19abda42b45077c9eea23f339fe8b4、73c4d8999af1e691365ab2dcd191952792d2ba86、71863e52ba72d9bb67809cb786312a554df2ff08、8a3bbb9bd1411b81f16cc69411057248ede4509f、760678501cb0fa5b3095293b70cd12b68ce890ee
- Shield 子页 Tab 索引修正为 2，Dia 工具归 Hook 索引 4，脚本库索引 3，备份索引 5，系统代理索引 0（相关 Activity 变更已逐文件提交）。
- 导航归属回归：42c8849832ad84672c417d23e085a6010037493f、977b5df9226dea7450a9c569cc31767d6ac31a11、f319b82643143a0fce40191e830b0d73c5bef292、f519879cd77e7bd1785f75b2c097ad79acccff57。
- Ad 页面旧品牌清理：4fcbfd32f846b79533631e4134bbe807be562256、8cacde0fdf5aa4bd9eadba122d27b529cd191152、0ce877e321279681933a29533226f4b23e535d37、3996e5115c1a37531abd26f776d9dc73551d9b15、f5f1eda4806cfa133ca2ed0d684e8894b8ec50b8。
- DEX/框架提示文字清理：029efb1cfca70d4372562c06a0edcfe17f6256b1、e0638d6331fdddeebf7a6089b31f0f36d57de30f、a9df38ae83a273a257535e5e08fb6328bbac37fa。

### 验证状态与未完成项
- 源码和回归断言已回读；本轮新的 fx-unified-navigation-regression.sh 正在重新执行，未获得成功结论前不标记通过。
- 之前一次导航回归曾因旧版 GPS 选点测试文案断言失败；该页面现在已改为 Hook 标题/Hook Tab，新的测试版本已追加。
- Wallpaper 定向回归此前在 run 41978013330 的 host-regressions 中通过，日志明确输出：10.0.2-compatible wallpaper storage、bounded import decode、Classic WebUI transparency、shared native wallpaper renderer across migrated Ad/Shield/Dia Activities。
- 已通过的 Wallpaper 是静态源码/宿主回归，不是 Android Gradle 构建，也不是设备实际选图、恢复默认、跨进程重启和所有 Skin 壁纸截图验收。
- 尚未执行 Gradle testDebugUnitTest/assembleDebug、Android 安装、真机六 Tab × 五 Skin 截图、壁纸实机选图和导航服务无中断验证。
- 下一步：等定向回归完成，修复具体失败；继续五 Skin 内部控件 tokens/逐页覆盖，清理剩余来源品牌文案，并完成功能清单级映射/测试；不提前构建最终 APK 或 KernelSU ZIP。


## 2026-11-05 — Ad 主页补齐快捷入口并修正导航回归

- 最新 Ad 主页已加入 DNS 查询日志和分应用流量统计快捷入口；此前已有广告过滤控制中心、通用设置/备份恢复、每日摘要、防火墙、应用白名单入口。
- 用户要求所有来源功能都归入 FX 对应业务 Tab，不能再回到来源应用启动器。当前 Ad 主页入口均启动 FX APK 内部 Activity，统一高亮 Ad Tab；旧来源品牌只留在研发注释/类名中，不显示给用户。
- 定向测试 fx-unified-navigation-regression.sh 曾因一条静态断言将 Ad 页使用的 txt(...) helper 误写成 text(...) 而失败。检查页面真实代码确认是测试写错，不是 Ad 入口缺失；已把断言修正为 txt("Ad · 广告过滤控制中心")。
- 验证：GitHub Actions FX Targeted Host Regression Run 41980484108（commit 19197a4eaedd1dbb81737a53fcb03b7dcafc1304）已完成，job host-regressions = success；日志中 fx-unified-navigation-regression.sh 明确输出 PASS。此 Run 针对导航回归脚本变更，只能证明该导航检查通过，不代表 Android APK 已编译或真机验收。
- 较早 Run 41980356221 的失败已定位并修复；Run 41980429861 在旧提交上另有一项不相关的 VPN API Host 检查因未恢复 Release WebUI 资源而失败，不能视作当前 19197a4 的结果。应继续修正 targeted workflow：仅当 canonical WebUI 资源已从 Release 解包就绪时才执行依赖该资源的 Host 检查，否则明确 SKIP，并由完整 build workflow 在 staging 后验证。
- 当前继续开发重点：五种 Skin 在所有页面控件中的细节一致性、Wallpaper 在 ClassicWebCompat 下的完整背景透出、Ad/DNS/Firewall/App stats 等旧功能的逐项业务整合。尚未完成 Gradle 编译、安装运行或真机视觉验收。


## 2026-11-05 — Ad/VPN/Privacy 页面归属继续落实

### Ad 入口与来源身份清理
- `MainActivity.buildNativeHostsPage()`（第二 Tab 的可见名称固定为 Ad）：
  - 删除主 Ad 页说明中的来源应用品牌文案，改为 FX Ad 统一管理说明。
  - 新增 DNS 查询日志、分应用流量统计直达入口。
  - 已存在的广告过滤控制中心、通用设置/备份、每日摘要、防火墙、应用白名单入口继续保留。
- Ad 原生子页面统一名称/返回：应用统计、应用白名单、DNS 查询日志、防火墙均显示 Ad 内部页面名、返回 Ad、selected index=1；DNS 日志里的返回说明也改为 Ad 路径。
- Hook JSON 操作页示例、剪贴板和导出文件名使用 FX Hook JSON，不再显示 FX Dia JSON。
- 回归脚本 `fx-unified-navigation-regression.sh` 现在校验 Ad 主页直达页面、无来源插件品牌、DNS/App Stats 子页的 Ad 标题与返回索引，以及 Hook JSON 的归属。

### VPN 分应用路由整合
- 原有 `showImportedVpnAppManager()` 是真实可运行的分应用 VPN 配置编辑器，但此前被旧来源 Ad“应用管理”流程隐藏，且错误使用 Settings selected index=5。
- 已在 VPN 首页“应用分流”分组增加“管理分应用 VPN 路由”入口。
- 子页标题改为 `VPN · 分应用路由`，selected index=0，返回按钮为“返回 VPN 控制中心”，不再回到旧 Ad/迁移应用页面。
- 新增 Activity 状态保存/恢复键 `fx_native_vpn_app_manager_visible`；系统 Back 回到 VPN 控制中心，底部切换其他 Tab 会退出此子页。
- 该路由名单仍与 Ad 防火墙名单、Hook 目标作用域分离；没有启动第二个 VpnService，继续使用 FX 唯一 VPN/TUN 路径。

### Privacy 子页面命名
- 每日安全总结、救援中心的页内返回按钮统一为“返回隐私首页”/“返回隐私防护中心”；安全中心悬浮救援入口说明改为“返回隐私防护中心”。
- 对应 Shield regression 同步断言 UI 文案。旧测试曾因来源页文案更名未同步而失败，已更新检查文本。

### 相关提交
- Ad 主页直达 DNS/统计并清理来源说明：`4a93ff5603dc283d091c07d89ece919dc4c83ba2`
- Ad 主页导航回归：`2d911d32f8431382e6b31c6c60d548dc51dd26ae`
- Ad 子页来源标题/返回：`f8ba07c3fa03dc39c25dac99ed827d85881c4473`、`dd7608a24d57188f8f01f732981008aedb7b4557`、`8df7b605c688f9bf4e24abe3323a10d555c28047`、`05f5fbc1af2b0f103e0365f922e93f6690b61661`
- DNS 说明文案：`7710350a4f866ea44ae1b70e0102204f3f9cbd76`
- Hook JSON 示例：`29e4712b1738989ad7d7d09531bb08e9326ac59f`；回归覆盖：`c71201bb1f1f7d26333e1310e26af46066840061`、`3551883e15763474c9145100b990889d4cecfbf8`
- VPN 分应用路由入口/子页状态：`0cfc5136aee3492196e15096cd4080e129cd58c8`；路由归属回归：`7793cb666281bf6d7119359eafeefd389b34de50`
- Privacy 返回标签：`b51c1f69a5e0e30bce1b1053b62fdcb6e505e767`、`458ca94e9ef4ca8530354fd4cb9bc5cfb7c289a1`、`5a9540a3c613338018b58f64ac507039e3fb35e9`；回归：`995b185986b7a217ab58e7c2fe724d6ab6773405`、`1d4cf8cca47d09cd5071ddd315638e1b2146d6f4`

### 验证状态
- Targeted Host 成功记录：run `41980599330`，HEAD `7793cb666281bf6d7119359eafeefd389b34de50`，日志明确显示 `fx-unified-navigation-regression.sh` PASS。该 run 验证了当时已提交的六 Tab、Ad/Hook/Script/Settings 页面归属和 VPN 分应用路由断言。
- 之后 Privacy 返回文案和对应回归断言又有提交；当前 branch HEAD 需要等待最新 Targeted Host run 完成后再更新本节的最新验证结论。
- 曾观察到的失败已按具体原因处理：Rescue footer 标签断言未同步、FxNativeSkin 变更缺少 Targeted Host mapping；不能把这些失败隐藏或折算为通过。
- 这仍是源码/Host 静态与主机回归，不是 Gradle `testDebugUnitTest`、APK `assembleDebug`、安装或真机测试。五种 Skin 的逐页设计、完整功能迁移、系统级 VPN 共存、防泄漏、证书无感等仍有大量待办。



## 2026-11-05 — 修复全局 Skin 的 Switch/CompoundButton 分派顺序

- `FxNativeSkin.transformKnownLegacyTokens()` 原来先匹配 `Button`，再匹配 `Switch` 和 `CompoundButton`。Switch/CheckBox/RadioButton 属于复合按钮类型，可能先命中通用 Button 分支，造成专用 tint 适配器不可达。
- 已改为 Switch → CompoundButton → Button：Switch 保留 Thumb/Track 颜色，复选/单选控件使用 `setButtonTintList`，普通按钮仍走独立的背景/Ripple 主题。
- `fx-global-ui-modes-regression.sh` 新增分支顺序与专用 tint 可达性检查。
- 源码提交、回归提交：稍后写入实际 SHA；尚未完成 Gradle 编译/真机控件验收。

- 提交：FxNativeSkin `95212688f0e75c760ed32ee899c32e2b7a4be64e`；回归脚本 `4bcbe3f51c81f2b82493805e14af4afc18873a93`。


## 2026-11-05 — 五种 Skin 的原生控件令牌扩展与回归通过

### 本批实际实现
- 扩展 `FxNativeSkin.java` 的五组 Palette：新增按钮背景/边框/主题强调色、开关未选中轨道色和模式圆角令牌。
- 原生 `Button` 现在按模式生成带 RippleDrawable 的动作表面，统一 AllCaps、触控高度、内边距、文字尺寸、强调色与圆角；液态模式保留轻微浮起，其余模式不额外增加 elevation。
- 原生 `Switch` 使用各模式的 thumb/track 状态色；`CheckBox`/`RadioButton` 使用对应模式的 button tint。
- 特殊控件派发顺序已修正：先识别 Switch 与 CompoundButton，再处理普通 Button，避免继承关系令开关误进通用按钮渲染分支。
- 保留 Switch 原有行/卡片背景，不以透明背景覆盖其容器；Button/Switch 样式按控件弱引用登记，避免每次布局回调重复重建 RippleDrawable。
- 继续使用共享动态布局适配器覆盖 MainActivity 与所有接入 `FxNativeTabActivity` 的迁入页面。

### 相关提交
- `df2cb7dbed4597099d1bd890c7bc81f98e9c51fe`：五模式 Button/Switch 首批 Skin
- `877a8053f3df46eae2156d1eaaa0708bc816cdfd`：保留 Switch 行背景并接入 Radio/Choice 控件
- `215b129df3a774e80ea34b74342db22da15391a8`：新增按钮/开关/选项控件回归断言
- `95212688f0e75c760ed32ee899c32e2b7a4be64e`：修正 Switch/CompoundButton 与 Button 的继承派发顺序
- `4bcbe3f51c81f2b82493805e14af4afc18873a93`：验证控件派发顺序的回归断言

### 验证
- GitHub Actions Host 回归 Run `41981291404`（HEAD `4bcbe3f51c81f2b82493805e14af4afc18873a93`）成功。
- 日志确认：Switch 与 CheckBox/RadioButton 令牌派发顺序检查通过；壁纸回归确认 10.0.2 存储格式、限幅解码、Classic WebUI 透明背景，以及 Ad/Shield/Dia 迁入页面共用壁纸层。
- Host lane 明确 SKIP 需要从 Release 恢复的完整 WebUI/module 资源检查；这不等于失败，也不等于这些资源已在本 lane 编译。
- 尚未执行 Gradle `testDebugUnitTest`/`assembleDebug`、APK 安装、真机逐页截图、按钮触控测试或 VPN/DNS/Hook/脚本服务无中断实测。不能称为 APK 构建通过或真机验收完成。

### 下一批
- 继续五 Skin 页面级适配，重点检查表单、列表、弹窗、RadioGroup、编辑器、统计/扫描页面，不只停留在底部导航和通用控件。
- 继续核对来源功能映射：旧来源名称不得回到用户主导航；功能必须真实归到 Ad/VPN/隐私/脚本/Hook。


## 2026-11-05 — 固定 GKD-XA v1.4.8 上游源码并建立融合门禁

### 来源核验
- 上游仓库：84593320z/GKD-XA。
- Release：v1.4.8，发布时间 2026-10-31。
- Annotated tag v1.4.8 解析至 commit：8a6ce935da11671dac7e1a7595416ec99ee07436。
- 官方 Release APK SHA-256：fb03dea5c206c063deb9f2a2031c7d3ca9e3b014052f9a91916af4e6c689e6fa（本批锁定源码，不以 APK 替代源码）。
- 许可证：GPL-3.0。必须保留版权/许可证/修改记录和组合分发源代码义务。

### FX GitHub 落地
- 新增 .gitmodules：vendor/GKD-XA → https://github.com/84593320z/GKD-XA.git。
- 新增 Git submodule gitlink：vendor/GKD-XA 固定至 8a6ce935da11671dac7e1a7595416ec99ee07436。
- 新增 docs/FX_GKD_XA_1.4.8_INTEGRATION_PLAN.md：记录上游模块、权限/服务边界、GPL 义务、构建冲突、FX Tab 归属和验收门槛。
- 新增 scripts/tests/fx-gkd-xa-source-lock-regression.sh：验证 submodule URL、gitlink SHA 和未完成状态声明。
- 在 .github/workflows/fx-targeted-regression.yml 增加对 .gitmodules、vendor/GKD-XA、融合计划或锁定脚本变更的定向回归。

### 源码审计关键发现
- GKD-XA 不是一个普通 Accessibility 开关。它包含 gkd-app、gkd-aidl、gkd-db、gkd-hidden-api、gkd-selector 五个模块。
- gkd-app 自带 Application、MainActivity/AppRoot/ViewModel、Manifest 服务/Receiver/Provider/Tile/Job 和运行时初始化；不能把整个 app 模块当普通 Activity 直接复制进 FX。
- FX 当前：AGP 9.1.1、Kotlin 2.4.21、Java/JVM 17、compileSdk37/minSdk28。GKD-XA v1.4.8：AGP 9.4.1、Kotlin 2.4.20、Java/JVM 21、compileSdk37/minSdk26。必须先解决 Gradle/JDK 兼容，不能跳过 spike。
- GKD-XA Accessibility runtime 与 FX 已有 Root/LSPosed/Accessibility 存在多套运行时风险。必须设计单一事件/动作 orchestrator，防止重复点击、重复截图和后台耗电。
- GKD 主要功能映射：应用规则/选择器/自动化/快照 → Hook；规则脚本/AI 编辑 → 脚本；明确广告跳过规则才进入 Ad；全局偏好/权限/备份 → 设置。
- 当前 FX 源码没有 GKD-XA runtime 文件，只有 submodule 指针；本次不声称完整功能已经迁入。

### 验证状态
- 已通过 GitHub 回读确认 .gitmodules、gitlink、实施计划和 source-lock regression 已存在；submodule SHA 精确匹配 v1.4.8。
- 已将 source-lock regression 接入 targeted Host workflow。
- 尚未看到本提交对应的最新 Actions 成功结果；尚未做 Gradle 兼容 spike、单 APK 构建、运行时移植、数据库迁移、无障碍合并或真机验证。
- 下一批应执行 Gradle/Manifest compatibility spike，先确定 JDK/AGP/Kotlin 构建图，再开始迁入 selector/订阅模块。不能把 GKD-XA 的 APK release asset 放进 FX，不能开第二 launcher。

## 2026-11-05 — 五 Skin 文字 token 映射扩展与语义颜色保护

- `FxNativeSkin.replacementText()` 已将 MainActivity 高频旧色值分类映射到全局 palette：主文本、次级说明/元数据、蓝色链接/选中状态。
- 对应主页面来源颜色包括 `0xff697681`、`0xff536170`、`0xff526170`、`0xff263443`、`0xff155a9c` 等。
- 负面/警告/成功颜色（红色、橙色、绿色）保持语义色，不被改写为普通灰色或当前 Skin accent。
- `fx-global-ui-modes-regression.sh` 覆盖颜色映射、语义色保护以及 Switch/CompoundButton dispatch 顺序，并会联动执行 Wallpaper 与相邻 VPN 静态检查。
- 代码提交：`0b810c724653e169d6fe05976fa8a597ed28b528`；回归扩展：`c8a025068562c842a8c7d74a0e92435110a25ec1`、`2fdbb1ec252e17025d1b528574a7652111c17ad5`。
- 这些是代码和 Host 静态检查，不代表 Gradle/设备真机通过。最新 Targeted Host run 需等当前脚本提交的 Actions 结果后再更新验证结论。


## 2026-11-05 — 壁纸缩放算法边界单测与 Host 回归确认

- 扩展 `adhook/app/src/test/java/de/privacyguard/adhook/FxWallpaperStoreTest.kt`：
  - 增加小图不放大断言。
  - 对宽度为 0、高度为 0、maxEdge 为 0 的输入逐项验证抛出 IllegalArgumentException。
  - 验证大图采样值始终为正数且为 2 的幂，避免 BitmapFactory 非法 sample size。
- 扩展 `scripts/tests/fx-wallpaper-regression.sh`：要求上述单测源文件存在，并检查测试方法，防止只保留实现而丢失缩放边界测试。
- 主要提交：`50788668069fe9e2b8dbf7cc685c7f3bcab9727e`（单测）；`ac623f55ee7977d43c3f19b2ac34fbe1f3df0d8e`（静态回归门禁）。
- Host 回归：GitHub Actions run `41981558626`，最新相关提交 `c8a025068562c842a8c7d74a0e92435110a25ec1`，job `host-regressions` 结果 success。日志明确输出五模式控件分派/文本 token PASS，以及 `PASS: 10.0.2-compatible wallpaper storage, bounded import decode, Classic WebUI transparency, and shared native wallpaper renderer across migrated Ad/Shield/Dia Activities.`
- 该 run 是主机静态/定向回归，不包含 Android Gradle 单元测试执行、APK assemble、安装或真机壁纸截图；新增 FxWallpaperStoreTest 仍需在后续 Gradle testDebugUnitTest lane 执行。

### 下一批优先工作
1. 继续五 Skin 逐页覆盖：检查 imported Activity 和 MainActivity 动态新增的控件，确保不覆盖警告/错误语义色、不吞掉自定义 Drawable、不重复挂载 layout listener。
2. 补齐 APK 10.0.2 旧界面页面映射与 wallpaper 行为实机截图验收；ClassicWebCompat 的网页资源只在完整 Release staging lane 验证。
3. 对 Ad、VPN、隐私、Hook、脚本进行来源功能逐项映射；已有入口不代表该页所有旧功能都已接入真实运行时。

## 2026-11-05 — 保留语义动作按钮颜色，并修复 Host-only DNS 回归脚本边界

### 五 Skin 语义按钮保护
- FxNativeSkin.applyButtonSkin() 现在先检测按钮当前文字色/纯色背景是否属于明确语义色，再决定是否套用普通主题按钮样式。
- 危险/错误红色、警告/风险橙色、成功/可信绿色按钮会跳过通用 accent 重绘，避免主题切换把红色“删除/危险”操作染成蓝色普通按钮。
- 新增 fx-global-ui-modes-regression.sh 静态断言，确保语义色 guard 在通用按钮缓存/重绘前执行，并覆盖红/橙/绿颜色集合。
- 代码与回归提交：7c84ef556f010fc04f337e449310d1aefcd52bf6、386e27ad491542166e84c5663cd3f4b9e0a8362b。
- Actions run 41981743883 的 host-regressions = success。

### 修复 DNS summary Host-only 测试参数错误
- 原 fx-yulong-ad-dns-summary-regression.sh 第 81 行直接读取 $1，但 Targeted Host workflow 无参数调用该脚本，触发 set -u 的 unbound variable。
- 修复：改用 ${1:-$ROOT/fx-module}；Host-only 且未传模块路径、Release module 文件不在 checkout 时明确输出 SKIP 并退出成功；完整 package lane 显式传入 fx-module 时仍强制检查 AdGuard Home lifecycle script 和 anti-fraud list，不降低包阶段验收。
- 提交：8768f4af9012f0ef384b95a67674dd8740bd0f89。
- Actions run 41981818472 的 host-regressions = success；日志明确出现 Host-only 条件下的模块依赖 SKIP，不再有 $1 未定义错误。

### 验证边界
- 本批通过的是 Host 静态回归：语义按钮 guard、五 Skin、壁纸共享渲染、Ad/Hook/VPN/Script 路由测试均按对应 workflow 条件执行；缺少 Release module staging 的模块运行时检查明确 SKIP。
- 未执行 Gradle testDebugUnitTest、assembleDebug、安装或真机验收；FxWallpaperStoreTest 源码已补充，但需在后续 Gradle lane 执行。


## 2026-11-05 — 10.0.2 参考 APK 原件确认与证据边界

- 从资料库根目录找到并读取 `游龙工具_10.0.2.apk`，原件大小 92,008,250 bytes，SHA-256 `c2d7bb1b8e688232888a927d5b81affcf5c28832f9e6420e27e800e54f5fee75`。
- ZIP 中有 classes.dex、resources.arsc、AndroidManifest.xml；assets 包含 bizhi.png、index.java、apk.tar.xz 等。index.java/bizhi.png 常规识别为非明文数据，不能直接复制为 webroot HTML 或 PNG。
- DEX 字符串/类名证据包含 `com.youlong.gj.MiuixScreenKt`、`MiuixUiRoot`、`MiuixWallpaperDialog`；`assets/apk.tar.xz` 内嵌 APK 名称为 hd.apk、ylads.apk、cj.apk。
- 已有 Wallpaper 复刻契约：壁纸弹窗“壁纸随心换”，上传本地图片、恢复默认；私有文件、最长边 1920、JPEG 85、prefs `native_wallpaper_prefs/wallpaper_path`。FX 已有对应 Store 与全局壁纸壳。
- 参考 APK 哈希、ZIP 目录和 DEX 结构已经核验；完整 JADX 反编译/资产解密和原版逐页截图仍未完成。ClassicWebCompat 不能声称逐像素复制 10.0.2。
- 本次资料更新提交：产品审计 `84a6a46f86db`；独立 AI 提示词同步 `d8487dd663de`。


## 2026-11-05 — 统一导航纠偏：移除来源应用目录，Ad 作为唯一第二 Tab

- 产品入口固定为 VPN、Ad、隐私、脚本、Hook、设置（索引 0–5）；第二 Tab 只显示 Ad，Hosts 只是 Ad 内部页面。
- MainActivity 已删除旧 migration hub 的状态字段、目录/分类/待迁移页/返回栈方法，以及 DEX picker 返回旧 Dia 分类树的逻辑；DEX picker 回归统一 Hook 目标/应用列表。提交：6d4bda992cd4172243509db69bcd8b6e3acf0dd2。
- Web 路由将 pageAd 设为规范 ID，pageHosts 仅作历史 DOM alias；已更新两个导航回归脚本，检查来源目录不存在且业务功能仍在 Ad/隐私/Hook/脚本中。提交：9423cd6cece752e3fc8f32e452a2667f9e758947、c08c17c6eecfc826c05fc286db8a33a5262da60c。
- 新建跨 AI 完整自主接管提示词 docs/FX_1.0.0_AUTONOMOUS_CROSS_AI_HANDOFF_PROMPT.md；更新产品总方案，修正 Domain 不再包含 Migration 产品域、P2 定义为开发期来源功能归并，并写入完成边界。相关提交：82248bec763b2f7f6a842ce411b3bbcf9eedb4fc、9d545c19dd0fca8106c41abd226a92957a85a739。
- 当前源码状态：MainActivity 中旧 migration hub 符号已查无；Settings 代码段无迁移应用入口；pageAd 路由与 pageHosts 兼容映射存在。导航改动尚待执行对应 Host 回归并查看 Actions 结果。
- 这不代表全部功能已迁入。Ad 多层执行、VPN 内核级代理与第三方 VPN 共存、防泄漏、MITM/证书、全部隐私护盾、Dia/GKD 运行时、代理脚本 API 和浏览器扩展仍需逐项实现与验证。五 Skin 页面级覆盖、10.0.2 逐页 UI 复刻也未全部验收。
- 当前可报告验证级别：GitHub 源码回读与静态文本断言；未在本批执行 Gradle 构建、APK 安装、UI 自动化或真机验收。不得发最终 APK/KernelSU ZIP。
- 下一步：回读最新导航源码与回归脚本、运行针对性 Host 回归；随后选择 Ad 完整业务链或 VPN Root 数据面风险项继续实际实现。


## 2026-11-05 — 移除来源应用导航、统一 Ad Tab 命名并修正续接提示词

### 本批源码变更
- `MainActivity.java`：移除旧来源应用的多级导航状态与路由（`migrationSuite`、`migrationCategory`、`migrationPage`、`migrationLevel`、`migrationChildActive`、`showImportedSuite*`、`restoreMigrationNavigation` 等）；来源功能直接进入 FX 的 Ad/VPN/隐私/脚本/Hook 对应页面。
- 统一方法名：`showImportedVpnAppManager()` → `showNativeVpnAppManager()`；`handleImportedNativeTabIntent()` → `handleNativeTabIntent()`。VPN 分应用路由仍保留在 VPN 业务域，不再使用来源导入命名。
- Native Shell 六个 Tab 固定为 VPN、Ad、隐私、脚本、Hook、设置。ClassicWebCompat 的主路由使用 `pageAd`；旧 `pageHosts` 仅作为 DOM 兼容别名，导航标题统一显示 `Ad`，中文标题不再显示“广告”或“Ad/Hosts”。
- Settings 保留全局外观/壁纸、备份恢复、系统授权/诊断、许可与关于；不再出现“迁移应用”入口。

### 回归和文档
- 更新 `scripts/tests/fx-imported-suite-back-navigation-regression.sh`：检查来源应用导航状态/方法不存在，并确认 Ad、隐私、Hook、脚本的功能入口仍在各自业务域。
- 更新 `scripts/tests/fx-unified-navigation-regression.sh`：修复已删除迁移页边界引用，改用 `showNativeVpnAppManager`、`addNativeSettingsCategory`、`showNativeWallpaperDialog` 和 `handleNativeTabIntent`；增加 ClassicWebCompat 的 Ad-only 标题断言。
- 更新 `docs/FX_1.0.0_MASTER_AI_TAKEOVER_PROMPT.md`：加入当前源码纠偏状态和后续直接开工任务，明确禁止把迁移应用入口加回去。
- 更新 `docs/FX_1.0.0_PRODUCT_RESTRUCTURE_AND_AI_HANDOFF.md` 第 11/12 节已明确的规范继续作为产品基线：唯一六 Tab、Ad-only、来源功能按业务域归属、Settings 仅系统级配置。

### 提交记录
- MainActivity 命名与 Ad 标题：`16280c6d624849c3977803e7a3fbe29bd342d983`
- Unified navigation regression 迁移边界与调用名：`033122764b727b606ca7dbf72a67fc81cb955bf7`
- ClassicWebCompat Ad-only 标题断言：`95a64aa6ae36c04affff2fa77a1cfe7007b4439e`
- 本节同步提交时的 HEAD 以 GitHub 最新分支 ref 为准；下一窗口必须重新读取，不能复用上述历史 HEAD。

### 验证等级与边界
- 已完成 GitHub 源码回读和静态内容核对：旧导航符号缺失、六 Tab 标签保持、ClassicWebCompat 的 Ad 标题与兼容别名关系明确、VPN 路由页面调用名一致。
- 当前轮次未在 Android SDK/Gradle 环境实际执行上述 shell regression；未执行 Gradle 单测、APK 构建、安装、UI 自动化或真机验收。不能将源码回读标为测试通过。
- 尚未证明所有来源应用功能均已完整迁入。该批仅清理导航/命名和回归断言；业务功能按各领域矩阵继续推进，不能用删除来源入口冒充功能全部完成。

### 下一批直接实施
1. 五 Skin × 六 Tab 的真实页面组件覆盖：从表单、列表、弹窗、编辑器、扫描/统计页中选择仍未适配的页面组，为 Harmony/Cupertino 补独立 Tokens/Renderer，不只换色。
2. 按 Ad / VPN / 隐私 / Hook / 脚本检查对应原来源功能页是否真实接到 FX Repository/Service；优先修复无后端按钮、虚假状态和缺失权限。
3. 针对本批导航脚本做一次定向执行；若 Actions 自动运行，读取结果并严格区分 Host 静态回归、Gradle、安装和真机层级。



## 2026-11-05 — GKD 本地规则运行链首批打通（仍非全量迁移）

- 将 pinned GKD-XA v1.4.8 上游 selector/parser 接入 FX 自有节点模型，新增本地规则存储、受限 Accessibility Snapshot、本地选择器匹配和 Click-only 规则执行器。
- 新增 Hook 内部页面 `FxGkdAutomationActivity`，由 Hook Tab 的“GKD 选择器自动化”卡片进入；支持用户创建目标应用+选择器+冷却规则、逐条启停/删除和独立总开关。
- 复用 FX 唯一的 `FxAccessibilityService`：默认只订阅窗口变化；总开关启用且存在目标规则时，动态加入 window-content-changed/view-scrolled。不会添加 GKD 第二服务、第二 Launcher 或第二 APK。
- 隐私/安全门：总开关默认关闭；包名逐应用白名单；普通用户应用校验；root window 包名精确匹配；Snapshot 上限 700 节点/32 深度/每节点 80 子节点/每文本 256 字；不读取 password/editable 文本或描述，不截图、不上传、不记录页面文本；仅允许可见且可点击的非密码/非编辑节点 ACTION_CLICK；点击前再次核验服务连接、总开关、规则启用和前台包名；单线程任务门与 250ms 全局扫描间隔、每规则 1–60 秒冷却。
- 修复规则列表重绘错误：保留前 6 个固定控件（两张说明卡、状态卡、系统授权按钮、总开关、添加规则按钮），只替换规则列表区域。
- 新增静态回归 `scripts/tests/fx-gkd-automation-regression.sh`，并接入 Host lane 与 GKD App compile lane；GKD compile workflow 改为运行正确的 `FxGkdSelectorEngineTest`。
- 相关提交：`35999243035c5f2de92604b4166d9c61a57b00e0`、`3478def751630ad2d0e7c2313c4577a340492ee8`、`5e3db8b41092820f516525c6bf66b72bd91b731d`、`d222597890770d1ad3263a70cf585245334f3771`、`7e708a2714644d31c0103d2d22356cbf2538ad5c`、`7c372a215eff741116f03174697cea9d7f3b2534`、`a786a06ce9c628e46c35cafae1f1ec65b989f469`、`a65b06f92b634289b10f6f09687dd877e4fed869`、`4a8ad38b05dd71d16c8c1bbd571328e14f15ba9e`、`1757c40d2c2bb9fa89f9848c48ce58e713739670`、`24075c97a954e086fd00f0cd0a409ab9d0a9210a`、`783e015636ab4848b958bfc4871b76c439f6d2df`、`cbbbca432a88ae28c5f0544f1e1a082869f4ac5b`、`f6d14fdd81df49ea4953c7353ad8e0c34d1068a2`、`ae398aa120e6acd07cc6deac6fd240ddc9fb1402`。
- 当前 GKD CI run `41983507306` 在上游 selector JVM 测试阶段进行；尚无本轮 App Java/Kotlin compile、GKD unit test 的最终结果。本轮未声称 Gradle 构建已通过、未声称真机验证。
- 未完成：订阅/规则组/排除项/导入导出/触发历史与日志/快照与 AI/数据库迁移/备份恢复/Shizuku-AIDL/开机通知 Tile 全生命周期；此为第一期本地手动规则 Click 试点，不等于 GKD 全功能迁移。

### 后续优先顺序
1. 读取 Actions run `41983507306` 的最新结果和失败日志；先修真正的编译/单测失败。
2. 实机验证 Android 无障碍授权、窗口树包名边界、动作冷却、前台切换取消、开关关闭立即停用和耗电/内存。
3. 增加事件去重/每事件预算/动作结果状态，再做规则组/排除项和订阅存储。
4. 再迁移 GKD snapshot/history/AI providers、数据备份和特权/后台生命周期。


## 2026-11-05 — 整体重构纠偏第二批：删除来源导航残留并统一跨 AI 执行指令

### 本批实际改动

- adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java
  - 将分应用 VPN 页面方法统一命名为 showNativeVpnAppManager()，它是 VPN（Tab 0）的 FX 内部页面，不再使用来源 APK 命名。
  - 将主 Tab Intent 路由入口统一命名为 handleNativeTabIntent()。
  - 清理 Hook 入口注释和 Settings 导航状态注释，明确 Hook 目标栈和全局设置是 FX 自身导航，不保留旧来源套件返回链。
  - 保留真实 DEX 方法选择后进入 FX Hook 目标编辑器的路径；不再维护 Dia 来源分类返回栈。
- scripts/tests/fx-imported-suite-back-navigation-regression.sh
  - 将回归目标改为确认来源应用导航状态/方法不存在。
  - 检查 DEX 选择回到 FX Hook 目标页。
  - 新增 Hook 目标、VPN 子页、Settings 的 Android Back 返回优先级断言；修复新增 Python 检查器的换行匹配。
- scripts/tests/fx-unified-navigation-regression.sh
  - 已核对最新版本：VPN 子页检查以 showNativeVpnAppManager() 为入口，函数边界指向 addNativeSettingsCategory()；Settings 检查以 showNativeWallpaperDialog() 作为边界；Activity 恢复路径使用 handleNativeTabIntent()。
  - 该脚本还检查六 Tab 标签、第二 Tab Ad、旧 pageHosts 仅作 Web DOM 兼容别名、Settings 不含来源应用菜单。
- 执行提示词：
  - docs/FX_1.0.0_UI优先自主推进与中断续接执行总指令.md 已将阶段 B 重写为“来源能力拆解与 FX 业务域归并”，六 Tab 第二项固定为 Ad，设置不再有来源应用独立入口。
  - docs/FX_1.0.0_UI优先提速与自主开工提示词.md 已替换旧的三来源应用独立三级导航要求，并明确指向主产品规格中的五 Skin 与 10.0.2 壁纸契约。
  - 跨 AI 的主执行提示词为 docs/FX_1.0.0_AUTONOMOUS_CROSS_AI_HANDOFF_PROMPT.md；它规定单 APK、六 Tab、五 Skin、完整功能大纲和禁止来源应用导航。
  - 主产品规格 docs/FX_1.0.0_PRODUCT_RESTRUCTURE_AND_AI_HANDOFF.md 已明确 Domain 只包含 Ad/VPN/Privacy/Hook/Script/Settings；Schema/配置迁移只属于 Data 层内部能力，不形成用户可见 Migration 模块。

### GitHub 提交

- MainActivity 导航方法命名归一：16280c6d624849c3977803e7a3fbe29bd342d983
- MainActivity Settings/Hook 导航注释纠正：399b91e62266a8ade1b3ff558a6c227fe38559f3
- 导航返回栈回归扩展：579965988651c3a4c1ad60210a6a4d8b853a1785
- 修复返回栈回归脚本的 Python 方法边界解析：262469f87ed92657518c03655cfb9de7491fc0a9
- UI 优先自主推进总指令纠偏：169cd3dee5deb65ccc8b0ce93d454a0f9273202e
- UI 优先提速/自主开工提示词纠偏：1ac0ca919dde4e944c93aa99ad4c72042d4f07d1

### 验证等级与边界

- 已完成：GitHub 分支文件回读；确认 MainActivity.java 不再含 migrationSuite/migrationCategory/showImportedSuite 等来源导航代码；确认主导航标签为 VPN、Ad、隐私、脚本、Hook、设置；确认 Settings 页面代码没有来源应用入口。
- 已完成：回读两份 UI 执行档、跨 AI 主提示词和产品规格，确认旧 Ad/Hosts Tab 与“设置下迁移应用”执行要求被纠正。
- 新增 fx-imported-suite-back-navigation-regression.sh 已修复源码解析器，但本轮尚未取得该脚本实际执行成功的 CI 结果。
- 关联 MainActivity 提交的 Targeted Host runs 41983590657 与 41983370463 状态为 cancelled（并发提交触发 concurrency cancel），不计为通过；未宣称 Actions 通过。
- 未执行 Android Gradle testDebugUnitTest / assembleDebug、APK 安装或真机视觉/返回手势测试。源码和文档回读不是设备验收。

### 下一步直接开工

1. 在一次有 MainActivity 变更的定向 Host 节点上运行 fx-unified-navigation-regression.sh 和 fx-imported-suite-back-navigation-regression.sh，读取失败日志修复真实问题。
2. 继续五 Skin 的页面级原生控件/renderer 适配；特别检查 Huawei 与 Cupertino 页面的列表、表单、开关、弹窗、Sheet、键盘和无障碍，而不是只检查底栏。
3. 按业务域推进 Ad/VPN/隐私/Hook/脚本真实功能闭环；来源 APK 页面树只作功能差异审计，不得重新变成用户导航。


## 2026-11-05 — 统一跨 AI 总提示词入口并归档 UI 导航纠偏

### 本批实际变更
- 将完整 UI 重构和功能大纲整合进正式跨 AI 提示词：`docs/FX_1.0.0_AUTONOMOUS_CROSS_AI_HANDOFF_PROMPT.md`。该文件现在是唯一可直接交给其他 AI 的执行提示词，覆盖固定六 Tab、Ad-only、设置页职责、五种 Skin、10.0.2 壁纸、多层 Ad、VPN/Root 内核级代理共存、防泄漏、MITM/CA、隐私/安全护盾、Dia/GKD Hook、脚本与浏览器扩展、版权/许可证、分阶段交付和验证分级。
- 在正式提示词补充 GKD-XA v1.4.8 的历史审计锁定依据（`8a6ce935da11671dac7e1a7595416ec99ee07436`、GPL-3.0）与 Gradle/JDK/Kotlin/Manifest/Room/AIDL/Accessibility 兼容 spike 要求；要求新接手 AI 继续回读最新 submodule，不把历史 SHA 当最新。
- 补充 ClassicWebCompat WebView 安全边界：只使用可信本地 WebViewAssetLoader，不开放任意远程页面或不必要 JavaScript bridge。
- 产品规格 `docs/FX_1.0.0_PRODUCT_RESTRUCTURE_AND_AI_HANDOFF.md` 顶部唯一提示词指针及第 9 节已改为指向正式 AUTONOMOUS 文件；第 9 节不再复制第二份长提示词。
- 删除重复的 `docs/FX_1.0.0_MASTER_AI_HANDOFF_PROMPT.md`，避免两份提示词争夺“唯一正式版”。
- 同一批 UI 源码纠偏已把 Ad 主页面方法命名为 `buildNativeAdPage()`，导航回归断言同步；前序记录见提交 `ac5003a6dfe36705d04b9844164318f80625a251`、`58f1579cd86d2e006aace2dfb28ac5531589aaaf`。

### GitHub 提交
- 统一完整提示词写入正式文件：`9e1dd2726967e05b791c1d1f856021b186c295ad`
- 产品规格唯一入口与旧提示词副本清理：`205e4c3cca7fba6a4ad4a2d7754d4f007e6552a9`
- 删除重复 MASTER 提示词：`69728293f03e436151b40f548eb23140f09a6bf4`

### 回读核验
- 已回读确认正式提示词包含六 Tab 固定结构、Ad/Hosts 命名边界、禁止设置“迁移应用”、壁纸原版契约、Ad 五层、VPN 共存/防泄漏、`who.1ms.dog`、GKD-XA 锁定与许可证要求。
- 已回读确认产品规格指向正式 AUTONOMOUS 提示词，第 9 节不再维护第二份提示词；重复 MASTER 路径已删除。
- 当前分支 HEAD 在本次状态写入前观测为 `9dbe40882cee7829eb03a0c226fb21a42cdf6baa`；分支有其他并发提交，下一轮必须重新读取实时 HEAD。

### 验证等级与限制
- 已完成 GitHub Contents API 写入/回读和源码静态内容检查。
- 当前 Targeted Host workflow run `41984171926`（run 499）在最后一次读取时为 `in_progress`，其 HEAD 为 `ce5106308727cd4b09c2c5c98ac5cdaf20094b90`；不能据此声称本批回归通过。
- 同一并发窗口内部分旧 run 被 GitHub Actions concurrency cancel，取消不计为通过。应读取最新成功/失败 run 和具体 job 日志，不要重复手动触发整套 Actions。
- 未执行 Gradle 单测/assemble、APK 安装、UI 自动化或真机验收。全量功能迁入和五 Skin × 六 Tab 逐页视觉适配仍未完成。

### 下一批直接开工
1. 读取最新 Targeted Host run 的 job 结果；用一次定向节点验证 `fx-unified-navigation-regression.sh` 与 `fx-imported-suite-back-navigation-regression.sh`，修复失败根因。
2. 继续五 Skin × 六 Tab 的实际页面控件适配，优先 Harmony/Cupertino 的列表、表单、开关、弹窗、Sheet、键盘和无障碍。
3. 按 Ad/VPN/隐私/Hook/脚本逐页接通真实 Repository/Service/权限，不以删掉旧来源导航代表所有功能已迁入。


## 2026-11-05 — Harmony / Cupertino 共享 Tokens 与双 renderer 接线

### 本批源码实现
- 新增 `HarmonySkinTokens.java`：独立 Harmony Color / Shape / Typography / Spacing token；数值为 FX 自有实现，不复制华为系统私有资产。
- 新增 `CupertinoSkinTokens.java`：独立 Cupertino Color / Shape / Typography / Spacing token；不打包未经授权的 Apple 字体、图标或系统资产。
- 新增 `HarmonySkinRenderer.java` 与 `CupertinoSkinRenderer.java`：为 Android 原生 View 页面构造统一 Palette。
- `FxNativeSkin.java`：将 HUAWEI / iOS 的 Android View 页面渲染分支改为委派上述 renderer；`Palette` 仅提高为包级可见，未改变 semantic warning/error/success 色彩保护、未知 Drawable 保留和动态页面重应用机制。
- `FxComposeSkinTokens.kt`：Compose 六 Tab Shell 的 Harmony/Cupertino tokens 改为读取 Java 共享 token 类；页面背景、壁纸遮罩、导航 surface/border、accent、选中/非选中文字、选中 Tab surface、形状、导航栏高度、Tab item 高度、导航间距和字号均从同一组 token 派生。避免 Compose 与原生 Activity 两套 token 数值漂移。
- 调整 Harmony 导航半径和水平 inset、Cupertino 导航圆角/底栏与 item 高度，使与实际 Compose Shell 布局匹配；补齐 Cupertino selected-tab surface token。
- `scripts/tests/fx-global-ui-modes-regression.sh`：加入四个新 Java token/renderer 文件的存在性检查，并要求 Compose 使用 Harmony/Cupertino 共享 Color/Shape/Spacing/Typography tokens、Android View 路由到专用 renderer。

### 相关提交
- Harmony / Cupertino token 与 renderer 新文件：`cf3e53821cf08d8f763d43227c2e50fe1443bdf0`、`2e1ae5093b3c823a2c71437e6ddca9b13cffd180`、`b8727b7560acd90fd645b0c4c52d9a51edbf984e`、`7a39a566fcd08effb620aaa4749bd1c03ee03c56`。
- Android View Palette renderer 接线：`9c15e7cccdb0a24659f746a6c1dbb1b710cc19b4`。
- Harmony / Cupertino 细节 token 对齐：`a676d25a60eecff341dde2c98110610b97fb85e6`、`41cdcae8031035fd31de89ebce255c4b1540500b0`、`9e5c75b1ee57109dbadedf5e76a6397ba8cbd869`。
- Compose 与 View 共享 token 接线：`e37ea1aa3ebecafab278bd0dacd74531635e20c1`。
- 双 renderer 统一回归门禁：`826f20761f236c627828a2a6a4b7e0e6ffd83dcf`。

### 回读核验与验证边界
- 最新分支 HEAD 回读：`826f20761f236c627828a2a6a4b7e0e6ffd83dcf`（记录时；后续窗口仍须实时读取）。
- GitHub 回读确认：主应用仍为六 Tab；MainActivity 不含来源应用 Migration 导航状态/方法；第二 Tab 与 ClassicWebCompat 中文标题为 Ad；Hosts 只保留 Ad 内部功能路径；VPN 分应用路由使用 FX 原生方法名。
- GitHub 回读确认：FxComposeSkinTokens 的 Harmony/Cupertino 分支均引用 Java token 的 Color / Shape / Spacing / Typography；FxNativeSkin 分别委派 HarmonySkinRenderer / CupertinoSkinRenderer；五 Skin Shell 继续使用统一的 `fxComposeShellTokens()`。
- 这批完成的是**五 Skin 中 HUAWEI / iOS 的共享设计 Token、主导航 Shell 与原生 View 基础 renderer 接线**，不是整个六 Tab 的逐页视觉重构完成。
- 本批未在本地 Android SDK 环境执行 shell regression、Kotlin/Java 编译、Gradle 单测、APK 构建、安装或真机截图；不能称 CI / 构建 / 设备验证通过。Regression 文件已更新但仅完成 GitHub 内容回读。
- 尚未完成：将 Harmony/Cupertino tokens 深入覆盖六 Tab 所有 Activity 的列表行、表单、Dialog、BottomSheet、编辑器、错误/空状态；当前 FxNativeSkin 主要转换已知旧色值/通用按钮/开关/选择控件，尚不能代表全部组件已完成独立样式。

### 下一批立即实施
1. 以 Ad 和隐私页面为样本，将 Android 原生页面的卡片/列表/表单/弹窗从色值替换推进到统一 renderer/组件适配；先保证真实控件操作与状态不变。
2. 补五 Skin × 六 Tab renderer coverage 静态矩阵和 Android UI 自动化/截图基线；实际运行前注明可用 SDK/设备环境。
3. 按业务页逐项检查 Ad、VPN、隐私、Hook、脚本按钮是否已连接真实服务/Repository；优先消除无后端空操作与假状态，不恢复来源应用入口。

## 2026-11-05 — Targeted Host 回归结论补记与下一条 UI 实施线

- 最新分支 HEAD（读取时）：e5c9cb7d44ced68cba6136e191736c01bb9e7a09
- Targeted Host run：41984541289，job host-regressions = success。
- 该 run 的实际 changed paths 只有 scripts/tests/fx-global-ui-modes-regression.sh，因此它执行的是五 Skin 全局样式/控件/壁纸相关回归；没有执行 fx-gkd-automation-regression.sh、fx-gkd-selector-integration-regression.sh 或 fx-unified-navigation-regression.sh。不能扩张解释为这些脚本通过。
- 先前 Targeted Host run 41984271284 在 GKD automation regression 的 Python 检查处失败（日志报告内联检查器 line 34）。失败 HEAD 当时的 AccessibilityService 源码确实包含 disabled 分支撤销 FLAG_REPORT_VIEW_IDS 的表达式；随后规则仓库和测试的 package-scoped API 断言经并行提交修订。最新 HEAD 的 GKD 源码对 45 项对应静态契约逐条回读匹配，但尚未取得该修订版本实际运行 GKD regression 的 CI 结果。下一次触发 GKD 相关路径时必须读完整 job 输出再关闭问题。
- 导航重构：MainActivity 六 Tab、Ad canonical WebUI route、Settings 不含 source app hub、旧 migration router 不存在、Hook/VPN/Settings Back 顺序等 15 项源码回读检查全部 PASS。测试文件已修正，但本轮 Host success 未触发 fx-unified-navigation-regression.sh，因此该脚本本批仍未取得 CI 执行证明。
- 下一条实际开发线：继续五 Skin 的独立 Design Tokens / Renderer 与页面控件派发，优先 Harmony/Cupertino，覆盖六 Tab 内真实控件，而不是重复增加文档或只改主壳颜色。编译、UI 自动化、模拟器和真机视觉验收仍未完成。

## 2026-11-05 — 五 Skin Compose 导航 tokens 接入

- 新增 `FxComposeSkinTokens.kt`，为 ClassicWebCompat、FXLiquidNative、MiuixStyle、HUAWEI HarmonyStyle、iOS CupertinoStyle 建立独立 Compose shell tokens，涵盖页面背景、壁纸遮罩、底栏背景/边框、选中/未选中颜色、圆角、高度、间距和字号。
- `FxNativeAppShell.kt` 通过 `fxComposeShellTokens()` 选取五套 tokens；内容区 bottom inset 随底栏高度变化，不再固定 72dp。Liquid 保留 Kyant `LiquidBottomTabs` renderer，其余模式使用对应 surface/border/shape。
- Harmony/Cupertino tokens 已接入 Java `HarmonySkinTokens` / `CupertinoSkinTokens` 的颜色、形状、间距、字体定义；Android View renderer 通过 `HarmonySkinRenderer.palette()` 与 `CupertinoSkinRenderer.palette()` 复用对应色板。
- 新增 `FxComposeSkinTokensTest.kt`：覆盖五套几何、Liquid renderer 选择、Harmony/iOS 色板差异、Miuix 动态颜色和未知模式回退。
- 更新 `fx-global-ui-modes-regression.sh` 检查五套 token 与 Java renderer 接线；更新 `fx-hook-native-ui-regression.sh`，从固定 72dp 改为检查 Skin 对应的动态高度。
- 相关提交：`ee05a9cd4aa0cc171a616ef9bc3ca1ff4fa10a06`、`81c2cde1d7e1dc45b0c7c8601d6622bb1aa460e9`、`2792bc67d839205ea1f0f5c26bb7af3dcaa287ec`、`a25235f055411593f2b7b422bc864dd11ff49cf1`、`a0a7d50bc5a718d3f58cd40ef2c99adf0ae609b8`、`9dbe40882cee7829eb03a0c226fb21a42cdf6baa`、`2e19a6ecd2cb8602bd3e90e564824962e67fb778`。
- GitHub Host regression runs `41984541289`（`826f20761f236c627828a2a6a4b7e0e6ffd83dcf`）与 `41984658383`（`e5c9cb7d44ced68cba6136e191736c01bb9e7a09`）成功，包含五 Skin regression、统一导航、Hook 原生 UI 检查通过。Host-only job 未构建 APK，因此 Gradle/JUnit、APK、UI 自动化和真机验收仍未验证。
- 尚未完成五 Skin 的全部六 Tab 逐页组件；Harmony/Cupertino 的 TopBar、Card、ListItem、Dialog、Sheet、Switch、Search、InsetGroupedList、FormRow、Alert、ActionSheet 等仍需继续开发。ClassicWebCompat 还需对照 10.0.2 原始资源逐页验收。
- 下一步：优先把 Harmony/Cupertino renderer 扩展到六 Tab 共用的 TopBar、卡片、表单行、开关、列表、Dialog/Sheet，再做截图/UI 自动化；随后进入 Ad 完整真实过滤链或 VPN Root 数据面共存安全链。


## 2026-11-05 — 主 Activity 组件 Token 化与纯色 GradientDrawable 页面适配

### 本批源码实现
- `MainActivity.java`：Ad、隐私和设置等原生主页面共用的背景/表面/主次文本 helper 改为读取 Harmony / Cupertino 的共享 Color Tokens；卡片圆角读取 Shape Tokens；分组标题背景和描边读取 Surface Variant / Divider Tokens。保留 FXLiquid/Miuix 原有路径与交互回调。
- `FxNativeSkin.java`：除已知旧色值的 `ColorDrawable` 外，增加对纯色 `GradientDrawable` 的安全适配。仅在 `getColor()` 返回非空 ColorStateList 且颜色命中现有旧主题映射时替换；不会压平自定义渐变，也不会改写 selector、ripple 或未知 Drawable。
- `scripts/tests/fx-global-ui-modes-regression.sh`：增加 MainActivity 使用 Harmony/Cupertino 共享 Color/Shape Tokens 的断言；新增纯色 GradientDrawable 适配路径和未知 Drawable 保留边界断言。

### 相关提交
- MainActivity 主页面 helper token 化：`0f88b76dab520e7540e8fdd1c7b86e59fe59817d`。
- MainActivity shared token regression：`3f5e444c19cb8db604dd821bdd57689607d7d39b`。
- 纯色 GradientDrawable 安全换肤：`bdc2afc36f90c6076403437d77611b1a970d2370`。
- GradientDrawable regression：`1aed6dc9d3c8ffe34ee2c1d134aee1369ff0015c`。

### 当前验证状态
- GitHub 回读确认上述源码/测试修改存在，且共享 token 路由没有覆盖 MainActivity 的业务回调。
- 新增 Drawable 适配只识别 ColorStateList 单色背景；对于多色渐变（`getColor() == null`）、RippleDrawable、selector 及自定义未知颜色，保留原 drawable。
- 未执行 shell regression、Gradle Kotlin/Java compile、Android 单元测试、APK assemble、安装、UI 自动化或真机视觉验收；源码静态回读不等于测试通过。
- Harmony/Cupertino 当前已覆盖：共享主导航 tokens、MainActivity 常见页面背景/卡片/分组 helper、已知旧色值的 Android View 基础适配；仍未覆盖所有导入 Activity 的全部自定义行、复杂表单、弹窗、Sheet、编辑器/扫描状态。不能标记六 Tab 页面级换肤完成。

### 下一批直接实施
1. 继续将共享 token 接入主要页面中的分组标题、表单行和动态列表，优先 Ad / 隐私；保留原来的动作回调、持久化和权限语义。
2. 检查导入的 Ad / Shield Activity 中自定义 GradientDrawable、Radio/CheckBox、Dialog 和列表行，按组件类型添加有限、可回归的 renderer 规则，禁止无差别递归重绘未知背景。
3. 在当前环境可执行时先跑 `fx-global-ui-modes-regression.sh`、`fx-unified-navigation-regression.sh` 和 `fx-imported-suite-back-navigation-regression.sh`；此后才推进 Gradle build/UI automation，严格记录未验证层级。


## 2026-11-05 — GKD 本地规则 JSON 导入/导出接入

- 在 `FxGkdRuleStore.kt` 增加版本化规则文件：
  - format：`FX-GKD-LOCAL-RULES`
  - schema_version：1
  - 最大文件大小：256 KiB；单文件规则数量上限：128
  - 导出仅包含 id/package/selector/cooldown/enabled 等规则配置，不包含页面文本、截图、触发历史、凭据或无障碍服务状态。
  - 导入采用 merge，不覆盖原规则；要求目标仍安装且为普通用户应用、selector 通过上游 GKD 编译校验、cooldown 在 1–60 秒；重复的 package+selector 跳过。
  - 导入强制将新规则 disabled，不信任输入文件中的 enabled 字段；用户需逐条检查并手动启用。
- 在 `FxGkdAutomationActivity.java` 增加系统文档选择器导入/导出按钮；导入时再次做 256 KiB 流式限额，导出生成 `FX-GKD-Local-Rules.json`。
- 规则列表刷新现在保留总开关、添加规则和导入/导出控件，只替换规则列表区域（固定保留 7 个顶部控件）。
- 静态回归 `fx-gkd-automation-regression.sh` 增加格式、schema、尺寸限制、import/export 入口、导入默认关闭、目标包验证及失败回滚断言。
- 对应提交：`e5c9cb7d44ced68cba6136e191736c01bb9e7a09`（Store codec）、`81609ed4e21f8f1dc9537edd010691bc93b35785`（Activity document picker UI）、`41971a2df424866cef3b5bc1fa450b97344e75c3`（import/export 静态测试）、`d91a6cf71eaba6f0199b8ef6e8a240a188b2eaf7`（package-selector 去重键回归）。
- 本轮 GKD Actions run `41984962613` 正在运行（触发 head d91a6cf71eab）；截至本次状态更新，尚未取得最新 Android App compile 和 FX GKD unit test 的最终结果。旧 run 曾因后续 push 被 concurrency 取消；不能据此宣称构建失败或通过。
- 尚未完成：上游订阅管理、规则组/分类/排除项、规则刷新与版本、复杂动作、触发记录/日志、快照与 AI Provider、Room 数据迁移、Shizuku/AIDL、后台/开机/通知/Tile 生命周期。当前导入/导出仅是 FX 自有本地 JSON 格式，不兼容宣称为 GKD 原版备份文件。


## 2026-11-05 — 六 Tab 原生操作分组与 Settings 边界布局

### 本批源码实现
- 新增 `addNativeActionGroup(LinearLayout)` 统一分组卡片 helper：按 FX 当前 Skin 读取卡片表面/描边，保留调用方设置的横向或纵向排列；子按钮仍由 `FxNativeSkin` 样式适配。
- Ad：本地 Hosts 操作、订阅与过滤规则、广告过滤完整功能三个 action group 已分组显示；Hosts、规则、外部编辑、Ad Activity 的原有动作回调没有改变。
- 隐私：Root/LSPosed/Remote Files 状态操作按钮使用独立 group；各隐私保护页面仍通过原 Hook 目标配置导航。
- 脚本：新增/导入/导出/刷新/日志/MITM 证书相关操作按钮放入统一 group。
- VPN：节点订阅的“添加订阅 / 节点”“更新全部”操作加入统一卡片，但保留水平布局和原回调；订阅列表动态行仍使用自己的卡片，不改变启停、更新、详情和删除操作。
- 设置：许可证、模块运行状态与诊断、系统授权、运行日志分为四个全局设置 group；备份、壁纸、五种模式继续保持在 Settings；没有恢复“迁移应用”入口。
- `scripts/tests/fx-unified-navigation-regression.sh`：增加 Ad Hosts/订阅/完整功能 group、Privacy/Script group、Settings 四组、VPN 横向订阅操作卡片的静态结构断言。

### 相关提交
- 新增统一原生操作分组 helper，接入 Ad / 隐私 / 脚本：`92d6a13d4c76bcede6fef71e1aadda432f73faeb`。
- Ad / 隐私 / 脚本操作分组回归：`ddf55b2745fcddf3c203945a008829bd7e35cb8a`。
- 保留调用方方向、接入 VPN 订阅操作卡：`bfe13a3f01216e08ef80390abe9e2552dc0ebb73`。
- VPN 订阅卡片回归：`035506d9e247d3773b370c514810b88a16d5d430`。
- Settings 系统级分组：`e58246adf378d3dc29a9013c14e64623b8286f07`。
- Settings 分组与无迁移入口回归：`ad2c8539973b14f370bc7f8694d8a210cbf0d1b7`。

### CI 与验证等级
- GitHub Actions Host job `41985075861`：HEAD `ddf55b2745fcddf3c203945a008829bd7e35cb8a`，`host-regressions = success`。该成功点覆盖 Ad / 隐私 / 脚本分组及当时的统一导航回归，不包含之后新增的 VPN 订阅横向卡和 Settings 四组。
- 随后连续 push 的旧 Actions runs 被取消，包括 `41985258983`、`41985232321` 等；这些不是 PASS。
- 当前最新分支 HEAD（本批记录时）：`ad2c8539973b14f370bc7f8694d8a210cbf0d1b7`；Targeted Host Regression run `41985280861` 已完成，`host-regressions = success`。Job API 回读确认只有 Host 静态回归 job，未包含 Gradle/APK/设备验收。
- 本地未执行 Gradle compile、Android 单测、APK assemble、安装或真机 UI 测试。不得把 Host job success 扩大解释成完整 APK / 设备验证。
- 分组是 UI 布局收敛，不代表各业务能力功能已全部迁移或后端已完整实现。

### 下一批直接实施
1. 将同一分组容器延伸到 VPN 高级配置/节点列表与 Hook 应用列表中的重复操作区，保持横向/纵向布局和动作语义。
2. 逐页审计导入的 Ad / Shield Activity：确认它们的卡片/分组背景实际通过共享 Skin Host 适配；对自定义状态色、危险操作、未知 Drawable 保持保护。
3. 检查五 Skin 切换是否保存当前 Tab/页面滚动/编辑草稿，且不重启 VPN、DNS、Root proxy、Hook 和 Script 服务；补适配回归。


## 2026-11-05 — Dia Dialog/按键 Hook 路由归属与跨 AI 提示词同步

### 实际源码调整
- `MainActivity.showHookHub()` 增加“Dialog 对话框 Hook”和“按键动作 Hook”两个可见入口，分别进入 `showAppList("Dialog处理")`、`showAppList("按键控制")` 的逐应用目标流程；不创建第二个 Activity 入口或来源应用目录。
- `showAppList()` 将“自定义 Hook”“Dialog处理”“按键控制”识别为 Hook 来源，应用列表与目标配置页高亮 Hook；Toast、通知监听/权限提示仍由隐私页提供，避免业务重复。
- 页面入口不等于真实 Hook 执行成功；仍须分别核验 Root/LSPosed 作用域、配置发布、目标进程状态与设备权限。

### 回归测试调整
- `scripts/tests/fx-dia-native-tab-regression.sh` 改为检查 Hook Hub Dialog/按键真实入口、Toast/通知隐私入口、Hook/Privacy Tab 归属，以及统一 `handleNativeTabIntent(intent)`，不再要求已删除的旧 Dia 类别数组。
- `scripts/tests/fx-hook-native-ui-regression.sh` 将 Hook 来源判断扩展到 `Dialog处理` 和 `按键控制`，并保留 Privacy 来源高亮 Privacy 的约束。
- GKD 页面固定保留七个头部控件；规则列表刷新从 child index 7 起替换，对应回归阈值已同步。

### 产品规格与跨 AI 提示词
- `docs/FX_1.0.0_PRODUCT_RESTRUCTURE_AND_AI_HANDOFF.md` 明确 Dialog/按键 Hook 属于 Hook 且高亮 Hook；Toast/通知隐私策略属于隐私且高亮隐私。
- 唯一跨 AI 执行提示词仍为 `docs/FX_1.0.0_AUTONOMOUS_CROSS_AI_HANDOFF_PROMPT.md`，已写明相同归属边界；没有创建第二份提示词。

### 相关提交
- Hook Hub Dialog/按键入口与 Hook 来源路由：`c435ebf844670332ddf8ddd2c4079760e7d790cb`。
- Dia native-tab 回归更新：`fdb27552563633c33a1066d57a5282da7c103a48`。
- Hook 原生 UI 回归更新：`16522fbf8e87b872b5e0faeac79c2ef20d4b111d`。
- 产品规格 Tab 归属更新：`3f39f411305ff22edbcdbfdb09d2f3619bd4dc2d`。
- 唯一总提示词归属更新：`469aba74c18ebedb8bcc8c755d8959155a973cc9`。

### 验证与边界
- Targeted Host run `41985075861`（run 541）在源码/测试组合提交 `ddf55b2745fcddf3c203945a008829bd7e35cb8a` 上为 success，覆盖当时的五 Skin 静态检查、统一导航、Hook 原生 UI、Dia native-tab 等受影响 Host 回归。
- 后续并发 push 会取消旧 Actions；必须按最新 HEAD 查看新 run，取消不算通过。
- 未执行 Gradle assemble、Android JUnit、APK 安装升级、UI 自动化或真机测试；未验证目标设备实际 Dialog/按键 Hook 执行、LSPosed 注入、页面触控和视觉适配。
- 不能把来源页面清理或功能入口可达称为全部功能迁移完成。

### 下一批直接实施
1. 对 Dialog/按键逐项核对目标配置、发布和 Hook runtime，补齐缺失的真实调用链与可观测状态。
2. 继续五 Skin × 六 Tab 页面级组件适配，优先 Harmony/Cupertino 的 List/Form/Switch/Dialog/Sheet/编辑器，而非只改导航色值。
3. 推进 Ad 五层过滤真实链路和 VPN Root 数据面与第三方 VPN 共存；安全回滚、防 DNS/IPv6/WebRTC 泄漏优先。

## 2026-11-05 — 统一导航、五 Skin 页面 Tokens 与 GKD 本地规则传输续接

### 本批真实源码与 UI 改动
- 主导航继续固定为 VPN / Ad / 隐私 / 脚本 / Hook / 设置；第二 Tab 只显示 Ad，Hosts 仍是 Ad 内部功能页。Settings 保持全局外观、壁纸、备份、权限、许可和运行诊断，不恢复“迁移应用”来源 Hub。
- MainActivity.showDiaDialogTarget() 修正为 selectedBottomTab = 4，标题使用“Hook · Dialog 处理”，返回入口为“返回 Hook 应用列表”；避免从 Hook 工具进入 Dialog 目标配置后错误高亮隐私。Toast 与通知配置仍从隐私页进入并保持 index=2。
- fx-dia-native-tab-regression.sh 已补充检查 Hook Hub 的 Dialog/按键入口、隐私页的 Toast/通知入口、目标页路由与实际 Tab 归属。对应 MainActivity commit：f46b57b2356496ee2f479a4ce1dd69508b31a5f6；回归脚本 commit：e1734620ce23ba5d1659ed0da3424f7d60de8498。
- Harmony / Cupertino tokens 继续扩展至页面背景、分组、卡片和列表行；共享 renderer 继续区分 Harmony/Cupertino 的表面、边框、字号、间距与圆角。相关提交：964466323a5ae830f88e7035eeaaf1ff0052d01b、d19f94bad82f33539aec434244fa785a076ccf84、0c803a4593a868bab6b822fa88bcb8dacafe1026、c89e33d8971339aa4f5e0b0e21545a2daa8c86ec、18ee23bf3a445921edc4aaf4dcb98d175c6740cc。
- addNativeActionGroup() 已用于 Ad 本地 Hosts/订阅/广告功能、隐私状态、脚本操作、VPN 节点订阅操作和 Settings 系统级卡片分组；动作回调保持原样。相关提交：92d6a13d4c76bcede6fef71e1aadda432f73faeb、ddf55b2745fcddf3c203945a008829bd7e35cb8a、bfe13a3f01216e08ef80390abe9e2552dc0ebb73、035506d9e247d3773b370c514810b88a16d5d430、e58246adf378d3dc29a9013c14e64623b8286f07、ad2c8539973b14f370bc7f8694d8a210cbf0d1b7。
- 唯一正式跨 AI 提示词去除了已废止的重复 Master Prompt 路径，明确自身是唯一执行入口：b0c231e63959dd8f8f54ddfb1afed639b60967b8。产品方案和两份 UI 执行档继续以统一六 Tab/来源功能归并为准。

### GKD 本地 JSON 规则传输
- FxGkdRuleStore.kt 提供 FX 自有格式 FX-GKD-LOCAL-RULES / schema v1，文件 256 KiB、规则 128 条上限；导入只 merge，不覆盖原规则，目标包必须是仍安装的普通用户应用，selector 必须通过编译校验，package+selector 去重，所有新导入规则强制 disabled。
- FxGkdAutomationActivity.java 已接入 ACTION_OPEN_DOCUMENT / ACTION_CREATE_DOCUMENT 的 JSON 导入导出；导入按流式字节计数限额，成功后刷新规则、失效运行时缓存并重新配置单一 FX AccessibilityService。
- fx-gkd-automation-regression.sh 新增 UI 文件选择器、版本/大小/目标应用/selector/去重/导入默认关闭/不自动开启总开关等安全契约检查。Store、Activity 与回归提交历史已在 GKD 专项章节记录。
- 修复该回归中把布尔断言误放进字符串 token tuple 的测试脚本问题：6d2ebd3650f1dd296884f2f6420ffec28e038fe6。该测试修复之后的 GKD Selector Compatibility run 41985350088 在本次记录时仍为 in_progress；不得提前标记 GKD workflow 通过。

### CI、验证和限制
- Host Regression run 41985280861（HEAD ad2c8539973b14f370bc7f8694d8a210cbf0d1b7）成功，验证其当时受影响的主导航、五 Skin 和 Settings/操作分组静态契约。较早 Host run 41985075861（HEAD ddf55b2745fcddf3c203945a008829bd7e35cb8a）成功，覆盖 Ad/隐私/脚本分组和当时路由检查。
- Dialog 目标页修正与新增的 Dialog/Toast 归属断言之后的 Host run 41985225377 被后续 push concurrency cancel；当前不能声称该新断言已在 CI 通过。新 GKD regression fix 的 workflow 正在执行；以完成后的 job 结果为准。
- 41985350065 Host run 因并发提交被取消，不计为通过。Canceled 与 queued 都不计为 PASS。
- 未执行 Android Gradle 主应用全量 assemble、APK 安装、五 Skin × 六 Tab UI 自动化/截图或真机验收。源码和 Host 静态回归不能代表视觉/设备验收。

### 下一批直接实施
1. 完成当前 GKD Selector Compatibility job，若有失败只修对应具体根因；随后为 GKD JSON codec 补充可执行的 Android 单元测试/纯 Kotlin codec 测试，不只依赖 grep。
2. 继续 Harmony / Cupertino 在 Ad 与隐私页的表单行、列表控件、Dialog/Sheet 的真实 renderer 覆盖，维持业务回调与状态语义。
3. 对 Hook/Privacy 的目标页 Tab、标题、返回路径做一次定向 UI 回归；确认 Dialog Hook=Hook、Toast/通知=隐私，不恢复来源应用目录。


### GKD 本地规则 JSON 导入/导出落地补记（2026-11-05）

- `FxGkdRuleStore.kt` 增加 `exportJson/importJson`：FX-GKD-LOCAL-RULES、schema v1、最大 256 KiB、最多 128 条；合并而不覆盖已有规则；要求目标仍是已安装的普通用户应用、selector 通过上游引擎编译、cooldown 在 1–60 秒范围；对 package+selector 去重。
- 导入不会相信文件中的 enabled 字段：每条新规则都强制 `enabled=false`；不会开启 GKD master switch。写入失败返回明确错误，不报告成功。
- `FxGkdAutomationActivity.java` 增加系统 JSON 文档选择器：ACTION_OPEN_DOCUMENT / ACTION_CREATE_DOCUMENT；读取按流计数，超过 256 KiB 立即拒绝；成功后失效规则缓存、重配唯一 FX AccessibilityService，并提示新增/跳过数量和全部关闭状态。
- `scripts/tests/fx-gkd-automation-regression.sh` 覆盖文件选择器、文件大小上限、格式版本、目标包/selector 校验、去重、全部关闭以及不自动开启 master 的契约。
- 主要提交：Store `e5c9cb7d44ced68cba6136e191736c01bb9e7a09`；Activity `81609ed4e21f8f1dc9537edd010691bc93b35785`；安全回归 `4b200b8e2902f10628215ff42002b6eea9f6c38a`；README 与计划同步 `1d405676f73d692cdce332d9018cb3dc061a2d23` / `e66db31fe3c9daf206b83c9e8062b7f3803c170f`。
- 修正了 GKD 自动化回归脚本中把布尔表达式误放入字符串断言元组造成的 Python TypeError；另修正全局 Skin 回归中的动作按钮圆角断言变量名。
- 上游 Selector JVM 测试在专用 Workflow `41985451124` 已通过；专用 workflow 的 FX App Kotlin/Java compile 目前运行中，尚不能宣称通过。较早失败 `41984962613` 是回归脚本 TypeError，修复后需以新 run 结果为准。
- 当前仍未完成整套 GKD-XA 功能迁移：在线订阅源/规则组/排除项、复杂触发/动作、快照/触发历史、AI、Shizuku/AIDL、后台/磁贴/开机生命周期仍是后续任务。


## 2026-11-05 — Hook 应用列表、逐应用作用域与自定义规则页 Skin 分组

### 本批源码实现
- Hook 授权中心 `showHookHub()`：Remote Files、KernelSU/Root、LSPosed、Android Accessibility 的状态与刷新/操作分别进入独立 native action group；保留各自真实 status refresh、Root 检查、LSPosed Manager 跳转、应用列表打开及 Accessibility 系统设置 callback。
- Hook 应用列表 `showAppList()`：搜索、分类提示和异步加载状态使用当前 Skin 的表面背景；保留固定的头部 child 索引（0..4），不改变后台应用索引、搜索 TextWatcher、分页计数、滚动位置保存与恢复。
- Hook 动态应用行 `appendAppRows()`：应用行使用 `uiPanelDrawable()`；应用名、包名与箭头颜色从 `uiPrimaryTextColor()/uiSecondaryTextColor()` 读取；分隔线使用 `0xffe3e8ee`，由 `FxNativeSkin.replacementBackgroundDrawable()` 转为当前 Skin divider。应用图标异步加载、点击 `showTarget(ai)`、加载更多及分页逻辑保持不变。
- 逐应用 `addLsposedScopeControls()`：实时作用域状态、刷新、申请和移除四个控件放进统一 Skin 卡片；LSPosed request/remove 的审批、安全确认、超时与状态回读 callback 不变。
- 自定义 Hook 规则页 `showCustomHookRulesPage()`：规则说明/新增/分组管理/JSON 导入导出/OBSERVE 日志为一个动作卡；保存发布与返回为单独 footer 卡；规则筛选 Spinner、搜索、清除筛选与摘要为 filter 卡。动态 `ruleRows` 保持独立容器；筛选 View 恢复引用、规则渲染、校验、草稿、发布与返回 callback 不变。
- `scripts/tests/fx-hook-native-ui-regression.sh`：新增断言，覆盖五组授权卡、搜索/加载 Skin 背景、固定头部/分页/目标路由、Hook app row 的表面/文字/分隔线、LSPosed scope card、custom Hook action/filter/footer cards 与原 callback。

### 相关提交
- Hook 授权中心与应用列表初轮 Skin 接入：`ac969213f0ed3656c92116b4184cd16b5a969526`。
- Hook Hub / app list 静态回归：`696d235aa539a565aed6d573845e02a8c79c06f8`。
- Hook 动态应用行换肤：`5799a9145b91c1c94d76dde2c76892562bbf1ea1`。
- Hook app row 回归：`d5b2b4487bbe067b3c526b1867464a096ac620fe`。
- 逐应用 LSPosed 作用域分组：`9154a293932d6494c5d332a3ede8eeaa3186e835`。
- 自定义 Hook 页面筛选/动作/发布分组：`34ee3577c6a56509c4ce2f557126aeb63dc7ad82`。
- scope/custom-rule group regression：`7248b0af3ae171c4b12e5394b085a9313e8bf839`。

### 验证等级和限制
- 已逐文件 GitHub 回读确认 MainActivity/ FxNativeSkin/Hook regression 的新代码存在，且固定列表头部/索引、应用打开、分页和过滤 View 引用仍保留。
- 当前 Hook 源码/测试批次 HEAD `7248b0af3ae171c4b12e5394b085a9313e8bf839` 对应 Targeted Host Regression run `41985996956` 最终为 `cancelled`（GitHub API 最终状态）；未获得该 Hook 回归批次的 CI PASS。此前连续 push 对应中间 runs（含 `41985983455`、`41985940528` 等）也被 concurrency cancel；取消不代表失败，也不代表通过。
- 本批未在 Android SDK/Gradle 环境执行 Hook regression、Gradle compile、Android JUnit、APK assemble、安装或真机触控/视觉检查。当前只能标为 GitHub 源码回读，等待最新 Host job 结果。
- 五 Skin 的完整逐应用页视觉验收仍未完成；本批主要建立共享 surface/color 的真实调用和页面分组，不能视为五 Skin × 六 Tab 完成。
- Root、LSPosed、Accessibility 的状态卡反映对应系统事实；UI 分组本身不代表 Root 授权、LSPosed 批准或目标进程注入已经成功。

### 下一批直接实施
1. 逐应用目标页的广告识别、隐私 Hook、标识/剪贴板/Wi-Fi/网络类型/设备标识/版本/时区/位置表单，核对 EditText、Spinner、Switch、危险/保存按钮是否覆盖五 Skin renderer；优先补缺失的控件级 Skin 回归。
2. 继续 Hook 自定义规则列表项、Dialog/Toast/按键页面的组件级 Skin 覆盖，同时保持业务数据/验证与执行安全边界。
3. 后续代码批次合并后再读取最新 HEAD 对应 Host run；本 Hook 批次取消，不可写为 CI PASS。继续 Ad/Privacy 对应 Activity 的页面级控件适配。


## 2026-11-05 — 五 Skin 共享卡片与开关组件接入 Harmony/Cupertino Renderer

### 实际实现
- MainActivity 的共享信息卡片标题/正文/设置说明分别使用 `fx-card-title`、`fx-card-body` 语义标签；统一 toggle 行使用 `fx-switch-row`。
- Harmony Renderer 与 Cupertino Renderer 分别实现卡片标题、正文与开关行的视觉分支：使用各自独立的 PRIMARY/SECONDARY text、CARD_TITLE、CARD_DESCRIPTION、SWITCH_LABEL、ROW_MIN_HEIGHT、横/纵 padding、surface/stroke/radius token。
- 两套 skin 的说明文字令牌不同：Harmony 13.5sp、Cupertino 13sp；两者均使用独立字重/letter spacing/line spacing，业务事件和点击回调不变。
- `FxNativeSkin.beginTaggedComponentRender(view, mode, role)` 使用 WeakHashMap 缓存 View 的当前 Skin/role，重复 bind 不再重复创建相同 Drawable；切换 Skin 或 component role 后重新应用。
- 相关页面适配并行扩展至 Hook 应用列表、LSPosed 逐应用 scope、Dia Frida 页面和聚合卡片/操作组；它们仍调用原有功能逻辑，不因换肤替换业务回调。

### 主要源码/测试提交
- Harmony card title renderer：`9ab0d6722c07390c05bac3744e34f840ab67afbd`。
- Harmony/Cupertino card description typography tokens：`c4c8b2e3ea65be37e69c58645ef4bd65597ac35d`、`74f328061a2696d1f3f2ed5566c2507b693ea465`。
- Harmony/Cupertino card/switch renderer：`44289cf22350bf68cb70f17c666dacb85a425750`、`649c277739c61573f2c590e65f682491876a0236`。
- Harmony/Cupertino redraw cache：`1ec5cc076e7336d19ec90a74e1d8ef8afbdb8d20`、`4bfa596c0cc0a1e8adcbee3f662dcc0242d9be2e`。
- MainActivity toggle role：`bf67e66b8f31cc0ae020961f6e0f5fa9da791e04`；Harmony 说明文字渲染：`9f99a82dbbe17dbf9e96c29076738284c0db40d3`；Cupertino 说明文字渲染：`dee16d59fbb35e6aa1069becca344ed7296b1251`。
- Skin palette typography 单测：`537fe8701af8a1a7acc2f0154a33c4505385ec0c`。
- Hook app row / Frida screen / LSPosed scope 适配：`5799a9145b91c1c94d76dde2c76892562bbf1ea1`、`aef3ea88df3ad2f4047d5d3a215e7c887d183e95`、`9154a293932d6494c5d332a3ede8eeaa3186e835`。

### 回归修复与验证
- Host run `41986085308`（run 627）最初失败：测试仍要求卡片组条件只含 `fx-card` 与 `fx-setting-card`；当前实现新增 `fx-card-group`，旧断言已更新为分别要求三种角色。
- Host run `41986237883`（run 635）失败：测试仍要求语义色检查直接内联在 `applyButtonSkin()`；当前实现已抽取 `shouldPreserveSemanticAction(button)`，测试已改为检查该 guard 在 BUTTON_SKINS 缓存前执行，并核验其读取文字色/背景色。
- 修正提交：`28ecd0f05a255ad964185e2cb917f3f58c5082b8`。
- Targeted Host run `41986350889`（run 639）在 HEAD `28ecd0f05a255ad964185e2cb917f3f58c5082b8` 上 **success**。当前相关静态回归覆盖：Renderer cache gate、token 常量唯一性、五 Skin 页面/section/card tokens、卡片角色、Switch/CompoundButton 分派、背景仅重绘已知中性色、语义危险/警告/成功颜色保护。
- Host success 只表示这些源码静态/主机回归通过，不是 Android Gradle 编译、安装或真机视觉验收。

### 未验证与下一批
- 尚未运行 `testDebugUnitTest` / `assembleDebug`、APK 安装升级、UI 自动化、截图基线或真机触控；五 Skin × 六 Tab 的每个页面并未全部覆盖完成。
- Harmony/Cupertino 当前已接入导航、卡片、标题/正文、列表行、开关和部分 Hook/Frida 页面；Dialog/Sheet、EditText/Spinner、键盘、空/加载/错误状态仍需逐页补齐和验收。
- 下一批继续将语义标签扩展到未接入的业务 Activity 与表单/弹窗；同时检查 cache 在 View tag 或 mode 改变后的正确失效，并保留 ClassicWebCompat 原有 WebView 与壁纸行为。


## 2026-11-05 — 五 Skin 原生弹窗统一接线与 Ad/设置边界回归

### 本批实际实现
- `FxNativeSkin.showDialog(Activity, AlertDialog)` 已建立统一弹窗入口：先显示原生 AlertDialog，再对 Window decor 树运行当前 Skin 的 `applyComponents`，并在 decor 首次布局后补一次渲染，覆盖系统标题/按钮和动态表单/列表内容。
- MainActivity 已把以下原生弹窗接入共享 renderer：
  - 本地 Hosts 分页编辑器；
  - Ad 过滤规则/订阅新增、编辑对话框；
  - 五 Skin 壁纸管理弹窗；
  - 系统 CA 管理弹窗。
- `scripts/tests/fx-global-ui-modes-regression.sh` 增加门禁：必须存在统一 dialog renderer、decor 首次应用和布局后复渲染，并检查 Hosts、Ad、壁纸、系统 CA 的调用点。
- HUAWEI Harmony / iOS Cupertino renderer 继续使用独立 token：颜色、形状、间距、字体；其 Android View 组件分支包括页标题、分区标题、卡片标题/说明、列表行、Switch 和动作按钮。Compose 六 Tab Shell 已通过 `FxComposeSkinTokens.kt` 读取两套相同的 Harmony/Cupertino 共享 token。
- 导航清理仍保持：MainActivity 不包含来源应用 Migration router/状态；六 Tab 固定 VPN、Ad、隐私、脚本、Hook、设置；ClassicWebCompat 第二 Tab 标题为 Ad；Settings 无迁移应用入口。

### 本批相关提交
- `0a53050c3153c0065f536f15ccf0f9aaf72ae3a0` — 新增五 Skin 原生 Dialog 通用入口。
- `b077c50408e36d74888974279748129135c19e44` — Hosts、Ad 规则、壁纸、系统 CA 弹窗接入。
- `f119ac70b2686e3db0eb3a210f2525d34918a2e2` — Dialog 接线静态回归门禁。
- 前序 Skin token/renderers 与 Ad-only 导航改动见本文件更早的本轮条目；当前 HEAD 必须实时读取，以上 commit 只是本批变更证据。

### 验证与边界
- 已从 GitHub 最新分支回读源码，确认 `showDialog` 方法存在，并确认 MainActivity 有 5 处调用共享弹窗 renderer；回读检查还确认旧 Migration router 符号缺失、Ad 分栏名称没有 `Ad/Hosts`、主导航六项保持。
- 当前 HEAD 的 commit status 尚无附加检查项；本轮没有本地 Android SDK/Gradle 环境执行 shell 回归、JUnit、Gradle assemble、安装或真机 UI 检查。不能称本批回归已运行或通过。
- 旧 Targeted Host run `41986350889` 的 SUCCESS 只覆盖其对应旧 HEAD 的上一批 Skin 静态回归，不覆盖本批 Dialog 代码，也不代表 Gradle/真机验收。
- 五 Skin × 六 Tab 的全量视觉适配尚未完成；本批只把四个高频 FX 原生弹窗接入通用 renderer，其余内嵌/来源页面的 AlertDialog、BottomSheet、空态/加载态还要逐页面接入和验收。

### 下一批直接开工
1. 将 `FxNativeSkin.showDialog` 扩展接入 Ad 规则详情/删除确认、VPN 节点/订阅编辑、Hook/Frida 工具和隐私 Shield 的高频自定义弹窗；优先迁移真正使用 FX 主导航的页面。
2. 为 EditText/Spinner/搜索框/多行代码编辑器与表单行增加语义标签和控件级回归；保留自定义 Drawable、危险/警告/成功动作颜色和现有输入行为。
3. 针对最新 HEAD 运行 Dialog/Skin/Ad-only 导航定向 Host 回归；没有 Actions 结果时只记录源码回读，继续推进真实页面覆盖，不重复触发整套 Actions。


## 2026-11-05 — Hook 表单 Spinner 统一 Skin 与 Dialog/Frida 过期回归纠正

### 本批实现
- `MainActivity.java` 新增 `createSkinAwareSpinnerAdapter(List<String>)`。选中项与下拉项都调用当前 FX 主文字 token、14sp、Android 公共字体族 `sans-serif-medium`、统一 padding 和单行布局。
- 已接入 ActivityKey finish trigger、Dialog toggle trigger、签名语法选择、Hook action 选择、自定义规则组筛选等 Spinner。原来的 item 数值映射、`OnItemSelectedListener`、草稿/保存回调均保留。
- 修正早期无效写法 `Typeface.MEDIUM`（Android Typeface 不存在此常量），改用 `Typeface.create("sans-serif-medium", Typeface.NORMAL)`；Hook regression 加入正向字体族断言和禁止该无效常量的检查。
- Hook 页面仍使用原生列表/弹窗/配置存储；Skin adapter 只改文本呈现，不改变触发器语义或执行逻辑。

### 旧测试失败原因与纠正
- Host run `41986611189`（HEAD `1a967a67dd737f816c93395be88bee1b6cdfdd9c`）失败在 `fx-dia-dialog-native-regression.sh` stdin line 110。失败断言要求旧 `case "按键控制":`；实际 MainActivity 已使用 `if ("按键控制".equals(activePrivacySection))` 并调用 `showDiaKeyControlTarget(ai)`。该断言属于旧路由结构，不是业务路由缺失。后续版本的测试改为检查 Hook Hub 的“按键动作 Hook”卡片、`showAppList("按键控制")` 和真实目标页调用。
- Host runs `41986776704`（HEAD `ebfcdc1900cf8f2d02859f09a3c6bed633f27462`）与 `41986829015`（HEAD `cca8e4a34451ff219e83133a403593a38a55b75a`）失败于 `fx-dia-frida-page-navigation-regression.sh` stdin line 6：测试仍寻找已经废止的来源菜单 `case "运行日志":`。FX Frida 已整合至 Hook Hub 的“Frida 环境与注入”入口，运行日志通过 Frida 目标上下文深链打开；后续测试已改为检查 Hook Hub 入口和新目标页导航，不再要求来源应用菜单。
- 上述旧失败都应保留为历史失败证据，不得改写为通过；后续 HEAD 已修正相关测试结构。

### 当前源码回读
- 最新回读的 `MainActivity.java` 仍保留 `showHookHub()`、ActivityKey 真实目标页条件路由、Skin Spinner adapter；没有 `migrationSuite` 等旧来源应用导航状态，也没有 `Ad/Hosts` Tab 名。
- `fx-hook-native-ui-regression.sh` 检查 Spinner 的 selected/dropdown renderer、合法字体族及五个表单 Spinner 的共享 adapter。
- `fx-dia-dialog-native-regression.sh` 使用 Hook Hub 卡片和当前业务路由检查 ActivityKey，不再要求旧 `case` 分支。
- `fx-dia-frida-page-navigation-regression.sh` 使用 Hook Hub “Frida 环境与注入”入口检查，并保留目标会话日志上下文检查。

### CI 验证
- 最新已完成 Host job：run `41987056283`，HEAD `e06dbc9b8eefd6444949aa57aeb0eb0453c51335`，`host-regressions = success`。GitHub job API 回读确认该 job 已完成成功。
- 更早旧断言失败：`41986611189`、`41986776704`、`41986829015`；它们与后续源码/测试纠正前的旧结构对应，不得列为当前版本 PASS。
- 本轮仍未执行 Android Gradle compile、Android JUnit、APK assemble、安装升级、UI 自动化或真机触控/耗电/服务连续性测试。

### 下一批立即实施
1. 继续检查 Hook 目标页中剩余的原始 `ArrayAdapter` / Spinner，按实际业务含义统一 Skin 文本 renderer；避免全局机械替换造成行高/长文案截断。
2. 扩展 Ad / 隐私导入 Activity 的表单、Dialog、列表和加载/空/错误状态 renderer；语义危险色、证书状态、扫描风险色必须保持。
3. 检查五 Skin 切换时页面状态/草稿/滚动恢复及网络服务不中断；继续严格区分 Host 静态回归与 Android/真机验收。


## 2026-11-05 — Frida 脚本库、会话日志、监控事件与代码编辑器接入五 Skin 角色

### 源码改动
- `FxDiaScriptLibraryActivity.java`：
  - 页面标题加入 `fx-title:18`。
  - 导入/导出/新建操作组加入 `fx-card-group`。
  - 动态脚本条目现在使用 `fx-list-row`，脚本名 `fx-list-title`，UTF-8 大小与“不会自动执行”说明 `fx-list-subtitle`。
  - 原有排序、搜索、保存/删除回调和 JSON 数据格式不变。
- `FxDiaSessionLogActivity.java`：
  - 标题、目标身份、状态与筛选/操作容器接入共享 Skin 角色。
  - 刷新/清空操作由共享 `fx-action-row` button helper 提供；原始多行 monospace 日志正文未作换色或内容改写。
- `FxDiaMonitorEventsActivity.java`：
  - 标题、目标身份、状态、过滤控件容器、自动刷新 Switch 和事件数量加入 Skin 角色。
  - 动态事件项改为带 `fx-list-row` 的容器和 `fx-list-subtitle` 文本；仍保留每次最多显示 120 条、筛选条件、点击查看详情和滚动恢复。
  - 事件详情 Dialog 统一使用 `FxNativeSkin.showDialog()`，弹窗仍显示原事件类别和原始白名单元数据。
- `FxDiaCodeEditorActivity.java`：
  - 返回/保存按钮、标题与编辑说明接入 Skin 角色。
  - Sora `CodeEditor` 内容与其语言选择/编辑逻辑保持原样，避免主题适配改写用户代码。
- `FxNativeSkin.java`：将共享 Skin facade 与 `showDialog(Activity, Dialog)` 暴露为 public API，供 `de.privacyguard.adhook.imported.dia` 子包调用。原因是 Java 子包不是同一 package，包级类/方法不能跨子包访问。

### 回归
- 扩展 `scripts/tests/fx-dia-frida-page-navigation-regression.sh`：
  - 检查脚本库动态行、会话日志操作/标题、监控事件行/Switch/详情弹窗、全屏编辑器标题/操作/说明的 Skin 角色。
  - 检查 FxNativeSkin 类和 Dialog helper 为 public，防止跨包访问编译错误。
  - 原有 Frida Hook Hub 入口、debuggable 目标 picker、目标身份传递、日志页面路由、AppEntry observer 元数据-only 检查继续保留。

### 提交
- 脚本库 Skin 角色：`ca39c20020df1237444f16b0b9f9ede9c4bb0695`
- Session Log Skin 角色：`be87e4a4c879e4a799cc0692e0509c26ed37f4c8`
- Monitor Events 角色/详情 Dialog：`2d1bfdbc647dd3aa3b139f9e7c7ced18083bdd68`
- 全屏代码编辑器角色：`a79bc653919b9b42df50f7b951cc70bd13378246`
- FxNativeSkin 跨子包 Dialog API：`eb360b47b7ac87ac2fe2aa87a81f5f8b276e720a`
- Frida 页面 Skin 角色与 public API 回归：`8d4ac461446c104ae07fa51ed016880e155cd415`、`45c68f0322f4adf3c748ba3231027d45e7cb654f`
- 本状态提交的父 HEAD：`fdcfff394753074b49a54f5ba3ebca548d59276d`；状态写入后仍以 GitHub 实时分支 ref 为最新依据。

### 验证边界
- 已完成 GitHub 源码回读：四个页面角色标签存在，脚本库/监控事件动态行均交给对应 Renderer；日志正文与 CodeEditor 组件未被全局 Skin 改写；跨包 Dialog API 已公开。
- 最新定向 Host run `41987810702` 在读取本节时尚未取得 job 记录/最终结论；不得把它当作通过，后续必须读取其最终状态及具体步骤日志。
- 本批未执行 Android Gradle compile、Android JUnit、APK assemble、安装、UI 自动化或真机视觉检查；尚不能声称五种 Skin 的所有 Activity 已逐页完成。


## 2026-11-05 — Ad / Hook 子页弹窗全面接入共享五 Skin renderer

### 实际源码改动
- 统一弹窗渲染底层使用 FxNativeSkin.showDialog(Activity, android.app.Dialog)，同时兼容 MainActivity 使用的 AndroidX AlertDialog 和迁入 Activity 原有的平台 AlertDialog / TimePickerDialog。
- FxNativeSkin.builder(Activity) 是 MainActivity 原生页的共享 AppCompat Builder；FxNativeTabActivity.fxDialogBuilder() 是保留平台 AlertDialog 类型的来源 Activity 兼容 Builder；showFxDialog(Dialog) 用于先创建、设置自定义 OnShowListener 后再显示的弹窗。
- Ad 业务页：
  - FxYulongAdActivity.java：14 个 AlertDialog Builder 改用 fxDialogBuilder()。
  - FxYulongDnsActivity.java：2 个 DNS 日志/缓存确认对话框改用 fxDialogBuilder()。
  - FxYulongFirewallActivity.java：应用防火墙规则编辑器改用 fxDialogBuilder()；自定义按钮保存监听通过 showFxDialog(dialog) 显示；TimePickerDialog 也走 showFxDialog(picker)。
- Hook 业务页：
  - FxDiaFridaActivity.java：16 个 Builder 改用 FX Builder；4 个 create 后添加/保留自定义监听的弹窗改用 showFxDialog()，包括脚本编辑、debuggable 目标选择等。
  - FxDiaDexBrowserActivity.java：3 个 APK/方法选择与详情对话框改用 FX Builder。
  - FxDiaGlobalSettingsActivity.java：3 个 Hook 全局设置确认框改用 FX Builder。
- MainActivity 已有并行改动接入 FxNativeSkin.builder()；当前读回看到约 95 个共享 Builder 调用，且已无直接 new AlertDialog.Builder(...) 残留。该数据是源码字符串计数，不代表每个 modal 视觉验收完成。

### 相关提交
- caf577d19c37ea6b7dac065fe38ca9fc19801d97 — FxNativeTabActivity 平台 AlertDialog Skin Builder。
- cd75fc7418fa46e3d70c54c3babc5adeb5175496 — Ad 控制中心 14 个对话框接入。
- 3475a70118b9ec29d63711a1955492007708f545 — Ad DNS 对话框接入。
- 745f7bf8a0c9aa97d08e3cd4c3f21117e2f7c1a1 — Firewall 自定义 OnShow 对话框接入。
- 4f73213c5107e84cc8688c88bdc2d08b8222cd10 — Firewall TimePickerDialog 接入。
- 4bf1f0351b355566f157cecde5d5d8e3f09eede9 — Dia Frida 16 个 Builder 与 4 个自定义 Dialog 接入。
- 951658fcb55e7e0e33d07ecb68a8338902953cb5 — Dia DEX 浏览器 3 个 Dialog 接入。
- 12c932cc883f0c9a5b997de361ded4cd4224b47d — Dia Hook 全局设置 3 个 Dialog 接入。
- 14cfe1a4dfcc8837e864c374004f17b3c451ccdf — 对话框回归检查对齐公共 Dialog 类型和平台 Builder。
- 88d8254a0b32a2b4909c6846b73b162c4c763689 — Ad 子页共享 Dialog Skin 回归。
- 5aea796a0afcc500873e53e262e5f3367ca4b19a — Frida/DEX/Hook 设置共享 Dialog Skin 回归。
- 当前 HEAD 以 GitHub 实时 ref 为准；以上只列出本批关键提交，不可将它们误认为当前分支 HEAD。

### 验证级别
- 已完成 GitHub 源码读回：共享 builder、AndroidX 与平台 Dialog 公共显示、Ad/Hook 对话框调用点及回归断言均可检索。
- 没有在当前环境执行 bash regression、Android JUnit、Gradle 编译、APK assemble、安装、UI 自动化或真机视觉检查；本批不能标记 CI PASS 或五 Skin 完整验收。
- 当前 commit status/Actions 必须针对最新 HEAD 重新读取；历史 41986350889 只属于它自己的旧 HEAD 和上一批 Skin 静态回归。

### 下一批继续执行
1. 将共享 Dialog renderer 接入剩余 Dia Activity Browser、Inspector、Signature、File/JSON、Backup、Crash Report 与 Wi-Fi Proxy 页面；对自定义 create()/setOnShowListener/show() 保留回调。
2. 将同一 Builder 接入隐私 Shield 高风险确认、白名单/黑名单编辑与扫描详情弹窗，并核验警告/删除/成功语义色不被全局 Skin 改写。
3. 继续给表单、Spinner、搜索框、代码编辑器、空态/加载态打语义 Skin 标记和定向断言；完成一组后检查最新 HEAD 的 Host regression，不要反复触发全套 Actions。



## 2026-11-05 — 用户最终需求清单并入总方案/跨 AI 接管提示词

### 本批文档更新
- 将用户最新明确提出的五 Skin、游龙工具 10.0.2 壁纸、Ad 五层过滤与游龙广告插件、VPN 小火箭类能力/内核级代理共存/防泄漏/低功耗/MITM、隐私与安全护盾、Dia/GKD Hook、代理脚本及浏览器 UserScript/扩展、六 Tab 页面布局统一整理为可逐项验收的最终需求基线。
- 产品方案新增“用户最终需求基线：全功能清单、页面布局与逐项验收”章节。
- 唯一正式跨 AI 接管提示词新增同一批执行门禁；新 AI 必须按功能矩阵实施，不得只更新文档或保留旧来源应用入口。
- 再次明确：设置不得出现“迁移应用”；第二 Tab 只能显示“Ad”；Hosts 仅为 Ad 内部功能页；六 Tab 固定 VPN、Ad、隐私、脚本、Hook、设置。
- 明确 Hook VIP 只能用于合法授权/自有应用 entitlement 测试；位置模拟仅用于用户授权测试；Root/模块/LSPosed 不承诺绝对隐藏；系统 CA/MITM 不承诺所有 App 无警告；Android Always-on 不承诺零耗电。
- 本批仅更新 MD 需求和执行方案，不代表上述功能已全部实现或真机验证。

### 本批提交
- 产品规格与页面布局：本批已提交，见同分支最新产品方案。
- 唯一正式接管提示词：本批已提交，见同分支最新接管提示词。
- 本状态文件：本次提交。

### 当前验证边界
- 文档写入后需回读并检查六 Tab、Ad-only、Settings 无迁移应用、五 Skin、壁纸、所有功能域与安全边界关键词。
- 本批不执行整套 Actions，不声称 Gradle、APK 或真机验证。


## 2026-11-05 — Shield / Dia 剩余弹窗接入共享 FX Skin

### 实际源码改动
- Dia Wi-Fi Proxy 页面 `FxDiaWifiProxyActivity.java` 剩余 3 个确认对话框改为 `fxDialogBuilder()`；继续保留平台 AlertDialog 类型与原来的系统代理确认/恢复操作回调。
- Shield 主控制中心 `FxYulongShieldActivity.java` 的 6 个平台 AlertDialog Builder 改为 `fxDialogBuilder()`。
- 复核 Shield 关联页：
  - `BlacklistActivity.java`：4 个 FX Builder，1 个自定义 OnShow Dialog 使用 `showFxDialog(dialog)`。
  - `FxYulongScanActivity.java`：1 个 FX Builder。
  - `FxYulongBatchCleanupActivity.java`：1 个 FX Builder。
  - `FxYulongWarningActivity.java`：3 个 FX Builder。
  - `FxYulongRescueActivity.java`：2 个 FX Builder。
  - White/Blacklist picker 页面本身未检出平台 AlertDialog Builder；不代表其列表/表单视觉覆盖已完全验收。
- 扩展 `scripts/tests/fx-unified-navigation-regression.sh`：
  - Dia ActivityBrowser / Inspector / Signature / File / CrashReport / Wi-Fi Proxy 均要求 FX Builder 且禁止遗留直接 Builder；ActivityBrowser 自定义 Dialog 要使用 `showFxDialog`。
  - Shield 中心、Blacklist、Scan、Batch Cleanup、Warning、Rescue 要求 FX Builder 且禁止平台 AlertDialog Builder；Blacklist 的自定义 OnShow Dialog 要调用共享显示入口。
- 既有 Ad / Hook / Dia Frida Dialog 检查继续保留；主 Activity 约 95 个对话框路径使用共享 Skin Builder。

### 关键提交
- `e0a5b7150cbe3cf642e9e83ee657fb7bd39428ff` — Dia Wi-Fi Proxy 3 个对话框改为 FX Builder。
- `cb9e464b4dace6d3b30b3f9d37de1ca4439d92fb` — 剩余 Dia 页面弹窗回归。
- `8898bef2ed0ecb6e4207974705e3eb17133f49ba` — Shield 主控制中心 6 个对话框改为 FX Builder。
- `dd16f847f3948a5ba0a617f2f4c76ac1cfdd296a` — Shield 弹窗专项静态断言。
- 上述为具体变更提交，不代表当前分支 HEAD；新窗口必须重新读取 HEAD。

### 验证级别
- 已完成目标源码和脚本的 GitHub 回读核对：本批覆盖文件中不再存在直接 `new AlertDialog.Builder(this)`；Shield 主页面为 6 个 FX Builder，Dia Wi-Fi Proxy 为 3 个 FX Builder。
- 当前环境没有运行回归 Shell、Gradle/JUnit、APK 构建、安装、UI 自动化或真机触控/视觉检查；本批只能标记为源码写入 + GitHub 回读，不是测试 PASS。
- Actions 的历史 run `41987810702` 对应更早 HEAD `4bf1f035...`，最终 `cancelled`；不可当作本批通过。对最新 HEAD 必须重新查询状态。

### 下一批直接实施
1. 检查 Shield 的扫描结果、风险详情、Stellar 子树、名单管理和 Rescue 页面自定义 Dialog/PopupWindow/BottomSheet；保留危险操作语义色与原回调。
2. 检查 Dia Backup / JSON / Inspector / Signature / Activity Browser / Wi-Fi Proxy 的剩余自定义弹窗与空/加载/错误状态，继续用共同 Dialog Renderer。
3. 继续把共享 Skin tokens 接到未覆盖的表单、Spinner、搜索、多行编辑器和列表；有新的动态页时增加最小回归覆盖。


## 2026-11-05 — Shield / Dia 非主页面弹窗覆盖补齐

### 实际实现
- Shield 主中心 `FxYulongShieldActivity` 的 6 个确认/权限提示框已切换为 FX Builder。
- Shield 子页当前回读情况：Blacklist 4 个 Builder + 1 个 `showFxDialog` 自定义 OnShow；Scan 1 个 Builder；Batch Cleanup 1 个；Warning 3 个；Rescue 2 个；Screen Filter 2 个。Virus Database、Daily Summary、Integrity、Whitelist、Whitelist Picker 当前未发现独立 AlertDialog Builder / Dialog / PopupWindow 自建入口。此结论为本次源码关键字和类内容核对，不替代完整运行时 UI 覆盖。
- Dia 子页继续补齐：
  - `FxDiaMonitorEventsActivity`：监控详情使用 FX Builder，显示转发给 `showFxDialog`。
  - `FxDiaSessionLogActivity`：清空当前目标 Frida 日志确认框使用 FX Builder。
  - `FxDiaSystemExpandActivity`：3 个确认/状态弹窗使用 FX Builder；安装来源 picker 创建后用 `showFxDialog(pickerDialog)`。
  - `FxDiaScriptLibraryActivity`：4 个 Builder 使用 FX Builder；新建脚本对话框创建后使用 `showFxDialog(dialog)`，保留原取消状态清理监听。
- Dia Wi-Fi Proxy 的 3 个系统代理确认框已接入；剩余 Activity Browser / Inspector / Signature / File / Crash Report / Wi-Fi Proxy 均在导航回归中加入 Builder 门禁。
- `scripts/tests/fx-unified-navigation-regression.sh` 现在覆盖 Shield 主中心及五个子页，以及 Frida、DEX、Hook 设置、Activity Browser、Inspector、Signature、File、Crash Report、Wi-Fi Proxy、Monitor Events、Session Log、System Expand、Script Library 的共享 modal builder 路径和自定义显示路径。

### 关键提交
- `8898bef2ed0ecb6e4207974705e3eb17133f49ba` — Shield 主控制中心 6 个 AlertDialog 改用 FX Builder。
- `dd16f847f3948a5ba0a617f2f4c76ac1cfdd296a` — Shield 弹窗专项回归。
- `e0a5b7150cbe3cf642e9e83ee657fb7bd39428ff` — Dia Wi-Fi Proxy 3 个系统代理确认框改用 FX Builder。
- `d96c19d96f128a1cd63394f63f2fed737e700bda` — Monitor Events 详情弹窗统一。
- `5bf93c8411d763ef360eda5ddf030164fff34879` — Session Log 清理确认框统一。
- `5302a8a501d8c237fa19b9d3ea56ea4090e533d4` — System Expand 弹窗和安装来源 picker 统一。
- `5c46c9a90ae0c79bff69c56c3754b821a432679f` — Frida Script Library 创建/导入/删除对话框统一。
- `2131778f18b7843a81bdfb8f5581c6fd7b3e05ee` — Dia Monitor / Session / System Expand / Script Library modal 回归。

### 验证边界
- 已完成 GitHub 源码回读确认上述调用路径及回归断言存在；没有在当前工具环境执行 Shell regression、JUnit、Gradle 构建、APK 安装、UI 自动化或真机视觉验收。
- 不能把“直接 Builder 关键字消失”写成弹窗视觉通过；仍需检查 AndroidX/platform Dialog、键盘弹出、长文本滚动、无障碍读屏、按钮语义色和屏幕尺寸。
- 当前分支 HEAD / CI status 必须实时读取；不能沿用早前被取消的 Host run 或把旧 HEAD 的成功当成本轮通过。

### 下一批
1. 继续核对 Shield 页面自定义菜单/弹窗以外的表单、搜索、加载/错误状态和动态列表行，优先标记剩余非语义控件。
2. 继续检查 Dia / Hook 文件/签名/Inspector 页面里的自定义 PopupWindow、系统选择器、AlertDialog 以外的 Dialog 子类。
3. 针对最新 HEAD 跑定向 Host regression；若自动触发 Actions，读取实际 job 结果并区分 Host / Gradle / 真机级别。



## 2026-11-05 — 新增 qufz / AntiFraudBlock 隐私功能来源审计

### 已完成
- 核验来源仓库 `vip-svip/qufz` 的 main 分支、README、LICENSE、递归文件树、`MainHook.java`、Manifest、Xposed metadata 和 `docs/REVERSING.md`。
- 确认它是 OPPO/ColorOS 手机管家专用 LSPosed/libxposed modern 模块：目标包 `com.coloros.phonemanager`；API 102（min 101）；minSdk 33；MIT 许可。
- 确认其阻断路径为 `AiDetectStatistics` static void 埋点、`AiVoiceDetectDCSUtils.m/n` 云端 DCS 上报、`TrackApi.E` 对 appId 20092 的反诈事件兜底；保留本地风险服务、通知、弹窗和记录。
- 用户已指定归属 FX 第三 Tab「隐私」，入口规划为「反诈遥测保护」。

### 尚未完成 / 不得误报
- 尚未把 qufz 源码迁入 FX 仓库或统一 LSPosed 模块。
- 尚未建立隐私 Tab 实际 UI、模块总开关、目标设备检测、Hook 状态回读和紧急透传控制。
- 尚未执行 FX Host 回归、Android 编译、APK/LSPosed 模块构建、支持设备真机拦截和本地反诈功能回归。
- 适用性目前仅有来源仓库记录的 RMX5200 / ColorOS 16 / Android 16 / PhoneManager 17.1.6 实测；其他系统版本必须逐项兼容核验。
- 当前状态只能标记为「来源审计完成、需求登记完成、代码迁移未开始」，不得把仓库已有 APK 视为 FX 集成产物。

## 2026-11-05 — Host 回归失败根因修复与后续成功证据

### 失败记录（不隐藏中间失败）
- run 41988885927，HEAD 5c46c9a90ae0c79bff69c56c3754b821a432679f，失败于 fx-dia-frida-page-navigation-regression.sh：该脚本仍要求 Monitor Events 直接调用 FxNativeSkin.showDialog(this, dialog)，而实现已经统一为 FxNativeTabActivity.showFxDialog(dialog)。已将过时断言改为新 helper，并保留 public Skin/Dialog API 可见性检查。
- run 41989189687，HEAD 81828e8b74127196bec390b8d7cc6f5f78645c08，失败于 fx-yulong-shield-six-tab-regression.sh：旧测试固定要求 FxNativeAppShell.kt 存在 .height(72.dp)，但五 Skin 已切换为 tokens.tabBarHeightDp.dp；同时该脚本仍引用已重命名的 handleImportedNativeTabIntent。已改为验证 token-driven geometry：Classic 60dp、Liquid 72dp、Miuix 68dp、Harmony 72dp、Cupertino 76dp，并更新为 handleNativeTabIntent。
- 更早 run 41988567924 的失败为测试脚本在新 Ad modal 断言前引用了尚未赋值的 ad_main（NameError）；后续 35d6b146 已调整加载顺序，并在后续 run 中通过相关路径。

### 修复后的成功证据
- run 41988961088，HEAD 2131778f18b7843a81bdfb8f5581c6fd7b3e05ee，Host job host-regressions = success；通过六 Tab / Settings 边界相关回归。
- run 41989284497，HEAD 4ab6f7d6b9bb3e080a4a382d188672a11d5a8dbe，Host job host-regressions = success；日志显示 Dia Frida SAF 脚本库、二进制导入、Gadget 配置/部署/会话、服务器生命周期及 fx-dia-frida-page-navigation-regression.sh 全部通过。
- run 41989495360，HEAD f1f8295ef1a9108a86f16584757eae20098b25c1，Host job host-regressions = success；日志明确显示 fx-yulong-shield-native-regression.sh、fx-yulong-shield-six-tab-regression.sh 和 Shield worker-bound 回归通过。
- 以上是指定 commit 的 Host regression 成功证据，不是当前分支 HEAD 的 CI badge，也不是 Gradle/Android JUnit/安装/真机验收。


## 2026-11-05 — Shield 全页面组件 Skin 补齐、SeekBar renderer 和 Host 通过

### 本批实际实现
- Shield Scan：页标题标记 `fx-title:18`；扫描状态与结果已有卡片/section role；复用 action helper 的 `fx-action-row`，避免对局部按钮重复设置不必要的独立 tag。
- Shield Warning：风险详情页标题标记 `fx-title:18`；原有风险等级、包名、命中理由等语义角色和危险色保留。
- Shield Screen Filter：
  - 页标题、卡片、卡片标题/描述、动作按钮、主开关、音量键开关均接入 Skin role。
  - 亮度/对比度/饱和度/色温滑杆增加 `fx-seekbar` role，值说明为 `fx-card-detail`。
- Shield Virus Database：
  - 页标题、动作按钮、同步卡片、状态/摘要文本接入 Skin role。
  - 远程名单动态列表行标记 `fx-list-row`；名单名/状态/源 URL 分别标记 `fx-list-title`、`fx-list-subtitle`、`fx-card-detail`。
- Shield Integrity：
  - 页标题与签名/模块完整性/迁移边界分区接入 Skin role。
  - 签名报告、模块状态使用卡片正文/详情角色；迁移边界的橙色警告文本保留原语义颜色。
- 共享 `FxNativeSkin` 新增真实 SeekBar renderer：
  - 按当前 Skin 的 palette accent 设置 progress 和 thumb tint；
  - 用 inputBorder / switchOffTrack 设置背景轨道颜色；
  - 使用 WeakHashMap 按 View 记录模式，避免每次 layout 重复覆盖。
- ScreenFilter 页面操作回调、权限提示、滑杆存储和即时 APPLY 行为没有改动；VirusDB 动态列表的数据源和后台 worker 没有改动；Integrity 的 Root 只读检查和安全限制没有改动。

### 相关源码/测试提交
- `4274b8a3389cce8eb42b22a19525a329fdd719b2` — Shield Scan page title role。
- `ea19d6813836689c6455389d7cf5b102edaac0ca` — Shield Warning page title role。
- `4a6d0229f807e339b8eaca4ce84ff8cbbb3ae776` — Screen Filter cards/actions/switches/SeekBar tags。
- `b45b9ba6bb47db5dd46ac8865ab197db060931c6` — Virus Database cards and dynamic row roles。
- `4e8ae6a2f4597dd7b1b7736d250e94c23e09d332` — Integrity report title/sections/actions/body roles。
- `2fd53d9d60e38cf024312fe8c993c74c17796158` — shared SeekBar renderer consumes Skin palette.
- `c3948103311729ab0b4f1bc0e57cd77fa036d36d` — Shield six-tab/component role assertions; initial run exposed assertion mismatch described below.
- `569ae9262323cbdebd3f93abac0de03b87974d41` — shared Dialog host assertion changed from AlertDialog-specific parameter to android.app.Dialog.
- `403399854802fdda0d1d089300a1b33074aa9579` — Scan regression changed to verify its actual shared action helper tag rather than requiring a per-field tag.

### Host regression failures and correction
- run `41991117851` failed because `fx-global-ui-modes-regression.sh` still expected `showFxDialog(AlertDialog)`; actual shared host correctly exposes `showFxDialog(Dialog)` to support platform AlertDialog and TimePickerDialog. Updated the assertion to the shared base type.
- run `41991210394` failed because the Shield regression expected `scan.setTag("fx-action-row")`; the real page creates the scan button with `scan = action(...)`, and that action helper sets `fx-action-row`. Updated the regression to assert the helper and its use.
- run `41991591436` was cancelled during replacement by the next targeted push; this was not a source/test failure.
- run `41991611129`, HEAD `403399854802fdda0d1d089300a1b33074aa9579`, Host job `host-regressions = success`. Its log shows the global five-Skin regression, unified navigation regression, Shield native feature regression, Shield six-tab/component-role regression and Shield worker-bounds regression all passed.
- This is Host regression evidence for the named commit only; no Gradle assemble/JUnit, APK install, UI automation, or device visual review was performed in this batch.

### 下一批
1. Continue Skin-role coverage across the remaining Shield subpages (especially whitelist picker, warning detail rows and dynamic scan result rows), while preserving risk/success colors and accessibility semantics.
2. Apply shared SeekBar/Form renderer to other FX pages that expose sliders or native form widgets; do not create page-local color maps.
3. Inspect Dia/Hook file, JSON, signature, Activity Browser and backup pages for remaining PopupWindow/custom Dialog paths, then add targeted regression assertions and run a bounded Host batch.

## 2026-11-05 — 权威需求纠偏：默认模式、VPN 多实例、系统应用部署与容量边界

本节是当前需求基线纠偏，不代表相应功能已实现。此前状态记录中“全局 Skin 由三种扩展为五种”“五种模式”等文字属于当时的历史进度；从本节起，产品目标统一为 **六种界面模式 = 独立默认模式 + 五种可切换皮肤**。不得再将液态玻璃称为默认模式。

### 六种界面模式
- 默认模式 `default`：FX 自有标准原生基础界面，首次安装默认选中，独立 renderer/tokens。
- 五种皮肤：旧网页 `classic`、液态玻璃 `glass`、Miuix `miuix`、HarmonyStyle `huawei`、CupertinoStyle `ios`。
- 首次安装默认 `default`；旧有效 ID 保留原映射；未知/损坏 ID 回退 `default`。
- 六种模式全部覆盖六 Tab 和二级页面；换肤不得重启后台服务。当前实现状态仍须以源码、测试和本文件后续验证记录为准。

### VPN 共存目标分层
- 标准 Android 同一用户/配置文件通常只有一个活动 VpnService/VPN 接口；普通 APK 或仅有 KernelSU/Magisk 模块不能自动增加系统 VPN 槽。
- 真正多个 Android 系统 VPN/VpnService 同时运行属于 ROM/AOSP Framework/厂商能力，需要 VPN 管理、ConnectivityService/netd、接口生命周期、per-UID 路由和系统 UI 等集成及设备验证。
- FX KernelSU/Magisk 内核级代理应独立于 VpnService 槽，使用设备支持的 netfilter/TPROXY/policy routing/fwmark/UID 等路径，并与第三方 VPN 做真实路径兼容测试。
- 两条路线分开报告，不能把 FX 内核代理与第三方 VPN 共存误报为 Android Framework 多 VPN 已实现。

### 其它此前未完整写明的硬要求
- 本地 DNS 是独立服务，有自己的生命周期、配置、开关、状态、缓存、日志和回退，不依赖代理节点或 FX VpnService。
- 安装 KernelSU/Magisk 模块时自动部署 FX APK 为系统应用，优先 systemless overlay；系统应用/特权应用的签名、privapp allowlist、SELinux、升级、卸载和回滚必须分别处理。放入 system 分区不自动获得平台签名或所有特权权限。
- 不人为设置 APK、模块、源码、功能、插件、规则、订阅、脚本或内核数量/体积上限；只处理真实设备资源和 Android/内核硬限制，采用分页、按需加载、模块化和缓存。
- Safe Execution Boundaries 已纳入产品规格与正式接管提示词；高风险/不可逆设备操作须先确认，保护凭据和用户现有 VPN/DNS/路由。

### 本次文档纠偏的安全边界
- qufz 只保留公开源码研究、权限/数据流透明审计和官方用户控制说明；不迁入阻断反诈遥测、风险判定、告警、举报/求助或安全处置通信的 Hook 逻辑。
- 本节是需求/文档纠偏，不代表六种模式、Framework 多 VPN、内核代理共存、系统应用部署或本地 DNS 已实现/通过设备测试。

### 本轮额外查出的来源清单遗漏
此前主方案和正式接管提示词未逐字登记五份来源压缩包，也未明确写出旧 Hook APK 的统一合并对象。现补入权威要求：
- `Dia_23.11_src.zip` → Hook；
- `GKD-XA_1.4.8_src.zip` → Hook；
- `_10.10.62_src.zip` → VPN / Shadowrocket 源码，不能归入游龙广告；
- `_7.0.1_src.zip`、`_9.9.60_src.zip` → Ad / 游龙广告版本差异。
- `PrivacyGuardHook.apk` 与 `FXAdHook.apk` → 合并为单一 FX Hook 入口、统一配置/生命周期和原生 UI。
压缩包是否已取得、读取和迁移，仍必须由后续实际文件证据分别确认；写入需求不等于已完成迁移。

## 2026-11-05 — 旧 AntiFraudBlock 执行计划正式废止（安全边界纠偏）

此前本状态文档第 4583 行附近将 qufz / AntiFraudBlock 描述为“反诈遥测保护”，并记录 `AiDetectStatistics`、`AiVoiceDetectDCSUtils`、`TrackApi.E` 的拦截路径及 Hook 实现计划。**这些内容仅保留为历史来源审计记录，不再是 FX 的有效功能需求或开发任务。**

从本节起：
- 不得迁入、实现、启用或测试用于拦截反诈遥测/云上报、风险判定、检测、告警、举报/求助或处置通信的 Hook/网络规则。
- 不得使用 `AiDetectStatistics`、`AiVoiceDetectDCSUtils`、`TrackApi.E` 等历史分析符号作为 FX 执行拦截的实现依据或验收断言。
- 允许的功能仅为本机实际存在组件的透明识别、权限/AppOps 状态说明、平台允许的服务/进程可见信息、经授权的通信元数据审计、官方设置跳转及脱敏诊断。
- 用户没有安装且不会安装国家反诈中心 App；不得要求安装，不得伪造该 App 的本机状态或数据。仅检测本机实际存在的厂商组件；不存在时明确标记“本机未安装/不可观测”。
- 历史的“反诈遥测保护”入口规划、模块总开关、Hook 状态回读、拦截回归等任务全部标记为**已废止，不得继续执行**。
- 这项纠偏不删除原始历史记录，但本节优先级高于此前记录；后续 AI 必须以当前产品规格和正式接管提示词为准。

本次文档修订状态：需求纠偏已写入产品规格、正式接管提示词和实时状态文档；这不代表其他 FX 功能已实现或通过设备测试。


## 2026-11-05 — 六种全局界面模式纠偏（独立 Default + 五种皮肤）

- 从源码发现并修复一个与最新权威需求冲突的实现缺口：`FxUiMode` 仍只有五个枚举项，缺省/未知值回退 `classic`，设置页仍写“五种模式”；Default 并未作为独立 renderer 存在。
- 已提交的代码变更：
  - `6f44a3f` — 新增首位 `DEFAULT_STANDARD/default/NATIVE_DEFAULT`；首次无偏好、null 和未知/损坏值回退 `default`；历史 `classic/glass/miuix/huawei/ios` 继续原样映射。
  - `a2e8b7e` — 设置页增加 Default 首项并更新为六种模式。
  - `7f5e6ac` — 新增独立 Default Compose shell tokens，Classic 显式保持 Classic renderer；Default 66dp、Classic 60dp、Glass 72dp、Miuix 68dp、Harmony 72dp、Cupertino 76dp。
  - `1186f2c` — Android View Skin palette 为 Default 增加独立分支。
  - `7092db5` — MainActivity 默认 ID 和默认模式颜色/圆角/导航强调色改为 Default。
  - `504bf41` — 单元测试改为断言六项稳定顺序、Default 独立 renderer、未知/空值安全回退和五个旧皮肤 ID 保留。
  - `956a1a1` — 全局 UI 回归增加六项枚举/设置卡顺序、Default token 和独立 palette 检查。
- 影响文件：`FxUiMode.kt`、`FxDesignModePanel.kt`、`FxComposeSkinTokens.kt`、`FxNativeSkin.java`、`FxUiModeTest.kt`、`MainActivity.java`、`scripts/tests/fx-global-ui-modes-regression.sh`。
- 版本保持 `versionName=1.0.0/versionCode=10000`；未生成 APK/模块。
- 验证状态：已通过 GitHub API 回读逐文件检查提交内容（回读验证）；尚未执行 Shell regression、Kotlin/JUnit、Android Gradle compile/assemble、UI 自动化、模拟器或真机测试。不得把源码回读称为测试通过。
- 下一步：读取最新分支 HEAD 与 workflow 权限/状态，执行可用的定向 Host regression；随后继续检查六种模式在所有迁入 Activity 的覆盖，尤其 Default/Classic 的 renderer 分离与服务不重启行为。


## 2026-11-05 — 六模式源码回读后的编译缺陷修复

- 回读目标分支时发现 FxUiMode.kt 的 DEFAULT_STANDARD 常量曾被写入 enum 构造参数列表，导致 Kotlin enum 声明结构不合法；不能仅凭设置页/脚本中的字符串断言认定实现完成。
- 已直接修复并提交：
  - 2e6ad2f7017f2dcfb38e1a242700e1f1397ddfef — 将 enum 构造参数恢复为 storageId/title/description/renderer，把 DEFAULT_STANDARD 放回 enum entry 列表首位。
  - 2a6fe84b79184367289adc89a5b8a988bec07324 — Compose tokens 测试覆盖 Default 66dp 独立几何、Classic 60dp 旧网页几何、Default/Classic 不相等以及未知模式回退 Default。
- 已通过 GitHub 回读验证 enum 声明、Default 首项、六个稳定 ID、缺省/未知值回退、独立 Default Compose tokens、Classic 显式分支、Android View palette、MainActivity 默认 ID、六项设置卡和回归脚本中的 Default 断言；本次静态断言 14/14 通过。
- GitHub commit workflow 查询未返回可读取的 PR workflow runs；当前不能声称已执行仓库 Shell regression、Kotlin/JUnit 或 Gradle 编译。后续仍需在可用 CI/构建环境实际运行 scripts/tests/fx-global-ui-modes-regression.sh、Android 单测和 Gradle compile/assemble。
- 本次没有修改版本号、网络服务生命周期或既有用户配置；没有生成 APK/模块，也没有真机测试。


## 2026-11-05 — KernelSU/Magisk FX Hook 系统应用部署路径

- 源码确认此前真实安装链路仍把 `FXUnifiedHook.apk` 放在 `optional/`，由开机服务调用 `pm install -r` 安装为普通 `/data/app` 应用；这不满足“模块安装自动部署系统应用”的要求。
- 已实施：
  - `scripts/install_adhook_app.sh` 优先使用 `system/app/FX/FX.apk`，保留旧 `optional/FXUnifiedHook.apk` 作为兼容 fallback。
  - 安装 helper 检查 `pm path` 的 system/product/vendor 路径及 `pm list packages -s` 系统应用分类；已由系统 overlay 提供且 SHA-256 一致时不再执行普通安装。更新系统应用若 PackageManager 将更新 APK 存于 `/data/app`，则保留 system-app 分类并沿用原更新路径。
  - overlay 不可见时才执行原有安全的普通 APK 安装路径，并明确记录降级日志；原有签名冲突回滚、FX ownership marker 和不卸载用户应用逻辑保留。
  - `fx-module/scripts/install_adhook_app.sh` 与根目录 installer 已同步，字节一致。
  - `scripts/tests/adhook-app-installer-regression.sh` 新增 updated-system-app 检测 fixture，并保留普通安装 fallback、签名冲突回滚、ownership-safe uninstall 与 stale marker 测试。
  - `.github/workflows/build-fx-adhook.yml` 在受控 APK 构建步骤将同一 APK 同时放入 optional fallback 与 `fx-module/system/app/FX/FX.apk`，生成 SHA-256，并把 overlay 纳入 module-source audit artifact。
  - `adhook/README.md` 已更新安装、升级、降级和权限边界说明。
- 设计边界：使用 `system/app` 而不是 `system/priv-app`。这会使 APK 成为系统应用，但**不会**伪造平台签名或授予 privileged 权限；无需为普通权限创建 privapp allowlist。SELinux 依赖 KernelSU/Magisk 对 systemless overlay 的正常标签/挂载处理，不关闭 SELinux、不安装 permissive 策略。
- 安装/升级仍需设备 PackageManager 在重启时扫描 overlay。ROM 不支持或 overlay 未挂载时会降级为普通应用并明确记录，不能宣称该设备已系统应用部署成功。
- 验证：已从 GitHub 回读 installer 根副本与模块副本，确认字节一致；回读测试 fixture、构建 workflow 和 README，确认 overlay staging、SHA、系统应用识别和 fallback 路径存在。Host regression、Gradle 构建、APK 签名/安装、KernelSU/Magisk 真机挂载与 SELinux/开机扫描尚未运行。
- 本批没有创建或覆盖 Release APK/KernelSU ZIP；没有执行设备安装或修改设备分区。


## 2026-11-05 — FX APK systemless system-app 安装链回归补强

- 继续回读现有安装链，确认 APK 构建工作流把同一份 FX Hook APK 同时放入 optional 兼容载荷和 system/app/FX/FX.apk，生成 overlay SHA-256；KernelSU/Magisk boot service 在启动完成后调用 install_adhook_app.sh。
- 安装器按 PackageManager 系统包分类和 PackageManager 返回的实际 APK 路径校验摘要；系统 overlay 已可见时跳过 pm install，系统更新版位于 /data/app 时保留 system-app 分类并原位升级。仅当 ROM/overlay 不可见时才记录降级并安装普通 /data/app 副本。卸载时不把 overlay 当普通用户包卸载，交由模块卸载/卸载挂载处理。
- 这是一种 system/app 系统应用，不是 priv-app：APK 未平台签名，不能因此获得 signature/privileged 权限；不关闭 SELinux。Overlay 可见性、标签、PackageManager 扫描和卸载后行为仍需具体设备/ROM 验证。
- 已扩展 scripts/tests/adhook-app-installer-regression.sh，要求回归检查 build workflow 的 system/app APK staging、0644 文件模式、SHA-256、非 priv-app 权限边界、启动服务部署、PackageManager 系统包识别和安装器按实际 APK 路径验签：
  - 6001fb44dcf5e65f44bba317d23ee6532b70fedc — 增加 system-app overlay 构建/启动部署断言。
  - 041527b821ecf19dfb8ae003cc1b121f0ab4645e — 对齐当前安装器的 PackageManager 实际路径摘要验证逻辑。
- GitHub 回读静态检查 10/10 通过；未执行该 Shell 测试、Android PackageManager 真机验证或 SELinux 标签检查。不得将静态回读称为设备安装验收。


## 2026-11-05 — VPN 页面增加 Android 活动 VPN 接口只读诊断

- 在 FX 原生 VPN 控制卡增加只读 Android VPN transport 状态：通过 ConnectivityManager.getAllNetworks() + NetworkCapabilities.TRANSPORT_VPN 统计当前可见的活动 VpnService 网络；无活动网络时明确说明这不代表设备未安装 VPN 应用。检测结果在页面初始化及后端状态同步时刷新，不创建额外轮询器、不修改路由。
- 明确标注 FX Root 内核代理不占用 Android VpnService 名额，并说明与其他 VPN 的流量兼容性仍受 ROM、UID 路由、DNS、TUN 和策略规则影响。检测接口不识别具体 VPN 所属应用，也不证明多个 VpnService 可以并行。
- 修正旧状态文案把 root_proxy_on 描述为“第三方 VPN / Root DNS 保护正在运行”的错误归因；现在只显示 FX Root 网络代理保护状态。AndroidManifest 已有 ACCESS_NETWORK_STATE，且当前 APK 未声明 android.net.VpnService/BIND_VPN_SERVICE。
- 提交：
  - cf4aba297fdfae1b651ab3c85b8298b9f65a14f8 — 增加活动 Android VPN transport 诊断并纠正状态标签。
  - 1cb631109b1bfea5f3ffddeca28403c389bdfb59 — 加入 VPN 诊断静态回归断言。
  - 756181ff9bae1742f16d520fd43fa531a45344e3 — 明确断言 FX APK 不注册 VpnService。
- GitHub 回读静态检查 10/10 通过；未运行 Shell/Gradle 测试、未在设备上与第三方 VPN 做真实数据面共存测试。该改动是检测与产品透明度补强，不是多 VpnService 或 TPROXY/UID 路由兼容验收。

## 2026-11-05 — Android VPN / Root DNS 状态文案纠偏与 Host 回归

- 回读 MainActivity.handleLegacyVpnShortcut() 发现无节点 fallback 分支启动 FX Root Proxy 后，成功提示曾写成“已通过第三方 VPN / FX Root DNS 启用网络保护”。该提示把 FX Root DNS 服务与第三方 Android VpnService 状态混在一起，可能误导用户以为第三方 VPN 已连接。
- 已修正：3bca5a03b8d5341903be01685f5636e2362bb06e，提示改为“已启动 FX Root Proxy DNS 保护（不代表第三方 VPN 已连接）”。
- 已增加防回归断言：b2d25b2c51cce0e243900be28d7e83fefb1c513a，同时拒绝旧文案并要求新文案明确区分服务归属。
- 已通过 GitHub API 回读确认两个文件的最新 blob SHA 与新文案/断言一致。
- 对应 FX Targeted Host Regression workflow run 42007424220 已完成，结论 success；运行链接：https://github.com/vip-svip/SY/actions/runs/42007424220
- 同一分支此前 42007316576（FX 内核代理不占 Android VpnService 名额的断言）和 42007234671（活动 Android VPN transport 诊断断言）也为 success。
- 验证边界：这些是 Host regression 成功，不是 Android Gradle 编译、APK 构建、模拟器或真机 VPN 共存测试。ConnectivityManager.TRANSPORT_VPN 只能统计当前可见活动 VPN 网络，不能证明具体 VPN 应用身份、UID 路由可兼容或多 TUN 能同时稳定工作。
## 2026-11-05 — Dia 全局设置回归修复与 Host CI 通过

- 根据 GitHub Actions job log，`scripts/tests/fx-dia-global-settings-registration-regression.sh` 首次失败不是运行时代码缺陷，而是测试断言与当前实现脱节：
  - `MainActivity.refreshHookHubLsposedStatus()` 中 `active_tip` 的 `getSharedPreferences(...).getBoolean(...)` 调用合法地跨行排版；原断言错误要求连续单行文本。
  - Dia 全局设置页的真实动作标签是“重启 LSPosed 框架服务”，旧断言仍要求“快速重启系统”，与当前明确的服务级操作名称不符。
- 已修正测试：将 Java 源码断言改为去除空白后匹配，避免格式差异导致误报；动作断言改为真实 UI 标签，不更改框架重启行为或降低安全检查。
- 相关提交：
  - `399c8df4cf43b9a884ac18d49af88164291612f6` — 规范化 active_tip 源码断言。
  - `885b5e317ad26d508f8903d3e929a5a88348bba6` — 对齐框架重启动作标签。
  - `9ddb49d8535292a50255c629f795522e1745d008` — 更新 LSPosed 状态提示刷新路径。
- 最新分支提交 `9ddb49d8535292a50255c629f795522e1745d008` 对应 FX Targeted Host Regression run `42010843009` 已完成，结论 `success`： https://github.com/vip-svip/SY/actions/runs/42010843009
- Android APK/KernelSU 构建没有在本轮执行：`.github/workflows/build-fx-adhook.yml` 只允许 workflow_dispatch 或 PR 触发，且 APK 构建还受迁移完成验收门控；KernelSU 最终打包 workflow 也要求显式 workflow_dispatch 且 migration_complete=true。不能在未完成全部迁移验收时伪造该输入。
- 本次 CI 是 Host regression，不等于 Android Gradle compile/assemble、APK 安装、KernelSU/Magisk overlay、SELinux 或真机验证。后续应继续 VPN/本地 DNS 的数据面共存与恢复测试，并完成所有迁移验收后再按仓库工作流授权构建。


## 2026-11-05 — Root Proxy 与独立本地 DNS 引擎生命周期隔离

- 发现的真实缺陷：`fx-module/scripts/yulong-root-proxy.sh` 的 `_stop_engines()` 无条件停止 AdGuard Home 和 Unbound。两者同时也是独立本地 DNS 功能的共享 resolver；关闭外部 VPN DNS fallback、故障 fail-open 或 Root Proxy stop 时，可能连带中断仍单独启用的本地 DNS。
- 已直接修改 `fx-module/scripts/yulong-root-proxy.sh`：停止 Root Proxy 时只清理 FX 自己的 DNS 重定向链；分别读取 `dns_engine_adguardhome` 与 `dns_forward`，独立引擎仍启用时保留对应守护进程，只停止不再被独立 DNS 配置使用的引擎。
- 已扩展 `fx-module/scripts/tests/v1.0.0-yulong-root-proxy-lock-regression.sh`：加入 Package config `pg_get` fixture 和引擎 stop 记录，覆盖两个独立 DNS 引擎均启用时不停止、仅 AdGuard Home 启用时只停止 Unbound、仅 Unbound 启用时只停止 AdGuard Home；保留原有锁文件并发、陈旧锁和旧目录迁移用例。
- GitHub 提交：
  - `ea4c36e5b990001c305d314b5cf83cb1355a8c8a` — `fix(vpn): preserve independently enabled local DNS engines`。
  - `30a142302c5406556ef97cc393a78bb7f47428ca` — `test(vpn): cover independent local DNS engine ownership`。
  - `10279a4182e01d96960af03626ba45282672a386` — 修正新增 Host fixture 的 POSIX shell 参数展开。
  - `83fa0617fbe8c63e8644ffa6bc9d1abecb9aeda4` — 将 DNS 设置键放在 canonical settings 全局段，避免 fixture 误用列表段布局。
- 已通过 GitHub API 回读验证源码和测试文件的新 blob SHA、独立 DNS 分支判断、三组引擎生命周期断言及测试 fixture。回读是静态核对，不等于测试执行。
- 另在隔离 Host shell harness 中执行共享引擎停止策略的三种配置组合：两引擎均独立启用时不停止任何引擎、仅 AdGuard Home 启用时只停止 Unbound、仅 Unbound 启用时只停止 AdGuard Home，均 PASS。该 harness 只验证本次分支逻辑，不等于仓库完整 regression 脚本执行。
- `fx-targeted-regression.yml` 已有 Root Proxy runtime regression run `42011770715` 完成且 `host-regressions` 为 `success`；该 run 的 changed paths 仅为 `scripts/tests/fx-yulong-root-proxy-runtime-regression.sh`，验证了当前 Root Proxy runtime/fail-open 测试路径，但没有执行本批新增的 `fx-module/scripts/tests/v1.0.0-yulong-root-proxy-lock-regression.sh`。专用 lock regression 的 GitHub Actions 结果仍未取得。Shell isolated harness 已 PASS；Android Gradle 构建、设备 DNS 生命周期、第三方 VPN 共存和真机测试未验证。
- 本批没有改动 Android VpnService 注册、第三方 VPN 路由或系统防火墙；未改变版本号，未生成 APK/KernelSU ZIP。
- 下一批：读取本批 Host regression 结果；继续梳理独立 DNS 的开机启动/配置/停止路径与 Root Proxy 共享引擎所有权，补齐真实服务状态和回滚测试。


## 2026-11-05 — Root Proxy fail-open regression assertion correction

- 读取 FX Targeted Host Regression run `42011667361` 的失败日志，定位到 `scripts/tests/fx-yulong-root-proxy-runtime-regression.sh` 的 `assert_stopped()`：它已按独立 Unbound 状态分别断言“保留”或“停止”，函数末尾却仍无条件要求 `unbound-stop`，导致正确保留独立 resolver 的 fail-open 路径被误判失败。
- 仅删除该相互矛盾的无条件断言；保留按 `MOCK_UNBOUND_INDEPENDENT` 分支验证 stop/keep 的检查，未更改 Root Proxy 数据面实现或放宽安全断言。
- 提交：`0e809b7d58bbf668d689acbcd97e3e5735ae5d93` — `fix(test): respect independent Unbound ownership in fail-open regression`。
- 提交后 GitHub Actions run `42011770715`（HEAD 同上）已完成，`host-regressions` job 结论 `success`：https://github.com/vip-svip/SY/actions/runs/42011770715
- 已回读验证测试文件新 blob SHA `0df968ba3c34647a6695f783cc71caf856918365`，确认冲突断言已移除；源码 blob SHA 仍为 `350d261ae1023007869f881c77c1e877c0b3f9ff`。
- 此次通过的是 GitHub Actions Host regression，不代表 Android Gradle 构建、设备内核路由、第三方 VpnService 共存或真机 DNS 验证通过。


## 接管资料可用性补记（2026-11-05）

- 已读取 Library `/FX` 当前完整目录清单。可见原始 `Dia_23.11.apk` 与 `游龙广告插件_7.0.1.apk`；未见项目交接指令中提到的五份 `*_src.zip` 源码包。当前也未在 `/FX` 清单中找到《FX_1.0.0_项目接管总档_自主开发与查漏补缺.md》及《FX_1.0.0_快速推进与主动修复执行档.md》；按其准确路径读取 GitHub `docs/` 同样返回 404。
- 已读可用的《FX_1.0.0_UI优先自主推进与中断续接执行总指令.md》《FX_1.0.0_UI优先提速与自主开工提示词.md》及新对话启动提示词；它们确认 UI 优先、垂直功能闭环、不得虚报测试和真机结果。
- `.gitmodules` 确认 `vendor/GKD-XA` 指向 `https://github.com/84593320z/GKD-XA.git`。本批没有读取该子模块的完整树，也没有把缺失的源码压缩包当作已检查。
- 因此，本轮仅对当前 VPN/DNS 源码实施了定向修复；Dia、GKD-XA、游龙广告/安全护盾原始 APK 的全量 Manifest/Smali/资源对照仍未完成，后续需使用已存在 APK 或取得缺失源码包后按页面批次继续。


## 2026-11-05 — Targeted Host regression: minimal module overlay handling

- GitHub Actions run `42012278340` for commit `f8801a08cbe0267a5050c0dc6546a47b1a627689` completed successfully: `host-regressions` = `success`.
- Root cause in the earlier failing runs `42011463160`–`42011727328`: `scripts/tests/fx-atomic-cache-lock-release-regression.sh` treated the tracked `fx-module/` overlay as a complete restored Release module and required `scripts/apply.sh` + `scripts/subfetch.sh`, which are intentionally supplied by the Release archive rather than tracked in this minimal overlay.
- Updated the regression entrypoint to detect this known source-layout boundary. In a minimal checkout it now explicitly skips only the Release-archive Hosts/subscription cache-lock portion, runs the tracked Root Proxy lock regression, and exits successfully only if that Root Proxy test passes. It does not create placeholder scripts or weaken the module-backed Release checks.
- CI log confirms: Root Proxy atomic lock, stale/live owner, concurrent serialization and independent local-DNS engine ownership regression passed. The separate Root Proxy regression and VPN external-fallback regression also ran in the targeted workflow.
- Full Hosts/subscription cache-lock coverage remains dependent on the restored FX Release module in the module-backed build lane; it is not claimed as tested by this host-only run.


## 2026-11-05 — System-app overlay uninstall regression

- Extended `scripts/tests/adhook-app-installer-regression.sh` to simulate PackageManager resolving FX Hook from `/system/app/FX/FX.apk` during module removal.
- The regression verifies the remover clears only FX ownership markers, does not call `pm uninstall`, and leaves the system package registered for KernelSU's module unmount to remove. This closes a distinct lifecycle edge not covered by the previous updated-`/data/app` system-classification scenario.
- Commit: `295e37730230fd3a16f0b60f9fe65398d5210aa8` — `test(hook): verify system overlay uninstall is handled by module unmount`.
- GitHub Actions run `42012660923` completed successfully; `host-regressions` = `success`. The log explicitly reports: `PASS: system-app detection, overlay-safe uninstall, ordinary-app fallback, signature safety, ownership-safe cleanup, and stale-marker handling`.
- Re-read verified test blob SHA `22809df48f99f2a4fb2605f155768a47298eb627`.
- This validates the shell-level PackageManager/remover contract with a mock; it does not replace a real KernelSU mount/unmount test on a device.


## 2026-11-05 — External Android VPN TUN coexistence regression executed

- Added the self-contained `scripts/tests/fx-vpn-tun-external-fallback-regression.sh` to the minimal-overlay fallback path of `fx-atomic-cache-lock-release-regression.sh`. This makes the TUN coexistence fixture run even when the Release archive is not staged in the source checkout.
- GitHub Actions run `42012514171` for commit `c7ee4d73c567bbfb527ca6e5a5f04bb40d4e1df7` completed with `host-regressions: success`.
- Confirmed in the job log:
  - Root Proxy atomic lock, stale/live-owner handling, concurrent serialization and independent local-DNS engine ownership: PASS.
  - TUN-to-REDIRECT fallback fixture: PASS. It verifies the outer VPN interface, owner UID, explicit compatibility switch and route proof; unsafe/unknown states fall back to direct mode; requested/effective mode and fallback reason are reported.
- The fixture is a host-side deterministic test of the patcher and mode-selection functions. It does not establish live Android VPN coexistence or device-kernel behavior.


## 原始来源 Intake Artifact 恢复（2026-11-05）

- 补充发现 GitHub Actions run `41538478144` 的 artifact `fx-apk-source-intake`，artifact ID `13184309776`，当前未过期（到期 2026-11-16），已下载并校验 SHA-256：`5e8328d9c940d961fb49073ac9be8b2d2aac793148bafff700eed80a97851a3a`。因此此前“/FX Library 没有源码 ZIP”只代表 Library 目录缺失，不代表 GitHub Actions 没有可用来源。
- Artifact 内有三个已解包来源树：Dia 23.11（31,698 个文件，package `dialog.box`，Manifest 70 个组件）；游龙广告 7.0.1（9,105 个文件，package `com.youlong.ad`，Manifest 20 个组件，原版声明 `AdBlockVpnService` 与 `RootProxyService`）；游龙安全护盾 9.9.60（39,311 个文件，package `com.youlong.hd`，Manifest 44 个组件，含 Stellar 内部组件）。
- 该 artifact 不含原始 `_10.10.62_src.zip`，也未发现 `GKD-XA_1.4.8_src.zip`；GKD-XA 仍以仓库 `.gitmodules` 指向的独立上游 submodule 为来源，需单独回读 gitlink/commit。Artifact 内三个解包目录不是原始 ZIP 本体，不能把它们描述成五份源码 ZIP 全部齐备。
- 架构约束：原游龙 7.0.1 的 `AdBlockVpnService` 不得直接迁入 FX Manifest 形成第二个 VpnService；FX 应继续使用自己的 Root/系统网络栈数据面与 Root Proxy，按 Android 单 VPN 槽限制检测外部 VPN。
- 已用 artifact SHA、Manifest 包名和组件数完成来源身份初步核验；尚未完成 Dia/7.0.1/9.9.60 的完整 Smali/资源/许可证逐项映射，也未核验 10.10.62 源码。


## 单独本地 DNS 引擎所有权回归扩展（2026-11-05）

- 在已被 CI 实际执行的 `scripts/tests/fx-yulong-root-proxy-runtime-regression.sh` 中新增两种单引擎组合：仅 AdGuard Home 独立启用时，停止 Root Proxy 只停止 Unbound；仅 Unbound 独立启用时，只停止 AdGuard Home。
- 原有两种组合继续保留：两个引擎都独立启用时都保留；两个引擎都未独立启用时都释放。这样覆盖完整 2×2 引擎所有权矩阵，而不是只测“全开/全关”。
- 提交：`ecaedb06db86c8cdc5a9bb704d23d36016dedfc8`（`test(vpn): cover single-engine local DNS ownership`）。提交后已回读新测试文件 blob SHA `29f2bcffa320e16df81807bb71257983d6145f42`。
- 该文件路径会触发 `fx-targeted-regression.yml` 的 push host regression；本次新提交的 Actions run ID 尚未从 GitHub API 读取。此前 run `42011770715` 对同一 Root Proxy runtime regression 的原有全开/全关测试通过，不应把此前结果冒充本次新增两项的执行结果。


## 2026-11-05 — Local DNS watchdog uninstall stale-PID recovery

- Review of `fx-patches/patch_localdns_uninstall_shutdown.py` found that its fail-closed PID identity check also treated an already-exited watchdog PID as an unknown live process. A stale PID file could therefore block module removal even though there was no process left to stop.
- Updated the release patcher to distinguish dead PID from live-but-unverifiable PID: a dead PID's non-symlink state record is cleared and uninstall may continue; a symlinked record or a live PID whose command identity is not the expected watchdog still aborts before firewall teardown and preserves state. Existing TERM/KILL identity revalidation for a confirmed watchdog remains intact.
- Added `scripts/tests/v1.0.0-uninstall-stops-localdns-watchdog-before-firewall-regression.sh`. It creates a minimal release-uninstall fixture, applies the patch twice to check idempotence, validates shell syntax, and exercises dead PID cleanup, live unrelated PID refusal, symlink refusal, and cooperative-helper shutdown failure.
- Commits:
  - `061f6ee9fc5c507204846712921a1e9ca61a1a21` — `fix(dns): clear dead local DNS watchdog PID during uninstall`.
  - `8dd44801a53cae4fae9d95e9edf2301fd9663a9e` — `test(dns): cover local DNS watchdog uninstall ownership`.
- The first targeted workflow for the patcher-only commit (`42012964957`) failed because the workflow's changed-source mapping did not yet include this new patcher regression; this was a CI mapping gap, not a test failure. After adding the regression entrypoint, run `42013033671` completed with `host-regressions = success`; its log explicitly reports the local DNS watchdog uninstall regression PASS.
- This is a host shell fixture test. It does not claim real Android uninstall, KernelSU lifecycle, SELinux, or device DNS continuity verification.


## 2026-11-05 — Local DNS watchdog PID ownership regression and current branch verification

- 读取 fx-patches/patch_localdns_uninstall_shutdown.py 与其 Host regression。卸载路径现区分已退出 PID、可验证的 FX watchdog、PID 身份不明/复用及符号链接 PID 文件；无法确认服务停止时在防火墙清理前中止卸载并保留状态目录。
- 扩展 scripts/tests/v1.0.0-uninstall-stops-localdns-watchdog-before-firewall-regression.sh，增加符号链接 PID 文件目标保持不变的断言。首次测试发现非数字哨兵不能进入数字 PID 校验分支，已改为数字哨兵 99999999，确保真实覆盖 symlink 拒绝路径。
- 最终提交：6f61211d54066e67dbc3cf8e0ad968e8e91f87aa — test(dns): use numeric sentinel to exercise symlink PID rejection。
- GitHub Actions run 42013532891：host-regressions = success。该 run 直接执行上述卸载回归脚本，测试进程退出码为 0。
- 曾有前序失败 run 42012964957：其变更仅触及 fx-patches/patch_localdns_uninstall_shutdown.py，当时 workflow 没有把该 patcher 名称映射到对应测试，因而报告无测试映射。随后独立回归文件变更触发了对应测试；不能把前序失败 run 记为通过。
- 回读当前分支确认 scripts/install_adhook_app.sh 与 fx-module/scripts/install_adhook_app.sh 当前 blob SHA 相同（3c4af6e698ab6dfcb9c1eebbc61b12c0b41573ba），打包副本同步已在当前分支状态中成立。
- 新发现、尚未修改的 Root Proxy 风险：_status_locked() 在外层 VPN 路由失效、egress 改变、IPv4/IPv6 redirect 缺失或本地 DNS probe 失败时会报告 active=0，但这些分支本身没有调用 _stop_locked() 清理残留 FXYRP 规则。需要补上锁内 fail-open 清理，并增加状态核验后的规则/marker 清理测试；目前不将其记为已修复。
- 本轮 Host CI 不代表 Android APK 构建、KernelSU/Magisk 挂载、SELinux 真机验证或 Android 外层 VPN 与 FX TUN/REDIRECT 的设备级共存验证。


## 2026-11-05 — FX Hook 系统应用部署 fail-closed 修复

- 发现并修复的新模块降级风险：构建流水线已经把同一签名 APK 放入 `system/app/FX/FX.apk` systemless overlay，但旧安装脚本在 PackageManager 尚未识别该 overlay 时，会继续把 APK 复制到 `/data/local/tmp` 并通过 `pm install -r` 装成普通应用。这会掩盖 KernelSU overlay 挂载、PackageManager 扫描或 SELinux 标签失败，与新版本“自动作为系统应用部署”的要求不符。
- 更新 `scripts/install_adhook_app.sh`，并同步至 `fx-module/scripts/install_adhook_app.sh`：当新模块携带 system-app overlay 时，必须先由 `pm path` / `pm list packages -s` 证明包已被识别为系统应用；若 APK 尚未被识别、overlay 未挂载或 ROM 未扫描，立即 fail closed，记录检查 overlay mount、`post-fs-data.sh` SELinux labeling 和 reboot 的诊断信息，不执行普通应用降级安装，也不写入 FX ownership marker。已识别为 system app 且更新位于 `/data/app` 的系统更新包仍可按原逻辑安全更新；签名不匹配仍拒绝对系统包执行破坏性卸载。
- 保留兼容边界：只有旧模块 ZIP 根本不含 `system/app/FX/FX.apk` 时，才继续允许历史 `optional/FXUnifiedHook.apk` 普通应用安装路径。新构建的 overlay 存在时绝不走该路径。
- 扩展 `scripts/tests/adhook-app-installer-regression.sh`：新增 overlay 存在但 PackageManager 未识别时不得调用 `pm install`、不得创建 digest/ownership marker；同时验证已有普通应用在这种失败场景下不会被覆盖；旧 ZIP 缺少 overlay 时仍保留兼容安装路径。保留系统应用识别、系统签名变更拒绝、旧独立 Hook 迁移、ownership-safe uninstall 和 stale marker 用例；新增静态断言锁定 fail-closed 条件。
- 更新 `adhook/README.md`，明确系统应用 overlay 不可见时的 fail-closed 行为、旧模块兼容路径及 Android/KernelSU/ROM 的设备限制。
- GitHub commits：
  - `c2e8b518d783161df7600c1f0b007a310f60c93a` — installer fail-closed fix。
  - `df0700f8b4a275450ece0cbea2d285420541c44d` — installer regression for overlay downgrade prevention。
  - `368c7665b8ad93fa0cb2a2d858ef56dd5197a63a` — synchronize packaged module installer.
  - `0b64bf521d65887318d0c2d8bcba57e433a829b6` — update installer architecture documentation.
  - `ffed6919c953f0eb1b604933cfe019002016dc7e` — static regression assertions for fail-closed policy.
- 已回读验证 root installer 与 packaged installer 完全一致，blob SHA 均为 `3c4af6e698ab6dfcb9c1eebbc61b12c0b41573ba`；测试文件 blob SHA 为 `3da57d1247031b6905577e35b4a81906730f4f23`。这属于 GitHub 源码回读，不代表 Shell regression 已执行。
- `fx-targeted-regression.yml` 的 push path filter 包含 `scripts/tests/**`，本批测试提交应触发 Host regression；当前可用 GitHub 状态接口未返回该提交的 check status（空 statuses），因此尚不能报告 CI PASS。Android Gradle 构建、KernelSU ZIP 安装、PackageManager 系统应用识别、SELinux 与卸载行为仍需真机/ROM 验证。
- 当前 CI APK 使用 debug signing identity，不能作为已验证的生产升级签名。发布前必须配置稳定 FX release keystore，并验证旧版/新 APK signing certificate 一致；不能通过自动卸载系统包来规避签名不匹配。


## 2026-11-05 — Root Proxy status fail-open reconciliation completed

- Updated fx-module/scripts/yulong-root-proxy.sh: every failed active-state proof now runs _stop_locked() while the existing Root Proxy lock is held, then reports active=0 and the original failure reason. Covered disabled configuration, absent/orphan state, invalid or incomplete markers, invalid chain names/metadata, egress marker mismatch, lost/changed VPN route, missing IPv4/IPv6 OUTPUT redirect and failed local DNS probe.
- Cleanup uses the existing FX-owned FXYRP chain names and _stop_engines() policy. It does not flush global OUTPUT/NAT tables or alter Android Private DNS. Independently enabled Unbound and AdGuard Home remain running; engines not independently enabled are stopped.
- Extended scripts/tests/fx-yulong-root-proxy-runtime-regression.sh with executable cases for missing IPv4 redirect, missing IPv6 redirect, unavailable VPN route, failed DNS probe, disabled proxy and orphaned hooks without state markers. Each case verifies state markers and both family hooks are removed and independent DNS engines are preserved.
- Initial regression run 42014045380 failed because the newly added shell assertions printed a literal backslash-n; corrected the test's printf escape and reran. Do not count the initial failed run as passing.
- Source commit: 8e00bd764aa48a9b1c8f06dd682ea7d33be90693 — fix(vpn): reconcile stale Root Proxy redirects on failed status proofs.
- Regression commit: 8bda5a259ae64d1ded008094d893775c4679c90a — test(vpn): fix newline assertions in status fail-open regression.
- GitHub Actions run 42014171517 completed successfully; host-regressions = success. Log reports: PASS: Root Proxy runtime route/UID proofs, dual-stack rules, state-path symlink guards, independent DNS ownership and fail-open rollback.
- This is host-side shell integration with mocked Android commands and iptables/ip6tables. It does not establish real device VPN recovery, kernel TUN behavior, OEM firewall compatibility, SELinux policy behavior or uninterrupted network service on Android hardware.


## 2026-11-05 — VPN regression coverage and Dia automation navigation repair

- CI mapping gap closed: .github/workflows/fx-targeted-regression.yml now runs scripts/tests/fx-yulong-root-proxy-runtime-regression.sh whenever FX module scripts or Root Proxy/VPN patchers change. Previously that runtime test ran only when the test file itself changed, so source edits could bypass it.
- Added the same Root Proxy runtime regression to .github/workflows/build-fx-adhook.yml immediately after release module restore and Root Proxy patching. This ensures the package lane exercises the restored/patch-applied module source rather than relying only on the host-only tracked copy. Commit: 680d8d598020404625cb0483eef42ea9d284c405. This build workflow change has not yet been executed via its gated workflow_dispatch/PR path.
- Full host workflow run 42014520068 exposed a real Dia navigation regression: FxDiaFridaActivity already supported click-auto and viewgroup-remove template routes, but MainActivity's Hook hub did not expose them. Added two native action cards that route into the existing Frida Activity using its supported dia_page values; no second automation engine was created. The templates retain their default-empty matching rules and existing bounded traversal/action limits.
- The initial full-suite run failed at scripts/tests/fx-dia-monitor-event-view-regression.sh with "auto-click page missing from Dia native navigation". This was a real missing entrypoint, not a VPN failure. After the MainActivity fix, run 42014690754 completed successfully with host-regressions = success; its logs show the GKD, six-skin UI, Hook/Dia, native VPN controller, DNS cache and related host regressions passing.
- Dia entrypoint commit: d2c318112ae4c23684406cf71a1b8cb277c721a3 — feat(dia): expose bounded Frida automation templates in Hook hub.
- Root Proxy CI mapping commit: 5f229a549f0fd60a74d21b6778720b5e616d34ea — ci(vpn): run Root Proxy runtime regression for module changes.
- Android Gradle/APK build, restored Release ZIP package-lane run, KernelSU/Magisk installation, device VPN coexistence, SELinux and physical-device power/network continuity remain unverified.


## 2026-11-05 — Dia / Frida script-library arbitrary capacity limits removed

- Removed fixed 64-script, 128 KiB per-script, 1 MiB library/import/export, and 64-character script-name limits from the shared Dia script-library policy and native/legacy Frida library flows.
- Preserved the existing `fx_dia_frida/frida_script_library_v1` preference store and `FX-DIA-FRIDA-SCRIPTS-1` JSON schema; no data migration or duplicate store introduced.
- Preserved non-empty-name/source validation, control-character and delimiter checks, strict UTF-8 decoding, serialized read-modify-write, commit-confirmed persistence, explicit import overwrite preview/confirmation, and SAF URI grant lifecycle.
- Import preview now lists every same-name conflict instead of truncating the display to five names.
- Added Host JVM regression coverage for long names and multi-megabyte source validation; updated static regression to reject reintroduction of arbitrary capacity constants.
- Verification status at commit time: GitHub source readback and pre-commit transformation assertions; Host JVM and Android Gradle tests await CI execution. No APK build, device install, or real Frida injection is claimed.
- Follow-up: review the separate Frida editor/Activity state transport's 48 KiB / 512 KiB caps and replace Binder-sized source handoff with file-backed transfer before removing those distinct runtime/editor safeguards.


- Post-commit review correction: the Java Host test's control-character fixture is encoded as an actual newline escape (not a literal backslash sequence), and the full conflict preview no longer appends the obsolete “等” suffix after listing every conflict.

- Regression-script cleanup: removed a stale assertion for a newline-delimited conflict list; the actual native preview uses the localized full-name list and is now asserted directly. The check also verifies the obsolete truncation suffix is absent.

- Follow-up compatibility fix: aligned the legacy Frida SAF regression with the unbounded library contract, retained its separate file-backed draft safeguards for later editor transport work, and removed the remaining 64-character name truncation during Activity rotation.


## 2026-11-05 — Remove remaining legacy Dia script storage caps

- Removed the legacy Frida page's 128 KiB per-script save guard, 64-character saved-script name guard, and 512 KiB standalone JavaScript SAF import/export guards; the original example ZIP loader no longer truncates entries at 128 KiB or stops after 32 examples. Shared store validation still rejects empty names/content, delimiters/control characters, malformed JSON values, and malformed UTF-8.
- Removed the 512 KiB ceiling from AtomicFile-backed Activity draft persistence; writes remain atomic and corrupt drafts are removed on read failure. Activity state stores only an ownership marker for large drafts, not their full source in the Bundle.
- Updated the SAF regression to validate actual import/export/cancellation/rotation/overwrite guarantees and reject arbitrary capacity constants instead of requiring old limits.
- 48 KiB 仅是 Activity Bundle 的内联/文件暂存分流阈值，不是源码容量上限；大草稿与编辑器返回值已使用私有文件传递。Frida Root 运行时当时仍有 8 MiB 上限，该上限已在后续 2026-11-05 的 RootAccess InputStream 改造中移除。


## 2026-11-05 — Remove saved-script name draft truncation

- The first legacy page-navigation CI pass after removing script storage limits found a stale 64-character name truncation in Activity recreation state. Removed it and updated the navigation regression to require complete saved-script name preservation rather than the obsolete bounded-name behavior.

## 2026-11-05 — Dia 弹窗移除规则取消人为数量/长度限制

- 直接修改现有 `FxDiaFridaActivity` 的弹窗移除规则编辑器：移除关键词正则和资源 ID 各自最多 12 条的硬编码限制，以及每条 160 字符的硬编码限制；保留 Java 正则语法编译校验、资源 ID 名称/十进制格式校验、去重、空规则拒绝和脚本生成前的精确模板替换。
- 更新两个多行输入框提示，不再宣传不存在的规则数量上限。仅改变产品输入限制，不扩大 Hook 执行权限；脚本仍须由用户检查后手动注入。
- 源码提交：`d94938201a6851e04c0747577eccf73ac856232f`；回归提交：`22f1872345a64356293f0a0c90bfa0c411d06c9e`。
- 验证状态：GitHub 写入 API 已成功提交两项源码变更；对应 Host regression 等待 GitHub Actions 执行。尚未声称 Android Gradle 构建、设备运行或真机 Hook 验证通过。
- 后续转入 VPN 内核数据面和本地 DNS 的真实验收；Frida 8 MiB runtime transport 已由后续提交完成文件流替代，保留设备存储、内存和 Root 超时等真实资源边界。

## 2026-11-05 — Frida Root 源码传输改为文件流，移除 8 MiB 硬上限

- `RootAccess` 新增 `InputStream` 输入重载，Root stdin writer 按 64 KiB 块读取并转发，不再将完整脚本复制成第二个 byte[]；旧 byte[] API 保留为兼容重载。Root shell 命令自身的 128 KiB 命令长度校验保留，避免把脚本正文嵌入 shell 命令。
- Dia Frida Gadget attach 与 frida-inject 改为先将源码以 UTF-8 分块写入 FX 应用私有 cache 临时文件，再通过 `FileInputStream` 传给 RootAccess；文件名随机、父目录校验、输入文件身份校验、队列拒绝/执行完成/Activity 销毁均清理暂存文件。
- 移除运行时 8 MiB 脚本上限，以及弹窗移除模板生成路径复用该常量形成的隐藏上限。保留空脚本/NUL 拒绝、目标包/UID/debuggable 验证、固定 Root 命令、原子目标文件替换和用户手动执行确认。
- 代码提交：RootAccess `986b58e289ceafb06c6bbe343d5bdf7693e5d4b3`；Frida Activity `6bb4ddb50142131dc7e9e828c99a833eefd2af42`，随后队列前置暂存及失败清理修正 `2ec191ac2c79ed95edcca28de73b92ed37d974a3`、`e1c44bf2004466ceb9063b76f2aa17652f96b360`。测试提交：Gadget `b890edcde27e65d1e825522d7f73d92fe48bc524`、清理生命周期与 file-backed 断言 `b061c8fa96fa7d14131b19b4967c1c99dbd65087`；进程身份 `c2f6aeaac7d1e86bab6bcbae6d62a7d9c96ae357`。
- 验证状态：GitHub 源码提交成功；最新 Gadget lifecycle regression 提交已触发 Targeted Host Regression。当前 GitHub connector 返回该提交的 commit status/checks 为空，尚不能确认 Actions 执行结果。没有声称 Android Gradle 构建、Frida 真注入或真机测试通过。
- 说明：不设人为脚本字节上限不代表设备存储/内存无限；编辑器仍持有当前文本，磁盘空间、Android 进程内存、Root 超时和目标 Frida CLI 能力是实际资源约束，UI 不应再将 8 MiB 宣称为产品限制。


## 2026-11-05 — RootAccess 大脚本流式传输 Host 行为回归

- 在现有 scripts/tests/fx-dia-frida-gadget-session-regression.sh 内加入真实 Java Host 行为测试：编译项目当前 RootAccess.java，通过隔离的 fake su broker 执行 InputStream 数据桥。
- 测试生成 9 MiB 确定性二进制输入，实际调用 RootAccess.executeWithInput(String, InputStream, ...)，在接收端校验 SHA-256 与字节数；另以故障 InputStream 验证 stdin 写入异常不能被误报为成功。
- 该测试由既有 fx-targeted-regression.yml 的 scripts/tests/** push 触发及 fx-dia-frida- 变更映射执行，无需增加第二个 workflow 或重复工程。
- 提交：587aeee45121d87bb703b5e19f19a5be316804b4。GitHub 回读已确认测试脚本包含 9 MiB 流完整性和写入失败断言，且旧 byte[] 调用断言不存在。
- 当前 commit status 接口尚未返回任何 CI status；本条不把源码回读当作测试通过。该 Host test 不代表 Android KernelSU/Magisk root broker、Frida 运行时或真机注入已验证。

## 2026-11-05 — 接续状态校正与当前分支验证边界

- 本次状态快照读取的分支 HEAD：`dc7671b1131b2f05ff380ed65536a4dbc9859218`。期间保留并吸收并行提交 `587aeee45121d87bb703b5e19f19a5be316804b4`：现有 Gadget 回归脚本编译实际 `RootAccess.java`，通过 fake su broker 验证 9 MiB 二进制流 SHA-256/长度完整性及 InputStream 写入失败 fail-closed；随后 `dc7671b` 将生成的 Java 测试源放入临时目录，避免污染工作树。
- 最新 Frida 回归脚本已增加私有 cache 路径、UTF-8 分块写入、输入路径身份校验、传输后清理和 Activity 销毁清理断言。
- GitHub commit-status 查询仍未返回 CI checks；9 MiB Host test 已写入并由现有 push workflow 触发，但没有可读取的执行结果，不能标记通过。Android Gradle 构建未运行；构建 workflow 需要手动 dispatch 且 `migration_complete=true`，本次没有绕过迁移验收门槛。
- 真机未验证：KernelSU/Magisk 安装与系统应用识别、SELinux、开机启动、Android/第三方 VPN 并行链路、内核 TUN/REDIRECT、DNS/IPv4/IPv6 泄漏、网络切换和低功耗常驻。
- Android 平台限制：每个 Android 用户/配置文件通常只能有一个活动 VpnService VPN；系统 VPN 与第三方 App VPN 不能被 FX 强制同时占槽。FX Root/内核代理不注册 VpnService，可在外层 VPN 已通过接口/UID/路由验证时使用 REDIRECT 链接；封闭 VPN 是否允许链式转发仍依赖厂商/ROM/应用实现。
- 下一优先级：取得并核验小火箭 10.10.62 第一手源码（本轮仓库与可检索 Library 均未找到源码包），按协议、路由、策略组、DNS、脚本、MITM、应用分流逐项补数据面矩阵；同时完善本地 DNS 与外部 VPN/内核代理的设备验收。不得把源码回读或 Host fixture 结果冒充真机/Gradle 通过。

## 2026-11-05 — Host stream regression assertion normalization

- Latest branch HEAD at this snapshot: `2728c6dc9b09ebc50ceecfd554f7970c57f58a2e`.
- `RootAccess.java` 声明跨行，Gadget 回归已改为先压缩空白再核对 InputStream 重载，避免静态断言因换行格式误报；提交 `2728c6dc9b09ebc50ceecfd554f7970c57f58a2e`。
- 当前脚本同时包含 9 MiB SHA-256 流完整性测试、异常输入 fail-closed 测试、私有 cache staging/清理断言；CI check-run 仍不可从当前 GitHub connector 查询，等待现有 push workflows 执行状态。

## 2026-11-05 — RootAccess 回归断言归属修正

- 分支 HEAD 快照：`04cae02c4dfbd8bf7b84fd205d1847ba71ce8475`。
- 将 64 KiB 分块断言放在 RootAccess 源码内容上验证，而不是 Frida Activity 源码上；InputStream 重载同样先压缩空白再检查，避免换行格式导致误报。提交 `04cae02c4dfbd8bf7b84fd205d1847ba71ce8475`。
- 该提交仍由现有 `scripts/tests/**` push workflow 触发；commit-status 查询无 check 记录，执行结果待 Actions 提供。

## 2026-11-05 — Dia Frida 大型脚本草稿恢复内存优化

- `FxDiaFridaActivity.readTransientFridaScriptDraft()` 改为 `InputStreamReader` + 8 KiB 字符缓冲区增量 UTF-8 解码，避免先将完整草稿读入 `ByteArrayOutputStream`，再复制成第二份 `byte[]`；没有引入脚本大小上限。
- `fx-dia-frida-script-library-saf-regression.sh` 新增静态回归断言，防止恢复路径退回整份字节缓冲复制。
- 提交：`70e655dbce9df6af2c09db90186cd05ae8577409`（Activity），`d81dd4eb7f822a87590ff948cf47b14db8492b57`（回归断言）。
- Gadget session regression 的既有断言原先把 `RootAccess.java` 的方法签名/缓冲区检查错误地在 Frida Activity 字符串中匹配，已修正到 RootAccess 源码并做空白归一化；提交：`2728c6dc9b09ebc50ceecfd554f7970c57f58a2e`、`04cae02c4dfbd8bf7b84fd205d1847ba71ce8475`。
- GitHub Actions：最新 `04cae02` 的 FX Targeted Host Regression 已通过；FX Module Runtime Regression 当时仍在运行。此前两次 Host 失败均为既有测试断言归属/换行匹配问题，修正后重新触发验证。尚未声称 Android Gradle 构建或真机测试通过。

## 2026-11-05 — 隐私页授权状态补齐 Accessibility 实际连接态

- 分支快照：本条状态更新前 HEAD 为 `11a078e90c78533c66f64ba050f0f9dd54a8ef01`。
- `MainActivity.refreshNativePrivacyStatus()` 现在在原有 Root / LSPosed / Remote Files 状态之外，额外读取 Android `ENABLED_ACCESSIBILITY_SERVICES` 中的 FX 服务项，并同时核对 `FxAccessibilityService.isConnected()`、FX 私有连接标记及当前进程 PID。显示区分“系统未启用”“系统已启用、FX 服务已连接”“系统已启用、等待 FX 服务连接”，不把系统开关开启误报成服务已连接。
- Root JSON 状态现在区分字段明确为 false 的“未授权”和状态接口缺少 `root` 字段的“未知（状态接口未提供）”，避免数据缺失造成错误结论。
- 代码提交：`f7571e7793ea74b98624b5d1a271000fb61ce4ba`。
- 回归覆盖：`scripts/tests/fx-native-privacy-settings-regression.sh` 增加 app-side 状态契约断言；修正该测试在没有 restored FX module archive 的 targeted Host 环境中直接失败的问题，使 app-side 静态检查始终运行，而依赖模块归档的配置持久化/回滚检查仅在归档可用时执行。相关测试适配提交：`880f4bb109fc2bf7621f624cf8c1ddff24252468`、`e2c3f33053aab51babc1556db77491eab3a9d697`、`2dc4d9db5409035db4207696dcf75e646a2db0e9`，随后由 `8ad3f7ebcaaae0badc60df76c4b612f41a7735c6` 与 `11a078e90c78533c66f64ba050f0f9dd54a8ef01` 整理测试为始终执行状态检查、模块归档可用时再执行模块行为验证。
- 验证：GitHub Actions FX Targeted Host Regression run `42029516063`（HEAD `11a078e`）已 completed/success；FX Module Runtime Regression run `42029515963`（同一代码 HEAD）已 completed/success。Targeted workflow 的成功包含新增 app-side 状态静态断言；Runtime workflow 成功仅代表其现有 VPN/DNS Host 回归通过，不代表 Android 编译、Accessibility 服务真机连接、Root/LSPosed 实际注入或本次隐私 UI 的模块归档行为已通过。
- 未运行/未验证：Android Gradle 构建、APK 安装、真机无障碍设置切换与 Binder 生命周期、Root/LSPosed 真机状态、模块完整归档测试（等待 runtime workflow）。
- 下一批：继续核对 Hook 目标应用详情的授权状态与规则发布回读一致性；并行回到本地 DNS/外部 VPN/内核代理真实链路验收矩阵。不得把系统 Accessibility 开关开启等同于目标应用已执行 Hook。

## 2026-11-05 — Hook OBSERVE 日志查询回归补强

- 为 `fx-hook-observation-logs-regression.sh` 增加查询安全合同：目标包名必须先经过包名格式校验，再由 `shellQuote()` 作为固定字符串 grep 参数传入；只筛选 `FX Hook` 标签下的 `dev-observe` / `dia-dialog-match` 记录，并要求包名与 executable 字段精确匹配。避免日志查看器未来退化成宽泛日志搜索或 shell 字符串注入。
- 本次只强化回归约束，没有改变 Hook 目标应用的执行行为，也没有把 OBSERVE 日志当成实时 Hook 授权或当前进程存活证明。
- 提交：`e47ebd78f2e9dc1be9a1be2c4ec8e99d60d3a1ac`（首次断言草稿，CI 暴露断言字符串构造错误）；`c4f399d3af20f5c12901327ad1f556a8c95534d3`（修复首轮字符串但 Python token 列表仍错误）；`80a3b88a03f9fd2b644344c8d2f547eb720c324e`（Host 通过的中间版本）；`60f113a2ec65faae34e83eca5408422ce1eaa199`（简化并修正最终断言）。
- 最终版本 FX Targeted Host Regression run `42030169436` 已 completed/success；日志明确输出两条 PASS：生命周期/边界保护，以及目标包名 shell quoting 与精确日志筛选。FX Module Runtime Regression run `42030169200` 已 completed/success（vpn-dns-runtime job）。该 workflow 验证的是既有 VPN/DNS Host 运行时回归，不代表本次 Hook 查询在设备上的行为。
- 未执行 Android Gradle 完整构建或真机 LSPosed/Hook 注入验证。


## 2026-11-05 — System-app overlay verification and Hook hub navigation regression

- Current branch HEAD before this state update: b4d0808d1e7d6ec934145d193363cc91969d32dc.
- Commit f0a80b988163d8c99bf4dd518f97149548aa3d52 hardens both canonical and packaged FX Hook installers: the system/app/FX/FX.apk overlay requires a present SHA-256 sidecar, a 64-character hexadecimal digest and an exact APK digest match. Older optional-payload archives retain their legacy compatibility behavior.
- The installer Host regression now covers missing, malformed and mismatched sidecars and confirms that PackageManager install and FX ownership markers are not touched on rejection. FX Targeted Host Regression run 42031415187 completed SUCCESS on the follow-up branch tree; its installer test printed PASS.
- A full Host run initially exposed a stale SystemExpand assertion that expected the removed application/module migration menu. The current native MainActivity already places SystemExpand as an action card in the unified Hook hub. Commit 32f5a615d089337285bf918ed1a2204aca42efc5 aligns the regression with the actual Hook-tab route. FX Targeted Host Regression run 42031389055 completed SUCCESS; log confirms: “PASS: Dia SystemExpand native screen is reachable from the unified Hook hub and restores its scroll position safely”.
- Commit b4d0808d1e7d6ec934145d193363cc91969d32dc adds malformed checksum coverage. The subsequent Targeted Host run 42031415187 completed SUCCESS.
- FX Module Runtime Regression run 42030977447 completed SUCCESS on the installer change: 18/18 VPN/DNS runtime regressions passed, followed by restored-module tests for TUN-to-REDIRECT external-VPN proof, Unbound VPN-bound egress, Root Proxy dual-stack state/rollback, native VPN transactions and atomic Hosts/subscription locks. The latest branch run 42031415700 is still in progress at this snapshot.
- The earlier Targeted Host run 42030977468 failed only at the stale SystemExpand navigation assertion after the installer test itself passed; the corrected regression subsequently passed as recorded above.
- No Android Gradle build, APK installation, KernelSU/Magisk device deployment, PackageManager visibility on a physical ROM, SELinux device behavior, or real-device VPN coexistence/power test is claimed.

## 2026-11-05 — Latest post-hardening VPN/DNS module regression

- Branch HEAD at this verification: 881397499c3e2083788513261e6a026899f1de3c.
- FX Module Runtime Regression run 42031415700 completed SUCCESS against commit b4d0808d1e7d6ec934145d193363cc91969d32dc. Logs confirm VPN/DNS runtime regressions 18/18 passed, plus restored-release runtime tests for verified outer-VPN TUN-to-REDIRECT fallback, Unbound VPN-bound IPv4 egress, Root Proxy dual-stack route/UID proof and fail-open rollback, native VPN lifecycle/config locking, transparent VPN control and atomic Hosts/subscription/Root Proxy locks.
- This is GitHub Actions host-side execution with mocked Android networking/package commands and restored module source. It does not verify a physical Android device, ROM-specific netfilter, SELinux, Android Framework VPN multi-instance support, actual third-party VPN inner traffic, radio wakeups or power draw.


## 2026-11-05 — FX Hook 配置流式发布与大配置解析回归

- 分支 HEAD：42f5ff4681155d6b8de19a6514a6ee4b01a79cd8。
- 3d2461be46054fda91822b49be77e242792488a2 新增 FxHookConfigPublisher：配置正文改由 RootAccess.executeWithInput(InputStream) 经 Root stdin 分块传输，不再把整份 Base64 配置塞进 shell 命令；移除发布端 990 目标、64 KiB 配置和兼容映射大小限制。
- 639188a0c996207d3c480405ded6fdd4b5d20509 修正发布事务 Shell 防护，并补齐现代和 legacy parser 中残留的 64 KiB / 1000 行检查。
- Hook 模块 AdVisibilityHook.loadConfig() 改用严格 UTF-8 InputStreamReader 分块读取；HookTargetConfigParser 不再因 1000 行拒收旧格式配置。
- 发布前对临时路径做 symlink / 文件类型检查；每个 payload 分开流入 staging 文件并核对 SHA-256；三份目标文件（LSPosed Remote Files、原生 overlay、legacy ownership mapping）按事务流程替换，逐一回读核对最终 SHA-256，提交步骤失败时恢复旧文件。此处是具备回滚的多文件事务，不是文件系统提供的跨文件单次原子 rename。
- scripts/tests/fx-hook-config-stream-publish-regression.sh 通过 fake su broker 运行实际 RootAccess 和 FxHookConfigPublisher：成功传输 256 KiB 配置与 96 KiB 兼容映射；注入第三份文件 rename 失败后，确认三份旧文件均恢复且 staging / backup 临时文件清理完成。
- 同一 Host 脚本直接编译并运行现代 UnifiedHookConfigParser 和 legacy HookTargetConfigParser：两种格式均接受 2,500 个目标，配置均超过 64 KiB 和 1,000 行；现代隐私总开关及 legacy 不启用隐私的兼容语义均保留。
- 回归兼容修正：2ab90857faff32f5864aeea48ea66e386af87c91 将旧 UI 超时断言改为新流式 publisher contract；ba3c9e49d55a23fc2fda99e983b95919d48db08d 补齐 parser Host 编译依赖；56e6e6784b8b8a1a873255862de4adf6b357bc08 更新 JUnit 配置大小用例；42f5ff4681155d6b8de19a6514a6ee4b01a79cd8 将 parser JUnit 变更映射到此 Host regression。
- 验证：FX Targeted Host Regression run 42042940195 completed/success，日志确认发布/回滚测试及 2,500 目标解析压力测试全部 PASS；FX Module Runtime Regression run 42042476025 completed/success，日志确认 VPN/DNS runtime regressions 18/18 passed，后续 TUN fallback、Unbound VPN-bound egress、Root Proxy 双栈 / UID proof、DNS 和原子锁回归也通过。
- 仍未验证：Android Gradle 完整构建、APK 产物安装、KernelSU/Magisk 真机写入、LSPosed 真正读取 Remote Files 并注入目标进程、ROM SELinux 标签实际策略、第三方 VPN 内层流量、设备 IPv4/IPv6 泄漏与功耗。
- 容量策略范围说明：本轮移除的是聚合配置字节数、目标应用总行数与命令行 Base64 限制。每个目标的自定义开发规则数仍有 64 条限制，Dialog / Toast 规则仍有独立条数、字符长度与输入字节限制；这些仍需逐项审查，不能宣称所有产品容量限制已全部清除。
- 其他阻断继续保留：尚未取得并核验 _10.10.62_src.zip 原始源码，协议、策略组、DNS、脚本、MITM 和应用分流的源码迁移不能据此声称完成。APK build workflow 的迁移门槛也未绕过或触发。


## 2026-11-05 — Dialog / Toast 规则去除用户输入容量上限

- 分支 HEAD（本条状态记录前）：c1e9e807218d4a112801ce47f06c0aba2b04ee05。
- FxDiaDialogMatchPolicy 移除 1 KiB 总输入字节、32 条唯一规则、96 字符单条规则三项用户配置限制；保留空白跳过、大小写不敏感去重、控制字符拒绝和只读不可变结果。
- MainActivity 的 Dialog 与 Toast 提示同步移除旧容量上限文案；Dialog/Toast 仍需用户显式启用并至少配置一条有效规则，空规则不会全拦截。
- MAX_TEXT_CHARS=4096 仍作为运行时待检查 Dialog 文本扫描窗口，限制每次事件的候选文本扫描成本；它不是用户规则条数、规则长度或配置文件大小限制。
- JUnit 与真实策略 Host 测试改为覆盖 40 条唯一规则、单条超过 96 字符、UTF-8 规则输入超过 1 KiB；控制字符仍应拒绝。
- FX Targeted Host Regression run 42043603559 completed/success；日志确认 Dialog / Toast / ActivityKey 集成回归通过，Dia Dialog policy Host assertions 20 项通过，ActivityKey Host assertions 27 项通过。
- FX Module Runtime Regression run 42043603180 completed/success；VPN/DNS runtime regressions 18/18 passed，后续 TUN fallback、Unbound VPN-bound IPv4 egress、Root Proxy dual-stack/UID proof 与独立 DNS 锁回归通过。
- 当前剩余容量项：每个目标的 Developer Hook 自定义规则仍限制 64 条（parser、serializer、MainActivity slots、导入/导出逻辑都依赖此范围）；需单独迁移为动态 slot/key 遍历和兼容旧 dev_rule_N 字段后才能安全解除。本条不宣称 64 条限制已移除。
- 尚未运行 Android Gradle 构建、安装 APK 或真机验证；小火箭 _10.10.62_src.zip 原始源码仍未取得。

## 2026-11-05 — Developer Hook per-target rule count cap removed

- Branch HEAD before this state update: `058e56830c0c7d26b57d9291aed9412a99eba8d9`.
- Removed the fixed per-target 64-rule count cap from the versioned Hook parser and serializer. Positive decimal legacy `dev_rule_N` and encoded `dev_rule_b64_N` slot keys are accepted above 64; duplicate slots and invalid/non-positive slots remain rejected. Serialization emits every parsed rule in sequence.
- MainActivity now discovers persisted numeric slots from SharedPreferences for editor duplicate checks and allocation, grouping, group rename/delete, JSON export/import, rollback cleanup, list rendering and final config publication. Sparse legacy slots are readable; import compacts the accepted set transactionally and restores the previous key set if commit fails.
- Capacity qualification: there is no fixed per-target rule-count cap, but the pasted JSON editor remains bounded to 65,536 UTF-16 characters and the UTF-8 JSON payload remains limited to 64 KiB; enclosing configuration size and device storage still apply.
- Added parser/serializer JUnit coverage for 96 rules and sparse legacy slots 65 / 4096. The streaming Host regression directly compiles parser plus serializer and round-trips 96 rules. The custom Hook Host regression checks that editor, grouping, import/export, render and publish paths enumerate slots dynamically.
- FX Targeted Host Regression run `42047046509` completed SUCCESS on HEAD `058e5683`. The later FX Targeted Host Regression run `42047318523` completed SUCCESS on HEAD `70f549e1`; logs confirm Hook config streaming/hash/rollback, 96-rule parser/serializer round-trip, sparse-slot compatibility and dynamic editor/group/import/export/render/publish lifecycle checks PASS.
- FX Module Runtime Regression run `42047046721` completed SUCCESS on HEAD `058e5683`; logs confirm VPN/DNS runtime regressions 18/18 passed, plus TUN-to-REDIRECT fallback, Unbound VPN-bound IPv4 egress, Root Proxy dual-stack/UID proof, native VPN transaction and Hosts/subscription lock regressions. Later HEAD `70f549e1` only adds test coverage and workflow mapping; no runtime product code changed after the successful module run.
- The APK build gate remains closed: `.github/workflows/build-fx-adhook.yml` only runs Gradle/package steps on manual dispatch with `migration_complete=true`. That boolean is a human attestation, not automated proof of full source parity. Do not set it yet: Dia Frida listener/message lifecycle and remaining editor behavior, Yulong AdBlock original Trie/Bloom runtime plus true per-app DNS query counters, and original Shield Stellar Binder transport / remaining ProtectService semantics remain open.
- Still unverified: Android Gradle full APK build, APK install, KernelSU/Magisk deployment, LSPosed Remote Files loading and target injection, ROM SELinux behavior, third-party VPN inner traffic, device IPv4/IPv6 leakage and power behavior.


## 2026-11-05 — Custom Hook JSON import payload ceiling removed

- Branch HEAD before this continuation entry: `8c26431c418190c79be06ba7b8aa9794edd47703`.
- Removed the 65,536-character EditText filter and 64 KiB UTF-8 payload rejection from `showCustomRuleImportDialog()`. Existing legacy-array and portable-object parsing, package-prefix remapping, per-rule signature/action validation, duplicate-ID checks, and transactional SharedPreferences commit/rollback remain intact.
- Extended `scripts/tests/fx-custom-hook-passthrough-regression.sh` to assert the editor/parser path has no fixed character or byte ceiling. The test uses the method boundary in source to avoid false positives from unrelated size policies elsewhere in MainActivity.
- This removes an arbitrary product-level import cap; Android memory/storage and parser resource constraints still apply. The edit-time draft remains in app preferences.
- Source and regression are committed on this branch. Await the push-triggered FX Targeted Host Regression result before marking this regression passed. No Android Gradle build, APK install, KernelSU deployment, or device test is implied.


## 2026-11-05 — Native script capacity and file-backed transport

- Removed fixed native-script source, catalog-count, and aggregate-config ceilings: editor/import validation no longer rejects at 64 KiB, the store/runner no longer assumes 128 entries, and the config store no longer rejects at 700 KiB.
- Removed the APK's 1 MiB script-file import cap and 512 KiB script-export cap.
- Added a file-backed `add-file` operation. APK text edits and JSON import entries are staged under the app cache and passed to the root module by path, not as a Base64 shell argument. Arbitrarily large source text therefore no longer hits Linux's per-argument `MAX_ARG_STRLEN` boundary.
- File picker imports are copied to app-cache staging incrementally; non-JSON script files are sent to the module store by path. JSON document parsing still consumes memory proportional to the JSON document because the existing Android JSON object model is in-memory.
- The module store snapshots the staged file under its existing list lock, validates HTTPS subscription syntax or stores local source as Base64, then commits the updated config using the existing atomic rewrite/rollback path. Existing SHA-256 runner verification, explicit execution confirmation, 25-second timeout, HTTPS-only remote subscriptions, and 512-character display-name validation remain.
- Regression coverage now includes 70 KiB sources, 140+ entries, aggregate storage beyond the former 700 KiB threshold, file-backed imports, and exact source bytes reaching the QuickJS runner.
- CI: targeted Host regressions passed on `4fbf64e2e9f503b35850f7a41a6eb9c904f3866b`; VPN/DNS/Root-proxy runtime regressions also passed on that commit. The newer HEAD `1c1ad6a86ae22d981a7eb7118f020476ea750d01` has a passing targeted Host run; its matching VPN/DNS runtime run was still executing when this note was written.
- Hard limits remain those of the Android device: available RAM/storage, Java heap, filesystem capacity, Shell/kernel argument limits for unrelated commands, and the JSON parser's in-memory representation. No physical Android device test is claimed.
## 2026-11-05 — Native script streaming import and uncapped Hook JSON draft persistence

- Latest verified branch code checkpoint: `2abcc9e37da3ca5210e4cf980fac42c26abebac9`.
- Native script imports no longer put source contents in the Root shell argument. MainActivity stages editor/individual-file JS under its app-private `cache/fx-native-script-*.src`; the fixed `add-file` operation passes only the staged path, display name and enabled bit to the locked module store.
- The module store accepts only regular non-symlink staging files in the exact FX package cache path for numeric Android user IDs, or the explicit module-private fixture staging path used by Host tests. It snapshots the file while holding the existing native script-list lock. For local JavaScript it reads only the first line to classify the input and streams the full source from the staged file through Base64 into the `[list:script]` row; it does not copy the complete JS body into a shell variable. HTTPS subscription URLs retain explicit syntax validation.
- Removed the APK's former 1 MiB file-import and 512 KiB export limits, plus native script-store limits on one source, catalog count and aggregate config size. Host coverage stores and executes 70 KiB local source with exact SHA-256/content checks, accepts 140+ catalog entries and tests the file-backed `add-file` path.
- FX Targeted Host Regression run `42051761605` completed/success on this HEAD. Its log prints: `PASS: file-backed local source import stays streaming and accepts only FX app-cache staging paths` and `PASS: native script-list backend supports CRUD, preserves unrelated config, round-trips multiline source and installs the local runner`. The same Host suite includes the large-source / exact-execution regression.
- FX Module Runtime Regression run `42051761624` was still in progress when this state was updated; do not mark it complete unless the Actions run later reports success. The previous Module Runtime run `42051317315` completed/success on HEAD `9959bd18`.
- The no-cap policy does not imply infinite device resources. The `.js` source path is file-backed; JSON script-list imports still materialize the JSON document in the app process and therefore remain subject to available heap/storage and parser cost, even though the former arbitrary 1 MiB file-selection rejection was removed.
- Custom Hook JSON imports now have no fixed editor-character or UTF-8 byte ceiling, and per-target developer rule count has no fixed 64-rule cap. Their editing drafts are persisted with a 400 ms debounce and flushed on dialog submit/cancel plus Activity pause, state-save and destroy.
- Still unverified: Android Gradle full APK build, APK install, KernelSU/Magisk deployment, LSPosed Remote Files loading and target injection, ROM SELinux behavior, third-party VPN inner traffic, device IPv4/IPv6 leakage, radio/power behavior and on-device large-payload memory behavior. The manual APK gate remains closed while Dia/Yulong source migration acceptance gaps remain.


## 2026-11-05 — Dia Frida Gadget 日志统一原生查看器

- 本批基于分支 HEAD `1b46f7c5ac8f4a346d38b0be8947ced730fcaafe` 开始；将 Gadget Listen 的消息/console 日志从 Frida 管理页中的临时弹窗迁入既有原生运行日志页，复用搜索、刷新、最近 500 行读取、确认清空、队列限流与 Activity 状态恢复。
- Gadget 日志仅接受 1024–65535 且排除 Frida server 默认端口 27042 的端口值；文件路径由应用固定目录与已校验端口构造，不接受 Intent 任意路径。沿用目录/文件符号链接拒绝和 Root 输出大小保护。
- 目标应用会话日志与 Gadget 端口日志仍是两种独立日志源；页面按模式展示不同标题、身份与清空提示，不混淆目标包名与监听端口。
- 改动文件：`FxDiaSessionLogActivity.java`、`FxDiaFridaActivity.java`、`fx-dia-frida-page-navigation-regression.sh`。
- 验证：本提交触发的 Host Regression 将检查 Gadget 日志入口必须打开原生可搜索查看器，且不再在 Frida 主页执行 Root 日志读取/弹窗。Android Gradle 编译、Gadget 真正加载/连接与真机行为尚未验证。
- 当前分支基线 HEAD：`1b46f7c5ac8f4a346d38b0be8947ced730fcaafe`；本批提交 SHA 以 GitHub 提交后回读为准。

## 2026-11-05 — Gadget 原生日志查看器回归收敛与 CI 验证

- 本轮从分支 HEAD `8db951a3f1a6ed43190bad7d0ec126302497b287` 继续；Gadget Listen 日志入口已统一跳转至 `FxDiaSessionLogActivity`，并按端口读取独立日志文件。
- `756feee3dba7a754ebd56b96eab75ab43df02984` 更新 `fx-dia-frida-process-identity-regression.py`：不再要求已迁移出 Frida 管理页的旧错误标记，而是验证 Gadget 入口传递端口并打开原生日志页，同时验证原生日志读取路径要求常规、非符号链接、可读且非空的文件。
- 同批前置修正：`05be01a`、`cffa2ea`、`8db951a` 分别调整 Gadget 日志回归断言，使其与日志页迁移后的实际实现一致；`943d837` 完成 Gadget 日志入口与原生日志页接入。
- 最新提交 `756feee` 已回读确认；FX Targeted Host Regression 运行 `42053364872` 通过，FX Module Runtime Regression 运行 `42053365005` 通过。
- 以上为 GitHub Actions 主机回归及模块运行回归结果，不代表 Android APK 构建、Gadget 真正加载/连接、LSPosed 注入或真机行为已验证。
- 尚未验证：Android Gradle 完整 APK 构建与安装、KernelSU/Magisk 部署、LSPosed Remote Files 加载及目标注入、ROM SELinux 行为、第三方 VPN 内层流量、设备 IPv4/IPv6 泄漏与耗电行为。APK 手动构建门仍保持关闭。

## 2026-11-05 — Gadget 重连拒绝 CLI/输入馈线半失效状态

- 修复 `attachToGadgetAndResume()` 的重连判定：旧 CLI 进程即使仍存活，也必须同时确认对应 stdin feeder 存活且命令行身份匹配，才报告 `FX_GADGET_SESSION_ALREADY_RUNNING`。
- CLI 存活但 feeder 已退出时，现在明确返回 `FX_GADGET_SESSION_DEGRADED`，不再把半失效会话误报为正常运行；检测到 feeder PID 被其他命令占用时返回 `FX_GADGET_FEEDER_PID_CONFLICT`，拒绝触碰外部进程。用户可先通过现有“停止 Gadget 会话”操作回收归属已验证的 CLI，再重新连接。
- `fx-dia-frida-gadget-session-regression.sh` 增加重连必须校验 feeder 活性及身份的回归断言。
- 本次代码、回归和本文档作为一个提交单元；提交后回读并等待 Host 与 Module Runtime Regression。Android 真机行为仍未验证。

## 2026-11-05 — Gadget 重连 feeder 退出等待

- Gadget 重连发现旧 CLI 已退出、但归属校验通过的 stdin feeder 仍存活时，先向 feeder 发送终止信号，再最多等待 5 秒确认其退出，之后才允许删除旧 PID 记录/FIFO 并创建新管道。
- 等待超时返回 `FX_GADGET_FEEDER_STOP_TIMEOUT`，保留旧会话记录和 FIFO，避免旧 feeder 与新 FIFO 生命周期重叠。
- Frida 进程身份回归增加有界等待及 degraded/feeder PID 冲突断言。
- 本次提交 `9e22a3d378fa02a1c67dc9e3c76746a19d689de4` 对应的 FX Targeted Host Regression（运行 `42054317181`）与 FX Module Runtime Regression（运行 `42054317293`）均通过。该结果为 GitHub Actions 主机/模块回归，不代表 Android 真机验证。

## 2026-11-05 — Gadget stale feeder recovery 行为回归

- `768b880d78ec4ee3b881bc12b596d6547d723e32` 将 Gadget 重连行为测试夹具更新为与原生实现一致：CLI 仍运行时验证 feeder PID/命令行；CLI 退出后验证旧 feeder 身份，终止并等待最多 5 秒；超时保留 PID 记录与 FIFO。
- `0be6ae87fb1aa038667ef34bd7a9a83ae7e96824` 修正测试 PID 记录的换行格式，并在清理模拟 feeder 时显式 wait 回收子进程。
- 对应 FX Targeted Host Regression（运行 `42055263388`）与 FX Module Runtime Regression（运行 `42055263323`）均通过。
- 该行为回归在 Linux/GitHub Actions 主机上模拟 PID/FIFO 生命周期；不等同于 Android Root Shell、Frida Gadget 远程连接或真机行为验证。


## 2026-11-05 — Gadget stdin feeder 识别 CLI 僵尸退出

- 修正 feeder 自身监控循环：除 kill -0 外，读取 /proc/<cli-pid>/stat 的进程状态；遇到 Z、X 或 x 立即退出，避免 CLI 已成为僵尸时 feeder 仍持续占用 FIFO。
- 保留 feeder 固定端口身份、PID 绑定与现有 FIFO 生命周期管理；回归增加源码契约断言，确保生产 feeder 具备 zombie-aware 退出条件。
- 本次代码与回归验证覆盖 Linux/GitHub Actions 主机环境；Android Root Shell 和真机进程回收行为仍需设备验证。


## 2026-11-05 — Gadget feeder 僵尸退出行为测试

- 将 Gadget 会话行为夹具中的 feeder 命令同步为生产实现，并新增真实 Linux 僵尸子进程场景：验证 feeder 在 CLI 状态为 Z 时快速退出，而不是等待 PID 被父进程回收。
- 此项是主机进程状态行为测试；Android Root Shell 上 /proc 可见性与设备内核进程回收仍需真机验证。


## 2026-11-05 — 修正 feeder 僵尸状态解析的 shell 引用

- 首轮新增行为回归暴露嵌套单引号导致的 shell 语法错误；生产 feeder 与主机行为夹具现改为读取 /proc/<pid>/stat 后用 POSIX 参数展开提取状态，避免嵌套引号。
- 此前失败运行 42056347974 记录为修正依据；本次以 Host Regression 实际执行结果验收。


## 2026-11-05 — 修正 feeder 僵尸状态解析的 shell 引用

- 首轮新增行为回归暴露嵌套单引号导致的 shell 语法错误；生产 feeder 与主机行为夹具现改为读取 /proc/<pid>/stat 后用 POSIX 参数展开提取状态，避免嵌套引号。
- 恢复并保留真实 Linux 僵尸子进程行为场景；此前失败运行 42056347974 记录为修正依据。


## 2026-11-05 — 恢复完整 Frida Activity 并修正 feeder 引号

- 回归检查发现中间修订的源码替换范围过宽，导致 `FxDiaFridaActivity.java` 内容被截断；本提交以已验证提交 `1865680` 的完整文件为基底恢复全部内容，再只定位修改 feeder 启动命令，确认 Root 临时文件清理逻辑等既有实现保留。
- feeder 与 Linux 僵尸行为夹具统一改为读取 /proc/<pid>/stat 并通过 POSIX 参数展开提取状态，避开嵌套单引号；保留真实僵尸子进程测试。
- 先前失败的 Host Regression `42057131094` 暴露 Activity 文件被截断后造成的二级回归；本次需以新 CI 结果验收。


## 2026-11-05 — feeder 状态解析语法修正

- 将生产 feeder、Host 行为夹具及 zombie 状态轮询统一为 POSIX 参数展开解析 /proc/<pid>/stat，移除嵌套单引号；此前失败的 Host run `42056347974` 已定位为该引用错误。
- 本次提交以 Host Regression 的真实执行结果作为验收；Android Root Shell 与真机仍未验证。


## 2026-11-05 — 使用未回收子进程验证 feeder 僵尸退出

- 普通后台 shell 子进程会被测试 shell 主动回收，无法稳定观察 Z 状态；行为夹具改为 Python fork 出子进程并让父进程暂不 wait，稳定制造 /proc 中的僵尸状态。
- feeder 必须在 1 秒轮询周期内自行退出；测试结束后显式终止并回收测试父进程，避免泄漏。


## 2026-11-05 — 僵尸 feeder 行为夹具解除 FIFO 打开阻塞

- 回归日志显示 feeder 子进程被 FIFO 输出重定向的 open 阶段阻塞，尚未进入状态监控循环；新增并行 FIFO reader，确保行为测试确实执行 feeder 的 Z 状态判断。
- 测试完成后等待 reader 退出并清理僵尸父进程，避免后台进程残留。


## 2026-11-05 — Gadget feeder zombie-aware 回归通过

- 最终提交 `0be02c0293cb70a7eaed348abdf23e87f8be4e8b` 的 FX Targeted Host Regression（`42057994175`）与 FX Module Runtime Regression（`42057994169`）均通过。
- Host 回归覆盖真实 Linux 僵尸子进程：测试用未 wait 的 fork 子进程维持 Z 状态，并打开配对 FIFO reader，确认 feeder 进入循环后在一个轮询周期内退出。
- 早期 Host 失败分别来自 shell 嵌套引号、测试父进程提前回收子进程、以及 FIFO 无 reader 导致 feeder 阻塞；均已按日志修正。Android Root Shell、真实 Frida Gadget 连接与真机生命周期仍未验证。


## 2026-11-05 — Gadget feeder /proc stat 复杂 comm 字段回归

- 扩展真实 Linux 僵尸子进程夹具：通过 PR_SET_NAME 将进程名设为包含右括号和空格的 `zombie ) fixture`，验证 feeder 仍能从 `/proc/<pid>/stat` 正确提取状态字段并退出。
- 该用例防止未来把 stat 的进程名字段误当作不含空格/括号的简单 token；生产实现使用最长匹配去除最后一个 `) ` 分隔符。
- 本提交待 Host 与 Module Runtime Regression 实际运行验收；仍不代表 Android Root Shell 或真机验证。

## 2026-11-06 — Dia Frida 脚本库分页呈现

- 脚本库原先对全部匹配脚本一次性创建完整 UI 行；现在增加每页 50 项的展示分页，所有脚本仍可保存、搜索、导入和导出，不限制脚本总数或脚本内容大小。
- 上一页/下一页根据完整过滤结果计算页数；搜索回到第一页；删除后自动钳制有效页码；Activity 重建保存/恢复当前页。
- 新增回归断言覆盖分页控件连线、仅渲染当前页、搜索复位及页面状态恢复。
- 本批验证：源码锚点与差异检查已在提交前执行；GitHub Actions 将在推送后运行定向 Host Regression。当前执行环境无法 DNS 解析 github.com，未能进行本地 Gradle/Android 构建；未进行设备测试。
- 下一批：将脚本库的完整数据加载与 SAF 导入/导出改为面向大数据集的文件/数据库流式路径，避免分页仅减少 View 数量而仍需将整个 JSON/脚本集合常驻内存。


## 2026-11-06 — Root Proxy activation-time tunnel address drift regression

- 基线 HEAD：`3c67945f9b15fcf67f3dc1ca7bfa828ce7bec4a7`；本批为 Root Proxy 运行时回归补充，不改动生产路由规则。
- 扩展 `scripts/tests/fx-yulong-root-proxy-runtime-regression.sh`：模拟 VPN 隧道在 DNS 引擎启动和 DNS 重定向激活期间将 IPv4 地址从 `10.23.4.5` 切换到 `10.23.4.6`，并断言 post-activation egress revalidation 拒绝提交活动状态、执行 fail-open 回滚。
- 保留原有 route-recheck 场景，新增 address-recheck 场景，验证地址漂移和路由漂移两种独立故障。
- 验证等级：待本批 GitHub Actions Host Regression 与 FX Module Runtime Regression 运行；尚未进行 Android 真机 VPN 切换测试。
- 下一批：继续检查 FX Root Proxy 的接口/地址重绑定及 Unbound 生命周期竞态；不将该 Root Proxy DNS 兼容路径等同于 FX 内核 VPN 数据面。


## 2026-11-06 — Root Proxy activation-time tunnel address drift regression verified

- 最新代码 HEAD：`6f20d26d9c1ea3f7df1337157834fdde3490771c`（包含 `test(dns): cover VPN tunnel address drift during activation` 与计数器 fixture 修正）。
- Host Regression：PASS，run [42069868626](https://github.com/vip-svip/SY/actions/runs/42069868626)。
- FX Module Runtime Regression：PASS，run [42069868514](https://github.com/vip-svip/SY/actions/runs/42069868514)。模块归档恢复、VPN/DNS 补丁应用、外部 VPN/TUN/DNS/watchdog 回归及 Root Proxy/native VPN 集成回归均通过。
- 新增 address-recheck 用例与既有 route-recheck 并列，覆盖 DNS 重定向激活期间隧道地址变化；测试通过，验证 Root Proxy 在活动状态提交前拒绝地址漂移并 fail-open 回滚。
- 本批仅为 Host/CI 模拟运行时测试；Android 真机 VPN 切换、DNS 泄漏和功耗测试未执行。
- 当前硬限制仍然有效：标准 Android 单用户/配置文件通常只有一个活动 VpnService 槽位；Root Proxy 是第三方 VPN 的 DNS 兼容路径，不等于 FX 内核 VPN 独立数据面，也不证明 ROM 级多 VpnService 并行。
- 下一批：检查 Root Proxy 在 VPN 接口重建、同名接口复用和地址快速轮换时的状态恢复，以及 Unbound 重载/停止失败后的 watchdog 收敛。


## 2026-11-06 — Root Proxy DNS probe answer validation

- 基线 HEAD：`ad3fdcefa738f59b6666460c218d66c6c5e59ea7`。
- 修复 Root Proxy 健康检查的误判：旧检查只要 nslookup 输出中出现任意 IPv4 Address 行就通过，可能把本地解析器自身的 127.0.0.1 Server 地址误当成域名答案。
- 新增统一 `_local_dns_probe`，只接受 `Name: example.com` 后的有效 IPv4 答案；ensure 和 status 共用同一验证逻辑。
- 增加启动与 status 回归：模拟 nslookup 仅返回 Server/127.0.0.1、不返回域名答案，必须 fail-open 并清理 FX 自有重定向。
- 本次功能测试结果以随后 Host Regression 和 FX Module Runtime Regression 为准；Android 真机 DNS 故障注入未执行。


## 2026-11-06 — Root Proxy rejects unusable DNS answer addresses

- 基线 HEAD：`5a429a81313dea2ca10b85e08ab7fbe7b0e099fe`；生产健康探测器已在前一提交中要求域名答案，避免将 Server header 误判为 DNS 成功。
- 本批补充回归：DNS 查询虽返回 `Name: example.com`，但答案地址为 `127.0.0.1` 时，必须因非可用单播地址而失败；确保不会仅凭存在答案字段就报告 DNS 健康。
- 新增 `probe-invalid-answer` 场景，复用生产 `_valid_ipv4` 策略校验答案地址。
- 待本批 CI 验证；不代表完成设备级网络故障注入。


## 2026-11-06 — Hook 授权状态可见性与六模式说明纠偏

- 基线 HEAD：`f32aa47202f55887764f582e0af47db4b220ab0b`。
- 修正 Hook Hub 中旧 `digXposed/active_tip` 偏好造成的状态遮蔽：关闭旧版 Manager 激活提示时，不再把整个 LSPosed 状态 TextView 隐藏；libXposed Binder 的实时连接/未连接状态始终可见。偏好现在只控制 Manager 安装提示行。
- 设置页界面模式说明改为准确列出六种模式：独立 Default + ClassicWebCompat、FXLiquidNative、MiuixStyle、HarmonyStyle、CupertinoStyle 五种皮肤；明确 Default 不是液态玻璃别名。
- 改动：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`。
- 验证：回读源码确认状态视图始终 VISIBLE、提示偏好只控制 managerHint、Binder 状态无条件生成；回读设置页说明确认六种模式和独立 Default。未运行 Gradle/Android 编译、UI 自动化或真机 LSPosed 状态验证。
- 下一批：继续核对六 Tab 与二级页返回/高亮状态；Hook Root、LSPosed Binder、Accessibility 状态刷新需在页面恢复时及时回读。


## 2026-11-06 — LSPosed live-state regression coverage

- Follow-up commit after the LSPosed status visibility correction.
- Extended `scripts/tests/fx-hook-native-ui-regression.sh` with executable Python source-contract checks proving that the legacy `active_tip` preference controls only the Manager hint, never hides the live Binder status, and that the displayed status retains the injection-state disclaimer.
- The same regression checks that the settings explanation names independent Default plus all five skins.
- This is a source-contract regression, not an Android UI/device test. CI must execute it before claiming regression coverage.


## 2026-11-06 — Hook top-level tab navigation cleanup

- Baseline HEAD: `cf559eb694698231cc6ba095ec17640103feea2e`.
- Cleaned the Hook tab branch in `handleNativeTabSelection(4)`: removed duplicated wording and aligned the selected-tab assignment with the branch scope.
- Added a source-contract regression ensuring the top-level Hook tab sets index 4 and returns to the app list, rather than retaining a nested Hook route.
- This is static source regression coverage; Android navigation behavior still requires Gradle/UI/device validation.


## 2026-11-06 — Refresh all Hook authorization states on foreground return

- Baseline HEAD: `f6b31b3985a082cb6f3ab1ef7985e3d1101ec09b`.
- Fixed a stale-state gap in `MainActivity.onResume()`: it previously refreshed LSPosed only on every foreground return, while Root, remote status and Accessibility depended on a pending `onPause` flag. The Hook hub now refreshes all authorization sources whenever it is foregrounded, regardless of whether that flag was set.
- The pending refresh flag remains available for the per-target LSPosed scope route; duplicate Hook-hub refresh is avoided.
- Added source-contract regression coverage for the lifecycle branch and all four refresh calls.
- Static source validation only; Android lifecycle/UI and real permission transitions still require device testing.


## 2026-11-06 — Root Proxy reconcile cleans orphaned DNS redirects

- Baseline HEAD: `73b7bb6b84acd629a4cfaf36178e43cda2cd6b8f`.
- Fixed a crash-recovery gap in `_reconcile_locked()`: when the authoritative active metadata file was missing, reconcile previously returned `active=0` without checking whether FXYRP OUTPUT hooks or companion markers were still present. A crash between NAT activation and metadata publication could therefore leave redirects attached without a validated VPN owner/interface record.
- Reconcile now detects active/egress markers and any attached FX-owned IPv4/IPv6 OUTPUT hook; if found without metadata it runs the existing fail-open cleanup, which removes only FX-owned chains and preserves independently enabled local DNS engines.
- Added runtime regression scenarios for lost metadata after activation and orphan hooks without marker files.
- CI execution is required for the new scenarios; no Android device test is implied.

## 2026-11-06 — Root Proxy preserves recovery state when firewall detach fails

- Baseline HEAD: a737ae7ec3f07c37040c66ec4265e42cd36ae867.
- Fixed a fail-open cleanup flaw: the hook removal loop previously treated any failed iptables delete as proof that a hook was gone, while global cleanup deleted active/egress markers regardless. A transient firewall failure could leave a live OUTPUT redirect with no recovery metadata, and stopping could take down the local resolver still targeted by that redirect.
- Cleanup now verifies each FX-owned OUTPUT jump is absent. If any remains, it returns failure, retains state markers, and does not stop shared DNS engines. A subsequent stop/status/reconcile can retry after the firewall recovers. Orphaned private chains remain harmless once their OUTPUT jump is detached.
- Added a runtime regression that injects an IPv4 detach failure, checks marker/resolver preservation, then retries cleanup successfully.
- CI is pending for this change; no Android device validation is implied.

## 2026-11-06 — Surface incomplete Root Proxy cleanup to status/reconcile callers

- Follow-up to the firewall-detach recovery fix at cd276977211be84b8dd4f45a17765a28954cd23a.
- Status and missing-metadata reconcile now propagate a failed cleanup instead of returning a normal inactive result. Status emits cleanup=failed while preserving the retry markers and resolver.
- Added a status-path regression that forces iptables detach failure and verifies the error is surfaced, then confirms a subsequent stop clears the state.

## 2026-11-06 — Propagate cleanup failure through Root Proxy status

- CI for the initial cleanup-failure hardening exposed two gaps in its new regression: the mocked detach fault targeted only one alternating IPv4 chain, and status branches discarded `_status_fail_open`'s nonzero result with an unconditional return 0.
- The fault injection now rejects deletion of either FX-owned IPv4 OUTPUT jump. Every status fail-open branch propagates the cleanup result, so callers can distinguish a fully cleaned inactive state from an incomplete firewall cleanup.
- The targeted host and module runtime workflows are rerun on this correction; previous failed runs remain recorded rather than being represented as passing.

- Follow-up: the disabled/not-active early status branches also now propagate cleanup failure; all status fail-open paths consistently return the cleanup result.

- Test-fixture correction: the status cleanup-failure scenario now also forces the DNS health proof to fail, ensuring status actually enters its fail-open cleanup path before the firewall detach fault is asserted.

## 2026-11-06 — Correct status cleanup failure test precondition

- The first status-path regression attempt injected firewall delete failure but left the health state healthy, so status correctly did not enter cleanup. Corrected the fixture to inject both a DNS health failure and the firewall detach failure.
- No production behavior change in this test-only correction.

- Regression harness refinement: the status cleanup-failure test now corrupts the active interface metadata to force the validation/fail-open branch deterministically before injecting firewall detach failure; it no longer depends on DNS-probe fault propagation.

- Fixture metadata is written with `printf '%s\\n'` arguments so the invalid interface is a real first-line field rather than a literal backslash sequence.

## 2026-11-06 — Disabled Root Proxy ensure propagates cleanup failure

- Baseline HEAD: 87d56337aba65761a514e61c2c6af6034b784b4c.
- `_ensure_locked()` previously ignored `_stop_locked()` failure when the proxy was disabled and returned success, even if an FX-owned OUTPUT DNS redirect remained attached and its recovery metadata/resolver had intentionally been preserved.
- Disabled ensure now returns non-zero when firewall cleanup is incomplete. Added a runtime regression that activates the proxy, disables it while injecting an iptables detach failure, verifies marker/resolver preservation, then retries successfully after the fault is removed.
- No Android device validation is implied.


## 2026-11-06 — Root Proxy legacy lock cleanup hardening

- Branch HEAD before this batch: `bb18cf2246f8fc3f24aabfaae1a454da4097626d`.
- Source commit: `e8246fdfcf4f2dcf0abda9a5798662866667af48`; regression additions: `a91f23f2592ceb14670ad7eb6f72d9adbf15d937`; fixture newline correction: `472451b2b7c6d3a2853aad4aa98ddb2f8babcae3`.
- Changed `fx-module/scripts/yulong-root-proxy.sh`: legacy lock-directory retirement no longer uses recursive `rm -rf`. It accepts only an empty directory or a directory containing exactly one non-symlink regular `pid` file; unknown entries and symlinks are preserved and cleanup fails closed. Canonical regular-file locks continue to be removed normally.
- Changed `scripts/tests/fx-yulong-root-proxy-runtime-regression.sh`: extracted production lock remover is exercised against valid PID-only directories, empty directories, canonical regular files, and a legacy directory containing unrelated nested data.
- Verification: isolated host-shell execution of the production-equivalent lock-removal cases passed. The complete Root Proxy runtime regression harness and full source `sh -n` were not run in this environment because a repository checkout/runtime download is unavailable. GitHub combined status returned no checks and the available commit-workflow query returned no runs; CI result is therefore unknown, not passed. No Android build, install, emulator, or real-device validation was performed.
- Current branch HEAD at state update: `472451b2b7c6d3a2853aad4aa98ddb2f8babcae3`.
- Next implementation focus: continue Root Proxy / independent local DNS coexistence and service lifecycle tests; then proceed with the next complete native UI page group. Preserve existing VPN and DNS routes; do not generate a final APK/module before acceptance gates.


## 2026-11-06 — VPN 共存原生状态卡补齐槽位与 UID 证据

- 本批基于分支 HEAD `d043ba89c41dafc605a08fda692f06de92d59d0e`，将 VPN 共存卡片补齐快照中的第三方 VPN UID 与 `vpn_service_slot_used`。
- 当快照明确给出 `false` 时，UI 显示“FX 内核数据面不占 Android VpnService 槽位”；明确为 `true` 时显示正在占用；旧快照缺字段则显示未知，不猜测。
- 保留路由探测的 fail-closed 文案：只有 `route_probe=verified` 才显示已验证；其他值均显示未验证。
- 改动：`adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`、`scripts/tests/fx-vpn-coexistence-ui-regression.py`。
- 验证状态：源码锚点和回归断言已更新；提交后等待 GitHub Actions Host Regression。尚未进行 Android Gradle 构建、模拟器或真机测试；UI 回归属于源码契约检查，不等于设备端渲染验收。
- 平台边界不变：该字段仅说明 FX 内核数据面不占普通 VpnService 槽位，不代表 Android Framework 支持多个活动 VpnService。


## 2026-11-06 — Dia 结构化监控日志路径防符号链接

- 基于分支 HEAD `6b692997c4cc29e0bbf0024d620abc99dd4ec758` 检查 Frida 结构化事件页时，发现只拒绝最终日志文件符号链接仍不够：父目录若被替换为符号链接，Root 读取仍可能跟随到模块状态目录之外。
- 读取前现逐级验证 `/data`、`/data/adb`、`/data/adb/privacyguard`、`dia-frida`、`logs` 均为真实目录且非符号链接；日志文件本身也显式拒绝符号链接。缺少尚未创建的日志目录仍返回“暂无事件”，不将正常首次启动误报为安全故障。
- 更新 `scripts/tests/fx-dia-monitor-event-view-regression.sh`，守护全部父目录检查与符号链接拒绝契约。
- 本批验证级别：代码/测试契约修改；待本提交 Host Regression 实际执行。尚未运行 Android Gradle 构建或设备端 Frida 注入/日志验证。


### Frida 清空会话日志根目录校验补齐（2026-11-06）

- 复核清空日志 Root 命令时补上 `/data` 本身的目录/符号链接检查，避免只校验 `/data/adb` 以下路径而遗漏最上层父目录。
- 对 `/data`、`/data/adb`、FX 状态目录、Dia 目录、logs 目录均要求存在且为非符号链接目录；目标日志仍需是非符号链接普通文件，清空成功必须由退出码和完成标记共同确认。
- 回归脚本增加 `/data` 根目录拒绝符号链接断言。本次为源码和静态契约更新；后续 CI 重新验证。


### Dia Gadget 会话回归断言同步（2026-11-06）

- 最新提交增加 `/data` 根目录的 fail-closed 检查后，原 Gadget 会话回归仍匹配旧的 `if [ -L '/data/adb' ]` 前缀，导致 Host Regression 在静态断言处失败。
- 将断言同步到当前 guard 顺序：先检查 `/data`，再检查 `/data/adb`；产品逻辑无需回退。后续以当前 HEAD 的 Host 与模块 CI 实际结果为准。


## 2026-11-06 — Dia 结构化监控事件刷新队列有界化

- 将事件页原先无界的单线程 Executor 改为单执行线程、一个待执行槽位的 ThreadPoolExecutor。
- 新刷新到来而待执行槽位已满时，淘汰旧的待执行请求并仅保留最新请求；正在执行的 Root 读取仍受 15 秒超时和输出上限约束，过期 generation 的回调仍会被丢弃。
- Activity 销毁后继续使用 shutdownNow；队列饱和不再导致无限堆积的特权 Root 读取任务。
- 增加源码回归断言覆盖队列容量、最新请求淘汰与 shutdown 拒绝策略。尚未做 Android Gradle 构建或设备端刷新压力测试。


## 2026-11-06 — 游龙 Tasker 授权应用选择器

- 在 Ad 通用设置的 Tasker/自动化广播卡新增“选择已安装应用”入口。选择器仅读取 Android 可见且带桌面 Launcher 入口的应用，不申请全量应用可见权限；列表显示应用标签和包名，并排除 FX 自身。
- 选择应用只填入包名，不固定签名、不打开外部 Root 控制。用户仍必须单独点击“验证包名并固定 APK 签名”，再手动启用授权开关；未出现在列表的应用仍可手动输入包名。
- 扩展 Tasker/Receiver 回归，检查 launcher 选择流程、包名校验和“选择不等于授权”的交互边界。
- 验证：待当前提交 GitHub Host / 六套 UI 回归；未进行 Android Gradle 构建、设备端应用列表和 Tasker 广播验收。


### Tasker 应用选择器 Host 断言校正（2026-11-06）

- Tasker 选择器回归首次运行时，Host 因将跨行 `queryIntentActivities` 调用误当作单行 token 而失败；已拆成方法名和查询 flag 两项源码断言。
- 加强安全契约：选择器方法不得写入授权包名、签名摘要或 Root 外部授权开关；签名固定及授权仍由独立显式操作执行。
- 当前仅修正测试匹配和增加边界断言；待最新 HEAD 的 Targeted Host Regression 再验证。


## 2026-11-06 — 游龙 Ad 本机总结刷新一致性

- 本机防护总结的配置读取与 DNS 聚合计数改为共享刷新代次；旧代次的 Root 回调不会再覆盖用户最新一次刷新结果。
- 将原先最多堆积 8 个 Root 读取的线程池收紧为 1 个执行线程 + 1 个待执行槽位。队列满时只保留最新请求；Activity 销毁时递增 generation 并关闭 worker。
- DNS 统计数据来源、只返回数字的隐私约束、日志关闭默认值和 30 天保留说明均保持不变。
- 同步 `scripts/tests/fx-yulong-ad-dns-summary-regression.sh`，覆盖 bounded queue、latest-only request 与回调 generation。尚未运行 APK 构建、模拟器或真机统计刷新压力测试。


### 前一批 Dia 刷新/路径修复验证记录

- `6ec508f5fd41cf6eeeba97e5bed60ab6ebc0c0e7` 的 Targeted Host Regression run `42091648985`：SUCCESS；FX Six UI Modes run `42091649028`：SUCCESS。
- 该提交的 Module Runtime Regression run `42091648844` 最终标记 CANCELLED；取消前 TUN/DNS/watchdog 与 Root Proxy/native VPN 两个实测步骤均显示 SUCCESS。故记录为“相关回归步骤通过、workflow 总结状态取消”，不表述为完整 workflow success。


## 2026-11-06 — LSPosed 提示补丁器与 Tasker 回归映射修复

- 新增隔离 fixture Host 测试，实际执行 `ensure_lsposed_manager_notice.py`，覆盖 Hook Hub / 配置发布提示插入、重复执行幂等，以及发布按钮锚点丢失时拒绝写入且不留下部分修改。
- 将该补丁器接入 targeted Host 回归，修复只修改 `fx-patches/ensure_lsposed_manager_notice.py` 时被误判“没有 Host 回归映射”的 CI 阻断。
- Tasker 回执回归调整为检查实际实现的 `target` 局部变量与 Intent extra，避免依赖旧的内联三元表达式写法；同时明确将 Tasker receiver / General Activity 改动映射到 Tasker 并发回归及 Widget 回归。
- 本批代码与工作流改动已提交；验证以新提交 Actions 结果为准，未声称 Android 构建或设备端验收。


### Ad 本机总结刷新队列容量回归修正（2026-11-06）

- 首次提交的定向 Host 回归指出 Summary Activity 的线程池容量仍是旧值 8；最新请求替换逻辑已存在，但队列并未真正收紧。现将容量修正为 1，与单 active + 单 waiter 的设计和测试断言一致。
- 上一提交 run `42092065276` 的 Host Regression 为 FAILURE，失败位置为 `fx-yulong-ad-dns-summary-regression.sh` 的队列容量断言；当前修订等待新的 Host/UI/Runtime 回归。


### Host 回归覆盖补全（2026-11-06）

- Tasker 并发回归的旧断言错误地要求 `target` 三元表达式直接写在 Intent extra 中；修正为分别匹配实际的 `String target = ...` 和 `.putExtra("target", target)`，保持对广告过滤与 VPN 两条控制面的语义检查。
- LSPosed 管理器提示补丁器回归再补充 Hub 定位锚点缺失用例，确认在 Hub / 发布按钮锚点缺失时都不会将部分改动写回源文件。
- 此提交仅完善 Host 回归与文档，Android 构建/设备验证仍未执行。


## 2026-11-06 — Ad 总结页 Root 模块解析路径加固

- 检查 `FxYulongAdSummaryActivity.moduleShell()` 时发现，Summary 页的 Root 读取 resolver 只检查 `module.prop` 内容，可能跟随被替换为符号链接的模块目录、元数据文件或脚本目录。
- 现对 `/data`、`/data/adb`、`modules`、`modules_update` 以及候选模块目录、`module.prop`、`scripts` 目录和 `yulong-ad-control.sh` 本体逐层拒绝符号链接；同时要求模块 ID 与 `version=1.0.0` 精确匹配。
- 扩展 DNS summary Host regression，覆盖这些 Root 命令解析前置条件。此前 Summary 队列容量已收紧为 1，刷新代次仍保证新结果优先。
- 本批未声称 Android Gradle 构建或设备端验证；等待当前提交 Targeted Host、六套 UI 与模块 Runtime workflow 结果。


### Ad 总结页模块解析回归断言修正（2026-11-06）

- Targeted Host run `42092733168` 指出新的模块路径静态断言将分成两段 Java 字符串拼接的 `/data/adb` 检查误认为一个连续字面量。
- 修正测试为分别验证 `/data/adb` 目录存在与非符号链接两个条件；Root resolver 不作逻辑变更。当前提交之后会重新观察 Host 回归结果。


### Ad 总结页模块父目录类型验证加固（2026-11-06）

- 在拒绝 symlink 的既有基础上，进一步要求 `/data/adb/modules` 必须是真实目录；`modules_update` 允许不存在，但若存在必须是真实目录且不能是符号链接。这样避免父路径被替换为普通文件时被静默忽略或产生不明确的候选路径解析。
- 回归覆盖 modules 目录存在且非 symlink、modules_update 可选目录的类型语义；模块目录、元数据、脚本目录和入口脚本的既有检查保持不变。
- 父提交 `da3b9c70` 的 Host Regression run `42092919337` 与六套 UI run `42092919389` 均 SUCCESS。当前新增父目录类型边界的代码仍待新提交 CI 验证。


## 2026-11-06 — Hosts cache legacy lock fail-closed hardening

- 修复 `fx-patches/patch_hosts_file_lock.py` 生成的旧目录锁清理逻辑：`_hf_read_lock_owner` 现在只会读取非符号链接的普通 `pid` 文件，避免对 FIFO 执行 `cat` 而阻塞；`_hf_remove_lock_path` 不再使用递归删除。
- 旧目录锁只允许两种安全清理形态：空目录，或只含一个普通、非符号链接 `pid` 文件的目录。未知文件、隐藏文件、嵌套目录、FIFO 和符号链接均拒绝清理并保留现场。
- 锁补丁升级标记为 V3，使已使用旧 V2 的模块在重新打包时也能重写安全清理函数。
- 新增 `scripts/tests/fx-hosts-cache-lock-regression.sh`，动态执行生产函数并覆盖空目录、PID-only 目录、普通文件锁、未知/隐藏内容、外层 symlink、PID symlink 与 FIFO；在 KernelSU 包装阶段接入该补丁和回归，并在 Targeted Host Regression 中按补丁路径触发。
- 本批待 CI 验证；未运行最终 KernelSU 包生成、APK 构建或设备安装。


### Yulong 防火墙迁移回归适配当前导航（2026-11-06）

- 旧 Host/迁移流水线的防火墙回归仍通过 `应用管理` 与 `HTTPS 与证书` 两个旧分类标题切片 MainActivity；当前 FX Ad 原生页已改为独立 `应用网络防火墙` action card，旧标题不存在时测试直接抛出 `ValueError`。
- 将回归改为验证当前 Ad action card 直接打开 `FxYulongFirewallActivity`，同时验证 Activity 仍兼容 `用户应用`、`系统应用`、`按应用设置` 三种 suite_page 并执行真实系统/用户包分类过滤。
- 该修复仅调整过时的导航断言，不改变防火墙实现；待新 Host/模块 Runtime workflow 验证。


## 2026-11-06 — Ad 总结配置协议严格校验

- 修正 Summary 页 `parseConfig()` 的默认值风险：原解析器在输出缺少 `AD_MASTER`、主开关重复/非法，或规则/域名记录格式损坏时仍返回对象，可能将读取失败伪装成广告过滤关闭与零计数。
- 现要求 `AD_MASTER` 恰好出现一次且值为 0/1；RULE/ALLOW/BLOCK 记录的启用字段必须为 0/1；未知记录、畸形记录或缺少主状态全部拒绝。UI 收到无效配置协议时停止本次汇总，不继续消费 DNS 统计并冒充完整状态。
- DNS 统计数字仍以本机当前保留日志的隐私聚合结果为准，不读取或展示原始域名/IP。
- Summary 路径安全及并发读取：提交 `31c275c57ebb`、`64fbd542197e` 分别加入候选模块和父目录类型/symlink 校验；修正 Host 源码匹配断言后，`da3b9c70ee5c` Host `42092919337`、Six UI `42092919389`、Module Runtime `42092919165` 均通过。
- 本批严格解析器改动提交后须重新观察 CI；APK 构建、安装、设备 DNS UI 验收均未在本批完成。


### Hosts cache lock V3 与旧集成回归同步（2026-11-06）

- `FX Module Runtime Regression` 对 V3 的首轮验证中，外部 VPN/TUN/DNS/watchdog 回归组全部通过；Root Proxy/native VPN 集成组最后在旧断言 `FX_HOSTS_FILE_LOCK_V2` 处失败。失败原因是测试仍要求旧版标记，不是新锁运行逻辑失败。
- 已将 `fx-atomic-cache-lock-release-regression.sh` 的两处 Hosts 版本断言更新为 V3，并把新动态安全清理回归嵌入该完整缓存锁回归。后续模块回归会同时验证真实补丁器和 FIFO/符号链接/未知内容拒绝策略。


### Hosts V3 锁标记兼容性回归修正（2026-11-06）

- 当前 Module Runtime run `42093393397` 的 TUN、DNS、watchdog 回归步骤通过；Root Proxy/native VPN 集成步骤失败在 Hosts 原子锁 marker 断言，原因是新 Hosts 安全清理实现已升级为 `FX_HOSTS_FILE_LOCK_V3`，而旧回归仍硬编码检查 V2。
- 将 `fx-atomic-cache-lock-release-regression.sh` 中 Shell 与 Python 两处 marker 断言同步到 V3；不改变锁实现与运行行为。当前提交等待 Host 和 Runtime 重新验证。


### Yulong 防火墙 Host/Package 回归源选择修正（2026-11-06）

- Host Regression 发现无参数模式读取仓库 `fx-module/` 下的旧 Release 快照，而不是 canonical `scripts/yulong-app-firewall.sh`；该快照尚未运行 package lane 的 source-restoration patcher，因此缺少 UID 变更拒绝逻辑。
- 无参数 Host lane 现直接测试 canonical 脚本；显式传入模块目录的 package/runtime lane 仍测试 patcher 恢复后的模块副本。两条路径分别验证源码本体与最终模块产物。
- 前一 Host run `42093526987` 因该错误源选择导致 UID mismatch 回归失败；当前修订等待新 CI 验证。


### Hosts 锁安全回归在 Host-only lane 独立运行（2026-11-06）

- `fx-atomic-cache-lock-release-regression.sh` 在普通 Host checkout 中因 Release-only `apply.sh` / `subfetch.sh` 缺失，会提前跳过完整缓存锁链路。此前虽然新增了独立合成夹具，但该早退分支未调用它，导致 Host lane 没有真正执行这项新回归。
- 现将独立 Hosts lock safety regression 放到早退分支，在缺少 Release module 时仍直接动态运行补丁器与生产锁 helper；Release module 存在时则由完整缓存锁回归调用。
- `e6120449` 的 Host Regression 与 Six UI Modes 均通过。Module Runtime Regression 仍在进行；其中 VPN 共存/TUN/DNS/watchdog 步骤已经 SUCCESS，等待 Root Proxy/native VPN 集成步骤结束。


## 2026-11-06 — Ad 应用防火墙分类页恢复为可达原生路由

- 检查原生 Firewall Activity 发现它虽已支持 `suite_page` 与用户/系统应用过滤，但 FX 壳层没有传入这些页面值，也没有页内分类切换入口；三个原始分类无法从当前 UI 到达。
- 在唯一的 FX Firewall Activity 中加入“按应用设置 / 用户应用 / 系统应用”三项切换，分别显示全部应用、非系统应用、系统及更新系统应用；标题与范围说明同步更新，底层继续使用同一个 IPv4/IPv6 应用防火墙，不创建额外服务或重复 Activity。
- 分类选择纳入 Activity 状态恢复。PackageManager 清单读取采用单活动 + 单待执行槽位，类别快速切换时淘汰旧的待执行任务，并通过 generation 丢弃过期结果，避免较早的用户/系统筛选覆盖当前选择。
- 更新行为与 UI 定向回归，并将 Firewall Activity / Ad Activity 改动映射到 Host workflow。
- 已知历史阻塞：完整 FX APK migration workflow `42092600253` 曾在旧 app-firewall 测试对已迁移 MainActivity 分类代码执行 `index()` 时失败（`ValueError: substring not found`）；之后测试已改为 FX 当前 native entry contract。此批重新校验这一页面的真实可达性。
- 本批尚未宣称 Android Gradle 构建、安装、模拟器或真机验证完成。


### 防火墙分类 Host 回归与策略职责对齐（2026-11-06）

- 当前 Host run `42094107263` 已运行到应用防火墙回归，失败原因是测试仍要求 Firewall Activity 本体出现 `FLAG_SYSTEM` / `FLAG_UPDATED_SYSTEM_APP` 字段名；实际实现把分类规则集中在纯策略类 `FxYulongFirewallAppFilterPolicy`，Activity 仅把 Android ApplicationInfo flags 传入策略。
- 将回归改为验证策略类中 ALL/USER/SYSTEM 三种模式和两种系统标志位，并检查对应单元测试仍覆盖 unknown mode fail-closed；不为迎合旧断言在 Activity 保留无用变量。
- 分类页面实现与异步 generation 逻辑不变，当前提交后会重新触发定向 Host/UI 检查。


### 防火墙系统应用标志常量回归同步（2026-11-06）

- `FxYulongFirewallAppFilterPolicy` 将 Android `FLAG_SYSTEM` 与 `FLAG_UPDATED_SYSTEM_APP` 的位值提取为具名常量，保持 policy 类不依赖 Android SDK、可由 Host JDK 单测执行。
- 同步静态回归：不再要求位掩码以数字字面量出现，改为分别检查两个具名常量的值及实际参与位判断；分类行为本身不变。
- `d71d4021` 的具名常量重构后，旧的数字字面量断言会失配；本修订修复测试与实现的表达方式差异。


## 2026-11-06 — VPN 共存槽位状态必须来自完整模块证据

- 修正此前槽位状态过度确定的问题：共存状态发布器曾硬编码 `vpn_service_slot_used=false`，而 arbiter 在没有传入模块根目录时也会默认返回 false。现在仅当模块根目录、`module.prop`（ID/version）及四个关键数据面脚本均为可读取的非符号链接普通文件，并完成静态扫描后，才返回 true/false；模块缺失、文件缺失或路径不可信均返回 unknown。
- Arbiter 在生产调用时从自身 `scripts/fx-vpn-coexistence-arbiter.sh` 路径推导模块根目录；测试仍可注入隔离根目录。若扫描命中 VpnService.prepare/Builder 调用，即使其他扫描文件缺失也报告 true；只有全部必需文件扫描完整且未命中才报告 false。
- 槽位扫描 unknown 现在使 arbiter verdict 变为 `unknown`、退出码 2，并在 JSON 中输出 `vpn_service_slot_used:null`。状态发布器解析 arbiter 的 true/false/null，不再写入硬编码 false；缺少/旧版本 arbiter 字段也输出 null 并将等级降为未知。
- MainActivity 只接受 JSON Boolean 类型作为确定槽位证据；缺失、null 或其他类型均展示“FX VpnService 槽位状态未知”。
- 新增/更新 arbiter 回归：完整模块 fixture、缺少文件 fixture、installed-path 自动发现、阳性 VpnService 命中；状态发布器回归覆盖 true/false/null 和缺少 arbiter；UI 回归覆盖 strict Boolean 读取。
- 本批尚未在 Android 设备上验证系统实际槽位状态；静态扫描证明的是所列数据面脚本未调用 VpnService API，不证明路由/回程/DNS 数据路径，`route_probe` 仍保留 unverified。



## 2026-11-06 — Hosts 锁与 Ad 防火墙分类回归闭环

- 最新稳定验证提交 `4d996b44cd24199c59af3c0172576c7a2e9710fc`：Targeted Host Regression run `42094679264` SUCCESS；FX Six UI Modes run `42094679466` SUCCESS；FX Module Runtime Regression run `42094679551` SUCCESS。
- 模块运行回归中 Release module restore、VPN/DNS/Root Proxy patching、外部 VPN/TUN/DNS/watchdog 回归组，以及 Root Proxy/native VPN/cache-lock 集成回归步骤均完成 SUCCESS。
- `scripts/tests/fx-atomic-cache-lock-release-regression.sh` 的 Host-only 分支现在会运行 `fx-hosts-cache-lock-regression.sh` 的合成生产函数夹具；Host run `42093993446` 日志确认 `PASS: Hosts cache lock cleanup removes only empty/PID-only locks and refuses FIFO, symlink and unknown contents`。
- Ad 防火墙分类回归路径在 `4d996b44` 修复为显式传入 `FxYulongFirewallAppFilterPolicyTest.java`，不再从 Java 源文件路径反推测试目录。最新 4d996b44 Host run 全量通过。
- 验证边界：以上为 GitHub Actions Host 自动化、六套 UI 源码契约和恢复版模块运行测试；仍未完成 Android Gradle 最终 APK 构建、最终 KernelSU ZIP 生成、设备安装/升级/卸载或真机 VPN/TUN 测试。`migration_complete` 仍保持人工门控，不为绕过未完成迁移而触发最终包构建。


### 应用防火墙策略源文件回归映射（2026-11-06）

- 将 `FxYulongFirewallAppFilterPolicy` 与其 Host 单测类 `FxYulongFirewallAppFilterPolicyTest` 加入 Targeted Host firewall 回归路径，确保只修改用户/系统应用分类规则时也会执行 `fx-yulong-app-firewall-regression.sh` 与 `fx-yulong-firewall-activity-regression.sh`。
- 完整闭环已在 `4d996b44` 的 Host/UI/Module Runtime runs 中验证；本次仅扩大后续增量变更的 CI 触发覆盖。


### VPN 槽位证据集成回归修正（2026-11-06）

- `53512fa05345` 中新增的 arbiter fixture 核心场景均通过；CI 进一步发现状态发布器测试夹具把 `\\n` 写成了字面字符，导致模拟 arbiter 实际输出不是有效 JSON，7 项状态断言失败。现改为真正的多行 shell fixture 和单行 JSON 输出。
- 状态发布器增加一致性约束：slot=true 强制 verdict=incompatible；slot=false 才保留 arbiter verdict；slot 缺失/null/非法时强制 verdict=unknown。避免旧版或缺失模块扫描的 arbiter 仍发布 partial/kernel_only。
- Live arbiter smoke assertion 修正为接受“仓库 checkout 不含完整已安装模块树”时的 `vpn_service_slot_used:null` + verdict unknown；只有扫描证据为 false 时，才要求无隧道/可读接口显示 kernel_only。
- 上一个提交 `53512fa05345` 的 Arbiter regression 主要场景通过，但 live runner smoke 因未提供完整模块根而返回 exit 2；Module Runtime workflow 在状态发布器回归处失败。上述均为本提交修复对象，不能记为通过。


### VPN 槽位状态验证边界修正（2026-11-06）

- CI 复查 `574c83d64640`：状态发布器的 true/false/null 断言已全部通过；仅“arbiter 不可用”用例的 `FX_COEXIST_ARBITER` 环境变量覆盖仍读到原模块夹具，改用确定存在但输出为空的 `/dev/null`，验证无有效 arbiter JSON 时应降级到 local/unknown/null。
- Live smoke workflow 原先在 `set -e` 下执行 arbiter，合法的 fail-closed 退出码 2 会令 shell 提前结束，未把 JSON 交给 live assertion。现在仅接受退出码 0 或 2，再由 Python 校验状态与退出码一致；当 slot 为 null 时必须 verdict=unknown 且 exit=2。
- 本轮之前的 Host 失败只在 case 9 的 source 标签断言；arbiter fixture 的 true/false/null 案例和六套 UI 均已通过，完整 Runtime finalize 步骤因同一 Host 测试失败而停止，待本修正提交重新验证。


### VPN 共存发布器来源标记校验（2026-11-06）

- 状态发布器此前仅凭 arbiter 路径可读就把 `source` 标成 `arbiter`；当路径指向空文件（如 `/dev/null`）或旧版/不完整 helper 时，实际数据来自本地 fallback，却被错误标记为 arbiter。
- 现在仅在 verdict、grade、probe 与 slot 字段均完整时接受 arbiter 记录；否则标记 `source=local`，再由槽位证据规则将缺失/null/非法 slot 降为 `unknown`。slot=true 仍强制 incompatible，slot=false 才保留已验证的 arbiter verdict。
- 修复 Host 回归 case 9 对 `/dev/null` 的真实边界验证，不改变网络数据面与端口探测行为。


### VPN 发布器无 arbiter 场景测试夹具隔离（2026-11-06）

- `574c83d64640` 的 case 9 将 `FX_COEXIST_ARBITER` 指向 `/dev/null` 后，测试仍意外得到 `source=arbiter`；状态结果本身已正确为 `unknown/null`。为消除 shell 环境覆盖歧义，改为使用不含 arbiter 文件的独立模块根目录，直接验证发布器的真实 default-path fallback。
- case 9 继续要求无 arbiter 时 verdict 必须为 unknown、槽位字段必须为 JSON null；不因来源标签而弱化核心安全断言。


### Yulong 7.0.1 规则导入数量基线同步（2026-11-06）

- KernelSU package run `42095725390` 已完成 ZIP 解码、规则分类和 Hosts/AdGuard 注册检查，失败仅在回归仍固定期待 210,097 个 DNS 域名；当前校验过 SHA-256 的上游资产实际解码出 210,118 个唯一域名（增加 21 条），cosmetic/exception 规则数仍为 3,476。
- 将精确域名基线更新为 210,118，并显式断言输出无重复；不改变规则解码、过滤或合并逻辑。由于上游 ZIP SHA-256 固定，此基线仍可重复验证。
- 当前修订等待新的 KernelSU package workflow；先前该 run 在规则数量断言失败后未进入补丁整合、APK/QuickJS 编译或 ZIP 打包阶段。


### Yulong DNS 规则 Host-only / Package lane 分界修正（2026-11-06）

- `22144b49` 更新固定规则数量后，Targeted Host Regression 运行 `fx-yulong-ad-rule-import-regression.sh` 时没有传入恢复后的模块路径；Host-only checkout 不包含由校验过的 Yulong APK Trie 解码生成的 `Yulong_AdBlock.txt` 与 Cosmetic 文件，因此在预检处触发 FileNotFoundError。
- 回归脚本现明确区分：未传模块路径且生成规则文件不存在时，Host-only lane 输出 SKIP；KernelSU package lane 显式传入恢复模块目录，文件缺失仍为 FAIL，继续执行 210,118 DNS 域名、3,476 Cosmetic 规则和 Hosts/AdGuard/sing-box 集成断言。
- 不跳过规则解码器的 Bloom/TRIE 校验，也不在 package lane 放宽数据数量/内容断言。待本提交 Host、Module Runtime 和 KernelSU package workflow 验证。


### Yulong 规则导入 Host-only 与完整数据集回归分层（2026-11-06）

- `22144b49` 的 Host Regression 在运行 `fx-yulong-ad-rule-import-regression.sh` 时失败，原因是无 Release restore 的普通 checkout 没有 `fx-module/rulefiles/Yulong_AdBlock.txt`。这不是解码或 DNS 路由行为失败，而是 Host lane 误要求正式包构建后才存在的 210k+ 规则数据。
- 新增 Host-only 分支：无 `fx-module` 且未传模块参数时，只验证 decoder/importer 的输入输出契约、`[list:rule]`/FX anti-fraud 分区隔离、 pinned 210118 DNS / 3476 cosmetic baseline 及 KernelSU package workflow 的完整模块测试接线，然后明确打印 SKIP/PASS 边界并退出。
- 正式模块数据回归保持不变：KernelSU package lane 下载校验固定 SHA-256 的原始 Yulong 资产，解码后对 210118 域名去重、3476 cosmetic/exception 规则和 AdGuard/sing-box/Hosts 路由做完整行为回归。Host-only 静态检查不声称覆盖这些真实规则数据。
- `22144b49` 的 Host 首次失败与当前 `22144b49` Module Runtime Regression SUCCESS 分开记录；最终 APK/KernelSU ZIP 仍未完成。


## 2026-11-06 — Ad 防火墙共享 UID 作用范围提示

- Android owner UID 防火墙匹配的是 UID，不是包名；多个已安装应用共享 UID 时，底层规则无法只隔离其中一个包。原 UI 逐包显示开关，容易让用户误以为共享 UID 应用可独立控制。
- 应用清单加载阶段现先基于完整已安装应用列表建立 UID 分组，再按“用户应用/系统应用/全部”筛选页面，确保切换分类不会把同 UID 的另一应用隐藏在检测之外。
- 对共享 UID 的列表行显示影响范围；快速开关变更和详细配置入口均先展示明确确认对话框，说明规则会影响该 UID 下的全部应用。用户取消时快速开关会回滚；单 UID 应用保持原来的直接操作路径。
- 扩展 Android-free UID policy 与 Host 单测，覆盖唯一 UID、重复 UID、未知 UID、无效 UID、缺失快照；将 JDK Host test 接入 fx-yulong-firewall-activity-regression.sh。
- 验证：提交后由 Targeted Host Regression 与 Six UI Modes 执行；本批未进行 Android Gradle 构建、模拟器或真机 shared-UID 网络阻断测试。


### KernelSU 包装流程同步 canonical Hook installer/remover（2026-11-06）

- KernelSU package run `42096247931` 已通过 DEX 资源暂存、Release 模块恢复及 Yulong 7.0.1 规则解码/导入；在“应用 reviewed FX source compatibility patches”阶段，`adhook-app-installer-regression.sh` 发现恢复版 Release 模块仍携带旧 `fx-module/scripts/install_adhook_app.sh`，缺少新系统应用覆盖层优先策略。
- 在运行安装器回归之前，KernelSU workflow 现在显式将仓库 canonical `scripts/install_adhook_app.sh` 与 `scripts/remove_adhook_app.sh` 以 0755 暂存到 `fx-module/scripts/`。boot service、uninstall hook 和回归测试因此针对同一份已审阅实现。
- 不改变 APK 签名、PackageManager 或 SELinux 策略；此改动确保发布模块不会继续打包过期安装器。下一次 KernelSU package run 将继续验证 QuickJS-NG、APK Gradle 构建和最终 ZIP。


### KernelSU 安装器系统应用覆盖层回归闭环（2026-11-06）

- KernelSU package run `42096247931` 在 `Apply reviewed FX source compatibility patches` 阶段失败：恢复 Release ZIP 后，`adhook-app-installer-regression.sh` 先读取到旧版 `fx-module/scripts/install_adhook_app.sh`，因此未找到系统应用 overlay 优先逻辑。
- 仓库 canonical installer 本身已正确选择 `system/app/FX/FX.apk`，并在 PackageManager 不确认 system-app 分类时拒绝回退为普通应用；问题是 KernelSU workflow 未像 APK workflow 一样在回归前同步 canonical installer/remover。
- KernelSU workflow 现先覆盖同步 `scripts/install_adhook_app.sh` 与 `scripts/remove_adhook_app.sh`，再用 `cmp -s` 验证模块副本逐字节一致，最后才执行安装器回归。回归脚本增加顺序检查，防止以后先测试旧 Release 脚本。
- 本批没有更改安装器运行逻辑、系统权限或签名策略；等待新 KernelSU package workflow 验证恢复、同步、overlay 检查及后续完整打包阶段。


### 系统应用安装脚本发布映射防回归（2026-11-06）

- 在 KernelSU workflow 中补入 canonical `install_adhook_app.sh` / `remove_adhook_app.sh` 后，进一步把两条 `install -D -m 0755` 映射加入 Host installer regression，防止未来 Release restore 再覆盖为旧版脚本。
- 上一次 KernelSU package run `42096247931` 在该脚本映射处失败；修复后的 workflow 尚未重新执行最终 package。`migration_complete` 仍是显式人工门控，本轮不擅自触发最终 APK/ZIP 构建。


### KernelSU 归档安装器同步验证（2026-11-06）

- Package run `42096247931`（commit `22144b49`）已完成 Yulong 规则解码/导入及 210118 域名、3476 cosmetic 规则验证；随后 `adhook-app-installer-regression.sh` 失败，原因是 Release ZIP 恢复会覆盖 `fx-module/scripts/install_adhook_app.sh`，而旧归档副本不包含新系统应用 overlay 优先路径。
- 后续提交 `6841eda` / `5b197bac` 已在 KernelSU 兼容补丁阶段先把仓库中的 canonical installer/remover 复制到恢复后的 `fx-module/scripts/`，并在最终打包前再次比较两份脚本，防止 Release 遗留副本覆盖新实现。
- 现将这四项同步/比对约束加入 `adhook-app-installer-regression.sh`，确保未来 Release restore 或 workflow 重排不会移除同步步骤。旧 run 未进入 APK/QuickJS 编译和 ZIP 封装；当前分支新提交仍需回归验证，未声称最终包构建成功。


### KernelSU installer workflow synchronization deduplication（2026-11-06）

- 回读 `build-fx-kernelsu.yml` 发现 canonical installer/remover 被连续同步两次：一组位于 system-app patcher 之前，另一组位于 patcher 之后并有 `cmp`。保留有字节核验且紧邻安装器回归的后者，删除前置重复复制。
- 安装器 regression 现在要求每条 copy 命令恰好出现一次，并固定顺序为 installer copy → remover copy → 两个 cmp → installer regression，防止重复 staging 或先测后同步。
- 本批只清理 build pipeline 和加固测试；APK / ZIP 构建仍遵守 migration gate。待当前 HEAD 的 Host Regression 验证测试代码，再在允许的最终验收阶段运行 KernelSU package。


### Hook 安装器 Root 状态和日志路径防符号链接（2026-11-06）

- `scripts/install_adhook_app.sh` 现在在创建和打开文件前逐级检查 STATE_DIR、TMP_DIR、日志父目录的路径组件；拒绝相对路径、`..`、任意层级符号链接、日志文件符号链接和非普通日志文件。目录创建后再次检查状态/临时目录，失败则在执行 PackageManager 前终止。
- 安装器状态与临时文件创建使用 `umask 077`；APK 暂存文件后续仍显式设置 PackageManager 安装所需权限，所有 ownership marker 保持 0600。
- 扩展 `adhook-app-installer-regression.sh`：分别用 symlink state root、symlink parent、symlink temp root 和 symlink log file 作为攻击夹具，验证安装被拒绝且所有链接目标 sentinel 保持不变。
- 该提交待最新 Host/Module Runtime 回归；未进行 Android 设备上 Root 安装、SELinux、PackageManager 或更新/卸载验证。


## 2026-11-06 — 游龙防火墙共享 UID 规则并集说明与双栈回归

- 复核 `scripts/yulong-app-firewall.sh`：内核通过 `owner --uid-owner` 匹配流量；配置仍按包保存，但每个共享 UID 成员当前生效的限制分别生成同 UID 的过滤规则，运行时效果是 Wi-Fi / 移动数据拦截条件的并集，无法按包隔离。
- 更新 `FxYulongFirewallActivity` 的行内说明和确认对话框，明确“任一共享成员当前生效的 Wi-Fi / 移动数据限制都会影响全部共享应用”，不再仅笼统表述为所有应用同时受影响。
- `fx-yulong-app-firewall-regression.sh` 新增共享 UID 双包场景：一个包只拦 Wi-Fi，另一个包只拦移动数据；验证两个独立配置均保留，且 IPv4/IPv6 规则都按同一 UID 同时生成两类拦截，然后恢复原测试配置继续执行生命周期回归。
- `fx-yulong-firewall-activity-regression.sh` 增加 UI 文案契约检查。此次仅验证 Host 源码和 mock iptables 行为，不代表 Android 真机包 UID/网络栈验收。


## 2026-11-06 — Ad 首页主开关未知态 fail-closed

- 将 Ad 主开关状态解析抽为 Android-free `FxYulongAdSnapshotPolicy`。只有协议头 `FXYULONGAD1` 有效且快照中恰有一个 `AD_MASTER|0/1` 时才返回明确状态；缺失、重复、非法值、重复头或协议头前噪声均返回未知。
- Ad 首页收到未知状态时不再默认显示“已启用”，开关文案改为“状态未知（暂不可切换）”并禁用。Root 读取失败时清空旧快照并禁用该开关，避免旧状态残留造成误导。
- 新增独立 JDK Host 测试覆盖 true/false、缺失/空快照、头缺失、master 缺失、非法值、重复字段与协议噪声；接入 `fx-yulong-ad-activity-state-regression.sh`。
- 本批提交后核对 Targeted Host Regression 与 Six UI Modes；未做 Android Gradle 构建或设备 UI 验收。


### 系统应用安装阶段行为测试夹具同步（2026-11-06）

- `3db79048` 的安装阶段行为回归失败在 `patch_system_app_install_stage.py`：新补丁会从仓库 canonical `scripts/` 同步 installer/remover，但旧的独立行为夹具只创建 `tmp/fx-module/customize.sh`，没有创建对应的 `tmp/scripts/` 源目录。
- 修正夹具为复制真实 canonical installer/remover 到临时仓库根目录，再执行生产 patcher；同时断言两份脚本已逐字节同步。测试仍从真实注入的 `customize.sh` 提取并执行安装阶段代码，不重写业务逻辑。
- 本修订仅修复测试夹具布局，等待 System App Install Stage、Host 与 KernelSU package lane 重新验证。


### Dia DEX 方法选择器与 Hook 标签页回归更新（2026-11-06）

- 旧导航回归仍查找已移除的 `方法 Hook/函数重写`、`规则组/规则列表` 分支；当前实现由原生 DEX 类/方法浏览入口将经过校验的方法签名带入自定义 Hook 编辑器。
- 回归现在检查完整往返：只允许 debuggable 用户应用选择具体方法；DEX 浏览页返回包名和 descriptor；MainActivity 再校验目标包状态、debuggable/system 标志及 `DeveloperHookRule` 语法，然后打开自定义 Hook 目标页。
- 同时验证 Hook app picker 仍选择底部 Hook tab（index 4），返回按钮回到 Hook 应用列表；Targeted Host 映射覆盖 MainActivity 与 FxDiaDexBrowserActivity 改动。
- 旧 APK migration run `42094851449` 在 Release merge 后执行旧导航断言时失败；本修订只同步回归契约，不改变功能实现。


### Ad 首页未知态回归断言对齐（2026-11-06）

- 新增的 12 项 Android-free 快照策略 Host 用例已通过；Targeted Host 在同一脚本后续阶段失败，原因是既有编辑草稿契约列表仍要求 `out.putBundle(STATE_DRAFTS,drafts);`，而当前实现实际保存 `retainedDrafts`，并且前面已有正确断言覆盖该路径。
- 将过期字面断言同步到实际保存的 `retainedDrafts` 变量，不改变编辑器保存/恢复行为；本修正提交后重新核对 Host Regression。


## 2026-11-06 — Ad 防火墙列表协议 fail-closed

- 设备端 `yulong-app-firewall.sh list` 原先只输出通过局部条件的规则行；损坏/畸形行会被静默跳过，导致 UI 可能把缺失的已启用规则展示为默认关闭。
- Shell 列表读取现完整校验非注释、非空记录：包名格式、正 UID、0/1 状态位、旧版 3 字段或新版恰好 8 字段、时间格式及包名唯一性；异常记录让 list 命令非零退出。
- 新增 Android-free `FxYulongFirewallListParser`：要求唯一 `FXYULONGFW2` 头、恰好一个 `master=0|1`，每条规则必须是 8 字段且包名/UID/状态/时间有效；拒绝重复包名、重复主状态、未知文本和字段缺失/多余。
- Activity 初始读取与安装/卸载刷新均须通过严格解析才加载可修改应用列表；响应异常时锁定总开关和规则写入入口、保留旧列表只读，不再默认为“防火墙关闭”。
- Host 加入纯 Java 协议测试与损坏 `settings.conf` 的 Shell 动态回归；KernelSU workflow 的 patcher 会将 canonical Shell 脚本和回归一并复制到恢复模块。
- 本批尚未完成 Android Gradle 构建、设备端 Root 列表协议和真实 iptables 网络验收；等待新提交 Host、Module Runtime 与六套 UI Actions。


## 2026-11-06 — 游龙 Ad 页面异步回调按页面代次隔离

- `FxYulongAdActivity` 新增页面代次；每次重新渲染/切页都会使旧代次失效，Activity 销毁时也会递增代次。
- 通用 Root 读取、配置档 Root 读取和配置写入完成回调必须匹配发起时的页面代次与页面标识；过期回调不再更新当前页面的状态、弹出旧错误框或把旧页面数据写入新页面。
- 设备端写操作仍正常完成；成功后仍刷新桌面 VPN widget 并重新读取当前页配置，避免 UI 回调过期被误解为已取消 Root 操作。
- `fx-yulong-ad-activity-state-regression.sh` 增加 root/apply/profileRoot 代次契约检查。此批仅有 Host 源码回归，尚无 Android 构建/设备交互和并发 Root 压力验证。


### Ad 编辑草稿回归方法边界修正（2026-11-06）

- 修正草稿回归脚本对 `open()` 方法结束位置的旧假设：它曾依赖后续出现另一个固定缩进的 `private` 方法；当前 `open()` 为类中的末尾单行方法，后面直接是类结束符。
- 现按当前单行方法边界截取并继续检查“先捕获草稿、切页、重建控件、恢复草稿、重新绑定”的顺序；不改变页面业务实现。
- 上一轮 Host run `42097906700` 的新快照 Host 用例 12 项已通过，后续失败位于这条旧草稿测试的 substring 定位；本次修正后等待新 Host run。


## 2026-11-06 — KernelSU 模块安装器副本与 canonical 同步

- Targeted Host Regression 在 `adhook-app-installer-regression.sh` 报告 `packaged installer drift`。核对发现根目录 `scripts/install_adhook_app.sh` 已包含路径组件/符号链接 fail-closed 防护，而 `fx-module/scripts/install_adhook_app.sh` 仍为旧版（文件长度 13,158 / 11,463 字符，内容不一致）。
- 将 canonical installer 原样同步到模块内副本；卸载脚本此前已逐字节一致，不做无关修改。保留回归中的 `cmp` 一致性要求，不通过放宽断言绕开问题。
- 本批只修复仓库内发布/测试副本漂移；仍需当前 HEAD 的 Targeted Host、Module Runtime 与 KernelSU package lane 结果确认，未声称真机 Root 安装或 SELinux 设备验证。


### DNS 生命周期回归断言转为顺序校验（2026-11-06）

- Host 再次运行已通过 12 项 Ad snapshot policy 测试以及前面的草稿/页面状态检查；随后失败在既有 DNS onDestroy 检查，其 Python 字符串把 `\\n` 作为字面反斜杠，而不是换行，无法匹配源码中的相邻两行。
- 现直接截取 DNS `onDestroy()` 方法体，并比较 `loadGeneration.incrementAndGet()` 与 `worker.shutdownNow()` 的实际顺序，保持原生命周期安全要求且不依赖换行转义。


### KernelSU Release restore 后保留 canonical post-fs-data（2026-11-06）

- KernelSU package run `42097408806` 在安装器回归阶段失败：回归读取到 Release ZIP 中旧版 `fx-module/post-fs-data.sh`，缺少 `/system/app/FX` 路径派生的 `restorecon -RF` 处理，导致断言 `system-app overlay does not apply path-derived SELinux context`。
- KSU 恢复步骤现在在覆盖模块目录前，把 checkout 中受审阅的 `fx-module/post-fs-data.sh` 保存到 `$RUNNER_TEMP`；Release 解包后恢复该文件并 `cmp -s` 字节核对。这样安装器/boot post-fs-data 检查针对的是准备打包的 canonical 实现，而不是 Release 历史副本。
- 安装器 Host 回归已经由 `306fc0d1` 调整为优先测试根目录 canonical scripts；Host 不再把 partial `fx-module/` 快照误判为已同步产物。真实模块副本同步仍由 APK/KSU workflow 的 install+cmp 步骤负责。
- 当前最新 APK/模块与 UI 的 CI 结果需继续按提交 HEAD 核对；本次未触发受 `migration_complete` 控制的最终 KernelSU package dispatch，也未做设备端安装、SELinux 或 overlay mount 验收。


## 2026-11-06 — Ad 主页面 Root 模块发现路径加固

- `FxYulongAdActivity.cmd()` 是 Ad 主页面全部 Root 控制命令的模块发现入口；旧逻辑仅检查 `module.prop` 是否含 id，未拒绝模块目录、元数据或控制脚本的符号链接，也未校验 FX 版本和 scripts 父目录。
- 现要求 `/data`、`/data/adb`、modules 根目录为真实目录，`modules_update` 若存在必须为真实目录；候选模块目录、`module.prop`、`scripts` 与 `yulong-ad-control.sh` 均必须是非符号链接的正确文件类型，并精确匹配 `id=privacyguard`、`version=1.0.0`。
- 更新 `fx-yulong-ad-activity-state-regression.sh` 锁定 Root 模块解析约束。该修复只收紧 Root 命令入口，不改变 Ad 控制参数、页面行为或后台服务状态。
- 待当前提交 Host/Module Runtime 回归；未进行 Android 构建、Root 真机或 ROM 安装测试。


### 每日安全总结回归契约对齐（2026-11-06）

- `fx-yulong-ad-activity-state-regression.sh` 旧断言要求每日安全总结 Activity 具备 Root worker 队列；核对 `FxYulongDailySummaryActivity` 后确认该页只读取本地 `SharedPreferences` 计数及 `ActivityManager` 的服务运行状态，没有 Root/网络操作。
- 保留 Ad 备份、DNS 日志两个确有后台 I/O 的页面有界线程池、拒绝过载及销毁关闭断言；每日总结改验本地持久化计数和真实服务状态，并确认没有引入不必要的 Root/线程池工作。
- 对应先前 HEAD `c5dec2e882f217d53004a5063c77cb0967e21667` 的 Host run `42098375614`：前 12 项 Ad snapshot policy 测试通过，失败仅为该过时的 worker queue 断言。当前修订提交待新 CI 验证。


### Ad 防火墙主状态与列表 section 完整性补齐（2026-11-06）

- 复核严格列表查询后发现，read_master() 仍把缺失、重复或非法的 enabled 状态默认折叠为 0；这会绕过 Java 端严格解析器，因为 Shell 仍可能生成表面有效的 master=0。
- read_master() 现在要求配置段唯一、enabled key 恰好一个、值严格为 0/1；列表命令显式检查读取失败再输出协议头。
- list_rows() 对重复的 [list:yulong_app_firewall] section 拒绝；缺失列表 section 仍是合法的空规则集合，保留新安装无规则状态。
- Shell 回归新增缺失/重复/非法主状态、重复 master key、空列表 section 和重复列表 section 场景。本提交等待 Targeted Host/Module Runtime CI。


### Shield 每日总结 Host 测试目标路径修正（2026-11-06）

- `42098602252`（HEAD `22ff74cd`）Targeted Host Regression 在 Ad Activity 状态测试中失败：每日安全总结断言要求本机 `shield_prefs` 计数和 Protection/Rescue 服务运行状态，却错误地读取 `imported/ad/FxYulongAdSummaryActivity.java`。
- 实际每日安全总结页面是 `imported/shield/FxYulongDailySummaryActivity.java`；其实现读取本地 SharedPreferences、查询两个本机服务状态，不执行 Root 或网络请求。Ad 的 `FxYulongAdSummaryActivity` 则是另一页本机广告过滤/DNS汇总，保留原实现不变。
- 仅将回归测试目标路径改为正确的 Shield 页面，业务代码不变；本修订等待新 HEAD 的 Host 回归确认。


### 游龙 Ad 总结页生命周期测试恢复真实 Root 数据口径（2026-11-06）

- Host run `42098602252` 指出上一版测试错误地断言“日常总结只读本地 SharedPreferences/ActivityManager”，但 `FxYulongAdSummaryActivity` 实际需要 Root 读取当前广告过滤配置和 DNS 保留日志数字统计；这属于测试契约错误，不是产品代码缺陷。
- 恢复对 Summary Activity 的真实边界检查：单执行线程 + 1 个待执行槽位、AbortPolicy、RejectedExecutionException 处理、Activity 销毁 shutdownNow，以及同一刷新代次贯穿 `list` 和 `dns-log-summary` 两次 Root 读取。
- 同时保留 generation 失效检查，确保过期配置或 DNS 统计不会覆盖新刷新结果；不把 Root 读取伪称为本地-only。


### Yulong 应用防火墙 AWK 规则解析语法修复（2026-11-06）

- Host run `42098544790` 在 `fx-yulong-app-firewall-regression.sh` 开始阶段报告系统 AWK 第 14 行存在 `unexpected newline`。已定位到 canonical `scripts/yulong-app-firewall.sh` 的 8 字段周计划校验条件：`else if` 表达式跨行后在系统 awk 中被视为不完整语句。
- 将 `NF==8` 条件合并为单一逻辑行，保持既有字段/时间验证与 fail-closed 分支不变。KernelSU patcher 会复制 canonical 源文件到恢复后的模块。
- 本次为源码语法修复；新 Host/Module Runtime 回归结论待提交后确认。未声称设备端 iptables 行为已验证。


### System App 安装阶段行为夹具目标目录补齐（2026-11-06）

- `42098783855`（HEAD `8329a212`）System App Install Stage workflow 在行为测试阶段失败：临时 fixture 创建了 canonical `tmp/scripts/`，但没有创建 `tmp/fx-module/scripts/`；生产 patcher 因模块 scripts 目录不存在而正确跳过同步，后续测试却读取缺失目标文件。
- 在合成模块 fixture 中创建独立的 `fx-module/scripts/` 目标目录，使 patcher 按生产语义把 canonical installer/remover 复制到模块目录；测试仍核对字节一致性和实际注入 Shell 阶段行为。
- 不放宽 patcher 对模块 scripts 缺失时的保守跳过行为，也不改变 installer/remover 逻辑。此修正等待新的 System App Install Stage、Host 与 KernelSU package CI。


### Ad / 隐私两种“总结”页面测试目标分离（2026-11-06）

- 最新 Host 失败 `42098905295` 的断言为 `daily summary worker queue must remain bounded`。追踪最近协作提交确认：回归脚本将 `summary` 路径改为隐私页 `FxYulongDailySummaryActivity`，但仍沿用 Ad 页原有 Root worker 队列断言。
- 将测试拆分为 `ad_summary`（`imported/ad/FxYulongAdSummaryActivity`）：验证 1 槽位有界 Root worker、AbortPolicy、拒绝处理及销毁关闭；`summary`（`imported/shield/FxYulongDailySummaryActivity`）：验证本地 SharedPreferences 和实际服务状态，不要求 Root worker。
- 这样保留两页各自真实数据来源与生命周期要求，不新增无必要线程。当前 HEAD 的 Host/Module Runtime 结果待本提交后重新检查。


### Ad 防火墙主状态回归验证接线（2026-11-06）

- `bb8c815c` 的 Host run `42098758244` 运行到新增 master/list section 场景时发现 AWK `else if` 换行语法错误；提交 `1688fc360405` 已将条件合为单行，保持逻辑不变。
- `b6c2c4da` 的 Host run `42099086925` 是安装器夹具增量，未运行防火墙专项测试；本次进一步要求每个无效/重复 master fixture 不得输出 `FXYULONGFW2` 成功协议头，并改动 firewall 专项脚本以触发针对性 Host 回归。
- `b6c2c4da` Module Runtime run `42099086747` 的 TUN/DNS/watchdog 和 Root Proxy/native VPN 两步均完成 SUCCESS，但 workflow 标记 CANCELLED；不记为完整 workflow success。


### Ad / Privacy 双 Summary 回归变量隔离（2026-11-06）

- `42099140694`（HEAD `856b1156`）的 Host Regression 失败在 Ad Activity 状态脚本后半段：新测试已分别定义 `summary`（Privacy `FxYulongDailySummaryActivity`）和 `ad_summary`（Ad `FxYulongAdSummaryActivity`），但后续 Root/代次检查仍误引用 `summary`，把 Ad 的 Root 读取要求套到 Privacy 页面。
- 现将 generation、两阶段配置/DNS Root 请求、销毁时失效检查及 Root/ThreadPoolExecutor 必需性断言全部绑定到 `ad_summary`；Privacy 本地总结继续单独验证 SharedPreferences、两个本机服务状态及无 Root/线程池。
- 不改两页实现，仅修正 Host 测试变量引用。此前 `b6c2c4da` 的 Host、六套 UI 和 System App Install Stage 回归均通过；本修订等待最新 Host 结果。


## 2026-11-06 — GKD 多应用扫描节流隔离

- 将 GKD 250ms 扫描节流从单一全局时间戳改为按目标包分别记录，避免应用 A 的无障碍事件短暂抑制应用 B 的已授权规则扫描。
- 规则缓存重建时只保留仍有已编译启用规则的包记录；规则配置失效时清空节流状态，不设置人工包数量上限。
- 新增 Android-free `FxGkdPackageScanThrottle` 与 3 个 JVM 单测，覆盖同包 cooldown、跨包互不干扰、规则移除清理和总失效清空；更新 GKD workflow 路径触发与单测筛选。
- `fx-gkd-automation-regression.sh` 同步检查该节流器确实接入运行时。等待最新 GKD/Host Actions；本批尚未进行 Android 设备无障碍点击真实验收。


### Ad 总结页 Root 模块发现安全回归补齐（2026-11-06）

- Ad 总结页 `FxYulongAdSummaryActivity.moduleShell()` 已使用与 Ad 主控制页相同的 fail-closed 模块发现：校验 `/data`、`/data/adb`、modules 根目录、modules_update 类型、模块目录、module.prop、scripts 目录和控制脚本的真实文件类型，并精确匹配 FX id/version。
- 本批只补充 `fx-yulong-ad-dns-summary-regression.sh` 对该模块发现契约的逐项断言，防止未来某一页面退回到仅 grep id 的宽松 Root 路径解析；产品源码保持不变。
- 回归与当前 HEAD 的 Targeted Host Regression 一并验证；未宣称 APK 构建、安装或 Root 真机验证。


### 共享 UID 防火墙解析 Host fixture 换行修正（2026-11-06）

- 最新 Host run `42099365565` 到达 `fx-yulong-firewall-activity-regression.sh` 的独立 JDK 测试后失败：`FxYulongFirewallListParser` 报 `invalid firewall list header`。
- 根因是 Host test Java 字符串把换行写成了字面反斜杠+n，导致 parser 收到单行文本；现将 fixture 的双重转义改成 Java 标准换行转义，测试覆盖的有效协议头、master 状态与 malformed cases 保持不变。
- 未更改 parser、安全策略或设备端防火墙命令；修复后等待新 Host Regression 确认。


## 2026-11-06 — KernelSU installer canonical sync 单一责任

- `patch_system_app_install_stage.py` 已在应用 system-app stage 时调用 `sync_packaged_installer(root)`，将仓库 canonical installer/remover 同步到 Release 恢复后的 `fx-module/scripts/`；`fx-system-app-install-stage-behavior-regression.py` 的隔离夹具已实测字节一致。
- KSU workflow 原先在 patcher 后又执行两次 `install -D` 覆盖同一文件，形成重复写入。现删除手动复制，仅保留 installer/remover 的 `cmp` 回读与 `adhook-app-installer-regression.sh`。
- 更新 Host regression：要求两条复制命令为零、patcher 内存在同步函数/调用、behavior fixture 断言模块副本等于 canonical 源，并强制顺序为 patcher → 两个 cmp → installer regression。
- 先前 `42099086771` System App Install Stage run SUCCESS，`42099086725`? 相关 run 状态以 Actions 当前查询为准；不将旧 package failure 当作本批修复已通过。尚未运行最终 APK/KernelSU ZIP，也未做设备安装验证。


### KernelSU installer 回归对齐 patcher 单一责任（2026-11-06）

- HEAD `7f6b2fccae4496cef330be0a95b63363bdd3c2fe7` 的 Host Regression `42099785668` 失败在 `adhook-app-installer-regression.sh`：测试仍要求 workflow 使用两条 `install -D` 手动复制 canonical installer/remover。
- 最近的构建重构已将同步职责收敛到 `patch_system_app_install_stage.py::sync_packaged_installer()`；workflow 刻意不再重复复制，而是在 patcher 后执行 `cmp -s` 字节回读再跑 installer 回归。原测试同一文件中已经有这套新契约，前后又保留旧的直接复制断言，互相矛盾。
- 删除四条过时的直接复制断言，保留 APK system-app overlay staging、patcher 负责同步、installer/remover cmp 顺序、uninstall/boot 行为等其余覆盖。只修测试契约，不改变产品脚本或构建行为。
- 本批提交后需要重新检查 Host/六 UI/Module Runtime；此前失败的 `42099785668` 不计为通过。


### KernelSU 订阅并发测试与兼容补丁顺序对齐（2026-11-06）

- KernelSU package run `42099301795` 在 `patch_atomic_cache_lock_release.py` 失败。根因不是缓存锁行为测试本身：build workflow 已先把当前仓库的 deterministic subscription concurrency fixture 复制进模块，但 compatibility patcher 仍要求旧 Release 测试里的两条裸 `wait "$p1"` / `wait "$p2"`，与当前 fixture 的退出码捕获和双 worker 诊断不匹配。
- 补丁器现在识别带有 `FX_SUBFETCH_CONCURRENCY_CANONICAL_V1` 的仓库规范夹具，逐项验证 transfer gate、单 worker 入场、双进程退出码、两侧输出诊断、串行网络请求、缓存元数据和 lock 清理契约；完整满足时跳过只适用于旧 Release 测试的文字注入。非规范旧夹具仍沿用原始兼容修补流程。
- `fx-atomic-cache-lock-release-regression.sh` 调整为先复制规范并发夹具，再运行补丁器两次，执行顺序与实际 KernelSU build workflow 对齐。
- 本批新增规范测试标记并记录 CI 根因；需要当前 HEAD 的 Host 与 KernelSU package CI 重新验证。未声称 APK/ZIP 构建已通过。


## 2026-11-06 — KernelSU Release 恢复阶段补齐 subfetch 并发锁迁移

- 包装 run `42099301795`（checkout HEAD `db33b64b`）在完整 FX module Host suite 的 subfetch 并发回归处失败；此前 `patch_subfetch_file_lock.py` 和 `patch_subfetch_legacy_lock_tests.py` 已存在，但 KernelSU workflow 没有在 Release ZIP 恢复后调用它们，旧版 `subfetch.sh` 未迁移到 POSIX noclobber 文件锁。
- 在 `.github/workflows/build-fx-kernelsu.yml` 恢复模块后，先应用文件锁 patcher，再生成兼容旧 PID 目录锁的 stale-lock 回归；随后安装并立即执行真实并发测试及两项 stale-lock ownership/reclaim 测试。完整模块 Host suite 仍会再次发现并运行这些脚本。
- 新增 `scripts/tests/fx-subfetch-release-patch-regression.py`：以最小 Release 旧版锁块验证 patcher、幂等性、生成脚本 Shell 语法，并锁定 KernelSU workflow 的补丁/测试顺序。
- 本批为打包恢复路径补齐，不改变 FX APK/UI 或订阅数据协议。待当前 HEAD 的 Host Regression 与 KernelSU package run 结果确认；未声称真实设备订阅抓取已验收。


### subfetch 兼容 patcher Host 断言修正（2026-11-06）

- 新增的 Host 检查需区分“生产源不得包含恢复 stale quarantine 的 mv”与“生成的测试脚本必须包含用于检测该危险操作的 grep”。此前把后者误判成生产行为，现将断言改为分别检查真实迁移后的 `subfetch.sh` 和测试脚本的拒绝断言。
- 保持锁算法与打包 workflow 不变；本次只修复新增回归自身的误判。


## 2026-11-06 — APK / KernelSU 打包统一 subfetch 原子锁迁移

- KernelSU 失败 run `42099301795` 在完整模块回归末尾报告 Release-restored `v1.0.0-subfetch-concurrency-regression.sh` worker failure；回读确认仓库已有 `patch_subfetch_file_lock.py` 与 `patch_subfetch_legacy_lock_tests.py`，而此前 KSU 打包步骤未应用这两个 patcher。
- 最新协作 HEAD 已将两个 patcher、并发回归和两种陈旧锁回归接入 KernelSU 流程。本批将同样的顺序接入 APK 打包流程：恢复 Release 模块后应用 POSIX noclobber 文件锁、重建 stale-lock 测试、安装 canonical concurrency 回归；在 TMPDIR fixture 标准化后运行并发/ownership/reclaim 三项测试。
- 新增 `scripts/tests/fx-subfetch-package-integration-regression.py`，检查 APK 与 KernelSU 两条打包路径均按“patch → stale-lock test generation → concurrency → owner/reclaim tests”顺序执行，防止打包链路漂移。
- 本批尚待新 APK/KSU package CI 对真实 Release-restored module 运行结果确认；未声称设备端网络订阅验证。


## 2026-11-06 — Hosts 分页保存临时路径防符号链接

- `MainActivity.writeHostsPage()` 原先直接对固定 `/data/local/tmp/fx-hosts.XXXXXXXX` 调用 `mktemp`，未验证 `/data`、`/data/local`、`/data/local/tmp` 父目录类型；若路径被替换为符号链接，Root 保存暂存内容可能被导向意外位置。
- 保存前现在逐级要求三个父目录均存在且不是符号链接；之后设置 `umask 077` 创建私有临时文件，启用退出清理 trap，并再次要求临时文件是非符号链接普通文件，才写入 Base64 解码内容并交给 `fileedit.sh replacepage`。
- 更新 `fx-native-managed-lists-regression.sh`，静态验证父目录 guard、私有 umask、mktemp、临时文件类型检查与执行顺序。Hosts 后端事务锁/并发回归保持不变。
- 本批源码与回归已提交；Android Gradle 编译、模拟器、设备文件系统权限/SELinux 路径验证未运行。


## 2026-11-06 — Yulong DNS 页面 Root 模块路径防护

- DNS 查询日志页此前通过 `module.prop` 的 `id=privacyguard` 宽松定位模块，Root 命令未验证 `/data`、`/data/adb`、modules 根目录、候选模块目录、module.prop、scripts 目录和控制脚本是否为真实非符号链接文件。
- 现与 Ad 主控制/总结页对齐：验证数据根目录、modules 与 modules_update 父路径类型，精确匹配 `id=privacyguard` / `version=1.0.0`，逐级拒绝模块、module.prop、scripts 与 `yulong-ad-control.sh` 的符号链接。
- DNS Activity 的 Root 操作参数收紧为 `dns-log-tail`、`cache-flush`、`dns-log-clear` 三项明确 allowlist；不接受其他参数拼入 Root shell 命令。
- 更新 `fx-yulong-dns-cache-regression.sh`，覆盖模块发现和操作 allowlist。未进行 Root 设备路径攻击模拟、APK 构建或真机 DNS 测试；等待新 Host/Runtime CI。


## 2026-11-06 — 游龙防火墙 Root 模块路径验证收紧

- 基于最新分支 HEAD `782fb3fde24ea70e6a2452de32c81fe11613b538` 检查防火墙 Activity 时，发现它仍以 `grep -q '^id=privacyguard$'` 作为唯一模块识别条件；与 Ad 总结页已有的严格 Root 模块发现策略不一致。
- `FxYulongFirewallActivity.scriptCommand()` 现先验证 `/data`、`/data/adb`、活动模块根和可选更新模块根的目录/符号链接属性；候选模块必须为真实目录，`module.prop`、`scripts` 和 `yulong-app-firewall.sh` 均为非符号链接的正确文件类型，并同时精确匹配 FX id 与 version 1.0.0。
- 防火墙 Activity 的所有 Root 读取、规则写入、主开关与应用命令共用该入口；发现路径异常时在执行控制脚本前失败关闭。
- 更新 `scripts/tests/fx-yulong-firewall-activity-regression.sh`，逐项锁定父目录检查、版本匹配与模块 payload symlink 防护。
- 本批尚未完成 CI 验证；未声称 APK 构建、Root 设备执行或真实防火墙流量验证通过。


### Ad 防火墙无效快照只读锁定覆盖补齐（2026-11-06）

- 复核 malformed list 失败路径后确认 Activity 已有双层写入保护：inventoryReady=false 使 rule editor/persist 拒绝写入，已渲染 row switch 和 detail/configure 按钮也会失效；恢复完整 Root list 后才重新启用。
- 本批仅把这些现有运行时门控加入 fx-yulong-firewall-activity-regression.sh，防止未来重构移除其中任一层却只保留总开关 disabled 的假只读状态。
- JDK parser/Shell strict protocol 的 33 条断言由前一批 d4588473 的 Host run 实际通过；本次新增静态断言等待新 Targeted Host 结果。


### 防火墙模块路径回归转义修正（2026-11-06）

- `db737fa8947c7e1c066c619198c7dae42c2cd848` 新增的模块 payload symlink 静态断言把 Java 源码反斜杠转义重复写了一层，测试文本与实际源码不匹配。
- 现将 Python raw-string 断言调整为单层 `\\"` 源码转义形式，和 `FxYulongFirewallActivity.scriptCommand()` 的真实文本一致；生产 Root 路径验证逻辑保持不变。
- `db737fa` 对应 Host run 结果以 Actions 回读为准；此修复后的提交需重新跑针对性 Host Regression。


### subfetch PID 路径断言修正（2026-11-06）

- 新增 Release patcher Host 检查中的 quarantine 路径模板补齐第二个 `$`，与生产 patcher 实际生成的 `$$` PID 分量完全一致。
- 仅更新测试字面量，不改变 subfetch 行为；当前分支中 KernelSU 与 APK 构建工作流均已接入该锁迁移步骤。


### Dia Frida 会话日志页补齐 /data 根目录检查（2026-11-06）

- `FxDiaSessionLogActivity` 的刷新与清空共用 `checkedDirectoryPrefix()`，此前已拒绝 `/data/adb`、FX 状态目录、Dia 目录和 logs 目录的符号链接，但未验证最上层 `/data` 是否为真实目录。
- 现对 `/data` 先检查 `-d` 且非符号链接，再执行已有的下层目录检查；读日志与清空日志都使用同一 fail-closed guard。
- 更新 Dia monitor/session regression，验证 session guard 包含 `/data` 与 `/data/adb` 拒绝条件。尚未进行设备端路径异常注入测试或 APK 构建。


### subfetch PID 模板断言的字面 `$` 保留修正（2026-11-06）

- 修正回归测试的生成过程：使用字面回调替换保留 shell `$$`，避免 JavaScript 替换字符串语法将 `$$` 折叠为单个 `$`，造成上一次修订未实际改变文件内容。
- 当前测试现验证生产 patcher 输出的 `$$_sl_try` PID 路径，不改变锁 patcher 或模块运行逻辑。


### Dia 会话日志 Host 断言对齐 shell 条件位置（2026-11-06）

- `14231dd4` 的 Host Regression 在 `fx-dia-monitor-event-view-regression.sh` 失败于 `/data/adb` 父目录断言：测试错误要求该条件以 `if` 开始，但实际 guard 先检查 `/data`，再以 `|| [ -L '/data/adb' ]` 追加下层检查。
- 将断言改为匹配实际的 `||` 子句；生产 guard 保持原样。该 Host 失败属于测试匹配错误，不是目录防护逻辑失败。


### Dia Session Log /data/adb 路径断言修正（2026-11-06）

- Targeted Host Regression 在 `fx-dia-monitor-event-view-regression.sh` 失败：`FxDiaSessionLogActivity.checkedDirectoryPrefix()` 已按 `/data`、`/data/adb`、FX/Dia/logs 目录逐级拒绝符号链接，但测试把 `/data/adb` 断言错误写成独立条件开头。
- 将断言匹配改为同一 `if` 链中的 `|| [ -L '/data/adb' ] || [ ! -d '/data/adb' ]`；同时保留 `/data` 根检查、明确失败 marker、统一 read/clear guard 和最终日志文件 symlink 检查。
- 本批只修正静态 regression 文本，不修改 Session Log/Frida 运行逻辑；等待新 Host run 验证。


## 2026-11-06 — Root Proxy Linux interface-name validation

- 代码提交：`77b044b73b04ca0d5eb5affa15d3fd4475684997`；回归提交：`5285af780e6260792604628a806411272c524f97`；测试用例边界修正：`5343075dcd624248878d05fc2984aaaa075cc194`。
- `fx-module/scripts/yulong-root-proxy.sh::_valid_if` 现在在原有 ASCII 字符白名单基础上，拒绝超过 Linux `IFNAMSIZ - 1`（15 字节）的接口名，避免把不可能存在的超长接口名传入 `ip` 路由探测；未更改任何第三方路由或防火墙规则。
- `scripts/tests/fx-yulong-root-proxy-runtime-regression.sh` 从生产脚本提取真实 validator，覆盖常见 VPN/蜂窝/Wi-Fi 接口名、15 字节边界、16 字节拒绝、空值、空格和斜杠拒绝。
- GitHub 回读验证：生产脚本与测试文件均已按分支 ref 重新读取；生产 validator 与新增测试片段匹配。Gradle/Android 构建未运行；Host 测试尚未由本执行环境直接运行。目标分支的 combined commit status 未返回任何 status 项，不能据此声称 CI 通过或失败；需查看对应 Actions run。
- 未进行设备真机测试；此项是 Root Proxy 输入验证收紧，不代表第三方 VPN 共存或 DNS 泄漏验收完成。
- 下一批：继续针对真实 VPN 数据面验证路由/端口/DNS/TUN 交互，并保持 Root Proxy 与独立本地 DNS 的生命周期隔离；随后回到六模式原生页面覆盖与 Hook 运行时完整度。


## 2026-11-06 — VPN 共存裁决补齐 AdGuard 客户端 DNS 53 端口探测

- 核对当前 Release runtime 的 `.github/dns/AdGuardHome-FX-runtime-v1.0.0.yaml`：AdGuard Home 客户端 DNS 监听端口为 TCP/UDP 53，上游 Unbound 为 127.0.0.1:5353；Root Proxy 的 IPv4/IPv6 链同样把客户端 TCP/UDP 53 导向本地 127.0.0.1:53。
- 原 VPN coexistence arbiter 仅探测 DNS 5353 与代理 7890，未检查 AdGuard Home 实际对客户端提供服务的 53 端口。外部进程已占用 53 时，AdGuard DNS 可能无法绑定，但裁决器仍可能将端口冲突漏报。
- 新增 `dns_filter` 状态（默认端口 53），同时保留既有 `dns`（5353）和 `proxy`（7890）JSON 字段；TCP LISTEN、UDP bind、/proc/net 任一协议/地址族不可读均沿用 fail-closed 端口判定。任何 53/5353/7890 冲突或探测未知都会使共存等级降为 partial。
- 新增客户端 DNS TCP/UDP 53 占用回归，并验证干净 fixture 中端口默认值与可用状态。当前代码批次以本节对应提交/Actions 实际结果为准；未执行 Android 真机 DNS 接管或第三方 VPN 设备级流量测试。


## 2026-11-06 — GKD 跨应用待扫描请求合并

- 原 FX 无障碍服务在一个 GKD 扫描执行期间直接丢弃之后到达的所有目标应用事件，快速切换应用时可能使新目标错过唯一触发事件。
- 新增 Android-free `FxGkdPendingPackageScan`：一个扫描执行中，只保留最新一个待扫描包名；不保存额外 `AccessibilityNodeInfo`，不堆积无界任务队列。
- 当前扫描结束后，经主线程 Handler 重新取得活动窗口根节点并再次校验包名；过期窗口请求被安全丢弃。服务销毁时清空待处理包名、移除回调并关闭执行器。
- 新增 4 个 JVM 单测；同步更新 GKD Host 契约、workflow 文件触发路径和 Gradle 测试选择器。
- 本批源码先在离线 commit tree 创建，随后将同一变更集移植到最新分支 HEAD；本提交之后的 CI 结论待 Actions 回报。


## 2026-11-06 — Yulong Ad 多页面 Root 模块命令统一

- 将 Ad 保护配置档、通用设置（含导入事务）和应用白名单三个仍使用旧式模块发现的 Root 入口，切换到新的 `FxYulongRootModuleCommand`。
- 公共构造器只允许 `yulong-ad-control.sh`、`yulong-profiles.sh`、`yulong-app-whitelist.sh` 三个固定脚本名；统一验证 `/data`、`/data/adb`、modules 根、可选 modules_update 根、候选模块真实目录、`module.prop` 精确 FX id/version、scripts 目录、util.sh 与目标脚本均非符号链接/文件类型正确。
- General 页面单独构建的批量导入事务也使用同一个 prefix，避免从普通 Root 入口绕过校验。
- 新增 standalone JDK Host test 和 `fx-yulong-root-module-command-regression.sh`，检查 allowlist 拒绝任意脚本名及三页所有 Root 调用点均接入 helper；workflow 加入路径触发。
- 本批提交后需检查 Host、六 UI 与 Module Runtime 结果。未声称 Android Gradle build、Root 设备执行或应用白名单真机流量验收已完成。


## 2026-11-06 — 六种界面模式选择器可访问性与名称校正

- 代码提交：`c0072e157e5c8deef8a594dca3e6fbfea803ef76`。
- 修改 `FxUiMode.kt)：保留 `default/classic/glass/miuix/huawei/ios` 稳定存储 ID 和旧值映射；将五种皮肤显示名改为明确的中文产品名称，默认模式仍独立排第一。
- 修改 `FxDesignModePanel.kt)：模式卡片由普通 clickable 改为带 `Role.RadioButton` 的 selectable，向 TalkBack/Compose 无障碍语义暴露真实选中状态；点击仍只调用既有模式选择回调。
- 修改 `FxUiModeTest.kt`：新增六种显示名称及顺序断言。
- GitHub 回读：三个文件均从目标分支重新读取并核对；名称、RadioButton 语义和测试断言均存在。
- 验证等级：源码回读通过；对应 `FX Six UI Modes` 与 `FX Targeted Host Regression` Actions 已排队（run `42102008681`、`42102008707`），尚无通过结论。未运行 Gradle、APK 构建、模拟器或真机测试。
- 不改变业务服务、VPN、DNS、Hook 或脚本生命周期；不改变产品版本号。
- 下一批：检查六种模式在各主 Tab/二级页的 renderer 覆盖和真实页面回归，不将选择器本身的完成误报为全应用皮肤覆盖完成。

## 2026-11-06 — KernelSU Hook APK payload路径防符号链接

- 本批修改：`scripts/install_adhook_app.sh` 在 APK 哈希计算与 PackageManager 调用前，验证模块根目录、所选 APK 和 checksum sidecar 的完整路径链；拒绝任何符号链接祖先、APK 末端符号链接、checksum 末端符号链接及不规则文件。即使 symlink 指向字节完全匹配的 APK/摘要，也不会进入安装流程。
- 回归扩展：`scripts/tests/adhook-app-installer-regression.sh` 增加 system-app APK 与 SHA-256 sidecar 符号链接用例，并断言拒绝发生在 PackageManager 之前；保留现有 overlay、legacy fallback、签名迁移和卸载所有权测试。
- 验证边界：代码与回归用例已推送；等待当前分支 GitHub Actions 定向 Host Regression 结果。Android 真机安装、SELinux、系统包识别与设备升级/卸载流程仍需设备验证，不在此处声称已通过。


## 2026-11-06 — VPN coexistence arbiter 严格校验端口配置与 JSON 输出

- 在当前协作分支最新 HEAD `4ab0ccee14cfe6aa7e655d62a5c2e5b68a5a1a25` 上续接；保留其他协作者此前对 AdGuard DNS TCP/UDP 53 端口 fixture 的修复。
- 修复共存裁决器把 `FX_ARB_DNS_PORT`、`FX_ARB_FILTER_DNS_PORT`、`FX_ARB_PROXY_PORT` 原样插入 JSON 数字字段的问题：异常环境值可能造成无效 JSON或注入额外字段，使 UI/状态消费者无法可靠解析。
- 新增统一十进制端口归一化：只接受 1–65535 的纯数字，先去除前导零并在算术比较前限制位数，避免 shell 八进制解释和超长整数溢出；非法值在 JSON 中输出 `null`、占用状态为 `unknown`，文本模式显示 `invalid`，现有 fail-closed 裁决会降级为 partial。
- 定向回归新增前导零十进制端口与带 JSON 注入字符的非法端口场景，验证端口 53 仍按十进制检测、非法值不会破坏 JSON，也不会被报告为无冲突。
- 代码提交：`f992eab17ae4301c243c7a64fa8f423e96c99237`；回归提交：`1ee6d3bd271ce4a9bf842689454d8b0176f5e759`。
- 验证等级：GitHub 源码写入成功；本执行环境未运行 Shell/Host/Gradle 测试，须回读对应 Actions run 后才能报告测试结果。未进行 Android 真机第三方 VPN、DNS 或 TUN 测试。

## 2026-11-06 — Hook APK payload路径防符号链接验证回执

- 本批功能提交：`2bf17ff18d6fff2665cc7060c42cf7144c78081e`；回归用例提交：`10ad058a6b1ea3800e807d9886ccc3f129bcab64`；随后修正测试对 overlay 专用拒绝消息的断言：`4ab0ccee14cfe6aa7e655d62a5c2e5b68a5a1a25`。
- GitHub Actions Targeted Host Regression：run `42102278095`，对应 `4ab0ccee`，结论 SUCCESS；测试步骤已完成，覆盖 APK 与摘要 sidecar 符号链接拒绝且不触达 PackageManager。
- GitHub Actions Module Runtime Regression：run `42102278033`，对应 `4ab0ccee`，读取时仍在运行；VPN/DNS/Root Proxy 集成回归尚未出最终结论。
- 本批最新读取时分支 HEAD：`7297aca5a243bb5965f61f5d8a83820997706da9`（其后有独立 VPN 文档提交；不得将其归为本批功能代码）。
- 仍未进行 Android 真机安装、SELinux 标签、PackageManager system classification、OTA/模块升级和卸载设备验收。

## 2026-11-06 — VPN coexistence arbiter port normalization regression expansion

- 测试提交：`01634762fd292781a5a4002470d732b740fb13bf`。
- 扩展 `scripts/tests/fx-vpn-coexistence-arbiter-regression.sh`，除既有 AdGuard 客户端 DNS 53 端口外，新增 Unbound 上游 DNS 5353 与代理 7890 的前导零十进制归一化断言。
- 新增 DNS 65536 越界、代理 00000 零端口的 fail-closed 检查：JSON 端口必须为 null、owner 必须为 unknown、共存等级必须降为 partial。
- GitHub Actions：`FX VPN Coexistence Arbiter` run `42102461771` 在提交 `01634762fd292781a5a4002470d732b740fb13bf` 上通过；Shell 语法、Python 编译、共存裁决回归、只读性检查和 runner 网络 smoke test 均成功。
- 本批仅增加自动化边界测试，没有修改运行时网络配置；未运行 Gradle/Android 构建、模拟器或真机 VPN/DNS 共存测试。


## 2026-11-06 — 六种界面模式名称与选择器无障碍回归

- 功能代码提交：`c0072e157e5c8deef8a594dca3e6fbfea803ef76`。
- 回归映射修复提交：`3a5085858f255ad53656aa33c66cb1e34bcdca10`。
- 六种模式显示名称已改为产品可读名称，保留稳定存储 ID 和既有旧值迁移；选择卡片使用 Compose `selectable` + `Role.RadioButton`，并将实际当前模式暴露为选中状态。
- `scripts/tests/fx-global-ui-modes-regression.sh` 新增六种显示名称、RadioButton 角色、selected 状态和旧 clickable 退役断言；`.github/workflows/fx-targeted-regression.yml` 将 `FxUiMode` / `FxDesignModePanel` 纳入 UI Host regression 映射。
- GitHub CI：`FX Six UI Modes` 对功能提交 `c0072e1` 成功（run `42102008681`）；`FX Targeted Host Regression` 同提交首次失败（run `42102008707`），失败原因是工作流未把这两个源文件映射到任何 Host 回归，并非 Kotlin 编译或测试断言失败。已补齐映射与回归断言，修复提交 `3a50858` 的新 CI 结果待回报。
- GitHub 源码回读确认功能文件、回归脚本与工作流路径映射已写入目标分支。尚未运行 Android Gradle 构建、模拟器、安装或真机测试。
- 本批仅涉及 UI 模式选择器展示与无障碍语义，不改变 VPN、DNS、Hook、脚本服务生命周期或 FX 1.0.0 版本号。
- 下一批：检查六种模式在各主 Tab/二级页的 renderer 覆盖；同时跟进 `3a50858` 对应 Targeted Host CI，修复任何真实回归失败。


## 2026-11-06 — VPN coexistence arbiter probe injection hardening

- 功能提交：`44de34b87ae68923fe77f319acfef691b5d8f65e`；回归提交：`a0e7f13a8e3b6bfa616d652ab049a5e0de5fa55c`；后续文档/测试补强提交：`ae3b983409e9c8f0515a41d6a4a131a6eb1a95a8`、`424cdc463a768c802af203f5210a59cb30bc7aa6`。
- 移除 `scripts/fx-vpn-coexistence-arbiter.sh` 对 `FX_ARB_LINK_CMD` / `FX_ARB_VPNINFO_CMD` 的 `eval` 执行。生产路径现在直接调用 `ip -o link show` 与 `vpncore_android_active_vpn_info`；回归注入只接受经普通文件/非符号链接/可读性检查的只读 fixture 路径。
- 更新 `scripts/tests/fx-vpn-coexistence-arbiter-regression.sh`，将探测夹具改为数据文件，并增加旧命令型环境变量不得执行的 marker 断言；保留端口、VPN 槽位、只读性与 fail-closed 覆盖。
- GitHub 回读确认 arbiter 不再含 `eval "$FX_ARB_..."`，回归脚本不再使用旧命令变量作为执行入口；对应 Actions：VPN Coexistence Arbiter run `42102646201`，Targeted Host run `42102646295`，Six UI Modes run `42102646307`，Module Runtime run `42102646227`。记录时尚未全部完成，最终结论以各 run 结束状态为准。
- 验证边界：已完成 GitHub 写入和回读；CI 正在执行。未声称本地 Shell/Host、Gradle、APK/ZIP、Android 设备或真机第三方 VPN/DNS 共存测试通过。


## 2026-11-06 — VPN coexistence arbiter failed-interface-inventory regression

- 回归提交：`6f5c195e97b9fa182dd0f6f603d920a60883b859`；测试夹具修正提交：`bba5e10275de0b847c49c848ce827f393c009596`。
- 在 `scripts/tests/fx-vpn-coexistence-arbiter-regression.sh` 增加失败的 `ip -o link show` 命令仍输出部分接口数据的场景。测试通过 PATH 注入一个只输出 loopback 接口后返回 7 的隔离假 `ip` 可执行文件；断言裁决器必须丢弃部分输出、将 probe 标记为 unavailable、verdict=unknown、exit=2，不能声称没有外部 VPN。
- 首次 CI 暴露新增 fixture 的 shell 转义错误（run `42102660148` failure）；已修正续行符和 printf 格式串，没有放宽断言。
- 修正后 GitHub Actions：VPN Coexistence Arbiter run `42102744421` SUCCESS；Targeted Host Regression run `42102745222` SUCCESS；Six UI Modes run `42102744474` SUCCESS。Module Runtime Regression run `42102744532` 在记录时仍为 in_progress，不据此宣称通过。
- 已从 GitHub 回读测试脚本，确认隔离假命令、非零退出、unknown/unavailable 断言已写入。此批为 Host/CI shell 回归；未运行 Android Gradle 构建、APK/KernelSU ZIP 构建、模拟器或真机 VPN/TUN/DNS 数据面测试。
- 下一步：跟进 Module Runtime Regression run `42102744532`；随后转入本地 DNS 独立服务的启停/卸载恢复与端口回滚测试，继续保持 VPN 与 DNS 分离的生命周期。


### VPN arbiter probe hardening — CI follow-up

- 后续协作提交 `bba5e10275de0b847c49c848ce827f393c009596` 修正只读 link fixture 的 Shell 转义；未覆盖或回退本批 arbiter 代码。
- 最新 HEAD 对应 Actions：`FX VPN Coexistence Arbiter` run `42102744421` SUCCESS（脚本语法、完整共存分级回归、只读性扫描、runner 网络 smoke test 均通过）；`FX Targeted Host Regression` run `42102745222` SUCCESS；`FX Six UI Modes` run `42102744474` SUCCESS。
- `FX Module Runtime Regression` run `42102744532` 记录时仍在执行，VPN/DNS/TUN/Root Proxy 专项结果未定。无 Android 真机证据，不将 CI 结果等同设备验收。


## 2026-11-06 — Local DNS health-probe boundary and integration regression

- Code commit: `fccbdc974b8f44a89b9af017e34ce74d89b33d1c`; regression test commit: `60216b7d79f1df326250b65cc07e393200a6f74a`; workflow integration commit: `9391c0d59824d26a4897c92a3989355684ce71cc`.
- Changed `scripts/localdns-probe.c`: enforce IPv4 loopback-only destinations (127.0.0.0/8), strictly parse numeric port/timeout arguments (reject trailing text, overflow and extra arguments), and validate DNS response ID, QR, opcode, RD, TC, QDCOUNT and echoed question before treating NOERROR/NXDOMAIN as healthy.
- Added `scripts/tests/localdns-probe-regression.py`: compiles the probe with `-Wall -Wextra -Werror` and exercises a real UDP loopback responder, NOERROR/NXDOMAIN acceptance, missing RD, truncated response, non-loopback rejection and malformed CLI arguments.
- Updated `.github/workflows/build-unbound-android-arm64.yml` to run the host integration regression before the Android NDK cross-build and to trigger when the regression test changes.
- Verification: GitHub write responses succeeded; all three code/test/workflow files were fetched again from the target branch and their new blob SHAs/content markers verified. The Actions result for commit `9391c0d59824d26a4897c92a3989355684ce71cc` has not yet been observed. No local execution, Android cross-build, installation or real-device DNS test is claimed.
- Scope: this closes the probe's unintended ability to send health checks to arbitrary IPv4 destinations; it does not change DNS routing, redirect device traffic or alter user VPN/firewall state.
- Next: inspect the triggered workflow result and fix any test/build failures; then resume the next existing UI/backend batch from the branch's latest HEAD. Real-device recursive DNS reachability and third-party VPN coexistence remain unverified.


### DNS probe host execution follow-up (2026-11-06)

- Executed the committed probe/test logic in an isolated Linux host workspace: `python3 test.py` — PASS. The test compiled the C helper with `cc -std=c11 -O2 -Wall -Wextra -Werror` and exercised UDP loopback NOERROR/NXDOMAIN responses, missing RD, TC/truncation, non-loopback rejection and malformed CLI arguments.
- This is a host integration test only. Android NDK cross-compilation, GitHub Actions result, actual Unbound runtime and device/mobile-network recursion remain unverified.

## 2026-11-06 — Root Proxy interface-name validation aligned with Linux netdevice rules

- 代码提交：`6f8b34c78b9859d1d761a6f2992574f2bf4286af`。
- `fx-module/scripts/yulong-root-proxy.sh::_valid_if` 现在拒绝 Linux netdevice 不接受的冒号别名及特殊名称 `.` / `..`，仍保留 15 字节上限和 ASCII 安全白名单。
- `scripts/tests/fx-yulong-root-proxy-runtime-regression.sh` 新增有效名称 `eth0.100`、`veth-test`，并验证 `tun0:1`、`.`、`..` 被拒绝；生产 validator 由测试直接提取执行。
- GitHub Actions：`FX VPN shell regression` run `42102931374` 在本提交上通过，包含 POSIX shell 语法、Root Proxy runtime regression 与卸载顺序回归。
- 同提交触发的 Targeted Host 与 Module Runtime runs 被后续协作者提交取消；其后代 HEAD `361a0e19fcb5010dd93aeca0c504b641a2e84a5a` 的 Targeted Host run `42102963704` 失败，具体失败项尚未从 Actions 输出中确认，不能标记为通过；该 HEAD 的 Module Runtime run `42102963655` 当时仍在运行。
- 未运行 Android Gradle 构建、模拟器或真机第三方 VPN 路由测试。


## 2026-11-06 — 六模式设置选择页按当前皮肤 tokens 渲染

- 主要功能提交：`361a0e19fcb5010dd93aeca0c504b641a2e84a5a`；兼容性修复提交：`153cf09a13987116dcf54d5f54b9278df5aed557`。
- `FxDesignModePanel` 不再让 Default、Classic、Glass、Miuix、Harmony、Cupertino 六张模式卡共用固定 Miuix 视觉参数；现在分别通过 `fxComposeShellTokens(mode, ...)` 解析各自的 surface、border、accent、selected/inactive text 和圆角，并保留 Miuix runtime 颜色作为 Miuix 模式的真实 palette 输入。
- Glass 卡继续使用 Kyant Backdrop blur/lens；其他模式使用各自 tokens 的 surface。所有卡保留 `Role.RadioButton` 与真实 selected 状态。
- 首次 Host 回归发现 `fx-hook-native-ui-regression.sh` 明确要求设置页保留 Miuix Card 组件；已在 `153cf09` 恢复官方 Miuix Card，并保留 per-mode token 颜色/描边与无障碍选择语义，没有删除或放宽既有断言。
- GitHub 回读确认最终分支版本同时包含 Miuix Card、六模式 token 解析、模式文字色与 RadioButton 语义。
- CI：`FX Six UI Modes` 在功能提交 `361a0e1` 成功；该提交的 Targeted Host 失败于既有 Miuix Card 组件契约（run `42102963704`），已修复。修复提交 `153cf09` 的 Targeted Host run 被后续并行提交取消；后续 `2eb061cf` 的 Six UI Modes 成功（run `42103301447`），其 Targeted Host run `42103301422` 同样因新提交而取消。故最终 Miuix Card 兼容修复尚无完成的 Targeted Host 结果。
- 未运行 Gradle/Android 编译、APK 构建、模拟器、安装或真机验证；不得将源码静态回归描述为设备验收。
- 下一批：在并行提交暂歇时补跑 Targeted Host；继续检查六种模式在六个主 Tab 与二级页的 renderer 覆盖和皮肤切换不触碰后台服务的回归。

## 2026-11-06 — FX Hook Kotlin source/Frida signature support

- `DeveloperExecutableDescriptor.java` now maps explicit Kotlin source aliases to exact JVM descriptors: primitive aliases, `String`, `Any`, `Unit` return, primitive arrays, and erased Kotlin collection interfaces.
- Generic arguments remain rejected unless the caller supplies the erased type; `Unit` is rejected as a parameter. Existing package scoping and descriptor resolution remain unchanged.
- Added JUnit coverage in `DeveloperExecutableDescriptorTest.java` and a JDK-only Host regression (`scripts/tests/FxKotlinHookSignatureHostTest.java`, run by `scripts/tests/fx-kotlin-hook-signature-regression.sh`).
- Documented supported Kotlin forms in `docs/FX-HOOK-DEVELOPER-CUSTOM-RULES.md` and connected the regression to `fx-targeted-regression.yml`.
- Commits: `0850121972c87017e1bdcaf00f49f97882feb921` (parser), `2eb061cf48e7bcb73486b2a2eeb36d557deba1df` (JUnit tests), `16067ae9648609f388c5e775b0e5dc2d574e7ff2` / `5251cb214e0eb6b70e502947251cfcdd9e45eca7` (Host test), `1ca95d7d963b967ee93becc04b94ed94ea272ffa` (docs), `6adb8ddb38a961c3051094f9e3db73a961fc8113` (CI).
- Verification: all six modified/new files were re-read from the branch and SHA-checked. Targeted Host Actions run `42103395746` was queued at the time of this update; no pass is claimed yet. Android Gradle build, LSPosed injection and real-device Hook execution were not performed.


## 2026-11-06 — VPN 共存端口状态贯通原生页面

- arbiter 的 5353 上游 DNS、53 客户端过滤 DNS、7890 代理端口状态现由 `patch_vpn_coexistence_status.py` 从同一份裁决 JSON 解析，并写入 0600 临时文件后原子替换状态快照；端口值和 owner 枚举进入白名单校验。
- 旧版/缺失 arbiter 字段回退到默认端口号与 `unknown`，不会把未知当空闲。已有 `dns`、`proxy` 等快照消费者保持兼容，新增 `dns_filter`。
- MainActivity 的共存卡新增端口状态展示：DNS 上游、DNS 过滤入口与代理分别显示空闲/已占用/未知；不把 `other` 进一步推断为具体应用进程身份。
- Host 状态发布回归和 UI 源码契约扩展同步覆盖端口传递、旧 arbiter 缺字段回退和页面显示。构建、设备端 Root / procfs 权限和真实监听进程归属仍以对应 CI/真机结果为准。


## 2026-11-06 — GKD test invocation / system-app overlay regression follow-up

- GKD CI 修复提交：`92e0ee9b0183b794fcc4591ab139835c54377beb`。修正 `.github/workflows/fx-gkd-selector.yml` 的 Gradle 多行参数缺少续行符，确保 selector、package throttle、pending package scan 三组 JUnit 一次性传入 Gradle。
- GKD Actions run `42102998771` 最终 SUCCESS：上游 selector contract、隐私/路由静态契约、FX Android app + Accessibility adapter 编译、FX GKD selector adapter JUnit 全部完成。该结果是 GitHub CI，不是设备无障碍服务真机验证。
- 系统应用 early-boot 日志目录 symlink guard 提交：`5990d3a5516c7d35e36681e2424b6326503e431c`（模板）及 `360a26f224ae7dd4141c708edab6131fdf678d86`（模块脚本同步）。post-fs-data 日志写入在逐路径组件检查之外显式拒绝 LOG_DIR 本身为符号链接。
- FX Hook native UI regression 中的 Miuix Card 断言已恢复为真实 Card 检查（`f99db43bfe368a57a6bbce15836073145f08bbe8`）；依赖并行修复提交 `153cf09` 在模式选择页恢复真实 Miuix Card，未降低原测试要求。
- System App Install Stage Actions run `42103559203` 在提交 `7e9664e` 上 SUCCESS：patcher 幂等性、安装期校验/部署、early-boot overlay symlink/digest/marker 测试、打包接线均通过。此前 run `42103453530` 的唯一失败是测试脚本 mktemp 模板引号错误；并行提交 `7e9664e` 修正测试路径后通过。
- VPN arbiter failed-interface-inventory 回归：`6f5c195e97b9fa182dd0f6f603d920a60883b859` 新增部分 stdout + 非零 ip 退出的 fail-closed 场景；`bba5e10275de0b847c49c848ce827f393c009596` 修正 fixture 转义。VPN Coexistence Arbiter run `42102744421`、Targeted Host run `42102745222`、Six UI Modes run `42102744474` 均 SUCCESS。
- 验证边界：Miuix Card 最终 Targeted Host 结果仍被后续并行提交取消；Module Runtime run `42103559262` 在当前状态更新时仍运行。未声称 KernelSU 真机安装、SELinux 标签、OnePlus 12 VPN/DNS/TUN 数据面或 LSPosed 实际注入通过。

## 2026-11-05 — FX system-app early-boot overlay hardening

- Implemented in the existing systemless /system/app/FX deployment chain; no new installer or parallel module was created.
- Canonical early-boot verifier now lives at fx-patches/fx_system_app_post_fs_data.sh; patch_system_app_install_stage.py reads this reviewed source when patching restored KernelSU/Magisk module archives. The tracked fx-module/post-fs-data.sh carries the same managed block.
- Added lexical path-component checks for the overlay and private state/log paths. Relative paths, parent traversal, and symlinked ancestors are rejected before state/log creation; log file and directory types are checked explicitly.
- Deployment and retry markers now use private 0600 temporary files with noclobber creation and atomic rename. Pre-existing temporary symlinks cannot redirect the privileged boot-time write. Existing APK digest verification, SELinux label verification, retry semantics, and non-privileged system-app classification are preserved.
- Added host regression scripts/tests/fx-system-app-overlay-boot-regression.sh covering valid deployment, invalid digest retry, symlinked state ancestor, and pre-created retry-temp symlink protection. The test uses injectable test paths only; production defaults remain /system/app/FX and /data/adb/privacyguard.
- Updated .github/workflows/fx-system-app-install-stage.yml to watch the canonical verifier and tracked boot script, so future edits run the deployment tests.
- Verification: FX System App Install Stage run 42103559203, commit 7e9664ea82d3141a28dee484b0ee4df8fcd4868a, SUCCESS. Patcher idempotence, installer behavior, synthetic installer execution, boot script syntax, boot overlay regressions, and KernelSU packaging-stage presence all passed.
- Not verified: Android device PackageManager recognition, device-specific SELinux policy behavior, reboot persistence, or actual KernelSU/Magisk installation. No APK/ZIP build or real-device test is claimed.
- Concurrent work continues on the same branch. The branch's live HEAD must be re-read before the next edit; this note records only the completed system-app batch and its exact CI evidence.



### 游龙 Ad Root 入口统一接入共享模块解析器（2026-11-06）

- 将 Ad 小组件、Ad 快捷磁贴、VPN 快捷磁贴、Tasker Receiver、本机防护总结页迁入 `FxYulongRootModuleCommand`，统一父目录、模块版本、脚本目录和目标文件的 fail-closed 检查。
- 共享 allowlist 新增 `yulong-vpn-control.sh`；保留 VPN 命令既有模块目录和状态目录参数，Tasker 的发送方 UID/签名校验、控制平面锁、回执均不变。
- 扩展共享解析器回归和 JDK Host allowlist 测试，覆盖这些入口不再自行构造 `MP='';` 路径。
- 设备端小组件、快捷磁贴和 Tasker 实际 Root 操作尚未验收。


## 2026-11-06 — VPN 共存快照临时文件权限失败关闭

- 修正 `fx_coexist_status_write()` 的临时文件创建顺序：原实现对整个子 shell 做输出重定向，重定向发生在子 shell 的 `umask 077` 执行之前；此外 `chmod 0600` 失败会被忽略，仍可能发布权限过宽的状态快照。
- 现在先在受限 umask 下通过 `mktemp` 创建随机名称临时文件，验证其为普通非符号链接文件；内容写入、强制 `chmod 0600`、JSON 完整性检查和原子 `mv` 全部成功后才发布。任一环节失败删除临时文件并保留上一份完整快照。
- 状态发布回归新增故障注入：替换专用 `chmod` 调用使临时文件权限设置失败，断言调用方仍 fail-open、旧快照内容/0600 权限不变且无残留临时文件。
- 本修复针对 Root 状态快照落盘的权限和原子性，不改变 VPN 路由、DNS 规则或第三方网络设置；设备端文件系统/SELinux 仍需真机验证。

## 2026-11-05 — production Android VPN ownership probe

- Fixed a production-path gap in scripts/fx-vpn-coexistence-arbiter.sh: the standalone arbiter referenced vpncore_android_active_vpn_info without defining or sourcing it. Test-only VpnInfo fixtures had hidden that missing production provider.
- Added a self-contained Android dumpsys connectivity reader. It accepts exactly one well-formed VpnInfo ownerUid/interface record; a successful mVpns section with no active VpnInfo is the only clean empty result. Missing/failed dumpsys, incomplete output, malformed records, or multiple VPN ownership records fail closed as unavailable rather than being mistaken for no external VPN.
- Added regression cases for a real-shaped VpnInfo dump, confirmed empty mVpns, failed dumpsys, and multiple VpnInfo rows. The arbiter remains read-only.
- Verification: FX VPN Coexistence Arbiter run 42104207561 (#26) SUCCESS, including the grading regression, read-only assertion, and live runner smoke check. Targeted Host Regression #1292 also completed SUCCESS on the same integrated branch lineage.
- Live runner correctly reported unknown because the GitHub runner did not contain a complete installed FX module root; this is an expected fail-closed result, not evidence that no VPN was active.
- No Android device test or real VPN traffic-path proof is claimed. The arbiter continues to report route/data-plane proof as unverified until a device-level end-to-end test exists.



## 2026-11-06 — Yulong Ad Root 模块发现集中化（续）

- 在保留并行提交已加入的 `yulong-vpn-control.sh` allowlist 和小组件/磁贴/Tasker 统一入口基础上，新增固定 allowlist 项 `yulong-app-firewall.sh`。
- Ad 主配置页、DNS 日志页和防火墙页现统一调用 `FxYulongRootModuleCommand`，不再各自拼接 `MP=''` 模块查找命令；Ad 总结页、General/import、profiles、白名单、小组件、两种磁贴和 Tasker 已在前序/并行提交接入共享构造器。
- DNS 页面仍将操作限制为 `dns-log-tail`、`cache-flush`、`dns-log-clear` 三种固定值；防火墙固定绑定 `yulong-app-firewall.sh`，不会接受可替换脚本路径。
- 扩展 JDK Host allowlist 与共享 Root resolver 回归，覆盖新增 Ad 主页、DNS、防火墙消费方；同步更新原有 Ad/DNS/Firewall 测试和 targeted workflow 路径映射。
- 本批等待提交后的 Targeted Host Actions；没有声称 Android 构建、设备 Root 执行或真实流量拦截验收通过。


## 2026-11-06 — 修复系统应用开机校验的临时文件碰撞

- 修复提交：`308c5730ff2d33d68ee80aee23d9c312e6407b86`（补丁源）；`899ae53d3437d2d8c8300545ba488799b0772265`（模块内同步）。
- CI 在早期开机覆盖层回归中发现 deployment marker 临时文件名未包含 PID：测试预置 `system-app-apk.sha256.tmp.<pid>` 符号链接时，脚本却写入固定的 `tmp.$` 名称，未能触发预期的安全拒绝/重试路径。
- 将 retry marker 与 deployment marker 临时路径统一改为 `tmp.$$`，使每个执行进程使用自己的临时文件名，并与现有原子创建（`set -C`）、符号链接检查及失败重试逻辑配套。
- 两份源文件已从目标分支回读：`fx-patches/fx_system_app_post_fs_data.sh` 与 `fx-module/post-fs-data.sh` 均包含 PID 后缀。
- GitHub Actions：`FX System App Install Stage` 在 `899ae53` 成功（run `42104541678`，job `127515820097`）；安装期幂等、行为测试、early-boot overlay hardening 与打包阶段检查全部通过。
- 验证仅为 GitHub Host CI；尚未在真实 KernelSU/Magisk 设备上验证重启后的 PackageManager 扫描、SELinux 实际标签或 OTA 行为。

## 2026-11-06 — coexistence status publisher and boot-marker follow-up

- Fixed the VPN coexistence status publisher's unset _fx_cs_slot_json under apply.sh set -u. It now serializes only true/false/null slot evidence and explicitly emits null for unknown values; the status write remains fail-open to the network path.
- Added/retained PID-scoped names for both retry-marker and deployment-marker temporary files. The boot regression now attempts symlink redirection against both temporary paths and checks the external sentinel remains unchanged.
- Verification: Targeted Host Regression #1297 SUCCESS on commit 8f6ddf7f96eaf634ca9dbe1fd094fa760ff703dd; System App Install Stage #21 SUCCESS on commit 899ae53d3437 (includes both temporary-marker symlink cases and the packaging-stage check).
- Earlier System App Install Stage #18/#19 failures were not hidden: their logs exposed the PID suffix regression and the test was corrected to use the actual child-shell PID; subsequent #21 passed.
- No device install, reboot, PackageManager, or SELinux enforcement test is claimed.



## 2026-11-06 — VPN 共存快照临时目录权限回归兼容修正

- 前一版权限加固以 `mktemp` 建立状态快照临时文件，但目标 Host/模块回归中的实际执行返回码为 2，导致正常快照未创建；已撤回对 `mktemp` 的依赖。
- 现使用 POSIX `mkdir` 的原子创建语义：在 `umask 077` 下创建 PID-scoped 私有临时目录，再在目录内以 noclobber 创建状态文件；文件必须通过 `chmod 0600`、非空/JSON 标记检查及原子 `mv` 才能替换正式快照。
- 任何写入/权限/替换失败均只清理该次临时文件和空目录，不覆盖原快照、不改变 VPN/DNS 路由；chmod 故障注入回归保持启用。新版本的 Host/Module Runtime 结果尚待当前 HEAD 的 Actions 核验。

## 2026-11-06 — Hook Kotlin signature Host verification and early-boot APK marker hardening

- Follow-up to the Kotlin signature integration above: the JDK-only regression now explicitly asserts `kotlin.Unit`, primitive-array and Kotlin collection erasure coverage. GitHub Actions run `42104749088` (`FX Targeted Host Regression`, HEAD `0cdf698c`) completed successfully and its log contains `PASS: Kotlin source and Frida signatures resolve to exact erased JVM descriptors`.
- Early-boot system-app verifier had a real path uniqueness defect: retry/deployment marker temp names ended in a literal `$` rather than the running shell PID. Canonical patch source `fx-patches/fx_system_app_post_fs_data.sh` and tracked module `fx-module/post-fs-data.sh` now use `.tmp.$$` for both marker types.
- Expanded `fx-system-app-overlay-boot-regression.sh` to exercise retry-temp and deployment-marker-temp symlink protection with the real FX state/app paths. The test fixtures publish the shell PID, then create the matching symlink before allowing the verifier to proceed.
- GitHub Actions run `42104541678` (`FX System App Install Stage`, HEAD `899ae53d`) completed successfully: patcher idempotence, installer behavior, shell validity, early-boot digest/SELinux/marker regression and packaging integration all passed.
- These are Host/CI results only. No Android Gradle APK build, KernelSU ZIP build, LSPosed injection, root-device SELinux verification or real-device VPN/DNS test is claimed.

## 2026-11-06 — dual-stack Root Proxy DNS health gate

- Root Proxy previously activated both IPv4 and IPv6 DNS DNAT rules after probing only 127.0.0.1. A broken/missing AdGuard IPv6 loopback listener could therefore leave IPv6 clients redirected to ::1 without a verified resolver.
- The runtime health gate now requires a valid DNS answer through both 127.0.0.1 and ::1 before attaching either OUTPUT redirect generation. The shipped AdGuard runtime config already binds both loopback addresses; failure of either probe triggers the existing fail-open rollback.
- Extended the Root Proxy runtime fixture to record both probe destinations and inject an IPv6-only probe failure. The regression verifies both loopback families are queried and the IPv6 failure path is rejected.
- Verification: FX Targeted Host Regression #1304 SUCCESS on commit 4b7c816005273dbc79c45356dcb8aa900ee376c3; FX VPN shell regression #34 SUCCESS on the same commit. The Root Proxy runtime regression reported PASS for dual-stack rules, route/UID proofs, symlink guards, independent DNS ownership and fail-open rollback.
- The test is a host-side mocked resolver test; actual Android IPv6 routing, device resolver binding and carrier-specific IPv6 behavior still require device validation.



### Ad 总结页 Host 回归契约补强（2026-11-06）

- `FxYulongAdSummaryActivity` 的有界 `enqueueLatest()` 已由并行提交恢复；本批不重复修改该方法，而是增强 DNS summary regression，明确验证 null task 拒绝、Activity teardown 拒绝、旧 waiter 淘汰和最新任务重新入队。
- targeted workflow 的 DNS summary 与共享 Root resolver 触发条件均加入 `FxYulongAdSummaryActivity`，确保后续 Summary 代码变更实际执行两项 Host 回归。
- 上次 Host run `42104599004` 的具体失败是 summary enqueueLatest 定义缺失；该实现已在后续并行提交进入当前 HEAD。本提交之后将以当前 commit 的 Host 结果确认回归。


## 2026-11-06 — 游龙 Ad 防护总结刷新队列修复

- 功能提交：`1a07ae472417331ff3947968465a41d6c98a0b53`；回归增强提交：`3e02e954cec0108028bcffcf57a6ee815e806f24`。
- 修复 `FxYulongAdSummaryActivity` 中调用了但未定义的 `enqueueLatest`：新请求先移除尚未开始的旧排队请求，再提交最新 Root 读取；正在执行的旧请求不强制杀死，仍由 `loadGeneration` 阻止过期结果覆盖新页面；Activity 已销毁时拒绝继续入队。
- 回归脚本新增队列销毁状态与最新请求提交断言，原有 `worker.getQueue().poll()` 断言保留。
- GitHub 回读确认 `enqueueLatest`、`poll`、`execute` 均已存在。
- GitHub Actions：`FX Targeted Host Regression` 在 `3e02e954` 成功（run `42105155375`，job `127517900195`）；日志确认执行了 `fx-yulong-ad-dns-summary-regression.sh`，静态请求队列/配置解析/隐私字段断言通过。该 Host-only lane 明确跳过依赖 Release 模块归档的 AdGuard YAML runtime 渲染测试；不将此项报告为已通过。
- 尚未执行 Android Gradle 编译或设备端 Root/DNS 运行验证。


## 2026-11-06 — VPN 共存快照权限修复与运行回归证据

- POSIX 私有临时目录版本的状态发布器回归已通过：FX Targeted Host Regression run `42104828405`，checkout `61436e014303688d8374c3f0d04cb53d3133e4ba`，结论 SUCCESS。日志明确包含 case 6b（临时文件 `chmod` 失败时旧快照保持不变）、旧快照 0600 权限保持、失败临时文件清理，并最终输出 `PASS: coexistence status is published atomically, 0600, fail-open and never overclaims`。
- UI / DNS 端口状态接线随同一提交进入分支：5353 上游 DNS、53 客户端过滤 DNS、7890 代理状态进入发布快照；未知字段回退为 unknown，原生共存卡显示空闲/已占用/未知。Host 的状态发布回归通过；六模式/UI 总体流程仍按各自 run 单独记录，不以此 Host 结果代替 Gradle APK 构建。
- FX Module Runtime Regression run `42104989565`（checkout `4b7c816005273dbc79c45356dcb8aa900ee376c3`）中，Release 模块恢复、VPN/DNS/Root Proxy patch 步骤 SUCCESS；外部 VPN/TUN/DNS/watchdog 回归步骤 SUCCESS；Root Proxy/native VPN 集成回归步骤也 SUCCESS。但 workflow 最终结论是 CANCELLED（被后续 push 中断），故只记录上述步骤通过，不记录为完整 Module Runtime SUCCESS。
- FX VPN shell regression run `42104989387` 在同一 checkout 上为 SUCCESS；其中 Root Proxy 真实脚本 Host fixture 验证双栈规则、路由/UID 证明、状态路径符号链接保护、独立 DNS ownership 和 fail-open rollback。
- 验证等级仍不包含 Android Gradle 最终 APK 构建、KernelSU ZIP 生成/安装、真实设备 SELinux enforcement、Android Framework 多 VpnService、第三方 VPN 实机链式路由或运营商 IPv6 兼容性测试。


## 2026-11-06 — DNS Root 模块发现测试迁移到共享命令构造器

- 测试修复提交：`6683f4d2b7f2d2cc86b83cec31a254a64edabbb6`、`740ab96913390fc3a6a31538e37131527f398dd1`。
- `FxYulongDnsActivity` 已通过 `FxYulongRootModuleCommand.command(...)` 统一构造 Root 命令；旧测试仍在 Activity 的 `shell()` 中寻找内联的 `/data/adb/modules` 路径校验，导致在代码正确集中化后误报。
- 更新 `fx-yulong-dns-cache-regression.sh`：确认 Activity 委托给共享 builder；对 builder 的 `prefix()` 验证 /data、modules、modules_update、module.prop、util.sh、scripts 路径及 symlink 拒绝；对完整 helper 验证 Ad control 脚本 allowlist；DNS 操作参数仍须显式 allowlist。
- 首次测试修订将动态脚本名误放在 prefix 子串中检查，CI 指出后已修正为在 helper 的 allowlist 中验证。
- GitHub Actions：`FX Targeted Host Regression` 在 `740ab969` 成功（run `42105645188`，job `127519614084`）；日志确认 `fx-yulong-dns-cache-regression.sh` 实际执行，DNS cache flush 顺序、失败传播、forward-only、锁所有权和共享 Root path/allowlist 静态断言均通过。
- 该改动只更新测试契约；共享 Root builder 的生产实现由此前 `00b291ce` 集中化提交提供。


## 2026-11-06 — Security Shield 前台事件驱动与低频 UsageStats 兜底

- 功能提交：`1d6fa8d39cdcbbe27ffa91695404f9c2f0c28a25`。
- `FxYulongProtectionService` 原先固定每 2.5 秒轮询 UsageStats。现在保留前台包名 Accessibility 广播的即时评估路径，并在收到首次有效前台事件后将 UsageStats 兜底轮询放宽到 15 秒；尚未收到事件时使用 5 秒兜底，避免依赖 Accessibility 权限才能运行。
- 新增 `lastForegroundSignalAt` 与 `nextPollDelay()`；不改变用户主动启用保护、Usage Access 撤销处理、白名单判断、摇动传感器或通知冷却策略。
- `fx-yulong-shield-native-regression.sh` 增加 5s/15s 调度、前台事件时间戳和动态调度调用断言。
- GitHub Actions：`FX Targeted Host Regression` 在 `1d6fa8d` 成功（run `42105958892`，job `127520719701`）；日志确认 Shield native、六 Tab 与 worker bounds 回归均通过。
- 这是源代码/Host 回归验证，不是实机电池测量；实际功耗和不同 ROM 的 Accessibility 广播稳定性仍待设备验证。


## 2026-11-06 — VPN/DNS Module Runtime 18 项回归通过

- GitHub Actions：`FX Module Runtime Regression` 在 `1d6fa8d39cdcbbe27ffa91695404f9c2f0c28a25` 成功（run `42105958695`，job `127520719072`），日志明确报告 `VPN/DNS runtime regressions: 18/18 passed`。
- 通过项覆盖：TUN UP/DOWN 检测与外部 VPN 冲突保护；sing-box DNS exact/suffix/whitelist 语义；VpnInfo 唯一 owner UID 与活动隧道验证；三轮 VPN connect/disconnect 状态切换；watchdog 数据面健康检查、恢复限频和 fail-safe；TUN 到 REDIRECT fallback 的外层 VPN 接口/UID/路由证明；Unbound VPN-bound IPv4 egress；Root Proxy 双栈 DNS 规则、状态路径 symlink 防护、独立 DNS 引擎所有权和 fail-open rollback；Hosts cache 锁、同 URL fetch gate、顺序提交及 SHA-256 sidecar。
- 该运行还通过 Hosts 缓存与 Root Proxy 原子锁、并发串行化、symlink/FIFO 拒绝回归。
- 验证等级为 GitHub Module Runtime/Host 仿真；不代表 Android Framework 的 VpnService slot、不同 ROM 路由策略、真实 TUN 包流或外部 VPN App 白名单组合已在设备上通过。


## 2026-11-06 — VPN 共存裁决器扩大 VpnService 静态扫描范围

- 功能提交：`73a338a93d7a5614624e3b6d835babcda7be65a5`。
- 回归提交：`5ca33f3f2d41556c17f73563c9b9f146842585ef`。
- 问题：原 `fx_arb_slot_used()` 只检查 `apply.sh`、`vpncore.sh`、`yulong-root-proxy.sh`、`yulong-vpn-control.sh` 四个固定入口。以后新增的模块 shell helper 若调用 `VpnService.prepare()` / `VpnService.Builder`，旧检测器可能仍把 FX 数据面报告为不占 Android VPN 槽。
- 修复：保留四个核心入口的完整性要求，并扫描模块 `scripts/*.sh` 全部顶层 shell 源文件；发现 VpnService API 即判定 slot-used，发现符号链接、不可读/非普通文件或空扫描则 fail-closed 为 unknown。没有执行网络命令，也没有改变任何路由或防火墙规则。
- 新增回归：在四个既有入口均干净时，额外注入 `new-dataplane-helper.sh` 调用 `VpnService.prepare()`，断言裁决器返回不兼容且 `vpn_service_slot_used=true`。
- 后续加固：扫描 glob 同时识别 `-e` 与 `-L`，避免悬空 `.sh` 符号链接因目标不存在而被跳过；新增悬空链接夹具，预期返回 unknown/null，而不是错误报告 slot-free。源码提交 `689d3d390b80879a459b6b381fe92bfb2e236741`，测试提交 `888a48d736d487f3d19cb910adaa9038c5fb1fe7`。
- GitHub 回读：最终源码 blob `9b0c9b5f5507cc6b8b16acb7b7c4881e06e91c91`，最终测试 blob `7540b5deeb776d78ec6c6b16690b30bfb22437d1`，均已从目标分支重新读取并确认包含全量扫描、新 helper 与悬空 symlink 回归。
- 验证等级：GitHub 提交成功、源码/测试回读确认。当前连接器未提供该分支的一般 Actions run 列表，且新提交的 combined status 为空；因此本批 Host regression / CI 尚未确认通过。未运行本地完整回归、Android Gradle 构建或真机测试。
- 限制：此检查只覆盖模块 `scripts/*.sh` 顶层脚本中的静态 API 特征；不能证明运行时没有动态加载、二进制或 APK 内部创建 VpnService，也不能证明第三方 VPN 流量路径共存。真实数据面仍须设备级测试。


## 2026-11-06 — VPN coexistence IPv6 DNS port-conflict regression

- 回归提交：`0f62bb234f5625a891764a2a02da6148c790622c`（`scripts/tests/fx-vpn-coexistence-arbiter-regression.sh`）。
- 新增独立 IPv6 TCP/5353 与 UDP/5353 监听夹具，分别验证 arbiter 从 `/proc/net/tcp6`、`/proc/net/udp6` 识别上游 DNS 端口占用；两种情况均必须显示 `dns.owner=other`，不能把 IPv6-only listener 误判为空闲。
- 工作流 `.github/workflows/fx-vpn-coexistence-arbiter.yml` 已核实会在该回归脚本路径变更时触发。
- GitHub 回读验证：分支版本测试文件 blob SHA 为 `629bf7155e385a34eed320e24a1ab9e8ab6de2c5`；IPv6 TCP/UDP fixture 与 case 4e/4f 均存在。未能通过当前可用 GitHub Actions 读取接口获取 push-triggered run 结果；因此不宣称 CI/测试通过。当前环境也未执行本地 Shell 回归。
- 未修改生产路由、DNS、iptables/nftables 或用户 VPN 状态；未运行 Android Gradle、APK/KernelSU 构建或真机测试。
- 后续：读取本次 push 对应的 VPN Coexistence Arbiter Actions 结果；若失败按日志修复 fixture/实现，不放宽断言。继续补齐 IPv6/DNS 实际路由和真机第三方 VPN 数据面验证。


## 2026-11-06 — 六种界面模式 renderer 独立性回归补强

- 测试提交：`2cc548f56f955944e5d41f0747e8ddc025d11d18`。
- 改动：`adhook/app/src/test/java/de/privacyguard/adhook/FxUiModeTest.kt` 在既有六模式稳定 ID / 顺序 / 默认 renderer 断言之外，新增六种模式必须映射到六个不同 Renderer 的断言，防止后续将某个皮肤错误复用为其他模式 renderer。
- GitHub 回读：测试文件 blob `7dd74cec53405fbab129e45a6bdeeebbca49130f`，新增断言已确认存在。
- 验证等级：仅完成 GitHub 写入与回读；本轮未运行 Gradle/JUnit、Android 构建、UI 自动化或真机测试。对新提交查询到的 workflow runs 为空，不报告 CI 通过。
- VPN 共存裁决器文件在本轮读取后出现并发更新；对其写入收到 GitHub 409，未强制覆盖，已放弃对共享 VPN 文件的修改并以最新分支内容为准。
- 下一批：补齐六模式跨页面 renderer 覆盖测试，并继续从最新 HEAD 检查 VPN/DNS 实际数据面状态与第三方 VPN 兼容性；设备级网络路径仍需真机证据。


## 2026-11-06 — 六模式 renderer 精确映射回归

- 测试提交：`2438452adcaa149b0050f6be82839401ecd5f1e0`。
- 在 `FxUiModeTest` 增加精确映射断言：default→NATIVE_DEFAULT、classic→WEB_COMPAT、glass→NATIVE_LIQUID、miuix→NATIVE_MIUIX、huawei→NATIVE_HARMONY、ios→NATIVE_CUPERTINO。原有六个 renderer 必须互不相同、稳定 ID 顺序、名称及旧别名迁移断言均保留。
- GitHub 回读：测试文件已确认包含新测试；本轮未运行 Gradle/JUnit。该提交关联的 workflow run 查询为空，故 CI 未确认。
- 这属于枚举配置契约测试，不证明六个 renderer 的每个页面都已完整实现或 UI 真机视觉一致。后续需补跨页面导航/功能入口覆盖，并运行 `./gradlew :app:testDebugUnitTest :app:assembleDebug` 与 release 构建；当前 Android Gradle/SDK/依赖解析环境尚未在本轮执行。


## 2026-11-06 — VPN kernel-only 状态措辞收紧

- 实现提交：`a4bb63dd37d433e1b1d92c07956eace2d03af0b7`。
- 回归提交：`7c5fc05797ad199d58c35c74eeb2f27cd2c08008`。
- 修正：无外部 VPN 时，不再把“内核数据面未占 Android VPN 槽”表述成“数据面正在运行”；现在明确说明数据面配置在 VPN 槽之外，但实时流量路径仍未验证。
- 回归覆盖：断言 `kernel_only` 的 `route_probe` 必须是 `unverified`，且理由必须披露实时流量路径未验证。
- 回读：实现文件与回归文件均已重新读取；新增断言已确认存在。
- CI：目标 Host Regression 工作流配置了该分支 push 触发，且 `scripts/tests/**` 属于触发路径；当前 GitHub 工具不能查询 push runs，故 CI 结果未确认。
- 本轮未执行本地 shell 回归、Gradle、Android 构建或真机流量测试。
- 并发协作：状态文件与回归文件均遇到并发 409；均重新读取最新 blob 后再提交/恢复，未强制覆盖其他 AI 的修改。


## 2026-11-06 — 修复 VpnService 静态检测正则漏报

- 生产修复提交：`227f589d318372578d3f8857e3e9321b9066f497`。
- 回归测试提交：`f9755e72ba037664538279f542a7bb3f9488f4ba`。
- 问题：现有检测正则把点号和美元符号写成了双反斜杠形式，导致 `VpnService.prepare()`、`VpnService.Builder` 等实际 API 签名无法可靠匹配；同时原有注释过滤方式会漏掉带缩进注释。
- 修复：先过滤以任意空白开头的整行注释，再使用字符类 `[.]` 和 `[$]` 匹配 API 分隔符，不再依赖易错的反斜杠转义。
- 新增/强化回归：保留 `VpnService.prepare()`、`VpnService.Builder` 两种调用覆盖；增加 `VpnService$Builder` 覆盖；将注释夹具改为带缩进形式，验证注释不造成误报。
- GitHub 回读：生产脚本 blob `e72cacc0e242e4866a929685b76c39100c16e3b7`；回归脚本 blob `0f6b7c9e72e70533899b0e353b3b3fe1d6e0e3b5`。两者均从目标分支回读，确认修复与测试用例存在。
- 验证等级：在独立 shell/grep 夹具中验证三种签名匹配、整行缩进注释过滤；未执行完整 arbiter regression。新提交 combined status 为空，当前 GitHub Actions 读取接口不能列出 push-triggered runs，故 CI 状态未确认；未运行 Android 构建或真机测试。
- 影响：修复前的静态扫描结果不能作为 FX 不占 Android VPN 槽的证据。修复后仍仅覆盖模块 shell 源码静态特征，不替代 APK/二进制扫描、运行时观测和设备级流量验证。


## 2026-11-06 — VPN arbiter 回归接入 CI

- CI 提交：`607b2365919912740f4b47f95e8f81d477d3de8b`。
- 发现：已有 `scripts/tests/fx-vpn-coexistence-arbiter-regression.sh`，但目标 Host Regression workflow 未按 arbiter 源码/测试文件变化触发它。
- 修正：在 `.github/workflows/fx-targeted-regression.yml` 增加路径匹配，修改 `scripts/fx-vpn-coexistence-arbiter.sh` 或对应 regression 脚本时自动执行该回归。
- GitHub 回读确认 workflow blob `817295b66beacfbb5b3e127bd77992cca477ebbb`，执行命令存在。
- CI 实际运行结果尚未通过可用工具查询；不能宣称测试通过。


## 2026-11-06 — FX Hook 系统应用启动时序回归

- 测试提交：`fe0b03f3b4bf8ff75b516a1faee755b70c8c65ac`，更新 `scripts/tests/adhook-app-installer-regression.sh`。
- 新增时序契约：KernelSU systemless `/system/app/FX` overlay 必须在启动早期由 post-fs-data 校验/恢复 SELinux 标签；Hook 的 PackageManager 检查/安装入口必须位于 `sys.boot_completed=1` 等待之后，避免与 Android 首轮系统应用扫描竞争。
- 回归还断言 post-fs-data 不直接执行 `pm install` / `pm path`，将 overlay 标签处理与 PackageManager 阶段隔离。
- GitHub 回读：新 Python 顺序断言和 post-fs-data 断言已确认进入分支。尚未执行该 Shell 回归或 Python 子断言；相关 Actions 结果未确认。没有声称系统应用真机部署通过。


## 2026-11-06 — VPN arbiter 生产脚本纳入 CI 触发路径

- CI 修复提交：`c14961926d9e6e25a44e5c8e499f2cf0ba888b45`。
- 发现：workflow 的 job 条件已经能识别 `scripts/fx-vpn-coexistence-arbiter.sh`，但 push/PR 的 `paths` 过滤器遗漏了该生产脚本。只修改裁决器源码时，整个 workflow 可能不会启动，导致刚修复的检测器没有自动回归。
- 修复：将生产脚本路径同时加入目标分支 push 与 pull_request 的路径过滤器；测试文件仍由既有 `scripts/tests/**` 覆盖，job 内按文件名条件执行 arbiter regression。
- GitHub 回读：workflow blob `f36be3b4b426d29a2518972d437c60ce7c2b4ea6`，确认 push 和 PR 路径过滤器均含生产脚本。
- 验证等级：workflow 源码静态回读确认；未触发 workflow_dispatch，也未取得该提交实际 Actions run。不能报告 CI 通过。


## 2026-11-06 — system-app overlay missing/mount failure retry visibility

- Production fix: `dbc1801703ca099ff51e4fcf60d1a480658b8863` updates `fx-module/post-fs-data.sh`. Missing/unmounted `/system/app/FX`, absent APK, symlink/traversal paths now enter the existing safe retry-marker path instead of silently exiting.
- Regression assertion: `1931a4942c068b10caf0f492c19bdf2fbea35953` extends `scripts/tests/adhook-app-installer-regression.sh` to require explicit missing-directory and missing/unsafe-APK retry diagnostics.
- Reason: post-fs-data executes before PackageManager's system-app scan; a later boot-service install cannot retroactively change the current boot's system-app classification. Failure now remains diagnosable and retry state is retained without an unsafe ordinary-app fallback.
- GitHub readback verified production blob `4bf9a423bfeede20ffbf82deadd9c1f5b7d30586`, test blob `109d8e5c6b6a390a35a8fedbfd9431416ad66308`, and that `.github/workflows/build-fx-adhook.yml` invokes the regression script.
- Not yet executed: shell regression on a runner, Android Gradle/APK/KernelSU ZIP build, SELinux behavior on a device, PackageManager scan-order validation on target ROM. Do not mark CI or device verification complete until Actions/device evidence exists.


## 2026-11-06 — Hook validation workflow now runs on integration-branch pushes

- CI fix commit: `29a6c625c14d56fe279310d9fa2a611044cb8cfa` adds a `push` trigger limited to `fx-v1.0.0-unified-hook-integration` in `.github/workflows/build-fx-adhook.yml`. Existing PR and manual dispatch triggers remain intact.
- Root cause: workflow comments described cumulative push validation, but the event list did not include `push`; direct branch commits therefore did not start this workflow. The commit-associated workflow-run connector available here filters to pull-request runs only, so it cannot confirm the new push run. CI status remains unverified until a run is visible in GitHub Actions.
- Readback verified the push branch filter and preserved PR/manual triggers. This enables future commits to validate the latest cumulative tree; concurrency continues cancelling superseded runs.


## 2026-11-06 — VPN 共存裁决器脚本目录与端口冲突状态补强

- VPN slot scanner 修复提交：`e53770b2a3cef431234a0d2a339f702d385b5df3`；对应嵌套/符号链接目录回归提交：`30e33c926c632b7f0c8a0e3541afe4e4c0856683`。
- 扫描器递归枚举模块 Shell 文件，并额外检查 `scripts/` 内符号链接目录；脚本清单逐行读取，避免空格路径被拆分。任何不可信链接、find 错误或 grep 读取错误均 fail-closed 为 unknown。
- 首次 Arbiter Actions run `42107291150` 失败于既有新增用例 case 1f：裁决器已在 `reasons` 输出重复服务端口，但 JSON 缺少测试/状态消费者要求的独立 `config_conflicts` 字段。
- 修复提交：`c48f2379211b3e05459c2f32a21374345e08f22b`，在 JSON 状态中发布规范化后的 `config_conflicts`。分支回读确认字段已存在。
- 新一轮 Arbiter run：`42107395857`；记录时状态为 queued，尚不能记为通过。Android Gradle、KernelSU ZIP、真实设备 VPN/TUN/DNS 路径仍未验证。


## 2026-11-06 — VPN arbiter 源码清单失败回归

- 测试提交：`0516184bb5cb9be19d0d5cc6aec2c72677ca84c9`。
- 新增用例：用 PATH 前置的伪 `find` 返回非零，模拟模块 shell 源码清单命令失败；断言 arbiter 返回 `unknown`、退出码 2、`vpn_service_slot_used=null`，不得把扫描失败误判为不占槽。
- 本次只增加回归夹具，没有改变设备路由、防火墙或服务状态。完整 regression/CI 运行尚待确认。


## 2026-11-06 — Hook PackageManager work is fail-closed after boot timeout

- Production commit: `fd5b833a914cbe72d5b2b000e4d8af099bf5687f` changes `fx-module/service.sh`: after the existing 120-second `sys.boot_completed` wait, Hook installer/PackageManager work now runs only if the property is exactly `1`. If boot completion times out, Hook PM work is explicitly deferred and logged; the main FX DNS/VPN startup continues.
- Regression commit: `ef6ea56a6a152cb3a0de9270067135723bf809e2` strengthens the Python ordering contract inside `scripts/tests/adhook-app-installer-regression.sh`: it requires the boot wait, exact boot-complete gate, installer invocation inside the gate, and explicit timeout-defer branch in that order.
- Design boundary: the systemless `/system/app/FX` APK is still verified and SELinux-labeled by `post-fs-data.sh` before PackageManager's system-app scan. The service-stage installer is a later PM reconciliation step; it must not run after timeout while Android's package state may still be incomplete. This does not delay or disable the main DNS/VPN apply path.
- GitHub readback verified service blob `b42f66ab8209b15aa480b4db1a6c08eb9d6fded9`, test blob `d1b34b2e1c0d8b1b58f2a6c928a8121fb7a94d7c`, and the new ordering assertion text. The Hook build workflow has a target-branch push trigger and invokes the installer regression script.
- Not yet executed: complete shell regression, Python behavior fixture, Android Gradle/APK build, KernelSU ZIP build, target-ROM PackageManager/SELinux validation. CI run status is not available from the current commit-workflow connector (it only exposes PR-triggered runs); no CI or device pass is claimed.


## 2026-11-06 — VPN arbiter listener collision and source-inventory verification

- Added a production check for collisions among FX's independent DNS upstream, AdGuard Home client-facing DNS, and proxy listener ports. Ports are normalized as decimal values before comparison, so leading-zero aliases cannot evade detection.
- The arbiter now grades a duplicate FX listener configuration as `partial`, exposes the conflicting service pairs in JSON as `config_conflicts`, and includes the same information in text output. Unknown module VPN-slot state retains higher precedence and remains fail-closed.
- Regression coverage includes all three pairwise listener collisions, all-three collision, decimal normalization, IPv4/IPv6 TCP/UDP occupancy, incomplete/failed module source inventory, symlinked/nested module helper scanning, VpnService API signature detection, and text/JSON parity.
- GitHub Actions validation: FX VPN Coexistence Arbiter run `42107661260`, commit `24733adb101d933ece749a17fa06e0258220ad4c`, **SUCCESS**. The passing run includes the collision checks and the corrected text-mode test fixture. This is host CI evidence, not device traffic-path validation.
- The arbiter remains observation-only. External VPN interface/owner detection does not yet prove packet routing, return path, DNS reachability, or outer-tunnel binding; `route_probe=unverified` and external VPN operation remains conservatively graded. No OnePlus 12 / physical-device verification is claimed.
- Next P0: build an end-to-end, non-destructive route/packet-path probe for supported external VPNs, then validate on real Android devices and vendor VPN implementations. Never mutate third-party VPN routes during observation.

## 2026-11-06 — VPN coexistence arbiter regression passes

- Fixed the incomplete-module fixture expectation after the arbiter's slot scan was hardened to reject symlinked script entries and fail closed when the source inventory is incomplete. The diagnostic assertion now includes the actual verdict/JSON when it fails.
- Corrected Android `VpnInfo` host fixtures to provide a deterministic FX package UID. The production probe intentionally refuses to label a tunnel as third-party until `ownerUid` can be compared with the installed FX package UID; tests now cover third-party owner, FX-owned owner, unavailable PackageManager UID, and text-mode output.
- GitHub Actions `FX VPN Coexistence Arbiter` run `42107661260` at commit `24733adb101d933ece749a17fa06e0258220ad4c` completed successfully. All cases passed, including no-VPN/kernel-only, external VPN ownership, FX self-VPN rejection, TCP/UDP IPv4/IPv6 DNS port conflicts, malformed/partial inventories, nested helper scanning, symlink rejection, read-only enforcement, and JSON/text parity.
- Follow-up commit `229f28be5d416eaa23f9570c5ad67c1e69b35279` exports the fake PATH in the source-inventory command-failure fixture; latest branch readback includes this follow-up. The successful arbiter run predates that fixture-only adjustment, so the exact latest HEAD still requires a fresh arbiter run before claiming CI pass at latest HEAD.
- This arbiter remains observation-only. Its `partial` verdict explicitly does not prove packet routing, return path, DNS reachability, or true tunnel chaining. No device-level coexistence test is claimed.


## 2026-11-06 — 修复 VPN arbiter CI 的 dumpsys 测试夹具

- 失败运行：Actions run `42107398173`（提交 `0516184bb5cb9be19d0d5cc6aec2c72677ca84c9`），`FX VPN Coexistence Arbiter` 在 case 5c 失败；Shell 解析通过，失败在 Android VpnInfo 测试数据。
- 根因：case 5c3 fake dumpsys 使用双重转义的 `\\n`，输出字面反斜杠+n 而非换行，导致 parser 无法识别 `mVpns` 与 `VpnInfo` 行，产生假失败。
- 修复提交：`118161b61d5ec1ce1126898120deaa97b8918380`，将 fixture 改为真实换行格式。case 5c 用明确的 `FX_ARB_SELF_UID` 隔离 PackageManager 查询；case 5c3 单独验证 PackageManager UID 不可用时 fail-closed。
- GitHub 回读与新 CI 结果待确认；未声称该修复已通过 CI。



## 2026-11-06 — 并行 AI 推送下保留最新验证运行

- 发现：分支存在多个 AI 连续推送，多个关键验证 workflow 的 `concurrency.cancel-in-progress: true` 会在下一次 push 到达时取消正在运行的验证。GitHub Actions 记录显示，同一批连续提交上的 Hook APK 验证、六模式 UI 验证、Targeted Host Regression 和 Module Runtime Regression 多次被取消；例如 HEAD `5c565f7` 对应的 Hook APK 与六模式 workflow 均为 cancelled。
- 修复：将以下验证 workflow 的并发策略改为 `cancel-in-progress: false`，让当前运行完成，并由 GitHub concurrency 保留最新待运行任务；不改变正式打包 workflow 的取消策略：
  - `.github/workflows/fx-module-runtime-regression.yml` — commit `3d09002c674c087d7b011c95ca9539ae74cda7d7`
  - `.github/workflows/fx-targeted-regression.yml` — commit `8e4e9ad5642d46c8914395da6d85991d73bb5b64`
  - `.github/workflows/fx-six-ui-modes.yml` — commit `66d7f838e28cd91c768f06954bb8486f3b016b82`
  - `.github/workflows/build-fx-adhook.yml` — commit `a028a5183fcc2421af4a16d868bb7bddf2797439`
- 回读：四个 workflow 均从目标分支重新读取，blob SHA 分别为 `d033bc471bd45102624787d9b9a2ecf31792e4fb`、`1d3d417950290f953f5de1c143acf2199e5265c0`、`d5a1c25be99f0d752131ca05b0a7016374581a7c`、`ac01219d56b1efcff7b714fa30f65a73a127e0ab`，均确认 `cancel-in-progress: false`。
- CI：修复后 HEAD `a028a5183fcc2421af4a16d868bb7bddf2797439` 已触发 Targeted Host Regression、FX Six UI Modes、Hook APK validation；读取时均为 pending。较早提交的 Module Runtime Regression `42107809526` 为 in_progress，VPN arbiter `42107810109` 为 queued。尚无本次修复后完整通过结果，不能标记 CI 通过。
- 既有证据：此前某次 FX VPN/DNS runtime workflow 的 18/18 子回归和后续 Root Proxy/native VPN 集成步骤成功；该结果只适用于当时 runner 下载并应用 patch 的 Release 模块快照，不代表当前 HEAD 的整包或真机验证。
- 未执行：Android Gradle/APK 构建、KernelSU ZIP 最终打包、OnePlus 12 真机 VPN/TUN/DNS 共存与 SELinux/PackageManager 测试。
