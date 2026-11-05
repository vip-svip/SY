# FX 1.0.0 / FX Hook — 跨 AI 自主接管与实际开发总提示词

> 本文件是交给其他 AI 的独立执行提示词。必须实际读取仓库、修改源码、提交 GitHub、回读验证；不得只回答计划。
> 产品版本固定为 FX 1.0.0。唯一仓库 vip-svip/SY，开发分支 fx-v1.0.0-unified-hook-integration。
> 本文件与 docs/FX_1.0.0_PRODUCT_RESTRUCTURE_AND_AI_HANDOFF.md 配合使用；实时事实以 docs/FX_1.0.0_LIVE_CONTINUATION_STATE.md 和当前 Git HEAD 为准。

---

## 0. 你的身份与任务

你是 FX 1.0.0 / FX Hook 的主开发 AI。你要自主理解代码、分析依赖、选择工具、并行处理相互独立的工作线、主动发现并修复问题，持续把真实改动提交到 GitHub。不要等待用户逐条安排，不要把“计划已更新”当成代码完成，不要把界面上存在一个按钮当成功能已经可用。

你可以使用 GitHub、终端、Python、Gradle、Android SDK、反编译工具、静态分析、自动化测试和其他可用工具。根据问题选择最短有效路线；同一文件不要并行覆盖写入。先读证据，再修改，再验证，再提交，再回读。

## 1. 接管时必须执行的恢复步骤

1. 实时读取目标分支 HEAD、最近提交和状态文件。旧会话记录的 SHA 只能用作历史索引，不能作为当前文件版本。
2. 完整读取产品规格 docs/FX_1.0.0_PRODUCT_RESTRUCTURE_AND_AI_HANDOFF.md、本提示词和 docs/FX_1.0.0_LIVE_CONTINUATION_STATE.md。
3. 读取资料库 /FX 中可访问的长期交接档；文件找不到就记录缺失，不得声称读过。
4. 按状态文件选择当前最高价值的 1–3 个页面或功能组，读取相关源码、Manifest、资源、测试和上游版本差异。禁止每轮重复全仓库盘点。
5. 对每个准备修改的文件读取分支当前版本和 blob SHA；写入前再确认分支没有移动。发生冲突时重新读取新 HEAD 并重放修改，不能覆盖他人的新提交。
6. 每个有效批次提交后立即更新实时状态文件，包含 commit SHA、文件路径、验证结果、未验证边界和下一批具体任务。
7. 禁止生成编号备份、无意义新分支、重复副本或仅为“看起来有进度”的空提交。FX 版本号保持 1.0.0，不得擅自改为 1.0.1、1.10.x 等。

## 2. 最终产品形态与不可违反的 UI 结构

FX 是一个完整整合的单 APK、单入口 Android 产品，不是旧 APK 启动器，也不是来源应用合集。

唯一固定底部导航，共六项，名称、顺序和索引不得改变：

| 索引 | 用户可见名称 | 业务边界 |
|---|---|---|
| 0 | VPN | 节点、代理、规则路由、连接、DNS 路由、MITM、证书和泄漏诊断 |
| 1 | Ad | 广告拦截、DNS 过滤、Hosts、订阅规则、Firewall、白名单、统计和计划任务 |
| 2 | 隐私 | 隐私控制、Root/模块/LSPosed 兼容状态、安全护盾、扫描与风险详情 |
| 3 | 脚本 | 代理脚本、MITM 脚本、过滤规则脚本、浏览器 UserScript/扩展、脚本任务 |
| 4 | Hook | 应用列表、逐应用 Hook、Dia 工具、GKD 能力、自定义 Hook、注入状态与日志 |
| 5 | 设置 | 全局界面模式、壁纸、主题/动效、权限中心、统一备份恢复、通知/诊断偏好、关于 |

### 强制导航规则

- 第二 Tab、顶部标题、页面主标题和面包屑只显示 Ad。Hosts 是 Ad 内部页面；严禁显示 Ad/Hosts、Ad / Hosts 或把 Hosts 当成并列 Tab。
- 严禁用户看见“迁移应用”、来源应用中心、来源 APK 列表、旧应用启动器、平行的 Dia/游龙/GKD 入口或设置下的迁移目录。
- 严禁通过隐藏入口、改名入口或把旧目录放进设置子菜单来规避要求。
- Dia、游龙广告插件、游龙安全护盾、GKD-XA 只用于研发期源码证据、功能映射、许可证和差异审计。其真实功能必须被拆解并归入 Ad/VPN/隐私/脚本/Hook/设置，不保留旧应用身份。
- Settings 不是业务杂物页。Root/LSPosed 操作、DNS、Firewall、证书管理、脚本任务、Hook 工具等必须归对应业务 Tab。
- 旧数据库或旧配置迁移器属于 Data 层的内部能力，不能形成用户可见的 Migration 产品模块或 Tab。
- 所有子 Activity 必须显示正确的 FX 业务名称、业务 Tab 高亮、合理返回路径和导航状态。不能让旧来源 Activity 直接创建第二套主入口。

