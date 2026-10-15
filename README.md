# SY · AdGuard Home 融合广告拦截（KernelSU / Magisk 模块）

> **AdGuard Home 内核 × uBlock Origin 语法** 融合过滤引擎
> 三层拦截体系 + 全生态脚本扩展 + **Shadowrocket 级代理路由层** + 极客控制台面板 + 内置管理器 App
> 基于 OverlayFS / bind mount 挂载，卸载无残留，**不占用 VPN 通道**，**完全离线可用**

---

## 特性总览

| 层级 | 能力 | 实现 |
|------|------|------|
| 规则引擎 | AdGuard Home × uBlock Origin 融合过滤 | `scripts/engine.sh` + `engine_parse/emit/hosts/test.awk` |
| 第一层 | DNS 级内核拦截 | `scripts/dns.sh` + hosts 绑定挂载，兼容 AdGuard / Pi-hole / uBO 规则 |
| 第二层 | MITM 中间人透明代理 | `scripts/mitm.sh` + `abserver proxy`，自动签发并注入根证书 |
| 第三层 | 增强开屏广告拦截 | `scripts/splash.sh`，内核级窗口监听 + 自动跳过 |
| 网络拦截 | 域名 / IP / 网段 / 端口 | `scripts/netblock.sh` |
| 网络代理 | 内置内核 / 节点 / 防 IP 泄露 | `scripts/proxynode.sh` |
| **代理路由层** | **Shadowrocket 级规则路由 / 策略组 / 连接管理 / 延迟测速** | `scripts/route.sh` + `abserver route`（配置编译）+ `abserver clash`（Clash API 客户端） |
| **内置 App** | **桌面管理器（LSPosed 式内置 App）** | `app/SYManager.apk` + `scripts/installapp.sh`（`pm` 会话式安装 + SELinux 上下文处理） |
| 扩展 | 脚本扩展中心 | `scripts/scripts_ext.sh`，油猴脚本 / MITM 规则 / QX-Surge-Loon-SR 兼容 |
| 面板 | 一体化在线管理 | `webroot/index.html`（**极客控制台** + 磨砂玻璃）+ `abserver serve` 内置 Web 服务 |

---

## 融合规则引擎

引擎以 **AdGuard Home 的规则语义为内核**，融合 **uBlock Origin 的匹配模型与优先级**，用纯 POSIX sh + POSIX awk 实现，**零外部依赖、完全离线可用**，在 Android（toybox / busybox awk）与桌面（gawk / mawk）上行为一致。

### 支持的规则语法（可任意混排于同一文件）

**AdBlock / AdGuard / uBlock Origin 网络规则**

```
||ads.example.com^              域锚定拦截（含子域）
|https://cdn.example.com/js/|   精确 URL 锚定
/ads?banner\d+/                 正则规则
@@||good.example.com^           例外放行
*  ^                            通配符与分隔符
```

**修饰符**

| 类别 | 修饰符 |
|------|--------|
| 优先级 | `$important`（重要拦截） |
| 规则控制 | `$badfilter`（关闭同形规则）、`$match-case` |
| 例外范围 | `$denyallow=` |
| 作用域 | `$client=`、`$ctag=`、`$domain=` |
| 来源判定 | `$third-party` / `$3p`、`$first-party` / `$1p` |
| DNS | `$dnsrewrite=` |
| 响应改写 | `$csp=`、`$removeparam=`、`$redirect=`、`$cookie=`、`$header=`、`$method=`、`$permissions=` |
| 资源类型 | `$document` `$script` `$image` `$stylesheet` `$xmlhttprequest` `$subdocument` `$websocket` `$webrtc` `$ping` `$object` `$media` `$font` `$other` `$popup` `$all` `$empty` `$mp4` `$inline-script` `$inline-font` `$generichide` `$specifichide` `$elemhide` `$genericblock` |

**Cosmetic / 注入（uBlock Origin 与 AdGuard 双语法）**

```
example.com##.ad-banner              元素隐藏
example.com#@#.ad-banner             取消隐藏
example.com#$#.ad { display:none }   AdGuard CSS 注入
example.com#?#div:has(> .sponsor)    扩展 CSS
example.com##+js(set-constant, ...)  uBO 脚本注入
example.com#%#//scriptlet('...')     AdGuard 脚本注入
example.com##^script:has-text(ads)   HTML 过滤
```

