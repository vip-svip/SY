# FX 1.0.0 / FX Hook — 跨 AI 自主接管与全面重构总提示词（唯一正式版）

> 本文件是唯一可直接交给其他 AI 的总接管提示词，也是 FX 1.0.0 UI 与功能全面重构的执行基线。产品规格见 docs/FX_1.0.0_PRODUCT_RESTRUCTURE_AND_AI_HANDOFF.md，真实进度见 docs/FX_1.0.0_LIVE_CONTINUATION_STATE.md。  
> 仓库：vip-svip/SY  
> 分支：fx-v1.0.0-unified-hook-integration  
> 版本固定：FX 1.0.0；必须先核对 versionName=1.0.0、versionCode=10000，不得擅自升版。  
> 当前真实进度、HEAD、最近提交和验证证据始终以 docs/FX_1.0.0_LIVE_CONTINUATION_STATE.md 与源码为准；本文件描述目标，不代表目标已经全部实现。

---

## 0. 你的身份与交付目标

你现在接管 FX 1.0.0 / FX Hook 项目，作为主开发 AI。你必须实际读取代码、修改代码、运行与修改匹配的测试、提交 GitHub，并持续更新实时状态。不要只给架构建议、计划、清单或伪代码。

最终产品必须是：

- 一个 Android APK、一个 Launcher、一个 FX Hook 原生主界面、一个统一业务状态与配置体系。
- 五种全局界面皮肤只改变 Presentation，不复制业务功能，不启停网络、Hook、DNS、证书或脚本服务。
- 六个固定主 Tab，所有来源能力按功能归属整合，不存在“迁移应用”入口或旧应用启动器。
- 所有可见按钮都连接真实业务状态与操作；未接入能力明确标注未接入，不得用假开关、假统计、假运行状态伪装完成。
- 最终版本号固定 FX 1.0.0。完成所有功能和验收前不打最终 APK/KernelSU ZIP。

禁止把“源 APK 已解压”“Activity 已存在”“按钮可点击”“配置能写入”“日志有输出”“规则文件存在”算作功能已完成。

## 1. 开始接管时必须读取的事实

开始后先做一次快速恢复，不要反复盘点全仓库：

1. 读取 GitHub 实时分支 HEAD、最近提交、docs/FX_1.0.0_LIVE_CONTINUATION_STATE.md。
2. 读取 docs/FX_1.0.0_PRODUCT_RESTRUCTURE_AND_AI_HANDOFF.md 与 docs/FX_1.0.0_LIVE_CONTINUATION_STATE.md；本文件就是唯一正式跨 AI 接管提示词，不要依赖不存在或已合并废止的重复 Master Prompt；再读取 docs 下本批相关功能的专项方案。
3. 读取资料库 /FX 中的长期交接档、快速推进档、UI 优先执行档、UI 提速提示词和当前可用的 APK/源码 ZIP。缺少文件时如实记录，不得说已经读取。
4. 对照真实代码、Manifest、资源、测试和功能调用链，只阅读当前批次所需文件。
5. 核实游龙工具 10.0.2 原件和相关源代码版本。记录文件哈希、包名、版本、来源和许可证。
6. 先列出当前最高优先级的 1–3 个页面/功能组，然后直接实施，不等待用户逐项安排。

任何文件修改前都要重新读取分支最新 HEAD 和目标文件当前 SHA。若 HEAD 前进，基于最新文件重放修改，不能用旧内容覆盖。每次写完必须回读验证。共享文件按顺序写入；不生成编号备份，不创建无意义分支，不强制推送。

## 2. 产品信息架构：固定六个 Tab

主导航顺序和索引固定：

固定六 Tab：VPN、Ad、隐私、脚本、Hook、设置。第二 Tab 的唯一名称是 Ad，Hosts 只是 Ad 内部页面。

| 索引 | 唯一显示名称 | 页面职责 |
|---|---|---|
| 0 | VPN | 代理内核、节点、订阅、路由、DNS 路由、MITM、证书、防泄漏、连接诊断 |
| 1 | Ad | 广告过滤总控、DNS 过滤、Hosts、规则订阅、白名单、防火墙、统计、计划任务 |
| 2 | 隐私 | 隐私控制、权限风险、Root/模块/LSPosed 兼容、安全护盾与扫描 |
| 3 | 脚本 | 代理脚本、MITM 脚本、规则脚本、浏览器 UserScript、扩展、运行任务 |
| 4 | Hook | 已安装应用列表、逐应用 Hook、Dia 工具、GKD 功能、自定义 Hook、授权状态 |
| 5 | 设置 | 全局界面模式、壁纸、主题、动效、权限中心、统一备份恢复、诊断偏好、许可证、关于 |

绝对约束：

- 第二 Tab 只能叫 Ad。底部导航、顶部标题、页面标题、面包屑、路由配置不得显示“Ad/Hosts”或“Ad / Hosts”。
- Hosts 是 Ad 内部功能页，不是第二个产品模块，不得与 Ad 并列为主 Tab。
- 设置永远是第六 Tab。不得放入“迁移应用”、Dia 启动器、游龙插件启动器、安全护盾启动器或任何旧来源应用列表。
- Dia、游龙广告插件、游龙安全护盾、GKD-XA 等只是开发期源码/功能来源。最终产品应把功能拆分到 Ad、VPN、隐私、脚本、Hook；不得为了保留旧 Activity 树而保留旧来源应用入口。
- “迁移”只允许作为内部数据 schema 升级、旧配置导入/兼容的工程术语，不是用户可见业务域或导航项。
- 旧页面可作为内部实现逐步迁移，但必须从 FX 的正确业务 Tab 直接可达；页面标题、返回路径和导航高亮必须显示 FX 业务归属。

