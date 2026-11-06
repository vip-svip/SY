

### FX 模块应用白名单批量事务 AWK 分区匹配修正（2026-11-07）

- 代码提交：`3a5ef228a9aa6ac960990fd5626842b79023e7d0`。
- 文件：`fx-module/scripts/yulong-app-whitelist.sh`。
- 删除批量白名单事务 AWK 程序中残留的旧 section 匹配行，避免与新匹配条件叠加形成不完整的 AWK 模式/动作块。
- 保留模块版批量添加/移除、PackageManager 过期项清理、锁、配置快照与失败回滚实现；未将较短的规范脚本覆盖模块版。
- 按用户要求未执行白名单脚本、测试、静态检查、构建、CI 或设备验证。

### FX Unbound 私有状态目录权限失败关闭（2026-11-07）

- 代码提交：`2f5b0ef5996ace336f12e72002c7660f8bdf0177`。
- 文件：`fx-module/scripts/unbound.sh`。
- `_prepare_state_dirs()` 不再忽略 `chmod 700` 失败；无法确保 Unbound 状态目录与工作目录为私有权限时，立即中止启动并给出明确错误。
- 避免在目录权限未收紧的情况下继续使用可能包含解析器状态与缓存数据的目录；原有路径符号链接检查、运行文件 SHA-256 校验和健康探测逻辑不变。
- 按用户要求未执行 Unbound 脚本、测试、静态检查、构建、CI 或设备验证。


### FX 模块应用白名单批量事务 Shell 续行修正（2026-11-07）

- 代码提交：`40a63fd20d7b40a8709bfaa2e6c7c7419f267fe3`。
- 文件：`fx-module/scripts/yulong-app-whitelist.sh`。
- 修正批量添加/移除与过期项清理事务中的四处多重行尾反斜杠，将 Shell 命令续行恢复为单个反斜杠，避免续行符被转义后导致后续 `&&` 条件链脱离原命令。
- 保留现有批量名单写入、PackageManager 快照校验、锁内事务、配置备份与 apply 失败回滚实现。
- 按用户要求未运行脚本、测试、静态检查、构建、CI 或设备验证。


### FX 模块应用防火墙 UID 在事务锁内二次核验（2026-11-07）

- 代码提交：`b475885e4694aab1de44d1c965afdf26d9768e76`。
- 文件：`fx-module/scripts/yulong-app-firewall.sh`。
- 在 `mutate_transaction()` 已取得防火墙配置锁后，对 `set_item_value` 与 `set_rule_value` 再次读取 PackageManager UID 快照并核对包名/UID。
- CLI 入锁前校验仍作为快速拒绝；锁内复核消除等待锁期间应用卸载或 UID 变化导致陈旧 UID 写入配置的窗口。其他事务操作不受影响。
- 按用户要求未运行脚本、测试、静态检查、构建、CI 或设备验证。


### FX 模块 DNS reconcile 与设置写入统一串行化（2026-11-07）

- 代码提交：`e331d1383af6ecaa34bb68915125aee6e4e733f1`。
- 文件：`fx-module/scripts/native-dns-settings.sh`。
- 将 `reconcile` 从无锁直接调用改为通过既有 `with_lock` 执行 `reconcile_locked`，使完整 DNS 服务协调与 `set` / `set-many` 设置事务共用同一把锁。
- 避免用户触发的重新协调与并发设置写入交错执行，减少旧配置运行态覆盖新配置的竞态窗口；状态输出仍在协调成功后返回。
- 按用户要求未运行脚本、测试、静态检查、构建、CI 或设备验证。


### FX AdGuard Home 私有状态目录权限失败关闭（2026-11-07）

- 代码提交：`ebebf3e26999f90913452462d6e7b2b2cd916eb8`。
- 文件：`fx-module/scripts/adguardhome.sh`。
- 将状态目录与工作目录的 `chmod 700` 从忽略失败改为失败关闭；无法收紧目录权限时，停止后续配置渲染和服务启动并报告错误。
- 与 Unbound 对应的私有目录保护保持一致，避免在权限未能收紧时继续使用包含 DNS 配置、缓存和运行状态的目录。
- 按用户要求未运行 AdGuard Home 脚本、测试、静态检查、构建、CI 或设备验证。


### FX Unbound 配置文件私有权限依赖安全暂存（2026-11-07）

- 代码提交：`05ca5a85220ddba33641d67dd10f9d9293762072`。
- 文件：`fx-module/scripts/unbound.sh`。
- 移除配置原子替换后重复执行且忽略失败的 `chmod 600`；配置文件在写入前已由 `_new_private_temp()` 使用 `umask 077` 创建并强制设置为 600，原子重命名会保留该权限。
- 避免权限设置失败被静默忽略，同时不引入配置文件删除/重建窗口。AdGuard Home 对应路径已采用明确失败返回，无需重复修改。
- 按用户要求未运行脚本、测试、静态检查、构建、CI 或设备验证。


### FX AdGuard Home 配置原子发布保留私有权限（2026-11-07）

- 代码提交：`bc1a02c2328206d22c285dc3d0a824fbf1c06867`。
- 文件：`fx-module/scripts/adguardhome.sh`。
- 移除配置文件原子重命名发布后的重复 `chmod 600`；渲染文件由 `_new_private_temp()` 在发布前通过 `umask 077` 创建并强制设为 600，原子重命名保留其权限。
- 避免配置已发布后因冗余权限命令失败而使启动流程报错，同时不增加配置删除/重建窗口。
- 按用户要求未运行 AdGuard Home 脚本、测试、静态检查、构建、CI 或设备验证。


### FX AdGuard Home 停止前复核进程归属（2026-11-07）