**hosts / dnsmasq / 纯域名**

```
0.0.0.0 ads.example.com       hosts 拦截
127.0.0.1 tracker.example.com
1.2.3.4   rewrite.example.com hosts 解析重写
address=/ads.example.com/     dnsmasq 拦截
local=/ads.example.com/       dnsmasq 本地应答
example.com                   纯域名清单
```

注释：`!` `#` `;` 以及 `[Adblock Plus 2.0]` 头。

### 优先级语义

与 uBlock Origin / AdGuard Home 完全一致：

```
重要放行  >  重要拦截  >  普通放行  >  普通拦截  >  未命中（默认放行）
```

- `$badfilter` 精确关闭同形规则；
- `$denyallow` 限定例外规则的作用范围；
- 例外规则（`@@`）在其自身带 `$important` 时提升为最高优先级。

### 命令

```sh
sh scripts/engine.sh build          # 编译全部规则
sh scripts/engine.sh stats          # 统计各分类产物数量
sh scripts/engine.sh syntax         # 多语法分布分析
sh scripts/engine.sh verify         # 规则体检（无效/冗余/冲突）
sh scripts/engine.sh test <domain>  # 单域名命中诊断（含浏览器侧 cosmetic 规则统计）
sh scripts/engine.sh testfile <f>   # 批量用例诊断（TSV 第 5 列为浏览器侧规则数）
sh scripts/engine.sh paths          # 输出各产物路径
sh scripts/engine.sh clear          # 清空编译产物
```

面板入口：**规则引擎** 页；`dns.sh` 亦提供 `engine-*` 子命令转发。

---

## 代理路由层（Shadowrocket 级能力）

底层用 **sing-box** 做数据面，`scripts/route.sh` + `abserver route` 做控制面，把 Shadowrocket / Clash 那套「规则路由 + 策略组 + 连接管理」完整搬到模块里。`profile.json` 是**唯一事实源**，面板、CLI、脚本都读写同一份，不再出现"面板改了脚本不认"的情况。

### 能力对照

| Shadowrocket 能力 | 本模块实现 |
|-------------------|-----------|
| 规则路由（有序规则表） | `abserver route` 把 `profile.json` 编译成 sing-box 配置；规则顺序即匹配顺序 |
| 策略组（select / url-test / fallback） | `ProxyGroup` 编译为 sing-box `selector` / `urltest` 出站 |
| 连接列表 / 强制关闭 | `abserver clash conn` / `clash close`（走 Clash API） |
| 延迟测速（批量） | `abserver clash delay`；面板「策略组与节点」页支持全部测速 |
| 实时流量曲线 | `abserver clash traffic`，面板 canvas 60 秒滚动窗口 |
| 内核日志流 | `abserver clash logs -level -lines` |
| DNS 分流 / FakeIP | `profile.json` 的 `dns` 段，按内核版本自动切换语法 |
| 规则集（geo 数据） | `rule_set` + `.srs` 二进制格式，**16 个内置规则集随模块离线打包** |
| 节点订阅 / 分享链接 | `route import`（vmess / vless / trojan / ss / ssr / hysteria2 / tuic / share-link / clash-yaml / base64 订阅） |

### 命令

```sh
sh scripts/route.sh status-json            # 面板用：内核 / profile / 规则集状态
sh scripts/route.sh summary                # 面板用：节点 / 策略组 / 规则 / 统计
sh scripts/route.sh rulesets               # 面板用：内置 + 本地规则集清单
sh scripts/route.sh set-profile            # 面板用：写入 profile.json（先做 JSON 合法性校验）
sh scripts/route.sh reload                 # 重编译并热重启内核
sh scripts/route.sh clash <sub> -json      # 透传 Clash API（status/conn/traffic/proxies/delay/select/mode/logs/close）

# 引擎侧（abserver route ...）
abserver route compile   -sb-version 1.14.3 -mirror testingcf   # 编译内核配置
abserver route lint                                             # 规则体检（无效/冗余/冲突）
abserver route test      -domain www.google.com -port 443 -v     # 单条流量命中诊断（逐条列出判定步骤）
abserver route explain                                          # 解释某条规则为何命中/不命中
abserver route import    -in links.txt -format share-links      # 节点导入
abserver route mirrors   -probe                                 # 规则集镜像测速
abserver route fetch-rules -dir rulesets                        # 离线规则集抓取
abserver route dnsprobe  -domain www.baidu.com                  # DNS 上游真实测速（UDP / DoT / DoH）
abserver clash           -api 127.0.0.1:9090 status -json       # Clash API 客户端
```

