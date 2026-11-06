

### FX Unbound 递归解析器运行参数接通与 38 字段 DNS 快照（2026-11-07）

- 文件：`scripts/yulong-ad-control.sh`、`fx-module/scripts/yulong-ad-control.sh`、`fx-module/scripts/unbound.sh`、APK 根目录与模块目录的 `FxYulongAdActivity.java`。
- 正式打包的根目录 DNS 控制器与模块目录已同步，新增 `unbound-runtime-get/set`：Unbound 缓存最大/最小 TTL、Serve Expired 开关、过期缓存最大年龄、过期答复 TTL、客户端等待超时、预取及 QNAME minimisation。
- Unbound 生命周期脚本从控制器读取参数并生成真实 `unbound.conf`；保存后走现有配置检查、生命周期锁和健康探测流程，不是仅保存 UI 值。
- DNS 页面提供 8 项 Unbound 参数的读取、编辑和保存；DNS 快照扩展到 38 项（18 个布尔开关），兼容旧 18/19/26/30 项快照。
- 清除并行合并造成的重复 Unbound 参数读取方法和重复设置卡；保留按后端 uint32 边界与最小 TTL 不大于最大 TTL的校验，且根目录/模块目录 APK 源码同步。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX AdGuard Home 上游策略、请求超时、缓存与 DNSSEC 引擎参数移植（2026-11-07）

- 文件：`scripts/yulong-ad-control.sh`、`scripts/adguardhome.sh`、`adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java` 及 `fx-module/` 对应模块镜像；同步运行模板 `.github/dns/AdGuardHome-FX-runtime-v1.0.0.yaml`、模块配置副本和 `fx-module/engines/adguardhome/AdGuardHome.yaml`。
- 新增受配置锁与事务保护的 DNS 引擎参数读写：上游选择 `load_balance / parallel / fastest_addr`、fastest 地址探测超时、上游查询超时、DNS 缓存开关与容量、过期缓存乐观应答、DNSSEC。
- AdGuard Home 配置渲染器从后端 `dns-runtime-get` 读取参数并写入实际运行 YAML；启动前的配置契约同步校验策略、超时、缓存容量和布尔开关，避免只保存 UI 值而运行配置未变化。
- DNS 页面新增参数编辑/读取/保存入口。新 DNS 快照扩展为 26 个字段（15 个布尔开关），旧 18/19 字段快照仍保留默认值兼容；快照恢复将运行参数与上游、VPN DNS、过滤策略和日志保留期限一起暂存，在外层事务中统一应用，失败回滚原配置。
- 运行 YAML 补齐此前缺失的 `fallback_dns` 与 `blocking_mode` 模板字段，确保现有备用解析和拦截响应模式能够被渲染器真正覆写。
- 参数按 AdGuard Home v0.107.79 支持的配置项实现；EDNS Client Subnet 仍关闭，避免将客户端网段信息发送给上游。参考官方配置说明：`https://github.com/AdguardTeam/AdGuardHome/wiki/Configuration`。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证；此次只提交源码和运行配置模板，尚未生成新的 AdGuard Home 二进制或 FX 安装包。

### FX DNS 策略值与上游状态统一回传（2026-11-07）

- 文件：`scripts/native-dns-settings.sh`、`fx-module/scripts/native-dns-settings.sh`、根 APK 与 fx-module APK 源码中的 `FxYulongAdActivity.java`。
- DNS runtime status 在既有上游模式、数量、bootstrap 与故障回退字段外，额外回传自定义/全局 DNS 开关、QUIC、DoT、明文 DNS、IPv6、跟踪域名保护和查询日志开关。
- 两份 APK 状态解析白名单同步接收新增字段；五项网络策略明确标注为“配置值”，不把尚未完成系统层拦截验证的开关描述为已经拦截。
- 根目录构建源码与 fx-module 镜像同步更新。Unbound 保留为本地递归默认路径及加密上游 bootstrap 服务。
- 按用户要求未执行测试、静态检查、构建、CI 或设备验证。



### FX DNS 查询日志记录类型筛选扩展为动态完整 RR 类型（2026-11-07）

- 文件：`FxYulongDnsActivity.java`。
- DNS 记录类型快捷筛选在保留常用选项的同时，根据当前加载的完整本地日志动态加入实际出现的合法 RR 类型，不再让未预置的记录类型只能手工输入。
- 类型数量较多时筛选栏可横向滑动；自定义 RR 类型输入仍保留，可筛选当前日志中尚未出现的类型。
- 不改变查询日志源数据、分页显示、搜索条件或分享筛选行为；未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 订阅字段、备注与状态输出残余长度门槛清理（2026-11-07）

- 文件：`scripts/native-managed-lists.sh`、`scripts/adguardhome.sh`、`FxYulongAdActivity.java`。
- 移除托管名单普通字段 4096 字符、备注 180 字符和 AdGuard 订阅 URL 2048 字符的应用层长度门槛；不再因这些人为字符数上限拒绝较长的有效订阅地址、名单字段或备注。
- Root Proxy 状态 UI 不再丢弃超过 256 字符的字段值，状态响应按完整字段读取。
- 继续保留字段分隔符、反斜杠、控制字符、HTTP/HTTPS 协议、DNS 域名 253 字符/标签 63 字符等语法和协议校验；Wi-Fi SSID 与 IP/端口约束未放宽。
- 根目录构建源码和模块目录镜像同步修改；本轮未运行测试、静态检查、构建、CI 或设备验证。


### FX Unbound 健康探测器 TCP 截断回退同步到编译源码（2026-11-07）

- 文件：`scripts/localdns-probe.c`。
- 将模块目录中较新的本地 DNS 探测器同步到 Unbound Android ARM64 构建实际使用的根目录源码。
- 探测器在 UDP DNS 响应带 TC（截断）标志时，会在同一超时期限内改用 TCP 重试；同时设置发送/接收超时，避免 UDP 发送阻塞没有超时约束。
- 保留 IPv4 loopback 目标限制、请求 ID/问题区匹配、递归可用标志和 RCODE 检查；不会把探测目标扩展到任意公网地址。
- 此改动会改变 Unbound 探测器构建输入；本轮未重编译 `fx-dns-probe`，也未运行测试、静态检查、构建、CI 或设备验证。旧二进制在重新构建前仍保留旧探测行为。


### FX DNS 主上游清空与快照恢复状态一致性（2026-11-07）

- 文件：`fx-module/scripts/yulong-ad-control.sh`、`fx-module/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java`。
- 清空自定义 DNS 或全局 DNS 列表时，在配置事务内同时关闭对应开关；清空备用 DNS 不影响主上游开关。
- DNS 快照导入预览和 Root 后端同时要求：启用全局 DNS 时必须有全局服务器列表；启用自定义 DNS 时必须有自定义服务器列表。无效快照在修改运行设置前被拒绝，避免恢复后上游缺失、引擎无法生成配置。
- m_dns_section_clear 仍经现有配置事务执行，失败时由外层备份恢复整个 settings.conf 并重新应用旧配置。
- 按用户要求未执行测试、静态检查、构建、CI 或设备验证。



### FX DNS 快照恢复改为单次完整应用事务（2026-11-07）

- 文件：`scripts/native-dns-settings.sh`、`scripts/yulong-ad-control.sh`。
- DNS 引擎开关批量写入新增受锁保护的 `set-many-deferred` 入口：沿用相同的开关白名单、默认声明、依赖归一化、配置写入和失败回滚，但将运行时应用延后。
- DNS 快照恢复先暂存 AdGuard/Unbound/第三方 VPN 兼容开关，再写入其余上游、过滤策略、VPN DNS、查询日志保留期限和拦截响应模式；由外层快照事务统一执行一次完整 `apply`，避免中途用不完整快照提前重启 DNS/VPN 路由。
- 普通 `set` 与 `set-many` 即时应用行为不变；延后应用入口由完整 DNS 快照事务调用。
- 根目录构建源码与 `fx-module/scripts/` 镜像同步更新；按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 开关事务、托管名单读取器与隐私统计同步至打包源码（2026-11-07）

- 文件：`scripts/native-dns-settings.sh`、`scripts/native-managed-lists.sh`、`scripts/yulong-ad-dns-summary.sh`。
- 将已更新的 DNS 引擎开关依赖约束/批量事务与运行状态输出、托管名单严格读取与变更处理、DNS 查询日志聚合统计实现同步到仓库根目录权威源码。
- 修正打包覆盖问题：正式构建会以根目录这些脚本覆盖 `fx-module/scripts/`，本轮使构建输入与模块目录中较新的实现一致，避免丢失后端依赖约束、严格名单协议和完整日志统计。
- 保留第三方 VPN Root Proxy 依赖状态判断、配置事务回滚、名单格式/重复项校验与隐私统计不输出域名明文的行为。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 查询日志开关接入 AdGuard Home 持久化日志（2026-11-07）

