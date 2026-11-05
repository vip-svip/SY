# FX 1.0.0：GitHub 规则源码核对与本地执行审计

- 审计日期：2026-10-28
- 模块版本固定为 `1.0.0`，`versionCode=10000`
- 目标：规则文件随 KernelSU ZIP 离线安装；每类作用单独使用中文名称；规则只有进入实际解析/执行链才计为生效。

## 上游源码与本地文件

| 作用 | FX 本地规则文件 / 入口 | 已核对的 GitHub 源码 | 执行边界 |
|---|---|---|---|
| 手机网页打开 App、客户端下载提示 | `rulefiles/NoAppDownload.txt` / `builtin://NoAppDownload.txt` | [Noyllopa/NoAppDownload](https://github.com/Noyllopa/NoAppDownload/blob/master/NoAppDownload.txt) | 打包了完整上游快照；网页引擎只执行安全 CSS / 域名限定子集。上游 `:contains`、`+js` 等不是 FX 已支持语法。不能去除原生 Android App 启动页。 |
| 网页 AI/文档/设计/播放器 DOM 水印 | `Adblock_Watermark.txt`、`RunningCheese_Watermark.txt` | [RunningCheese Watermark](https://github.com/runningcheese/RunningCheese-Firefox/blob/master/Restore/Adblock_Watermark.txt) | 本地 DOM/CSS 规则；不能去除已合成进图片或视频像素的水印。 |
| 网页浮层/弹窗补充 | `RunningCheese_Popup.txt` | [RunningCheese Popup](https://github.com/runningcheese/RunningCheese-Firefox/blob/master/Restore/Adblock_Popup.txt) | 只执行安全 CSS 子集；上游 `+js` 过滤器需要专用脚本引擎，不在本轮宣称可执行。 |
| 成人网站广告元素 | `AdultSite_Elements_EasyList.txt` / `builtin://AdultSite_Elements_EasyList.txt` | [EasyList `adult_specific_hide.txt`](https://github.com/easylist/easylist/blob/master/easylist_adult/adult_specific_hide.txt) | 以完整站点专用列表为输入，执行器筛选安全的 CSS/域名限定选择器；不把它误当成 DNS 黑名单。 |
| 成人广告服务请求 | `AdultSite_AdServers.txt` | [EasyList `adult_adservers.txt`](https://github.com/easylist/easylist/blob/master/easylist_adult/adult_adservers.txt) | 请求过滤器按域名、第三方条件等解析；不把成人网站根域统统封掉。 |
| 成人站资源例外 | `AdultSite_Allowlist.txt` | [EasyList `adult_allowlist.txt`](https://github.com/easylist/easylist/blob/master/easylist_adult/adult_allowlist.txt) | 仅允许来源域名受限的例外；没有来源域限制的通用路径例外不会放大为全局放行。 |
| 成人广告服务弹窗 | `AdultSite_AdServersPopup.txt` | [EasyList `adult_adservers_popup.txt`](https://github.com/easylist/easylist/blob/master/easylist_adult/adult_adservers_popup.txt) | 独立请求规则组，保留 `$popup` 语义。 |
| 成人网站专用弹窗/跳转 | `AdultSite_SitePopup.txt` | [EasyList `adult_specific_block_popup.txt`](https://github.com/easylist/easylist/blob/master/easylist_adult/adult_specific_block_popup.txt) | 请求规则按站点/路径条件处理；高级或未知修饰符会安全跳过。 |
| 成人第三方弹窗 | `AdultSite_ThirdPartyPopup.txt` | [EasyList `adult_thirdparty_popup.txt`](https://github.com/easylist/easylist/blob/master/easylist_adult/adult_thirdparty_popup.txt) | 单独保留第三方与弹窗条件。 |
| 成人站点请求/脚本/路径 | `AdultSite_RequestRules.txt` | [EasyList `adult_specific_block.txt`](https://github.com/easylist/easylist/blob/master/easylist_adult/adult_specific_block.txt) | 不支持的 `$csp`、`$rewrite`、复杂通配/修饰符会被跳过，不会误当作完整支持。 |
| 成人站点第三方资源 | `AdultSite_ThirdParty.txt` | [EasyList `adult_thirdparty.txt`](https://github.com/easylist/easylist/blob/master/easylist_adult/adult_thirdparty.txt) | 保留资源类型与来源条件；站点根域不做一刀切封锁。 |
| 反广告拦截提示 | `Adblock_Warning_Removal.txt` | [EasyList Anti-Adblock](https://easylist-downloads.adblockplus.org/antiadblockfilters.txt) | 仅隐藏已知网页提示；不会让已被请求过滤器拦截的资源自动恢复。 |
| 成人广告域名补充 | `AdultSite_AdHosts.txt` | FX 仓库里的 `adhosts.yaml`：[vip-svip/FX](https://github.com/vip-svip/FX/blob/main/adhosts.yaml) | 只放广告供应商/投放域名，不包含成人内容站根域名。默认域名清单与网页元素/请求规则分开。 |

## 实际解析验收

以下是当前提取的包内源码在主机侧运行测试得到的结果，不是浏览器或 OnePlus 12 真机测试：

- 本地网页元素解析器：接受 **1,345 条**安全 CSS / 域名限定规则，覆盖 NoAppDownload、RunningCheese 水印/弹窗、EasyList 成人网站元素快照。
- 本地成人请求解析器：解析 **1,276 条**请求规则，其中 **37 条例外、130 条弹窗、740 条路径类规则**；对请求规则和元素隐藏规则分开加载。
- 本地规则源在没有远程订阅缓存时依然由 MITM 引擎加载；升级迁移回归验证用户原订阅、启用位和 `[list:rule]` / `[list:fx]` / `[list:block]` 的分区不被意外覆盖。
- `NoAppDownload.txt` 上游快照包含约 **879 条上游规则行**。数字不等于 FX 实际执行条数；高级脚本/文本匹配语法需要另行实现，不会被本轮测试冒充为已支持。

## 规则目录与升级迁移

- 规则目录中每个用途独立命名为中文；同类在线订阅仍保留为“在线备用”条目，默认关闭，防止重复下载同一类规则。
- 一个旧迁移版本的 `awk` 缺少默认 `print`，可能把 `[list:rule]` 中与广告/水印无关的用户订阅一起丢掉。本版已恢复默认输出，并增加备份恢复路径与迁移末尾去重回归；恢复路径保留已有行与启用状态，只补充备份中缺失的来源。
- `[list:block]` 仍为空；FX 的反诈中心/96110 规则继续保留在 `[list:fx]`，不混入一般广告规则。
- `yokoffing/filterlists/adult_annoyance_list.txt` 已核对，但它混有评论、相关内容等非广告元素以及高级语法，本轮没有冒险将其作为默认开启的本地全站规则；在目录中作为可选在线补充并默认关闭。

## 原生 App 开屏广告与 VPN 协同：边界说明

- 原生 Android App 启动页不是网页 DOM，不能靠 `NoAppDownload` 或 CSS 规则移除。FX 使用单独的 FXAdHook / LSPosed Hook 入口；需要 FX 主开关、应用类别、模块进程注入、LSPosed 中同一包名的作用域和远程目标配置都满足才会尝试匹配。SDK/资源启发式不是所有 App 的通用解。
- FX 与第三方 App VPN 的方案是 **root 透明代理叠加在外层 VPN 上**，并非让两个 Android `VpnService` 同时成为独立 VPN。当前代码根据唯一的 Android `VpnInfo` 读取接口和 owner UID，要求 sing-box 至少 1.12，并为节点/direct/DNS 出站绑定外层接口；外层 VPN UID 从 FX 自身重定向链路豁免，避免隧道递归。接口、UID 或绑定无法确认时会安全退回直连/暂停接管。
- **该逻辑已做源码、配置生成与回归测试，但没有 OnePlus 12 真机数据面验证，不能据此宣称你遇到的双 VPN 问题已经彻底解决。** 某些 VPN 按应用排除 root、拒绝绑定到其 TUN 接口、开启特殊 per-app/lockdown 路由时，仍可能无法链式工作，需要真机同时运行两者并检查实际出口/日志。`vpn-overlay-check.sh` 只验证接口身份、UID 和生成配置绑定，不等于真实出口探测。

## 2026-10-28 追加追修：外部 VPN UID 诊断链一致性

复核 VPN 页面与后端探测时发现：`scripts/external-vpn-probe.sh` 已从唯一有效的 Android `VpnInfo` 返回接口和 `owner_uid`，并支持 `ownerUid = 12345` 这种带空格的系统输出；但旧前端忽略 JSON 的 `owner_uid`，另起一次 `dumpsys | grep ownerUid=...`。当 ROM 输出键值两边带空格时，前端可能误报“外部 VPN UID 未知”，与后端对同一个 VPN 的识别结果不一致。

现已让前端直接消费后端同一次探测返回的 `owner_uid`，删除重复的第二次 `dumpsys` 查询，并新增回归覆盖带空格与不带空格两种 `VpnInfo` 格式。该修复消除一个具体的 UI/后端状态不一致问题；**它不等于已证明外部 VPN 实际数据面可以串联**，仍需在 OnePlus 12 上用正在运行的第三方 VPN、实际应用流量和出口检测验收。

## 上游地址

- [EasyList adult 规则目录](https://github.com/easylist/easylist/tree/master/easylist_adult)
- [NoAppDownload（MIT LICENSE）](https://github.com/Noyllopa/NoAppDownload)
- [RunningCheese 网页水印规则](https://github.com/runningcheese/RunningCheese-Firefox/blob/master/Restore/Adblock_Watermark.txt)
- [RunningCheese 网页弹窗规则](https://github.com/runningcheese/RunningCheese-Firefox/blob/master/Restore/Adblock_Popup.txt)
- [FX 广告域名源 `adhosts.yaml`](https://github.com/vip-svip/FX/blob/main/adhosts.yaml)
- [FXAdHook / LSPosed 集成源码](https://github.com/vip-svip/SY/tree/main/adhook)
- [XiaomiHelper SkipSplash 源码参考](https://github.com/HowieHChen/XiaomiHelper/blob/master/app/src/main/kotlin/dev/lackluster/mihelper/hook/rules/browser/SkipSplash.kt)
- [Fuck-AD SDK 识别表参考](https://github.com/hujiayucc/Fuck-AD)