### 跨客户端规则语法

面板与 `profile.json` 直接吃各家客户端的写法，内部统一归一化（`NormalizeKind`）：

```
DST-PORT / DEST-PORT / DESTINATION-PORT   → 目标端口
HOST / HOST-SUFFIX / HOST-KEYWORD / HOST-WILDCARD
DOMAIN-SET / IP-SET / RULE-SET            → 规则集
URL / URL-REGEX                           → URL 正则
SRC-IP / SOURCE-IP-CIDR · IP6-CIDR / IPV6-CIDR
GEO-SITE / GEO-IP / ASN · PROCESS / PROCESS-NAME-REGEX
FINAL-MATCH / MATCH-ALL                   → 兜底匹配
```

> 这条归一化修掉了一个真实丢规则 bug：Shadowrocket / Clash 写法的 `DST-PORT` 原先会被判为"未知规则类型"而**整条丢弃**且只留一条 warn。

### 内核版本适配

sing-box 各版本语法断代严重，编译器按目标内核版本分支输出（`-sb-version`，或 `-kernel` 自动读版本）：

| 字段 | 1.11 | 1.12 | 1.13 | 1.14 |
|------|------|------|------|------|
| DNS 服务器 | 必须 `address` | `type`/`server` 可用 | 同左 | **`address` 已移除** |
| `default_domain_resolver` | 不支持 | 起支持 | 同左 | 同左 |
| 入站 `sniff` | 可用 | 可用 | **已移除**（改路由规则 `action=sniff`） | 已移除 |
| fakeip 区间 | `dns.fakeip` 块 | 服务器 `inet4_range` | 同左 | **`dns.fakeip` 块已移除** |
| `download_detour` | 可用 | 可用 | 可用 | 废弃 |

### 规则集镜像（中国大陆实测）

`abserver route mirrors -probe` 实测结果（2026-10，中国大陆网络）：

| 镜像 | 结果 | 耗时 |
|------|------|------|
| `testingcf.jsdelivr.net` | 200 | 0.30 s ← **默认** |
| `fastly.jsdelivr.net` | 200 | 0.87 s |
| `gh-proxy.com` | 200 | 1.05 s |
| `ghproxy.net` | 200 | 1.27 s |
| `cdn.jsdelivr.net` | 超时 | — |

> 原先默认用的就是 `cdn.jsdelivr.net`，在国内等于**默认配置不可用**；现已切到 `testingcf`。

---

## 内置管理器 App

模块里打包了一个极轻的原生 App（`app/SYManager.apk`，约 53 KB），安装时自动装到桌面，作用等同 LSPosed 的内置管理器：

- **桌面图标 / 快捷磁贴** 一键启停代理与拦截；
- **常驻通知** 显示实时速率与连接数；
- **内置 WebView** 直接打开本面板，不依赖浏览器；
- **完全离线**，不联网、不申请敏感权限。

安装由 `scripts/installapp.sh` 负责，三处调用（`customize.sh` 装机时、面板按钮、开机兜底）共用同一份逻辑，踩过的坑都写在脚本头注释里：

1. APK 在 `/data/adb/modules` 下时 SELinux 上下文是模块的，`installd` 读不了 → 先 `chcon u:object_r:apk_data_file:s0`；
2. Android 11+ 多用户必须显式 `--user 0`；
3. `pm install` 失败时退出码经常仍是 0 → 必须匹配输出里的 `Success`；
4. 部分设备只有会话式安装才成功 → `pm install-create / -write / -commit` 兜底。

---

## 目录结构

