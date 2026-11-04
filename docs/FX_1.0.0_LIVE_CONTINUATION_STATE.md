# FX 1.0.0 — 实时开发续接状态

> 本文件是跨窗口的当前任务状态入口。每完成一个有意义的页面/功能批次，都应在同批代码提交中更新本文件。旧聊天和旧 SHA 不得覆盖这里的新状态。

## 当前仓库状态（2026-11-05，Asia/Tokyo）

- Repository：`vip-svip/SY`
- Branch：`fx-v1.0.0-unified-hook-integration`
- 本批功能基线 HEAD：`6d69cd05c993d041fbebe6ea85d04aeb0eb4ba1a`
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
