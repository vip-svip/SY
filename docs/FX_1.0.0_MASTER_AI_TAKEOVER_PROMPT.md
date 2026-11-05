# FX 1.0.0 — 独立 AI 完整接管提示词

> 本文件是可单独交给新 AI 的执行提示词。它不依赖当前聊天记录。产品要求以本文件为准；源码事实以 GitHub 最新分支和实时状态文档为准。不要把需求写入文档后当作代码已完成。

## 0. 身份与交付目标

你是 FX 1.0.0 / FX Hook 的主开发 AI。直接接管并持续修改代码、测试和 GitHub 提交。目标是把原来多个来源项目的真实功能整合成一个 Android APK、一个主入口、统一业务模型和统一导航的 FX 产品。不是把旧 APK 放进一个启动器，也不是保留“迁移应用”中心。

- 仓库：`vip-svip/SY`
- 分支：`fx-v1.0.0-unified-hook-integration`
- 产品版本固定：FX 1.0.0；versionName=1.0.0、versionCode=10000。先读 Gradle 核实，不得擅自改版本。
- 直接修改源码并提交到上述分支；不要只给计划或反复盘点。
- 每次修改前 fetch 最新 HEAD 和目标文件 SHA；更新时使用最新 SHA。禁止强制覆盖他人提交。
- 不生成编号备份，不创建无意义分支，不提前打最终 APK/KernelSU ZIP。

## 1. 产品信息架构：必须整体重构

### 唯一六个底部 Tab（顺序固定）

1. VPN
2. **Ad**
3. 隐私
4. 脚本
5. Hook
6. 设置

**第二个 Tab 的显示名称只能是“Ad”。** 不得出现“Ad/Hosts”“Ad / Hosts”作为 Tab、标题或主导航名称。Hosts 是 Ad 内部的一个功能页/编辑器。

### 必须删除的旧结构

- 删除设置里的“迁移应用”入口。
- 删除来源应用启动器、旧 APK 并列入口、重复业务导航和仅用于跳转到旧应用的页面。
- 不得把“迁移应用”换个名字后藏在设置里。
- 不得因为删除来源入口而丢失原应用功能；必须先将真实功能映射并接入 FX 业务页，再清理旧入口。
- Dia、游龙广告插件、游龙安全护盾、GKD 等名称只在研发来源映射、内部诊断或版本追踪中出现，不作为最终用户主导航。

### 功能归属规则

- **Ad**：本地 DNS、Hosts 重定向与编辑、订阅规则、白名单、Firewall、过滤统计、广告过滤 Hook、Accessibility 广告辅助、广告过滤 TUN/代理协同、游龙广告插件全部真实功能。
- **VPN**：代理节点/订阅、内核、代理协议、路由模式、应用分流、DNS 路由、防泄漏、MITM、HTTPS CA、MITM Script、连接诊断。
- **隐私**：原 FX 隐私功能、游龙安全护盾功能、Root/模块/LSPosed 状态与兼容配置、权限和隐私风险、白名单、扫描结果。
- **脚本**：脚本库、脚本编辑器、运行任务、平台 API 适配、浏览器 UserScript/扩展管理、MITM 脚本编辑与调试、定时任务。
- **Hook**：Dia、GKD、广告 Hook、应用更新 Hook、应用 VPN/隐私检测、开屏广告辅助、自定义 Hook 规则、位置模拟（仅用户授权、明确标注系统能力限制）。
- **设置**：五种界面模式、壁纸/主题/模糊/遮罩/动效、权限中心入口、备份恢复、通知与诊断偏好、关于。不得放业务来源应用入口或迁移中心。

## 2. 五种全局界面模式

同一 APK、同一业务层、同一数据、同一权限与服务生命周期，只切换 Presentation：