- 代码提交：`869b84830f98f16401b4ad8b0466ac05d6ecec28`。
- 文件：`fx-module/scripts/adguardhome.sh`。
- 在发送 TERM 前再次通过 `_owned_pid()` 核对 PID 对应的进程命令行；若进程归属已变化或进程已退出，则拒绝发送信号并保留后续状态清理流程。
- 与 Unbound 停止路径采用相同的信号前归属复核，缩小 PID 退出并被系统复用时误向其他进程发送 TERM 的竞态窗口。
- 按用户要求未运行脚本、测试、静态检查、构建、CI 或设备验证。


### FX 应用白名单锁释放前复核目录与 PID 所有权（2026-11-07）

- 代码提交：`bec8bfca539d204e7bcabe0e32d99a4d773d042c`。
- 文件：`fx-module/scripts/yulong-app-whitelist.sh`。
- 锁清理函数不再无条件删除 `LOCK/pid` 并尝试移除锁目录；现在先确认锁路径仍是非符号链接目录、PID 文件仍是普通文件且记录仍等于当前事务 shell 的 PID。
- 若锁路径在事务期间被替换或所有权记录改变，清理函数不会触碰新锁，避免旧事务退出时误删其他操作持有的锁。
- 按用户要求未运行白名单脚本、测试、静态检查、构建、CI 或设备验证。


### FX 模块应用防火墙配置与规则列表严格解析同步（2026-11-07）

- 代码提交：`551017fa75ed0d4b47e11a1752cf82a208d2fd02`。
- 文件：`fx-module/scripts/yulong-app-firewall.sh`。
- 将规范脚本中更严格的 `read_master()` 与 `list_rows()` 校验移植到模块副本：主开关配置必须恰有一个合法 section 和一个合法 enabled 值；规则列表拒绝重复 section、重复包名、无效包名/UID、非法状态位及不完整的时间/策略字段。
- 不再静默跳过损坏规则行，避免 UI 将不完整列表误认为有效配置；保留模块版 UID 快照校验、锁内二次核验、事务锁和回滚实现。
- 按用户要求未运行脚本、测试、静态检查、构建、CI 或设备验证。


### FX 应用白名单批量请求重复包名拒绝（2026-11-07）

- 代码提交：`575a3605715bbc4e62081fa18ff73266af92d184`。
- 文件：`fx-module/scripts/yulong-app-whitelist.sh`。
- 批量添加/移除在暂存包名列表时即检查重复项；发现重复包名立即清理私有暂存文件并拒绝整个请求，避免请求数量与实际唯一目标数不一致，也避免重复参数掩盖调用端错误。
- 保留原有批量事务锁、配置备份、原子发布及 apply 失败回滚。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX 应用白名单列表读取失败关闭（2026-11-07）

- 代码提交：`a026844017c677a31ca34fb75dc8ee73bc488335`。
- 文件：`fx-module/scripts/yulong-app-whitelist.sh`。
- 将白名单读取由宽松过滤改为完整性校验：必须恰有一个白名单区段；有效行必须包含三个字段、合法包名、非空显示名和 0/1 状态；重复包名或损坏行会使整份列表读取失败。
- 先在 AWK 内暂存全部行，只有整体校验通过才输出，避免 UI 收到部分名单并误以为其完整。
- 保留现有批量事务、重复输入拒绝、锁所有权校验和失败回滚。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX Hosts/Ad 托管名单读取完整性校验（2026-11-07）

- 代码提交：`63729b6b05f014455d18ec00d7440e02347134b1`。
- 文件：`fx-module/scripts/native-managed-lists.sh`。
- 列表读取不再静默忽略损坏记录：校验字段数量、值/备注长度、控制字符、启用状态和名单类型对应的 URL/域名格式。
- 同一名单中的重复值现在使整次读取失败；域名名单按大小写不敏感去重，规则 URL 保持精确匹配。
- 保留旧配置兼容：允许两字段记录（默认启用）及历史重复 section，避免破坏既有配置迁移。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 设置锁崩溃恢复与所有权保护（2026-11-07）

- 代码提交：`5ff844686451963dacce99502c90af5f0902ad34`。
- 文件：`fx-module/scripts/native-dns-settings.sh`。
- DNS 设置锁新增 PID 所有者验证、双重存活检查和陈旧锁原子隔离回收；仅在锁目录和 owner 文件身份复核通过、且原持有进程确实不存在时清理。
- 正常释放时先将锁目录原子改名，再复核 owner 后删除，避免旧事务误删被替换的新锁。
- 锁等待次数支持受限配置（默认 20 次，最大 120 次）；无法验证 owner 的旧锁继续失败关闭，不自动删除。
- 原有 DNS 设置事务、依赖归一化、回滚和 reconcile 共用锁行为保留。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX 隐私设置应用失败自动回滚（2026-11-07）

- 代码提交：`30f3a9691a78d6b6fdbfe1473514ee93bcebdfcf`。
- 文件：`fx-module/scripts/native-privacy-settings.sh`。
- 隐私开关写入前创建私有配置快照；设置写入成功但 `apply.sh fast` 失败时，原子恢复旧配置并重新应用旧状态。
- 回滚暂存或发布失败时保留原始备份并返回独立错误码，不再把未生效的新设置留在配置中却只报告 `applied=0`。
- 正常应用成功后删除快照；原有 allowlist、事务标记检查及配置路径保护保留。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX AdGuard Home PID 标记并发替换保护（2026-11-07）

- 代码提交：`95007f43023adf1c1f9173d5a00a40cd44675ed2`。
- 文件：`fx-module/scripts/adguardhome.sh`。
- 清理旧 PID 标记时不再执行“读取后直接 rm”；先将标记原子改名隔离，再核对隔离文件内容是否仍属于当前生命周期操作。
- 若并发启动已替换 PID 标记，旧操作不会删除新标记；发现隔离文件内容不匹配时，在目标路径空闲的前提下恢复原文件。
- 保留符号链接/非普通文件拒绝、PID 内容匹配和现有进程身份复核。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX 原生 VPN 配置拒绝重复区段与歧义键（2026-11-07）