```
SY/
├── module.prop            # 模块元信息
├── customize.sh           # 安装脚本（自动选择 ABI 二进制）
├── post-fs-data.sh        # hosts 绑定 + 证书 OverlayFS 准备
├── service.sh             # 启动服务（规则 / 代理 / 开屏 / 面板）
├── action.sh              # KernelSU 面板「操作」按钮 → 启动面板
├── uninstall.sh           # 卸载清理（含证书子模块）
├── .gitattributes         # 统一 LF 换行，防止 Android 上语法错误
├── bin/                   # abserver 三架构静态二进制
│   └── abserver-arm64 / abserver-arm / abserver-amd64
├── app/                   # 内置管理器 App
│   └── SYManager.apk      # 约 53 KB，安装时自动装到桌面
├── rulesets/              # 16 个内置 .srs 离线规则集（sing-box binary 格式）
├── src/                   # abserver 的 Go 源码（编译产物落到 bin/）
│   ├── sbcfg.go           # sing-box 配置编译器（按内核版本分支）
│   ├── rules.go           # 规则模型 / 解析 / 跨客户端别名归一化 / 命中诊断
│   ├── cmd_route.go       # route 子命令族
│   ├── cmd_dnsprobe.go    # DNS 上游真实测速（手写 DNS 报文，UDP/DoT/DoH）
│   ├── api_clash.go       # /api/clash 端点
│   ├── clashapi.go        # Clash API 客户端
│   └── serve.go           # 面板 Web 服务 + 脚本桥（/api/route、/api/exec）
├── scripts/               # 核心 shell 引擎
│   ├── common.sh          # 共享库（路径 / 日志 / 配置 / JSON / base64 / 导入工具）
│   ├── ctl.sh             # 统一控制入口
│   ├── engine.sh          # 融合过滤引擎驱动器
│   ├── engine_parse.awk   # 多语法解析器（TSV 规范化）
│   ├── engine_emit.awk    # 分类发射器
│   ├── engine_hosts.awk   # hosts 生成器（优先级求值）
│   ├── engine_test.awk    # 命中诊断器（单域 / 批量）
│   ├── filter.sh          # 旧 filter-* 命令兼容层
│   ├── dns.sh             # DNS 拦截层
│   ├── dnssrv.sh          # 独立 DNS 接管
│   ├── mitm.sh            # MITM 透明代理层
│   ├── splash.sh          # 开屏跳过层
│   ├── netblock.sh        # 网络拦截
│   ├── proxynode.sh       # 网络代理（gen_config 已委托 route.sh）
│   ├── route.sh           # 代理路由层（profile 单一事实源）
│   ├── installapp.sh      # 内置 App 安装 / 卸载 / 状态
│   ├── selfcheck.sh       # 自检 / 低风险自愈
│   ├── scripts_ext.sh     # 脚本扩展中心
│   └── lists.sh / ruleset.sh / updater.sh / backup.sh / panel.sh / ...
├── config/                # 默认配置模板（不含任何内置拦截规则）
├── tests/                 # 自检套件
│   ├── run_tests.sh          # 引擎多轮自检（7 轮）
│   ├── run_e2e.sh            # 独立端到端验证（逐条人工推导期望值）
│   ├── run_module_checks.sh  # 模块级静态校验（10 组 A–J）
│   ├── run_panel_api.sh      # 起真 abserver serve，逐端点打 HTTP（29 项）
│   ├── run_kernel_compat.sh  # 真内核双版本 check + run（1.11.15 / 1.14.3）
│   ├── run_route_e2e.sh      # 真流量验证规则命中 + Clash API 策略组切换
│   ├── verify_ui_assets.py   # 面板资产回归（318 个 id / 225 个 action 零丢失）
│   ├── ui_baseline.json      # 面板资产基线清单
│   ├── ui_runtime_check.js   # jsdom 真实执行面板 JS，模拟导航交互
│   ├── ui_shot_panel.js      # 真实 Chromium 逐页渲染线上面板并截图（注入 KSU 桩）
│   ├── ui_screenshot.js      # Chromium 渲染截图 + 布局/裁切/性能断言
│   ├── perf_compare.py       # 真机渲染性能对比（dumpsys gfxinfo，多轮取中位数）
│   ├── make_heavy_variant.py # 生成"重玻璃"受控变体（DOM 不变，仅换 CSS）
│   ├── perf_serve.sh         # 在设备上并行起多个面板服务，供同机多版本对比
│   ├── corpus/01_mixed.txt   # 多语法混合语料
│   ├── gen_preview.py        # 由面板源码重新生成 ui-preview.html
│   └── expect.tsv            # 期望命中表
├── package.sh             # 打包脚本（预检 → 打包 → ZIP 校验 → SHA256）
├── tools/                 # 发布工程辅助（不随模块打包）
│   ├── push_api.py           # Git 直连被限速时，改走 REST API 推送提交
│   ├── verify_remote.py      # 逐项比对远端 tree 与本地 HEAD（path/mode/blob）
│   ├── verify_files.py       # 比对若干关键文件的远端内容与本地（走 Contents API）
│   └── release_update.py     # 替换 Release 附件并复核大小
├── ui-preview.html        # 面板静态效果预览（可直接用浏览器打开）
├── webroot/index.html     # 面板前端（AdGuard Home 布局骨架 + 磨砂玻璃）
├── system/etc/security/cacerts/  # 根证书挂载目标
└── META-INF/              # 刷入引导
```