## 3. 主界面布局与页面层级重构

### 3.1 全局页面框架

所有五种 Skin 共用一致的信息架构：

- 顶部区域：FX 品牌/当前页面标题、必要的实时连接或服务状态。错误状态不能盖住导航与主操作。
- 页面主体：可滚动、分组卡片式业务内容。重要主开关、状态、主要动作放在第一屏；复杂配置进入二级页面或 Sheet。
- 底部区域：六 Tab 固定常驻，高度足够，适配手势区域和软键盘。页面滚动不得把底栏挤走。
- 二级/三级业务页面：返回路径明确；从任意子页点六 Tab 必须直接切回相应主业务，不遗留旧来源应用栈。
- Loading、Empty、Error、Permission Missing、Unsupported、Partially Integrated 状态必须各自明确，不能显示虚假的成功绿点。
- 支持屏幕旋转、Activity 重建、进程回收、前后台切换后恢复 Tab、页面层级、搜索、滚动位置、编辑草稿和待完成的系统授权流程。
- 大屏/折叠屏使用 WindowSizeClass/WindowInsets 或等效 Android 公共 API；字号缩放、深浅色、TalkBack、触控区域必须合格。
- 不为每种 Skin 复制 Activity 或业务页面。优先统一 ViewModel/Repository 与页面组件，再由 Skin Renderer 提供视觉差异。

### 3.2 VPN 页面

首页按从上到下排列：

1. 代理总状态与总开关：显示当前内核、数据面模式、启动失败原因和实际运行状态。
2. 模式选择：直连 / 全局 / 规则；每个模式必须真实改变路由。
3. 当前节点与订阅：节点信息、延迟、可用性、订阅刷新时间、导入/编辑/分组。
4. 代理策略：应用分流、域名/IP/CIDR 规则、路由策略、DNS 路由。
5. 防泄漏中心：DNS、IPv4、IPv6、WebRTC、断线与重连检测。
6. MITM 与证书：CA 状态、系统安装/信任状态、证书轮换与撤销、脚本 Hook。
7. 运行日志与诊断：内核、接口、路由、错误和耗电观测。

节点/订阅、直连/全局/规则、分应用路由、协议、规则、DNS、连接控制、导入导出、日志、自动重连等必须按真实能力实现，不得只展示 UI。

### 3.3 Ad 页面

Ad 是独立的广告过滤主页面，不显示“Ad/Hosts”。

首页按以下功能分组：

1. 广告过滤总开关及总体状态。
2. 多层过滤状态：本地 DNS、Hosts 重定向、应用层 Hook、Accessibility 辅助、TUN/代理过滤层。显示每层真实状态、当前运行通道和失效原因。
3. 本地 DNS：本地解析服务、上游/缓存、DNS 日志、规则、异常和重启策略。
4. Hosts：真实本地 Hosts 文件、编辑器、分页、外部修改回读、系统实际生效视图、原子写入/回滚。
5. 订阅规则：订阅源、规则解析、启停、刷新、更新日志、规则冲突检查。
6. 白名单/黑名单：域名名单、应用名单、自定义规则。
7. 应用网络防火墙：按应用网络权限和规则策略设置；与 VPN 应用路由区分。
8. 统计与总结：真实 DNS 命中、拦截计数、应用流量、每日摘要。
9. 计划任务、Quick Settings Tile、Widget、Tasker/Automation 等原来源能力。

本地 Hosts 文件必须与订阅规则分开保存。不得把订阅缓存写进本地 Hosts 编辑器，不得把只读系统文件伪装为可编辑文件。Hosts 编辑器应支持分页、外部修改检测、原子写入、校验和回滚。

游龙广告插件来源功能必须逐项比对 7.0.1、9.9.60、10.10.62 等可取得版本；差异项单独记录。已实现功能可以复用，但必须确认真实数据、权限、服务、生命周期和 UI 入口都归入 Ad。

### 3.4 隐私页面

包括：

- 隐私总览与实际风险状态。
- 已安装应用隐私详情、权限、传感器、剪贴板、通知监听/权限提示、Toast 文本过滤及网络隐私策略；这些按应用隐私策略归入隐私页。
- Root 状态、模块状态、LSPosed 状态、Accessibility 状态，必须分别读取系统/框架真实结果。
- 游龙安全护盾全部可合法复用的安全页面与功能：扫描、风险详情、病毒库、屏幕过滤、每日摘要、完整性、救援、批量清理、白名单/黑名单等。
- Root/模块/LSPosed 兼容或隐藏功能按应用配置、提供回读和撤销；不得承诺绝对隐身，不得规避支付、金融、反作弊、设备完整性或其他安全访问控制。
- 安全扫描不完整、病毒库过期、权限不足、数据源不可用时必须显示不完整/未知，不得显示“安全”或“扫描完成”。