- 代码提交：`919819c916bee64b492103b986e0a705546989f3`。
- 文件：`fx-module/scripts/native-vpn-config.sh`。
- 新增配置结构完整性门槛：`[conf:vpn]` 必须恰好出现一次；区段内键名必须合法且唯一；每条有效配置必须含值字段，值不得包含控制字符、分隔符或超过长度上限。
- `list`、`get` 和 `set` 在读取/修改前统一执行结构校验，发现重复键或重复 VPN 区段时拒绝继续，避免 UI 读到最后一个值而写入时只更新其中一条。
- 不改变现有合法键白名单、字段值范围校验、原子写入和 apply 失败回滚。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 默认开关声明唯一性校验（2026-11-07）

- 代码提交：`6b123cca453887e7e03c703ceda3ce1fc60e4b7f`。
- 文件：`fx-module/scripts/native-dns-settings.sh`。
- `declared_flag()` 不再以“找到任意一个合法值”作为默认项有效依据；目标 DNS 开关必须在默认配置首个 section 之前恰好声明一次，且该行必须严格为单一字段键值、值为 0/1。
- 缺失、重复或格式错误的默认声明均拒绝该开关变更，避免默认配置歧义被错误地当成合法 DNS 能力声明。
- 未改变 DNS 开关依赖归一化、批量事务、锁和失败回滚。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX AdGuard Home DNS 规则渲染改为严格托管名单读取（2026-11-07）

- 代码提交：`c27f74112852562bdfee5b213269aac4c0a62918`。
- 文件：`fx-module/scripts/adguardhome.sh`。
- AdGuard Home 生成用户白名单/黑名单时，不再直接扫描 settings.conf 并静默跳过格式错误记录；改为调用原生 `native-managed-lists.sh list domainList/blockList` 严格读取器。
- 复用该读取器的字段数量、域名格式、备注/控制字符、启用位及重复值校验；任一名单损坏或读取失败时，整个 DNS 规则渲染失败关闭，不发布只包含部分名单的配置。
- 对读取器输出再次检查协议头、行字段数、索引和启用位后才生成 AdGuard 规则；原有规则去重、私有临时文件及原子发布路径保留。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX AdGuard Home 内置 Yulong 订阅状态严格读取（2026-11-07）

- 代码提交：`14eff993de80ea63e725a14994a2445aae2c3f0c`。
- 文件：`fx-module/scripts/adguardhome.sh`。
- 生成 DNS 用户规则前，内置 Yulong 广告域名订阅的启用状态改由 `native-managed-lists.sh list ruleList` 读取，不再直接宽松扫描 settings.conf。
- 复用订阅名单的字段、URL、启用位及重复值校验；损坏或重复订阅记录使本次规则渲染失败关闭，避免因静默忽略歧义配置而误判内置规则开关。
- 保留原有订阅文件优先级、缺失文件回退和规则源隔离行为。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX Unbound PID 标记并发替换保护（2026-11-07）

- 代码提交：`22957d6d562d80c7f87a785b9e54d6c74961246f`。
- 文件：`fx-module/scripts/unbound.sh`。
- 停止/清理递归 DNS 进程时，不再采用“读取 PID 后直接删除标记”的方式；先原子改名隔离，再复核隔离文件内容和文件类型后删除。
- 若并发启动在隔离后发布了新的 PID 标记，旧停止操作不会删除新标记；隔离内容不匹配时，仅在目标路径仍空闲的情况下尝试恢复。
- 与 AdGuard Home 生命周期脚本采用一致的并发保护策略，保留原有进程 argv 身份验证和 TERM/KILL 前复核。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 状态页订阅计数改为严格名单来源（2026-11-07）

- 代码提交：`1eaf7d8ec3464c226680c2915b9b0e87f682cf0b`。
- 文件：`fx-module/scripts/native-dns-settings.sh`。
- DNS 状态不再通过宽松 AWK 扫描 settings.conf 并静默忽略无效订阅行来显示过滤源总数/启用数。
- 改为读取 `native-managed-lists.sh list ruleList` 的完整校验结果；仅在协议头、字段数、索引及启用位均有效时输出计数。
- 名单损坏、读取器不可用或输出格式异常时，两个计数均显示 `unknown`，不再呈现可能误导用户的部分统计。
- 未改变订阅数据、DNS 开关、运行服务和规则渲染行为。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX Root Proxy 白名单策略严格解析（2026-11-07）

- 代码提交：`0747fa9830e4e7bc98ce6fac53ce4e39b0a8be0b`。
- 文件：`fx-module/scripts/yulong-root-proxy.sh`。
- Root Proxy 不再静默跳过格式错误的白名单行；现在要求白名单区段唯一，记录必须恰好包含合法包名与 0/1 启用位。
- 重复包名、重复区段、字段缺失/多余或非法状态位均使整个白名单读取失败，避免只应用部分 UID 策略。
- 保留未启用条目、注释和空行的兼容处理；有效启用项仍按原顺序解析。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX Root Proxy PackageManager 快照完整性门槛（2026-11-07）

- 代码提交：`587cbfdf80e24af3ec0bedb75fb19ef13ba495b4`。
- 文件：`fx-module/scripts/yulong-root-proxy-package-watch.sh`。
- 包监视器不再从 PackageManager 输出中静默筛选合法行后，将不完整结果写成新的快照基线。
- 每条非空记录必须恰好包含合法包名和非零数字 UID；畸形行、重复包名、空快照均使本轮快照失败。
- 快照失败时保留上一次成功快照，不触发基于部分数据的 Root Proxy 白名单/路由协调；后续轮询继续重试。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX Root Proxy PackageManager 快照解析修正（2026-11-07）