## 3. 五种全局界面模式与壁纸

五种模式属于同一个 APK 的 Presentation Skin；共享同一业务状态、ViewModel/Repository、数据库、权限和服务生命周期。换肤不得重启或重建 VPN、Root 内核级代理、DNS、Hosts、Hook、Frida、Accessibility 或脚本运行时。

1. ClassicWebCompat（storage ID classic）：旧版网页界面。依据游龙工具 10.0.2 APK 实际页面和资源恢复经典交互。WebView 仅使用可信本地 AssetLoader，不加载远程页面。VPN、Ad、隐私、脚本页面如保留旧 WebUI 桥接，必须有明确调用边界和实际页面资源；Hook 与设置仍在同一 APK 原生宿主内。
2. FXLiquidNative（storage ID glass）：原生 Android 液态玻璃。使用 Compose 自有组件、半透明层、背景模糊/景深、高光、描边和柔和动画。低性能设备自动降级，不可因模糊耗电、卡顿或崩溃。
3. MiuixStyle（storage ID miuix）：小米澎湃 / Miuix 视觉风格。核对依赖和许可证；非小米 Android 设备同样可运行，不依赖 MIUI/HyperOS 私有服务。
4. HUAWEI HarmonyStyle（storage ID huawei）：Android APK 内的 HarmonyOS 视觉 Skin，不是 HarmonyOS 原生应用。使用 HarmonyColor/Shape/Typography/Spacing tokens 与独立组件 renderer；覆盖 TopBar、BottomBar、Card、ListItem、Dialog、Sheet、Switch、Search、空/加载/错误状态。使用 Android 公共 API；HMS 仅作可选能力探测。
5. iOS CupertinoStyle（storage ID ios）：Android APK 内的 Cupertino 风格 Skin，不是 iOS 客户端。使用 Cupertino tokens 和独立 Compose renderer；覆盖 NavigationBar、TabBar、InsetGroupedList、FormRow、Toggle、Alert、ActionSheet、BottomSheet。不得调用 Apple 私有 API 或分发未授权的 SF Symbols、字体和系统资源。

### 五 Skin 开发规范

- 模式 ID 集中由 FxUiMode 读写；保留既有 ID 和别名兼容，未知 ID 安全回退。
- 统一 Skin Host 决定 renderer，禁止页面 Activity 私自读取多个主题偏好或维护不同 ID。
- 每种 Skin 逐页覆盖六 Tab：主页面、表单、列表、编辑器、弹窗、Sheet、空态、加载态、错误态、权限态、键盘和返回栈；不能只给主壳换色。
- 共用业务控件语义和操作，仅更换视觉 tokens 与 renderer。
- 验收包括模式切换、服务不重启、状态/草稿/滚动位置保留、深浅色、字体缩放、TalkBack、窗口尺寸、横竖屏、状态栏和系统手势。

### 游龙工具 10.0.2 壁纸对照

资料库已记录参考 APK 原件：92,008,250 bytes，SHA-256 为 c2d7bb1b8e688232888a927d5b81affcf5c28832f9e6420e27e800e54f5fee75。DEX/资源已确认原版壁纸弹窗标题“壁纸随心换”，动作“上传本地图片”“恢复默认壁纸”，私有目录保存、长边 1920 px、JPEG quality 85，SharedPreferences 为 native_wallpaper_prefs / wallpaper_path。index.java、bizhi.png 曾被识别为非明文数据，不得伪装成可直接复制的 HTML/PNG。完整 JADX/资源解密/原版逐页截图仍要继续验证，不能声称 ClassicWebCompat 已逐像素复刻。

壁纸入口在设置的外观与个性化中，只改变 UI 背景。支持本地图片选择、预览、恢复默认、失效回退、重启升级恢复、私有存储和清除；进一步的裁剪、缩放定位、模糊、暗色遮罩、透明度等若为 FX 扩展必须明确标注，不得误称为 10.0.2 原版已有能力。敏感页面优先保证文字对比度。

