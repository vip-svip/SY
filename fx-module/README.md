# PrivacyGuard 隐私卫士

## v1.10.70 审计修复

- 移除 WebUI 分应用代理选择器中的静态演示应用清单（包括常见第三方应用与 `com.example.app`）。
- 离线/演示模式下应用列表保持为空，并明确说明未连接设备应用列表后端；不再允许通过虚构列表选择并保存包名。
- bridge 模式仍以 `scripts/applist.sh` 的真实输出为唯一应用列表来源；无输出时显示读取失败/权限不足提示。
- 验证范围：静态 JavaScript 解析、关键分支断言、Shell 语法、Go 单元测试与 ZIP 完整性；未在 OnePlus 12 上验证实际包管理器权限及分应用代理流量接管。


## v1.10.69 审计修复

- 修复 WebUI 代理订阅导入在演示/离线模式下生成并持久化合成节点的问题。现在未连接真实后端时只提示未执行拉取，不创建订阅记录、不写入节点配置。真实桥接下拉取失败仍保持错误提示，不会伪造节点。
- 静态检查不能证明设备端代理核心、网络连通或所有 UI 功能均已生效；相关功能仍需真机验证。


内核级 (KernelSU / Magisk / APatch) 隐私防护模块，内置 WebUI 配置面板，可选 LSPosed 扩展（应用层 70+ Hook，源码完整，见 `lsposed/`）。

## 功能架构

```
settings.conf（唯一配置源）
  ├─ post-fs-data.sh   开机早期：hosts 挂载 + resetprop 属性伪装
  ├─ service.sh        开机后期：首次生成配置 + 后台应用
  ├─ scripts/apply.sh  核心执行器（WebUI「应用」按钮 / action.sh 调用）
  │    ├─ Hosts：订阅下载 → 规则/遥测域名库/FX 合并 → 白名单剔除 → bind mount
  │    ├─ 防火墙：iptables PGUARD 链（filter）+ PGNAT 链（nat）
  │    ├─ Sysctl：TCP 指纹/ICMP/重定向防护
  │    ├─ 系统设置：settings put（广告 ID/AGPS/ANR/崩溃上报）
  │    ├─ SELinux：k_sysfs/k_read deny 规则（sepolicy.rule，管理器开机自动加载）
  │    └─ Wi-Fi MAC 伪装 / Root 痕迹遮蔽 / logcat 静音
  └─ lsposed/          可选 LSPosed 扩展（应用层 Hook）
```

## WebUI

KernelSU / APatch / Magisk（Delta）的 WebUI 均可直接打开（`webroot/index.html`）。
无管理器环境（浏览器直接打开）自动进入**演示模式**：所有操作存 localStorage，界面完整可用。

- 121 个开关全部持久化到 `settings.conf`
- 规则/域名/黑名单/脚本/Hook/FX 六个列表增删改、启停、导出（ZIP）
- v1.10.9 起：内置规则集 / 内置 FX / 本地 hosts 均可点开**文件视图分页编辑器**（一次一页 ≤100 行，逐行修改/插入/删除；大文件不再卡死），逐行改动写入用户副本，原内置文件不动、名字保留（见「v1.10.9」一节）
- 内置根证书子模块管理（MITM + HTTPS 根，独立子模块；**默认不启用**，启用后进入系统信任区，可随时禁用/移除）
- 状态卡片实时显示：管理器 / Root / LSPosed / 规则数 / 防火墙状态
- 配置整体导入导出（settings.conf 或代理 App 配置识别）
- 根证书管理：内置 CA 的启用/禁用/移除（WebUI pageAd「根证书管理」；默认不启用，避免浏览器/银行类 App 报“自定义根证书/风险证书”警告）

> 说明：本模块**只管理系统级信任区**，从不主动读写用户证书区（`/data/misc/user/0/cacerts-added`）。早期版本曾有「扫描/禁用用户 CA」功能（v1.7.x 及以前），已移除——它需要把用户证书移来移去，风险大于收益。安装时 `certmgr.sh cleanup` 只卸旧覆盖层、清暂存区并**原样保留**隔离区，绝不写用户证书区；只有**卸载**时 `uninstall.sh` 显式执行 `cleanup restore`，才把 ≤v1.7 被移走的证书原样移回用户 CA 目录（用户数据不丢）。检测 MITM 请用系统「设置 → 安全 → 加密与凭据 → 信任的凭据 → 用户」标签页。

## 内置根证书子模块（v1.7.0；v1.10.4 起默认不启用）

模块自带两张自签根 CA（2049 年到期，`BasicConstraints: cA=TRUE` + `KeyUsage: keyCertSign`），安装时以**独立子模块**释放到 `/data/adb/modules/`，但**默认不启用**（不写系统信任区，避免被安全软件/银行类 App 判为“存在自定义根证书”）。需要受控 MITM 检测实验时，在 WebUI『根证书管理』点『启用』，才会经 magic-mount 进入 `/system/etc/security/cacerts`；Android 14+ 另在开机早期（`post-fs-data`）bind-mount 覆盖 `/apex/com.android.conscrypt/cacerts`（Conscrypt 实际读取处），对之后启动的应用生效。启用状态会记住，升级/重装保持。

| CA | 子模块 id | 指纹(SHA256 前16) | 用途 |
|---|---|---|---|
| PrivacyGuard MITM Detection CA | `pg_mitm_ca` | `3cd7fe0549eaae30` | 导入抓包工具签发叶子证书，配合模块自身的 MITM 检测做受控实验 |
| PrivacyGuard HTTPS Root CA | `pg_https_ca` | `1a9960b9339b31a5` | 自签 HTTPS 站点证书备用根 |

- **双哈希命名**：每张 CA 以 MD5 旧版（`67bddb03.0`/`b6d831c3.0`）+ 当前证书 SHA1 subject hash（`6d4b9443.0`/`2fef94b4.0`）双文件落盘；具体哈希必须与本包 PEM 一致，不能照抄其他版本的证书哈希。`certmgr.sh` 在有 openssl 时按证书重算，在无 openssl 时按 `ca-index` 并校验指纹自愈文件名
- **启用即时生效**：启用后 `certmgr.sh builtin sync` 用 bind-mount 覆盖层把合并后的信任区盖到 `/system/etc/security/cacerts`（Android 14+ 为 APEX 覆盖层）；已运行的进程可能仍读缓存，重启或重开应用后确定生效
- **即时摘除**：WebUI「禁用/移除」当场更新覆盖层（A14+ 覆盖层就绪时）；管理器里也能像普通模块一样单独禁用 `pg_mitm_ca`/`pg_https_ca`
- **卸载干净**：主模块卸载时 `builtin purge` 删除两个子模块并解除挂载，用户自装证书不受影响
- **历史残留清理**：`certmgr.sh cleanup` 卸掉旧 live 覆盖层、删暂存区，**默认保留** ≤v1.7 隔离区（`certs-quarantine`）文件原样、绝不写用户证书区；仅 `cleanup restore`（卸载时执行）把隔离区证书移回用户 CA 目录，`cleanup purge` 才删除
- **本候选包不包含 CA 私钥或 `.p12` 文件**。公开根证书只建立信任，不能单独签发叶子证书，也不提供 HTTPS 解密

WebUI 入口：pageAd「根证书管理」→「内置 CA」。命令行：`sh scripts/certmgr.sh builtin list|enable|disable|remove|purge|sync`，残留清理 `sh scripts/certmgr.sh cleanup [restore|purge]`。

### 浏览器/App 报“证书错误/连接不是私密连接”怎么办

v1.10.4 起按以下顺序排查（本模块的系统 CA **默认不启用**）：

1. **确认已启用并重启**：WebUI『根证书管理 → 内置 CA』状态应为「系统级信任中」；显示「已启用但未生效」说明 Android 14+ 的 APEX 覆盖层未挂上，重启或点『应用』后重试，日志见 `apply.log` / `early.log`。
2. **确认 Android 14+ 的 APEX 信任库**（应用实际读取处）含本模块 CA 文件：
   `su -c 'ls /apex/com.android.conscrypt/cacerts | grep -Ei "9f0c946f|b6d831c3|3eefd1d9|67bddb03"'`
   （`2fef94b4`/`6d4b9443` 为当前 PEM 计算出的 subject_hash，`b6d831c3`/`67bddb03` 为 subject_hash_old；若更换证书，需同步更新索引与文件名。）
3. **抓 logcat 定位**：`adb logcat -d | grep -iE 'CertPathValidator|TrustAnchor|SSLHandshake|CertificateException|ERR_CERT'`。
4. **“网络可能被监控”字样不是本模块系统 CA 触发的**：该提示来自 Android 对**用户安装的 CA** 或 **VPN** 的固有通知；请检查是否装过用户证书（`/data/misc/user/0/cacerts-added`）或 VPN 处于开启状态。
5. 实验完请在 WebUI 点『禁用』或『移除』；本模块默认不会留下系统级自定义根证书。

## 后端功能矩阵（shell 层）

| 分类 | 开关（data-key） | 实现方式 |
|---|---|---|
| DNS/Hosts | dns_block, hosts_block, custom_dns, global_dns, dot_enforce, block_dot, block_plain_dns, dns_leak | hosts 生成 + PGUARD 端口规则 + PGNAT DNAT |
| 广告/追踪 | block_track_domains, geo_domains, privacy_leak, app_info, app_list_upload, usage_upload, diag_upload, waf_block | 内置可编辑域名库并入 hosts |
| 防火墙 | block_quic, block_stun, block_ipv6, block_multicast, conn_guard, ip_block, mitm_block, echo_blackhole, hook_block | iptables PGUARD 链 |
| 泄露防护 | ip_leak, block_webrtc_leak, vpn_leak, net_privacy, loc_leak, isp_snoop | STUN/SSDP/mDNS/NetBIOS/SUPL/TR-069 端口封禁 + sysctl 防重定向 |
| 代理 | transparent_proxy, proxy_autoswitch | PGNAT tcp 80/443 DNAT（autoswitch 仅 Wi-Fi 下生效） |
| VPN 透明接管 | vpn_mode(global/rule/direct), vpn_cn_direct, vpn_lan_direct, vpn_ipv6, vpn_udp_block, vpn_app_proxy, vpn_dns_hijack, vpn_killswitch, vpn_auto_update, vpn_auto_pick, **vpn_hide** | PGVPN/PGKS/PGVPN6/PGBLK6/PGHIDE/PGHKS/PGMTU 链（nat+filter+mangle），chnroute 分流，分应用 UID 匹配，fail-closed；vpn_hide=1 时 DNS 全劫持+QUIC/STUN/本地痕迹端口封锁+TCP 指纹规范化（hide_level 分级） |
| 网络指纹 | disable_tcp_timestamps, hide_tcp_fingerprint, disable_icmp, random_src_port, block_udp_tracking, echo_blackhole, block_sepolicy_logs | sysctl |
| 系统设置 | ad_id_unify, anr_off, crash_upload_off, block_agps, block_wifi_scan, disable_passive_loc, block_logcat | settings put / setprop |
| 设备伪装 | hide_bl_status, hide_kernel_debug, hide_magisk, hide_ksu, props_random, patch_spoof, spoof_model/manufacturer/version/brand/hardware/baseband/fingerprint, boot_time_spoof, spoof_wifi_mac | resetprop / ip link |
| Root 遮蔽 | hide_su, block_rootcheck_libs | bind mount 空文件 |
| FX 规则 | fx（总开关）+ FX 列表 | DOMAIN→hosts, IP-CIDR→防火墙 |

### 订阅/FX 规则语法支持矩阵（后端实际消费）

WebUI `ruleTypeOf` 可识别 33 种语法。**v1.10.5 起新增两条消费路径**：除了原来的「hosts / iptables」，
VPN 接管模式下（`vpn_mode=rule|global`）会由 `scripts/vpnrule.sh` 把可表达的语法**编译成 sing-box 路由规则**，
真正按规则分流。下表按「实际落到哪一层」标注（真机 sing-box 1.14.3 逐条 `check` + 真实分流验证）：

| 语法 | 消费路径 | 状态 |
|---|---|---|
| HOSTS 格式 `0.0.0.0 domain` | hosts + 路由 `domain_suffix` | ✅ |
| DOMAIN / HOST（精确） | hosts + 路由 `domain` | ✅ |
| DOMAIN-SUFFIX / HOST-SUFFIX | hosts + 路由 `domain_suffix` | ✅ |
| DOMAIN-KEYWORD / HOST-KEYWORD | hosts（近似）+ 路由 `domain_keyword` | ✅ |
| DOMAIN-REGEX | 路由 `domain_regex`（须合法正则；不在 hosts 层） | ✅ |
| DOMAIN-WILDCARD / HOST-WILDCARD | hosts（剥离 `*` 取裸域） | ✅ |
| ADBLOCK `\|\|domain^` | hosts | ✅ |
| ADBLOCK 例外 `@@\|\|domain^` | 白名单剔除管线 | ✅ |
| IP-CIDR / IP-CIDR6 / MIXED-IP-CIDR | PGUARD 链 DROP + 路由 `ip_cidr` | ✅ |
| **PROCESS-NAME** | 路由 `process_name`（匹配**可执行文件基名**，如 `curl`→`/system/bin/curl`）；`PACKAGE-NAME` → `package_name`（匹配 Android 包名）。两者**不可互换** | ⚠️ 编译但当前不命中 |
| **SRC-PORT / DST-PORT**（含 `1000-2000` 区间） | 路由 `source_port`/`port`（区间→`port_range`） | ✅ |
| **PROTOCOL**（http/tls/quic…） | 路由 `protocol`（**依赖 sniff** 还原协议） | ✅ |
| **NETWORK**（tcp/udp） | 路由 `network` | ✅ |
| **RULE-SET** | 路由 `rule_set`（仅本地规则集文件；远程 .srs 需先下载） | ✅ 本地 |
| **AND / OR / NOT** | 路由 `type:"logical"` + `mode` + `invert`（支持嵌套括号） | ✅ |
| **MATCH / FINAL** | 路由 `route.final`（映射 direct/proxy） | ✅ |
| **REJECT** 策略 | 路由 `{"action":"reject","method":"drop"}` | ✅ |
| GEOIP / GEOSITE | 上游已废弃：`geoip database is deprecated ... removed in 1.12.0`（`check` 即 FATAL） | ❌ 移除 |
| URL-REGEX | 需 L7 解密拿完整 URL；1.14.3 `route.rules` 无此字段（`unknown field "url_regex"`） | ❌ 不支持 |
| USER-AGENT | 需 L7 解密读 HTTP 头（`unknown field "user_agent"`） | ❌ 不支持 |
| IP-ASN | 上游已移除 ASN 数据库（`unknown field "ip_asn"`） | ❌ 不支持 |
| MITM | 需 CA 中间人解密，与 iptables/redirect 转发是两套机制 | ❌ 不支持 |

**编译器的安全设计（为什么不会把 VPN 弄挂）**：
- 不可表达的语法一律 `SKIP:<TYPE>` 计数并记日志，**绝不写进 JSON**——写一个 `unknown field` 会让
  `sing-box run` 直接 FATAL，整个 VPN 挂掉。
- 生成后**逐条过真机 `sing-box check`**，任一规则不被接受就单条剔除（宁可少一条规则，不能让配置起不来）。
- 静态预校验：端口必须 1..65535（`port:99999` 会 decode FATAL）、区间必须 `a:b`、正则必须合法、
  CIDR 必须合法、`logical` 的 `mode` 只能 `and`/`or` 且 `rules` 不能为空。
- **`check` 抓不到、只在 `run` 炸的坑**（已实测并规避）：`route.final` 必须是真实 outbound tag
  （`final:"reject"` → run FATAL）；`rule_set` 引用的文件必须真实存在且 `format` 与内容匹配；
  `outbound:"nosuch"` check 通过但永不命中，按静态校验拒绝。
- 规则顺序固定：`sniff` → 用户规则 → `ip_is_private` 直连兜底，`route.final` 按 MATCH/FINAL。
- **前提**：规则只在 VPN 接管模式生效；`vpn_mode=direct` 不接管任何流量，规则自然不参与。
- **UDP 相关限制**：`redirect` 入站只处理 TCP，所以 `NETWORK,udp` / `PROTOCOL,quic` 类规则在当前
  架构下不会命中（QUIC 另由 `block_quic` 在 filter 层 REJECT 迫使回落 TCP）。