- 修正提交：`42bcf8813a6c72a2717baf1c5915a324f24bc99a`。
- 文件：`fx-module/scripts/yulong-root-proxy-package-watch.sh`。
- 修正新增解析器的 Shell/awk 转义，恢复逐行分隔与标准空白字符匹配。
- 保留整份快照完整性门槛；本轮未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 原生状态页补齐 Root Proxy 运行诊断字段（2026-11-07）

- 代码提交：`d2c5ef5c6b4d3a6ae708a4f08b64a6c1b147aaca`。
- 文件：`fx-module/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java`。
- DNS 运行状态页新增显示 AdGuard Home/Unbound 与第三方 VPN 兼容开关、Root Proxy 原因及清理状态、VPN 接口/UID/出口 IPv4、启动时间、DNS 重定向、DNS/路由探测、Android 私有 DNS 模式和 Root Proxy 白名单数量。
- 字段直接来自原生 DNS 状态命令的既有键值，不新增网络操作或更改 DNS/VPN 配置行为。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 运行状态响应结构完整性校验（2026-11-07）

- 代码提交：`cf611ced1d65f47894d24f38f088d903f47541e6`。
- 文件：`fx-module/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java`。
- DNS 运行状态页现在要求响应头为 `FXDNS1`，并校验完整的已知字段集合；缺少字段、未知字段、重复字段、空值记录或格式错误均拒绝渲染部分状态，改为显示明确错误。
- 避免脚本输出截断或格式异常时，界面把部分状态误显示为完整运行状态；不改变服务或路由。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 引擎就绪原因诊断（2026-11-07）

- 后端提交：`7ecd727de246d067319f0a39ae876694d53b267c`，文件 `fx-module/scripts/native-dns-settings.sh`。
- UI 提交：`a4dc79065e0b0558adaa3a7c31dca1da2c7adfe1`，文件 `fx-module/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java`。
- DNS 状态响应新增 `dns_stack_readiness_reason`：区分 `disabled`、`ready`、Unbound 不可用/未启用，以及 AdGuard Home 不可用等状态。
- 原生 DNS 状态页展示该原因，便于区分配置未启用和服务未就绪；未更改 DNS 引擎启停、上游或路由策略。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 定向缓存刷新命令参数修正（2026-11-07）

- 代码提交：`42287d27362cfe81aeda368fd46e998f8dcccd64`。
- 文件：`fx-module/scripts/yulong-ad-control.sh`。
- 修正 `cache-flush` 命令分发：允许可选的目标参数，并将 `adguardhome`、`unbound` 或 `all` 传入既有缓存刷新事务。
- 修复原分发器只接受一个参数且始终调用默认 `all` 的问题；此前 UI 发出的定向刷新命令会被拒绝，现可进入既有的指定引擎停止、重启和路由协调流程。
- 未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 查询日志清理路径与并发保护（2026-11-07）

- 代码提交：`313cfbb35657053bdbd3c69514baedc0dda5f62c`。
- 文件：`fx-module/scripts/yulong-ad-control.sh`。
- 将查询日志清理改为通过既有控制事务锁执行，避免与同一控制器的并发操作交错。
- 清理前逐级检查日志目录路径组件，拒绝符号链接目录；预先检查主日志和全部轮转日志，拒绝符号链接及非普通文件，再执行清理。
- 权限收紧失败现在返回错误，不再静默忽略；清理结果报告实际文件数。
- 按要求未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 查询日志读取与清理事务串行化（2026-11-07）

- 代码提交：`669763698dcde8fcee1619d52bad513bd8725237`。
- 文件：`fx-module/scripts/yulong-ad-control.sh`。
- 将 DNS 查询日志统计和最近 500 行读取也纳入既有控制事务锁，与查询日志清理共享同一把锁，避免 FX 控制入口的读取和清理交错。
- 查询日志尾部读取增加日志目录及目标文件符号链接拒绝检查，并校验普通文件类型。
- 查询日志统计仍调用原有隐私聚合器，不输出域名或客户端 IP。
- 按要求未运行测试、静态检查、构建、CI 或设备验证。


### FX AdGuard Home 查询日志保留期限严格解析（2026-11-07）

- 代码提交：`8fd905e4586da57074c6421b45397a0bbd5ae89a`。
- 文件：`fx-module/scripts/adguardhome.sh`。
- 配置渲染时严格读取查询日志保留期限：只接受单一区段、单一 `interval` 键及 `1d/3d/7d/30d` 值。
- 对重复区段、重复键、未知字段、缺失键或非法值拒绝渲染，不再静默回退到 7 天并掩盖损坏配置。
- 完全缺少该历史配置区段时仍兼容默认 7 天。
- 按要求未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 查询日志保留期限读写一致性加固（2026-11-07）

- 代码提交：`debfc569748f0683cd9c923473d133425a5516f4`。
- 文件：`fx-module/scripts/yulong-ad-control.sh`。
- 保留期限读取改为严格解析：重复区段、重复键、未知字段或非法值返回 `unknown`，不再伪装成默认 7 天。
- 保留期限写入前先验证现有配置；拒绝重复区段、重复键和未知内容，避免修改时静默合并或丢弃歧义配置。
- 对缺失整个历史配置区段继续兼容默认 7 天；写入时仍使用私有暂存文件和原子替换。
- 按要求未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 拦截响应模式严格读写与配置渲染（2026-11-07）

- 控制器代码提交：`110b0058bc351306684dd0f4219316801af649fa`。
- AdGuard Home 代码提交：`6bb218c9990902d8859fb1c2eaa3d55f05f03018`。
- 文件：`fx-module/scripts/yulong-ad-control.sh`、`fx-module/scripts/adguardhome.sh`。
- DNS 响应模式仅接受 `nxdomain`、`refused`、`custom_ip`；读取、写入和 AdGuard Home 配置渲染统一拒绝重复区段、重复键、缺失键、未知字段及非法值。
- 完全缺少历史配置区段时仍使用兼容默认 `nxdomain`；已有但损坏的配置不再静默降级并掩盖问题。
- 按要求未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 上游服务器配置写入前完整性保护（2026-11-07）