### 3.5 Hook 页面

Hook 是第五个主 Tab。首页：

- 已安装应用列表、应用图标、搜索、筛选、最近使用、配置状态。
- Hook Hub 提供 Frida 环境/注入、DEX 浏览与方法签名选择、Activity 入口/禁用、文件与 so 浏览、JSON 操作、内存快照、数据库监控、结构化监控事件、崩溃报告、签名信息、系统扩展、工具运行设置等开发工具入口。
- 提供“Dialog 对话框 Hook”和“按键动作 Hook”两个逐应用工具入口：从 Hook Hub 选择目标应用后进入对应配置页；目标页、应用列表与返回链始终归属并高亮 Hook。
- 点入其他应用后进入独立目标应用详情，不进入第二个 APK 或旧来源入口。
- 目标应用配置包含 Hook 开关、Root/LSPosed/Accessibility 通道、广告 Hook、自定义 Hook、规则组、运行日志、异常、启停状态。
- 通知监听/权限提示、Toast 文本过滤、剪贴板和传感器隐私策略属于隐私业务，入口归隐私页；不得因为它们曾出现在 Dia 来源工具树中就复制到 Hook。
- 整合 GKD-XA 的选择器、规则、订阅、自动化、快照、规则编辑和授权服务；先处理 Gradle/JDK/Manifest/Room/AIDL/Accessibility 兼容，再迁移 selector 和 runtime，禁止直接复制第二个 Application/MainActivity。
- GKD-XA 固定来源需每次回读当前 submodule，历史锁定只作为审计基线。2026-11-05 审计基线：84593320z/GKD-XA，tag v1.4.8，commit 8a6ce935da11671dac7e1a7595416ec99ee07436，GPL-3.0。审计记录 FX 构建基线为 AGP 9.1.1 / Kotlin 2.4.21 / JVM 17，上游基线为 AGP 9.4.1 / Kotlin 2.4.20 / JVM 21；必须先做工具链、Manifest、Application、Room、AIDL、隐藏 API 和 Accessibility 生命周期兼容 spike。不得直接复制第二个 Application/MainActivity，也不得把 submodule 指针或 Click-only 试点说成 GKD 全功能迁移。
- 应用更新检测、VPN 检测和隐私检测可以提供可配置的兼容性/测试能力；执行必须按用户授权与设备策略。
- 开屏广告 Hook 与广告 Hook 仅在用户授权设备及合规目标范围内执行。
- 自定义位置仅用于用户拥有/获准测试的应用和设备测试；使用 Android 允许的 mock location 机制，并明确它不保证与真实 GNSS、基站、Wi-Fi、IP、传感器和账号环境完全一致。
- VIP 相关只整合合法会员功能、授权状态显示和用户自有应用测试能力；不伪造付费资格、不绕过订阅、支付和服务端授权。

Root、LSPosed、Accessibility 不能被混成一个开关。分别显示是否获得 Root、LSPosed Binder/作用域是否连接、Accessibility 服务是否启用、目标进程是否真实注入。配置成功不等于注入成功。

### 3.6 脚本页面

脚本是独立主 Tab，覆盖：

- 脚本库、导入/导出、编辑器、版本管理、启停、运行任务、日志、调试、定时任务。
- 代理脚本生态：Surge、Quantumult X、Loon、Shadowrocket、Stash、Egern、Surfboard、Clash/Mihomo、sing-box。
- 浏览器生态：Tampermonkey、Violentmonkey、Greasemonkey UserScript，以及浏览器实际支持的扩展机制。
- MITM request/response 脚本，必须通过当前代理内核提供的真实 TLS hook 接口执行。
- 规则格式：AdGuard、uBlock Origin、Adblock Plus、Hosts、PAC、DNS blocklist、URL Rewrite、domain/IP/CIDR 等。
- 运行时：ARM64 QuickJS/QuickJS-NG 或经验证替代方案；平台 API Adapter、Parser、Validator、Serializer 分层。
- 兼容矩阵按“配置可解析 / 规则可执行 / API 部分兼容 / API 完全兼容 / 不支持”分类；不能把能解析配置说成脚本 API 完全兼容。
- 脚本沙箱包含权限白名单、文件/网络访问限制、超时、取消、内存限制、错误隔离、日志脱敏、导入来源和签名校验。
- 浏览器扩展只有在对应浏览器提供扩展 API 时才启用；不宣称对所有 Android 浏览器全局生效。

### 3.7 设置页面

Settings 只包含：

- 五种全局界面模式、主题、动效、背景、壁纸。
- 全局权限入口/权限状态总览。
- FX 统一配置备份/恢复。
- 通知、诊断、隐私偏好。
- 开源许可证、第三方声明、关于 FX。

设置不包含 VPN 业务操作、广告规则操作、Hosts 操作、安全扫描业务、Hook 应用管理、脚本运行器或迁移应用入口。相应功能必须放回对应 Tab。

## 4. 五种全局界面模式

五种 Skin 是同一 APK 中的全局 Presentation：