- **PROCESS-NAME / PACKAGE-NAME 限制（⚠️ 真机实测）**：这两类规则依赖 `route.find_process` 拿到
  客户端进程，而 **`redirect` 入站下进程查找必然失败**——内核按「源IP:源端口 ↔ 目的IP:目的端口」
  在 `/proc/net/tcp` 反查 socket，但 REDIRECT 已把目的地址改写成 `127.0.0.1:<端口>`，而 sing-box
  手里是 `SO_ORIGINAL_DST` 还原出的**原始目的地址**，两边对不上 → 日志 `failed to search process:
  process not found`，规则**永不命中**（对照：同一配置换成 `socks` 入站则正常
  `found process path: /system/bin/curl, user id: 2000`）。因此这类规则**能编译、能过 check，但当前
  架构下不生效**，与 UDP 限制同类。另外两者语义不可互换：`process_name` 匹配可执行文件基名
  （`curl` 命中 `/system/bin/curl`，但写路径形式不命中），`package_name` 匹配 Android 包名
  （`com.android.shell`）；把包名写进 `process_name` 不命中。规则语法按原样映射，不做自动转换。

### 本地 hosts 与订阅规则（v1.10.8）

`hosts` 产物里的条目来自**两类来源**，现在分开管理、并在产物里标注出处：

| 来源 | 编辑位置 | 是否经网络 | 产物里的分节注释 |
|---|---|---|---|
| **订阅规则集** | WebUI 规则页「规则集」卡片（`[list:rule]` 里的 URL 行） | 是，下载后解析 | `# --- 订阅来源 ---` |
| **本地 hosts** | WebUI 规则页「本地 hosts」卡片（`[list:hosts_local]`） | 否，本机手写 | `# --- 本地 hosts（[list:hosts_local]，用户手写，未经网络下载）---` |
| 老格式手写行 | 仍在 `[list:rule]` 里（非 URL 的裸行，**兼容保留**） | 否 | `# --- 手写规则行（[list:rule] 中的非 URL 条目）---` |

- 「本地 hosts」支持三种写法：`0.0.0.0 ads.example.com`、`127.0.0.1 tracker.example.net`、
  裸域名 `blockme.example.org`（自动补 `0.0.0.0`）。改完点「应用」立即生效，不触发任何下载。
- **向后兼容**：老 `settings.conf` 里 `[list:rule]` 中的非 URL 裸行继续生效（不会被迁移或删除），
  用户可自行搬到「本地 hosts」卡片；两处并存不冲突（产物里会各自成段）。
- `vpn_mode=direct` 时 VPN 分流规则不参与，但 **hosts 拦截仍然生效**（hosts 由 bind mount 提供，
  与代理模式无关）。

### 内置规则文件（历史记录与当前包状态）

当前 FX 1.0.0 包内包含独立的 `fxrules/anti_fraud_96110.txt`，来源为私有仓库 `vip-svip/FX` 的 `FX.txt`，仅筛选“国家反诈中心”域名和“反诈中心”标注的 IP 列表，并保留唯一明确的国家反诈中心 App 包名规则。它不导入 `com.android.packageinstaller`、OEM 通用安全中心，也不将 `mps.gov.cn` / `miit.gov.cn` 等宽泛站点混入 FX 规则库。通用开屏/下载提示与网页 DOM 水印仍在 `rulefiles/`，不属于 FX。

**外部 VPN 的 DNS 安全边界：**检测到第三方 VPN 隧道后，FX 会停用自己的透明 DNS/NAT 接管，同时跳过通用明文 DNS 锁定，避免只封系统/DHCP DNS 却不提供重定向导致全局解析失败。此时 DNS 泄露控制由第三方 VPN 自己负责；FX 不宣称能验证或替外部 VPN 接管 DNS。

**边界与风险：**仓库来源没有独立的 96110 域名条目；96110 是电话专线，DNS/IP 规则不能阻止蜂窝电话本身。源文件列出的 IP 地址沿用其“反诈中心”标签，但本项目没有逐 IP 独立核验其当前归属，且 IP 可能变更或共享，可能误拦截其它服务。FX 总开关默认关闭，用户主动开启才应用。开启 FX 且关闭通用 hosts 过滤时，模块会使用只包含系统 hosts 基线、用户本地 hosts 与 FX 域名的独立 hosts 视图，不会顺带启用 Ad/隐私/订阅黑名单。`fxfile://<id>` 缺少源文件时仍记录 `SKIP:FXFILE`，不会伪装成已生效。VPN 路由编译器同样受全局 `fx` 主开关控制；关闭时不应在 sing-box 配置中保留 FX 规则。hosts 挂载改为区分本模块拥有、第三方拥有和未挂载三态，应用/关闭/启动过程均不得覆盖或卸载第三方 hosts 挂载。动作语义也已统一：FX 的远程规则保留显式目标，空动作按黑名单旧格式补 `REJECT`；hosts 与 IP/UID 防火墙只消费拦截动作，不把显式 `DIRECT/PASS` 规则误拦。`PROCESS-NAME` 在当前 sing-box `redirect` 入站无法可靠找到原进程，虽然能被编译，但不能当成真正执行。

### 仅 LSPosed 层生效（shell 层只持久化配置，不改行为）
clipboard, clipboard_isolate, app_list, telephony, mock_location, perapp_mock, gnss_spoof, gps_accuracy, cam_null, cam_hw_hide, mic_block, mic_hw_hide, exif_strip, audio_fp_block, block_mediastore, block_notif_listen, hide_notif_perm, block_ime_logging, a11y_hide, usagestats_off, syssvc_hide, sensor_*, block_cell_info, spoof_android_id/serial/imei/sim/bt_mac/storage/screen/battery, block_kernel_version, block_mounts, hide_mounts, block_net_ifaces, block_netstats, block_pm_query, block_process_list, hide_sysfs_nodes, hide_face_hw, hide_fingerprint_hw, fs_*

### 内核面板 k_* 键的实现路线（免编译优先）

| 键 | 免编译实现（多机型通用） | 说明 |
|---|---|---|
| k_sysfs | SELinux deny 规则注入（sepolicy.rule + magiskpolicy --live / ksud） | 应用读 /sys 全家桶被 SELinux 拒绝 |
| k_read | SELinux deny 规则注入（同上，/proc 与 /proc/cpuinfo） | 应用读内核接口被拒 |
| k_task | LSPosed：ActivityManager 枚举 + /proc 数字 pid 过滤 | 应用进程内进程列表全空 |
| k_netfilter | iptables PGUARD/PGNAT 链（内核 netfilter 钩子用户态编程） | 一直是 shell 层实现，无需编译 |
| ~~k_ioctl~~ | 已从 UI 移除（seccomp-bpf 可拦一部分 ioctl，但检测类应用走 ptrace/io_uring 的无法用户态覆盖，真正的拦截需定制内核） | — |
| k_stack | sysctl 降级路线：kptr_restrict=2 / dmesg_restrict=1 / perf_event_paranoid=3（apply.sh 按 [conf:k_stack] 写入，首次开启记录原值、关闭时恢复） | 隐藏内核指针/日志/性能计数三大泄露途径；完全随机化（CONFIG_RANDOMIZE_KSTACK_OFFSET）仍需定制内核 |

> 编译内核方案（GKI 一次编译多机型刷 boot.img）需要解锁 BL、会覆盖 KernelSU/root 补丁，且失去 OTA —— 如今仅剩 k_ioctl 一个键需要它（已从 UI 移除），不建议。

## VPN 透明接管（v1.8.0+，内置自动核心）

本模块**默认自带自动核心**（v1.9.0 起）：`vpn_core=1` 时若检测到 `[conf:vpn] local_ip:local_port`（默认 `127.0.0.1:7890`）无监听，会按架构选择核心二进制——`bin/arm64/sing-box` 与 `bin/arm/sing-box` **随模块内置（离线可用）**；`amd64`/`386`（x86 模拟器/少数设备）无内置时按 `core_ver`（默认 `1.14.3`）从 GitHub SagerNet/sing-box release 下载。随后把 `[list:vpn_node]` 里的节点编译成 sing-box 配置（mixed 入站 + DNS + selector 出站 + 大陆/内网直连路由）并拉起进程。v1.10.4 起启动前先跑 `sing-box check` 预检，配置/核心错误会把 sing-box stderr 写进 `apply.log` 并由 WebUI 报错带出（旧版只有一句“核心启动失败”）。**导入订阅/节点链接即可用，无需另外装客户端。**

仍兼容自建客户端：`vpn_core=0`（或 WebUI「自动核心」关闭）时沿用你自行运行的 sing-box / Clash（监听 `127.0.0.1:7890`），本模块用 iptables **透明接管**把设备流量送进去。两种路径共用同一套接管/分流/防漏/隐藏逻辑。WebUI 首个标签页即「VPN」：

| 能力 | 说明 |
|---|---|
| 自动核心 | `vpn_core=1`（默认）：无监听 → 启动 sing-box（`core_auto=1`，`core_ver`/`core_bin` 可配；arm64/arm 二进制内置、amd64/386 联网下载；支持 vmess/vless(+Reality)/trojan/ss/hysteria2/tuic/anytls/socks5 节点 → sing-box outbound；启动前 `sing-box check` 预检）；`vpn_core=0` 或 `core_auto=0` 时不自启、只用自建核心；状态卡「核心」格与 `status.sh` 的 `vpn_core`/`vpn_core_pid` 字段显示运行态 |
| 三种模式 | `global`（全局代理）/ `rule`（chnroute 中国大陆 IP 直连、其余代理）/ `direct`（关闭接管） |
| 订阅 | URL 导入（自动识别 vmess/vless/trojan/ss/ssr/hysteria/hysteria2/tuic/anytls/socks5 URI、Base64 订阅、Clash YAML `proxies:` 段）、本地文件导入（大文件分块读取，不整段过桥层）、单节点链接粘贴；节点可删可停用，更新订阅不丢手动选择 |
| 自动选优 | **订阅驱动**（非按钮）：`vpn_auto_pick=1` 时每次订阅更新自动对全部节点测速（`curl telnet` 握手耗时），达到 `[conf:vpn] pick_min_ms`(默认 80ms) 才切换，全部不可达则保留当前节点；参数可在面板编辑 |
| 自动更新 | `vpn_auto_update=1` 时 service.sh 定时轮询（间隔 `auto_update_h` 小时，默认 24），只拉取不盲切 |
| 分流 | `vpn_cn_direct`（rule 模式，chnroute 列表自动下载，iptables-restore 批量注入、无则逐条降级）、`vpn_lan_direct`（内网三网段可编辑） |
| 分应用 | `vpn_app_proxy=1` 后**从设备已装应用多选**（WebUI 应用选择器，`pm list packages` + 应用名，无需手输包名）；`[conf:vpn] app_mode=only`（仅选中应用走代理）/ `bypass`（选中应用不走） |
| DNS | `vpn_dns_hijack` 劫持 53 到本地客户端；`remote_dns`/`cn_dns` 写入客户端配置 |
| 防漏 | PGKS 链：放行本地端口与节点出口 IP → `ESTABLISHED` → QUIC(udp443) REJECT（`vpn_udp_block` 全 UDP）→ killswitch（uid 10000:19999 REJECT 但 CN/LAN/Meta ACCEPT）；`vpn_ipv6=0` 时 IPv6 全断（PGBLK6）防半通道 |
| 客户端导出 | 选中节点一键生成 Clash YAML / sing-box JSON（含分流/分流组/DNS/混合入口），可直接复制到客户端 |
| 状态卡 | 模式 / 选中节点 / 是否生效（本地端口实测监听）/ 订阅与节点数 / chnroute 段数 |
| **隐藏 VPN/节点** | `vpn_hide=1` 时对外完全伪装成本机直连，对端（网站/服务/检测方）观测到的"本机网络"就是节点出口所在网络，看不到任何代理痕迹（详见下表） |

### 节点与订阅示例（复制即用）

> 下面所有域名、UUID、密码均为**占位示例，不可连通**；使用时替换成你自己的机场/节点即可。订阅正文与节点 URI 的识别逻辑在 `scripts/vpnsub.sh` / `scripts/vpncore.sh`。

**1) 订阅导入**

WebUI「VPN → 代理订阅」输入框粘贴订阅链接，点「导入」（或点「从文件」导入本地订阅/规则文件，`.txt/.yaml/.yml/.conf/.list`）。订阅行格式为：

```text
订阅URL|订阅名|1
```

- 第三字段 `1` = 启用；导入后自动拉取并解析节点，手动选中状态保留。
- 订阅正文自动识别三种格式：① 明文节点 URI（每行一条）；② Base64 订阅（整段或逐行，机场最常见）；③ Clash YAML 的 `proxies:` 段（自动转成节点 URI）。
- 本地订阅正文会落盘到 `/data/adb/privacyguard/subs/`，v1.10.2+ 用分块读取（大文件不整段过桥层，v1.10.4 块大小 8KB→128KB）。本地文件导入上限 **16MB**（超过提示拆分），订阅正文/URL 文件上限 **8MB**（v1.10.4 起；旧版 500/800 行截断已取消）。
- 更新：单条「更新」或「全部更新」；`vpn_auto_update=1` 时 `service.sh` 每 `auto_update_h` 小时自动拉取（默认 24h，只拉取不盲切）。

**2) 单节点导入（每行：节点URI|节点名|0，`1`=当前选中）**

```text
vmess://eyJ2IjoiMiIsInBzIjoiSlAtMDEiLCJhZGQiOiJ2cG4ubm9kZS10ZXN0LmV4YW1wbGUiLCJwb3J0IjoiNDQzIiwiaWQiOiJ1dWlkLTU2NzgiLCJhaWQiOiIwIiwic2N5IjoiYXV0byIsIm5ldCI6IndzIiwiaG9zdCI6InZwbi5ub2RlLXRlc3QuZXhhbXBsZSIsInBhdGgiOiIvd3MiLCJ0bHMiOiJ0bHMiLCJzbmkiOiJ2cG4ubm9kZS10ZXN0LmV4YW1wbGUifQ==|VMess-ws|0
vless://uuid-1234@vpn.node-test.example:443?security=tls&sni=vpn.node-test.example&type=ws&path=%2Fws|VLESS-ws|0
vless://uuid-9999@reality.example.com:443?security=reality&sni=www.microsoft.com&fp=chrome&pbk=abcdefghijklmnopqrstuvwxyz012345&sid=1234|VLESS-Reality|0
trojan://pw123@tj.example.com:443?sni=tj.example.com|Trojan|0
ss://YWVzLTI1Ni1nY206c2VjcmV0MTIz@ss.example.com:8388|SS-SIP002|0
hysteria2://pw456@hy2.example.com:443?sni=hy2.example.com|Hysteria2|0
tuic://uuid-tuic:pw-tuic@tuic.example.com:443?sni=tuic.example.com&alpn=h3&congestion_control=bbr|TUIC-v5|0
anytls://pw-any@any.example.com:443?sni=any.example.com&insecure=1|AnyTLS|0
socks5://sk.example.com:1080|SOCKS5|0
```

- 支持的 URI 协议：`vmess://`、`vless://`（ws / grpc / TLS / Reality）、`trojan://`、`ss://`（SIP002 与旧式 base64）、`hysteria2://`（含 `hysteria://` 别名）、`tuic://`、`anytls://`、`socks5://`；`ssr://` 不支持，导入时自动跳过并计数。
- 节点名：可取 URI 的 `#片段`，也可写在第二字段（第二字段优先）。
- VLESS Reality：`security=reality` + `pbk`（服务端公钥，base64url）+ `sid`（short id）+ `fp`（指纹，如 `chrome`）+ `sni`（伪装域名）必须与节点提供方一致；`insecure=1` 仅用于自签证书调试。
- SOCKS5：v1.10.4 起内核侧支持 `socks5://user:pass@host:port` 认证（用户名/密码会写入 outbound）；但 WebUI 节点编辑/回填仍可能丢掉认证字段，导入带认证节点后请核对 `settings.conf` 的 `vpn_node=` 行，必要时手改（后续版本会补 UI 回填）。
- 导入完成后在「节点」卡选中节点 → `vpn_node=` 写入 `proto:host:port`（供 iptables 放行与状态卡显示），点「应用」生效。

**3) 排错**

- 核心启动失败：WebUI「日志」看 `apply.log`；v1.10.4 起启动前会跑 `sing-box check`，配置错误会带具体字段与行号（旧版只报「核心启动失败」）。
- 导入后节点数 0：确认订阅可访问、内容为上述格式（Clash YAML 必须有 `proxies:`）；个别机场用非标准字段时用单节点导入。
- 自动选优不切换：需 `vpn_auto_pick=1` 且实测延迟 ≥ `pick_min_ms`（默认 80ms）；全部不可达时保留当前节点。

### 隐藏 VPN/节点（vpn_hide）

目标：让对端认为"我用的节点的地方就是我的 IP"——出口 IP、DNS 出口、网络特征三者全部收敛到节点所在地，无 VPN/代理痕迹。