- 代码提交：`80bad0be92bd2fadd2dfb978b3ba4889cf480c5c`。
- 文件：`fx-module/scripts/yulong-ad-control.sh`。
- DNS 服务器区段写入前先检查现有配置：拒绝重复区段、重复服务器、未知字段、畸形 nameserver 记录及超过三条的名单。
- 按区段分别复用现有端点校验：`custom_dns` 支持既有 IPv4/DoH/DoT/DoQ 格式；`global_dns` 与 `yulong_dns_fallback` 只接受既有 IPv4 DNS 格式。
- 限定可写入的 DNS 区段名称，避免内部写入函数被错误区段参数调用。
- 仅在现有区段完整合法时才进入原子配置替换流程，避免把损坏配置静默覆盖。
- 按要求未运行测试、静态检查、构建、CI 或设备验证。


### FX VPN DNS 参数写入前配置完整性保护（2026-11-07）

- 代码提交：`0a581d7cbdac1695ba91b2db70b88f8ea9fb6611`。
- 文件：`fx-module/scripts/yulong-ad-control.sh`。
- 修改 `remote_dns` / `cn_dns` 前，先校验现有 `[conf:vpn]` 区段。
- 拒绝重复 VPN 区段、重复目标键、畸形 IPv4 值及不合法目标键名；不再静默覆盖歧义配置。
- 写入值继续要求 IPv4 字面量，并保留原有私有暂存文件和原子替换路径。
- 按要求未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 配置快照导出完整性门槛（2026-11-07）

- 代码提交：`51af075a888728696a16c643216a40003773305a`。
- 文件：`fx-module/scripts/yulong-ad-control.sh`。
- DNS 配置快照导出前，统一校验自定义/全局/备用 DNS 名单区段、VPN DNS 区段及拦截响应模式区段。
- 任一名单存在重复区段、重复服务器、未知字段、畸形记录或非法端点，VPN DNS 有重复目标键/非法 IPv4，或响应模式配置存在歧义时，拒绝导出整份快照。
- 响应模式读取改为使用已校验区段的首个有效键，不再对异常配置静默降级成 `nxdomain`。
- 按要求未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 过滤源状态计数换行格式修正（2026-11-07）

- 代码提交：`9f33a5d39be2ff3316a8f2cc2f38fe65e4b9a389`。
- 文件：`fx-module/scripts/native-dns-settings.sh`。
- 修正状态页过滤源统计管道中被双重转义的换行格式：输入记录按真实行分隔交给 AWK，统计结果也以真实换行结束。
- 避免把字面量反斜杠和 n 当作记录分隔符，导致过滤源总数/启用数统计解析异常。
- 按要求未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 配置快照恢复预览（2026-11-07）

- 代码提交：`01cddc9dbd1da1d9b024cf6234c5901efa7e3297`。
- 文件：`fx-module/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java`。
- 恢复前先在原生界面展示快照字段完整度、12 个开关的启用数量、三组 DNS 上游条数、VPN DNS 地址和拦截响应模式。
- 本地预览拒绝未知字段、重复字段、缺失字段及畸形记录；用户确认后仍由 Root 后端执行完整语义校验和原有事务回滚，预览不替代后端验证。
- 按要求未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 配置快照恢复预览语义校验（2026-11-07）

- 代码提交：`bb63c024862034f421fde440d472ac797189f7c6`。
- 文件：`fx-module/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java`。
- 在 DNS 快照确认前，原生界面增加 12 个开关的 0/1 校验、VPN DNS IPv4 校验、响应模式枚举校验，以及三组上游的数量、格式和重复项校验。
- 自定义上游按后端现有格式接受 IPv4、HTTPS DoH、TLS DoT、QUIC DoQ；全局和备用上游只接受 IPv4。后端仍执行最终权威校验。
- 按要求未运行测试、静态检查、构建、CI 或设备验证。


### FX GKD 本地规则导入元数据严格校验（2026-11-07）

- 代码提交：`b5afea0ef742edc593ecf2780c10a3cd3e07882a`。
- 文件：`fx-module/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdRuleStore.kt`。
- 导入规则时，严格校验动作类型、分组名称和排除选择器；非法动作不再静默降级为 click，非法排除选择器不再被清空后导入。
- 保留包名/已安装用户应用、主选择器语法、冷却时间、重复规则及 500 条上限校验；所有导入规则仍强制禁用，必须由用户在本机审阅后启用。
- 按要求未运行测试、静态检查、构建、CI 或设备验证。


### FX GKD 本地持久规则整份失败关闭（2026-11-07）

- 代码提交：`fb18540b72099e117d078c49169025944ee396a5`。
- 文件：`fx-module/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdRuleStore.kt`。
- 本地规则读取改为整份文档校验：超过 500 条、非对象记录、重复 ID、非法包名/选择器、冷却时间越界、非布尔启用位、未知动作、空/超长分组或非法排除选择器，均使整份规则读取失败关闭，不再跳过坏行后继续执行剩余规则。
- 保留旧格式兼容：历史记录缺少 cooldown/action/group/exclude_selector/enabled 时仍使用既有默认值；新增字段若存在但类型错误则拒绝整份文档。
- 按要求未运行测试、静态检查、构建、CI 或设备验证。


### FX GKD 无障碍控件树截断时停止自动化（2026-11-07）

- 代码提交：`704ddc82b14570d1d4355da7e309241510cd6064`。
- 文件：`fx-module/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdAccessibilitySnapshot.kt`。
- 控件树超过最大深度、节点数或单节点子节点上限时，快照标记为不完整并整体丢弃；运行时不会基于被截断的局部控件树执行点击/长按。
- 仍保留既有节点数、深度、子节点数上限及节点回收机制；完整快照才交给选择器匹配。
- 按要求未运行测试、静态检查、构建、CI 或设备验证。


