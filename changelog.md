# SY 模块更新日志

## v1.0.0 — AdGuard Home × uBlock Origin 融合版

> 首个正式版本。以 AdGuard Home 的规则语义为内核，融合 uBlock Origin 的匹配与优先级模型，
> 纯 POSIX sh + POSIX awk 实现，**零外部依赖、完全离线可用**，不占用 VPN 通道。

### 融合过滤引擎（`scripts/engine.sh`）
- 全语法支持，可任意混排于同一规则文件：
  - **AdBlock / AdGuard / uBO 网络规则**：`||domain^`、`|http://...|`、`domain`、`/regex/`、`@@` 例外、`*` 与 `^` 分隔符
  - **修饰符**：`$important` `$badfilter` `$dnsrewrite=` `$client=` `$ctag=` `$denyallow=` `$domain=` `$third-party/$3p` `$first-party/$1p` `$match-case` `$csp=` `$removeparam=` `$redirect=` `$cookie=` `$header=` `$method=` `$permissions=`，以及全部资源类型（`$document` `$script` `$image` `$stylesheet` `$xmlhttprequest` `$subdocument` `$websocket` `$webrtc` `$ping` `$object` `$media` `$font` `$other` `$popup` `$all` `$empty` `$mp4` `$inline-script` `$inline-font` `$generichide` `$specifichide` `$elemhide` `$genericblock`）
  - **Cosmetic / 注入（uBO 与 AdGuard 双语法）**：`##` `#@#` `#$#` `#?#` `#%#` `$$`、`##+js(name,args)`、`#%#//scriptlet('name','args')`、`##^html-filter`
  - **hosts 格式**：`0.0.0.0 d` / `127.0.0.1 d` / `::1 d` / `IP d`（解析重写）
  - **dnsmasq 格式**：`address=/d/` `address=/d/IP` `local=/d/` `server=/d/`
  - **纯域名清单**、**正则规则**、注释（`!` `#` `;` `[Adblock Plus 2.0]`）
- 优先级语义与 uBlock / AdGuard Home 完全一致：**重要放行 > 重要拦截 > 普通放行 > 普通拦截**；`$badfilter` 关闭同形规则；`$denyallow` 限定例外范围。
- 规则编译为分类产物：`block` / `block_imp` / `allow` / `allow_imp` / `pattern_*` / `heuristic_*` / `regex_*` / `rewrite` / `allow_deny` / `cosmetic_*` / `scriptlets` / `js_inject` / `css_inject` / `ext_css` / `html_filter`，并生成可直接给系统使用的 `hosts` 与 AdGuard/dnsmasq 格式 `dnsrules.conf`。
- **规则体检**（`engine verify`）：统计无效规则、`$badfilter` 数量、冗余层级、冲突项。
- **命中诊断**（`engine test <domain>` / `testfile <file>`）：按后缀逐级求值，输出命中的规则原文、修饰符与重写结果，并单独统计作用于该域名的浏览器侧（cosmetic / 脚本注入）规则；支持批量用例与完整 URL 入参。

### 面板「规则引擎」页
- 融合引擎统计、多语法分布、规则体检、命中诊断、编译产物一屏总览。
- 一键编译 / 语法分析 / 体检 / 诊断 / 清空。

### 界面：玻璃磨砂质感
- 全新玻璃拟态设计系统：`backdrop-filter` 毛玻璃模糊 + 饱和度增强、SVG `feTurbulence` 噪点纹理、彩色光晕底、镜面高光、多层阴影。
- 提供 `@supports not` 降级方案，不支持 `backdrop-filter` 的设备自动回退为实色面板。
- 深浅色主题同步适配，所有原有页面与交互保持不变。

### 拦截能力
- 三层拦截：DNS/hosts 内核拦截 + MITM 透明代理 + 开屏广告跳过。
- 网络拦截、网络代理（含节点管理）、脚本扩展中心、通知过滤、规则仓库订阅管理。
- 面板服务（局域网后台）：同一 Wi-Fi 下用手机/电脑浏览器即可管理。
- 日志界面：面板内直接查看/清空 dns、mitm、proxy、内核等运行日志。
- 模块在线更新：面板与 KernelSU/Magisk 内直接读取 GitHub Release 更新。
- DNS 拦截域名计数为准确值（去重并扣除白名单）。