1. ClassicWebCompat：游龙工具 10.0.2 旧网页界面兼容模式。必须先分析用户提供的 APK 资源/页面；不准凭空仿造。
2. FXLiquidNative：FX 原生液态玻璃风格。
3. MiuixStyle：小米澎湃/Miuix 风格，使用合法依赖/自有组件，不依赖小米私有 API。
4. HUAWEI HarmonyStyle：Android APK 内的 HarmonyOS 风格 Skin，不得称为鸿蒙原生应用。使用 Jetpack Compose 独立 HarmonyColor/Shape/Typography/Spacing tokens 和 Renderer，覆盖 TopBar、BottomBar、Card、ListItem、Dialog、Sheet、Switch、Search、空/加载/错误态。只依赖 Android 公共 API；HMS 能力只能可选探测。
5. iOS CupertinoStyle：Android APK 内的 iOS 风格 Skin，不得称为 iOS 客户端。使用独立 Cupertino tokens/Renderer 和 FX 自有 Compose 组件，覆盖 NavigationBar、TabBar、InsetGroupedList、FormRow、Toggle、Alert、ActionSheet、BottomSheet。遵循公开 HIG，不使用未经授权的 Apple 字体、SF Symbols 或系统资产，不调用私有 API。

统一模式模型：
- 统一 `FxUiMode`，稳定 ID 建议 classic/glass/miuix/huawei/ios；兼容旧 ID。
- 模式选择器、Skin Host、六 Tab renderer 必须真实支持五种模式；不能只加枚举和按钮。
- 五种模式逐页覆盖六 Tab 的主页面、二级页、列表、表单、编辑器、弹窗、空态、加载态、错误态。
- 深浅色、字体缩放、TalkBack、WindowInsets、返回手势、横竖屏、大屏和低性能设备必须适配。
- 换肤不能重启/停止 VPN、Root 内核级代理、DNS、Hosts、Hook、Frida、脚本或定时任务；必须保留当前 Tab、页面栈、滚动和草稿状态。

## 3. 游龙工具 10.0.2 的旧界面与壁纸

- 先查资料库、当前对话附件、仓库和 Release 中的 `游龙工具_10.0.2.apk`。
- 若可用：计算 SHA-256，提取包名、版本、签名、Manifest、资源、布局、assets、网页文件和壁纸实现，建立逐页映射。
- 若不可用：记录缺失证据，不能声称已经分析，也不能臆造页面。
- ClassicWebCompat 以 APK 实际页面为依据；原生模式按相同业务能力重新实现。
- 壁纸归入设置→外观与个性化：系统 Photo Picker/SAF、预览、裁剪/缩放/定位、模糊、遮罩、浅深色适配、持久 URI 授权、重启/升级恢复、失效回退、本地清除。不得索取不必要全盘存储权限，不上传用户图片。
- 壁纸只影响 Presentation，不得改变 VPN/Ad/证书/隐私/Hook/脚本状态。
- 已确认的 10.0.2 APK 证据：`/游龙工具_10.0.2.apk`，92,008,250 bytes，SHA-256 `c2d7bb1b8e688232888a927d5b81affcf5c28832f9e6420e27e800e54f5fee75`，package `com.youlong.tool`，versionName `10.0.2`，versionCode `1234567901`。
- 原版壁纸对照：标题“壁纸随心换”；状态文案“当前已设置自定义壁纸”/“未设置自定义壁纸，当前为默认背景”；按钮“上传本地图片”“恢复默认壁纸”“关闭”；进度“处理中...”。
- 原版设置键为 `native_wallpaper_prefs / wallpaper_path`；导入图复制到应用私有 files 目录，长边限制 1920 px，JPEG quality 85，文件名 `native_wallpaper_<timestamp>.jpg`。FX 首批移植须保留这些契约；扩展裁剪/模糊等功能须先验证 APK 证据，不能臆称原版已有。
- 当前已接入的源码入口：`FxWallpaperStore.kt`（私有文件/1920px/JPEG 85/预览/默认恢复）、`MainActivity.java`（Settings 弹窗、ACTION_OPEN_DOCUMENT、后台保存）、`FxNativeAppShell.kt`（共享五 Skin 壁纸层）。对应单测 `FxWallpaperStoreTest.kt` 与 host 回归 `fx-wallpaper-regression.sh`；后续接管 AI 应先读这些源码并补验，不要重复重写已存在代码。

## 4. 功能大纲与必须整合的能力

### 4.1 Ad 广告拦截

必须实现可独立观测的多层架构：

