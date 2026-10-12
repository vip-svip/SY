# SY · AdGuard Home 融合广告拦截（KernelSU / Magisk 模块）

> **AdGuard Home 内核 × uBlock Origin 语法** 融合过滤引擎
> 三层拦截体系 + 全生态脚本扩展 + 玻璃磨砂一体化面板
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
| 扩展 | 脚本扩展中心 | `scripts/scripts_ext.sh`，油猴脚本 / MITM 规则 / QX-Surge-Loon-SR 兼容 |
| 面板 | 一体化在线管理 | `webroot/index.html`（玻璃磨砂）+ `abserver serve` 内置 Web 服务 |

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
├── scripts/               # 核心 shell 引擎
│   ├── common.sh          # 共享库（路径 / 日志 / 配置 / JSON / 导入工具）
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
│   ├── proxynode.sh       # 网络代理
│   ├── scripts_ext.sh     # 脚本扩展中心
│   └── lists.sh / ruleset.sh / updater.sh / backup.sh / panel.sh / ...
├── config/                # 默认配置模板（不含任何内置拦截规则）
├── tests/                 # 自检套件
│   ├── run_tests.sh          # 引擎多轮自检（7 轮）
│   ├── run_e2e.sh            # 独立端到端验证（逐条人工推导期望值）
│   ├── run_module_checks.sh  # 模块级静态校验（9 组）
│   ├── corpus/01_mixed.txt   # 多语法混合语料
│   ├── gen_preview.py        # 由面板源码重新生成 ui-preview.html
│   └── expect.tsv            # 期望命中表
├── package.sh             # 打包脚本（预检 → 打包 → ZIP 校验）
├── ui-preview.html        # 玻璃磨砂面板静态效果预览（可直接用浏览器打开）
├── webroot/index.html     # 玻璃磨砂面板前端
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
abserver fetch  -url URL -out FILE [-timeout SEC]   # HTTP(S) 下载
abserver ca     -dir DIR [-cn NAME]                 # 生成根 CA
abserver proxy  -http :8080 -https :8443 ...        # MITM 代理
abserver serve  -addr :8848 -webroot webroot ...    # 面板 Web 服务
abserver token                                      # 生成访问令牌
```

## 安全机制

- **脚本沙箱**：导入脚本自动扫描敏感 API 特征（Runtime.exec / su / sms / contacts 等），命中即拦截。
- **按应用隔离**：MITM 通过 iptables UID 精准分流，仅对目标 APP 生效。
- **细粒度白名单**：支付 / 登录类域名默认放行，误拦截 1 秒恢复。
- **无系统分区改动**：全部通过 OverlayFS / bind mount 实现，卸载后完全恢复。

## 自检

```sh
sh tests/run_tests.sh all          # 引擎多轮自检（功能/幂等/作用域/启发式/性能/语法/健壮性）
sh tests/run_e2e.sh .              # 独立端到端验证（每类语法逐条推导期望值）
sh tests/run_module_checks.sh all  # 模块静态校验（语法/可移植性/清单/ABI/引用/面板/HTML/编码/链路）
sh package.sh                      # 打包并校验 ZIP（输出 dist/SY_<版本>.zip）
```

## 界面预览

浏览器直接打开 `ui-preview.html` 可查看玻璃磨砂面板的静态效果（样式与真实面板一致，数据为示例值），右上角可切换深浅色。

## 备份与恢复

面板「工具 → 备份与恢复」一键导出 / 恢复 `config`、`rules`、`scripts`。

## 免责声明

本模块用于个人设备的学习与研究。请遵守当地法律法规及各应用服务条款。作者不对使用本模块产生的任何后果负责。