| 模式 | 稳定 storage ID | 视觉与实现重点 |
|---|---|---|
| ClassicWebCompat | classic | 游龙工具 10.0.2 经典网页 UI 风格，真实资源/交互证据与兼容桥接 |
| FXLiquidNative | glass | Android 原生液态玻璃、半透明、Backdrop 模糊、折射/高光、低性能降级 |
| MiuixStyle | miuix | 小米澎湃/Miuix 风格、分组设置、圆角卡片、合法开源组件 |
| HUAWEI HarmonyStyle | huawei | 鸿蒙视觉风格、卡片层级、留白与统一组件，在普通 Android 设备可运行 |
| iOS CupertinoStyle | ios | iOS/Cupertino 风格导航、InsetGroupedList、FormRow、Toggle、Sheet 等 |

### 4.1 ClassicWebCompat

- 必须基于用户提供的游龙工具 10.0.2 APK 原始 UI、页面和资源核验。
- 通过 APK Analyzer、Manifest、resources.arsc、assets、DEX、Smali/JADX 与截图映射页面，区分真实网页 UI 与 Miuix 原生 UI。
- 原 APK 的加密资源不能直接当普通 HTML/PNG 复制。只有合法可复用、已解密验证的静态资源才能复用。
- WebView 旧桥接只用于真实必要的兼容点；迁移后的新页面应使用 FX 原生 UI。
- Classic WebView 必须使用 AndroidX WebKit WebViewAssetLoader 与受信任的本地 `appassets.androidplatform.net` 域名；不允许加载任意远程网页、混用 file:// 或开放不必要的 JavaScript bridge。对外部链接必须离开兼容 WebView 并经用户操作确认。
- 未完成原版完整资源解密和逐页截图比对前，不能称为逐像素复制 10.0.2。

### 4.2 FXLiquidNative

- 使用 Kotlin/Jetpack Compose 和 FX Glass Design Tokens。
- 半透明材质、背景模糊、细描边、高光、柔和阴影、景深层次、短时可中断动画。
- 文字对比度、键盘、导航手势、TalkBack 必须达标。
- GPU/系统不支持模糊时降级为半透明纯色，不得造成卡顿、崩溃或明显耗电。

### 4.3 MiuixStyle

- 使用现有合法授权 Miuix 组件和规范；非小米 Android 设备必须能启动和使用。
- 大圆角、紧凑信息布局、分组列表、系统设置风格、轻量转场。
- 不依赖 MIUI/HyperOS 私有 API，不复制未经许可的系统私有资产。

### 4.4 HUAWEI HarmonyStyle

- 这是 Android APK 内的鸿蒙视觉 Skin，不是 HarmonyOS 原生应用。
- 建立 HarmonyColorTokens、HarmonyShapeTokens、HarmonyTypographyTokens、HarmonySpacingTokens 和 Harmony Renderer/组件适配层。
- 覆盖 TopBar、BottomBar、Card、ListItem、Dialog、Sheet、Switch、Search、表单、空态、加载态、错误态。
- 采用清晰服务卡片层级、合适留白、统一图标网格与字号、轻量动效。
- 仅使用 Android 公共 API。HMS 能力只能作为可选 Adapter 探测；缺失时正常回退。不得复制未授权华为资源。
- 华为和非华为 Android 设备都要验收。

### 4.5 iOS CupertinoStyle

- 这是 Android APK 内的 Cupertino 视觉 Skin，不是 iOS 原生客户端。
- 建立 CupertinoColorTokens、CupertinoShapeTokens、CupertinoTypographyTokens、CupertinoSpacingTokens 和独立 Renderer。
- 用 FX 自有 Compose 组件实现 NavigationBar、TabBar、InsetGroupedList、FormRow、Toggle、Alert、ActionSheet、BottomSheet。
- 交互参考公开 Apple Human Interface Guidelines；不能调用 Apple 私有 API，不能使用未经授权的 SF Symbols、字体或资源。
- 不得声称具备 iOS 后台生命周期、系统权限或 Network Extension。

### 4.6 五 Skin 统一实现约束

- FxUiMode 是唯一模式枚举与读写入口，固定 storage ID：classic、glass、miuix、huawei、ios。
- 未知/旧 ID 必须安全回退；旧 ID 迁移需有单测。
- 六个 Tab、二级 Activity、Dialogs、Sheets、Forms、List、Editor、Empty/Error 状态逐页适配五 Skin。
- 不能只换主壳颜色或导航栏后声称整个应用已换肤。
- 模式切换不得重启/停止 VPN、Root 内核级代理、DNS、Hosts、Hook、Frida、GKD 或脚本运行时；不得丢失连接、配置、任务和编辑草稿。
- 测试 FxUiMode、Renderer 路由、稳定 ID、六 Tab 覆盖、截图/UI 自动化、字号/深浅色/无障碍。

## 5. 游龙工具 10.0.2 壁纸功能

必须对照 10.0.2 已核验的原版壁纸行为实现：

- 弹窗标题：壁纸随心换。
- 当前状态：当前已设置自定义壁纸 / 未设置自定义壁纸，当前为默认背景。
- 操作：上传本地图片、恢复默认壁纸、关闭。
- 原版 SharedPreferences：native_wallpaper_prefs，键 wallpaper_path。
- 原版保存：复制到应用私有 files 目录，最长边限制 1920 px，JPEG quality 85，文件名 native_wallpaper_<timestamp>.jpg。
- 原版资料库 APK：游龙工具_10.0.2.apk，92,008,250 bytes，SHA-256 c2d7bb1b8e688232888a927d5b81affcf5c28832f9e6420e27e800e54f5fee75。若本地原件与哈希不符，先重新核对。