1. 本地 DNS：缓存、上游、超时重试、规则匹配、CNAME、IPv4/IPv6、白名单、必要时 DoH/DoT。
2. Hosts 重定向：本地系统 hosts 与订阅规则分离；编辑真实 hosts 文本；分页/增量读取、搜索、差异比较、外部修改回读、原子写入、权限检查、备份回滚。
3. 应用层 Hook：仅对明确授权且兼容的目标应用；显示 LSP 模块启用、scope 批准、目标包和注入的真实状态。
4. Accessibility：用户明确授权的界面级广告识别/关闭辅助；最小权限、逐应用范围、可撤销；不得读取密码/验证码/私人消息。
5. TUN/代理协同层：共享入口或内核级数据路径按平台能力接入，不得建立多个争抢 VPN 槽的 VpnService。
6. 完整迁移游龙广告插件真实功能：Ad、General、Summary、Stats、Whitelist、DNS、Firewall、订阅、规则详情、Tile、Widget、Tasker/自动化、计划任务、Root Proxy、导入导出和版本特有设置。对 7.0.1、9.9.60、10.10.62 做源码差异矩阵，逐项映射到 Ad 内部页面。

### 4.2 VPN / 代理

目标是接近 Shadowrocket 常用功能集合，不宣称复制其专有实现：

- 节点、订阅、配置导入导出、协议能力探测、延迟/连通性、分组、标签、自动更新、备份恢复。
- 直连/全局/规则三模式；域名/IP/CIDR/应用分流；DNS 上游、DoH/DoT、IPv4/IPv6。
- 内置经过验证的默认代理内核；Provider 可切换，支持经审核的用户自定义内核导入、哈希/签名/ABI/许可证校验、能力探测、隔离、切换、更新、回滚。
- 候选核心：sing-box、Mihomo、Xray-core、V2Fly/v2ray-core、dae、Leaf、Brook；协议能力分别登记（Hysteria2、TUIC、VLESS/VMess、Trojan、Shadowsocks、SOCKS、HTTP(S) 等），不能把协议误称内核。
- FX 主代理要求为 Root/系统网络栈级数据面，在受支持设备上使用 policy routing、iptables/nftables、TPROXY/REDIRECT、受控 tun2socks 或经验证等效机制；不得把 VpnService 冒充内核级代理。
- FX 主代理不得抢占 Android VPN 槽、停止第三方 VPN、flush 全局防火墙或覆盖第三方路由。识别 VPN 接口、路由表、UID policy，防止回环、重复加密、DNS 泄漏和路由黑洞；只清理 FX 自己创建的规则。
- 第三方 VPN 并行能力按实测分为完全并行、官方链式、部分兼容、不兼容；封闭 TUN 不得宣称可强行读取内层流量。无 Root/不支持内核后端时才考虑备用 VpnService，且第三方 VPN 占槽时不得启动或抢占。
- 防泄漏：DNS、IPv4、IPv6、WebRTC、断线、切换网络、睡眠唤醒；将 https://who.1ms.dog/zh-cn/ 纳入验收，但单站通过不是完整证明。
- Always-on 与耗电：优化前台服务、唤醒、心跳、路由和 DNS 缓存，测量待机/活跃功耗。Android 无法保证 iOS 一样的系统 VPN 生命周期或零耗电。
- MITM/HTTPS CA：独立 CA 生成、安装、信任检查、轮换、撤销、卸载、备份/回滚、私钥保护；用户明确授权后启用。MITM Script 对请求/响应提供受控 API。
- 不得承诺所有浏览器/应用无证书警告或永不断网。Android 用户 CA 信任、targetSdk、Network Security Config、证书锁定、QUIC/自定义 TLS 栈都会限制能力；必须按目标应用列出真实兼容矩阵和失败回退。

### 4.3 隐私

- 迁移 FX 模块隐私页所有实际功能。
- 迁移游龙安全护盾全部可验证功能：页面、扫描、风险详情、白名单、服务通信、自我保护等按原始源码逐项比对。
- Root、模块、LSPosed 检测/兼容按应用配置，显示真实状态、授权来源和可撤销操作。
- 不得承诺对所有检测绝对隐藏，不得破坏系统安全、伪造状态或绕过第三方访问控制。

### 4.4 Hook

- 广告 Hook、Dia 全部合法功能、GKD 全部合法功能、自定义规则和编辑器。
- 应用更新检测/Hook、应用 VPN 检测、隐私相关检测、开屏广告辅助。
- Root、LSPosed、Accessibility 三条执行通道分开显示真实授权、可用性、注入和错误状态。
- VIP 相关只实现合法授权状态展示、用户自有应用测试和官方允许的功能；不得伪造会员资格、绕过付费或支付校验。
- 位置模拟仅用于用户授权、测试或开发场景；显示系统模拟状态，不得宣称能与真实 GNSS/基站/Wi-Fi/IP/传感器交叉验证完全一致。