| 层 | 措施 | 对应检测手段 |
|---|---|---|
| shell（apply.sh） | `vpn_hide=1` 时强制 **DNS 全劫持**（udp+tcp 53 → DNAT 到 `[conf:vpn] remote_dns`，不经代理的 CN/LAN 直连流量也用远端解析，避免 DNS 查询出口暴露所在地）；**QUIC(udp443)/STUN(3478/3479/5349/19302-19305)/mDNS(5353)/SSDP(1900)/NetBIOS(137-139) 全断**；**封锁代理客户端本地痕迹端口**（7890-7894/1080/1081/1085/1086/1090/8080-8082/9090/9150/3128 等，仅放行本模块 REDIRECT 目标端口）；`vpn_ipv6=0` 时 IPv6 强制全断（防真实 v6 地址段与节点所在地不一致） | DNS 泄露、WebRTC/STUN 探测真实 IP、QUIC 绕过代理直连、本地端口扫描发现代理客户端、IPv6 半通道 |
| LSPosed（MainHook `vpnHide`） | `NetworkInterface.getNetworkInterfaces/getNetworkInterfacesList` **过滤 tun/ppp/ipsec/wg/vpn/tap 虚拟网卡**；`NetworkCapabilities.hasTransport(TRANSPORT_VPN)`→false、`hasCapability(NET_CAPABILITY_NOT_VPN)`→true、`toString()` 去 VPN 字样；`ConnectivityManager.getNetworkCapabilities` 改写传输类型为 WIFI；`VpnService.prepare` 返回 null；`/proc/net/tcp|udp|tcp6|udp6` 读取时**删除代理客户端本地端口所在行**（端口集合含 `[conf:vpn] local_port`，由 gen_xposed_conf.sh 透传）；`/proc/net/route|ipv6_route` 删除 Iface 列为虚拟网卡的行；`PackageManager.getInstalledPackages/getInstalledApplications` **过滤已知代理客户端包名**（clash/mihomo/v2ray/xray/singbox/sing-box/shadowsocks/surfboard/surge/trojan/hysteria/naiveproxy/nekoray/v2rayng/ssr）；`SystemProperties.get("http.proxyHost")`→空；`TrafficStats.getUidRxBytes/getUidTxBytes` 对 uid≥10000 归零 | 网卡枚举、`TRANSPORT_VPN`/`NOT_VPN` 能力查询、`VpnService` 痕迹枚举、`/proc/net` 端口连接与默认路由痕迹、已装代理 App 枚举、系统代理属性、per-uid 流量计数 |
| 状态 | WebUI VPN 状态卡「隐藏」格：未开启 / 已开启未生效 / **已生效（对端视同本机直连）**（含强度 L1/L2）；`status.sh` 输出 `vpn_hide`/`vpn_hide_on`/`vpn_hide_level` 三个字段 | — |

**隐藏强度分级**（`[conf:vpn] hide_level` + 4 个增强键，WebUI「VPN → 配置与工具 → 隐藏强度」一行设置）：

| 档位 | 包含措施 | 适用 |
|---|---|---|
| L0（hide_level=0） | 仅 LSPosed 层网卡/能力/VpnService/proc 痕迹隐藏（无 shell 规则、无 TCP 指纹改动） | 只想隐藏"是否在用 VPN"、不想改网络行为 |
| L1（默认，hide_level=1） | L0 + **DNS 全劫持**（PGHIDE DNAT 到 remote_dns）+ QUIC/STUN/mDNS/SSDP/NetBIOS 全断 + 代理痕迹端口封锁 + IPv6 强制全断 + **TCP 时间戳关闭**（net.ipv4.tcp_timestamps=0，抓包方看不到 timestamps/TSval 指纹） | 默认：伪装彻底且不影响正常使用 |
| L2（hide_level=2） | L1 + **ICMP echo 全禁**（net.ipv4.icmp_echo_ignore_all=1，防 traceroute/存活探测暴露链路）+ **UDP 全禁**（uid 10000:19999 强制 TCP，DNS 已被 DNAT 不受影响）+ **DoT(853) 禁**（防绕过本模块 DNS 全劫持）+ **TCP MSS clamp 1380**（mangle PGMTU，抹掉节点链路 MTU 特征） | 对抗深度流量分析的强场景；会阻断 traceroute/部分 QUIC-only 与 UDP 业务，游戏/语音类应用慎用 |

四个增强键（`hide_icmp_block_all`/`hide_udp_block_all`/`hide_dot_block`/`hide_mtu_clamp`）也可在 `[conf:vpn]` 单独设为 1/0 细粒度组合；hide_level=2 时全部置 1，hide_level=1 时全部置 0（L1 行为向后兼容旧配置）。

**fail-closed**：`vpn_killswitch=1` 且本地端口无监听（客户端没起来）时，PGKS 会直接断开应用外联——宁可断网也不漏明文。关闭该开关则为 fail-open（仅记日志）。

> 与其他 VPN App 的关系：若你**不启用**本模块的 VPN 接管（默认 `vpn_mode=direct`），本模块不占任何 VPN 槽位、不动你的代理 App——但注意 `dns_leak`/`block_quic` 默认开启会拦截代理 App 的明文 DNS 与 QUIC 外层（见共存表）。

## LSPosed 扩展（已内置编译好的 APK）

模块自带**已签名的 Hook APK**（`optional/PrivacyGuardHook.apk`，apksigner 实测 v2+v3 签名有效；`META-INF/` 内另有历史 v1 JAR 签名残留，Android 7+ 安装不受影响，装模块即部署）：设备装有 LSPosed 时，在 LSPosed 管理器中启用「PrivacyGuard Hook」并勾选目标应用作用域即可，无需自行编译。

应用层 Hook 覆盖上表「仅 LSPosed 层生效」全部键 + 部分双层键（hide_magisk/hide_ksu/hide_su/block_rootcheck_libs/block_logcat/fs_vfs/block_mounts/hide_mounts/hide_sysfs_nodes 等 Java 层加固），共 **70+ 开关键**。Hook 读取 `/data/local/tmp/privacyguard/xposed.conf`（每次「应用」自动重新生成，含 39 个 conf 段）。

> v1.9.0 的 APK **已用当前 `MainHook.java` 重新编译并签名**（含 `vpnHide` 的 8 类检测：虚拟网卡枚举过滤、`TRANSPORT_VPN`/`NOT_VPN` 能力改写、`VpnService.prepare` 置空、`/proc/net/tcp|udp` 代理端口行删除、`/proc/net/route` 虚拟网卡行删除、代理 App 包名过滤、`http.proxyHost` 置空、per-uid 流量归零），证书指纹与旧版一致（SHA-256 `4534952c…`）可覆盖升级。构建链路：`javac`（android-34 平台 jar + xposed-api-82）+ `D8`（R8 8.2.42，min-api 27）→ 换入 `classes.dex` → `zipalign` + `apksigner`（v2/v3，keystore 同旧版）。

源码在 `lsposed/`（同版本构建），构建方式见 `lsposed/README.md`：`cd lsposed && gradle :app:assembleRelease`。

## 真实性验证（busybox 沙盒测试台）

> 运行器约定：所有 shell 用例都需要把功能桩目录加入 `PATH`（`export PATH="<test-env>/bin:$PATH"`，桩内含 iptables/ip6tables/iptables-restore/netstat/curl/sysctl/settings/setprop/magiskpolicy/mount 等），并用 `PGPORT_PROBE_<port>=1` 显式告知「本地代理端口已监听」。缺任一条件时 `apply.sh` 会因探不到监听端口而整体 fail-closed，VPN 断言会误报失败（v1.9.1 排查 `tc10` 时踩过，已由 `run-tc10.sh` 自行配置这两个前置条件）。

`scripts/apply.sh` 不靠"看起来对"——全部执行路径在 busybox-w32 沙盒中实跑验证：iptables/sysctl/settings/setprop/magiskpolicy/mount 等 12 个系统命令替换为记录调用日志的桩，本地 HTTP 服务提供订阅源，7 个用例覆盖：

| 用例 | 覆盖 | 结果 |
|---|---|---|
| tc1 | hosts 管线：订阅下载 → hosts 行/DOMAIN 规则提取 → 垃圾行过滤 → 去重 → 遥测域名库 8 段合并 → 黑名单 → 白名单后缀剔除 | ✅ 41 行，白名单域名正确剔除，`localhost` 保留 |
| tc2 | 防火墙 14 开关：QUIC/STUN/DoT/IPv6/多播/mitm IP/hook 包名→UID 断网/ip_block | ✅ PGUARD 链 78 条规则逐条核对 |
| tc3 | DNS/NAT：custom_dns RETURN(v4+v6, udp+tcp)、udp/53 DNAT 重定向、global_dns 强制、dot_enforce、透明代理+autoswitch | ✅ 重定向目标 IP 正确（曾发现并修复：DNS 提取正则不匹配 `nameserver` 格式的出厂即死 bug） |
| tc4/tc4b | k_stack 开启→快照原值→sysctl 写入→关闭→恢复原值 | ✅ 往返一致，快照文件清理 |
| tc5 | settings put 9 条 / setprop / Wi-Fi MAC 三连 / SELinux deny 9 条 + sepolicy.rule 落盘 | ✅ 调用参数逐条核对 |
| tc1b | 真实订阅 URL、单源下载失败 | ✅ FETCH FAIL 不中断，其余管线照常 |
| tc10/tc10b/tc10c | VPN 三模式：global（DNS 劫持/LAN 直连/分应用 only/bypass/兜底 REDIRECT/PGKS 防漏/killswitch）、rule（chnroute 120 段 iptables-restore 批量注入+CN killswitch 放行）、fail-closed（端口无监听→PGKS 断应用外联） | ✅ 35 项断言全过 |
| tc14 | VPN 全功能：global + 分应用 only + DNS 劫持 + killswitch + 节点出口 IP 放行；关闭分应用后 uid 规则清理为 0；direct 模式 PGVPN 规则清空为 0 | ✅ 三段回归全过 |
| tc15 | **隐藏 VPN/节点**（`vpn_hide=1`）：DNS 全劫持 DNAT 到 remote_dns（PGHIDE 链）、QUIC/STUN/mDNS/SSDP/NetBIOS 封锁、17 个代理痕迹端口封锁（本模块 REDIRECT 目标端口豁免）、IPv6 强制全断（vpn_ipv6=0 时 PGBLK6 追加）、TCP 时间戳关闭、L2 增强（ICMP/UDP 全禁+DoT 禁+MSS clamp 1380）、关闭 vpn_hide 后 PGHIDE/PGHKS/PGMTU 规则清零、status.sh `vpn_hide`/`vpn_hide_on`/`vpn_hide_level` 字段 | ✅ 断言全过 |
| tc11/tc12 | 订阅更新拉取 5 节点 → [list:vpn_node] 段首次创建（曾修复段缺失静默丢节点 bug）；选中节点不在订阅内时不盲切 | ✅ 段写入健壮、选优保留策略正确 |
| tc13 | 应用选择器数据源：applist.sh pm 解析 → 7 行 JSON（中文名/sys 标记） | ✅ 全合法 JSON |
| tc16 | **自动核心**（`vpn_core=1`）：无监听→尝试自动启动并下载 sing-box（沙盒跳过真实下载）；给定核心二进制时生成 sing-box 配置（mixed inbound `127.0.0.1:18081`、selector proxy + node-1、direct、`ip_is_private` 直连路由）并拉起进程；`vpn_core=0` 时 fail-closed 且不自启；已监听时沿用不重复生成；status.sh `vpn_core`/`vpn_core_pid` 字段 | ✅ 23 项断言全过 |

验证过程中发现并修复 5 个真实 bug：DNS IP 提取不认 `nameserver` 格式（3 处）、黑名单单点域名（`doubleclick.net`）漏收、白名单点号未转义+边界缺失、`date +%F` 兼容性、自定义 DNS RETURN 只放行 udp。

后续版本（VPN 与自动选优）又发现并修复：`[list:vpn_node]` 段不存在时订阅节点静默丢失、`app_mode` 取值名不一致（apply 侧写 `proxy`、配置/UI 定义 `only`）、`pg_list_enabled` 把注释示例行误计为启用条目、`ip route` 取接口取到 metric 列（`$NF`）、`vpn_auto_pick` 复用循环变量导致协议名错乱、注释行被段头正则误 split。

### WebUI 桥接模式端到端测试（tabbit 浏览器沙盒）

用浏览器沙盒 mock `window.ksu.exec`（KernelSU WebUI API），对**桥接模式**（此前只测过演示模式）做全链路验证：探测 → 读配置 → 渲染 → 开关点击 → base64 持久化 → 重载 → 应用 → 日志 → 证书检测，24 项断言全过。

WebUI 侧去空壳整改（v1.9.0）：删除全部演示型假 handler，条目内容改为**真实来源**——订阅 URL 条目点开/导出时经 `scripts/subfetch.sh` 真实拉取原文（失败与演示模式明确提示，不伪造内容）、内联条目展示实际存储值；`refreshbtn` 真实重拉并回写时间戳；条目编辑器可写回条目值（单行值=条目值、多行=FX 规则内容）；`data-apply`/`data-preview` 展示 `__lastGen` 真实生成的配置；`import-conf`/四个「导入」按钮统一走真实文件选择器（`pgRealImport`）；pgRenderLists 渲染的真实条目补齐 `✎ 编辑` / `⟳ 刷新` 按钮，与静态演示条目的交互一致。脚本条目在 UI 中如实标注「本模块不在设备上执行第三方脚本，只存储与导出」（安全边界，见下），Hook 条目如实标注其真实生效路径（`hook_block=1` 按包名解析 UID 后 iptables 断网）。

该测试抓出一个**严重 bug**：初始化序列 `pgLoad → pgApplySwitches(→fxApply→saveState→pgSyncLists) → pgRenderLists` 中，`fxApply` 内部调用 `saveState` 会把 HTML 里遗留的**静态演示条目**（AdAway/StevenBlack 等预置占位数据）回写进 `settings.conf`——真机上首次打开 WebUI 后 600ms 内，用户的真实订阅就会被演示数据静默覆盖。修复：`PGB.ready` 门控（初始化/重载/导入期间禁止 DOM→conf 回写）+ 桥接模式下空列表强制清空 DOM 残留。修复后验证：初始化不再自发写盘、持久化内容保留真实订阅且无演示条目、演示模式交互无回归。

### v1.9.1：修复真机「直接安装显示演示模式、页面不全屏」

**根因（不是没网）**：WebUI 桥检测 `detectBridge()`/`pgExec()` 只支持**同步**形态的 `window.ksu.exec(cmd)`（直接返回 `{errno,stdout,stderr}`）。而 KernelSU npm 包装的 API 是 `exec(cmd, options)` 返回 **Promise**、原生桥是 `exec(cmd, optionsJson, cbName)` **异步回调**——两种形态下同步取值都拿不到 `stdout`，探测恒失败，`PGB.mode` 恒为 `demo`。于是真机上：页面一切正常但状态卡/列表/节点全部来自演示分支，与网络无关。

修复（`webroot/index.html`）：

| 项 | 改动 |
|---|---|
| 桥形态自适配 | 新增 `pgProbeBridge()`/`pgExecRaw()`：一次性探测并记住 `promise` / `sync` / `callback` 三种形态，之后所有命令按该形态执行；callback 形态用 `window[cbName](errno,stdout,stderr)` + 超时兜底，Promise 形态 `.then` 收敛，同步形态直读 |
| 全链 Promise 化 | `pgLoad`/`pgPersistNow`/`pgRefreshStatus`/`btnApply`/`btnReload`/`btnLogs`/CA 管理/订阅刷新/节点测速/核心探测/订阅拉取/应用列表/应用与分流更新/entry 拉取与导出等 20+ 调用点全部改为 Promise 链，不再有「拿到 Promise 当结果用」的同步残留 |
| 永不误判演示模式 | `detectBridge()` 在探测失败但 `window.ksu` 存在时仍判为 bridge（真机不回落 demo）；bridge 下任何拉取失败都明确报「网络不可达/地址无效/脚本无输出」，**绝不伪造节点或订阅内容**；demo 分支只在纯浏览器预览（无 `window.ksu`）时使用 |
| 写盘守卫 | `PGB.loaded` 门控：`pgLoad` 未完成前 `pgPersistNow` 直接返回，避免解析期的自动更新检查用空 model 覆盖真机 `settings.conf` |
| 状态透传 | `pgFillStatus` 改为**无条件**包装（原 `===null` 判断在 VPN 块未解析时永远不成立，导致 `status.sh` 的 `vpn_*` 字段到不了 VPN 卡）；`pgBoot` 在 VPN 块就绪后重刷一次 status，以 sh 侧真实生效态为准 |
| 真机全屏 | `pgEnterFullScreen()`：调 `ksu.fullScreen(true)` + `ksu.enableEdgeToEdge(true)`，并给 `<html>` 加 `pg-full` 类；`.phone`/`.screen` flex 铺满 100vh、`.page` 弹性高度、navbar/topbar/editor 全部适配 `env(safe-area-inset-*)`（详见 v1.9.2 的外壳重构） |
| 其它 | 标题由占位 `show_widget` 改为 `PrivacyGuard · 隐私守卫`；`viewport-fit=cover`；`navigator.getBattery()` 补 `.catch`（消除 unhandledrejection 噪声） |