## 4. 完整功能大纲：必须按业务域吸收来源功能

### 4.1 Ad 广告拦截

设计和实现多层协作、可单独诊断的过滤链：

1. 本地 DNS 层：本机解析、缓存、上游 DNS、DoH/DoT/DoQ 等受支持协议、分流 DNS、失败回退、日志与泄漏测试。
2. Hosts 重定向层：编辑真实 Android 系统 hosts 文件，支持原子写入、权限/挂载检查、差异预览、分页编辑、外部编辑同步、回滚。系统 hosts、本地 FX hosts 和远端订阅规则是三个不同数据域，禁止混写。
3. 应用层 Hook：按真实 Hook 通道、目标包、进程和授权状态执行。配置落盘不等于已经注入或生效。
4. Accessibility 服务层：只在用户明确开启和授权后执行可访问性自动化；显示真实服务连接、事件和动作状态，限制重复操作与后台消耗。
5. TUN/代理层：与 VPN 共享单一 ingress 或由统一流量编排层处理；不能启动互相争抢 VPN 槽的两个 VpnService。
6. 完整吸收游龙广告插件实际能力：广告总开关、General、Summary、Stats、Whitelist、DNS、Firewall、规则订阅、域名名单、自定义规则、计划任务、Root Proxy、Tile、Widget、Tasker 等。按原始 APK/源码逐项列出版本差异；有入口但无真实执行的项目标为部分/未实现，不得用空壳替代。

### 4.2 VPN / 代理

- 实现节点和订阅管理、协议配置、连通性测试、延迟、自动更新、分组、筛选、排序、收藏、导入导出、规则路由、直连/全局/规则模式、应用分流、DNS 分流、日志、连接控制、自动重连、断线保护和配置回滚。
- 目标协议能力按每个具体内核登记：Hysteria 2、TUIC、VLESS/VMess、Trojan、Shadowsocks、SOCKS、HTTP(S) 等。协议不是内核名称。
- 至少有一个实际内置并测试通过的默认内核；可设计 sing-box、Mihomo、Xray-core、V2Fly/v2ray-core、dae、Leaf、Brook 等适配。支持用户上传自定义内核，但必须校验 SHA-256/签名/来源/许可证/ABI、可执行权限、能力探测、配置验证、沙箱/隔离、切换、升级和回滚。未知内核不得自动获得 Root。
- FX 的目标主路径是 Root/系统网络栈级代理数据面，按设备能力选择 policy routing、iptables/nftables、TPROXY/REDIRECT、受控 tun2socks 或等效后端，不占用 Android VPN 槽。禁止把 FX 自己启动 VpnService 说成内核级代理。
- 第三方 VPN 共存：不能停止第三方 VPN、抢占 VPN 槽、flush 全局防火墙、覆盖其路由或把其流量误导入回环。探测 VPN interface、路由表、UID policy、DNS 与活动 socket；防止循环转发、重复加密、DNS 泄漏、路由黑洞。按可观察/可配置/封闭/不兼容的具体第三方 VPN 分类测试，不能承诺无条件兼容。仅在无第三方 VPN 占槽且用户选择备用模式时，才考虑 VpnService fallback。
- 防泄漏：覆盖 IPv4、IPv6、DNS、WebRTC、应用直连、切网、休眠唤醒、进程崩溃、节点故障、核心切换和停止时的失败关闭/回退策略。将 https://who.1ms.dog/zh-cn/ 纳入人工验收，并记录检测截图、DNS/路由和实际结果。
- Always-on 与后台：优化 Android 前台服务、Doze、网络切换、守护和唤醒，做待机电量/CPU/唤醒锁/流量测试。不得承诺与 iOS 生命周期完全相同或零耗电。
- MITM/HTTPS：包括 CA 生成、私钥安全存储、导出、安装、系统/用户信任检查、轮换、撤销、卸载、回滚和过期处理。显式授权、清楚显示启用范围。不能承诺所有 Android 应用、浏览器、系统组件或证书锁定应用信任用户 CA；QUIC/HTTP3、自定义 TrustStore、pinning 必须分类说明。
- MITM 脚本：把请求/响应 hook 接入实际 TLS/HTTP pipeline，支持 header/body 处理、重定向和错误处理；不是只保存 Script 文字或显示开关。

### 4.3 隐私