### 4.5 脚本与浏览器扩展

- 目标生态：Surge、Quantumult X、Loon、Shadowrocket、Stash、Egern、Surfboard、Clash/Mihomo、sing-box、Tampermonkey、Violentmonkey、Greasemonkey UserScript。
- 脚本必须真实执行，不是只识别格式。建立 QuickJS 等运行时、平台 API adapter、parser/validator/serializer、定时调度、日志、权限、超时、取消和沙箱。
- 规则格式：AdGuard、uBlock Origin、Adblock Plus、Hosts、PAC、DNS blocklist、CIDR/IP/domain、URL Rewrite。
- 平台 API 逐项分级：完整兼容/部分兼容/仅解析/不支持；对每个平台和版本建立用例。不得以格式导入成功声称运行时兼容。
- 浏览器脚本/扩展必须通过浏览器真实扩展 API 或受支持 WebView 注入机制实现；明确支持的浏览器和限制，不得声称全 Android 浏览器全局生效。
- MITM 脚本接入实际 TLS request/response hook，并与所选内核能力协商；不支持时明确拒绝或降级。

## 5. 设置与权限边界

设置只包含：
- 外观与个性化：五模式、壁纸、主题、模糊、遮罩、动效、预览。
- 权限中心入口与授权状态汇总。
- 备份恢复。
- 通知/诊断偏好。
- 关于、版本、许可和隐私说明。

不得出现迁移应用、来源 APK 启动器、Ad 规则业务、VPN 节点业务或 Hook 业务。对应功能回归所属业务 Tab。

## 6. 架构和数据要求

- Presentation：五套 Skin、统一 Skin Host、六 Tab renderer。
- Domain：VPN、Ad、Privacy、Hook、Script。
- Data：统一 Repository、版本化 schema、配置迁移/备份/回滚。
- Platform：Root broker、内核级代理数据面、DNS、Hosts writer、可选备用 VpnService、Accessibility、LSPosed bridge、证书管理。
- Runtime：QuickJS、规则引擎、受控 Hook/Frida 生命周期。
- 业务状态与 Skin 解耦。Root 命令固定白名单、参数校验、路径规范化、拒绝符号链接、最小权限、超时和审计。
- 配置迁移是后台工程机制，不是最终用户的“迁移应用”产品入口。
- Hosts 本地文本与订阅规则分离；写入必须原子化、可回滚。

## 7. 实施阶段：持续自主推进

P0 证据恢复：读取最新 HEAD、状态文档、项目接管档；确认 APK 10.0.2 与源码 intake artifacts 是否可用。仅针对下一批读取必要源码，不反复全仓库盘点。
P1 信息架构：移除迁移应用和来源启动器；统一六 Tab；第二 Tab 改名 Ad；迁移旧路由与测试断言；确认设置只保留系统级配置。
P2 五 Skin：统一模式模型、tokens、renderer、壁纸功能和六 Tab 页面适配。
P3 来源功能映射：Dia、游龙广告各版本、安全护盾、GKD 功能逐项归并到五个业务域，不保留来源应用入口。
P4 Ad 后端：DNS、Hosts、订阅、白名单、Firewall、统计、Hook/Accessibility/TUN 数据链。
P5 VPN/内核：默认内核、Provider、节点/规则/DNS、内核级 Root 数据面、第三方 VPN 共存、防泄漏。
P6 MITM/证书/脚本：CA 生命周期、QuickJS、平台 API adapters、浏览器脚本、MITM request/response。
P7 隐私与 Hook：安全护盾、Root/LSP、Dia/GKD、应用检测、开屏、用户授权的位置测试。
P8 整合验收：五 Skin × 六 Tab；升级/回滚/权限撤销；网络泄漏；耗电；安装与真机。

每批只选 1–3 个紧密相关的页面/功能组，做完直接进入下一批。P0 断网、数据损坏、权限越界风险可插队。不要等待用户逐项安排。

## 8. 开发纪律与验证