FX 可扩展：
- Photo Picker/SAF 选图、预览、裁剪/缩放/定位、模糊、遮罩透明度、深浅色自适应、恢复默认和清除数据。
- 私有存储、持久恢复、文件损坏/丢失回退、失败写入不覆盖旧壁纸。
- 壁纸只作用于全局 UI 背景，不影响 VPN、Ad、DNS、Hosts、证书、隐私、Hook、脚本。
- 敏感页面自动提高遮罩与文字对比度；用户可关闭动态背景。
- 同一壁纸应由五种 Skin 的共享壳使用，不能在每个 Activity 私自保存不同路径。

## 6. 网络架构与 Android VPN 共存

这部分是 P0/P1 的核心安全约束：

- Ad 的过滤逻辑与 VPN 代理逻辑必须分离配置、开关、状态与 pipeline；可以共享底层网络入口，但不能互相冒充。
- Android 同一用户/配置文件只有一个活动 VpnService/VPN 槽。禁止 FX 和第三方应用 VPN 互抢、自动停止对方、强行替换用户设置。
- FX 代理主路径应是 Root/系统网络栈级数据面：仅在设备和内核能力允许时采用 policy routing、iptables/nftables、TPROXY/REDIRECT、受控 tun2socks 或等效路径。
- 监测第三方 VPN 接口、路由表、UID policy 和 DNS 状态，避免路由环路、双重加密、DNS 泄漏、回环和路由黑洞。
- 对第三方 VPN 采用能力分级：可链式协作、仅 Ad Root 过滤可用、冲突不可用、未知；封闭 VPN 不提供链式接口时必须如实显示限制，不能宣称百分之百兼容。
- 无 Root 环境才可考虑 FX 自己的备用 VpnService；检测到第三方 VPN 占槽时不得抢占。
- 不要 flush 全局防火墙、覆盖未知路由、删除第三方 VPN 规则或强制切换设备默认路由。
- Root 命令使用固定白名单、参数规范化、路径规范化、拒绝符号链接、最小权限、超时、审计与回滚。
- 启动失败要安全降级，优先保留系统网络和第三方 VPN 正常运行；不得造成全设备断网。

## 7. 广告过滤五层实现

必须分别建立可观测状态：

1. 本地 DNS 层：本地 DNS resolver/cache、规则更新、上游策略、DNSSEC/DoH/DoT 能力按真实支持登记。
2. Hosts 重定向层：真实 Android 系统 hosts 文件管理与重定向，必须读取/校验/原子写入/备份回滚。
3. 应用层 Hook：目标应用按用户配置执行，报告真实 LSPosed/Root 注入情况。
4. Accessibility 服务层：只在用户显式授权后处理可见 UI 自动化；限制后台事件、截图、重复动作与耗电。
5. TUN/代理过滤层：与 VPN 使用明确共享/兼容架构，不能再建立第二个相互冲突的 VpnService。

每层都要有总开关、子状态、错误状态、权限提示和独立日志。总开关只能表示实际可工作的层，不得由配置文件存在推断服务成功。

## 8. VPN、协议内核、防泄漏与 MITM

### 8.1 代理内核

- 必须内置至少一个经过真实构建和 Android ARM64 验证的默认内核。
- 候选适配：sing-box、Mihomo、Xray-core、V2Fly/v2ray-core、dae、Leaf、Brook，以及专用 tun2socks 组件。
- 允许导入用户自定义内核，但要校验来源、SHA-256/签名、许可证、ABI、架构、可执行权限、版本、能力探测、沙箱和回滚；未知内核默认隔离，不自动 Root 执行。
- Hysteria 2、TUIC、VLESS/VMess、Trojan、Shadowsocks、SOCKS、HTTP(S)、WireGuard 等是协议或传输能力，不是独立内核名称；按每个内核实际支持矩阵登记。
- 内核切换必须有配置兼容检查、进程替换、失败回滚和连接状态恢复，不得用 UI 选择器冒充可切换。

### 8.2 小火箭类代理功能

实现节点管理、订阅管理、协议、分组、直连/全局/规则模式、应用分流、域名/IP/CIDR 规则、DNS 策略、测速、日志、导入导出、自动重连和连接诊断。每项均需实际连接内核。

### 8.3 防泄漏验收

每次重要数据面修改至少测试：

- DNS 查询路径、上游和 IPv4/IPv6。
- IPv4/IPv6 断线/重连切换。
- WebRTC 暴露、DNS 泄漏、代理出口地址。
- VPN 关闭、内核崩溃、Root 丢失、网络切换、飞行模式、Wi-Fi/蜂窝切换。
- 第三方 VPN 共存、应用分流、规则命中、DNS 失败回退。
- 用户指定人工测试地址：https://who.1ms.dog/zh-cn/。
- 同时记录测试网络、设备 Android 版本、内核版本、时间与结果。单个网站通过不等于所有流量无泄漏。

### 8.4 Always-on 与耗电

优化前台/后台服务、唤醒锁、空闲轮询、DNS 缓存、规则更新、网络回调、进程生命周期和重连退避。测量 idle/屏幕关闭/流量活动/断网恢复能耗。Android 受系统后台限制和 OEM 电池策略影响，不承诺 iOS 相同 VPN 生命周期，不承诺零耗电。