回归（tabbit 浏览器沙盒，三形态 mock 各跑一遍）：bridge 模式 **18–19 项断言全过**——`pg-full` 生效且 `fullScreen(true)`/`enableEdgeToEdge(true)` 均被调用、`.phone` 在 bridge 模式铺满视口（无 340px 上限；demo 预览时为居中手机框）、状态卡为真实 `KernelSU / v1.9.2 / 41 行`且**不含「演示模式」**、VPN 卡 `全局 / 已生效 · L1 · 对端视同本机直连 / sing-box 运行中 · 1.14.3`、开关点击→base64 落盘含 `k_stack=1`/`[list:rule]`、重载保持、apply.sh 被调用、日志编辑器含 `apply done`、CA 行来自 `certmgr.sh`、订阅导入产出**真实 mock 节点**（`REAL-MOCK-NODE`）且无 `HK-01/JP-01` 演示节点、页面运行期 `page_errors`/`console.error`/tabbit 诊断**全为空**。演示模式回归（core-ui-check 全绿、err-probe 9 步无错误）不退化；`syntax-check.js`：30 个内联 script 块 0 语法错误 + 14 条静态断言全过。

### v1.9.2：外壳重构——窄屏满屏、宽屏居中手机框（保留框内观感）

v1.9.1 把「真机全屏」做成了只有 `pg-full`（仅真机 bridge 模式）才铺满，桌面预览仍是 340px 黑色圆角手机壳且高度固定 520px，观感是「页面被塞在一个小手机模型里」——用户反馈「布局怪」「布局是这样的，不是让你拉伸成那种」「要手机框里面这种显示」。

外壳策略改为**一套 DOM 两种视口表现**（`webroot/index.html:209-220`）：

| 视口 | 表现 |
|---|---|
| 窄屏（<480px，真机 WebView / 手机浏览器） | `.phone`/`.screen` 满屏无黑框，默认就是全屏应用，不依赖 `pg-full`；`.page` 弹性高度、内部滚动；底部导航贴底 |
| 宽屏（≥480px，桌面浏览器预览） | 内容列收成 340px、居中，外面画 28px 圆角深色框 + 阴影（即用户要的「手机框里面这种显示」）；高度撑满视口而不是固定 520px |

卡片留白（左右 14px、圆角 16px）、底部导航、顶栏在两种视口下完全一致，同一套内部布局。`html,body` 补 `height:100%/margin:0/overflow:hidden`，消除 UA 默认 8px 外边距导致的整体偏移与页面级滚动。`pg-full` 块收敛为**只补真机安全区**（`env(safe-area-inset-*)` 给 topbar/navbar/editor/stylepanel）+ 深色背景，外壳铺满已成为默认行为。装饰光晕 `.screen::before/::after` 保持 `display:none`（全屏四角光晕会被误读为布局错误）。

实测（tabbit 412×915 / 707×904 / 1280×900）：412 视口 `.phone` = 412×915（满屏、x=0）、`.page` 高 809、navbar 底 905；707/1280 视口 `.phone` = 340×880 居中（x=184/470）、`.page` 高 758、卡片宽 296；三档均无横向溢出、无页面级滚动、`page_errors`/`console.error` 为空。回归：三形态桥接 mock（callback/promise/sync）全过、`core-ui-check` 演示模式断言全过、`tc10` 35/0、`tc15` 61/0、`tc16` 23/0、`syntax-check` 30 块 0 语法错误 + 14 条静态断言。

### v1.9.3：手机上「显示变小」修好了，顺手修掉「装完没网」

用户反馈两条（2026-10-20）：「在手机上还是怪，显示都变小了」；更早的「没网，直接安装显示演示模式，没全屏显示」。查下来是三个互不相干的问题，v1.9.3 逐条处理。

**一、手机上显示变小（已定性，代码可证）**

v1.9.2 的外壳策略用 CSS 媒体查询 `@media (min-width:480px)` 来猜「宽屏 = 桌面浏览器，窄屏 = 手机」，宽屏就套一个 340px 的手机模型框。但真机 WebView 的 CSS 视口宽度并不等于屏幕物理宽度：平板、折叠屏、系统字体放大、宽视口缩放都会让手机上报 ≥480px。于是**手机上也被套了 340px 的框**，可视内容只剩 ~324px，边距又加厚，观感就是「整体缩小了」。

判断设备类型不能用窗口宽度。v1.9.3 改成：

| 判定依据 | 行为 |
|---|---|
| 处在管理器 WebUI 里（存在 `window.ksu`，`PGB.mode==='bridge'`） | 一律铺满（`pg-full`），绝不套框 |
| 不在管理器里，但 UA 是手机/平板（`pgIsMobileDevice()`：Android / iPhone / iPad / iPod / Mobile / HarmonyOS / Windows Phone，兜底 `maxTouchPoints>0 && 短边<900`） | 一律铺满，绝不套框 |
| 只有在桌面浏览器里调试、且窗口 ≥480px | 才画 340px 手机框（`pg-preview`，仅预览用途） |

判定收敛到新增的 `pgSyncPreviewShell()` 一处，`pgEnterPreview()`/`pgEnterFullScreen()`/`pgBoot()` 全都走它；再挂 `resize` + `orientationchange` 监听（200ms 去抖），旋转屏幕、拖窗口都会重新判定，不会停在错误状态。旧注释里提到但从未实现的 `pgSyncPreviewShell()` 这次真的补上了。

同时 `html.pg-full` 的安全区从纯 `env(safe-area-inset-*)` 改成双兜底 `var(--safe-area-inset-top, env(safe-area-inset-top, 0px))`——因为 KernelSU 的 WebView 是通过 `evaluateJavascript` 注入 CSS 变量 `--safe-area-inset-*` 来传刘海/手势条高度的（见 `manager/.../webui/Insets.kt`），只写 `env()` 在 WebView 里取不到值，顶栏会被状态栏压住。

**二、装完「没网」（两个独立原因，都会被触发）**

| 原因 | 机制 | v1.9.3 修法 |
|---|---|---|
| 系统联网检测域名被黑洞 | `hosts_block=1` + `isp_snoop=1` + `net_privacy=1`（默认全开）会把 `connectivitycheck.gstatic.com`、`connect.rom.miui.com`、`msftconnecttest.com`、`captive.apple.com` 等写进 hosts 指向 `0.0.0.0`。Android 判断「已连接但无法访问互联网」正是请求这些域名，于是系统显示无网络，而实际链路可能是通的 | 新增顶层开关 `hosts_keep=1`（默认开）：内置保留这些联网检测/时间同步域名，另可用 `[conf:hosts_keep]` 自己追加。实现方式是转成域名边界正则追加进现有白名单文件，走原有 `grep -Ev` 剔除逻辑，不动下游 |
| 明文 DNS「只封不转」 | `dns_leak=1`（默认开）会对除 `[conf:custom_dns]` 里 223.5.5.5 / 119.29.29.29 之外的所有 udp/tcp 53 直接 `REJECT`；而 `custom_dns=0`、`global_dns=0` 时 NAT 段的 DNAT 不生效，等于**只封杀、不转发**。手机实际用的 DHCP/运营商 DNS 全被拒 → 真的解析不了 | 新增顶层开关 `dns_forward=1`（默认开）：从 `[conf:custom_dns]`（`custom_dns=1` 时）或 `[conf:global_dns]`（`global_dns=1` 时）取第一个合法 IPv4 作为「可信 DNS」，NAT 段加 udp+tcp/53 的 `DNAT --to-destination`，filter 段先 `RETURN` 放行该地址再封其余。**没有可信 DNS 时直接 fail-open 不封禁**（日志写明原因），绝不猜一个默认 DNS——猜错（比如国外网络被指到国内 DNS）会再次把网络打死 |

实测（busybox 沙盒，`run-tc17.sh` 17/17 通过）：无可用可信 DNS 时 calllog 里没有 `--dport 53 -j REJECT`、没有 DNAT，hosts 里也没有联网检测域名；`custom_dns=1` 时有 `PGNAT -p udp/tcp --dport 53 -j DNAT --to-destination 223.5.5.5`，放行 223.5.5.5/119.29.29.29 后其余 53 仍封；`hosts_keep=0` 对照组里联网检测域名会重新回到 hosts（证明开关有效）。

**三、「直接安装显示演示模式」**——v1.9.1 已修（桥层三形态自适配），v1.9.3 复查未回退。

回归：`tc10` 35/0、`tc15` 61/0、`tc16` 23/0、新增 `tc17`（DNS/hosts）17/0；`syntax-check.js` 30 个内联 script 块 0 语法错误 + **23 条**静态断言；布局回归 `layout-guard.js` 六档视口全过（Android 360/412/600 平板、iPhone 393 均 `pg-preview=false` 且 `.phone` 宽度=视口宽、无横向溢出；桌面 1200 才 `pg-preview=true`、340px 居中；桌面 400 不套框）；三形态桥接 mock（callback/promise/sync）全过，`page_errors` 为空。

> 说明：以上结论全部来自代码与沙盒/浏览器自动化。本机 8 台 Android 模拟器都没有 root（装不上 Magisk/KernelSU/APatch），**无法真机复现**，最终仍需在真机上装一次确认。

### v1.10.4：修复反馈的 4 类问题（核心启动 / 证书警告 / 大列表卡顿 / 节点订阅示例）

用户反馈环境：Android 14+ / arm64 / KernelSU 或 APatch；WebUI 规则数千~数万条、本地导入与订阅正文 >1MB；VPN 使用模块自带 sing-box。逐条定位与修复：

| # | 用户症状 | 根因（证据） | 修复 |
|---|---|---|---|
| 1 | 自带核心启动失败；点「应用」报失败 | ① `vpncore_genconf` 生成**旧版 DNS schema**（`dns.servers[].address`）——sing-box 1.12 弃用、1.14 移除，内置 1.14.3 解析即退出；② trojan 出站 `tls`/`transport` 括号错位（多一个 `}`）生成非法 JSON；③ `vpn_core_ensure` 失败只报一句“核心启动失败”，sing-box stderr 被 `apply.log` 吞掉 | 按内核版本自适应 DNS schema（<1.12 旧格式，≥1.12 `{type:"udp",server}`）；修正 trojan/vless 出站结构；启动前 `sing-box check` 预检并把 stderr 尾部写入 `apply.log`、由 WebUI「启动核心」/「应用」错误里带出；`apply.sh` 的 `vpn-core` 分支补 fd3 透传（否则原因永远到不了前端） |
| 2 | 浏览器/App 证书错误；用户怀疑“用户证书” | ① 历史版本的哈希说明与当前随包 PEM 不一致；实际哈希应由当前证书计算并同步到 `ca-index` 与 `.0` 文件名；② Android 14+ Conscrypt 读 `/apex/com.android.conscrypt/cacerts`，旧版要到 boot_completed 后才同步；③ `ca_selfheal()` 依赖 openssl（真机普遍没有）→ 文件名错误永不修复；④ 默认安装即把两张**私钥公开**的自签 CA 设为系统级信任 | 修正 `ca-index` 与子模块文件名；无 openssl 时用 ca-index+指纹校验自愈；`post-fs-data` 开机早期同步 + APEX 就绪/完整性护栏（不完整覆盖层拒绝挂载，保护公共信任链）；**默认改为不启用**（opt-in，启用状态升级保持）；安装期 `cleanup` 不再写用户证书区（仅卸载显式 `cleanup restore`） |
| 3/4 | 规则几千~几万条时 WebUI 加载不出来/卡死；本地导入 >1MB 卡住 | 每次变更全量 parse→全量 DOM 重建→整份配置 base64 过桥；`saveState` 把 5 个列表整份塞进 localStorage（2.1MB 即超限，50k 直接 quota 失败）；本地文件逐条 `saveState`（2,000 条出现 1,552ms 冻结且只导进 1 条）；`subread.sh` 每块 `wc -c`+`awk` 全量扫（O(n²)） | 模型优先行级变更 + 计数/选中模型化；分块渐进渲染（首屏 ≤120 行，24ms 时间片）；持久化 64KB 分片原子写 + 去重/合帧；localStorage 只存 UI 偏好；本地导入批量去重、取消 500 行截断、16MB 上限；订阅正文分块 8KB→128KB；`subread.sh` 取消逐块全量扫描 |
| 2 | 节点和订阅没有示例 | 默认配置只有占位注释，文档无完整 URI/订阅格式示例 | README 新增「节点与订阅示例（复制即用）」：9 种 URI（vmess/vless/vless-reality/trojan/ss/hysteria2/tuic/anytls/socks5）+ 订阅三种格式（明文 URI/Base64/Clash YAML）+ 排错；`default.conf` 同步补注释示例；WebUI 订阅/节点空态与输入框占位补格式提示，并修复 tuic/anytls 在节点页解析/保存/回填的缺失分支 |

**回归与测量（沙盒/浏览器自动化，非真机）**：全部脚本 `sh -n` 通过；`tc10/tc14/tc15/tc16/tc17` 重跑通过；9 种节点示例经真实 `vpncore_genconf` 生成后 JSON 全部合法；certmgr 沙盒 4 套场景 53 项断言全过（A14+/A13/有无 openssl/APEX 未就绪）；WebUI（headless Chromium，4× CPU 降频，同一套夹具）：50k 规则冷启动 2315→1766ms、DOM 稳定 2689→2214ms、启动长任务 1306+646→131+95+77ms；20k/5k/normal 启动 1326→926 / 677→539 / 619→425ms；单次开关点击 625→约 6ms；本地导入 2,000 条 1,862ms/冻结 1,552ms 且只进 1 条 → 392ms 导入 2,000 条无冻结；20,000 条 1,869ms/只进 1 条 → 渐进 2.98s 导入 20,000 条无 >50ms 长任务；`node --check` 30/30 script 块通过，页面无 console/page error。**仍无 root 真机，最终需真机安装确认。**

> 升级提示：装完打开 WebUI，在「VPN → 自动核心」点一次「启动核心」确认可拉起；证书如仍报错，按上文「浏览器/App 报证书错误怎么办」逐项检查（本版默认不启用系统 CA，不会主动留下自定义根证书）。

### v1.10.5：真机实证修复 6 类问题（代理/证书/闪退/编辑器/订阅/UI）

本轮全部结论均来自**真机**（Redmi 23076RA4BC / Android 13 / arm64 / KernelSU 3.3.1），不再依赖沙盒推断。