---

## 安装

1. 在 KernelSU / Magisk 管理器中刷入本模块 ZIP。
2. 安装脚本按设备 ABI 自动选择 `abserver` 二进制；`update-binary` 会依次探测 Magisk → KernelSU 的 `util_functions.sh`，两者都缺失时自动降级为内置安装器。
3. 重启设备，`service.sh` 自动应用规则并启动各项服务。
4. 根证书会作为独立子模块 `SY_cert` 释放，用于 MITM 抓包；随主模块卸载一并清理。

> KernelSU 说明：本模块不依赖 metamodule 即可工作（hosts 与证书均通过显式 bind mount 生效）。

## 使用面板

- **KernelSU 内打开**：KernelSU 管理器中点击本模块卡片的 **打开** 按钮（读取 `webroot/`）。
- **操作按钮**：点击模块卡片的操作按钮运行 `action.sh`，输出本地 / 局域网访问地址与令牌。
- **局域网访问**：浏览器打开 `http://<手机IP>:8848?token=<令牌>`。

## 服务组件 (abserver)

```
abserver fetch   -url URL -out FILE [-timeout SEC]   # HTTP(S) 下载
abserver ca      -dir DIR [-cn NAME]                 # 生成根 CA
abserver proxy   -http :8080 -https :8443 ...        # MITM 代理
abserver serve   -addr :8848 -webroot webroot ...    # 面板 Web 服务
abserver token                                       # 生成访问令牌
abserver route   <sub>                               # 代理路由层（compile/lint/test/explain/import/…）
abserver clash   -api HOST:PORT <sub>                # Clash API 客户端（status/conn/proxies/delay/…）
```

`abserver serve` 除静态面板外还暴露两个脚本桥，面板与 HTTP 两种运行环境走同一套逻辑：

| 端点 | 作用 |
|------|------|
| `GET /api/exec?cmd=…` | 执行 shell（等价 KernelSU 的 `ksu.exec`） |
| `POST /api/route` `{"args":["summary"]}` | 透传到 `route.sh`，多参数走 JSON 体（避开超长命令行） |
| `GET /api/clash?sub=status\|conn\|traffic\|proxies\|delay\|select\|mode\|logs\|close` | Clash API 代理 |
| `GET /api/proxy` `/api/dns` … | 其余脚本子命令透传 |

鉴权接受 `X-Auth-Token` 请求头或 `?token=` 查询参数；静态资源注入 `window.__SY_TOKEN__`，面板自身请求无需再手工拼 token。

## 安全机制

- **脚本沙箱**：导入脚本自动扫描敏感 API 特征（Runtime.exec / su / sms / contacts 等），命中即拦截。
- **按应用隔离**：MITM 通过 iptables UID 精准分流，仅对目标 APP 生效。
- **细粒度白名单**：支付 / 登录类域名默认放行，误拦截 1 秒恢复。
- **无系统分区改动**：全部通过 OverlayFS / bind mount 实现，卸载后完全恢复。

## 自检