### 8.5 MITM 与 HTTPS 证书

- 独立 CA 生命周期：生成、私钥存储保护、系统/用户证书安装、信任检测、轮换、撤销、卸载、备份和失败回滚。
- Root 系统证书路径按 Android 版本和系统分区/APEX 结构探测，不能盲目 remount 或覆盖未知证书。
- 必须区分系统 CA、用户 CA、应用私有信任库和证书锁定。不能承诺所有 App 都信任系统/用户 CA。
- MITM 默认关闭或仅对用户明确允许的 App/域名启用，必须显示敏感流量风险和可撤销配置。
- 只支持应用/服务实际开放的 TLS Hook；证书锁定不得通过不透明伪造状态绕过。
- MITM Script 必须能在真实 TLS 请求/响应处理回调中执行，超时、崩溃、脚本失败时安全放行/阻断按策略选择，不得破坏系统网络。

## 9. 脚本生态和兼容性

统一流程：Importer → Format Parser → Semantic Validator → Compatibility Adapter → Runtime → Permission Sandbox → Logs/Debugger。

- 不同平台有各自 API。必须逐项实现 $httpClient、$task.fetch、$done、$prefs 等必要 API Adapter，并明确同步/异步语义。
- 兼容 Surge、Quantumult X、Loon、Shadowrocket、Stash、Egern、Surfboard、Clash/Mihomo、sing-box；逐版本维护能力矩阵。
- 规则格式兼容 AdGuard、uBlock Origin、Adblock Plus、Hosts、PAC、DNS blocklist、URL Rewrite、CIDR/IP/domain。
- 浏览器 UserScript/扩展按具体浏览器支持情况接入 Tampermonkey/Violentmonkey/Greasemonkey 或 WebExtension 能力；不支持扩展 API 的浏览器不能谎称完整兼容。
- 脚本运行支持启停、定时、域名匹配、MITM 事件、运行日志、错误隔离、权限授权、沙箱、超时、取消、导入导出和版本回滚。
- 不能把正则替换、配置导入成功或一条静态测试通过称为完整平台脚本兼容。

## 10. 安全、隐私与合规边界

- Hook、Root、LSPosed、Accessibility 分别报告授权与执行状态。
- 位置模拟只用于自有设备/获准测试；不保证在所有应用里与真实地理/网络环境完全一致。
- Root/模块/LSPosed 兼容配置按应用管理，允许用户查看和撤销；不得绕过支付、金融、反作弊、设备完整性或服务端授权。
- 不伪造 VIP/会员 entitlement，不绕过付费墙、支付和订阅校验。
- 不未经允许抓取、修改他人应用数据或绕过应用安全边界。
- 扫描/防护只显示真实检测覆盖率与数据源状态。病毒库无数据或扫描不完整时不得报告安全。
- 证书、私钥、代理配置、脚本日志和用户数据尽量本地保存，敏感内容脱敏。
- 所有 Root/文件/网络操作都有参数验证、最小权限、超时、回滚与审计。

## 11. 来源功能映射与版权

按用户可取得的原始 APK/源码逐项核对，不允许仅按应用名字或页面截图猜功能：

- 游龙工具 10.0.2：旧界面模式、MiuixScreen 证据、壁纸行为和原始页面映射。
- 游龙广告插件：7.0.1、9.9.60、10.10.62 等可取得版本的功能差异；Ad、General、Summary、Stats、Whitelist、DNS、Firewall、订阅、Tile、Widget、Tasker、计划任务、Root Proxy 等。
- 游龙安全护盾：扫描、病毒库、屏幕过滤、每日摘要、风险详情、完整性、救援、名单、批量清理等。
- Dia 23.11：工具、Frida 生命周期、脚本库、DEX/Activity/文件/JSON/Inspector/监控/崩溃/签名等。
- GKD-XA：当前锁定源 commit 与 GPL-3.0 义务；先做 Gradle/JDK/Manifest/数据库/AIDL/Accessibility 兼容，再接入 selector/规则与 runtime。
- FX 现有隐私、Hook、脚本、模块功能也必须完整保留，不允许来源功能整合时把旧功能覆盖或删除。
- 每个来源功能必须映射到 FX 的真实页面、真实执行入口、数据仓库、权限、生命周期、回滚和测试。
- 保留第三方许可证、版权声明、NOTICE、修改记录与适用的开源分发义务。

## 12. 执行阶段与优先顺序

### P0：恢复事实、保护数据与网络

读取最新 HEAD/state，核对 APK 原件与源码 Intake；查断网、路由冲突、证书损坏、Root 命令、Hosts 写入、数据迁移风险。

### P1：统一 UI 与壁纸

固定六 Tab；清理旧迁移应用导航；完成五种 Skin 的模式状态、布局、页面 Renderer、壁纸原版契约和扩展控制；确保主 Tab、二级页面、返回、状态恢复一致。

### P2：来源功能页面融合

按完整页面组迁入 Ad、隐私、安全护盾、Hook、Dia、GKD、脚本。先完成页面与交互映射，再接真实数据与服务。每批只选 1–3 个紧密相关功能组。

### P3：广告过滤多层链路