| # | 用户症状 | 真机根因（证据） | 修复 |
|---|---|---|---|
| 1 | **「代理功能还是空壳」** | v1.10.4 生成 `inbound type=mixed`，而 `apply.sh` 用 `iptables REDIRECT` 把流量塞进去。mixed 是 HTTP/SOCKS 协议入站，**不识别 `SO_ORIGINAL_DST`**。实测：加 `REDIRECT tcp/80 → mixed 端口` 后 `curl http://example.com` 返回 **HTTP 400**，sing-box 日志 `inbound/mixed: read http request: EOF` —— 所有被接管的连接直接失败 | 改为 sing-box **`redirect` 入站**（7890，接 REDIRECT）+ 保留 `mixed`（7891，供客户端直连）；`route` 里用 1.13+ 规则动作 `{"action":"sniff","sniffer":["http","tls"]}` 还原域名；**PGVPN 链最前插入核心自身豁免**（`-m owner --uid-owner 0`、回环、local_port、管理器 uid），否则核心出站被自己再 REDIRECT 造成回环。真机实测：`curl http://example.com` **200**、`gstatic/generate_204` 204、`https://baidu.com` 200、`bing` 302，全部 0.1–0.5s |
| 2 | **「点应用也会卡死」** | 真机 `sh apply.sh` 耗时 **40s+**：默认两条订阅源（其中 `raw.githubusercontent.com` TLS 被重置 → 单源 20s 超时）+ hosts 生成 10 万行且逐行 fork。WebUI 的「应用」按钮用 `pgExec('sh apply.sh')` **同步等待**这段耗时 | 新增 `apply.sh fast`（只做 iptables/vpn/轻量项，不重抓订阅）；下载并发化/复用未过期缓存；hosts 管线改单进程 awk。真机实测 **fast = 1.41s**（提速 28 倍）；WebUI 改为 detached 后台执行 + 轮询 `apply.log` 真进度 + 可取消 + 超时，`fast` 45s / 全量 180s |
| 3 | **「证书导致 GitHub 闪退」**（用户强调） | **证伪**，但找到两个真会让"证书"搞坏 TLS 的缺陷。① 浏览器崩溃与模块无关：tombstone 显示**模块安装前 6 天**（10-17）就有同签名崩溃（`Chrome_InProcRe` / `libmiui_chromium.so` / 同 pc），共 4 次；证书开/关各 6/8 轮共 **14/14 浏览器存活、0 崩溃**；GitHub TCP443 换 3 个 IP 全超时而 bing/baidu 200 → 网络封锁。② **真缺陷 A（高危）**：`ca_sync`/`cleanup` 里 `while umount; do :; done` 吞掉 EBUSY 后**无条件 `rm -rf` 覆盖层源目录** → 仍生效的 bind mount 变空 → 信任库 0 张 → **全站 `unable to get local issuer certificate`**（真机 100% 复现）。③ **真缺陷 B（高危）**：`ca_selfheal` 用固定临时文件且无锁，并发时把 `ca-index` 写坏/丢行（实测行数 5/11/22/6/**3**，一轮 MITM CA 整行消失） | ① 新增 `scripts/crashreport.sh`（`list`/`show N`/`classify`）：读 tombstone 自动归因，8 个真实 tombstone 分类 **8/8 与事实相符**，输出 `verdict=not_module_related`；② `umount` 后**先验证挂载是否真的卸掉**，仍挂载则保留覆盖层源目录并 WARN（真机验证：EBUSY 场景下信任库 **127 张完好**、bing 302/baidu 200）；③ 临时文件名带 PID + 全局 `mkdir` 原子锁（toybox 无 flock，5s 超时接管）（真机验证：并发 3 个 disable，`ca-index` 稳定 2 行、无锁残留） |
| 4 | **「编辑器卡死」** | 订阅正文被 `edBody.value = txt` 一次性灌进 `<textarea>`（最多 1MB）；4MB 正文实测输入 **2940ms**、最坏滚动 1485ms、**22 条长任务（最大 628ms）** | 按 AdGuard Home 原则**永不把大文本放进可编辑控件**：改为只读分页查看器（200 行/≤64KB 一页，shell 侧 `subread.sh --page` 按行取，前端不持有全文）+ 上一页/下一页/跳转行；≤64KB 才允许「编辑」，超阈值禁用并提示导出。实测 4MB：打开 **16ms**、翻页 25ms、最坏滚动 18ms、**长任务 0 条** |
| 5 | **「订阅导入显示为空不能导入」** | 两个叠加 bug：① `parseSub` 的 Clash 判定正则 `/proxies:\s*$\|^mixed-port:\|^port:/` **缺 `m` 标志**（`^` 只匹配整串开头）+ 真机缓存带 **UTF-8 BOM** → Clash 订阅恒 0 节点；② `[list:vpn_node]` 第 3 字段**三向语义冲突**（`vpnsub.sh` 写"选中"、`pg_list_enabled` 读"启用"、`loadNodes` 读"启用"）→ 真机 5 节点全 `on=0`，UI 用 `if(!e.on)return` 全过滤 → 列表空 | ① `pgStripBom` + `/^(proxies\|mixed-port\|port\|socks-port)\s*:/m` + 全文 URI 兜底；② 第 3 字段统一为**启用位**，"选中"只由顶层 `vpn_node=` 表达；`loadNodes` 去硬过滤、`on` 缺省=启用、历史全 0 数据按全部启用兼容；`saveNodes` 不再丢未选中条目。真机真数据验证：Clash 646B（含 BOM）解析 **3 节点**（旧 0）、b64/明文各 2 节点、5 个全 0 节点载入后 **5 个全在** |
| 6 | **「VPN UI 要重构，参考 karing」** | — | 借鉴其**功能结构**（非抄 UI）：hero 状态总览 → 模式三态 → 订阅 → 节点（搜索/地区分组/延迟排序/批量测速进度）→ 快速配置 → 工具。全部复用现有 `.card/.setrow/.switch` 组件，中文/英文沿用 `vLt`。**非破坏**：关键 id 全保留、133 个 `data-key` 无重复、**直连(direct)默认且完整可用**、手机框居中/真机满屏未回退 |
| 7 | **「脚本订阅要支持 Shadowrocket/Loon/Surge/Stash」** | 模块 shell 层**没有 JS 引擎**，无法执行这些客户端的 `[Script]` JS | 新增 `scripts/modconvert.sh`：解析 `.sgmodule`/`.stoverride`/`.plugin`，把 `[Rule]/[Host]` 的 HOST/DOMAIN-SUFFIX/DOMAIN-KEYWORD/IP-CIDR/ADBLOCK 转成 `[list:rule]`/`[list:block]`/`[list:fx]` 条目，`--list` 人读 / `--emit` 可直接追加 / `--json`。**诚实边界：`[Script]` JS 一律 `SKIP:script`（无法执行）；URL Rewrite/Map Local 属 L7，仅转 reject 子集其余 `SKIP:l7`；MITM hostnames 需用户自行启用 MITM CA** |
| 8 | **「应用/网站闪退」防护** | 13 个破坏性 Hook 默认=1（`block_process_list` 返回空列表→`list.get(0)` NPE、`File.exists`→false、`/proc/mounts`→FileNotFoundException 等）；一旦用户在 LSPosed 勾选普通 App 即破坏其运行 | 新增 `lsposed_profile` 档位：**compat（默认，零破坏）**/standard（仅隐藏 root 痕迹）/aggressive（全开）/custom（按逐键）；`MainHook.on()` 里 profile **优先于**逐键值；69 个 Hook 体全部包 `SafeHook`（异常一律吞掉并记 `XposedBridge.log`，绝不穿给宿主）；`NEVER_HOOK` 跳过 system_server/自身/LSPosed 管理器；支持 `[conf:lsposed_scope]` 白名单；13 个破坏性键默认改 0；**旧配置自动迁移**（幂等补 `lsposed_profile=compat`，不覆盖用户显式设置，带 `.bak.<ts>` 备份） |

**真机实测汇总（本轮）**：18 个脚本 `sh -n` 全通过；30 个内联 script 块 0 语法错；`apply.sh fast` 1410ms；direct 模式 PGVPN/PGVPN6 **0 条规则**且联网正常；`sing-box check` rc=0 且 `run` 真实存活（7890/7891 双端口监听）；redirect 入站端到端 HTTP 200/204 + HTTPS 200/302；`genconf` 生成 `redirect`+`mixed` 双入站、`{"action":"sniff"}`、4~5 节点全进 selector；证书并发/EBUSY 两个高危缺陷修复后行为正确；`crashreport.sh` 8 个 tombstone 归因 100% 正确；profile 5 种输入（compat/standard/aggressive/custom/非法值）全部正确。

**本轮明确证伪的说法**：①「证书导致 GitHub 闪退」—— 崩溃在模块安装前就存在（同签名），14 轮 A/B 无差异，GitHub 失败是网络封锁；②「vpnsub 会毁配置」—— 我曾误报，实际是我测试脚手架的 `awk > tmp && mv` 在空输出时覆盖所致，模块本身三次实验均正常。

> 升级提示：本版建议在 WebUI「VPN」页重新点一次「应用」（走 fast，1~2 秒）；证书默认仍不启用，如需 MITM 检测实验再手动启用并在实验后禁用；升级后旧配置会自动补 `lsposed_profile=compat`（LSPosed 层不再有破坏性 Hook，勾选普通 App 不会改变其行为）。

### v1.10.6：规则语法编译进内核路由（PROCESS-NAME / PORT / PROTOCOL / NETWORK / RULE-SET / AND·OR·NOT / MATCH 等）

**背景**：用户问「URL-REGEX / USER-AGENT / PROCESS-NAME / MITM / IP-ASN / SRC·DST-PORT / PROTOCOL / NETWORK / RULE-SET / AND·OR·NOT / MATCH / FINAL 补上没」。答案是：v1.10.5 之前**没补**——WebUI 能识别标签，但 `apply.sh` 只消费 HOSTS/DOMAIN*/ADBLOCK/IP-CIDR（写 hosts 或 iptables），其余当垃圾行丢弃。

**v1.10.6 补上可表达的部分**，原因是 v1.10.5 把代理改成 `redirect` + `sniff` 后，能从 REDIRECT 过来的纯 IP 连接里还原域名/协议，于是这批语法可以编译成 sing-box 路由规则真正生效。

新增 `scripts/vpnrule.sh`（Clash/FX 规则 → sing-box `route.rules` 编译器），真机 1.14.3 验证：

| 结果 | 语法 |
|---|---|
| ✅ **已编译生效** | DOMAIN / DOMAIN-SUFFIX / DOMAIN-KEYWORD / DOMAIN-REGEX / HOST* / IP-CIDR / IP-CIDR6 / PROCESS-NAME / **PACKAGE-NAME** / **SRC-PORT·DST-PORT**（含 `1000-2000` 区间）/ **PROTOCOL** / **NETWORK** / **RULE-SET**（本地文件）/ **AND·OR·NOT**（嵌套括号）/ **MATCH·FINAL**（→`route.final`）/ REJECT（→`action:"reject","method":"drop"`） |
| ❌ **明确不支持** | URL-REGEX、USER-AGENT（需 L7 解密，1.14.3 是 `unknown field`）、IP-ASN（上游移除 ASN 库）、GEOIP/GEOSITE（1.12 废弃，`check` 即 FATAL）、MITM（需 CA 解密） |

**真机验证（不是"能解析"，是"真的在指挥流量"）**：
```
构造：DOMAIN-SUFFIX,example.com → direct ; 其余 → 死 socks(127.0.0.1:1)
  curl http://example.com  → 200 (0.67s)     ← 规则命中，走 direct
  curl http://neverssl.com → 000 超时        ← 未命中，走死 outbound
```
- 23 条覆盖全部语法的测试集 → **16 条编译成功 / 6 条正确 SKIP**。
- 编译产物喂真机 `sing-box check` → **rc=0**；真实 `run` → **核心存活无 FATAL**。
- `genconf` 产出的 route 段包含全部用户规则，顺序为 `sniff` → 用户规则 → `ip_is_private` 兜底。

**安全性设计（为什么不会把 VPN 弄挂）**：不可表达的语法只 `SKIP` 计数、绝不写进 JSON（一个 `unknown field` 会让 run 直接 FATAL）；生成后逐条过真机 `sing-box check`，任一不被接受就单条剔除；静态预校验端口范围（`port:99999` 会 decode FATAL）、区间格式、正则合法性、CIDR、`logical` 的 `mode`/非空 `rules`。

**本轮踩到并修掉的 4 个实现坑**（都是真机专属）：
1. **mksh 的 extglob**：`${var#*(}` 里 `*(` 被当 extglob 起点 → `no closing quote`，并把后续 `esac` 吃掉，报成 `syntax error: unmatched 'case'`。改用 awk/sed 剥括号。
2. **toybox `printf '\037'` 不生效** → 字段拆分静默失败。改用 `|` 作 IFS + `set --`。
3. **settings.conf 的 UTF-8 BOM** 让 `^\[list:rule\]` 匹配不到 → 整段规则被丢（与「订阅导入为空」同源）。已加剥 BOM。
4. **`cmd | while read` 的子 shell 变量丢失** + 分组重定向里的变量作用域，导致规则数统计不对。

**升级提示**：规则在 VPN 接管模式（`vpn_mode=rule|global`）下才生效；`direct` 模式不接管、规则自然不参与。UDP 类规则（`NETWORK,udp` / `PROTOCOL,quic`）在当前 `redirect`（仅 TCP）架构下不会命中。

### v1.10.7：UI 内容放大（导航不变）+ 规则页可见订阅报错 + RULE-SET 补全

**① 内容整体放大，底部导航尺寸不变**（用户原话：「底部 tap 大小不变，把其它的内容显示效果放大啊，太小了」）
- 用 CSS 变量 `--ui-fs-boost` / `--ui-space-boost` 集中控制，改一处即可整体调节；
  正文/标题/副标题/条目/按钮/徽标/面板/编辑器/状态卡统一放大 1~2px 字号、加大行距与内边距。
- **底部导航 `.navbar` / `.nav-item` / `svg` 尺寸被显式锁死**（`font-size:10px!important`、`padding:6px 0 8px!important`、`svg 20×20!important`），
  上面的任何字号变化都影响不到它。
- 不用 `transform:scale`（会把文字虚化、破坏滚动高度计算），只调字号与留白。

**② 「规则」页直接显示订阅下载结果与报错**（用户原话：「规则里面显示不出来下载的订阅报错」）
- 新增 `scripts/substatus.sh`：apply.sh 每个规则源抓取完成后把 `类型|URL|状态|原因|量|时间` 写入 `$PG/cache/substatus.db`。
- 失败原因**按 curl rc 细分**：`6`=DNS 解析失败 / `7`=连接被拒 / `28`=超时 / `35`=TLS 握手失败 / `56`=连接被重置 / `60`=证书校验 / `22`=HTTP 404·403；
  `rc=1` 这类通用码再用域名可达性探测细分（提示「DNS 解析失败或主机不可达（host）」）。
- 有本地缓存回退时明确标「已用本地缓存 N 行」，与彻底失败区分。
- WebUI 在规则条目 URL 下方渲染状态行：成功显示「订阅下载成功 · N 行」，失败显示「下载失败 · 原因」，并附「X 分钟前」时间。
- 刷新时机：WebUI 启动、点「重载」、点「应用」完成（成功或失败）后都会重拉状态并重渲染。
- 真机验证：可通源显示 `ok + 4 行`；不可达源显示 `fail + DNS 解析失败或主机不可达（no-such-host-xyz.invalid）`。

**③ 继续补全规则语法：RULE-SET 现在真的能用**
- 上一版 `RULE-SET` 只在 `route.rules` 里写引用、**不生成 `route.rule_set` 定义块** → run 阶段 FATAL `rule-set not found`（`check` 抓不到）。
- 现在 `vpnrule.sh` 同时产出定义：`.json`→`format:"source"`、`.srs`→`format:"binary"`，并校验文件存在与内容头（`.json` 必须以 `{`/`[` 开头），格式不符则 SKIP 而不是半对。
- 新增接口 `--emit-rulesets` / `--print-final`，`vpncore_genconf` 把定义拼进 `"route":{"rule_set":[...]}`。
- 真机验证：本地 `rulesets/myset.json` → 生成 `{"rule_set":["myset"],"outbound":"direct"}` + 定义块 → `check` rc=0 → 真实 `run` 核心存活（不再 FATAL）。
### v1.10.8：内置规则文件（8 规则集 + 3 FX）+ 本地 hosts 分区 + 性能修正

- **8 个规则文件内置为独立规则集**（`builtin://<id>`，随包、不联网、默认关闭、可独立启停）：
  AdguardDNS / chibi / adaway_hosts；含义与条目数见「内置规则文件（v1.10.8）」一节。
  正常清单在构建期归一化为 hosts 格式（保留原始 IP 映射、去重、跳过非域名行），
  两个装饰性清单如实保留 0 条而不是伪造条目。
- **FX 内置来源**：当前包将仓库 `FX.txt` 中明确标注的“国家反诈中心”域名与“反诈中心”IP 区段筛选为 `fxrules/anti_fraud_96110.txt`；未把 `userReject.yaml` / `anti_fraud_config.yaml` 的大而杂规则整份并入，避免广告追踪、通用安装器和其它政府站点进入专用库。来源规则的 IP 当前归属仍需设备外的独立核验。
- **本地 hosts 与订阅规则分开**（`[list:hosts_local]`）：本机手写、不经网络、改完「应用」即生效；
  WebUI 独立卡片，**不支持整段删除**（防止误删长期维护内容），只能添加/编辑/单条启停/单条删除。
  老版本写在 `[list:rule]` 里的裸行继续兼容生效，产物里分节标注来源。
- **性能**：FX 消费从「逐行 shell 循环（2.1 万行 ≈ 十万次 fork，实机会卡到分钟级）」改为
  「一次 sed 展开 + 一次 awk 整表解析」；内置规则集合并用单进程 awk；`pg_fx_expand` 只展开一次
  （原先计数 + 消费各展开一遍）。该性能说明针对旧版大规则集；当前 FX 专用源 `fxrules/anti_fraud_96110.txt` 是从仓库限定区段筛选而来，并会参与 hosts 与 VPN 路由两条加载链。
- **默认值**：新增的内置条目与在线订阅条目全部默认 `0`（用户要求「所有规则默认关闭、都是独立规则」）；
  升级时 `pg_migrate_lists` 会把 v1.10.7 默认开启的两条**模块示例**在线订阅（adguard filter_24 / hagezi pro）
  改为 `0`，只做一次（标记 `$PG/cache/migrate-1108-off.done`）；用户自加的订阅与他人启停状态一律不动。
  `[list:block]` / `[list:domain]` 等既有本地示例保持原默认值不变（如需全关可在 WebUI 逐条关闭）。