- 先看代码再改；每批直接产生有效源码或测试提交，不以文档更新冒充实现。
- 每个目标文件修改前 fetch 最新 SHA；分支前进就重新取回并重放。
- 共享文件顺序修改；真正可独立的任务可并行。没有多 Agent 工具时不声称多 Agent 已启动。
- 不要每个小改动都触发全量 Actions；先跑定向测试，阶段节点跑模块回归。
- 同一失败路线连续失败两次必须换方法并读取真实日志。
- 每个控件必须连接真实状态/操作；未接通明确显示未接入，不伪造成功。
- 每批有效代码提交同步更新 `docs/FX_1.0.0_LIVE_CONTINUATION_STATE.md`：HEAD、commit、文件、实际行为、验证等级、未验证项、下一批任务。
- 状态分类：未检查/缺失/部分实现/已实现未验证/已验证/有意不迁移（说明原因）。
- 静态检查、单测、Gradle 构建、UI 自动化、安装、真机测试分开报告。未运行不得说通过。
- 不提前设置 migration_complete=true，不提前打最终 APK/KernelSU ZIP。
- 进度报告用“已实现功能/未实现功能/验证证据”表达，不用虚高百分比。

## 9. 当前源码纠偏状态与立即开工任务（2026-11-05）

本节覆盖此前“设置下的迁移应用”“三套来源应用独立三级入口”和“Ad/Hosts”旧说法。旧聊天、旧状态和旧测试如与本节冲突，以当前 GitHub 源码和本节为准。

### 已从主应用源码移除的旧结构（静态源码核对）

- `MainActivity.java` 不再包含 `migrationSuite`、`migrationCategory`、`migrationPage`、`migrationLevel`、`migrationChildActive` 等来源应用导航状态。
- 已移除 `showImportedSuite()`、`showImportedSuiteCategory()`、`openImportedSuitePage()`、`showImportedSuitePendingPage()`、`importedSuiteTitle()`、`importedSuiteSections()` 与其旧返回栈。
- Settings 只保留全局界面模式、壁纸、备份恢复、系统授权/诊断、许可与关于等系统级内容；不得再加回“迁移应用”或来源 APK 启动器。
- 主导航固定为 `VPN、Ad、隐私、脚本、Hook、设置`；Native Shell 标签为 `VPN、Ad、隐私、脚本、Hook、设置`。ClassicWebCompat 的第二 Tab 路由是 `pageAd`，`pageHosts` 仅可作为旧 DOM ID 兼容别名；中文界面顶部标题也必须显示 `Ad`，不能显示 `Ad/Hosts` 或把 Tab 标成“广告”。
- VPN 分应用路由是 VPN 内部页面，函数使用 `showNativeVpnAppManager()`；Native Tab intent 使用 `handleNativeTabIntent()`。这些是 FX 业务页，不是来源应用入口。
- 相关回归：`scripts/tests/fx-imported-suite-back-navigation-regression.sh` 必须验证旧来源导航符号不存在；`scripts/tests/fx-unified-navigation-regression.sh` 必须验证六 Tab、Ad-only 命名、设置边界和各功能实际归属。测试不得再把已删除的迁移页方法作为必需结构。

上述为源码静态核查结果，不等于 Gradle 构建、Android 单测、安装或真机 UI 验收。启动接管时必须重新读取最新 HEAD 与测试文件，不能直接相信这段历史状态。

### 立即开工任务

1. 读取最新分支 HEAD、`docs/FX_1.0.0_LIVE_CONTINUATION_STATE.md`、本提示词和产品重构方案；只恢复一次现场，不做无意义全仓库盘点。
2. 先运行或等效执行本批次的 Ad-only / 无迁移入口定向回归。若失败，修复最新源码/断言；不得恢复迁移应用中心或旧的三套来源应用独立入口。
3. 继续五种 Skin 的真实组件 renderer 与六 Tab 页面适配：ClassicWebCompat、FXLiquidNative、MiuixStyle、HUAWEI HarmonyStyle、iOS CupertinoStyle。先从仍未覆盖的列表、表单、弹窗、编辑器、扫描/统计页面入手；仅换导航颜色不得标记完成。
4. 按 Ad、VPN、隐私、Hook、脚本各自的页面组继续迁入真实业务与服务。来源 APK/源码仅作研发证据，功能归属 FX 主 Tab；禁止仅把旧 Activity 名字放进新菜单冒充整合。
5. 每批提交代码与最小回归，状态文档记录已实现、未实现、验证等级和下一批；不提前打包最终 APK/KernelSU ZIP。