```sh
sh tests/run_tests.sh all          # 引擎多轮自检（功能/幂等/作用域/启发式/性能/语法/健壮性）  92 项
sh tests/run_e2e.sh .              # 独立端到端验证（每类语法逐条推导期望值）              81 项
sh tests/run_module_checks.sh all  # 模块静态校验（语法/可移植性/清单/ABI/引用/面板/HTML/编码/链路/UI 运行时） 331 项
sh tests/run_module_checks.sh J    # 只跑面板资产回归 + jsdom 运行时 + Chromium 布局断言
sh tests/run_panel_api.sh          # 起真 abserver serve，逐端点打 HTTP（含鉴权 / 静态注入 / 多参数 POST）  29 项
sh tests/run_kernel_compat.sh      # 真 sing-box 内核双版本 check + run（1.11.15 / 1.14.3）  10 项
sh tests/run_route_e2e.sh          # 真流量验证四种规则命中 + Clash API 策略组切换              9 项
python tests/verify_ui_assets.py   # 面板资产回归（318 id / 225 action / 131 函数）
python tests/gen_preview.py        # 由 webroot/index.html 重新生成 ui-preview.html
node tests/ui_runtime_check.js     # jsdom 真实执行面板 JS，模拟导航交互
node tests/ui_shot_panel.js shots  # 真实 Chromium 逐页渲染线上面板并截图（注入 KSU 假数据）
python tests/perf_compare.py <序列号> "新面板=http://127.0.0.1:8848/index.html" \
                                  "旧面板=http://127.0.0.1:8849/index.html"   # 真机性能对比
sh package.sh                      # 打包并校验 ZIP（输出 dist/SY_<版本>.zip + .sha256）
```

> `run_module_checks.sh` 的 J 组会在检测到 jsdom / playwright 时自动启用真实 DOM 与真实浏览器断言
> （下拉是否被裁切、各视口是否横向溢出、实际启用背景模糊的元素数量）；未安装时自动跳过。

## 界面预览

浏览器直接打开 `ui-preview.html` 可查看面板静态效果（样式与真实面板一致，数据为示例值），右上角可切换深浅色。

### 面板设计说明

面板是一套 **极客控制台**：沿用 AdGuard Home 的卡片栅格骨架与磨砂玻璃质感，但信息架构按「代理路由 / 过滤 / 工具 / 设置」重新编排，把 21 个页面收进 5 个导航分组。

| 项目 | 取值 |
|------|------|
| 布局 | 顶部 sticky 玻璃 `header` + 横向 `nav-tabs`（总览 / 代理路由▾ / 过滤▾ / 工具▾ / 设置▾）+ `page-title` 页面标题栏 + `col-12`/`col-6` 卡片栅格 |
| 暗色令牌（默认） | `--bgcolor:#0b0f14`、`--bgcolor-2:#0f151c`、`--mcolor:#e6edf3`、`--scolor:#656d76` |
| 浅色令牌 | `--bgcolor:#f6f8fa`、`--bgcolor-2:#eef1f5`、`--mcolor:#1f2328` |
| 强调色 | `--accent:#58a6ff`、`--green:#3fb950`、`--amber:#d29922`、`--red:#f85149`、`--purple:#a371f7`、`--cyan:#2dd4bf` |
| 延迟色阶 | `--lat0:#3fb950` → `--lat1:#7ee787` → `--lat2:#d29922` → `--lat3:#f0883e` → `--lat4:#f85149`（`<100 / <200 / <400 / <800 / 其余` ms） |
| 磨砂玻璃 | `backdrop-filter` **仅**施加在 `.header` 与浮层 `.dropdown-menu` 上 |
| 极客组件 | `.seg` 分段控件、`.spark` canvas 曲线、`.nrow` 节点行、`.lat.p0~p4` 延迟徽标、`.ctbl` 连接表、`.term` 终端日志窗、`.rrow` 规则行、`.wgrid` 磁贴网格、`.diag` 命中诊断、`.foldbox` 折叠块 |

**导航分组（21 页）**

```
总览
代理路由 ▾  代理总览 · 策略组与节点 · 实时连接 · 规则与分流 · DNS 与查询 · 内核日志 · 内核与配置 · 节点与订阅
过滤     ▾  DNS 拦截列表 · 自定义过滤规则 · 加密过滤·根证书 · 拦截服务 · 通知过滤
工具     ▾  内置管理器 App · 脚本扩展 · 开屏跳过 · 工具与备份
设置     ▾  常规设置 · DNS 设置 · 系统与日志
```