### FX GKD 无障碍子节点遍历失败关闭（2026-11-07）

- 代码提交：`0b0b40b8d340f79571b38ee24e67cb7bc6d7e7bc`。
- 文件：`fx-module/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdAccessibilitySnapshot.kt`。
- 平台报告存在子节点但读取子节点失败、返回空节点，或子节点数量读取异常时，均将快照标记为不完整并丢弃整份树。
- 避免在 Android 无障碍节点瞬时失效时，把只遍历到的控件树前缀交给自动化规则执行。
- 按要求未运行测试、静态检查、构建、CI 或设备验证。


### FX GKD 无障碍服务中断时暂停自动化（2026-11-07）

- 服务提交：`d5db5af904f0b04fc663e0c7646a12fce267ff46`（`FxAccessibilityService.java`）。
- 运行时提交：`112486dfb55826d3b6e28ce443073a0093644d52`（`FxGkdAutomationRuntime.kt`）。
- Android 调用 `onInterrupt()` 时，立即将 GKD 标记为不可用、清空待处理目标并移除主线程待执行任务；服务重新连接后才恢复可用状态。
- 自动化运行入口及真正执行点击/长按前均检查 GKD 专用可用状态，避免服务已被系统中断但静态连接标记仍为 true 时继续执行规则。
- 服务销毁时同样保持中断状态，直到下一次重新连接。
- 按要求未运行测试、静态检查、构建、CI 或设备验证。


### FX Unbound DNSSEC 信任锚刷新回滚失败关闭（2026-11-07）

- 代码提交：`b8f3d613bf071d47be0eb457bda1881d5661972e`。
- 文件：`fx-module/scripts/unbound.sh`。
- 修正 RFC5011 信任锚刷新后发现输出无效时的回滚处理：不再在原子恢复失败后静默继续并删除唯一的旧锚副本。
- 旧信任锚恢复失败时保留私有恢复副本并让刷新函数返回失败；Unbound 启动流程检查该结果，拒绝启动，避免使用未经验证的新锚继续递归解析。
- 正常刷新结果仍按原流程保留；无须刷新或网络不可用的既有路径不变。
- 按要求未运行测试、静态检查、构建、CI 或设备验证。


### FX AdGuard Home 启用的 Yulong DNS 订阅缺失时拒绝部分渲染（2026-11-07）

- 代码提交：`428bb87c8d0a3b11e506f8673d3f7a7f7f507bbe`。
- 文件：`fx-module/scripts/adguardhome.sh`。
- 当内置 Yulong 广告域名订阅已启用，但用户数据目录和模块内置目录均无法提供安全、可读且非空的规则文件时，拒绝生成部分 DNS 规则配置。
- 修正此前仅记录日志后继续渲染其他规则的行为，避免界面显示订阅启用、实际却静默漏掉该规则源。
- 未启用该订阅时不要求其规则文件存在；其余名单隔离、严格解析和原子配置发布路径保持不变。
- 按要求未运行测试、静态检查、构建、CI 或设备验证。


### FX GKD 本地规则导入严格 UTF-8 解码（2026-11-07）

- 代码提交：`293dfe4f5ac355f05dd976be2cc3d25be649147b`。
- 文件：`fx-module/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdAutomationActivity.java`。
- 将 SAF 导入规则文件的 UTF-8 解码改为严格解码器，遇到非法或不完整字节序列时直接拒绝导入，不再由 `new String()` 静默替换为 U+FFFD 后继续解析。
- 兼容可选 UTF-8 BOM；原有 1 MiB 读取上限、规则完整性校验和导入后默认禁用行为保持不变。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX GKD 分组/批量启用与总开关原子同步（2026-11-07）

- 代码提交：`0cb97b87a6a55c4e794ec68059199b7be8ed27b6`。
- 文件：`fx-module/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdRuleStore.kt`。
- 分组启用和选中规则批量启用现在在同一次 SharedPreferences 提交中同步更新规则 JSON 与 GKD 总开关，避免规则已启用但总开关仍关闭、界面回报失败的双阶段不一致。
- 批量禁用不影响其他已启用规则；当整份规则均已禁用时，写入逻辑仍自动关闭总开关。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX GKD 中断/总开关关闭时阻断排队扫描（2026-11-07）

- 代码提交：`c98d6a045490512f30c6f1fd1e71b98ec8cb0808`。
- 文件：`fx-module/adhook/app/src/main/java/de/privacyguard/adhook/FxAccessibilityService.java`。
- `startGkdScan()` 入口现在先检查无障碍服务中断状态和 GKD 总开关；若服务刚中断或用户刚关闭总开关，清空待处理目标并停止，不再获取活动窗口根节点或提交后台扫描任务。
- 这是对已排队主线程任务与中断/关闭操作之间竞态的补强；运行时原有执行前检查仍保留。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX GKD 单条规则启用与总开关同步（2026-11-07）

- 代码提交：`ce3614647ce0bdf88c6c65d50ad584ef96a34103`。
- 文件：`fx-module/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdRuleStore.kt`。
- `setRuleEnabled()` 在启用单条规则时，将 GKD 总开关与规则 JSON 放入同一次 SharedPreferences 提交；禁用单条规则时保留其他规则及总开关状态，最后一条启用规则关闭时仍由统一写入逻辑关闭总开关。
- 修复单条规则已启用但总开关仍关闭，导致自动化不执行的状态不一致。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX GKD 每应用扫描节流状态上限（2026-11-07）

- 代码提交：`99697c0d12105d577179c27e947db798180a56b6`。
- 文件：`fx-module/adhook/app/src/main/java/de/privacyguard/adhook/FxGkdPackageScanThrottle.kt`。
- 每应用扫描冷却记录改为按插入顺序维护，并限制最多 500 个包名；新包名到达上限时淘汰最早记录，避免异常或大量瞬时包名事件令服务内存状态无界增长。
- 原有按包名隔离冷却、规则包名变更时清理记录、规则失效时清空记录的行为保持不变。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX Dia Frida 脚本库统一 500 条容量限制（2026-11-07）