完成 DNS、Hosts、应用 Hook、Accessibility、TUN/代理过滤层；保证独立开关、共享资源、兼容第三方 VPN 和安全回滚。

### P4：VPN、内核、证书与脚本运行时

完成默认内核、自定义内核、节点/规则/应用路由、防泄漏、MITM/CA 生命周期和真实脚本回调。

### P5：隐私、安全护盾、Hook/GKD

完成 Root/LSPosed/Accessibility 授权状态、应用级规则、GKD selector/runtime、Dia Frida 生命周期和安全防护功能。

### P6：整合验收

进行 Gradle 编译、单元测试、静态回归、UI 自动化、安装/升级、真机测试、VPN 共存/防泄漏/待机耗电/证书回滚/应用兼容。未有设备的项目标记“真机未验证”。

## 13. 交付纪律与每批完成记录

- 直接改源码并提交到指定分支；不要只更新需求文件。
- 同一文件的修改按批次集中；独立文件可并行处理，但共享状态、Manifest、Gradle、MainActivity 等必须顺序合并。
- 如果工具不支持真正的多 Agent，就如实单线程协调，不得谎称多 Agent。
- 每批只跑最小且匹配的测试；阶段节点再跑模块回归，避免无关全套 Actions。
- 同一错误路线失败两次，换方法并定位具体原因。
- 每个有效代码批次之后同步更新 docs/FX_1.0.0_LIVE_CONTINUATION_STATE.md，记录：日期、HEAD、commit、路径、页面映射、真实接通功能、验证等级、未验证项、失败路线、下一批文件。
- 状态只允许：未检查 / 缺失 / 部分实现 / 已实现未验证 / 已验证 / 有意不迁移（原因）。
- 验证层级必须区分：源码静态检查、Host 回归、Android 单元测试、Gradle 构建、UI 自动化、安装/升级、真机验收。
- 最终 APK/KernelSU ZIP 只有全部功能与风险验收完成后才生成。不要为了让用户“看到包”提前发候选包。

现在开始：读取最新分支 HEAD、实时状态和本文件，直接执行最高优先级的源码批次；完成后写入 GitHub 并更新实时状态，随后继续下一个批次。不要只回复一份计划，也不要要求用户重复需求。


---

# 本轮用户最终需求：必须按此执行的完整功能和 UI 清单（2026-11-05）

你必须把本节作为本次整体重构的最终执行清单；不得因为历史代码里存在来源应用页面，就保留“迁移应用”或旧 APK 启动器。

## 1. UI/导航不可妥协项
- 单 APK、单 Launcher、单原生主界面、统一业务状态。
- 六 Tab 固定：VPN、Ad、隐私、脚本、Hook、设置；索引 0–5。
- Tab 1（索引 1）用户可见文字只能是“Ad”；Hosts 是 Ad 内部子页，禁止任何主导航/主标题写成“Ad/Hosts”。
- 设置绝对不能出现“迁移应用”、来源 APK 列表、Dia/GKD/游龙启动器。删除入口不等于丢弃功能；来源能力必须按业务域迁入。
- Settings 只保留五 Skin、壁纸、主题/动效、全局权限总览、统一备份恢复、通知/诊断偏好、许可证和关于。
- 六 Tab 每一页、所有二级页面、Dialog/Sheet/表单/列表/编辑器/空态/错误态都要支持五 Skin；切换 Skin 不重启任何业务服务。

## 2. 五种 Skin 与壁纸
- ClassicWebCompat：游龙工具 10.0.2 真实旧网页 UI；先对原 APK 资源/页面取证，禁止臆造原版。
- FXLiquidNative：Android Compose 原生液态玻璃。
- MiuixStyle：小米澎湃/Miuix 风格，不能依赖 MIUI 私有 API。
- HUAWEI HarmonyStyle：Harmony tokens/renderer，普通 Android 可用，不冒充鸿蒙原生。
- iOS CupertinoStyle：Cupertino tokens/renderer，不冒充 iOS 原生或系统能力。
- 壁纸沿用已核验 10.0.2 “壁纸随心换”行为：上传本地图片、恢复默认；私有存储、长边 1920px、JPEG q85；FX 扩展可做裁剪/模糊/遮罩，必须标注扩展。壁纸仅影响 UI。

## 3. Ad 完整范围
Ad 必须实现五个独立、可观测过滤层：本地 DNS、系统 Hosts 重定向、应用层 Hook、Accessibility 可见 UI 辅助、TUN/代理过滤。每层分别有开关、权限、状态、日志、统计、错误处理和回退。
游龙广告插件逐项迁入并核对 Ad/General/Summary/Stats/应用白名单/DNS/Firewall/规则订阅/域名名单/Tile/Widget/Tasker/计划任务/Root Proxy/配置备份恢复；版本差异以真实 APK/源码为证，禁止凭名字猜测“全功能”。