### 修复
- **修复 CRLF 换行导致的安装/运行失败**：仓库内全部文本文件（含 shell 脚本、安装器 `update-binary` / `updater-script`、配置与清单）统一规范化为 LF，并新增 `.gitattributes` 固化 `eol=lf`，避免在 Android 的 mksh / toybox sh 上出现语法错误。
- **修复面板「添加通知关键词」失效**：面板调用了脚本不存在的子命令 `add-keyword`，已更正为 `keyword-add`。
- **修复 `ctl.sh scripts` 指向不存在的脚本**：`scripts` 子命令原先会去执行不存在的 `scripts/scripts.sh`，现已正确别名到 `scripts_ext.sh`。
- **修复安装引导在无 `util_functions.sh` 环境直接失败**：`update-binary` 现按 Magisk → KernelSU 顺序探测，两者都缺失时自动降级为自包含安装器（解压、权限、执行 `customize.sh`、落地到 `modules_update`），并修正 Magisk 低版本误判（KernelSU 中 `MAGISK_VER_CODE` 恒为 25200）。
- **修复 `engine_test.awk` 缺参致命错误**：未传入规则表时不再 `fatal`，改为输出可读错误。
- **修复正则规则无法命中**：解析器此前把 `/.../` 的定界符一并存入规则值，导致诊断与匹配永远失败；现内部存裸正则、输出时补回定界符。
- **修复纯修饰符行被误判为模式规则**：形如 `$important`、`$script,image` 的行（无模式）现正确识别为无效规则，不再污染模式表。
- **修复畸形行被误判为元素隐藏规则**：形如 `$$$%%%` 的纯标点行不再被当作 HTML 过滤规则，统一计入无效统计。
- **修复规则诊断只接受裸域名**：`engine test` 现同时接受 `host/path` 与完整 URL，可诊断路径型正则与 URL 模式规则。
- **修复规则诊断中 `$dnsrewrite` 规则无法命中**：重写类规则现纳入独立优先级通道参与求值。
- **修复规则诊断不体现浏览器侧规则**：命中诊断现单独统计并列出作用于该域名的元素隐藏、脚本注入、CSS 注入等规则；同时修复 cosmetic 作用域父域继承的差一错误（`sub.example.com` 此前漏继承 `example.com##` 规则），并支持 `~` 取反与实体通配（`example.*`）。
- **修复规则体检中 `$badfilter` 数量恒为 0**：`$badfilter` 记录在编译阶段即被剔除，现由关闭阶段单独计数后回传给体检结果。
- **修复 hosts 统计为空、dnsmasq 多域名解析错误、畸形输入未计入无效统计**等问题。
- **修复多语法分布统计失真**：「修饰符」此前恒为 0（带 `$` 的规则被全部归入 adblock），现按可辨识语法特征分类。

### 优化
- 解析 → 分类发射 → hosts 生成 → DNS 规则导出全链路单次装载，避免逐行 fork，20000 条规则规模下依然快速。
- 严格规避 gawk 专有特性（`gensub` / `asort` / `PROCINFO` / `IGNORECASE` 等），在 gawk / mawk / busybox awk / toybox awk 上行为一致。
- 规则产物排序去重，重复编译结果可复现（幂等）。
- 证书子模块版本号改为从主模块 `module.prop` 动态读取，消除版本漂移。

### 测试
- 引擎多轮自检套件（`tests/run_tests.sh`，7 轮 92 项）、独立端到端验证（`tests/run_e2e.sh`，81 项）与模块级静态校验套件（`tests/run_module_checks.sh`，9 组 295 项）。
- 打包脚本 `package.sh`（预检 → 打包 → ZIP 内回读校验）与玻璃磨砂面板静态预览 `ui-preview.html`。