- 代码提交：`27d9b5fd790aa01f319f9a3b52be05bdb78ac5e7`。
- 文件：`fx-module/adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaScriptLibraryStore.java`。
- 将 500 条上限统一到共享 `validateScripts()`：本地读取、保存、重命名、批量删除写入及导入合并都会经过同一容量门槛。
- 超限脚本库拒绝写入/导入，修复复制入口限制 500 条、其他写入入口却可继续增加的策略不一致。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX 本地递归 DNS 健康探测支持 UDP 截断后的 TCP 重试（2026-11-07）

- 代码提交：`ab60159e9b6c979bec5503df767cc5f897d4cd52`。
- 文件：`fx-module/scripts/localdns-probe.c`。
- UDP 探测响应带 TC 截断标志时，探测器改用同一 IPv4 loopback 端点执行 DNS-over-TCP 长度前缀请求，并按声明长度完整读取响应。
- TCP 重试保留发送/接收超时、响应长度边界及后续原有事务 ID、问题区、递归可用性和 RCODE 校验；TCP 失败或响应畸形仍判定探测失败。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX GKD 扫描队列代际隔离，阻止旧任务释放新任务（2026-11-07）

- 代码提交：`c884cd17af8d1a5580f562d0ed26ee0d4f132810`。
- 文件：`FxGkdPendingPackageScan.kt`、`FxAccessibilityService.java`、`FxGkdPendingPackageScanTest.kt`。
- 每次 GKD 扫描分配单调递增 generation；完成回调必须匹配当前活动 generation，旧扫描在服务中断、规则重配置或队列清空后迟到完成时，不能清除或推进新一轮扫描。
- 主线程排队的旧扫描在获取窗口节点前、后台执行前再次确认 generation；失效请求不会处理过期窗口节点。
- 同一包名重复事件不再把相同包名重新排入待处理槽；再次回到当前正在扫描的包时，清除其他过期待处理目标。
- 增加针对 clear 后旧完成回调、活动包重复事件的单元测试源码；按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX 本地递归 DNS 探测的 TCP 建连超时边界（2026-11-07）

- 代码提交：`73b8d182851fff947d82ed7d291b8312773c5f73`。
- 文件：`fx-module/scripts/localdns-probe.c`。
- UDP 响应带 TC 标志后进入 TCP 重试时，TCP connect 改为非阻塞建连并通过 poll 等待可写结果；等待上限沿用探测器传入的超时秒数。
- 连接就绪后读取 `SO_ERROR` 确认真实建连结果，再恢复阻塞模式继续既有长度前缀 DNS 请求/响应流程；超时、连接错误或恢复标志失败均关闭 socket 并判定探测失败。
- 修复 TCP 重试阶段 connect 可能受内核 SYN 重试拖延、超出探测器配置超时的问题；UDP 探测和 DNS 响应校验行为未改变。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX 本地递归 DNS TCP 探测采用整段事务总超时（2026-11-07）

- 代码提交：`a89e20b3758a5b2d0da65358fe3cd43a9c4477bf`。
- 文件：`fx-module/scripts/localdns-probe.c`。
- TCP 重试在开始时建立单一 CLOCK_MONOTONIC 截止时间，连接、发送 DNS 长度前缀及查询、读取响应长度和响应正文共同消耗同一超时预算。
- TCP socket 全程非阻塞；poll 等待可读/可写时按截止时间计算剩余毫秒，EINTR 重试不会重置预算，EAGAIN/EWOULDBLOCK 则等待对应 I/O 就绪。
- 防止对端持续分片发送数据、让每次 recv 都在单次 socket 超时内返回，从而无限延长整个 DNS 探测事务。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX 本地递归 DNS UDP 探测发送超时边界（2026-11-07）

- 代码提交：`9ebe0f5090675a97015a673255c4d450ab311fd5`。
- 文件：`fx-module/scripts/localdns-probe.c`。
- UDP 健康探测 socket 同时设置 `SO_RCVTIMEO` 与 `SO_SNDTIMEO`，发送与接收阶段均使用传入的 1–10 秒超时配置。
- 避免只约束响应接收、却未给 UDP 查询发送设置内核超时的单边超时配置。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX 本地递归 DNS TCP 探测写入防 SIGPIPE（2026-11-07）

- 代码提交：`f88c092316a470b92696de4c832c9115185d670e`。
- 文件：`fx-module/scripts/localdns-probe.c`。
- DNS-over-TCP 请求帧发送使用 `MSG_NOSIGNAL`，对端在发送期间关闭连接时由写入返回错误，而不是让 SIGPIPE 直接终止探测进程；现有截止时间、EINTR 重试和失败回退逻辑保持不变。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX AdGuard Home 上游回退 DNS 地址排除本机回环与链路本地段（2026-11-07）

- 代码提交：`10204c540cf5003b0ffdf3609951bc28d858eb38`。
- 文件：`fx-module/scripts/adguardhome.sh`。
- 用户配置的 fallback DNS IPv4 地址现在拒绝 127.0.0.0/8 回环段及 169.254.0.0/16 链路本地段，防止回退查询再次进入本机 AdGuard 形成递归回环，或指向不可稳定路由的链路本地目标。
- 同一限制同时应用于配置生成阶段与最终 YAML 配置契约检查，避免只在输入阶段拦截而运行配置绕过。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX AdGuard Home 回退 DNS 配置采用严格键值解析（2026-11-07）