- 其他修复：① 本地 hosts 卡片「已启用 N / M」徽标此前固定 `0 / 0`（`updateCounts` 漏了该分区），已修；
  ② 订阅源彻底下载失败时 `apply.log` 会刷 `can't open .../f2: no such file`（shell 重定向先于命令执行），
  已改为先判文件存在再计数；③ `settings put` 增加退避重试（最多 6 次 ≈ 9.5s），
  减少开机早期 settings 服务未就绪造成的假失败。
- 诚实边界：装饰性清单启用后 0 拦截；`PROCESS-NAME`/`PACKAGE-NAME` 仅代理核心 + sniff 时生效；
  内置清单为快照、不自动更新；全开 30 万行 hosts 会增加「应用」耗时（功能正常）。

### v1.10.9：内置规则 / 本地 hosts 改为文件视图分页编辑器（大文件不再卡死）

- **根因**：旧编辑器把整篇正文一次性塞进 `<textarea>`，且经桥一次 base64 回传；文件一大主线程必冻，
  大文件还会因分块/编码/超时链路表现为「加载失败」。换实现而不是再调参数。
- **方案（参考 AdGuard Home 的分页只读视图）**：新增 `scripts/fileedit.sh`，分页与行操作全部在 shell 侧
  流式完成；前端一次只取一页（≤100 行 / ≤64KB），**前端永不持有全文**。几 MB 文件、30 万行清单也只渲染一页。
- **内置规则集 / 内置 FX 可编辑且保留原名**：点内置条目即进入分页视图；修改/插入/删除写入用户副本
  `$PG/rulefiles-user/<id>.txt`、`$PG/fxrules-user/<id>.txt`，原内置文件保持不动（升级不覆盖、校验可恢复），
  「恢复内置」两次确认后删副本。消费端三处（`apply.sh` 规则集、`util.sh` FX、`vpnrule.sh` FX 路由）均已改为**用户副本优先**。
- **本地 hosts 直接显示文件内容、点击即编辑**：卡片改为 `$PG/hosts.local` 的文件视图（行号 + 内容，点行打开
  分页编辑器并定位），去掉启用/导入/编辑导入/多选/整段删除；`apply.sh` 同时合并 `hosts.local`（旧 `[list:hosts_local]` 行继续兼容）。
- **编辑器能力**：上一页/下一页/跳转行/导出到 Download/末尾添加/两次确认删除；英文文案同步。
- **限制**：分页视图不做整篇搜索（用「跳转行」定位）；每页 100 行是按手机屏宽定的；超长单行横向滚动；
  逐行编辑只保存「行文本」，不做语法校验（写坏规则会在「应用」时由 apply 日志指出）。

## 与其他模块 / 代理 App 的共存（冲突说明）

本模块**不占用 VPN 槽位**（网络层全部走 iptables，无 tun 服务），清理时**只删自己的链**（`PGUARD`/`PGNAT`/`PGVPN`/`PGKS`/`PGHIDE`/`PGHKS` 等），不动别人的规则。但以下场景需要注意：

| 对方 | 冲突面 | 默认是否踩到 | 处理 |
|---|---|---|---|
| VPN 类代理 App（Clash/v2rayNG/Sing-box 等） | ① `dns_leak=1` 默认开：明文 53 全 REJECT——代理 App 解析服务器域名会失败 ② `block_quic=1` 默认开：UDP 443 REJECT——Hysteria/TUIC/QUIC 外层协议连不上 | **踩到** | 用此类 App 请在 WebUI 关掉 `dns_leak`/`block_quic`，或配置 `custom_dns`（RETURN 放行）让代理服务器域名走指定 DNS；TCP 外层协议（trojan/vless+ws）不受影响 |
| VPN 类 DNS 过滤 App（RethinkDNS/DNS66/personalDNSfilter） | 它们经 tun 转发明文 53 到上游——同样被 `dns_leak` 的 REJECT 拦截 | **踩到** | 同上：关 `dns_leak` 或配 `custom_dns` 放行其上游 |
| hosts 类模块（AdAway 等） | 双方都 bind-mount `/system/etc/hosts`，**后挂载的赢**，先挂的静默失效 | `hosts_block=1` 默认开，踩到 | 二选一：关掉本模块 `hosts_block`，或停用对方模块 |
| iptables 防火墙 App/模块（AFWall+ 等） | 对方"应用规则"时整体重建 OUTPUT 链，会把本模块的 `-j PGUARD` 挂链摘掉（本模块防火墙静默停摆）；反向不会——我们只重建自己的链 | 触发即踩 | 用 AFWall 后回 WebUI 点一次「应用」恢复；状态卡"规则数"可随时检查是否被清 |
| 其他透明代理模块（DNAT 80/443） | 两套 DNAT 同目标端口，iptables 首条命中——先插的赢，后者不生效 | `transparent_proxy=0` 默认关，不踩 | 同一时刻只开一家 |
| 其他 LSPosed 伪装类模块 | 同方法 Hook（如双方都改 `Build.MODEL`）按 Xposed 链式调用叠加，最终值取决于优先级——结果不可预期但不会崩溃 | 视对方而定 | 同一应用作用域别叠两家伪装模块 |
| 银行类证书锁定 App | 内置系统级 CA 只是多了一张根证书；证书锁定（pinning）应用校验叶子证书哈希，不受影响 | 不踩 | — |

**良好公民设计**：不占 VPN 槽位（可与你唯一的 VPN 共存）、iptables 清理只 `-F/-X` 自己的链、白名单（`[list:domain]`）和 `custom_dns` RETURN 是所有冲突的逃生通道、`status.sh` 的规则数字段可诊断"是否被别的工具清了规则"。

## 卸载（完整还原）

`uninstall.sh` 按状态类型分组还原（tc7 沙盒用例 30 项断言实测）：

| 状态类型 | 还原方式 |
|---|---|
| iptables PGUARD/PGNAT/PGVPN/PGKS/PGVPN6/PGBLK6/PGHIDE/PGHKS 链 | 逐链 -D/-F/-X（v4/v6 × filter/nat） |
| hosts bind mount / su 路径遮蔽 | umount（叠加挂载，原文件自动露出） |
| SELinux deny 规则（k_sysfs/k_read） | magiskpolicy --live allow 恢复；sepolicy.rule 随模块目录删除 |
| sysctl | kstack.defaults 有快照用快照值，其余恢复 AOSP 默认 |
| 属性伪装（resetprop） | post-fs-data 首次伪装前记录 props.snapshot（30+ 属性），卸载时逐项还原；空值属性 delete；重启亦彻底还原 |
| settings put（广告 ID/AGPS/扫描等） | 恢复出厂值 / delete 非出厂键 |
| setprop persist.log.tag | 清空 |
| 用户数据 | settings.conf + props.snapshot 备份到 /sdcard 后删除 |

Wi-Fi MAC 例外：`ip link` 改的 MAC 重启后由驱动重置，无法用户态即时还原（卸载报告记录当前 MAC 供参考）。

## 已知限制

- Wi-Fi MAC 伪装依赖驱动支持（多数高通/联发科机型可用，部分三星拒绝）
- boot_time_spoof 只能伪造属性层 uptime（`/proc/uptime` 单调性无法用户态伪造）
- hide_su/hide_rootcheck 的 mount 遮蔽对 Android 11+ 的 `/sbin` 已不存在的路径会静默跳过
- 透明代理只接管 TCP 80/443；UDP（QUIC）建议配合 block_quic
- VPN 透明接管要求客户端运行在本地端口（`vpn_port_open` 探测：netstat/curl 均无时保守假定监听并记日志）；节点 IP 会变，killswitch 的"节点出口 ACCEPT"按当前选中节点的 host 放行，客户端若做负载均衡会漏
- 内置 CA 默认不启用；启用后 Android 14+ 依赖 APEX bind-mount，个别 ROM 的 SELinux/挂载策略可能拒绝（`certmgr.sh builtin list` 的 `apex`/`live_apex` 与 `$PG/early.log` 可判断；覆盖层不完整时会拒绝挂载以保护公共信任链，不会把全局 HTTPS 弄坏）
- 主机内存/存储很小的设备上，超大规则集（>10 万条）仍会受浏览器 DOM 性能限制；v1.10.4 已用分块渐进渲染与分片持久化把可交互规模提升一个量级，建议单列表控制在数万条内
- vpn_app_proxy 的应用列表来自 `pm list packages`（安装/卸载应用后需重新打开选择器刷新）

## 兼容性矩阵

| 环境 | 状态 | 说明 |
|---|---|---|
| Android 14 (API 34) | ✅ 原生 | targetSdk 34，LSPosed APK 以 platform-34 编译 |
| Android 15 (API 35) | ✅ 已适配 | `Location.isMock()`（35 新 API）与 `isFromMockProvider`（旧）双 hook，字节级验证同入 dex；`SDK_INT` 反射写受 hiddenapi 限制时静默降级不崩 |
| Android 16/17 | ⚠️ 预期可用 | hook 按方法名匹配所有重载（签名免疫）；每功能独立 try-catch，单点失效不连坐 |
| GKI 内核 | ✅ 最佳环境 | 零内核依赖（不加载 .ko）；netfilter `-m owner`/conntrack/nat 全有；驱动接口统一 Wi-Fi MAC 成功率更高 |
| 非 GKI 老内核 | ✅ 自适应 | iptables `-w` 探测：不可用自动去锁降级（此前整条防火墙会静默失效）；sysctl 缺失节点静默跳过；SELinux 注入失败记日志 |
| KernelSU | ✅ | sepolicy.rule 不原生加载，但 `ksud sepolicy patch` 热注入运行时生效，重启由 service.sh 重注入 |
| Magisk / APatch | ✅ 最顺 | sepolicy.rule 开机自动加载 + magiskpolicy 全套 |
| 原版 Magisk（无 WebUIX） | ⚠️ 降级 | WebUI 自动进入演示模式（tabbit 实测），配置经导出/导入闭环 |


## v1.10.11 证书与 MITM 审计说明

本版本修复证书子模块模板缺少实际 `.0` 证书文件、安装脚本又删除模板证书的问题。子模块默认禁用，不会在安装时自动将自签 CA 加入全系统信任。旧版随包 P12 使用固定公开密码且包含 CA 私钥，因此已从本候选包移除。当前代码中尚无可验证的完整 TLS MITM 解密引擎；系统 CA 信任不等于 HTTPS 解密。请勿将本候选版本用于声称可解密所有 HTTPS 的生产场景。


## v1.10.12 审计修订说明

- WebUI 的 MITM 开关文案明确为“MITM 网关 IP 阻断”，并注明该开关仅按配置 IP 执行 DROP，不代表 HTTPS 解密。
- 移除 WebUI 中预置的示例广告域名、私网/IP 拦截、GEOIP 与 MITM 规则；FX 默认规则集为空，需用户主动导入。
- 离线/演示模式下不再伪造内置 CA 列表和指纹；证书管理状态必须来自真实后端。
- 本次为静态审计修订，未在 OnePlus 12 真机验证；不声称已实现 TLS MITM 解密、系统级 CA 全链路兼容或 VPN 共存。


## v1.10.13 审计修订

- 修正安装器欢迎信息与 `module.prop` 版本号不一致的问题。
- 修正英文界面中将 MITM IP 阻断误描述为 HTTPS 解密的文案。
- 本版本仍**不包含经验证的 TLS MITM 解密引擎**；`scripts/mitm-audit.sh` 应返回 `https-mitm-not-implemented`。
- 本次只完成静态一致性修订与可执行检查，不代表 OnePlus 12 真机、VPN 共存或浏览器稳定性已经验证。


## v1.10.20 HTTPS MITM 后端实验引擎（尚未端到端接通）

本版新增 `bin/arm64/pg-mitm`，以 Go 标准库实现 TLS 服务端握手、按 SNI 动态签发叶子证书、读取透明重定向连接的 `SO_ORIGINAL_DST`、HTTP/1.1 解密请求与上游 HTTPS 转发；首次初始化时为本机生成独立 CA，私钥保存在 `/data/adb/privacyguard/mitm/ca-key.pem`（权限 0600）。`scripts/mitm-engine.sh init-ca|status|start|stop` 可管理实验引擎。

**重要限制：本版仍不是已完成的全链路 MITM。** 引擎目前未接入 `apply.sh` 的 443 透明重定向，也未将本机生成的 CA 自动同步到独立证书子模块及 Android 14+ Conscrypt 信任覆盖层；因此即使引擎启动，也不会自动接管设备 HTTPS 流量，且客户端不会默认信任动态签发证书。`scripts/mitm-audit.sh` 会返回 `https-mitm-engine-present-not-integrated`，避免误报为已启用。此实现只覆盖 TCP TLS 上的 HTTP/1.1，不支持 QUIC/HTTP/3、证书固定绕过、客户端证书场景，也不能保证所有应用兼容。

此项静态/主机测试包含：Android ARM64 交叉编译、主机端 CA 生成与权限检查、叶子证书签发/签名验证单元测试。未在 OnePlus 12 真机验证；在透明流量规则、CA 子模块同步、失败回滚和真机兼容测试完成前，不建议启用流量重定向。

### v1.10.21 MITM status
The experimental TLS MITM engine now attempts to recover original destinations for both IPv4 and IPv6 redirected TCP sockets and rejects malformed SNI values. This is a backend hardening increment only: global TCP/443 interception remains disabled until device-specific firewall ordering, VPN coexistence, CA trust synchronization, and rollback have been validated. Do not treat the presence of `pg-mitm` as proof that HTTPS traffic is being decrypted.


### v1.10.22 MITM CA 验证
加载已有动态 CA 时会验证 CA 约束、有效期、证书签发用途以及证书/私钥公钥匹配，并修正私钥文件权限。此为安全性与故障定位加固，不代表透明流量接入或系统 CA 信任同步已完成。


## v1.10.25：动态 MITM CA 显式同步（仍未启用透明拦截）

- 新增 `sh scripts/mitm-engine.sh trust-ca`：在用户明确执行后，将设备本地 CA 同步到 `pg_mitm_ca` 独立系统 CA 子模块，并调用 `certmgr.sh` 启用系统信任；操作前备份 CA 索引、模板证书和已释放子模块，启用失败时尝试回滚。
- 为兼容 Android CA subject hash，设备本地 CA 的 Subject 与 `pg_mitm_ca` 子模块保持一致；从早期实验版本升级时，首次显式 `trust-ca` 会提示 subject 不匹配并旋转本地 CA，旧证书/私钥保留为 `.previous` 供恢复。
- `sh scripts/mitm-engine.sh untrust-ca` 可禁用该 CA 子模块；`init-ca/status/start/stop` 生命周期入口保留。
- 透明 TCP/443 重定向仍未接入 `apply.sh`，因此即使显式信任 CA，也不代表设备 HTTPS 流量已被解密。不得将本版本标记为端到端 HTTPS MITM 已完成。

### HTTPS MITM 实验接入（v1.10.27）

透明重定向默认关闭。仅在明确理解兼容性限制、已执行 `sh scripts/mitm-engine.sh trust-ca` 且准备好恢复方式时，才手动执行：

- `sh scripts/mitm-redirect.sh enable` — 显式启用 TCP/443 实验重定向；若检测到 PGVPN 规则会拒绝启用。
- `sh scripts/mitm-redirect.sh status` — 查看 IPv4 重定向状态（IPv6 不会被修改）。
- `sh scripts/mitm-redirect.sh disable` — 删除带有本功能所有权标记的 IPv4 重定向链并停止引擎。

不支持 QUIC/HTTP3、证书固定绕过、HTTP/2 或全部应用保证；真机测试前不要将其作为日常全局网络过滤功能。


### v1.10.27 透明接入安全边界

MITM redirect 当前仅实验性支持 IPv4 公网 TCP/443，IPv6 和 LAN 流量不重定向。入口默认关闭，必须手动执行 `sh scripts/mitm-redirect.sh enable`。如需停止，执行 `sh scripts/mitm-redirect.sh disable`。此功能尚未经过 OnePlus 12 真机端到端验证。


## v1.10.28 增量审计

- 透明接入重复执行 `enable` 时，若自有链已挂入 OUTPUT，不再清空正在使用的链或重复插入跳转。
- 启用前同时检查 IPv4 `PGVPN` 与 IPv6 `PGVPN6` 的 OUTPUT 跳转；任一存在都拒绝开启，避免 VPN 与 MITM 接管重叠。
- 本次只完成源码级修正和可执行的静态/编译检查；未在 OnePlus 12 真机验证防火墙、Conscrypt APEX、SELinux 或真实 HTTPS 端到端链路。