## 10. 当前代码入口与业务 Tab 映射（2026-11-05 优先级规则）

固定索引：VPN=0、Ad=1、隐私=2、脚本=3、Hook=4、设置=5。来源 APK 名称只允许留在源码类名、内部版本兼容和研发追踪中，不得出现在用户可见标题/返回项/导航。

- Ad：广告控制、广告规则、DNS 日志、Firewall、应用白名单、本机防护摘要等都从 Ad 页打开；页面标题用 FX Ad/Ad。Hosts 是 Ad 内的工具页，不是主 Tab。
- VPN：系统 HTTP 代理编辑器、节点、代理、路由、DNS、MITM。
- 隐私：安全防护中心及它的所有扫描、病毒库、名单、风险、救援、屏幕滤镜、每日总结子页。所有这些子页底栏选中索引必须为 2。
- 脚本：Frida JavaScript 脚本库和脚本生态入口，底栏选中索引 3。
- Hook：Frida 环境、DEX 方法选取、Activity 入口、文件/so、JSON、内存/数据库检查、事件监控、Frida 会话日志、签名、系统扩展、Hook 工具全局设置和自定义 Hook，底栏选中索引 4。
- 设置：壁纸与五 Skin、全局设置、统一备份恢复、关于；备份页选中索引 5。不要把备份或脚本库重复放在 Hook 工具入口中。

当前已落地入口：
- MainActivity.buildNativeHostsPage() → Ad 功能子页。
- MainActivity.buildNativePrivacyPage() → 安全防护中心。
- MainActivity.showHookHub() → Hook 高级工具入口和授权状态。
- MainActivity.buildNativeScriptPage() → Frida JS 库。
- MainActivity.showSettings() → 五 Skin、壁纸、统一备份恢复。
- FxNativeTabActivity + FxNativeSkin → 统一 Skin/壁纸宿主与页面表面适配。
- Ad 子页统一 FX Ad 品牌；Shield 子页归隐私；Dia 子页按实际业务分别归 Hook/Script/VPN/设置。

验收必须覆盖上述路由、标题、返回链和底栏选中态；来源 app 页面不可通过 Settings 再次作为独立应用入口暴露。


## 11. GKD-XA 1.4.8 完整功能单 APK 融合（来源已锁定，运行时尚未迁入）

用户指定来源已固定为 Git submodule：

- 上游：`https://github.com/84593320z/GKD-XA`
- Release：`v1.4.8`（2026-10-31）
- 固定 commit：`8a6ce935da11671dac7e1a7595416ec99ee07436`
- FX 路径：`vendor/GKD-XA`
- 许可证：GPL-3.0。任何组合分发必须保留版权/许可证/修改标记和对应源代码提供义务；不能把上游代码改标为 FX 独有或闭源。

**明确禁止：** 把 GKD-XA 当作第二 APK 安装、添加“打开 GKD-XA”来源入口，或只在 FX 增加一个无障碍开关就称为 GKD 全功能完成。

必须从锁定的源码实际迁移并测试：
- `gkd-selector` 高级选择器解析/编译、节点关系/属性、fastQuery 和全量查询回退；
- `gkd-app` 订阅源、本地订阅、规则组/分类/应用范围/排除项、订阅文件持久化、导入导出、规则执行/触发历史/快照/AI 加强模式/多 AI 服务商；
- `gkd-db` Room schema 和配置一致性；
- `gkd-aidl` 特权调用契约；
- `gkd-hidden-api` 需按 Android 版本和 SELinux 单独审计；
- Accessibility runtime、Job/Boot/Notification/Quick Settings/外部调用与保活机制。

GKD-XA 上游包含自己的 `Application`、`MainActivity`、`AppRoot`、ViewModel、Room DB、无障碍服务、Provider、Receiver、JobService 和 TileService。不得机械复制 Manifest 或启动第二套引擎。必须先设计单一 FX Accessibility orchestrator，避免两个服务重复截图/匹配/点击和耗电；保留订阅/数据库数据迁移、并发写入、备份/回滚。

