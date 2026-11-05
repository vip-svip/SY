# FX 1.0.0 规则集与 FX 反诈规则补齐报告

## 普通「规则集」

- 本地规则：`builtin://NoAppDownload.txt`、`builtin://Adblock_Watermark.txt`；旧黑名单迁移得到的 `builtin://privacy_ad_domains` 仍独立且默认关闭。
- 新增独立上游订阅入口（全部默认关闭）：秋风官方 Adblock 格式、AdGuard DNS Filter、AdAway Hosts、10007 Hosts、Chibi Hosts、AdGuard 广告服务器、AdGuard 跟踪服务器、EasyList、EasyPrivacy、EasyList China、EasyList Anti-adblock、NoAppDownload 上游、1Hosts Lite（AdGuard Hostlists Registry filter_24）、HaGeZi Multi PRO（Adblock 格式）。
- 旧秋风 Clash YAML 链接已被上游移除/返回 404；升级迁移改成当前仓库的 Adblock 文本格式。若用户旧设置启用了旧链接，则保留该条目的启用位；新加入的其他远程源默认关闭。
- 列表目录的映射使用的是可访问的公共上游，不是将私有仓库的全部文件静态复制进 APK。上游源在启用后才下载，避免升级后不经用户同意就改动网络。

## 「FX 规则」

- `scripts/default.conf` 的 `[list:fx]` 只含 `fxfile://anti_fraud_96110`，不混入普通广告、跟踪、网页水印或下载客户端提示规则。
- `fxrules/anti_fraud_96110.txt`：5 个唯一反诈中心域名、一个国家反诈中心 App 包名、142 个源文件标注的 IPv4 `/32` 地址。
- 来源是 `vip-svip/FX` 仓库 `FX.txt` 的明确区段，源 blob SHA：`ba2e792d448aba3ac0dcedd7e12f3b0dcfde998b`。
- 排除通用 Android 安装器、OEM 系统安全中心、宽泛的 `mps.gov.cn` / `miit.gov.cn`、后续国家平台和备案域名段；它们可能影响系统安装/更新或误拦无关政府服务。
- 上游 `FX.txt` 没有字面 `96110` 的域名/端点条目。96110 是电话号码，不是域名，当前没有伪造 DNS 条目；这条规则不能拦截电话/短信/IMS 信令。随包 IP 只沿用源文件标签，没有逐个独立核验当前归属。

## 兼容范围与验证

- 订阅入口完整可见，不等于导入器实现所有过滤语法。AdGuard/ABP/uBlock 规则仍只支持明确识别的子集；复杂 `$` 选项、脚本过滤和所有 cosmetic 规则不保证等价运行。
- 新增回归检查覆盖来源列表、默认关闭状态、迁移幂等、旧 AWAvenue URL 替换、黑名单保持空白、FX 区域与普通规则分离。静态/沙盒回归不等于 OnePlus 12 真机网络验收。
