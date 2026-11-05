# FX 1.0.0 规则生态兼容边界

本文说明导入器能转换什么，不代表所有生态的完整运行时都已实现。

## 当前可转换子集

- **Surge / Loon / Stash / Shadowrocket 模块常见静态段**：`[Rule]`、`[Host]`、`[URL Rewrite]`、`[Map Local]`、`[Script]`、`[MITM]`、`[Header Rewrite]`、`[Body Rewrite]`、`[General]`；支持的是导入器明确识别的条目子集，不能据此宣称完整客户端兼容。
- **Clash / Mihomo / Quantumult X 类静态规则**：导入器支持 Clash/Mihomo YAML 中显式 `rules:` 列表的有限子集，包括 `DOMAIN`、`DOMAIN-SUFFIX`、`DOMAIN-KEYWORD`、`DOMAIN-REGEX`、`IP-CIDR`、`IP-CIDR6`、`PROCESS-NAME`、端口/网络谓词、`MATCH` / `FINAL`，以及 `host` / `host-suffix` 等部分别名。策略会保留为 FX 路由规则；`DIRECT` 域名规则可进入 FX 白名单。代理组、DNS、远程 `rule-providers`、YAML 锚点/复杂结构不会被解析；`RULE-SET` 不会被伪装成已导入。
- **AdGuard / Adblock Plus / uBlock Origin 网络过滤器**：仅转换没有额外匹配选项的纯域名 `||domain^` 和 `@@||domain^`。例外写入 `[list:domain]`，拦截写入 `[list:block]`。
- **规则订阅**：FX 后端对已缓存且 SHA-256 sidecar 匹配的已知格式规则进行编译；缓存缺失或摘要不匹配时跳过，不把不完整数据当作有效规则。

## 明确不等于完整支持的能力

- **JavaScript 脚本运行时**：当前导入器不会执行客户端 `.js` 脚本，也不模拟 Surge / Quantumult X / Loon / Shadowrocket 的专有脚本 API、HTTP 客户端、持久化、定时任务或请求上下文。
- **L7 内容改写**：URL Rewrite、Map Local、Header/Body Rewrite、元素隐藏、脚本注入及带路径/请求条件的过滤器不会被冒充成域名拦截规则。
- **复杂 Adblock 选项**：带 `$third-party`、`$domain=`、`$redirect`、资源类型或其他选项的过滤器会跳过，因为把它们转换成全域拦截会改变语义。
- **完整 YAML/JSON 配置**：导入器不是通用 YAML/JSON 解析器，不会把代理节点、DNS、TUN、策略组或全部 sing-box 配置自动转换成 FX 配置。复杂逻辑规则 `AND` / `OR` / `NOT`、远程规则集、GeoIP/GeoSite、URL 正则和 User-Agent 仍不能保证等价转换。
- **MITM**：识别模块中的 MITM 域名不等于自动启用 TLS 接管；证书信任、透明流量接管、HTTP 解析和应用证书固定仍是独立能力。

## 导入原则

1. 不支持的条目必须显示 SKIP 和原因，不能静默丢弃后提示全部成功。
2. 不得把 `PROXY` 误写成 `DIRECT`，也不得把带额外条件的过滤器扩大成全域拦截。
3. 白名单输出到独立的 `[list:domain]`，不与系统 `/system/etc/hosts` 文件或订阅文本混放。
4. 规则格式兼容不代表脚本运行时、代理协议或 HTTPS 解密兼容。


## 普通广告/网页元素规则与 FX 专用规则分离（2026-10-28）

网页开屏/下载提示、网页 DOM 水印、成人网站广告弹窗和反广告拦截提示属于普通 `[list:rule]`，不是 FX 专用反诈规则。DNS/Hosts 规则本身不改写 CSS；网页元素隐藏只在 MITM 成功读取 HTML、证书信任和流量接管均满足条件时运行。原生 Android App 的开屏/插屏/信息流广告仍需要目标应用同时被 FX Hook 规则与 LSPosed Scope 选中。