- 代码提交：`277d6c54b9d0bd61586edd160318c077b3464c73`。
- 文件：`fx-module/scripts/adguardhome.sh`。
- 回退 DNS 的 `nameserver` 项必须是无额外字段的单一键值记录；缺值、多余参数、非法字段和重复服务器地址均拒绝渲染，不再静默忽略错误或重复条目。
- 保留 IPv4 地址范围限制及最多三个回退服务器的约束。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX AdGuard Home 回退 DNS YAML 段头严格校验（2026-11-07）

- 代码提交：`9524187c9d91186c5a143ba804e95dc6fa709ed2`。
- 文件：`fx-module/scripts/adguardhome.sh`。
- 最终配置契约检查仅接受 `fallback_dns: []` 空列表或无内联值的 YAML block-list 段头；拒绝把标量地址、额外字段或畸形内联值误判成合法空列表。
- 与前一轮 nameserver 键值解析及地址范围限制共同生效。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX Unbound DNSSEC 信任锚刷新失败时恢复原文件（2026-11-07）

- 代码提交：`a31cde1eeeb554081f843d7746e4baea9dd3a823`。
- 文件：`fx-module/scripts/unbound.sh`。
- 离线超过 14 天触发的有界 `unbound-anchor` 刷新，只要 helper 超时或返回失败，就恢复刷新前的完整信任锚文件；不再仅凭输出中仍存在一条 DNSKEY 记录而接受可能不完整的失败产物。
- 恢复失败时保留私有恢复副本并拒绝继续启动；成功刷新仍经过原有 DNSKEY 格式检查。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX 回退 DNS 地址校验在控制器与配置恢复入口统一（2026-11-07）

- 代码提交：`90846d32270488ac48f1b3c54e52a59396e68fd2`。
- 文件：`fx-module/scripts/yulong-ad-control.sh`。
- 新增独立回退 DNS IPv4 校验器，拒绝 127.0.0.0/8 回环地址及 169.254.0.0/16 链路本地地址。
- 单项配置写入、批量 DNS 配置写入和 DNS 配置快照恢复均使用相同的回退地址规则；普通 Global DNS 校验仍保留原有策略，不误伤有意使用本机地址的其他 DNS 配置。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX 回退 DNS 现有配置读取与快照校验统一（2026-11-07）

- 代码提交：`9fd100d7bc6c38d172bd73c3058bc0a625eb287c`。
- 文件：`fx-module/scripts/yulong-ad-control.sh`。
- 修正现有 DNS 段校验分派：`yulong_dns_fallback` 不再复用普通 Global DNS 校验器，而是使用专用回退 DNS 校验器。
- 因此读取 DNS 配置、生成配置快照及恢复前检查现有配置时，也会拒绝回环与链路本地回退地址，避免仅写入入口受限、旧配置读取/快照路径仍接受不合规数据。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX Stellar 授权策略列表整份校验与锁内读取（2026-11-07）

- 代码提交：`7e35af6f2b31af1a2789167388955b01fdb1d1ab`。
- 文件：`fx-module/scripts/yulong-stellar-control.sh`。
- Stellar 列表接口现在先完整校验包授权、能力授权和命令授权文件；重复记录、字段数量错误、非法包名/能力、非法命令或畸形行会使整个列表请求失败，不再静默跳过坏行并展示不完整策略。
- 列表读取改为通过现有 Stellar 事务锁执行，避免在授权文件并发替换期间读取到跨版本组合。
- 未改变授权写入格式、能力范围或实际权限执行行为。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX Hosts/Ad 托管名单读取与写入事务串行化（2026-11-07）

- 代码提交：`a07a144dc094c73f6fd7d820c748d1bd32490141`。
- 文件：`fx-module/scripts/native-managed-lists.sh`。
- `list` 操作现在使用与新增、编辑、启停、删除相同的托管名单锁，避免读取期间并发写入替换配置文件而得到跨版本或不完整的列表。
- 列表内容先在锁内完整解析和校验，成功后才输出 `FXLIST1` 协议头；畸形数据不会留下看似成功的半截响应。
- 未改变名单格式、排序、条目操作或 apply 行为。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX DNS 查询日志汇总拒绝畸形与截断记录（2026-11-07）

- 代码提交：`40011c12944fb66b0683aa3d2e3e4b85970bac11`。
- 文件：`fx-module/scripts/yulong-ad-dns-summary.sh`。
- 汇总器现在区分合法的非查询记录、合法查询记录和结构损坏记录；遇到括号不匹配、字符串未闭合或被截断的非空 JSONL 行时，整次汇总失败，不再跳过异常行后输出看似完整的计数。
- 统计结果只在完整扫描结束且没有畸形记录时输出；空白行仍允许忽略，原有只输出数字、不暴露域名和客户端地址的隐私边界保持不变。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX DNS 查询日志汇总拒绝非对象 JSONL 行（2026-11-07）

- 代码提交：`2ebd7000e39fd4d4518a48255dfcd596091de39c`。
- 文件：`fx-module/scripts/yulong-ad-dns-summary.sh`。
- 对非空日志行增加 JSONL 记录外层类型约束：每条记录必须以对象边界 `{` 和 `}` 包裹；数组、标量及被截断的外层结构均作为畸形记录，触发整次汇总失败。
- 与上一轮畸形记录失败关闭逻辑衔接，避免非对象行被误判为普通非查询记录并静默跳过。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX DNS 查询日志汇总严格校验 JSON 字符串转义（2026-11-07）

- 代码提交：`8cc996b9a279708c64d8cf8e3b747f7dd9b226d9`。
- 文件：`fx-module/scripts/yulong-ad-dns-summary.sh`。
- JSON 字符串扫描器现在只接受 JSON 标准允许的反斜杠转义；`\\u` 后必须紧跟四位十六进制码，拒绝未知转义、残缺 Unicode 转义和字符串内未转义控制字符。
- 对用于 reason/status 统计的嵌套字符串也执行同一完整性校验，畸形值会使整份日志汇总失败，不再作为普通状态被忽略。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