## v1.10.29 增量审计
- MITM 服务默认只监听 `127.0.0.1:18443`，避免实验端口暴露到 Wi-Fi/LAN 接口。透明接入仍需用户显式启用。
- 卸载脚本现在尝试先调用 MITM 重定向清理、停止引擎并禁用 `pg_mitm_ca` 独立证书子模块。若遇到无法确认所有权的防火墙同名链，会保留该链而不是强行删除。
- 以上为源码级改动；尚未在 OnePlus 12 上验证 Android 防火墙实现、CA/APEX 信任同步和真实应用 TLS 流量。


## v1.10.30 增量检查
- MITM 引擎停止流程现在会校验 PID 对应命令行，先发送 TERM 并有限等待；只有进程仍匹配模块二进制时才尝试 KILL。若进程仍可见则返回失败，不再无条件报告成功。
- 已进行脚本语法、Go 测试/ARM64 交叉编译和 ZIP 完整性检查；未进行 OnePlus 12 真机运行测试。


## v1.10.31 增量审计

- MITM NAT 链安装失败路径增加事务式回滚：仅对本次新建或此前已通过所有权标记验证的 `PGMITM27` 链清理；在插入 OUTPUT 跳转失败或规则写入中断时，尝试删除本次链及跳转。
- 关闭重定向时若引擎停止失败，脚本返回非零并报告失败，不再把失败状态包装成成功。
- 已执行静态脚本语法检查和包完整性检查；这不等同于 Android 真机 iptables 故障注入或 HTTPS 端到端验证。


## v1.10.32 增量审计

- 修复 CA 信任库覆盖层同步中的高风险路径：当 `/system/etc/security/cacerts` 的旧 bind mount 因 EBUSY 无法卸载时，立即中止本轮同步，不再删除或重建仍被挂载的源目录。
- 修复 Android 14+ Conscrypt APEX 覆盖层同步：每次重建前先尝试卸载上一层；若仍挂载则保留源目录并跳过重建，避免活跃信任库在同步期间被部分改写。
- 本轮仅完成静态修复与本地可执行检查；没有在 OnePlus 12 上做挂载忙碌/故障注入或系统 CA 端到端验收。


## v1.10.33 增量审计

- 对 `/system/etc/security/cacerts` 和 Android 14+ Conscrypt APEX 覆盖层增加“挂载仍存在但标记文件丢失”的保护分支。此类状态不再进入重建流程，避免删除仍被 bind mount 引用的源目录。
- `certmgr.sh cleanup` 即使标记文件丢失，也会检查目标是否仍处于挂载状态；若卸载失败则保留源目录。
- 本次只做静态/主机侧检查；未在 OnePlus 12 真机上执行挂载故障注入或系统 CA 生命周期测试。


## v1.10.34 增量审计

- 修正卸载脚本对 `/apex/com.android.conscrypt/cacerts` 与 `/system/etc/security/cacerts` 的无条件 `umount`。这两个目标现在仅由 `certmgr.sh` 通过自身标记及挂载状态进行有保护的清理，降低误卸载其他模块/管理员挂载的风险。
- `/system/etc/hosts` 仍由模块卸载流程单独解除。
- 本轮仅完成静态代码修改与主机侧检查；未执行 OnePlus 12 真机挂载故障注入，也未完成 HTTPS 端到端验收。


## v1.10.35 审计补丁
- Root 检测路径遮蔽现在记录本模块成功建立的 bind mount；重复应用时避免叠加挂载。
- 卸载只处理跟踪文件中且属于固定允许列表的遮蔽路径，避免无条件卸载其他模块或管理员建立的挂载。
- 这项修复尚未在 OnePlus 12 真机上做挂载故障注入。


### v1.10.36 状态接口修复

修复 MITM 状态命令将 CA 状态与监听器状态分两次输出、导致消费者收到多个 JSON 对象的问题。现在返回单个 JSON 对象，并明确标记监听器 PID 状态、CA 到期时间与尚未配置流量重定向的状态。该状态仍是进程/PID 检查，不等同于端口探测或端到端 HTTPS 解密验收。


### v1.10.37 MITM 状态真实性修复

- `mitm-engine.sh status` 不再把流量重定向状态硬编码为 `not-configured`；它读取 `mitm-redirect.sh status`，报告 IPv4 重定向链的 enabled/disabled/unknown。
- 返回 `listener_pid`，但该字段只代表 PID 与进程命令行匹配，不代表端口探测或 TLS 解密成功。
- 该状态仍不覆盖 IPv6、QUIC/HTTP3、证书固定及自定义 TLS 栈。未进行 OnePlus 12 真机验证。

### v1.10.38 MITM 重定向状态准确性

状态检查现在不仅验证 OUTPUT 是否跳转到 PrivacyGuard 自有链，还核对链内的安全排除规则和 TCP/443 REDIRECT 规则。若链已连接但规则缺失，会返回 `partial`，而不是错误报告 `enabled`。启用时仅复用完整链；不完整的自有链会重建，所有权标记缺失时仍拒绝修改。


### v1.10.39 MITM 与 CA 状态解耦

MITM 状态接口新增独立 CA 子模块状态与系统信任库状态字段，避免将引擎进程健康等同于 CA 已受信任。停止引擎后也读取重定向链的实际状态，不再固定返回 `not-configured`。这些状态字段仅用于诊断，不代表端到端 HTTPS 解密已验证。


### v1.10.40 系统 CA 状态指纹核验

MITM 状态接口现在比较本地 CA 与当前系统/Conscrypt APEX 信任视图中对应哈希条目的实际证书 DER SHA-256 指纹；仅存在同名哈希文件不再足以报告 `ca_system_trust=present`。如果系统信任库不可读或本地指纹不可计算，状态保留 `unknown`。


### v1.10.41 MITM CA 指纹校验加强

- CA 索引继续使用兼容格式的 16 位十六进制指纹前缀；系统信任状态核验改为比较完整 256 位 SHA-256 摘要，避免把前缀相同但证书不同的文件误判为已受信任。
- 当 CA 索引缺失或哈希字段为空时，系统信任状态保持 `unknown`，不再尝试检查错误的 `/.0` 路径。
- 该修改仅强化状态核验；不代表已完成真机信任链或端到端 HTTPS 解密验收。


## v1.10.42 CA 轮换安全性
- `trust-ca` 遇到 CA subject 不匹配时立即失败，不再自动轮换 CA 密钥。
- 增加显式 `mitm-engine.sh rotate-ca` 命令；轮换与安装信任分开执行，避免隐式改变 CA 身份。
- 引擎轮换逻辑会将原 `ca.pem` 与 `ca-key.pem` 保存为 `.previous` 文件以便人工恢复。
- 已完成 Shell 语法、Go 单元测试、ARM64 构建及 ZIP 完整性检查；未进行 OnePlus 12 真机验收。


## v1.10.43 CA 轮换安全修复
- 显式 rotate-ca 不再先删除已有 `.previous` 文件；恢复副本存在时拒绝覆盖，避免连续轮换意外丢失上一次可恢复密钥对。
- 当前 CA 证书与私钥只存在其一时拒绝轮换，避免把不完整状态当作可安全备份的配对。
- 新 CA 生成失败时删除不完整的新文件并尝试恢复旧证书/私钥。
- 新增单元测试覆盖恢复副本保护与成功轮换路径。
- 限制：这是主机侧单元测试与 Android ARM64 交叉编译结果，尚未进行 Android 真机故障注入或系统 CA 轮换端到端验收。


v1.10.44：CA 初始化在仅存在证书或仅存在私钥时拒绝自动生成/覆盖，避免残缺密钥对被静默替换；新增测试验证幸存文件不会被覆盖。已执行 Go 单元测试、Android ARM64 交叉编译、Shell 语法检查、WebUI JavaScript 解析和 ZIP 完整性检查；未进行 OnePlus 12 真机验收。


## v1.10.45
- MITM `status` 命令改为只读读取已有 CA；缺失证书时报告错误，不再因状态轮询自动生成 CA，也不改变私钥权限。初始化和服务启动仍由显式命令负责创建运行目录。

## v1.10.46

- CA trust synchronization no longer deletes an existing `trust-backup` at the start of a new run. A leftover backup is treated as evidence of an interrupted transaction and causes a safe refusal until reviewed.
- After a successful trust enable, the temporary recovery backup is removed. If cleanup fails, the command reports an explicit error and preserves the backup rather than silently discarding it.
- This is a conservative recovery safeguard; Android device-level trust restoration still requires device testing.


## v1.10.47 审计补充

MITM shell 管理脚本不再在解析命令前统一创建运行目录或修改其权限。`status`/`stop` 查询路径因此避免此项副作用；`init-ca`、`rotate-ca`、`trust-ca`、`start` 等显式变更命令会先确保私有运行目录存在并设为 0700。该修复仅证明脚本行为边界，不代表真机 TLS 解密通过。


## v1.10.48 审计记录

修复 MITM CA 信任同步事务的回滚保护：恢复 CA 索引、模板证书和子模块时逐步检查返回码；任一恢复步骤失败时保留 `trust-backup`，不再静默删除恢复数据；成功恢复后才清理备份。初始 CA 索引备份失败时清理本次创建的不完整备份目录。该修改尚未经过 Android 真机故障注入，不能视为跨组件事务已完全验证。


## v1.10.49 CA 信任备份事务补强
- CA 信任变更前，先在 `trust-backup.tmp.<pid>` 私有暂存目录内完整复制索引、模板证书和可用的独立子模块。
- 仅在全部备份步骤成功后，才通过目录重命名发布 `trust-backup`；复制或发布失败时清理本次暂存目录，并在修改信任状态前退出。
- 这降低了失败备份留下半成品、导致后续操作永久被旧备份阻塞的风险；尚未替代真机故障注入验证。


## v1.10.50 MITM 停止流程复查

`mitm-engine.sh stop` 在发送 SIGKILL 后增加最多 10 次、每次约 0.2 秒的有界复查；每次复查仍要求 `/proc/<pid>/cmdline` 指向本模块 MITM 二进制，避免仅凭 PID 误判或误杀。该变更改善异步退出时的状态判定，但仍需 Android 真机执行进程异常退出测试。


## v1.10.51 审计记录
- MITM 引擎 `status` 对失效 PID 文件不再执行删除操作，避免只读状态轮询修改运行状态；显式 `start` / `stop` 仍负责生命周期清理。
- 此项为静态代码修复，未宣称完成 Android 真机端到端验证。

## v1.10.52 审计记录

- MITM 重定向清理与部分安装回滚中的 OUTPUT 跳转删除循环增加 64 次上限，防止异常 iptables 包装器/后端在删除成功但状态不变时造成无限循环。
- 超过上限时明确返回失败并保留链状态供诊断，不继续执行无界清理。
- 本项为静态防护；未在 OnePlus 12 真机或故障注入环境验证。


## v1.10.55 卸载诊断改进

卸载阶段若 MITM 重定向清理、引擎停止或独立 CA 子模块停用未能确认成功，会向 stderr 和 Android logcat（PrivacyGuardUninstall 标签）发出警告，不再静默吞掉失败。卸载脚本仍会继续执行其他清理；这些警告不等于已成功恢复全部系统状态。


### v1.10.56 静态审计说明
MITM 重定向状态在防火墙工具不可用时显示为 unknown；存在自有但脱离 OUTPUT 的 PGMITM27 链时报告 orphaned-chain，避免误报已关闭。该修改尚未通过真机防火墙故障注入。


### v1.10.58 进程身份校验
MITM 生命周期脚本现在精确匹配 `/proc/PID/cmdline` 的 argv[0] 与引擎路径，不再对整条命令行做子串匹配。此改动降低误操作其他进程的风险，但仍需在设备上验证 PID 复用和异常停止场景。


### v1.10.60 DNS 状态诊断
状态页新增实际防火墙 DNS 转发规则检查，分别显示 UDP/53 与 TCP/53 规则是否齐全。`active` 仅代表规则齐全，不代表上游 DNS 解析成功；`partial` 表示规则不完整，`inactive` 表示未发现规则，`unknown` 表示无法读取防火墙状态。


### DNS 主动诊断（v1.10.61）

普通状态查询只检查防火墙转发规则，不会主动联网。需要进行一次有界的系统 DNS 查询时，可执行：

```sh
sh /data/adb/modules/privacyguard/scripts/status.sh dns-check text example.com
sh /data/adb/modules/privacyguard/scripts/status.sh dns-check json example.com
```

该诊断需要设备同时提供 `nslookup` 和 `timeout`；缺少任一必要工具时会报告 `unsupported`，而不是假称 DNS 正常。探测成功仅代表此次查询成功。


## v1.10.62 诊断一致性修复

- MITM 重定向状态会额外检查 PID 文件及 `/proc/PID/cmdline` 的 argv[0]，区分监听进程 `running/stopped/unknown`。如果 TCP/443 重定向仍启用但监听进程已退出，报告 `health=degraded`；该查询只读，不会擅自删除防火墙规则。
- DNS 主动探测支持独立 `nslookup`，也尝试 Android Toybox 的 `nslookup` 与 `timeout` applet；若无法建立有界执行方式，仍返回 `unsupported` 且不发起查询。
- 这仍是静态诊断改进，不等于已在 OnePlus 12 真机验证引擎崩溃后的网络恢复。


## v1.10.63 lifecycle hardening

- `mitm-engine.sh stop` now checks the redirect state before stopping the listener. For an enabled/partial/orphaned owned redirect it removes the owned firewall chain first; if cleanup fails or firewall state is unknown, it refuses to stop the listener and reports the reason. This avoids leaving TCP/443 redirected to a closed loopback port when the engine is stopped directly from another control path.
- `mitm-redirect.sh disable-rules` is an internal lifecycle primitive that removes only the module-owned redirect rules without recursively calling engine stop. Normal `disable` still removes rules first and then stops the engine.
- Validation is static/host-side only; OnePlus 12 firewall integration and failure injection remain unverified.


## v1.10.64 WebUI 应用结果可信度修复

- WebUI 后台执行 `apply.sh` 时新增监督 shell，记录真实子进程退出码到 `/data/adb/privacyguard/apply.exit`。
- 旧逻辑仅凭 `kill -0` 检查发现进程退出，就调用成功收尾函数；这会把非零退出的失败任务误报为完成。本版只有退出码明确为 `0` 才报告成功；非零退出、标记缺失或读取失败均报告失败/无法确认。
- 超时取消时监督 shell 会尝试向实际 apply 子进程转发 TERM，减少只杀外层进程导致任务遗留的风险。
- 验证边界：已做静态脚本与 JavaScript 语法检查；当前主机没有 Android root/KernelSU 环境，尚未在 OnePlus 12 验证桥接器对后台 shell、信号转发及文件写入的具体行为。


## v1.10.65 WebUI 配置持久化审计

- `pgWriteConf()` 在临时文件原子替换后检查最终 `settings.conf` 文件是否存在且字节长度与 UTF-8 序列化内容一致；长度不符时不报告写入成功。该检查可发现截断/缺失写入，但不是逐字节内容校验。
- bridge 或本地存储写入失败时，尝试重新读取最后已保存配置并重绘开关与规则列表；无法确认时显示明确错误，不将未保存的开关视觉状态保留为已保存状态。
- 静态审计覆盖 WebUI 中声明的 134 个 `data-key` 开关，并对脚本、`service.sh`、`post-fs-data.sh` 与 LSPosed Java 源码进行交叉检索。交叉检索只能证明存在代码引用，不能证明所有设备/ROM 上运行时生效。
- 未完成 OnePlus 12 / KernelSU 实机桥接、系统网络规则和证书信任链验证；本版本不宣称所有开关均已实机验证。证书独立子模块文件与目录结构未改动。


## v1.10.66 WebUI 应用前置条件审计

- 修复 `applyRun()` 忽略 `pgPersistNow()` 返回值的问题：配置持久化失败时不再启动 `apply.sh`，避免界面已恢复旧配置但后端仍应用旧配置造成状态不一致。
- 应用任务启动失败时清除忙碌状态和进度 UI，并显示可区分的错误提示。
- 本轮为源码静态修复与主机侧回归检查；未在 OnePlus 12/KernelSU WebUI 实机验证桥接返回值及端到端应用行为。


## v1.10.67 WebUI 后端执行链审计

- VPN 应用兼容备用路径先校验 `pgPersistNow()`，再执行 `apply.sh`；解析真实 `EXIT` 状态，未确认成功时不提示 VPN 已生效。
- 全部订阅刷新优先使用统一应用监督器，继承配置持久化守卫和任务退出码检查；备用路径也验证退出码。
- 演示模式不再随机增加 `vpn_flow_bytes`，无后端时明确提示未执行订阅刷新。
- 检查边界：经过源码静态检查和主机侧模拟测试；尚未在 OnePlus 12 / KernelSU WebUI 实机验证。