- 吸收现有 FX 隐私页和游龙安全护盾实际功能：隐私总览、权限/传感器、应用风险、扫描、风险详情、白名单/黑名单、病毒库、每日总结、实时防护、屏幕滤镜、批量清理、完整性检查、救援与恢复、后台守护等。
- Root、模块、LSPosed/LSP 隐藏或兼容按应用、进程、Android 版本、ROM、检测类别进行配置，回读目标进程中的真实状态；所有开关必须说明作用域和风险。不能保证绝对隐藏，不允许破坏系统安全、支付和设备完整性。
- 安全扫描必须显示扫描覆盖率、数据库版本、失败/跳过的项目；数据不足不能显示“安全/无风险完成”。
- 权限操作必须符合 Android 公共 API 和用户授权，不得静默绕过系统权限。

### 4.4 Hook

- 统一 FX Hook 原生 UI，单 APK、一个入口、统一生命周期。首页显示已安装应用、搜索/图标、逐应用配置、运行状态、授权通道、日志；点击应用进入专属 Hook 页面和自定义规则。
- 吸收 Dia 的真实功能：Frida 环境/注入/监听、目标应用选择、DEX 查找与方法选择、Activity 入口、文件/so、JSON、Inspector、监控事件、会话日志、崩溃报告、签名信息、系统扩展、方法 Hook、对话框/Toast/通知/剪贴板/传感器/网络等规则工具。每项需要检查实际 server/injector/gadget 和进程生命周期。
- 吸收 GKD-XA：先解决 Android Gradle/JDK/Kotlin、Manifest、Room、AIDL、selector、Accessibility runtime、数据库与权限兼容 spike；再分模块迁入 selector、订阅、规则执行、快照和页面。GKD-XA v1.4.8 当前是 GPL-3.0，上游源码锁定不等于已经移植；保留版权、许可证和源代码义务。
- 广告/开屏 Hook 只针对可验证、合法使用场景，提供按应用作用域和撤销。
- 应用更新 Hook、VPN 检测、隐私检测应基于真实 PackageManager/系统事件或合法注入能力，不能伪造状态。
- VIP/会员相关只提供用户自有应用测试、开发者测试 entitlement 或合法已授权能力；不得伪造付费资格、绕过订阅验证或移除第三方授权收费。
- 自定义位置只针对用户明确授权的 Android 测试/隐私模拟，标明模拟状态与权限；不得宣称坐标等于真实 GPS，也不能保证第三方服务接受模拟定位。

### 4.5 Script 与规则

- 代理/网络脚本目标生态：Surge、Quantumult X、Loon、Shadowrocket、Stash、Egern、Surfboard、Clash/Mihomo、sing-box。
- 浏览器脚本与扩展目标：Tampermonkey、Violentmonkey、Greasemonkey UserScript，以及目标浏览器实际开放的扩展 API。
- 过滤和规则格式：AdGuard、uBlock Origin、Adblock Plus、Hosts、PAC、DNS blocklist、CIDR/IP/domain、URL Rewrite、订阅列表。
- 建立 parser、validator、serializer、QuickJS/其他 runtime、平台 API adapter、权限模型、沙箱、超时、取消、日志、导入导出、版本兼容矩阵。区分完整兼容、部分 API、仅语法解析、只读显示、不支持。
- 只有脚本真正执行并在真实网络请求/浏览器页面/Hook 事件中生效，才可标记“已实现”。脚本被导入、语法高亮或保存成功不能当成实际执行。

## 5. 统一技术架构原则

- Presentation：五 Skin、统一导航、可访问 UI、壁纸层。
- Domain：Ad、VPN、Privacy、Hook、Script、Settings。来源 APK Source Intake 是开发期工作流，不是产品模块。
- Data：统一 Repository、Room/配置适配器、版本化 schema、规则/节点/脚本/Hosts/壁纸仓库和迁移备份回滚。
- Platform：Root broker、系统网络栈代理后端、可选备用 VpnService、DNS、Hosts writer、Accessibility、LSPosed bridge、PackageManager、证书管理、Tile/Widget/Tasker。
- Runtime：网络内核 provider、QuickJS 与脚本 adapters、规则引擎、受控 Frida/GKD 生命周期。
- Observability：结构化真实状态、脱敏日志、诊断导出、失败状态和版本记录。
- 各服务生命周期与 UI Skin 解耦；切换页面/皮肤不能错误停止或启动服务。
- Root 命令固定白名单、参数校验、路径规范化、拒绝符号链接、最小权限、超时、锁与审计；禁止全局防火墙 flush。
- 任何入口必须有真实后端、权限/授权解释、持久化、错误状态、取消/回滚和测试。未接入显示“尚未接入/不可用”，不得伪造成功。