- 本地内置并默认启用：`builtin://NoAppDownload.txt`、`builtin://Adblock_Watermark.txt`、`builtin://AdultSite_AdPopup.txt` 和 `builtin://Adblock_Warning_Removal.txt`。成人网站本地规则只选广告容器/弹窗类选择器，不把站点根域名加入广告主机列表。
- 默认开启的网页元素上游订阅：RunningCheese `Adblock_Watermark.txt`、RunningCheese `Adblock_Popup.txt`、NoAppDownload CDN 镜像。它们使用独立的 best-effort 缓存更新；下载失败不会让 Hosts/IP 规则生成事务失败，已有校验缓存或本地内置规则仍可继续使用。
- 可选补充源 `cxfl-ublock.txt` 默认关闭；其 `:has-text()`、`:contains()`、`:upward()`、`+js` 等程序化或 uBlock 专有语法不会被伪装成标准 CSS。其他网络过滤来源仍独立启停，避免首次应用因任意远程来源不可达而扩大断网风险。
- MITM 选择器引擎现支持属性选择器、组合器、普通 CSS 伪类、`:style(...)` 的受限属性子集和 `#@#` 例外规则；每条远程来源都必须有匹配的 SHA-256 缓存摘要。每次解析最多 5000 条，输出 CSS 最多 512 KiB，HTML 正文上限仍是 1 MiB。高风险或可能隐藏真实内容/播放器/画布的选择器会跳过。
- DOM 水印可尝试隐藏，但已经烧录在图片/视频像素里的水印不能由 CSS 擦除。Native App 广告启发式也不保证覆盖所有私有布局；不开证书信任/不启用相应 Hook，不会因此自动去广告。
- 外部 VPN 共存改为自动检测，不再要求用户手动切换共存模式。仅在识别到外层隧道、VPNService owner UID，并确认当前 FX 节点的候选地址均由 root UID 路由经过该隧道时，才允许 FX 透明代理叠加；不再使用 `1.1.1.1` 作为节点路由的替代检查，也不采用不带 UID 的回退路由。地址解析/路由检查不确定，或任一地址仍走物理网卡时会安全退回直连。诊断页面不再为查看出口额外访问公网 IP 服务。该守卫不能取代 OnePlus 12 真机出口测试，不能宣称兼容所有 VPN 应用；域名解析本身的 DNS 路径仍需真机验证。

## 规则集来源目录（FX 1.0.0）

- 本地内置网页元素规则：`NoAppDownload.txt`（246 行文件，241 条域名限定选择器）、`Adblock_Watermark.txt`（41 条选择器）、`AdultSite_AdPopup.txt`（384 条选择器）、`Adblock_Warning_Removal.txt`（30 条选择器）。这些是静态内置基线，不等于覆盖所有站点或原生应用。
- 普通远程过滤来源仍包括秋风 Adblock、AdGuard DNS Filter、AdAway Hosts、10007 Hosts、Chibi Hosts、AdGuard 广告服务器、AdGuard 跟踪服务器、EasyList、EasyPrivacy、EasyList China、EasyList Anti-adblock、1Hosts Lite 和 HaGeZi Multi PRO；网络域名/跟踪列表保持独立开关。
- 成人广告主机列表 `builtin://AdultSite_AdHosts.txt` 包含已知广告/弹窗供应商域名，默认关闭，且不包含成人内容站点根域名；用户可以在规则界面独立启用，可能影响使用这些供应商托管的站内资源。
- 旧版 AWAvenue Clash YAML 地址当前返回 404，升级迁移改为当前仓库的 Adblock 文本格式；已存在条目的启用位保留。

## FX 反诈规则目录边界

`[list:fx]` 只登记 `fxfile://anti_fraud_96110`，与普通广告、网页美化、下载提示和跟踪列表分离。随包 `fxrules/anti_fraud_96110.txt` 来自私有 `FX.txt` 明确标注的“国家反诈中心”域名和“反诈中心” IP 区段：5 个唯一域名、国家反诈中心 App 的一个包名、142 个来源标注的 `/32` IP。没有把后续“国家平台/备案域名”段落、`com.android.packageinstaller` 或 OEM 系统安全/安装器包混进 FX 规则，避免妨碍安装和系统更新。

电话 `96110` 本身不是 DNS 主机名；源仓库中没有可核验的 `96110` 域名/运营商端点清单，因此没有伪造域名规则，也不能通过这份规则拦截电话拨号、短信或蜂窝/IMS 信令。FX 主开关仍保持关闭默认值。来源 IP 的当前归属没有逐个独立验证，启用前应理解共享地址变化可能导致误拦。