## v1.10.68 静态审计修复
- LSPosed 状态不再仅凭管理器 APK/配置目录存在就报告 active；需要检测到 `lspd` 进程。该结果仍只证明 daemon 进程存在，不证明目标应用已被 Hook。
- `gen_xposed_conf.sh` 先将镜像配置与 Hook 配置写入临时文件，验证后原子发布；镜像失败、Hook 配置为空/缺少 `lsposed_profile` 或发布失败均返回非零，避免半成品文件被当作成功。
- 本轮未在 Android 设备验证 LSPosed daemon 进程名兼容性、SELinux 读权限、Hook 实际加载或应用内效果。


## v1.10.72 审计记录
- 节点测速前端统一使用严格 JSON 结果解析；仅接受有限数值延迟或明确的 -1 不可达结果。
- 后端输出缺失、JSON 格式错误、延迟字段类型错误和桥接调用拒绝时均保留未知状态，不伪造测速值；静默测速的未知结果向自动选优回调传递 null。
- 验证范围：静态检查与主机侧测试；尚未在 OnePlus 12 真机上验证 KernelSU 桥接、实际节点网络可达性及自动选优端到端行为。


## v1.10.73 审计记录
- 批量节点测速结束时按有效延迟、明确不可达（-1）和未知/失败三类统计结果；全部结果未知/失败时显示明确提示，不再仅显示笼统的“测速完成”。
- 停止测速时报告已处理数量及分类结果，结束后刷新节点列表，避免旧 UI 延迟状态残留。
- 验证范围：静态检查与主机侧测试；未在 OnePlus 12 上验证真实节点连通性、自动选优和 VPN 分流。


## v1.10.74 自动选优参数与候选校验审计

- 自动选优参数增加边界保护：延迟阈值 1–60000 ms、单节点超时 1–30 s、最多测速节点 1–300；异常值回退到默认值或安全上限。
- 候选节点上限仅统计可解析的 host:port，避免畸形订阅条目消耗测速名额；端口必须为 1–65535，空主机/无效端口跳过。
- 保持原有 WebUI 样式不变；没有新增 UI 设计或玻璃拟态样式。
- 这些是静态/主机侧代码改动；真实订阅、设备网络与自动切换仍需在 OnePlus 12 上验证。

### v1.10.75 后端审计补充
- `apply.sh vpn-sub` 成功后继续进入快速应用流程；托管核心启用且代理模式非直连时，先停止旧核心，再由快速应用重新生成配置并启动，避免只更新持久化 `vpn_node` 而运行核心仍使用旧配置。
- `vpncore_stop` 只有在确认进程退出/身份不再匹配后才删除 PID 文件；强制停止后仍存活则保留 PID 并返回失败。
- VMess IPv6 `add` 字段保留或补齐方括号，避免 host:port 拆分歧义。
- 证书子模块 enable/disable/remove 操作在文件标记或 `ca_sync` 返回失败时返回错误，不再无条件输出成功消息。安全保护导致的“跳过同步”仍需结合设备实际挂载状态判断，主机侧测试不能证明系统 CA 已被真实安装/摘除。
- 本版不修改 `webroot/index.html`，保留原有 UI。

## v1.10.76 后端审计：订阅事务与 CA 信任核验
- `apply.sh vpn-sub` 在改写订阅前备份 `settings.conf`；整个快速应用/核心重载链以退出码决定提交，失败时尝试原子恢复旧配置，并在旧核心原本运行且停止成功时尝试用旧配置重启。运行态/网络规则回滚是 best-effort，不能保证每个 Android 网络状态都可逆。
- `certmgr.sh ca_sync` 对标记缺失但挂载仍存在、EBUSY、系统/APEX 信任库未就绪、覆盖层复制不完整和 bind mount 失败返回非零；安全跳过不再冒充同步成功。
- 证书状态列表不再只凭 `<hash>.0` 文件存在就认定已信任，而是比对实际证书 SHA-256 指纹与 `ca-index`。`enable`/`disable`/`remove` 同步失败时尝试恢复原标记或子模块目录并再次同步；回滚失败会保留备份并记录错误。
- 保留 `pg_mitm_ca` 与 `pg_https_ca` 两个独立证书子模块。`webroot/index.html` 与 v1.10.75 完全一致，未修改 UI。
- 主机侧验证：Shell 语法、31 段内联 JavaScript 语法、MITM Go 单元测试、证书索引指纹与两个子模块证书文件一致、事务/错误返回静态回归断言、ZIP 完整性。
- 未验证：OnePlus 12 真机上的实际 bind mount、Conscrypt/APEX 信任库加载、证书安装/禁用/移除后的应用信任变化、Android 运行中应用缓存、真实代理核心重载与网络规则回滚。主机侧指纹测试和静态断言不等于系统实际信任已生效。


## v1.10.77 后端审计补充

- `scripts/apply.sh` 的订阅事务增加 HUP/INT/TERM 信号处理器，将可捕获信号转换为非零退出，使 EXIT 事务处理器有机会恢复旧 `settings.conf` 并尽力恢复旧核心运行状态。SIGKILL/断电仍无法由 shell trap 处理。
- `scripts/certmgr.sh` 对 `/system` 与 Conscrypt APEX 覆盖层中的启用子模块证书改为逐文件复制检查；缺失 `.0` 文件或复制失败立即中止，不再忽略复制错误后继续构造/挂载覆盖层。
- 本轮没有修改 `webroot/index.html`。主机侧测试不能证明 Android bind mount、信任库实际生效或真机网络回滚。
- `vpncore.sh` 新增方括号 IPv6 authority 解析，覆盖 VLESS/Trojan/Shadowsocks/Hysteria2/TUIC/AnyTLS/SOCKS 分支，并为 VMess 与标准 URI 端口增加 1–65535 校验。该项为 URI→JSON 解析层修复，未声称代理握手或端到端网络已验证。
- 订阅事务 EXIT 回滚期间继续持有 apply 锁，避免先释放锁再恢复配置/核心导致并发 apply 与回滚相互覆盖。

### v1.10.77 后端审计

订阅事务增加 HUP/INT/TERM 非零退出处理，并在回滚结束前保持 apply 锁；证书同步用共享 fail-closed helper 逐文件检查 `/system` 与 Conscrypt APEX 覆盖层的启用 CA 文件，缺失或复制失败会拒绝挂载。`scripts/tests/v1.10.77-host-regression.sh` 提供可重复的主机侧复制失败注入测试。IPv6 authority 解析已覆盖 VMess、VLESS、Trojan、Hysteria2、TUIC、AnyTLS、SOCKS 的 URI→JSON 路径；这不代表协议端到端连接已验证。

### v1.10.78 后端审计补充
- 订阅事务使用持久 `vpn-sub.transaction` 标记记录旧配置备份路径和核心原运行状态；下一次持有 apply 锁启动时检测遗留事务，原子恢复旧 settings.conf，并尽力重启原核心。恢复失败保留标记/备份供重试；核心恢复成功后仍需正常 apply 协调网络规则。SIGKILL/断电不能执行 trap，因此该机制是启动恢复而非原子跨系统事务。
- CA bind mount 成功但挂载标记提交失败时，尝试卸载；若仍处于挂载状态，保留覆盖层源目录，避免破坏 live mount。
- 新增 `scripts/tests/v1.10.78-host-regression.sh`，提供可重复的主机侧命令故障注入。它不模拟 Android 内核的真实 mount/Conscrypt 行为。

## v1.10.80 事务完整性审计
- 新订阅事务标记增加旧配置备份 SHA-256 和 `active` / `committed` 阶段。提交先原子发布 `committed` 决策，再清理标记与备份；下次启动若发现已提交阶段，只完成清理，不误回滚成功事务。
- 恢复时校验备份 SHA-256，校验失败则保留标记/备份并拒绝使用损坏快照。兼容旧版两行标记，但无法对其提供完整性校验保证。
- `scripts/tests/v1.10.80-host-regression.sh` 包含重复运行的源码契约断言和备份哈希篡改注入。它不模拟 Android 断电持久化、真实 sing-box 生命周期或防火墙原子协调。

## v1.10.89 卸载挂载所有权审计
- `uninstall.sh` 不再无条件卸载 `/system/etc/hosts`。只有 mount 表确认挂载源为 `/data/adb/privacyguard/hosts` 时才尝试卸载；如果目标挂载存在但来源不是本模块，则保留挂载并输出警告，避免误拆第三方模块/管理员建立的挂载。
- 新增 `scripts/tests/v1.10.89-host-regression.sh`，检查所有权判断、未知来源分支不执行 umount，并对 shell 脚本做语法检查。
- 主机回归、v1.10.87 证书事务故障注入、MITM Go 单元测试、31 个内联 JavaScript 语法检查均通过；`webroot/index.html` 与 v1.10.87 字节级一致，ZIP 完整性检查通过。
- 尚未在 OnePlus 12 真机验证挂载表输出格式、KernelSU 卸载时序、真实 hosts 挂载清理或 Android 网络恢复。

## 2026-10-24 · QuickJS-NG ARM64 宿主运行时补强（候选状态）

本包新增 `bin/arm64/qjs`（QuickJS-NG v0.17.0，Android arm64-v8a / API 24）和 `scripts/jsruntime/` 显式脚本执行入口。宿主桥提供 `$done`、持久化 `$prefs`、常见 `$httpClient` 回调方法与同步 HTTP bridge，以及 `$task.fetch().then().catch()` 链式接口。使用说明见 `scripts/jsruntime/README-zh-CN.md`。

**2026-10-27 安全加固：**发现并修复了订阅脚本可通过 `import('qjs:os')` 绕过隐藏全局、取得 `os.exec()` 的高危路径。加固版 QuickJS-NG 在可信宿主预加载之后、模块缓存查询之前拒绝导入 `qjs:std`、`qjs:os`、`qjs:bjson` 与 `.so` 原生模块。回归覆盖四类导入以及 `$task.fetch` / `$prefs` / `$done` 主机流程。此改动**不是 Android/内核级进程沙箱**，也不代表已在 OnePlus 12 真机验证；仍只应执行可信脚本，订阅脚本的第三方 API 兼容性需逐项实测。

**关键边界必须保留：**目前尚未把订阅中的 `[Script]` 声明自动绑定到 MITM 实时请求/响应触发链，`$done` 返回的改写结果也没有回写到代理流量；`$task.fetch` 返回原生 Promise，但网络请求在 Promise 创建前同步执行，不具备真正的非阻塞网络 I/O。因此本次属于后端增强候选构建，不宣称 Shadowrocket / Surge / Loon / Stash 全量兼容，不宣称 HTTPS 脚本改写已完成。测试包括 34 个 shell 回归脚本；这些是当前构建环境的静态/沙盒回归，不替代 OnePlus 12 真机联网、证书信任及代理流量测试。


### Audit113 规则边界修正

开屏与水印隐藏不属于 FX 规则定位，已从默认订阅登记、MITM 响应处理链路及规则兼容性说明中移除。FX 继续聚焦隐私保护、追踪控制、连接安全和可审计的例外策略；不会将网页美化能力包装成反诈或隐私防护能力。

### Audit115：白名单域名校验

白名单在 Hosts 与 VPN 路由生成阶段均进行严格域名标签校验，并抑制重复项。VPN 白名单只将合法多标签域名生成 `DIRECT` 后缀规则；单标签名仅保留在 Hosts 侧。白名单优先于对应的拦截规则，因此应只加入明确需要放行的主机名或域名。

## Audit116：白名单维护入口

新增 `scripts/whitelist.sh`，用于安全维护 `[list:domain]` 白名单：

- `sh scripts/whitelist.sh list`：查看当前白名单；
- `sh scripts/whitelist.sh add login.example.com "登录接口"`：添加或更新一条白名单；
- `sh scripts/whitelist.sh remove login.example.com`：按规范化域名移除白名单；
- `sh scripts/whitelist.sh apply`：显式重新应用配置。

域名会先做严格校验，`*.example.com` 会归一化为 `example.com`；不接受空标签、超长标签或非法字符。新增/删除只修改配置，不会自动重启网络组件；需要显式执行 `apply`。白名单会优先于对应的 FX 拦截规则，请只添加确实需要放行的具体域名。


**IPv6 本地 Hosts 映射：**本地 `local/hosts` 支持标准 IPv4 与 IPv6 地址映射（例如 `192.0.2.7 host.example`、`2001:db8::1 host.example`），FX-only 模式与完整 hosts 模式都会保留映射；单独一行、没有主机名的裸 IP 不会被当成有效 hosts 项。若活跃 hosts 目标被 bind mount 隐藏，FX 优先从首次安装备份恢复原始系统基线，并拒绝把本模块生成的 hosts 文件再次用作基线。

## FX 1.0.0 当前 MITM 安全状态（2026-10-27）

当前代码有单独的显式启用入口 `scripts/mitm-redirect.sh enable`，并非由 `apply.sh` 或开机自动启用；WebUI 的 MITM 流量卡片调用同一后端。启用要求运行时 CA 已在系统信任视图中确认存在，监听器已真实绑定 `127.0.0.1:18443`，并且不得检测到 FX 自身 PGVPN/PGVPN6 接管或常见第三方隧道接口。启用后启动轻量看护进程；检测到常见外部 VPN 隧道、监听器失效或自有 NAT 链不完整时，尝试只移除 FX 自己带所有权标记的重定向规则并停止引擎。

这是保守防护而不是“所有 VPN 都可共存”的保证：隧道检测依赖常见接口名（tun/wg/ppp/ipsec/tap/utun/tailscale/zt），未知 VPN 接口可能无法识别。MITM 只覆盖实验性的 IPv4 TCP/443、TLS HTTP/1.1；IPv6、QUIC/HTTP3、证书固定、客户端证书和部分自定义 TLS 栈不支持。未在 OnePlus 12 真机验证 Android iptables、系统 CA/APEX/SELinux、第三方 VPN 切换时序或真实 HTTPS 请求。监听器端口检查和故障回退已增加主机侧回归测试，但不得把它等同于真机端到端验证。

## FX 1.0.0 · 2026-10-27 follow-up reliability work

- MITM script URL matcher now accepts the common `https?:\\/\\/host\\/path` spelling used by proxy-module configs; Go regex does not use slash as a delimiter. Added Go tests for Bilibili feed and Aloha profile URL patterns, including double-escaped metadata.
- A paired local DNS chain is packaged: AdGuard Home v0.107.79 filters only FX anti-fraud domain rules on loopback port 53, and Android ARM64 Unbound 1.26.2 listens on `127.0.0.1:5353`, caches locally, and resolves cache misses by querying root/TLD/authoritative DNS directly. Runtime config does not hard-code Tencent/Alibaba/Cloudflare forwarders. The chain is attempted automatically when safe prerequisites pass; activation requires binary hashes, config check, an uncached recursive-query health probe, and successful IPv4/IPv6 redirect prerequisites. A watchdog delegates failures back to the normal `apply.sh` rollback path. Android builds, official config checks and host-side fake-process regressions pass. **Neither DNS binary has been tested on a OnePlus 12 device**; direct UDP/TCP 53 reachability, live DNSSEC, SELinux, IPv6 DNAT, Private DNS/DoH bypasses and true third-party VPN coexistence remain unverified. See `docs/FX-v1.0.0-AdGuardHome-ARM64-integration-status-2026-10-27.md`.


## FX 1.0.0 当前补充：上游网页规则与自动 VPN 共存（2026-10-28）

- 网页元素规则保存在普通 `[list:rule]`，不会混入仅供反诈中心的 `[list:fx]`。本地基线包含 241 条网页打开客户端提示选择器、41 条网页 DOM 水印选择器、384 条成人网站广告容器/弹窗选择器和 30 条反广告拦截提示选择器。
- 上游补齐：RunningCheese `Adblock_Watermark.txt`、RunningCheese `Adblock_Popup.txt`、NoAppDownload 全量 CDN 镜像默认开启；cxfl uBlock 补充源默认关闭。远程网页元素规则通过已校验缓存供 MITM 使用；这些 CSS 源为 best-effort，下载失败不参与 Hosts/IP 规则事务的失败判定。
- MITM 规则解析支持标准属性选择器、组合器、普通 CSS 伪类、受限 `:style(...)` 和 `#@#` 例外；不支持的 uBlock 程序化语法会跳过。对 Canvas/播放器/文章等可能承载正文的选择器增加保留检查，避免把移除水印误做成隐藏实际内容。CSS 只能隐藏 DOM 元素，不能擦除已烧录进图片/视频像素的水印。
- 外部 VPN 共存现在自动检查隧道、VPN UID 与 root 路由；只有 root 上游路由确认经过外部 VPN 才启用叠加，否则 FX 退回直连以避免节点连接跑出外部 VPN。该逻辑通过主机回归，不代表所有第三方 VPN 都能串联；真机仍需验证。