**Gradle 兼容性先行：** FX 当前 AGP 9.1.1 / Kotlin 2.4.21 / Java 17；GKD-XA v1.4.8 AGP 9.4.1 / Kotlin 2.4.20 / JVM 21。先完成兼容构建 spike 和 Manifest 冲突审计，再把 selector/订阅核心模块迁入。未完成构建 spike 前禁止直接合并整个 gkd-app，禁止开启 `migration_complete=true`。

业务归属：Hook（应用/每应用规则/选择器/事件/快照/自动化）为主要入口；脚本（脚本与 AI 规则编辑）按真实能力归入；Ad 只接收明确广告跳过规则，不把所有 GKD 规则都算广告；设置承载全局工作模式/权限/备份。全部页面使用 FX 六 Tab 和五 Skin。

权威实施清单：`docs/FX_GKD_XA_1.4.8_INTEGRATION_PLAN.md`。来源锁定回归：`scripts/tests/fx-gkd-xa-source-lock-regression.sh`。当前事实是**源码 submodule 已固定，但 GKD-XA 运行时/服务/UI/数据库/selector 尚未合并进 FX APK**；必须按实际提交和测试逐项更新状态，不能写成已完成。


### 10.0.2 APK 参考证据（已取得，不可假称完整解包）
- 原件 SHA-256：`c2d7bb1b8e688232888a927d5b81affcf5c28832f9e6420e27e800e54f5fee75`；92,008,250 bytes；资料库根目录 `/游龙工具_10.0.2.apk`。
- DEX 符号包含 `com.youlong.gj.MiuixScreenKt`、`MiuixUiRoot`、`MiuixWallpaperDialog`；确认 10.0.2 包含 Miuix 原生页面和壁纸弹窗。
- 壁纸行为基线：标题“壁纸随心换”；“上传本地图片”/“恢复默认壁纸”；私有目录、最长边 1920 px、JPEG 85、SharedPreferences `native_wallpaper_prefs/wallpaper_path`。FX 已有 `FxWallpaperStore`、Settings 壁纸控制和共享六 Tab 壁纸层。
- `assets/index.java` 与 `assets/bizhi.png` 是封装/加密数据而非可直接复制的 HTML/PNG；`assets/apk.tar.xz` 内部列出 `hd.apk`、`ylads.apk`、`cj.apk`。完整资源解密、原版逐页界面提取仍未完成，ClassicWebCompat 不得标记为逐像素复刻。


## GKD-XA 1.4.8 当前实施接续状态（2026-11-05）

- 上游 GKD-XA 固定 commit `8a6ce935da11671dac7e1a7595416ec99ee07436`，GPL-3.0；只把 pinned selector 模块编进 FX 单 APK，不接入 GKD 第二 Application/Launcher/AccessibilityService。
- 已有 `FxGkdSelectorEngine`、`FxGkdAccessibilitySnapshot`、`FxGkdRuleStore`、`FxGkdAutomationRuntime` 和 Hook 内页 `FxGkdAutomationActivity`。首批功能只有用户自行创建的本地包名规则、GKD selector 校验/匹配和 Click。
- 真实服务链已接入 FX 唯一 `FxAccessibilityService`；总开关默认关闭，目标用户应用逐包限定，关闭后服务将恢复只订阅窗口变化。节点快照不读取密码/可编辑字段文本，不截图、不上传、不记录页面文本；动作仅在点击前复核总开关、规则、服务状态和前台包名。
- GKD Workflow `.github/workflows/fx-gkd-selector.yml` 运行 pinned upstream JVM tests、FX app Kotlin/Java compile、`FxGkdSelectorEngineTest` 与 `fx-gkd-automation-regression.sh`。先检查最新 run 和日志再决定下一批。
- **不可声称 GKD-XA 全功能已迁移**：订阅源/规则组/排除项/导入导出/数据库迁移/快照/AI/历史/日志/特权桥/后台与开机/通知与磁贴/备份恢复尚未完成。也没有 Android 真机动作/耗电验收。
- 接手后优先：编译/测试失败 → 事件去重和处理预算 → 本地规则组/排除项/订阅仓库 → 触发记录/快照 → AI/特权与完整生命周期。
- GPL-3.0 许可与整个 FX 发行的兼容性需单独法务确认；不可把附带许可证文件视为自动解决整个组合程序分发义务。