- 文件：\`fx-module/scripts/adguardhome.sh\`。
- 将 \`dns_querylog_enabled\` 配置开关接入 AdGuard Home 的 \`querylog.enabled\` 与 \`querylog.file_enabled\`；关闭时不启用文件日志，开启时同时启用查询日志和本机文件持久化。
- 保留用户配置的查询日志轮转期限，并继续沿用本地日志读取器读取当前及轮转文件的完整记录。
- 保留 AdGuard Home 的内存批量写盘阈值作为写入缓冲策略；该阈值不是日志总条数上限或历史记录保留数量上限。
- 按用户要求未执行测试、静态检查、构建、CI 或设备验证。



### FX DNS 与 Hosts/Ad 名单页面同步至 APK 实际构建源码（2026-11-07）

- 文件：`adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java`、`adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongDnsActivity.java`。
- 将模块目录中较新的 DNS/Hosts/Ad 页面实现同步到 APK 实际构建目录 `adhook/`，避免构建时重新使用旧 UI 源码。
- 同步包含 Root 命令输出容量提升、DNS 快照查询日志保留字段与旧快照兼容、完整 DNS 日志读取、域名批量分享/导入分隔符修正及 UI 导出限制清理。
- 列表页面保留分批渲染，完整日志/名单数据不因固定条数而丢弃；仍受设备内存、Java 数组、Intent/Binder 与进程资源的实际平台能力约束。
- 按用户要求未运行构建、测试、静态检查、CI 或设备验证。


### FX DNS 引擎与配置控制器同步至打包权威源码（2026-11-07）

- 文件：`scripts/adguardhome.sh`、`scripts/yulong-ad-control.sh`。
- 将已集成的 FX 自定义/全局上游选择、DoH/DoT/DoQ 和 IPv4 逐条验证、bootstrap 生成、备用上游列表、AdGuard 配置契约及 DNS 查询日志保留期限快照等实现同步到仓库根目录权威源码。
- 修复打包流程的源文件漂移：`build-fx-kernelsu.yml` 会先将根目录 `scripts/adguardhome.sh`、`scripts/yulong-ad-control.sh` 安装覆盖到 `fx-module/scripts/`，因此仅修改 `fx-module/scripts/` 会在正式打包时丢失；本轮使构建输入与当前模块实现保持一致。
- 继续保留本地 Unbound 递归解析默认路径、AdGuard loopback 监听契约、端点格式校验、DNS 配置事务与回滚；本轮未运行测试、静态检查、构建、CI 或设备验证。


### FX AdGuard Home 上游设置实际接入运行渲染（2026-11-07）

- 文件：\`fx-module/scripts/adguardhome.sh\`、\`fx-module/engines/adguardhome/AdGuardHome.yaml\`、\`fx-module/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java\`。
- 将已保存的 DNS 上游配置接入 AdGuard Home 实际运行 YAML：全局 DNS 开关开启时优先读取 \`[conf:global_dns]\`；否则自定义 DNS 开启时读取 \`[conf:custom_dns]\`；两者关闭时继续使用本地 Unbound \`127.0.0.1:5353\`。
- 上游列表按完整 section 读取；重复 section、重复 endpoint、额外字段、无效 IPv4、非法 DoH/DoT/DoQ URL/端口均失败关闭，不生成部分上游列表。保留不限定数量的完整名单。
- 配置加密上游时动态加入 bootstrap DNS；显式备用 IPv4 列表仍作为 AdGuard fallback。AdGuard 运行契约改为接受通过严格校验的显式外部上游，同时继续强制 DNS 监听与管理接口仅绑定 loopback，且禁止本地 Unbound 与外部 upstream 混用。
- DNS 拦截响应模式模板补入 \`blocking_mode\`，\`custom_ip\` 模式动态输出 IPv4/IPv6 空地址。
- UI 文案同步明确全局 DNS 优先级与本地 Unbound 默认路径。
- 按用户要求未执行测试、静态检查、构建、CI 或设备验证。



### FX DNS/域名名单导出容量与换行协议修复（2026-11-07）

- 代码提交：`08c3cbd77d883c7396399b8494cc3d06d2edebeb`。
- 文件：`fx-module/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java`。
- 移除白/黑名单合并分享的 64 KiB 导出门槛，完整序列化所选名单；保留域名自身 253 字符 DNS 协议长度边界。
- 修复黑名单筛选批量启停将分隔符写成字面量反斜杠-n 的问题；修复名单分享头部和记录行的换行序列化，导出文本可按真实行读取。
- 清除过滤订阅分享中遗留的未定义 `omitted` 变量引用，并修复分享成功提示的相邻字符串拼接问题。
- 移除过滤订阅名称 256 字符、域名备注 160/180 字符应用层限制；继续拒绝备注字段中的换行并保留分隔符、域名格式校验。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 上游数量上限最后两道校验清理（2026-11-07）

- 文件：`fx-module/scripts/adguardhome.sh`、`fx-module/scripts/yulong-ad-control.sh`。
- 移除 AdGuard Home 渲染备用 DNS 列表时的 `count>3` 拒绝条件；每条 IPv4 仍按格式、可路由地址范围和重复项校验。
- 移除 DNS 上游写入前检查既有 `custom_dns/global_dns/yulong_dns_fallback` 配置时的 `count>3` 条数拒绝条件；保留重复 section/key、未知字段、端点格式和协议校验。
- 与前端列表、批量配置写入及 DNS 快照的无条数限制行为对齐，避免保存成功但引擎配置渲染/再次编辑失败。
- 本轮未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 上游列表移除三条业务数量上限并扩展完整快照（2026-11-07）

- 代码提交：`c3c9d41de079f6b797a5427ea43dacbe033a5dee`。
- 文件：`fx-module/scripts/yulong-ad-control.sh`、`fx-module/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java`。
- 自定义 DNS（IPv4/DoH/DoT/DoQ）、全局 DNS 与备用 DNS 列表移除最多 3 条的应用层数量门槛；继续逐条验证端点格式、端口、重复项和 IPv4 合法性。
- DNS 配置快照增加查询日志保留期限字段；新快照写入并恢复该字段，后端同时接受旧 18 字段格式与新 19 字段格式，旧快照缺少该字段时采用 7d 默认值。
- DNS 主控制页的 Root 命令输出不再限定为 512 KiB，应用层缓冲上限提升为 `Integer.MAX_VALUE`；设备内存、Binder/系统参数和 Java 运行时仍属于平台边界。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX AdGuard Home 备用 DNS 列表运行契约移除三条上限（2026-11-07）

- 代码提交：`63a4a36b6edf065ff18381adb553dbef82e7e4da`。
- 文件：`fx-module/scripts/adguardhome.sh`。
- 删除 AdGuard Home 配置契约中的 `fallback_count<=3` 条件，避免前后端已允许的备用 DNS 列表在引擎运行前又被第二道数量门槛拒绝。
- 保留每条备用 IPv4 地址的格式、可路由性及重复项校验；没有放宽监听地址和本地 Unbound 唯一上游约束。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 缓存刷新控制器恢复与查询日志入口统一（2026-11-07）

- 代码提交：待提交。
- 文件：`fx-module/scripts/yulong-ad-control.sh`。
- 修复 `cache_flush()` 中缓存重启流程被 DNS 日志 case 分支片段破坏的问题，恢复 Unbound/AdGuard Home 的停止、启动、路由重新应用和退出码汇总路径。
- DNS 查询日志摘要与完整日志读取统一经由 `with_lock` 调用已有安全函数，避免绕过锁、日志路径符号链接检查和读取/清理串行化。
- 保留完整日志读取，不恢复 `tail -n 500`；保留现有日志清理的路径、文件类型和权限检查。
- 按用户要求未执行脚本、测试、静态检查、构建、CI 或设备验证。


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

### FX AdGuard Home 启停生命周期互斥（2026-11-07）

- 代码提交：`e30a59f99500fe0249b27f70c7a2909de514b8e6`。
- 文件：`fx-module/scripts/adguardhome.sh`。
- `ensure` 与 `stop` 现在共用状态目录内的原子目录锁；配置安装、PID 标记发布、进程启动/停止及健康探测期间，不允许另一条启停命令并发进入。
- 锁等待最多 35 秒，超时或锁路径异常时失败关闭；通过 owner PID 限定释放动作，避免误删其他生命周期操作持有的锁。
- `status` 与只读 `render-config` 不获取生命周期锁，不阻塞状态查询。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX Unbound 递归 DNS 启停生命周期互斥（2026-11-07）

- 代码提交：`6edad574d0ff9899bb45f8b6d3786f599cfce128`。
- 文件：`fx-module/scripts/unbound.sh`。
- `ensure` 与 `stop` 现在共用 Unbound 私有状态目录内的原子目录锁；配置生成/替换、信任锚刷新、PID 标记发布及进程启停不会被另一条启停命令并发打断。
- 锁等待最多 35 秒；锁路径异常、锁所有者发布失败或权限收紧失败时拒绝执行。锁释放仅允许当前持有者 PID 移除自己的 owner 标记与锁目录。
- 内部启动流程需要停止旧进程时仍调用锁内的 `_stop`，不会重复获取锁；只读 `status` 和 `render-config` 不获取生命周期锁。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX VPN 双 DNS 地址成对原子写入（2026-11-07）

- 代码提交：`a2cf8ae55937e569b4a79cc997b0dd4ab97c32fd`。
- 文件：`fx-module/scripts/yulong-ad-control.sh`。
- 新增 `write_vpn_dns_many`：一次校验现有 VPN DNS 配置后，在同一临时文件中同时替换/补齐 `remote_dns` 与 `cn_dns`，最后通过单次原子 rename 发布。
- VPN DNS 批量设置和重置统一走成对写入，避免两个独立配置替换之间出现只更新一项的中间状态；保留现有事务备份、失败回滚和 apply 流程。
- 单项 DNS 设置仍使用原有单项写入入口。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。

### FX Custom/Global/Fallback DNS 三组服务器单次原子更新（2026-11-07）

- 代码提交：`317283d80434ebc0f5b6a0374e796cddbf9a669d`。
- 文件：`fx-module/scripts/yulong-ad-control.sh`。
- 新增 `write_dns_sections_many`：先完整校验三组现有 DNS 配置，再在同一临时文件中同时重写或清除 custom、global、fallback 三个配置段，最后只执行一次原子替换。
- `dns-config-set-many` 不再依次替换三个独立配置段；任一配置写入失败不会留下只更新一部分的中间文件状态。输入地址格式及 fallback 专用地址限制保持不变。
- 保留原有外层事务备份、失败回滚和运行配置应用流程。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。



### FX DNS 引擎开关组单次原子配置发布（2026-11-07）

- 代码提交：待提交。
- 文件：`fx-module/scripts/native-dns-settings.sh`。
- 新增白名单约束的 `write_flags_many`，对 DNS 引擎、递归转发、第三方 VPN 兼容及外部 DNS 代理开关执行整组读取校验与单次临时文件替换。
- 单项开关及依赖联动（启用/停用 AdGuard Home、Unbound、Root Proxy）改为一次写入；`set-many` 的四项最终状态也不再连续调用多次 `pg_set`，消除配置文件中间态，同时保留原有外层备份、回滚、锁和 apply 流程。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX 开机配置初始化改为安全原子发布（2026-11-07）

- 代码提交：待提交。
- 文件：`fx-module/service.sh`。
- 开机首次生成 `settings.conf` 改为先在私有状态目录创建临时文件、完整复制默认配置、设置权限，再通过单次 rename 发布，避免启动中断或存储写入失败留下半截配置。
- 拒绝既有配置路径为符号链接或非普通文件；默认配置缺失、不可读、临时写入失败、最终配置为空/不可读/不安全时，停止后续运行时 apply，避免把无效配置送入 DNS/VPN/Hosts 启动链。
- 若并发启动的另一工作进程先完成初始化，不覆盖其已发布配置。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX QuickJS 订阅同步锁增加进程启动身份校验（2026-11-07）

- 代码提交：待提交。
- 文件：`fx-module/scripts/jsruntime/sync-subs.sh`。
- 订阅同步锁的 owner 记录从单独 PID 扩展为 PID + `/proc/PID/stat` 启动时钟；锁冲突判断同时核对 PID 存活与启动身份，避免 PID 被系统复用后把无关进程误认作同步任务持有者。
- 锁释放必须匹配当前 PID 和启动时钟；锁目录/owner 文件遇到符号链接时拒绝跟随，owner 发布后再次读取确认归属。
- 保留原有并发互斥、失效锁限时回收、脚本文件保留与回滚流程。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX ProtectionProfile 定时任务 PID 身份绑定与安全停止（2026-11-07）

- 代码提交：待提交。
- 文件：`fx-module/scripts/yulong-profile-schedule.sh`。
- Profile watcher PID 文件改为同时记录 PID 与 Linux 进程启动时钟；状态判断、重复启动识别和停止信号都绑定这组身份，避免 PID 复用时误把其他进程当作 watcher。
- watcher 命令行验证改为逐个读取 NUL 分隔 argv，并要求脚本路径参数后紧跟 `watch`，不再使用扁平命令行子串匹配。
- 对旧版 PID-only 文件保留受限兼容：只有精确 argv 证明目标是本 watcher 时才升级记录或发停止信号；身份不匹配时拒绝向该 PID 发送信号。
- 保留现有 Profile 计划调度、运行锁、TERM/KILL 等待和日志行为。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX Yulong Ad 定时任务 PID 身份绑定与精确 watcher 识别（2026-11-07）

- 代码提交：待提交。
- 文件：`fx-module/scripts/yulong-ad-schedule.sh`。
- watcher PID 文件改为记录 PID 与 `/proc/PID/stat` 启动时钟；状态查询、重复启动识别及停止流程绑定进程启动身份，避免 PID 重用误判。
- watcher 命令行识别改为按 NUL 分隔 argv 精确确认脚本路径与 `watch` 参数，不再依赖扁平命令行子串。
- 对旧版 PID-only 记录保留受限兼容；只有精确识别为本 watcher 后才允许升级记录或发送 TERM/KILL，身份不符时拒绝信号。
- 保留现有运行锁、时间计划计算、规则 apply 与失败回滚行为。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX QuickJS 订阅调度时间戳文件安全发布（2026-11-07）

- 代码提交：待提交。
- 文件：`fx-module/scripts/jsruntime/native-script-scheduler.sh`。
- 订阅刷新时间戳读取前拒绝符号链接、非普通文件、不可读文件和非纯数字内容；损坏时间戳不再被默认为零并触发意外刷新。
- 刷新成功后在私有状态目录内创建权限受限的临时文件，完整写入后再原子替换时间戳；发布前拒绝符号链接或异常目标对象。
- 启动时约束时间戳和调度日志只能是普通文件，避免调度日志重定向跟随预置符号链接。
- 保留订阅刷新周期、失败重试和 watcher 所有权协议。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX QuickJS 兼容调度入口时间戳安全发布同步（2026-11-07）

- 代码提交：待提交。
- 文件：`fx-module/scripts/jsruntime/scheduler.sh`。
- 将兼容调度入口的订阅刷新时间戳读取与发布策略同步到 native scheduler：拒绝符号链接、非普通文件、不可读或非数字时间戳；异常状态不再被默认为零并触发刷新。
- 刷新成功后使用状态目录内权限受限的临时文件原子替换时间戳；启动时约束时间戳和调度日志目标只能是普通文件。
- 保留现有调度间隔、同步脚本调用、失败重试和 PID 所有权协议。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX QuickJS 订阅同步临时文件改为随机私有创建（2026-11-07）

- 代码提交：待提交。
- 文件：`fx-module/scripts/jsruntime/sync-subs.sh`。
- 活动订阅快照、下载暂存文件和元数据包装文件不再使用可预测的 PID 文件名直接创建；统一由 `mktemp` 在脚本目录内创建唯一文件，并收紧为仅 owner 可读写。
- 下载输出目标在交给 curl 前已由本进程创建为普通临时文件，避免预置符号链接抢占固定 `.fetch.PID` 路径后让下载内容写入其他文件。
- 元数据包装也使用独立随机临时文件，完成包装后再替换当前下载暂存文件；清理流程只删除本次持有的临时路径。
- 保留订阅 URL/元数据约束、SHA-256 完整性记录、旧脚本回滚和同步锁协议。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX QuickJS 订阅同步 PID 参数展开修正（2026-11-07）

- 代码提交：待提交。
- 文件：`fx-module/scripts/jsruntime/sync-subs.sh`。
- 修正订阅同步锁持有者 PID、进程启动时间查询、锁释放身份比较、过期锁隔离目录以及临时备份清理路径中的 PID 展开，统一使用 shell 当前进程 PID（`$$`）。
- 修复后锁 owner 记录与当前同步进程身份能够对应，过期锁目录及本轮备份文件也按真实 PID 命名和清理。
- 本轮未运行测试、静态检查、构建、CI 或设备验证。


## FX DNS 配置快照系统文件导入/导出
- 代码文件：`fx-module/adhook/app/src/main/java/de/privacyguard/adhook/imported/ad/FxYulongAdActivity.java`
- DNS 配置备份新增 Android 系统文件保存入口，使用 Storage Access Framework 的 `ACTION_CREATE_DOCUMENT`，由用户选择保存位置与文件名；保留原有系统分享入口。
- DNS 配置恢复新增系统文件选择入口，使用 `ACTION_OPEN_DOCUMENT`；读取内容限制为 48 KiB，并以严格 UTF-8 解码，拒绝超限或非法编码文件。
- 文件读取只填入现有快照编辑框，不会自动执行恢复；仍须经过既有完整字段校验、二次确认和 Root 后端事务回滚流程。
- 本轮未运行测试、静态检查、构建、CI 或设备验证。


## FX DNS 快照导出格式与恢复协议对齐
- 修正 `FxYulongAdActivity.java` 中系统分享和系统文件导出的快照正文：第一行现在直接写入 `FXYULONGDNSPROFILE1`，后续写入配置字段，与后端恢复器的首行版本检查完全一致。
- 同时将正文分隔符改为实际换行，避免导出内容携带字面量反斜杠与 n，保证文本备份可直接交给现有导入流程。
- 不改变后端快照字段、兼容版本、48 KiB UI 限制或恢复前确认流程。
- 本轮未运行测试、静态检查、构建、CI 或设备验证。


## FX DNS 快照恢复预览增加当前配置差异对照
- 恢复前先读取当前 DNS 快照，与待导入的 18 项字段逐项对比。
- 预览明确列出所有即将改变的字段及旧值/新值；完全相同时提示无字段变化。
- 当前快照读取失败、版本头异常、字段重复或缺失时停止恢复，不继续进入确认流程。
- 保留现有导入字段校验、双重确认及 Root 后端事务回滚。
- 本轮未运行测试、静态检查、构建、CI 或设备验证。


## FX 用户域名名单导出拒绝静默截断
- 修改 `FxYulongAdActivity.java` 的白/黑名单分享导出：如果完整名单超过 64 KiB，立即取消分享并提示当前已处理数量与总数量，不再生成带 omitted 注释的部分备份。
- 采用增量 UTF-8 字节计数，避免每追加一行都重新编码整个累计文本。
- 确保标记为“完整名单备份”的导出结果不会悄悄漏掉后半部分；用户可拆分白名单/黑名单或减少条目后重新导出。
- 本轮未运行测试、静态检查、构建、CI 或设备验证。


## FX DNS 上游配置读取响应严格解析与空列表同步
- `loadDnsLists()` 现在要求 `FXYULONGDNS1` 协议头，拒绝未知记录、格式错误记录、重复单值字段及缺失必需字段。
- 严格验证自定义/全局 DNS 开关值，以及 VPN DNS IPv4 地址；异常响应不会把部分数据写入界面。
- 三组 DNS 上游列表无论为空与否都会同步覆盖输入框，修复后端已清空名单但 UI 仍残留旧地址、造成误保存的状态错位。
- 保留 VPN DNS 缺省地址回退行为。
- 本轮未运行测试、静态检查、构建、CI 或设备验证。


## FX DNS 拦截响应模式应用后同步正确选项
- 修复 DNS 安全配置预设应用成功后，界面无论实际选择何种响应模式都强制勾选 NXDOMAIN 的状态错位。
- 现在按后端实际提交的 `nxdomain`、`refused`、`custom_ip` 模式分别选中对应单选项；避免 UI 展示与已保存 DNS 行为不一致。
- 本轮未运行测试、静态检查、构建、CI 或设备验证。


### FX 导入、名单、GKD 与 Dia 脚本库容量限制移除（2026-11-07）
- 移除 FX Ad 订阅/域名白黑名单导入、批量状态切换、恢复和分享中的 64 KiB、2000 条及输入框字符数上限；后端同步移除 base64 字符数、解码字节数与批量行数门槛。
- 移除本地 GKD 规则库 500 条持久化/新增/导入上限及 1 MiB 导入文本上限。
- 移除 Dia Frida 脚本库 500 个脚本上限。
- 保留格式、编码、域名/来源有效性、重复项、配置完整性和事务失败回滚校验；本轮未运行测试、静态检查、构建、CI 或设备验证。


### FX 文件浏览、Root 输出、备份与 QuickJS 内存限制放宽（2026-11-07）
- RootAccess 移除默认 1 MiB 输出截断和 128 KiB 命令字符串限制；默认输出容量改为 Java 可表示的最大正整数。
- Dia 文件浏览移除目录 5000 项、文件预览 512 KiB、APK/SO 2000 项上限；目录仍保留分页显示，避免一次性堆满 UI。
- Dia 备份/恢复将 1 MiB 人为门槛提升至 Java byte[] 可表示范围；GitHub 请求/响应不再使用原 1 MiB/64 KiB 限额。
- QuickJS 启动不再强制指定 64 MiB memory-limit；保留脚本运行时已有权限、超时与错误处理。
- 设备内存、Java 数组、Android Binder/Intent、操作系统参数长度和进程资源仍属于平台硬边界；本轮未运行测试、静态检查、构建、CI 或设备验证。


### FX 用户字段长度、崩溃报告与监控事件容量限制移除（2026-11-07）
- 移除托管名单规则值 4096 字节、备注 180 字节限制；域名自身仍遵守 DNS 标签/域名协议长度规则。
- 移除 GKD 选择器、排除选择器和分组名称的 512/40 字符上限；保留语法解析、包名、动作与冷却值校验。
- 移除 Dia 崩溃报告 512 KiB 读写上限。
- 移除 Dia 监控日志 256 KiB、单行 2048 字符、单事件 10 字段和仅保留 300 个事件的截断策略；保留事件标签/字段白名单及值字符过滤。
- 本轮未运行测试、静态检查、构建、CI 或设备验证。


### FX 域名导入、Dia 监控事件与崩溃报告容量限制移除（2026-11-07）
- 移除后端域名白/黑名单导入 64 KiB 与 2000 行限制，并修复此前批量移除上限代码后遗留的孤立错误处理语句，恢复导入函数正常控制流。
- Dia 监控事件解析不再截取最近 256 KiB、不再限制单行 2048 字符或仅保留 300 条事件；按输入完整解析。
- Dia 崩溃报告读取/写入移除 512 KiB 限制。
- FX DNS 控制日志与启动日志读取不再固定只显示最近 500/180 行，改为读取完整日志。
- 继续保留事件字段白名单和安全值过滤、域名格式校验、JSON 结构校验及原子文件写入；本轮未运行测试、静态检查、构建、CI 或设备验证。


### FX GKD 与 Dia 日志/事件/清单显示容量上限继续移除（2026-11-07）
- GKD 每应用扫描节流器不再只保留最近 500 个包名状态，避免超过数量后旧包状态被提前驱逐。
- Dia Activity 清单导出移除 256 KiB 截断/省略行逻辑。
- Dia Frida/Gadget 会话日志改为读取完整日志文件，移除 500 行、512 KiB Root 输出、512 KiB 文件导出、48 KiB 分享及搜索词 256 字符限制。
- Dia 结构化监控事件移除 120 条界面显示上限、800 行读取上限、512 KiB Root 输出、256 KiB 文件导出、48 KiB 分享及搜索词 256 字符限制。
- Frida 目标/进程搜索词不再截断到 256 字符，待选 PID 列表不再限制 256 项；保留进程 PID 格式校验。
- 本轮未运行测试、静态检查、构建、CI 或设备验证。


### FX Dia DEX 索引数量/大小限制移除（2026-11-07）
- DEX 单文件读取上限从人为 96 MiB 放宽至 Java byte[] 可寻址范围。
- 移除 100,000 个类、每类 20,000 个成员、每类 512 个调用点、每 DEX 150,000 个调用边及每方法 2 Mi code units 的截断/拒绝门槛。
- 移除接口数和方法参数数 4096 项人为限制；保留 DEX 偏移、表范围、整数可寻址性、取消请求和格式完整性检查。
- 本轮未运行测试、静态检查、构建、CI 或设备验证。


### FX GKD 无障碍树、选择器匹配与规则导入容量限制继续移除（2026-11-07）
- GKD 无障碍快照移除 700 节点、每节点 80 子节点和文本/描述 256 字符截断；选择器移除 512 字符上限，匹配结果不再截取前 12 项，自动化规则对完整匹配集执行既有动作资格检查。
- GKD 规则文件导入移除 1 MiB 读取门槛。
- GKD-XA 备份归档读取移除 64 MiB 输入包限制。
- Dia Frida/Gadget 会话日志状态提示改为完整日志；错误详情不再截断 240 字符。
- 无障碍树仍保留递归深度保护（避免恶意/异常树导致进程栈溢出）；无障碍敏感节点文本仍不采集；保留平台节点失效处理与完整树检查。
- 本轮未运行测试、静态检查、构建、CI 或设备验证。


### FX QuickJS Egern/Stash 脚本元数据长度与位置限制移除（2026-11-07）
- `host.js` 不再只检查脚本文件前 16/20 行来寻找 Egern 环境变量、脚本名称和 Stash 参数元数据，改为扫描完整脚本源。
- 移除 Egern 环境变量值 512 字符限制、环境变量键名 64 字符限制、脚本名称 512 字符截断及 Stash 参数 512 字符拒绝门槛。
- 保留环境变量键名字符集校验、元数据 JSON 类型检查、控制字符清理及脚本源解析失败回退。
- 本轮未运行测试、静态检查、构建、CI 或设备验证。


### FX Shield 用户黑白名单容量上限移除（2026-11-07）
- 移除 Shield 黑名单与用户白名单 1 MiB 原始文本、10,000 个应用条目限制；解析、去重、序列化和白名单加载均不再因这些人为容量阈值拒绝完整名单。
- 白名单选择器不再因条目数或序列化字符数提示超限；仅在存在无效包名时拒绝整批保存，不做部分写入。
- Dia 结构化监控事件读取错误详情不再截断 240 字符。
- 保留 Android 包名格式/长度校验、整批原子拒绝和 SharedPreferences 写入成功确认；本轮未运行测试、静态检查、构建、CI 或设备验证。


### FX AdGuard Home 与 Unbound DNS 生命周期锁 PID 所有权发布修复（2026-11-07）

- 文件：`fx-module/scripts/adguardhome.sh`、`fx-module/scripts/unbound.sh`。
- 修复两个 DNS 引擎生命周期锁的 owner PID 展开错误：发布 owner 文件时使用当前 shell PID `$$`，释放锁前也使用同一 PID 核对所有权。
- 同时将 owner 文件写入格式修正为真正的换行分隔，避免把字面量反斜杠-n 写入 PID 文件，导致释放阶段无法匹配并遗留锁目录。
- 该修复覆盖 AdGuard Home 与 Unbound 两个引擎，确保 start/stop 互斥锁可正确建立和释放；不改变 DNS 解析、上游、规则或 VPN 路由策略。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证。


### FX DNS 查询日志与名单批量操作容量链路扩展（2026-11-07）

- 文件：`FxYulongDnsActivity.java`、`yulong-ad-control.sh`。
- DNS 查询日志后端不再只返回最后 500 行，改为读取完整本机保留日志；UI 文案同步移除“最近 500 条”的错误描述，列表仍按页面分批渲染以控制视图开销。
- DNS 日志 Root 输出容量由 768 KiB 放宽到 Java 可表示范围，避免完整日志在到达解析器前被截断。
- 批量加入名单移除 2000 个唯一域名与 64 KiB payload 限制；Root 命令参数白名单不再以 87384 字符拒绝较大的 base64 名单。
- 域名复制与筛选结果分享移除 48 KiB 文本上限/静默省略策略；修正域名列表分隔符及导出报告的换行、制表符转义，使批量导入与分享文本按真实行分隔。
- 保留 DNS 域名格式校验、Root 命令操作白名单、筛选条件、逐页渲染和后端事务回滚。未运行构建、测试、静态检查、CI 或设备验证。


### FX DNS 设置页快照与名单批处理限制继续移除（2026-11-07）

- 文件：`FxYulongAdActivity.java`。
- 移除过滤订阅导入 2000 条/64 KiB 门槛、DNS 配置快照分享/文件导出/文件读取/恢复的 48 KiB 门槛。
- 移除白/黑名单筛选批量启停 2000 条及 64 KiB 限制；移除合并名单备份恢复、批量移除、批量导入的 2000 条与 64 KiB 限制。
- 批量域名列表统一使用真实换行分隔，继续保留域名/字段格式校验、重复项合并、快照版本头与字段白名单校验、后端整批事务回滚。
- 设备内存、Android Intent/Binder 与 shell 参数长度仍属于平台边界；本轮未运行构建、测试、静态检查、CI 或设备验证。


### FX DNS/Ad 名单输入控件与筛选操作剩余容量门槛清理（2026-11-07）

- 文件：`FxYulongAdActivity.java`。
- 移除名单/批量文本输入控件 48 KiB 与普通文本 4096 字符的统一 LengthFilter；移除筛选过滤订阅 2000 条上限及批量名单状态切换 64 KiB 门槛。
- 更新白/黑名单导入与移除 UI 描述，不再显示已移除的 2000 条/48 KiB/64 KiB 限额。
- 保留完整名单校验、单次配置事务、失败回滚和不完整导出拒绝策略；未运行构建、测试、静态检查、CI 或设备验证。


### FX DNS 名单 UI 残余文案与批量黑名单状态门槛收尾（2026-11-07）

- 修正白/黑名单导入、移除说明中残留的 2000 条/48 KiB/64 KiB 文案。
- 黑名单批量启停同步移除残余 64 KiB 检查，并统一为真实换行分隔，避免将字面量反斜杠-n 写入名单导入载荷。
- 未运行构建、测试、静态检查、CI 或设备验证。


### FX DNS/Ad 列表状态批量操作与订阅分享上限收尾（2026-11-07）

- 文件：`FxYulongAdActivity.java`。
- 移除黑名单批量启停 64 KiB payload 限制，修复其批量域名分隔符为真实换行。
- 移除过滤订阅分享的 64 KiB 导出容量与超限省略行逻辑，改为完整输出所有有效订阅。
- 本轮保留名单数据校验、Root 命令白名单和后端事务处理；未运行构建、测试、静态检查、CI 或设备验证。


### FX DNS 上游本地容错、快照恢复与构建入口同步（2026-11-07）

- DNS 日志保留期限自定义值现在贯通配置快照恢复：Root profile parser 复用 `valid_dns_querylog_retention`，不再只接受 1d/3d/7d/30d；根目录和 `fx-module` 两份脚本均已更新。
- AdGuard Home 外部自定义/全局上游若未配置显式 fallback，运行时自动写入 `fallback_dns: 127.0.0.1:5353`，让上游无响应时回退到 FX 本地 Unbound；显式填写的用户备用 DNS 列表保持优先。配置安全校验只允许这个精确本地地址作为特例，普通用户备用服务器仍要求可路由 IPv4。
- DoH/DoT/DoQ 的 hostname bootstrap 使用本地 Unbound 递归解析，不再依赖固定公共 DNS；运行时配置验证已允许精确的 `127.0.0.1:5353` bootstrap 地址。
- 两个 DNS build patcher 已同步全局 DNS 优先于自定义 DNS、未显式填写 fallback 时使用本地 Unbound、加密 upstream bootstrap 使用本地 Unbound 的生成规则。
- 原生 Ad 页说明同步解释自动本地回退与用户显式 fallback 的优先级。
- 相关提交：`fac8e359a14b3bcd8f7a020c27f5051b74694d49`、`06e72554a19933fdd95aa7cac73b2e0f3e796167`、`04d095f762a1063e94d27ad7ea4c1d2f2d501446`、`bf19291670d88a64df2dd1be5e0a1b7a7808f527`、`cdba5c63a9a0bf9684ae49cece0d46f87ef99046`、`f49591575cbf300eb73aa38ea46cd4656e27899b`、`5ac6097b02c58767b4482f12e612e44db6880407`、`046d468d6068e0627341a32ac91d17e7e198dd03`、`2a3264c44a8346f4282351527efd0abd325c4214`、`ddff0fecec21c40df51090dbd93c6c9592835d91`。
- 按要求未运行测试、静态检查、构建、CI 或 Android 真机验证；不能把上述源码变更描述为已通过验证。
## 2026-11-07 — AdGuard 双栈未缓存健康探测与手动 DNS 修复入口

- 将 `scripts/localdns-probe.c` 和 `fx-module/scripts/localdns-probe.c` 的探测端点由仅 IPv4 loopback 扩展为 IPv4/IPv6 loopback：IPv4 仅允许 127.0.0.0/8，IPv6 仅允许 ::1；UDP 与截断后的 TCP 重试均沿用同一地址族，拒绝非 loopback 地址。
- AdGuard Home canonical/module 生命周期脚本不再用固定 `example.com` A 记录的 `nslookup` 判断健康，改为调用已校验 SHA-256 的 FX 随机唯一查询探测器，对 `127.0.0.1:53` 与 `[::1]:53` 分别发起未缓存查询并验证 DNS 报文、递归可用标志及响应码；缓存命中不再足以伪装为上游健康。
- 增加 watchdog `repair` 一次性命令：沿用现有 `_reconcile_once()` 恢复逻辑，按当前配置检查并恢复 FX 自有 Unbound/AdGuard Home，返回 ready/failed 及原因；不改写 DNS 设置，不接管第三方 VPN，不修改 Android Private DNS 或系统路由。
- `scripts/localdns-watchdog.sh`、`fx-module/scripts/localdns-watchdog.sh`、两份 `yulong-ad-control.sh` 均提供 `dns-repair` 命令；canonical 与 module 两套 `FxYulongAdActivity.java` 在 DNS 状态卡片增加“立即尝试修复 DNS 服务”按钮，确认后执行修复并刷新状态。
- 本批主要提交：IPv4/IPv6 探测器 `800295628c02201f31e6bc1a0b31c743bd8c5ca2`、`ccdfe41e1f4b278a8d2e52246cbfc11eeed9ed16`、显式 IPv6 头文件 `70a304c3d0f1397d8be25cf13f7bbf0184e4d7bb`、`1bd6200c4a3c6de46d6704d2ba26248328167d3e`；AdGuard 未缓存探测 `c87ab368a2fee1620a888a7f836a280eca1acb3c`、`ee3eb8ffd9a15335315ff977879b1b45ffb33b47`；watchdog/CLI 修复入口 `4ea03dcc4028546af3e4615baf65c2d7e5161403`、`96f719d5f37e5b2a77db2b5b077bade266d0f9bd`、`b53a39721a3f69529fcf417c10751e44a5879590`、`50e608b8d994705b4a6752587a08b372a06267b1`；两份 UI `ef18dec1b72e4185d26c78271f0792e158d714a1`、`4fd792f7089119a300488065b680eaf67f13d009`。
- 按当前要求未运行 C/Shell/Java 测试、静态检查、构建、CI 或 Android 真机验证；以上是源码提交与接线记录，不代表设备运行验收。

## 2026-11-07 — 自定义 DNS IPv4 非标准端口支持

- 扩展自定义 DNS 上游端点语法，允许纯 IPv4 地址附带显式端口（1–65535），默认不填写时仍使用 DNS 默认端口。此项仅放宽 custom DNS；global DNS、VPN DNS 及 IPv4-only fallback 继续保留原有类型约束。
- Root 控制脚本的 DNS CSV 校验接受 IPv4:port；AdGuard Home 配置渲染器及渲染后配置策略校验同步识别该格式，防止保存成功后被运行配置安全校验拒绝。
- 修正 AdGuard Home 两套 DNS 主机校验器中 IPv4 检查函数名不一致的问题，统一调用 valid_ipv4，避免以 IPv4 字面量作为加密上游主机名时发生错误。
- DNS 配置快照导入验证仅对 CUSTOM_SERVERS 接受 IPv4:port；global/fallback 与 VPN DNS 仍执行原有 IPv4 校验。原生 Ad UI 提示同步为 IPv4[:端口]。
- 变更同步覆盖 scripts/ 与 fx-module/ 两套 Root、AdGuard Home 和 APK Activity 源码；按当前推进要求未执行测试、静态检查、Gradle 构建、CI 或 Android 真机验证。
## 2026-11-07 — Unbound DNSSEC 密钥预取 UI / Root / 快照贯通

- 修复 Unbound DNSSEC `prefetch-key` 配置已经由 Root 后端及 Unbound 渲染器支持，但原生 Ad 页面没有入口、保存命令缺少参数的问题。
- 原生 Ad 页面新增“启用 DNSSEC 密钥预取”开关；参数读取、布尔值校验、保存命令和状态反馈全部接入 `UNBOUND_PREFETCH_KEY`。
- DNS 配置快照允许并比较 `UNBOUND_PREFETCH_KEY`，恢复旧版 38 字段快照时默认补为 `1`；当前快照字段总数更新为 39，开关统计同步更新为 19。
- 已同步 `adhook/app/.../FxYulongAdActivity.java` 与 `fx-module/adhook/app/.../FxYulongAdActivity.java` 两份正式源码。
- 源码提交：`00bf11c0133afb4c2cd3b150324e812ff344ec64`。
- 按用户当前要求未运行测试、静态检查、构建、CI 或 Android 真机验证；仅完成 GitHub 源码提交。
## 2026-11-07 — DNS 查询日志排序与轮转清理反馈

- DNS 查询日志列表在聚合活动 `querylog.json` 与所有轮转 `querylog.json.*` 后，按可识别的记录时间从新到旧稳定排序；无法识别时间的条目保留在列表末尾，不静默丢弃。
- 清理确认说明同步为活动及全部轮转日志，清理成功后从后端 `files=` 返回值显示实际处理文件数；不修改 DNS 规则、Hosts 或系统日志。
- 同步正式源码与模块源码：`fx-module/adhook/app/.../FxYulongDnsActivity.java`、`adhook/app/.../FxYulongDnsActivity.java`。
- 代码提交：`207cb5b0669f41ad650f0eda2b2b575c814818d3`。
- 按当前要求未运行测试、静态检查、构建、CI 或 Android 真机验证。
## 2026-11-07 — DNS 查询日志轮转时长边界与输入修复

- 对照 AdGuard Home 配置语义，将自定义查询日志轮转时长限制为上游支持的 1 小时至 8760 小时（最长 365 天）；保留 1/3/7/30 天快捷值，新增小时或天数输入，例如 12h、90d。
- 修复 `valid_dns_querylog_retention` 中参数后缀展开被反斜杠转义的问题；Root 写入、配置读取与 DNS 快照恢复现在共用相同的数值/单位范围校验。
- AdGuard Home 配置渲染器同步校验 `h` 与 `d` 单位及 8760 小时上界，避免设置落盘但服务启动时拒绝配置。
- 同步文件：`scripts/yulong-ad-control.sh`、`fx-module/scripts/yulong-ad-control.sh`、`scripts/adguardhome.sh`、`fx-module/scripts/adguardhome.sh`、两个源码树中的 `FxYulongAdActivity.java`。
- 本批提交：`f30b3d5e4cbad8ed8c6257c01225d84813dd5925`、`ea9bf037cae0ac37d93a4f8295dbd8d8dadf724f`、`e924227716cf6e8c8396927f2e380c288a44cfc5`、`6aea643681d284b92c82c430ded3cdc1102503ef`、`39cebb0f00fd12fe395f871d55c397fa5390b63e`、`49ace88241568722cec75b56ae8c1838eeebb122`。
- 按当前要求未运行测试、静态检查、构建、CI 或 Android 真机验证；仅确认 GitHub 文件写入返回成功并进行了源码回读。
## 2026-11-07 — DNS 上游完整校验与备用配置歧义拒绝

- `native-dns-settings.sh` 的 DNS 区段读取由简单行数统计升级为完整端点校验：custom 支持 IPv4、IPv4:port、DoH、DoT、DoQ；global 与 fallback 只接受可路由 IPv4 / IPv4:port。校验重复区段、重复端点、空值、未知字段、非法域名/端口及格式错误；状态接口不再把结构上像 nameserver、实际上无法被运行时接受的配置报为正常数量。
- `adguardhome.sh` 的备用 DNS 渲染器拒绝重复 fallback 区段、缺失值、额外字段、未知字段及重复/非法端点，避免静默忽略错误配置。
- 同步修改仓库脚本源与 `fx-module/scripts` 实际模块脚本；代码提交包括 `b072182ecd1fd4884a8226b1b929fad15d42716d`、`8029e862b0dbf19c870fdacd75c772991c212eda`、`74e0768bef6f5ffcefb5ca30a2902a47f2b52e58`、`78cb484a491425bcf99287747f8af8db38b1a660`。
- 按当前提速要求未运行测试、静态检查、构建、CI 或设备验证；以上为源码提交，不代表运行验收。
## 2026-11-07 — DNS 查询统计扩展到本地域名与响应分布

- 原有本地查询统计继续保留服务端全部活动/轮转日志的总查询、拦截和未拦截计数；原始统计协议不增加客户端 IP 或明细域名字段。
- 原生 DNS 查询日志页在已有本地载入数据上增加二次聚合：去重域名总数、全部已出现 RR 类型分布、全部 DNS 响应码分布，以及高频拦截域名排行。域名按小写归一后去重，统计不依赖当前搜索、类型、时间或结果筛选器。
- 高频拦截域名 UI 只显示前五名以保持页面可读；内部计数遍历全部已载入记录，其他域名仍计入总量。客户端 IP 不显示、不导出、不上传。
- Root 查询统计请求成功/失败状态与日志载入成功/失败状态分别维护；任一异步回调完成后会重绘同一摘要，避免异步到达顺序覆盖本地聚合结果。
- 源码提交：`d922e6db7520bceb5ce24d37d6951b93957005e6`；模块打包源码同步提交：`12722c2086761669936df32b5dd550ee64ec1e30`。
- 本批按要求未运行测试、静态检查、Gradle/APK 构建、CI 或 Android 真机验证；已完成 GitHub 写入与源码回读，不代表设备验收。
## 2026-11-07 — DNS 查询日志统计与日志维护自动联动

- 在已有查询总量/拦截/未拦截服务端汇总上，原生 DNS 日志页增加本机载入记录的二次聚合：去重域名数、全部出现的 RR 类型分布、全部响应码分布，以及高频拦截域名排行。
- 所有已载入记录均参与统计；高频拦截域名仅为页面可读性展示前五名，其余域名仍参与总量和排名统计。没有增加客户端 IP 字段，也不上传域名或原始查询日志。
- 每次刷新查询日志时同步刷新服务端汇总；清理活动/轮转日志成功后立即清空本机统计，并显示空日志状态，不要求额外手动刷新统计。
- 普通源码提交：`d922e6db7520bceb5ce24d37d6951b93957005e6`、`4362590b06a827374b12eb6c3398a27a3273ef9f`；模块打包源码提交：`12722c2086761669936df32b5dd550ee64ec1e30`、`47d538430e6c930a5d6c107f5dbd715a03550ab9`。
- 按当前要求未运行测试、静态检查、Gradle/APK 构建、CI 或 Android 真机验证；提交后的源码只做了 GitHub 内容回读。
## 2026-11-07 — DNS 聚合统计持久设置、内存缓冲与源码树同步

- DNS 聚合统计设置独立于逐条查询日志：新增本地启用开关与轮转周期配置（1h–8760h、1d–365d），Root 后端提供读写命令与事务写入；AdGuard Home 渲染器将其实际写入 `statistics.enabled` / `statistics.interval`，并在配置契约中校验两个字段。
- 原生 Ad 页面增加聚合统计数据库设置入口；统计开关与轮转周期加入 DNS 快照导出/导入字段、变更预览和恢复确认。旧快照缺少新字段时采用关闭统计/10d 默认值，保留旧版快照兼容。
- 修正 DNS 统计 Shell 输出中的双重反斜杠换行，确保 `STATISTICS_ENABLED` 与 `STATISTICS_INTERVAL` 作为独立响应行供 UI / 配置渲染器读取；成功写入响应也输出真实换行。
- DNS 查询日志内存缓冲动态上限不再使用固定 `10000` 回退；`/proc/meminfo` 无法提供物理内存时明确返回不可用，拒绝伪造设备上限。模块 Root getter 同步使用已读取的动态上限返回 `memory_max`。
- 原生缓冲设置 UI 严格检查响应协议头、重复/未知字段与设备动态上限；内存上限缺失时停止编辑，不再套用固定默认值。
- 同步模块与普通源码的内存 getter 顺序、UI 换行转义及 DNS 服务器 IPv4 端口说明，减少打包后行为偏差。
- 主要提交：`1eb7b4021b9c900ae89087053783965e7005f3d3`、`46af65512053fa9ed3ec7b432bc39f66cdaa3874`、`7e00ce77fb3abf8c08f44c6f6b9cf3b064d0d316`、`8304362a0e8b46fe147a2c721fbd7eab2c9f571b`、`0b7f592840c6bee633012c96bcf86b8544e2bd3c`、`e1199db3e6a84036d682966047fee479dfbb5baf`、`e0179e3218a322ae61ac4eed221449d78577c7ce`、`227b660e46c91b10268f6920d2ad3ab1061a8acd`。
- 已回读普通源码与模块打包源码：统计响应协议、统计 YAML 注入、统计设置 UI、快照字段、动态内存上限均存在；未运行测试、静态检查、Gradle/APK 构建、CI 或 Android 真机验证。
## 2026-11-07 — Unbound CPU worker 参数贯通

- 将 Unbound worker 线程数从固定运行配置改为 FX 可配置项。Root 后端读取、写入和快照恢复 `UNBOUND_NUM_THREADS`；设置值必须为正整数，且不得超过设备当前在线 CPU 核心数。
- `fx-module/scripts/unbound.sh` 在渲染最终 `unbound.conf` 时读取 Root 配置，校验线程数和当前在线核心数，并将实际数值写入 `num-threads`；不再固定写为 1。
- 原生 Ad 设置页新增 Unbound worker 线程输入，读取/保存命令已接通；DNS 配置快照新增该字段，旧快照缺少时采用 1 线程默认值。
- 同步普通 APK 源码与 `fx-module/` APK 源码；同步模块 Root 控制脚本与 Unbound 生命周期脚本。并保留并行协作者已完成的 CPU 上限状态读回字段。
- 相关源码提交：模块 Root `1894abb7a97b53c88c965890328494ee1f298b75`；Unbound 最终配置 `9a44cbef3c2a10c14194ea4396781f4bdb3c4356`；原生 APK 源码 `26b21880683be90a572bed8e9a862111431b1bf6`、`c9ff73e864c48b3085ff4785a6388edd047ca9d7`；CPU 上限读回协作提交 `5fbfa5282ea0c6bee633012c96bcf86b8544e2bd3c`、`5978db35fb85`。
- 本阶段按用户要求未运行测试、静态检查、构建、CI 或 Android 真机验证；已完成 GitHub 源码写入与内容回读，不代表实际设备验收。

## 2026-11-07 — Unbound CPU 自适应工作线程 UI 与快照闭环

- 普通源码和 FX 模块打包源码均已包含 Unbound 工作线程参数 `UNBOUND_NUM_THREADS`；Root 后端从设备在线 CPU 集合读取核心数，校验线程数为正整数且不得超过当前在线核心数。
- 原生 Ad 页面读取 `UNBOUND_NUM_THREADS` 与 `UNBOUND_THREADS_MAX`，显示当前线程数和设备在线核心数；保存前按读取到的动态上限校验，Root 写入时再次校验，防止 CPU 热插拔或读取后状态变化导致超限配置落盘。
- DNS 配置快照纳入 `UNBOUND_NUM_THREADS`；旧快照缺少该字段时补默认值 `1`，新快照预览显示线程数，Root 恢复阶段继续执行设备在线核心数校验。
- 对齐两个 Java 源码树，普通源码与 `fx-module` 打包源码内容一致。
- 相关实现提交：后端同步 `26b21880683b` / `c9ff73e864c4`；普通与模块 UI/快照 `2ba7e94a9252d33f4eb74445d6ca52e768f315b0` / `19933b8729f6c6376c0a2ea11cd56bf21e84333f`。
- 同步纳入并保留近期 DNS 统计排除域名后端/UI与 `statistics.ignored` 渲染；同时已移除快照固定字段数量门槛，使用字段白名单、去重、必需字段及旧字段默认值来判断格式。
- 本批未运行测试、静态检查、Gradle/APK 构建、CI 或 Android 真机验证；GitHub 文件回读确认两套 Java 源码一致，后端和 AdGuard renderer 对应文件均包含上述字段。
## 2026-11-07 — DNS 两类排除列表状态可观测性

- 逐条查询日志排除域名与聚合统计排除域名仍是两套独立配置：分别控制 AdGuard Home `querylog.ignored_enabled`/`querylog.ignored` 和 `statistics.ignored_enabled`/`statistics.ignored`，不会改变 DNS 拦截/放行。
- `scripts/native-dns-settings.sh` 与 `fx-module/scripts/native-dns-settings.sh` 的 DNS 状态响应新增四项字段：逐条日志排除开关/域名数量、聚合统计排除开关/域名数量。响应只返回开关与数量，不返回域名明细，避免在状态面扩大域名信息暴露。
- canonical 与模块原生 Ad 页面同步加入四项状态字段白名单与展示；两套 `native-dns-settings.sh` 与两套 `FxYulongAdActivity.java` 回读内容一致。
- 提交：状态后端 `64ee78ee099c5d0f37cd904602212c3ac005b6be` / `128fa5a813d788940cdbfef02a818ab603399a0d`；响应行结束符修正 `c9b5e64d88a31185f59c034488133d8f54aa5580` / `f1e394f2850042973afea78248abb971ab69d389`；原生状态页 `ce5ffad75e85eea9b86f02d0d7a4a8de4e5b0e45` / `020b8fe88f1ad66edc4010af367ef2c380bdcd3a`。
- 本批只进行了 GitHub 源码回读，未运行测试、静态检查、Gradle/APK 构建、CI 或 Android 真机验证。
## 2026-11-07 — DNS 查询日志大文件流式导出

- 原有“分享全部筛选结果”将完整查询日志文本放进 Android `Intent.EXTRA_TEXT`；在大日志场景可能受 Binder/跨进程事务体积限制，不能作为完整日志的可靠导出通道。
- 原生 DNS 查询日志页新增“保存筛选结果为文件”：调用系统 `ACTION_CREATE_DOCUMENT` 文件保存器，随后在后台工作线程中以 UTF-8/TSV 逐条写入当前全部筛选匹配记录，不将完整导出内容放入 Intent，也不受页面 50 条显示分页影响。
- 导出包含当前搜索词、拦截状态、时间范围、RR 类型及响应码筛选元数据；记录字段清理制表符/换行，避免破坏 TSV 列结构。导出使用 SAF 输出流，不依赖私有共享目录或外部存储权限。
- 同步正式 APK 源码与 `fx-module/` 打包源码；源码提交：`709446e6ea0eea86dc2e67aaa15d6a1e8f5dffb7`、`79ded82ee998b1ac0d2f6adc2f549cb284ede0d5`。
- 按当前要求未运行测试、静态检查、Gradle/APK 构建、CI 或 Android 真机验证；完成的是源码写入，不代表大日志设备实测。


## 2026-11-07 — DNS 汇总统计修复无轮转日志输入

- 修复 DNS 汇总统计脚本在仅有活动 `querylog.json`、尚无 `querylog.json.*` 轮转文件时，将未匹配通配符作为字面路径传给 AWK，导致统计报错的问题。
- 两套脚本在逐项完成路径组件、符号链接及普通文件检查后，使用 POSIX shell 位置参数构建实际日志输入列表；AWK 只接收真实存在且已通过检查的日志文件，兼容只有活动日志、活动加轮转日志及空日志目录。
- 保留对所有活动/轮转日志的完整聚合、畸形 JSONL fail-closed 和不输出域名/客户端 IP 的隐私行为。
- 同步文件：`scripts/yulong-ad-dns-summary.sh`、`fx-module/scripts/yulong-ad-dns-summary.sh`。
- 本批代码提交：`eeb8c956ca1d47005fe4fcbef70c2ab3e45e9d4e`。
- 按当前要求未运行脚本、测试、静态检查、构建、CI 或 Android 真机验证；本次仅进行源码修改与 GitHub 提交。


## 2026-11-07 — DNS 重写 UI 与快照换行协议收尾

- 对 DNS 重写编辑器及快照链路统一修复 Java 换行协议：批量订阅导入、DNS 快照文本标准化、导入差异行、DNS 状态摘要均写入真正的换行字符；快照头检查与实际标准化换行保持一致。
- 修复 DNS 查询日志 TSV 导出字段清理中的换行/回车字符字面量，避免将多字符 char literal 留在 Java 源码中。
- DNS 地址重写贯通 Root 持久化、AdGuard Home `filtering.rewrites` 运行时渲染、原生编辑/清空入口、DNS 快照导出/导入/预览/恢复；规则数量不设应用层上限，由 Root 后端整批校验和原子写入。
- 同步正式源码与模块打包源码，并更新两份续接记录。
- 按当前提速要求未运行测试、静态检查、Gradle/APK 构建、CI 或 Android 真机验证；本批仅完成源码提交。


## 2026-11-07 — Root Proxy VPN egress 周期重验证与同接口自动重绑

- 扩展现有 yulong-root-proxy-package-watch.sh，不新增第二个并行 watcher：每个既有 watcher 周期除检查应用包名/UID 集合外，还调用 Root Proxy 的 reconcile-route。
- Root Proxy 新增 reconcile-route 锁内路径：验证当前记录的 VPN 接口、UID、egress IPv4、活动双栈 NAT OUTPUT 跳转、链内 root/VPN UID/白名单 UID/loopback/UDP+TCP 53 规则及本地 DNS 探测。
- 同一 VPN 接口的 egress 地址发生变化时，重新运行完整 _ensure_locked，更新 Unbound outgoing-interface 与 VPN egress marker，并轮换双栈 DNS 重定向链；未变化且所有链路仍符合预期时仅回报 rebind=unchanged，不反复重启解析器或重建规则。
- 路由不可证明、DNS 探测失败或链条不完整时，走现有 fail-open/事务恢复路径；不能确认当前接口身份时不会猜测并接管另一个接口。该机制覆盖同一已验证接口上的地址/路由变化，不把未知新接口当作已验证 VPN。
- canonical/module Root 控制脚本均新增 rootproxy-reconcile-route；原生“VPN 与 Root Proxy”页新增手动重验证/重绑入口与状态回显。
- 修改：fx-module/scripts/yulong-root-proxy.sh、fx-module/scripts/yulong-root-proxy-package-watch.sh、两份 scripts/yulong-ad-control.sh、两份 FxYulongAdActivity.java。
- 按用户提速要求未运行测试、Shell/Java 静态检查、构建、CI 或 Android 真机验证；源码提交不代表实际 VPN 路由或设备验收。


## 2026-11-07 — Unbound DNSSEC 信任锚状态与安全手动维护

- fx-module/scripts/unbound.sh 新增 anchor-status、anchor-refresh 操作；状态接口以 FXYUNBOUNDANCHOR1 返回 trust anchor 有效性、文件字节数、14 天陈旧状态、VPN 绑定出口状态和 Unbound 运行状态。
- 手动刷新走 Unbound 生命周期锁，要求已有有效 root.key、解析器当前停止、没有 VPN egress 绑定，并要求系统具备 timeout。刷新最多等待 5 秒；helper 失败或 DNSKEY seed 校验失败时原子恢复原 trust anchor；回滚不能确认时保留恢复副本并拒绝报告成功。
- Root 控制接口新增 unbound-anchor-status 与 unbound-anchor-refresh；两个原生 Ad 页面新增 DNSSEC 根信任锚状态卡片与手动维护入口。正常运行中的 Unbound 继续通过 RFC5011 在线维护，不要求人为停止解析服务。
- 修改文件：fx-module/scripts/unbound.sh、两份 scripts/yulong-ad-control.sh、两份 FxYulongAdActivity.java。
- 按用户当前提速要求未运行 Shell/Java 测试、静态检查、构建、CI 或 Android 真机验证；本批仅完成源码移植及双源码同步。


## 2026-11-07 — DNSSEC Root Hints 完整性与文件流式分享

- Unbound 信任锚状态协议升级为 `FXYUNBOUNDANCHOR2`，在 root.key 的有效性/大小/陈旧状态之外，追加 Root Hints 文件状态与字节数；通过现有私有路径检查和 SHA-256 sidecar 校验判断 `root.hints` 的有效性、缺失、损坏或不安全状态。
- 原生 DNSSEC 状态卡片同步展示 Root Hints 完整性，避免只看到 DNSKEY anchor 而忽略递归 DNS 根提示文件。
- DNS 快照“分享”从 `Intent.EXTRA_TEXT` 改为系统 `ACTION_CREATE_DOCUMENT` 写入文件后，以 `EXTRA_STREAM` + `ClipData` URI 权限打开分享面板；完整配置不再进入 Binder 文本事务，保留另一个独立的“保存到文件”入口。
- 按提速要求未运行测试、静态检查、构建、CI 或 Android 真机验证；本批仅完成源码修改及文档同步。


## 2026-11-07 — DNS 全链路只读诊断面板

- Root 控制命令新增 `dns-diagnose`，读取原生 DNS 栈状态并执行本地回环 DNS 查询：Unbound `127.0.0.1:5353`、AdGuard Home `127.0.0.1:53` 与 `[::1]:53`。只对已启用的解析服务执行相应探测；组件未启用时返回 disabled，探测器缺失时返回 unavailable。
- 诊断同时汇总 DNS 栈就绪标志/原因、本地 DNS watchdog 状态、VPN 共存判定、VPN 路由探测与 Android 私有 DNS 模式。响应使用 `FXYULONGDNSDIAG1` 固定字段协议，不包含域名查询明细、客户端 IP 或私有 DNS 主机名。
- 原生 Ad 页面新增“执行完整 DNS 链路诊断”入口，严格检查协议头、字段白名单、重复/缺失字段和枚举值。诊断不修改配置、不重启服务、不操作第三方 VPN 或改写路由。
- 同步正式/模块 Root 脚本、两套 APK 原生页面和 watchdog 使用说明。
- 按用户要求未运行 Shell/Java 测试、静态检查、构建、CI 或真机验证；本轮仅完成源码移植与提交。


## 2026-11-07 — DNS 拦截响应自定义地址与 TTL 完整接入

- DNS 拦截响应从 NXDOMAIN / REFUSED / 固定空地址扩展为可自定义 A 记录 IPv4、AAAA 记录 IPv6 以及 blocked-response TTL（uint32 秒，允许 0）。Root 后端校验 IPv4/IPv6 字面量、TTL 数值、配置 section 唯一性，并通过原子写入保存四项设置。
- 原有 `dns-response-set MODE` 命令保持兼容：只修改模式并保留地址和 TTL；新增 `dns-response-config-set MODE IPV4 IPV6 TTL` 支持完整设置。
- AdGuard Home 运行配置生成现在读取 Root `FXYULONGDNSRESP1` 响应，将自定义地址写入 `filtering.blocking_ipv4` / `blocking_ipv6`，将 TTL 写入 `filtering.blocked_response_ttl`；不再硬编码固定空地址和 10 秒。
- 原生 DNS 设置页新增三项编辑控件、响应协议检查、读取回显和保存入口；DNS 配置快照导出/导入/字段差异预览/恢复加入 `RESPONSE_IPV4`、`RESPONSE_IPV6`、`RESPONSE_TTL`，旧版快照缺少字段时自动回填原默认值。
- 同步普通源码与 FX 模块 Root/AdGuard renderer、两份原生 APK 源码。
- 按用户当前提速要求未运行测试、静态检查、构建、CI 或 Android 真机验证；本批为代码移植与接线提交，不代表设备验收。


## 2026-11-07 — AdGuard Home DNS 拦截响应运行配置契约

- 将运行配置校验器扩展到 FX DNS response profile：必须且只能有一项合法 blocking_mode 和一项 blocked_response_ttl；TTL 必须为 uint32（允许 0）。
- custom_ip 模式必须同时存在唯一且合法的 blocking_ipv4 / blocking_ipv6；NXDOMAIN / REFUSED 模式不得意外携带自定义地址字段，避免模板残留地址改变解析响应。
- 校验值与 Root 持久化读取、运行 YAML 注入一致；缺失、重复、格式错误或模式/地址组合不一致的配置拒绝启动/发布。
- 同步 `scripts/adguardhome.sh` 与 `fx-module/scripts/adguardhome.sh`。
- 按用户要求未运行脚本测试、静态检查、构建、CI 或设备验证；本轮只更新源码和续接记录。


## 2026-11-07 — DNS 查询日志分享统一改为文件 URI

- 移除 DNS 查询日志“分享全部筛选结果”将全部记录拼成 `Intent.EXTRA_TEXT` 并一次性跨进程传输的路径；分享按钮现在与文件导出共用系统 `ACTION_CREATE_DOCUMENT`，在后台逐条以 UTF-8/TSV 写入用户选定文件。
- 写入成功后通过 `Intent.EXTRA_STREAM`、`ClipData` 和 `FLAG_GRANT_READ_URI_PERMISSION` 分享文件 URI；不将原始日志正文装进 Intent，不受 Binder 文本事务大小影响。用户只保存文件时仍使用原有独立入口。
- 取消、写入失败、后台队列繁忙及分享面板不可用均清理待处理状态并给出对应提示；只分享当前搜索/状态/时间/RR 类型/响应码筛选匹配的全部记录，不受列表 50 条显示分页限制。
- 同步普通 APK 与 `fx-module/` 原生 DNS 日志页面。
- 按用户要求未运行测试、构建、静态检查、CI 或真机验证；本轮仅提交源码与续接记录。


## 2026-11-07 — Unbound Root Hints 状态函数重复片段修复

- 最新源码回读发现 `anchor-status` 升级到 `FXYUNBOUNDANCHOR2` 时，旧版本 `else/fi` 分支与状态输出块被重复拼接在函数结束符之后，形成悬空 Shell 控制结构。
- 删除重复片段，保留一套完整的 root.key 状态、Root Hints SHA-256 sidecar 校验、VPN egress 状态和 Unbound 进程状态输出；不改变 `anchor-refresh` 手动维护保护、生命周期锁或运行时配置。
- 修改：`fx-module/scripts/unbound.sh`；同步更新两份续接文档。
- 按用户要求未运行 Shell 语法检查、测试、构建、CI 或真机验证；这是基于源码回读发现的结构性修复，尚不能宣称 Shell 执行通过。


## 2026-11-07 — DNS response 构建补丁器契约防回退

- 两份 `patch_yulong_dns_upstreams.py` 显式识别新版 Root DNS response adapter：只有同时存在 `dns-response-get`、IPv4、IPv6 和 TTL 字段读取时，才将目标识别为动态 response contract 并跳过旧版固定值注入。
- 继续兼容带 `FX_YULONG_DNS_RESPONSE_BEGIN` 标记的既有补丁结果；构建补丁器不会因新版 renderer 缺少旧式配置锚点而尝试重新写入固定空地址或 10 秒 TTL。
- 同步 canonical 与 fx-module 构建 patcher 源码。
- 本批未运行 patcher、测试、构建、CI 或设备验证；只做源码接线与提交。


## 2026-11-07 — ProtectionProfile 名称与 HTTPS 来源长度限制移除

- 移除 `yulong-profiles.sh` 配置档名称 96 字节与 HTTPS 来源 URL 2048 字节的应用层硬上限；配置档 ID 格式、HTTPS/builtin 协议约束、分隔符/换行拒绝、Base64 与配置写入结构保持不变。
- 自定义 ProtectionProfile 可保留更长名称及完整有效 HTTPS 订阅地址，不再在写入前被人为字节阈值拒绝。
- 同步 `scripts/yulong-profiles.sh` 与 `fx-module/scripts/yulong-profiles.sh`。
- 按用户要求未运行测试、静态检查、构建、CI 或设备验证；本轮仅修改和提交源码。


## 2026-11-07 — DNS 全链路诊断升级到 DIAG2

- DNS 诊断报告在原有进程/回环探测、watchdog、VPN 共存和 Android 私有 DNS 信息之外，增加当前上游模式、上游配置状态、加密上游 bootstrap、故障回退、DNSSEC trust anchor 状态、Root Hints SHA-256 完整性状态与文件大小。
- Root 后端从 `native-dns-settings.sh status` 只读采集上游/回退状态，并复用 Unbound `anchor-status` 读取信任锚及 Root Hints 完整性；异常或缺失数据统一降级为 `unknown`，不把未知状态报告为正常。
- 原生 Ad 页面协议升级到 `FXYULONGDNSDIAG2`，同步严格字段白名单、值校验和报告显示；修正 Root Hints 状态卡片换行显示。
- 同步正式 APK 源码与模块打包源码、Root 控制脚本及两份续接文档。
- 按当前要求未运行测试、静态检查、构建、CI 或 Android 真机验证；本批仅完成源码修改和 GitHub 提交。


## 2026-11-07 — Unbound Root Hints 安全手动更新闭环

- fx-module/scripts/unbound.sh 新增 root-hints-refresh：通过 HTTPS 获取 InterNIC named.root（IANA Root Files 官方页面所链接的文件），限时 25 秒；要求 Unbound 已停止且不存在 VPN egress marker。
- 下载内容通过 A–M 13 个根服务器 NS/A 记录结构校验；SHA-256 sidecar 与 Root Hints 同目录发布。发布后再次校验，任何步骤失败均尝试恢复原文件与 sidecar；回滚不完整时保留恢复副本并返回失败。
- _check_files 与 Root Hints 状态检查复用 13 个 root NS/A 结构校验，不再将 A/M 根服务器当前 IPv4 地址写死在代码中；状态仍保留 SHA-256 sidecar 比对。
- 两份 yulong-ad-control.sh 新增 unbound-root-hints-refresh；两份 FxYulongAdActivity.java 增加更新按钮、限制说明与更新后状态刷新。
- 安全边界：本批依赖 HTTPS/TLS 证书链和文件结构校验，不执行 PGP detached-signature 校验；不在 Unbound 运行或 VPN egress 绑定时更新，不修改第三方 VPN、系统 DNS 或用户上游配置。
- 按用户要求未运行 Shell/Java 测试、静态检查、构建、CI 或 Android 真机验证。

## 2026-11-07 — SafeSearch / YouTube 配置档运行契约

- AdGuard Home `_config_contract()` 检查 `filtering.safe_search` 区段唯一、字段完整且无未知字段；Bing、DuckDuckGo、Ecosia、Google、Pixabay、Yandex 和 YouTube 的布尔值必须与 Root `settings.conf` 中的 ProtectionProfile 状态一致。
- `safe_search.enabled` 必须等于 SafeSearch 与 YouTube 受限模式的逻辑或；启用状态缺字段、渲染不一致或错误降级时，运行配置契约会拒绝报告 DNS 服务就绪。
- 历史安装缺少 Profile flag 时按关闭处理；默认 YAML 的关闭状态仍为有效值。
- 同步 `scripts/adguardhome.sh` 与 `fx-module/scripts/adguardhome.sh`。
- 按用户要求未运行脚本测试、静态检查、构建、CI 或设备验证；本轮仅完成源码提交。


## 2026-11-07 — DNS 全链路诊断扩展到全部运行参数

- `dns-diagnose` 响应升级为 `FXYULONGDNSDIAG3`，除 DNS/VPN 共存与本地 IPv4/IPv6 回环探测外，同一只读报告现纳入逐条查询日志开关/保留周期/内存刷盘批量与设备动态上限、聚合统计开关/周期、AdGuard Home 上游策略/超时/缓存容量/TTL/乐观缓存/DNSSEC，以及 Unbound TTL/serve-expired/预取/QNAME minimisation/四类缓存池/线程数与在线核心上限。
- DNSSEC 诊断补入 root.key 文件大小、14 天陈旧状态、Unbound 运行状态与手动刷新出口；Root Hints SHA-256 状态及文件大小继续保留。读取失败或配置响应版本不符的单项以 `unknown` 表示，不阻断其他诊断字段。
- 原生页面同步升级协议白名单、字段完整性、数值/枚举/时长校验，并按日志、统计、AdGuard 缓存、Unbound 递归参数、DNSSEC 分组展示。仍为只读报告，不修改配置、不重启服务、不改写 VPN 或 DNS 路由。
- 同步正式/模块 Root 控制脚本与两份原生 Ad 页面。
- 按用户要求未运行测试、Shell/Java 静态检查、构建、CI 或 Android 真机验证；本次仅完成源码接线与续接记录。


## 2026-11-07 — Root Hints 状态结构校验与刷新回执闭环

- Root Hints 状态接口现在同时要求 SHA-256 sidecar 匹配和 A–M 13 个根服务器 NS/A 结构校验通过，避免仅有正确 checksum、实际 root hints 记录却不完整时误报 valid。
- 手动更新命令在正常状态字段后附带可选 `root_hints_refresh=updated`；原生状态解析白名单允许该可选回执，并在状态卡片显示“最近操作：Root Hints 已更新”，不会再把成功回执误报为未知字段。
- 同步普通与模块 APK 的 FxYulongAdActivity；Unbound 生命周期结构校验、启动前检查和更新后验证继续复用同一 `_root_hints_valid` 函数。
- 本批未运行测试、静态检查、构建、CI 或真机验证。

## 2026-11-07 — 本地 DNS 诊断报告文件导出

- 原生 DNS 页面“执行完整 DNS 链路诊断”在显示报告后新增“保存报告到文件”；通过系统 ACTION_CREATE_DOCUMENT 保存 UTF-8 文本，文件名带本地时间戳，不把报告正文放进跨进程 Intent 文本参数。
- 导出内容复用既有 `FXYULONGDNSDIAG3` 已校验诊断报告，包含引擎状态、IPv4/IPv6 回环探测、上游/Bootstrap/Fallback 配置状态、VPN 共存/路由判定、DNSSEC/Root Hints 完整性、缓存与查询日志参数；不包含查询域名、客户端 IP 或原始查询日志。
- 保存请求单独记录 pending 数据；取消、目标 URI 缺失、Activity Result 迟到/内容丢失、文件流失败均明确报错并清空待处理内容，不报告虚假的保存成功。
- 修改文件：正式与模块 APK 的两份 `FxYulongAdActivity.java`。
- 本批未运行 Java/Gradle 测试、静态检查、构建、CI 或 Android 真机验证。