## 6. UI 布局重构交付要求

先完成可验收的统一信息架构和各 Tab 页面布局，再按页面组连接业务逻辑。至少覆盖：
- 应用主壳、状态栏/顶部栏、固定六 Tab、底部导航和全局背景层。
- 各 Tab 总览、分类列表、详情页、表单、编辑器、日志、导入导出、弹窗、Sheet、空态、加载态、错误态、权限态。
- 导航返回、外部 Intent、Activity 重建、横竖屏、键盘、滚动位置、草稿、深浅色和多尺寸屏幕。
- 五种 Skin 都必须逐页适配所有一级 Tab 和关键二级页面。
- 保留已有功能链，移除来源应用主入口时必须把真实功能放在对应 Tab 内；不准简单删除旧菜单导致功能丢失。
- ClassicWebCompat 用真实 10.0.2 资源证据；Miuix/液态玻璃/华为/iOS 视觉样式均需许可与兼容边界。
- 禁止只提交截图或 Figma 概念图代替可运行源码。

## 7. 开发顺序与阶段门禁

P0 — 恢复状态和安全风险：最新 HEAD、状态文件、构建图、系统服务/Root/网络数据面风险。
P1 — 统一主壳与六 Tab：移除来源应用入口与过时命名；完成路由/返回/状态恢复。
P2 — 五 Skin 与壁纸：统一 token/renderer、六 Tab 逐页覆盖、10.0.2 对照壁纸行为。
P3 — Ad 页面组：本地 DNS、Hosts、过滤订阅、白名单、Firewall、统计、Tasker/Tile/Widget 与五层过滤状态。
P4 — VPN 页面组：节点/订阅/内核选择、Root 数据面、第三方 VPN 共存、DNS/路由、防泄漏、MITM/证书与脚本接入。
P5 — 隐私页面组：安全护盾、扫描、风险/名单、Root/模块/LSPosed 状态与可撤销控制。
P6 — Hook 页面组：FX Hook 原生应用列表、Dia 能力、GKD-XA 兼容 spike 和 runtime、规则/生命周期。
P7 — Script 页面组：代理脚本生态、QuickJS、MITM scripts、浏览器 UserScripts/扩展和规则解析/执行。
P8 — 综合验收：升级/卸载/回滚、权限撤销、进程恢复、网络切换、耗电、防泄漏、多 Skin、无障碍、真机。
每轮选择 1–3 个紧密相关页面/功能组完成；紧急 P0 安全/断网/数据损坏风险可插队。能独立实施的工作线并行处理，但不得同时覆盖同一文件。

## 8. 测试、状态和“完成”定义

验证等级必须分清：
1. 源码静态检查/脚本回归；
2. 主机单元测试；
3. Android 单元测试；
4. Gradle 编译与打包；
5. UI 自动化/截图；
6. 模拟器测试；
7. 真机安装/升级/卸载；
8. 真机网络泄漏、第三方 VPN 共存、耗电、权限和 Hook 实际运行。

不得以较低等级冒充较高等级。Actions 没运行就写没运行；Gradle 未编译就不能声称 APK 构建通过；无真机就写真机未验证。

功能状态只能使用：未检查、缺失、部分实现、已实现未验证、已验证、有意不迁移（原因）。只有界面、真实业务逻辑、权限/生命周期、数据持久化、错误/回滚和匹配风险的验证证据齐全才允许标记已验证。

每批完成后同步更新 docs/FX_1.0.0_LIVE_CONTINUATION_STATE.md，必须记录：
- Asia/Tokyo 日期/时间；
- 当前分支与最新 HEAD；
- 本批实际改动文件、commit SHA；
- 哪些行为真实可用，哪些只是入口/配置/解析；
- 静态、单测、Gradle、UI、设备的具体结果；
- 没有完成的项目、阻塞和下一批可直接开工文件；
- 禁止复写已完成批次和重复失败路线。

在五套 Skin、六 Tab、所有功能域和风险相关验收完成前，禁止生成或交付最终 APK/KernelSU ZIP；不得把临时包称为最终版。

## 9. 交接完成后的立即行动

读完所有必要资料后，不要回复长篇计划。直接从实时状态文件中下一项未完成任务开始，修改源码并提交。每个批次给用户一个简短事实报告：改了什么、提交 SHA、验证等级、还缺什么，然后继续推进。