## 4. VPN 完整范围
- 小火箭类节点、订阅、分组、协议、直连/全局/规则、应用分流、域名/IP/CIDR、DNS、测速、流量统计、日志、自动重连、导入导出。
- 内置默认内核并允许切换其他内核和上传自定义内核；校验签名/hash/许可证/ABI/能力，切换失败回滚。
- FX 代理主数据面是 Root/系统网络栈级代理，与第三方应用 VPN 共存时不抢占 VPN 槽、不停止对方、不 flush/覆盖第三方路由；检测真实接口/策略路由/DNS，兼容级别按真机验证报告。封闭第三方 VPN 不得承诺完全兼容。
- 防泄漏测试 DNS/IPv4/IPv6/WebRTC/断线/重连/Root 丢失/网络切换/应用分流/第三方 VPN；人工测试 https://who.1ms.dog/zh-cn/ 并记录设备环境。不得以单站点通过推断绝对无泄漏。
- Always-on 优化待机 CPU、唤醒、轮询、重连；用真机功耗数据验收，不承诺零耗电或等同 iOS。
- MITM 支持用户允许范围内的 TLS 请求/响应脚本；CA 生成、保护、安装、信任检查、轮换、撤销、卸载、备份回滚；逐 Android 版本/应用测试。不得保证所有 App 信任系统 CA 或无警告，证书锁定与 QUIC 单独标注。

## 5. 隐私完整范围
保留 FX 原有隐私模块所有功能；迁入游龙安全护盾可合法复用的扫描、病毒库、风险详情、屏幕过滤、每日摘要、完整性、救援、白名单/管控名单、批量清理。应用隐私详情覆盖权限、传感器、剪贴板、通知、Toast、网络隐私。Root、模块、LSPosed、Accessibility 分别显示真实状态；隐藏/兼容能力不承诺绝对隐身，不规避金融、支付、反作弊或设备完整性校验。

## 6. Hook 完整范围
- 已安装应用列表 → 应用详情 → Hook 工具/规则/日志；一个入口，不保留 Dia 第二入口。
- 迁入 Dia 可合法复用工具：Frida 服务/注入/会话、脚本库、DEX、Activity、文件/so、JSON、Inspector、监控、日志、崩溃/签名、系统扩展、Dialog Hook、按键动作 Hook、工具设置。
- 迁入 GKD-XA 1.4.8：selector、规则订阅/分组/应用范围、自动点击/跳过、触发条件/冷却、快照、规则编辑、AI 辅助、历史/日志、备份恢复、Accessibility runtime；先做构建/Manifest/Room/AIDL/生命周期兼容；遵守 GPL-3.0。
- 自定义 Hook 支持多语法/多规则，必须真实解析、校验、执行；按应用更新/VPN/隐私检测展示证据与误报风险。
- 位置模拟仅限用户拥有/授权测试应用，明确不是保证与真实 GPS/网络环境完全一致。
- VIP 仅允许合法授权状态和自有应用 entitlement 测试；禁止伪造会员/绕过支付。

## 7. 脚本完整范围
代理脚本平台覆盖 Surge、Quantumult X、Loon、Shadowrocket、Stash、Egern、Surfboard、Clash/Mihomo、sing-box；实现平台 Parser + API Adapter + Runtime，验证 $httpClient/$task.fetch/$done/$prefs 等真实语义。
规则格式覆盖 AdGuard/uBlock/Adblock Plus/Hosts/PAC/DNS blocklist/URL Rewrite/domain/IP/CIDR。
浏览器脚本覆盖 UserScript 元数据、匹配/排除、GM API、权限、更新和日志；扩展仅在目标浏览器公开支持 WebExtension/扩展 API 时启用，逐浏览器报告能力，不能宣称全局适配所有浏览器。MITM Script 与 Browser UserScript 是不同执行环境。

## 8. 页面布局交付要求
按产品方案文件中的“页面布局重构要求”逐 Tab 实现，不允许只做文档或静态卡片：
- VPN：连接总卡、模式/节点、内核和真实流量路径、共存状态、防泄漏、订阅/规则/DNS/MITM 子页。
- Ad：总开关、五层状态卡、过滤列表、白名单、Firewall、DNS 日志/统计/计划任务；Hosts 编辑器为内部子页。
- 隐私：风险摘要、Root/模块/LSPosed/Accessibility 状态、安全护盾、扫描/病毒库/权限/传感器/剪贴板/通知/Toast。
- Hook：应用列表/详情、Frida、Dia 工具、GKD、自定义 Hook、更新/VPN/隐私检测。
- 脚本：脚本/规则库、平台兼容等级、编辑器、运行任务、MITM、浏览器脚本/扩展、日志/调试。
- 设置：只保留外观、壁纸、权限总览、备份恢复、诊断偏好、许可证、关于。

## 9. 执行方式与验收门禁
1. 读取最新 HEAD 和实时状态；不重做已完成工作，不覆盖并发修改。
2. 建立逐功能矩阵，列出来源证据、FX 页面、实现类、服务/数据、权限、测试和状态。
3. 先修 P0 网络/数据/权限安全，再以完整页面组重构 UI；不得反复只更新文档。
4. 每次改动前读取最新文件和 SHA；串行更新同一路径，写后回读。
5. 每个功能只能标记未检查/缺失/部分实现/已实现未验证/已验证/有意不迁移（原因）。
6. Host 静态回归不等于 Gradle、安装或真机验证。每次报告必须分层。
7. 不支持/不可合法迁移的功能必须写明具体原因和可用替代，不得静默删掉。
8. 现在立即把本节并入唯一正式提示词和产品规格，然后继续源码实现；不要只回复“计划已更新”，也不要要求用户重复需求。