极客向能力集中在新增的 9 个页面里：实时流量曲线（60 秒滚动窗口）、策略组折叠 + 批量测速 + 手动切换、连接表 + 强制关闭单条连接、规则体检 + 单条流量命中诊断（逐条列出判定步骤）、DNS 上游真实测速、内核日志流（级别 / 行数 / 持续抓取）、`profile.json` 在线编辑 + 编译产物对照、内置 App 一键安装/卸载/打开、系统自检 + 诊断包导出。

**性能约定（低端机不卡的关键）**

- `backdrop-filter` 全页只允许出现在 `.header` 与 `.dropdown-menu` 两处；一旦下放到 `.card` / `.btn` / 输入框，页面上两百多个元素会各开一层背景模糊，Android WebView 必然卡死。
- 不使用 SVG `feTurbulence` 噪点层（每帧重算，代价极高），改用 `body::before` 的静态 `radial-gradient` 光斑为玻璃提供可模糊底色。
- 过渡只作用于 `transform` / `opacity` / `background-color` / `border-color`；全页无 `animation` 声明。
- 导航不设 `overflow`，窄屏折行而非横向滚动 —— 否则下拉菜单会被滚动容器裁掉。

以上四条均由 `tests/run_module_checks.sh` J 组与 `tests/ui_screenshot.js` 自动断言。

### 真机实测：卡顿确实是可量化复现的

上面四条是"设计约束"，下面是同一台真机上实测出的**违反约束的代价**。

设备：Redmi 23076RA4CB（sky2）· Android 13 · arm64-v8a · KernelSU v3.3.0 · 系统 WebView 111
· 1080×2460 @ 60Hz · 用系统浏览器加载面板，`dumpsys gfxinfo` 采样，每项 3 轮取中位数。

对比三方：

- **新面板** = 当前发布版本（极客控制台 + 磨砂玻璃，`backdrop-filter` 仅 2 处）
- **旧面板** = v1 历史版本（原 SY 界面）
- **重玻璃变体** = 用 `make_heavy_variant.py` 从**当前面板**生成，DOM / 内容 / 页高**完全相同**，只把 `backdrop-filter` 铺回全页并加回 `feTurbulence` 噪点层

| 指标 | 新面板 | 旧面板 (v1) | 重玻璃变体（受控） |
|------|--------|-------------|-------------------|
| 卡顿帧占比 | **3.68 %** | 100 % | 100 % |
| P50 帧耗时 | **19 ms** | 150 ms | 250 ms |
| P90 帧耗时 | **22 ms** | 200 ms | 400 ms |
| P95 帧耗时 | **24 ms** | 200 ms | 550 ms |
| P99 帧耗时 | **31 ms** | 200 ms | 750 ms |
| 丢 Vsync 率 | **0.40 %** | 90.85 % | 99.47 % |
| UI 线程超时率 | **2.38 %** | 90.85 % | 92.11 % |
| 绘制命令超时率 | **3.72 %** | 100 % | 100 % |
| 采样窗口内渲染帧数 | **1262** | 284 | 190 |

结论：

1. **修好了** —— P50 帧耗时从 150 ms 降到 19 ms（**7.9×**），卡顿帧从 100 % 降到 3.68 %，丢 Vsync 率从 90.85 % 降到 0.40 %（**227×**）。
2. **根因确认** —— 第三列是**受控实验**：DOM 一字未改，只把玻璃模糊铺回全页，P50 立刻从 19 ms 劣化到 250 ms（**13×**），丢 Vsync 率从 0.40 % 冲到 99.47 %。这排除了"是不是内容太多""是不是别的代码"等一切解释，卡顿就是 `backdrop-filter` 铺满全页 + `feTurbulence` 噪点层造成的。
3. 复现方式：`tests/perf_compare.py`（完整原始输出见 `tests/perf_results.txt`）。

> 已知限制：Android 13 起应用窗口层走 BLAST 缓冲，`SurfaceFlinger --latency` 对该层返回全零，
> 因此呈现间隔无法采集；结论以 gfxinfo 的帧耗时分位、卡顿帧占比与**按帧数归一化**的超时率为准。

## 备份与恢复

面板「工具 → 备份与恢复」一键导出 / 恢复 `config`、`rules`、`scripts`。

## 免责声明

本模块用于个人设备的学习与研究。请遵守当地法律法规及各应用服务条款。作者不对使用本模块产生的任何后果负责。
