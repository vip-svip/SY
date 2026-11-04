# FX 1.0.0 / FX Hook — 产品重构总方案与跨 AI 接管提示词

> 状态：需求基线 / 架构与 UI 重构方案（不是已实现声明）
> 仓库：`vip-svip/SY`
> 分支：`fx-v1.0.0-unified-hook-integration`
> 产品版本固定：FX 1.0.0（versionName=1.0.0、versionCode=10000；修改前必须核实）
> 本文件用途：让新的 AI 在不依赖当前聊天上下文的情况下，理解产品目标、边界、页面结构、技术路线、验收标准，并直接接管实施。
>
---

## 0. 执行摘要与不可变原则

FX 是一个单 APK、单入口、统一配置和生命周期的 Android 工具套件。目标不是把多个旧 APK 简单放在一个启动器里，而是把可合法迁移的 UI、业务能力和数据流程整合到 FX 原生应用中。

本次产品重构定义五种可切换的全局界面模式：

1. **老版本界面（网页界面）**：保留游龙工具 10.0.2 APK 的旧版 Web UI 风格、导航和操作习惯，作为兼容/经典模式。
2. **原生界面（液态玻璃风格）**：FX 默认主界面。使用 Android 原生控件和统一组件，半透明材质、层次模糊、柔和高光、圆角卡片和动态层级；低性能设备自动降级。
3. **Miuix 界面（小米澎湃风格）**：采用 Miuix/HyperOS 风格的布局、组件密度、色彩、图标与动效；不得把小米系统私有 API 当作所有 Android 设备的必需依赖。
4. **HUAWEI 界面（HarmonyOS/鸿蒙风格）**：采用华为 HarmonyOS 的视觉语言，包括清晰的信息层级、卡片式服务入口、和谐留白、统一图标网格、轻量转场、强调内容与状态的布局。它是 Android APK 内的鸿蒙风格 Skin，不是 HarmonyOS 原生应用，也不得依赖华为私有系统服务才能运行。
5. **iOS 界面（Cupertino 风格）**：采用 iOS 人机界面指南中的导航栏、标签栏、分组列表、表单、Sheet、开关、圆角和层级模糊等视觉与交互语言。它是 Android APK 内的 iOS 风格 Skin，不是 iOS 客户端，也不能调用 Apple 私有 API 或声称具备 iOS 系统能力。

**界面模式是表现层切换，不是五套独立应用。** 五种模式必须共用同一业务层、状态模型、权限、数据库、服务、配置和路由。切换模式不能清除数据、重启过滤规则或改变 VPN 实际路由。

其他不可变原则：

- 固定六个底部主 Tab，顺序：VPN、Ad、隐私、脚本、Hook、设置；第二个 Tab 的唯一显示名称为“Ad”，设置始终第六。
- Hook 必须是第五 Tab；不能另建第二个 Hook APK 入口。
- 老版 Web UI 仅作为兼容显示层逐步迁移，不得用 WebView 假装新原生页面；旧桥接被真实功能依赖时，先迁移调用方再退役。
- 业务状态必须来自真实服务/系统 API。禁止假按钮、假数据、假运行状态、空壳页面或用日志冒充功能。
- 保留原有数据格式和可迁移配置；迁移必须有版本化、备份、失败回滚。
- 优先补齐页面和真实交互，再按页面批次接后端；断网、数据丢失、权限越界、VPN/DNS 错路由等 P0 风险可并行优先修复。
- 不生成编号备份；不覆盖未读取的最新分支状态；不提前交付未完成的最终 APK/KernelSU ZIP。

## 1. 五种界面模式与壁纸系统

### 1.1 模式选择入口

设置 → 外观与个性化：

- 界面模式：ClassicWebCompat / FXLiquidNative / MiuixStyle / HUAWEI HarmonyStyle / iOS CupertinoStyle。
- 壁纸：系统壁纸、从相册选择、恢复默认、模糊强度、遮罩强度、壁纸明暗适配。
- 动效：跟随系统 / 减少动效 / 关闭背景模糊。
- 主题：跟随系统、浅色、深色、自动。
- 预览：切换前显示首页和主要 Tab 预览；确认后应用。
- 可选“仅本机应用界面”，不得把壁纸上传到服务器。

### 1.2 经典网页模式

- 以游龙工具 10.0.2 APK 的实际页面、菜单、布局、图标、配色和操作顺序为对照。
- 必须先取得并核验 `游龙工具_10.0.2.apk` 原件；记录 SHA-256、包名、版本、签名信息。
- 使用 APK Analyzer/apkanalyzer、Manifest、资源表、布局 XML、assets、Smali/反编译结果建立页面映射。
- 若原版 Web UI 资源可合法复用，优先复用并迁移其静态资源；若只能通过旧 WebView 运行时兼容，明确标记兼容层，不将其计为原生迁移完成。
- 不得把原 APK 作为外部依赖安装/启动来冒充已整合。

### 1.3 原生液态玻璃模式

- 原生 Android 页面；统一 Design System：Material 3 基础 + FX Glass tokens。
- 玻璃效果：半透明面板、背景模糊、细描边、高光、柔和阴影、景深分层；内容区必须保证文字对比度和可访问性。
- 根据 Android 版本、GPU 和系统模糊能力自动降级为半透明纯色，不允许因模糊效果导致卡顿、耗电或崩溃。
- 支持动态颜色，但品牌色、状态色和安全警告色必须保持一致。
- 动效短、可中断、尊重系统减少动效设置。

### 1.4 Miuix / 澎湃风格模式

- 以 Miuix/HyperOS 的视觉语言作为设计参考：紧凑信息布局、大圆角、分组列表、清晰层级、轻量转场、系统设置式交互。
- 先确认仓库已有依赖和许可；优先采用可合法集成的开源 Miuix 组件/设计规范。不得复制未经许可的私有资源或系统代码。
- 在非小米设备上必须完整运行；不能依赖 MIUI/HyperOS 私有服务。
- 统一控件语义、可访问性、字号缩放和深色模式。

### 1.5 HUAWEI / HarmonyOS 风格模式（新增）

- 产品定位：在 Android 版本 FX 中提供 HarmonyOS 视觉风格适配，不将其包装成 HarmonyOS 原生应用。必须能在非华为 Android 设备上运行。
- 设计规范：采用清晰卡片层级、服务卡片式信息组织、较宽松的内容留白、统一图标与字号网格、明确的主次操作、轻量连续动效；避免照搬华为系统私有图标、品牌资产或未授权资源。
- Android 实现：继续使用现有 Kotlin + Jetpack Compose 页面体系，新增 HUAWEI_HARMONY Skin token/renderer；建立 HarmonyColorTokens、HarmonyShapeTokens、HarmonyTypographyTokens、HarmonySpacingTokens 和组件适配层，统一覆盖 TopBar、BottomBar、Card、ListItem、Dialog、Sheet、Switch、Search 与空/加载/错误状态。
- 系统能力：优先使用 Android 公共 API。若设备确实提供可选华为能力，可通过独立 capability adapter 探测后启用；缺失时无缝回退，不允许把 HMS、HarmonyOS 私有 API 或华为设备作为基础运行前提。
- 适配边界：状态栏/导航栏颜色与图标对比度、手势返回、字体缩放、深色模式、横屏、折叠屏/大屏和系统显示尺寸必须遵循 Android WindowInsets 与 WindowSizeClass；不伪造鸿蒙系统设置页或系统级卡片能力。
- 验收：华为设备与非华为 Android 设备均可启动；切换 Skin 不重建业务服务；各主 Tab 的列表、表单、弹窗、键盘、返回栈和无障碍语义一致。

### 1.6 iOS / Cupertino 风格模式（新增）

- 产品定位：在 Android APK 内模拟 iOS 的视觉与交互风格，不代表 FX 已有 iOS 原生版本，也不承诺获得 iOS 系统权限、后台生命周期或 Network Extension 能力。
- 设计规范：采用 Cupertino 风格导航栏、分组设置列表、底部标签栏、圆角 Sheet、简洁表单、开关控件、层级模糊、轻量转场和克制的强调色；交互细节参考公开的 Apple Human Interface Guidelines。
- Android 实现：新增 IOS_CUPERTINO Skin token/renderer；建立 CupertinoColorTokens、CupertinoShapeTokens、CupertinoTypographyTokens、CupertinoSpacingTokens 和组件适配层。Compose 中使用 FX 自有组件实现 Cupertino 风格 NavigationBar、TabBar、InsetGroupedList、FormRow、Toggle、Alert、ActionSheet 与 BottomSheet，不将 Android Material 默认控件仅换色后称为 iOS 风格。
- 图标与字体：优先使用合法授权的 SF Symbols 使用范围或采用语义一致的开源/自绘图标；不得打包或分发未经许可的 Apple 字体、图标、壁纸和系统资源。系统字体采用 Android 可用字体栈近似呈现，允许用户调整字号。
- 手势与系统栏：用 Android 公共 WindowInsets、BackHandler 和 Compose 手势实现页面内交互；不得拦截系统返回/辅助功能手势，不伪造 iOS 状态栏、控制中心或系统弹窗。
- 验收：在 Android 设备上逐页检查导航栏、标签栏、列表分组、Sheet、键盘、深浅色、字号缩放和 TalkBack；所有控件仍调用同一 FX 业务状态与真实操作。

### 1.7 五种 Skin 的统一源码实现方法

- 统一模型：扩展 FxUiMode，为新增模式分配稳定 ID（建议 huawei、ios），保留既有 classic、glass、miuix ID；未知值安全回退，不覆盖已有用户设置。
- Renderer：将模式到页面的映射集中在 FxNativeAppShell/统一 Skin Host，不允许各 Activity 私自读取偏好或各自维护不同的模式 ID。
- Design tokens：新增独立 HarmonyOS 与 Cupertino token 集，禁止把所有模式写成散落的 if (mode == ...) 色值；共用语义组件接口，模式仅替换 token 和 renderer。
- 页面迁移：先完成六个 Tab 的共享组件，再逐页覆盖主页面、列表、表单、编辑器、弹窗、空状态、错误状态；旧页面无法适配时明确记录兼容边界。
- 状态与服务：模式切换只更新 Presentation 层；不得停止/重建 VPN、内核级代理、DNS、Hook、脚本或定时任务，不清空页面状态、滚动位置和编辑草稿。
- 测试：为五种模式建立枚举/存储迁移单测、Skin token 单测、六 Tab renderer 回归、截图基线、无障碍语义、字体缩放、深浅色、横竖屏、窗口尺寸和服务运行中换肤测试。截图测试不得代替功能测试。
- 兼容策略：ClassicWebCompat、FXLiquidNative、MiuixStyle、HUAWEI HarmonyStyle、iOS CupertinoStyle 是同一个 Android APK 的五套 Presentation Skin；未来如开发真正 iOS 客户端，应单独建立 iOS 工程并复用协议/业务契约，不能把 Android Compose Skin 视作 iOS 原生实现。

### 1.8 壁纸功能

- 支持从系统照片选择器选取图片，优先使用系统 Photo Picker/SAF，不索取不必要的全盘存储权限。
- 支持应用内壁纸预览、裁剪/缩放、位置调整、模糊、暗色遮罩、透明度、重置。
- 壁纸 URI 使用持久授权；授权失效、文件删除或格式损坏时回退到默认背景并给出提示。
- 壁纸只影响 UI，不得改变过滤、VPN、证书、隐私或 Hook 的运行状态。
- 对敏感页面（证书、密钥、日志、扫描详情）自动使用高可读性遮罩；用户可关闭动态背景。
- 不将原图复制到公共目录；默认本地存储，提供清除壁纸数据操作。
- 验收：模式切换、壁纸更换、重启、升级、权限撤销、图片删除、横竖屏、深浅色、低性能降级均可正确恢复。

### 1.8.1 游龙工具 10.0.2 原版壁纸行为（已核验）

资料库根目录中的 `游龙工具_10.0.2.apk` 已实际读取并校验：
- 文件：`/游龙工具_10.0.2.apk`
- 大小：92,008,250 bytes
- SHA-256：`c2d7bb1b8e688232888a927d5b81affcf5c28832f9e6420e27e800e54f5fee75`
- 包名：`com.youlong.tool`
- versionName：`10.0.2`；versionCode：`1234567901`

DEX 可核验的原版壁纸交互：
- 弹窗标题：`壁纸随心换`
- 当前状态文案：`当前已设置自定义壁纸` / `未设置自定义壁纸，当前为默认背景`
- 操作：`上传本地图片`、`恢复默认壁纸`、`关闭`；处理状态：`处理中...`
- 原版偏好项：SharedPreferences `native_wallpaper_prefs`，键 `wallpaper_path`。
- 原版私有保存行为：选取图片后存入应用私有 files 目录，长边限制 1920 px，JPEG quality 85，文件名模式 `native_wallpaper_<timestamp>.jpg`；恢复默认会清除自定义路径并回到默认背景。

当前 FX 首批迁移必须保持上述可见文案、上传/恢复行为、私有存储边界和图片处理参数。更进一步的裁剪、模糊、遮罩、定位调节属于扩展体验要求，必须先从 APK 的实际实现证据确认原版是否存在；不得把 FX 新增设计误标成 10.0.2 原版功能。

FX 当前源码接线（实现状态以实时状态文档为准）：
- `adhook/app/src/main/java/de/privacyguard/adhook/FxWallpaperStore.kt`：私有存储、缩放、JPEG、预览解码、恢复默认。
- `adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`：Settings 壁纸弹窗、系统图片选择器、后台保存、恢复默认和 WebView 透明背景。
- `adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt`：五 Skin 共用壁纸层、IO 解码和 Bitmap 生命周期。
- `adhook/app/src/test/java/de/privacyguard/adhook/FxWallpaperStoreTest.kt` 与 `scripts/tests/fx-wallpaper-regression.sh`：图片缩放/采样测试与端到端源码契约回归。
- 壁纸数据不上传、不放公共目录、不保留长期外部 URI 授权；失败写入不替换旧图。未完成 Gradle/设备验证前，不得称为真机验收通过。

## 2. 应用信息架构与导航

### 2.1 固定六 Tab

1. **VPN**
2. **Ad**
3. **隐私**
4. **脚本**
5. **Hook**
6. **设置**

顶部标题、底部导航、页面返回栈和状态恢复由统一导航状态管理。各模式只替换视觉组件和布局适配器，不复制业务 Activity/Service。

### 2.2 来源能力的内部归并原则

Dia、游龙广告插件、游龙安全护盾、GKD-XA 等只作为开发阶段的源码/功能来源，不在最终产品中保留“迁移应用”入口、来源应用启动器或平行的旧应用导航。必须将其真实功能按业务归属拆解并融入 FX：

- 广告拦截、DNS、Hosts、Firewall、白名单、统计、订阅、Tile/Widget/Tasker 等归入 Ad。
- 节点、代理、VPN、规则路由、DNS 路由、防泄漏、MITM/证书等归入 VPN（Ad 专属过滤规则仍由 Ad 管理）。
- Root/模块/LSPosed/权限风险/安全护盾等归入隐私。
- Dia、GKD 及自定义 Hook、应用更新/检测/开屏等归入 Hook。
- 所有脚本库、运行任务、浏览器脚本、MITM 脚本和规则脚本归入脚本。
- 设置只保留全局外观、权限入口、备份恢复、通知/诊断偏好、关于等系统级配置，不得放置“迁移应用”或旧来源应用入口。

来源标识、版本差异和映射表仅保留在开发文档、内部诊断或迁移日志，不作为最终用户主导航。不得为了保留旧 APK 页面树而破坏 FX 统一信息架构。


## 3. 功能总纲

### 3.1 广告拦截（Ad）

目标：多层协作、可独立开关、可观测、失败可回退。

1. **本地 DNS 层**
   - 本地 DNS 解析与缓存、上游选择、DoH/DoT（按实际实现和许可）、超时/重试、DNSSEC 状态（若支持）。
   - 域名规则匹配、CNAME 处理、IPv4/IPv6、缓存失效、分流和白名单。
   - 不把 DNS 层开关与 VPN 节点开关混为一谈。

2. **Hosts 重定向层**
   - 本地系统 hosts 与订阅规则严格分离。
   - 本地 hosts 必须编辑真实系统文本文件，支持分页/增量读取、搜索、差异比较、外部修改回读、原子写入、权限检查、备份/回滚。
   - 订阅源独立管理：来源、更新时间、条目数、失败状态、合并优先级和白名单。
   - 防止错误规则将系统域名、DNS、更新服务或登录服务整体阻断。

3. **应用层 Hook**
   - 对明确授权、兼容的目标应用执行域名/请求拦截或隐私保护。
   - 支持 LSPosed/LSP scope、模块启用状态、目标包名和注入状态真实回读。
   - 不以配置文件存在就声称 Hook 已注入；需区分未安装框架、未授权、目标不兼容、注入失败、运行中。

4. **无障碍服务层**
   - 仅用于用户明确授权的界面级广告识别/关闭、跳过按钮辅助和可访问性增强。
   - 提供服务用途说明、最小权限、逐应用启用名单、立即停用和日志脱敏。
   - 不用于读取密码、验证码、私人消息或绕过应用安全验证。

5. **内核级代理层（FX 代理的主实现，不依赖 Android VpnService 抢占槽位）**
   - FX 代理必须优先采用 Root/系统网络栈级数据面：在设备支持且经验证的环境中，通过 Linux policy routing、iptables/nftables、TPROXY/REDIRECT、受控 tun2socks 或等效内核网络机制接管流量；具体后端按 Android 内核版本、SELinux、厂商规则和 ABI 探测选择。
   - 代理转发、DNS、规则分流和连接状态由 FX 内核级代理服务负责；不能把“启动一个 VpnService”包装成内核级代理。FX 自身 VpnService 仅作为无 Root/不支持内核级接管时的可选兼容后端，不是内核级代理的默认实现。
   - 必须以“FX 代理与第三方应用 VPN 同时运行且互不争抢 VPN 槽”为核心验收目标。FX 不注册第二个 VpnService、不调用 VPN prepare 抢占第三方 VPN、不擅自停止或重置用户 VPN。
   - 与应用 VPN 并行时，优先采用可验证的路由链/接口协作：识别当前 VPN 接口、路由表、策略规则和 UID 范围；只接管明确允许的流量，防止 FX 代理与第三方 VPN 形成回环、重复加密、DNS 泄漏或路由黑洞。
   - 若第三方 VPN 提供官方代理链、上游代理、分流接口或可配置排除项，使用其受支持集成方式；若其 TUN/策略路由封闭，不能假称 Root 规则一定能看到 VPN 内层明文流量。此时明确标记该 VPN 的兼容等级和可用路径，不能破坏或绕过用户 VPN 的安全策略。
   - 提供模式：内核级代理独立运行；与受支持应用 VPN 并行；第三方 VPN 接管全部流量时的兼容/链式模式；无 Root 时的单 VpnService 回退模式。各模式分别显示真实流量路径、能力、限制和状态。
   - 任何规则变更前保存原有 iptables/nftables、ip rule、路由表和 DNS 状态；停止/崩溃/升级时只撤销 FX 自己创建的规则，恢复原状态；禁止 flush 全局规则或覆盖第三方 VPN 路由。
   - 第三方 VPN 占用 Android VPN 槽时，FX 内核级代理不得因此自动关闭；必须先检测实际网络路径，报告“完全并行/链式兼容/仅部分兼容/不兼容”的真实结果。
6. **备用 TUN 代理层**
   - 仅在无 Root 或内核级后端不可用时，使用 FX 自己的共享 VpnService/TUN 入口承载 DNS/广告过滤和代理流量两条逻辑管线。
   - Android 同一用户/配置文件只能有一个活动 VpnService；不得让广告 VPN 与代理 VPN 相互抢占。
   - 第三方 VPN 已占槽时，备用 TUN 后端不得启动或抢占；明确提示改用内核级后端/受支持链式模式，不能谎报全量过滤。

6. **游龙广告插件完整功能迁移**
   - 以已接管的游龙各版本源码为依据建立功能矩阵，逐项核对：Ad、General、Summary、Stats、App Whitelist、DNS、Firewall、订阅/规则详情、Tile、Widget、Tasker/自动化、计划任务、Root Proxy、配置导入导出及其原始设置项。
   - 对 7.0.1、9.9.60、10.10.62 的差异做版本映射；不能只迁移一个版本页面就宣称“所有功能”完成。
   - 每个功能记录：原始类/页面、数据格式、权限、FX 对应页面、后端、验证状态。

### 3.2 VPN / 代理

目标：实现接近 Shadowrocket/小火箭的常用能力集合，而非声称复制其专有实现。

1. **内核级代理与应用 VPN 共存**：FX 主代理必须是 Root/系统网络栈级数据面，不能依赖第二个 VpnService。以第三方应用 VPN 同时运行作为 P0 验收场景；检测路由/接口/UID 策略并防止回环、DNS 泄漏和路由黑洞。支持并行或官方链式集成；对封闭 VPN 的能力边界如实标注。无 Root 时才回退 FX 自身 VpnService，且不得抢占第三方 VPN。
2. **去广告协同**：Ad 过滤与代理逻辑分离；能接入同一内核级流量路径时共享 DNS/策略决策。无 Root/内核级后端时才由 FX 备用 TUN 承载；VPN 关闭时仍可使用独立 Root hosts/DNS 能力（取决于系统环境）。
2. **节点和配置**：节点管理、订阅更新、配置导入/导出、协议能力检测、延迟/连通性测试、分组、标签、排序、备份恢复。
3. **代理协议与路由**：按项目依赖和许可逐项支持常见协议/传输；规则模式、全局模式、直连模式、域名/IP/CIDR/GeoIP/进程/应用分流（Android API 可行范围内）。
4. **DNS**：本地 DNS、远程 DNS、DoH/DoT、Fake-IP/Real-IP（若实现）、DNS 分流、污染防护、缓存、IPv6 和防泄漏策略。
5. **应用级路由**：按应用选择代理/直连/阻止；与 Android VPN allow/disallow 应用规则正确协调。
6. **连接控制**：启动/停止、自动重连、网络切换、Wi-Fi/移动网络策略、开机启动、Always-on VPN 兼容、锁定模式提示、前台服务通知、连接日志。
7. **防泄漏**：建立 DNS、IPv4、IPv6、WebRTC、路由绕行和断线行为测试矩阵。将用户提供的 `https://who.1ms.dog/zh-cn/` 纳入人工验收目标；记录测试时间、网络、节点、VPN 模式和页面结果。单一网站通过不等于全面无泄漏。
8. **低耗电常驻**：采用 Android 正规 VpnService/前台服务/Always-on 能力，事件驱动网络监听、合理心跳、无高频轮询、无空闲持锁、缓存和批处理；测量待机耗电、唤醒次数、CPU 和流量。Android 不能保证与 iOS 相同的 VPN 生命周期/耗电表现，不得承诺绝对零耗电或绕过系统电池管理。
9. **MITM / HTTPS 证书**：
   - 独立 CA 生命周期：生成、安装、信任状态检查、轮换、撤销、导出受保护备份、卸载、回滚。
   - 明确区分用户 CA 与系统 CA；Android 版本、厂商、应用 targetSdk 和 Network Security Config 会影响信任行为。
   - 仅在用户明确开启并授权的设备/流量范围内执行 TLS 检查；提供按应用/域名白名单、敏感域名默认绕过、即时关闭和审计日志。
   - 不能保证所有浏览器/应用都无警告：证书锁定（pinning）、应用自定义信任库、QUIC/HTTP3、硬件密钥/安全策略都可能阻止 MITM。不得通过伪造安全成功状态掩盖失败。
   - 系统级证书安装需 Root/系统版本适配、可验证回滚和设备恢复方案；不能把用户 CA 安装描述成系统级信任。
10. **MITM 脚本**：为 Script 提供请求/响应钩子、URL 匹配、Header/Body 处理、超时、错误隔离、权限沙箱和逐规则启停。TLS 失败时必须 fail-closed 或按用户配置安全绕过，不得无限重试造成断网。

### 3.3 隐私

1. **现有 FX 隐私模块**：逐项迁移当前隐私面板、应用列表、规则、白名单、开关、说明、权限状态和持久化；以当前源码为准，不用新 UI 覆盖未完成的后端。
2. **游龙安全护盾**：迁移 Hub、扫描、风险详情、黑白名单、批量清理、病毒库、告警、完整性/日报、Screen Filter、Rescue、Stellar 内部页面及其数据流程。
3. **Root 隐藏/兼容**：做成按应用配置的兼容性控制和状态诊断；不得承诺对所有检测方式隐身，也不得破坏系统完整性、银行/支付安全或 Android 安全模型。
4. **模块隐藏**：展示模块可见性配置、作用范围、状态回读和恢复入口；隐藏失败必须可诊断，不得误报成功。
5. **LSP/LSPosed 框架隐藏/兼容**：区分框架安装、scope 授权、模块加载、目标注入和运行状态。不能仅隐藏图标就称框架已隐藏；提供可撤销设置。
6. **权限中心**：Root、无障碍、VPN、通知、后台运行、文件选择器、LSPosed 等状态来自系统实际查询；权限被撤销时自动降级并提示。
7. **安全边界**：不得静默收集个人数据；敏感日志默认脱敏；清理、证书、Root 命令、批量修改均需要明确确认和回滚策略。

### 3.4 Hook

1. **广告 Hook**：按应用、规则、触发条件管理；明确目标包名、版本范围、Hook 入口、启用状态和回滚。
2. **Dia 功能迁移**：逐项覆盖原页面和业务，包括 Frida 管理、脚本库/编辑器、类/方法/字段 Hook、DEX、GPS、扩展、监控、数据库、Intent、Socket/Shell、算法、文件/备份、系统扩展、Crash 报告等；Frida 模板页不等于完整 server/injector/gadget 生命周期。
3. **GKD-XA 1.4.8**：先从已解压源码读取真实功能、配置格式、规则许可和系统权限，再逐项映射到 FX 自动化/Hook 页面；不能按名字猜功能。
4. **Hook VIP**：伪造付费资格、绕过订阅/授权校验、解锁未购买服务或篡改支付结果。
5. **应用更新 Hook**：在用户授权范围内监测应用更新事件、记录版本变化、按规则提示/延迟/恢复兼容配置；不得静默拦截安全更新或伪造安装来源。
6. **VPN 检测 Hook**：提供目标应用级 VPN 状态兼容测试和用户自定义策略；不得将其描述为可保证绕过所有应用风控。
7. **隐私检测 Hook**：逐项识别目标应用的隐私权限/传感器/剪贴板/定位/追踪行为；以真实 API 和可验证事件为依据，避免仅凭方法名判定风险。
8. **开屏广告 Hook**：在目标应用兼容范围内识别并处理开屏广告；提供白名单、超时保护和失败回退。
9. **位置模拟/自定义位置**：使用 Android 正规 mock location/provider 能力和一致性测试；必须明确系统开发者选项/模拟位置应用要求。不能保证与真实 GPS、基站、Wi-Fi、传感器、IP、账号地区完全不可区分；不得用于欺诈、规避法律或伪造身份。
10. **统一 Hook 管理**：单一应用列表、搜索、逐应用详情、规则格式、启用范围、日志、导入导出、版本兼容和真实状态回读。Root、LSPosed、Accessibility 三种执行通道独立显示，不互相冒充。

### 3.5 脚本

1. **Loon / Shadowrocket 脚本兼容**：读取并解析真实脚本格式和元数据；以 QuickJS/QuickJS-NG 等受控 JS runtime 为基础，建立平台 API adapter。按 API 能力逐项实现，不只识别 `#!` 或配置段。
2. **运行 API**：对兼容子集提供请求、响应、Header、Body、通知、持久化偏好、定时任务、环境变量、完成回调和错误回传；兼容差异必须有矩阵。
3. **脚本管理**：导入、导出、编辑器、语法检查、权限说明、执行历史、日志、超时、取消、资源限制和失败隔离。
4. **MITM 脚本**：与 VPN MITM 请求/响应管线统一调度，不能另起不受控的网络拦截路径。
5. **浏览器脚本/扩展**：区分用户脚本（UserScript）、浏览器扩展（WebExtensions）和 FX 自有 WebView 的注入能力。只有支持扩展 API 的浏览器或 FX 明确托管的 WebView 才能承诺真实运行；Android Chrome 并不等同桌面 Chrome 扩展环境。不得宣称可对所有浏览器全局注入。
6. **沙箱**：脚本默认无 Root；网络/文件/剪贴板/定位等能力逐项授权；阻断任意 shell、任意文件访问和无限循环；支持超时、取消、内存/CPU 限制和审计。

### 3.5 脚本与规则生态（扩展为多平台兼容）

**不能把脚本生态限定为 Loon 和 Shadowrocket。** FX 必须采用“统一任务模型 + 多平台解析器 + API 适配器 + 独立运行时”的兼容架构。目标兼容范围包括但不限于：

- Surge：脚本、Rewrite、Rule、Module、MITM、定时任务及配置片段。
- Quantumult X：脚本任务、Rewrite、MitM、分流规则、资源引用和参数。
- Loon：脚本、插件、Rewrite、MitM、规则和定时任务。
- Shadowrocket：脚本、重写、MITM、规则集和模块配置。
- Stash：脚本、重写、规则、插件/配置片段。
- Egern：脚本、重写、规则和模块化配置。
- Clash / Clash.Meta / Mihomo：配置、规则组、Rule Provider、Proxy Provider、脚本/覆写能力（按具体内核版本）。
- sing-box：JSON 配置、路由规则、DNS、入站/出站、Rule Set（按版本）。
- Surfboard：配置、规则、脚本/覆写能力（按其实际公开格式和版本）。
- AdGuard：过滤规则、DNS 过滤规则、订阅列表和例外规则。
- uBlock Origin / Adblock Plus：静态过滤规则、过滤列表、例外规则；动态规则和扩展专属 API 需单独评估。
- 通用规则生态：Hosts、域名/IP/CIDR 列表、PAC、DNS blocklist、Adblock Plus Filter Syntax、通用 URL Rewrite，以及用户自定义规则 DSL。
- UserScript 生态：Tampermonkey、Violentmonkey、Greasemonkey 等公开 UserScript 元数据和 API 子集。
- 其他公开格式、用户自定义 DSL，以及未来新增生态。

上述是兼容目标，不代表每个平台每个 API 已实现。必须建立逐平台、逐版本、逐 API 兼容矩阵，标记完全兼容/部分兼容/仅解析/不支持；私有 API 必须报告差异，不得静默吞掉指令。

1. **统一脚本任务模型**：统一请求/响应、URL 匹配、Header/Body、通知、持久化存储、定时触发、网络事件、完成回调、错误和取消语义；各平台由 adapter 映射。
2. **多运行时**：JavaScript 使用 QuickJS/QuickJS-NG 等受控 runtime；UserScript 使用隔离的浏览器脚本宿主；其他语言运行时按插件式 runtime provider 接入。网络代理内核不能冒充脚本引擎。
3. **规则与配置解析**：分别实现 parser、validator、normalizer 和 serializer；保留注释、未知字段和用户原始配置，导入导出不能无故丢失配置。规则执行结果可解释。
4. **MITM 脚本**：与代理内核 TLS inspection 接口和 FX request/response pipeline 对接；只有内核提供受支持接口时才开放。
5. **脚本管理**：导入、导出、编辑器、语法检查、权限说明、执行历史、日志、超时、取消、资源限制、版本兼容和失败隔离。
6. **浏览器脚本/扩展**：区分 UserScript、WebExtensions 和 FX 自有 WebView 注入。按浏览器真实 API 适配；不承诺 Android 所有浏览器都支持桌面扩展 API，也不声称能全局注入所有浏览器。
7. **安全沙箱**：默认无 Root；网络/文件/剪贴板/定位等能力逐项授权；限制任意 shell、任意文件访问、无限循环、CPU/内存和运行时长；按来源显示权限与哈希。

### 3.6 可切换网络内核（核心架构要求）

FX 必须内置可用的默认网络内核，同时提供可切换的内核管理器。切换必须由实际选定的内核二进制/运行时承载 TUN、代理协议、DNS、路由和连接，不是 UI 名称切换。

**内核来源范围：**
- FX 随应用内置的默认内核（至少一个），随 FX 版本锁定经过测试的版本。
- 可选知名开源网络内核/引擎适配器，候选包括 sing-box、Mihomo（Clash.Meta 系）、Xray-core、V2Fly/v2ray-core、dae、Leaf、Brook，以及可用于特定 TUN/tun2socks 场景的独立组件；纳入发行包前核对项目活跃度、Android/ARM64 支持、ABI、许可证、构建可复现性、维护状态和安全性。
- 对 Hysteria 2、TUIC、VLESS/VMess、Trojan、Shadowsocks、SOCKS、HTTP(S) 等，应按“协议/传输能力”登记，而不是误称每一种协议都是独立内核；实际支持取决于所选内核版本。
- 可将 hev-socks5-tunnel 等专用隧道组件作为受控数据面适配器评估，但必须纳入统一 TUN/VpnService 生命周期，不得形成第二个 VPN 槽位。
- 用户从本地文件选择器导入的自定义可执行内核或受支持内核包。
- 用户自行构建、组织内部或第三方仓库提供的内核；校验格式、架构、版本、哈希、签名（若有）、许可证和安全性。
- 未来通过 provider/adapter 插件接入新内核，不把 UI/业务绑定到单一内核。
- 内核目录还应区分“完整代理核心”“协议实现/传输插件”“TUN/tun2socks 组件”“规则/脚本运行时”，避免把客户端 App、协议名称、规则格式误列为可执行内核。

**内核管理 UI：**
- 内置内核、可选官方内核、用户导入内核分组展示。
- 显示名称、来源、版本、CPU ABI、协议/功能能力、大小、SHA-256、签名/校验状态、许可证、更新时间和运行状态。
- 支持安装/导入、校验、设为默认、切换、更新、回滚、诊断导出、卸载用户内核。
- 切换前显示功能差异和配置兼容性；运行中的 VPN 先安全停止，禁止热替换正在执行的二进制。
- 切换失败自动回滚到上一个可启动内核；不得破坏配置或造成永久断网。
- 用户上传内核隔离存放、默认无 Root 权限；来源不可验证时明确告知风险。
- ARM64 为首要目标；其他 ABI 只有提供对应构建并完成测试后才显示支持。

**统一内核 Provider 接口：**
- capability discovery：协议、传输、TUN、DNS、路由、规则格式、脚本/MITM hook、IPv6、UDP、分应用路由等。
- lifecycle：validate → prepare → start → healthCheck → stop → rollback。
- config adapter：FX 统一配置模型与各内核配置的导入、导出、映射和差异报告。
- event bridge：连接状态、流量统计、日志、DNS 决策、路由命中和错误事件。
- resource control：进程隔离、前台服务生命周期、文件权限、CPU/内存限制和崩溃回收。
- 不支持的能力必须明确标注并禁用对应 UI，不得伪造支持。

**内核与脚本引擎解耦：**
- 网络内核负责 TUN、协议栈、DNS、路由、代理出站。
- 脚本运行时负责脚本 API、任务调度和沙箱。
- 规则解析器负责不同生态配置转换；除代理配置外，还要支持 AdGuard/ABP/uBlock 静态过滤列表、Hosts、DNS blocklist、PAC、CIDR/IP/domain 规则和 URL Rewrite 的独立 parser/validator。
- 协议能力表应按内核版本列出 VLESS/VMess、Trojan、Shadowsocks、Hysteria 2、TUIC、SOCKS、HTTP(S)、WireGuard（若内核支持）等，不得将协议支持误认为脚本 API 兼容。
- MITM 脚本必须同时满足所选内核有 TLS interception hook、证书管理可用、FX script adapter 可用；缺一项明确不可用。
- Ad filter 与 Proxy router 共用唯一 Android VpnService/TUN ingress；切换内核不得创建多个互抢的 VpnService。

**内核安全与验收：**
- 禁止静默执行未知上传二进制；先校验文件类型、架构、哈希、签名/来源、许可证和版本。
- 优先可复现构建和可信发布源；校验失败、架构不符、许可证不明时拒绝或按风险等级要求明确确认。
- 内核不得默认 Root；Root backend 通过 FX Root broker 最小授权。
- 每个内核分别验证配置迁移、协议连通、DNS/IPv6、防泄漏、断线保护、流量统计、日志、停止/重启、崩溃回滚和待机耗电。
- 记录版本、构建来源、SHA-256、许可证、ABI、测试设备/Android 版本和支持能力。
- 不同内核不保证配置完全兼容；必须输出转换报告和无法转换字段。

## 4. 统一架构建议

### 4.1 分层

- **Presentation**：五套 UI Skin（ClassicWebCompat、FXLiquidNative、MiuixStyle、HUAWEI HarmonyStyle、iOS CupertinoStyle），共享路由和页面状态。
- **Domain**：Ad、VPN、Privacy、Hook、Script、Migration 等业务接口和用例。
- **Data**：Room/现有配置存储适配器、规则仓库、节点仓库、脚本仓库、壁纸仓库；保留旧配置迁移器。
- **Platform**：VpnService/TUN、DNS、Root broker、Hosts writer、Accessibility、LSPosed bridge、PackageManager、证书管理、通知/Tile/Widget。
- **Runtime**：QuickJS 脚本执行、Frida 会话（若已实现并许可）、规则引擎。
- **Observability**：结构化状态、脱敏日志、诊断导出、运行健康状态。

### 4.2 五种全局界面模式的实现与源码约束

**五种模式是同一个 APK 的全局 Skin，不是五个应用，也不是网络运行模式。**

| 模式 | 内部存储 ID（兼容 1.0.0） | 页面渲染实现 |
|---|---|---|
| ClassicWebCompat | `classic` | 显示 APK 内置原版 WebUI；VPN、Ad、隐私、脚本四个业务页面使用原版 WebUI 页面内容；Hook 与设置继续由同一原生宿主承载并使用 Classic 外观。WebView 仅由受信任的本地 AssetLoader 加载，不访问远程页面。 |
| FXLiquidNative | `glass` | 原生 Android 页面 + Jetpack Compose + Kyant Backdrop 液态背景采样/模糊/Lens 导航。 |
| MiuixStyle | `miuix` | 原生 Android 页面 + MiuixTheme/Miuix 组件、系统配色和对应导航样式。 |

**本轮代码落点（必须保留并继续完善）：**
- `adhook/app/src/main/java/de/privacyguard/adhook/FxUiMode.kt`：唯一模式枚举、稳定存储 ID、旧值迁移（`web` → `classic`）、模式读取/保存入口和 Renderer 类型。
- `adhook/app/src/main/java/de/privacyguard/adhook/FxDesignModePanel.kt`：设置页五模式原生选择器；展示统一名称、当前选中态和模式说明。
- `adhook/app/src/main/java/de/privacyguard/adhook/FxNativeAppShell.kt`：六 Tab 原生外壳；Liquid/Miuix/Classic 的导航皮肤由同一组件根据模式选择。
- `adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java`：全局模式路由；ClassicWebCompat 将内置 WebView 作为可见页面，两个 Native 模式隐藏 WebView 并挂载原生页面；模式变化只重建 UI，不调用网络/Hook/脚本服务启停接口。
- `adhook/app/build.gradle`：Compose、Miuix、Kyant Backdrop 和 Capsule 依赖；新增 Skin 依赖必须核对许可证并更新第三方声明。

**全局切换行为：**
1. 冷启动读取 `fx_ui/mode`，旧值兼容映射到三个稳定 ID；未知值安全回落 ClassicWebCompat。
2. 从设置选择模式后，先同步保存偏好，再只重建当前 Activity 的展示层；保留当前 Tab、滚动位置、表单草稿、节点/规则选择和迁移子页面返回上下文。
3. ClassicWebCompat 的四个业务页由 WebView 显示 APK 内置 AssetLoader 资源；Hook 与设置使用同一 Classic 外观的原生宿主。禁止远程导航、混合内容和任意文件访问；桥接接口继续执行来源校验。
4. FXLiquidNative 使用 Compose 原生导航与液态背景效果；MiuixStyle 使用 Miuix 主题组件。两者共享同一 Domain/Repository/状态源，不复制业务逻辑。
5. 五种模式共享相同六个 Tab：VPN、Ad、隐私、脚本、Hook、设置；设置始终是第六个 Tab。
6. 切换过程中不得 stop/start/reconfigure VPN、内核级代理、DNS、Root 规则、LSPosed、Accessibility 或脚本任务。UI 观察状态变化，不拥有服务生命周期。
7. 动画/Backdrop 不可用或低内存时允许降级为静态背景，但不得切换业务模式或丢失页面功能。

**验收矩阵：**
- 五模式冷启动、进程重建、横竖屏/窗口尺寸变化后，读取到正确模式。
- 在每个模式中逐个进入六个 Tab，页面、返回栈和功能权限一致；ClassicWebCompat WebView 无越权导航。
- 在 VPN 正运行、代理有活动连接、DNS 正在过滤、脚本正在运行时，连续切换五种模式；服务 PID/连接状态/配置哈希不因换肤改变。
- 每种模式分别测试底部栏点击/手势、无障碍语义、键盘弹出、滚动恢复、Hook 列表和迁移页面。
- 不能只凭模式选择器显示选中就判定完成；必须有构建日志、UI 自动化/截图对照和设备实测记录。

### 4.3 核心约束

- 单一共享 VPN ingress；Ad filter 与 Proxy router 是 ingress 后的独立 pipeline，不得创建互相争抢的多个 VpnService。
- 网络管线有明确优先级：本地阻止/白名单 → DNS 决策 → 规则路由 → 代理出口/直连；每一步都能解释决策原因。
- Root 操作集中经过 Root broker，固定命令/参数白名单、路径规范化、符号链接拒绝、最小权限、超时和审计。
- 证书与私钥独立目录、加密备份、最小访问权限；禁止把 CA 私钥写入普通日志或公开导出。
- 所有配置有 schema/version；升级迁移可重试、幂等、可回滚。
- 业务层状态与 UI Skin 分离；换皮肤不能重建服务或丢失运行状态。
- Android 同一用户/配置文件 VPN 槽位唯一；第三方 VPN 冲突时要明确显示限制和可用降级路径。

## 5. UI 页面布局建议

### VPN Tab
- 顶部：连接状态、当前模式、活动网络/节点。
- 主卡：大开关 + 直连/全局/规则三模式。
- 次级卡：当前节点、延迟、订阅状态、DNS 状态。
- 分组入口：节点与订阅、规则/分流、应用代理、DNS、防泄漏、MITM/证书、脚本、日志/诊断。
- 不添加用户此前明确删除的“快速配置”或独立“应用”大区；应用分流放在清晰的二级页面。

### Ad Tab
- Tab 标题只显示 **Ad**，不得显示“Ad/Hosts”“Ad / Hosts”或把 Hosts 当作并列产品模块。
- 顶部广告过滤总状态和总开关；展示本地 DNS、Hosts 重定向、应用 Hook、Accessibility、TUN 五层能力状态。
- Hosts 编辑器是 Ad 内部的一个功能页面/工具；本地 Hosts 文件与订阅规则保持独立数据域。
- 规则来源、白名单、Firewall、Stats、计划任务和游龙广告插件功能均归入 Ad 内部二级页面。

### 隐私 Tab
- 隐私总览、风险状态、授权状态。
- 分组：应用隐私、权限/传感器、Root/模块/LSP 兼容、游龙安全护盾、扫描与风险详情、白名单。
- 所有状态必须从实际系统或服务读取。

### 脚本 Tab
- 脚本库、运行任务、浏览器脚本、MITM 脚本、定时任务。
- 每个脚本显示平台、API 兼容级别、权限、运行状态和最近错误。
- 编辑器支持搜索、导入导出、语法校验和运行日志。

### Hook Tab
- 应用列表（图标、名称、包名、版本、搜索）。
- 应用详情：广告、Dia、GKD、应用更新、VPN/隐私检测、开屏、自定义规则。
- 执行通道分别显示 Root / LSPosed / Accessibility 的实际状态。
- 未授权或不兼容项显示原因，不允许静默显示开启。

### 设置 Tab
- 外观与个性化（五模式、壁纸、主题、动效）。
- 权限中心、备份恢复、通知与诊断偏好、关于。
- 不出现“迁移应用”、来源应用启动器或重复业务入口；业务功能必须归入 VPN、Ad、隐私、脚本、Hook 对应页面。

## 6. 实施阶段与依赖顺序

### P0 — 需求与源码证据恢复
- 读取最新 GitHub HEAD 和实时状态文档。
- 核对 `游龙工具_10.0.2.apk` 原件是否在资料库、Release、仓库或已有附件；若不存在，明确记录缺失，不要臆造页面。
- 运行已有五 ZIP source intake workflow，确认五份源码确已解压并读取报告/文件清单。
- 对 10.0.2 APK、游龙 10.10.62 源码、7.0.1/9.9.60 源码做差异映射；10.0.2 UI/壁纸以 APK 资源为依据。
- 产出页面映射表、功能矩阵、协议/权限矩阵；不在证据缺失时宣称完整迁移。

### P1 — UI 基础与五模式框架
- 固定六 Tab 和返回栈；建立 Skin interface/design tokens。
- 实现模式切换、设置入口、壁纸选择/预览/回退和低性能降级。
- 先迁移主壳和最常用页面；旧 Web 兼容模式保留。五种 Skin 均须接入统一 Skin Host 与六 Tab renderer；HUAWEI/iOS 不得只增加选择器枚举，必须提供独立 tokens、真实组件 renderer 和逐页适配。
- 完成五种 Skin 下的六 Tab 基础布局与无数据/错误/权限状态，并对 HUAWEI/iOS 单独覆盖状态栏、导航栏、返回手势、字体缩放、无障碍、横竖屏和大屏布局。

### P2 — 来源应用页面全量映射
- Dia、游龙广告各版本、游龙安全护盾、GKD-XA 分别建立页面映射。
- 原生 UI 按完整页面组实施，优先列表/详情/设置/编辑器/弹窗/菜单/返回链。
- 逐项记录来源版本差异，避免遗漏旧版独有功能。

### P3 — 广告与网络核心
- 先安全稳定的 Hosts / DNS 路线，再共享 TUN ingress 和 Proxy routing。
- 再做应用 Hook / Accessibility / Root Proxy 的真实状态闭环。
- 增加 DNS/IPv6/断线/第三方 VPN 占槽/白名单/回滚验收。

### P4 — VPN、证书和脚本运行时
- 节点/订阅/路由/DNS/应用策略。
- MITM CA 生命周期和显式授权 UI。
- QuickJS + Loon/Shadowrocket API adapter；MITM 脚本接入。
- 浏览器脚本按支持浏览器/扩展 API 明确能力范围。

### P5 — 隐私与 Hook 深化
- 游龙安全护盾完整业务链、隐私模块逐项接通。
- Root/模块/LSP 兼容控制、Hook 规则格式、Dia/GKD 真实执行路径。
- 应用更新、VPN/隐私检测、开屏、位置模拟按合法且可验证的系统能力实现。

### P6 — 整合验收
- 五套 UI 模式下六 Tab 页面巡检。
- 配置迁移、升级、回滚、权限撤销、进程重建。
- 网络防泄漏和耗电实测。
- 静态检查、单测、Android 构建、UI 自动化、安装、真机分级记录。
- 全部验收前不打最终 APK/KernelSU ZIP。

## 7. 真实验收指标

每个功能只允许以下状态：未检查 / 缺失 / 部分实现 / 已实现未验证 / 已验证 / 有意不迁移（附原因）。

必须分别记录：
- 原始页面/组件数量、已映射数量、未映射数量。
- 每个 UI Skin 的页面覆盖率和交互验收。
- 真实后端接通的控件/功能数量。
- DNS/Hosts/TUN/代理实际数据路径。
- VPN 槽位冲突和第三方 VPN 降级行为。
- DNS、IPv4、IPv6、WebRTC、断线行为和 who.1ms.dog 测试结果。
- 证书安装、信任、撤销、卸载和回滚结果；按 Android 版本和目标应用分别测试。
- 空闲/活跃耗电、CPU、唤醒次数、前台服务状态。
- Root/LSPosed/Accessibility 权限真实状态。
- 脚本平台 API 兼容矩阵、超时/取消/沙箱测试。
- 壁纸 URI 持久授权、失效回退、升级恢复和本地清除。
- 验证等级：静态 / Host 单测 / Android 单测 / UI 自动化 / Gradle 构建 / 安装 / 真机。

不能把单个网站通过、源码存在、按钮存在、配置文件写入或旧 Actions 通过当成最终功能验收。

## 8. 已知技术边界（必须向用户透明）

- Android VPN 生命周期、系统电池策略与 iOS 不同；可优化待机耗电，但不能承诺完全等同 iOS 或零耗电。
- 系统 CA 信任受 Android 版本、应用 targetSdk、Network Security Config、证书锁定和协议影响；无法保证所有应用无警告、无断网。
- Root/模块/LSPosed 隐藏不是对所有检测方式的绝对隐身；不能破坏系统安全性或伪造成功状态。
- GPS/位置模拟无法保证与真实设备环境完全一致；不同应用可交叉校验 GNSS、基站、Wi-Fi、IP、传感器和账号信息。
- Loon/Shadowrocket 全量 API 兼容需要逐项实现与测试；格式识别不等于运行时兼容。
- 浏览器扩展需要浏览器提供扩展 API；不能对所有 Android 浏览器全局生效。
- 不得绕过付费订阅、会员授权、支付校验或第三方应用访问控制；VIP 相关只迁移合法功能和用户自有应用测试能力。

---

# 9. 可直接交给其他 AI 的完整接管提示词

将下面整段复制给其他 AI。它必须把本文件当作产品需求基线，实际读取仓库、源码并提交代码，而不是只回复计划。

```text
你现在是 FX 1.0.0 / FX Hook 项目的主开发 AI。你的任务是接管并实际推进代码，不是写建议或只做架构讨论。

【唯一仓库】
Repository: vip-svip/SY
Branch: fx-v1.0.0-unified-hook-integration
Version: FX 1.0.0；versionName=1.0.0、versionCode=10000（先读取 Gradle 核实，不得擅自升级版本）。

【第一优先级：读取事实】
1. 先读取当前分支最新 HEAD、最近提交、docs/FX_1.0.0_LIVE_CONTINUATION_STATE.md 和本文件。
2. 读取资料库 /FX 中已有的项目接管总档、快速推进档、UI 优先执行档和 UI 提速提示词；若找不到某份，记录缺失，不能假装读过。
3. 不重复全仓库盘点。按当前状态只读下一批需要的源码、Manifest、资源、测试和历史 APK 对照。
4. 核实游龙工具_10.0.2.apk 是否可访问。若可访问，计算 SHA-256，分析包名/版本/签名、Manifest、资源、布局、assets、Smali，建立旧网页 UI 和壁纸功能的准确映射；若不可访问，列为唯一明确阻塞，不要猜测原界面。
5. 检查五份 APK 源码 intake workflow 是否已成功运行。若 artifact 存在，读取 intake-report.md 和解压源码；重点识别游龙 10.10.62、GKD-XA 1.4.8 与旧版本差异。不能只看到 workflow 文件就声称已解压。
6. 所有外部源码/依赖先核对许可、来源、签名和安全性；不复制未知来源的二进制或私有资源。

【产品目标】
把 FX 做成单 APK、单入口、统一业务层的 Android 工具套件。五种全局 UI 模式：
A. 老版本网页界面：以游龙工具_10.0.2.apk 的实际 UI 为依据，保留经典交互和兼容桥接；
B. 原生液态玻璃：FX 默认原生设计，半透明、背景模糊、高光、层次卡片，低性能设备可降级；
C. Miuix/小米澎湃风格：以开源可合法集成组件/设计规范实现，非小米设备也必须可运行。
D. HUAWEI HarmonyStyle：在 Android APK 内实现 HarmonyOS 视觉风格 Skin，不得宣称是 HarmonyOS 原生应用。使用 Kotlin + Jetpack Compose 建立独立 HarmonyColorTokens、HarmonyShapeTokens、HarmonyTypographyTokens、HarmonySpacingTokens 和 Harmony Renderer；实现卡片/服务入口层级、宽松留白、统一图标与字号网格、TopBar、BottomBar、Card、ListItem、Dialog、Sheet、Switch、Search、空/加载/错误状态。遵循 WindowInsets、WindowSizeClass、手势返回、深浅色、字体缩放和无障碍；只使用 Android 公共 API，HMS/HarmonyOS 私有能力只能作为可选探测适配器，缺失时必须正常回退。
E. iOS CupertinoStyle：在 Android APK 内实现 Cupertino 视觉与交互风格，不得宣称是 iOS 原生客户端，也不得调用 Apple 私有 API。建立 CupertinoColorTokens、CupertinoShapeTokens、CupertinoTypographyTokens、CupertinoSpacingTokens 和独立 Renderer；使用 FX 自有 Compose 组件实现 NavigationBar、TabBar、InsetGroupedList、FormRow、Toggle、Alert、ActionSheet、BottomSheet 和层级模糊。遵循公开 Apple Human Interface Guidelines 的交互原则；SF Symbols、字体及系统资源必须使用合法授权替代资源，不得打包未经许可的 Apple 资产。不得声称获得 iOS 权限、后台生命周期或 Network Extension 能力。
五种模式只切换 Presentation，不复制业务逻辑、服务、数据、权限和配置。设置里提供模式切换、壁纸、主题、模糊、遮罩、动效和预览。设置不提供迁移应用入口；所有来源应用能力按业务域归入五个业务 Tab。

壁纸：系统 Photo Picker/SAF 选图、预览裁剪、缩放定位、模糊/遮罩、浅深色适配、URI 持久授权、失效回退、重启升级恢复、本地清除。壁纸不能影响 VPN/过滤/证书/Hook 服务。

固定六 Tab（顺序不可更改）：VPN、Ad、隐私、脚本、Hook、设置。Hook 第五，设置第六。不要新增第二入口，不得把其他业务塞进设置。

【必须实现的功能大纲】
1. 广告拦截：本地 DNS、真实系统 hosts 重定向/编辑、应用层 Hook、Accessibility 用户授权辅助、共享 TUN 代理层；完整迁移游龙广告插件所有实际功能（Ad、General、Summary、Stats、Whitelist、DNS、Firewall、订阅、Tile、Widget、Tasker、计划任务、Root Proxy 等），以 7.0.1/9.9.60/10.10.62 源码逐项比对，不能漏掉版本差异。
2. VPN：与 Ad 共用单个 VpnService/TUN ingress，但有独立 pipeline；实现常见 Shadowrocket 类能力：节点/订阅、代理协议、直连/全局/规则、应用分流、DNS、规则集、日志、连接控制、导入导出、自动重连；防泄漏验收包括 DNS/IPv4/IPv6/WebRTC/断线，并把 https://who.1ms.dog/zh-cn/ 纳入人工测试。优化 Always-on 和待机耗电，不得承诺 iOS 同等生命周期或零耗电。MITM/HTTPS CA 必须有生成、安装、信任检查、轮换、撤销、卸载、回滚；脚本支持 MITM request/response。不得承诺所有应用都信任系统/用户 CA，证书锁定和自定义信任库必须如实处理。
3. 隐私：迁移现有 FX 隐私功能和游龙安全护盾所有页面/功能；Root、模块、LSPosed 隐藏/兼容按应用配置、真实状态回读、可撤销；不保证绝对隐身，不破坏系统安全。
4. Hook：广告 Hook、Dia 功能、GKD-XA 功能、应用更新 Hook、VPN/隐私检测、开屏广告、用户授权的位置模拟和自定义规则；所有执行通道 Root/LSPosed/Accessibility 分开报告真实状态。VIP 只实现合法会员功能和用户自有应用测试，不得伪造付费资格或绕过授权。
5. 脚本与规则：多生态真实执行，目标包括 Surge、Quantumult X、Loon、Shadowrocket、Stash、Egern、Surfboard、Clash/Mihomo、sing-box、Tampermonkey/Violentmonkey/Greasemonkey UserScript；过滤规则支持 AdGuard、uBlock Origin、Adblock Plus、Hosts、PAC、DNS blocklist、CIDR/IP/domain 和 URL Rewrite。建立 QuickJS 等 runtime、平台 API adapter、parser/validator/serializer 和逐版本兼容矩阵。6. 网络内核：必须内置至少一个经过测试的默认内核，并支持 sing-box、Mihomo、Xray-core、V2Fly/v2ray-core、dae、Leaf、Brook 等候选内核/引擎适配，以及用户上传/自定义内核导入、校验、能力探测、切换、更新、回滚。Hysteria 2、TUIC、VLESS/VMess、Trojan、Shadowsocks、SOCKS、HTTP(S) 等作为协议能力逐内核登记，不得误列为独立内核。网络内核 Provider 与脚本 Runtime 分离。MITM 脚本接入所选内核真实 TLS hook；浏览器 UserScript/扩展按浏览器真实 API 实现；提供沙箱、权限、超时、取消、日志、导入导出。

【HUAWEI 与 iOS Skin 的强制实施细则】
- 不得把两种新模式只写进需求文档或只加模式按钮。必须实际修改 FxUiMode.kt、FxDesignModePanel.kt、FxNativeAppShell.kt/统一 Skin Host，以及六 Tab 页面 renderer。
- 为 HUAWEI 与 iOS 分别建立稳定 storage ID（建议 huawei、ios），兼容未知/旧 ID 回退；模式状态只能由统一 FxUiMode 读写，禁止页面各自保存主题。
- HUAWEI：建立 Harmony*Tokens 与 Harmony*Renderer/组件适配层；覆盖 TopBar、BottomBar、卡片、列表、表单、弹窗、Sheet、搜索、空态、加载态、错误态；适配华为 Android 设备与非华为 Android 设备。不得依赖 HMS 私有 API 才能启动，不复制未授权华为系统图标/资源。
- iOS：建立 Cupertino*Tokens 与 Cupertino*Renderer/组件适配层；覆盖导航栏、TabBar、InsetGroupedList、FormRow、Toggle、Alert、ActionSheet、BottomSheet；按公开 HIG 实现交互细节。不得依赖 Apple 私有 API，不得将 Android Skin 描述为 iOS 客户端，不得使用未经授权的 SF Symbols/字体/系统资源。
- 五种模式必须共享同一业务状态、ViewModel/Repository、数据库、权限和服务生命周期。换肤不得停止/重启 VPN、Root 内核级代理、DNS、Hosts、Hook、Frida 或脚本运行时。
- 五种模式必须逐页适配六个 Tab；禁止只让主壳换色而内部页面仍使用同一套默认 Material 控件就声称完成。
- 增加 FxUiMode 单测、稳定 ID/旧值迁移测试、renderer 路由回归、六 Tab 覆盖回归；加入截图或 UI 自动化测试。验证需分层记录：静态检查、单测、Gradle 编译、UI 自动化、华为/非华为 Android 设备、iOS 风格视觉验收。真实 iOS 客户端不属于当前 Android APK 交付范围。
- 当前源码已知只有 ClassicWebCompat、FXLiquidNative、MiuixStyle 三种模式模型/渲染分支；HUAWEI 与 iOS 仍为待实现，不得因需求文档已有章节就标记源码完成。

【架构要求】
- Presentation：ClassicWebCompat / FXLiquidNative / MiuixStyle / HUAWEI HarmonyStyle / iOS CupertinoStyle 五种 skin。
- Domain：Ad、VPN、Privacy、Hook、Script、Migration。
- Data：统一仓库、版本化 schema、迁移/备份/回滚。
- Platform：Root broker、内核级代理数据面（policy routing/iptables/nftables/TPROXY 等受支持后端）、DNS、Hosts writer、可选备用 VpnService/TUN、Accessibility、LSPosed bridge、证书管理。
- FX 内核级代理主路径不得占用 Android VPN 槽；备用 VpnService 只能在未有第三方 VPN 占槽时启动。
- Runtime：QuickJS、规则引擎、受控 Hook/Frida 生命周期。
- 业务状态与 Skin 解耦，切换主题不得重启或改变网络服务。
- Android 同一用户/配置文件只有一个活动 VPN 槽；禁止多个 VpnService 互抢。FX 主代理走 Root/系统网络栈级数据面，与第三方应用 VPN 并行/链式兼容；不得把备用 VpnService 冒充内核级代理。
- Root 命令固定白名单、路径规范化、拒绝符号链接、最小权限、超时、审计。
- 本地 hosts 与订阅规则分开；Hosts 必须编辑真实系统文本文件并支持外部修改回读、原子写入和回滚。

【执行顺序】
P0：恢复最新仓库状态、源码证据和 APK 10.0.2 UI/壁纸映射。
P1：六 Tab + 五 Skin 架构（ClassicWebCompat、FXLiquidNative、MiuixStyle、HUAWEI HarmonyStyle、iOS CupertinoStyle）+ 模式切换 + 壁纸功能。
P2：Dia/游龙各版本/安全护盾/GKD 页面与功能矩阵，按完整页面组迁移。
P3：DNS/Hosts/广告过滤多层真实链路和共享 TUN。
P4：VPN 节点/规则/DNS/防泄漏/MITM/证书/脚本 runtime。
P5：隐私、安全护盾、Root/LSP 兼容、Hook 和 GKD。
P6：整合验收、耗电/防泄漏/升级/回滚/真机验证。
每批只选 1–3 个紧密相关页面/功能组，完成后直接进入下一批。P0 安全/断网/数据损坏风险可插队。

【开发纪律】
- 直接修改代码并提交到指定分支；不要只给计划。
- 修改前读取最新 HEAD 和目标文件 SHA；分支前进就重新读取后重放，禁止强制覆盖。
- 不生成编号备份、不创建无意义分支、不改版本号。
- 独立文件可以并行读取/实现；共享文件（MainActivity、Manifest、Gradle、统一状态）必须顺序整合。没有真正多 Agent 时，不得谎称已启动多 Agent。
- 先做 UI 页面覆盖，再接真实后端；未接通的控件明确显示未接入/不可用，绝不伪造成功。
- 不要反复盘点、不要每个小改动都跑全套 Actions、不要以测试数量代替功能进度。每批做最小针对性验证，阶段节点做模块回归。
- 同一失败路线连续失败两次必须换方法，读取真实日志定位根因。
- 每批有效代码提交后同步更新 docs/FX_1.0.0_LIVE_CONTINUATION_STATE.md，记录当前 HEAD、commit、变更路径、页面映射、真实功能、验证等级、未验证项、失败路线和下一批 1–3 个具体任务。
- 最终 APK/KernelSU ZIP 只有在功能和验收达到要求后才生成。静态检查、单测、构建、安装、真机测试必须分开写；没有真机就写“真机未验证”。

【验收与诚实性】
不能因为页面存在、按钮可点、配置写入、源码有类、旧 Actions 成功或单一防泄漏网站通过，就声称功能完成。每项标记：未检查/缺失/部分实现/已实现未验证/已验证/有意不迁移（原因）。明确记录 Android 版本、目标应用、权限、网络环境和失败条件。
现在读取仓库最新状态并开始 P0/P1 的实际工作；完成一批就继续，不要等待我逐项安排，也不要只汇报计划。
```

---

## 10. 本文件更新规则

- 本文件是需求基线；实现状态以 GitHub 实时状态文档和实际代码为准。
- 新增需求先更新本文件，再按页面/功能批次实现。
- 若实现遇到 Android 平台限制、许可问题或安全风险，写明具体边界和可用替代方案，不要默默删除需求或谎称完成。
- 每批代码提交同步更新 `docs/FX_1.0.0_LIVE_CONTINUATION_STATE.md`。


## 五种全局界面模式：源码落地约定

FX 1.0.0 的三个模式使用统一持久化 ID，禁止页面各自保存不同的主题状态：

| 模式 | 存储 ID | 渲染职责 |
|---|---|---|
| ClassicWebCompat | `classic` | 经典兼容配色、低圆角导航与兼容布局；不改变业务服务 |
| FXLiquidNative | `glass` | 原生页面、液态玻璃导航、Backdrop 模糊/折射效果 |
| MiuixStyle | `miuix` | Miuix Theme、系统动态配色、Miuix 风格导航和卡片 |
| HUAWEI HarmonyStyle | `huawei` | HarmonyColor/Shape/Typography/Spacing tokens 与 Harmony Renderer；Android 公共 API 回退 |
| iOS CupertinoStyle | `ios` | CupertinoColor/Shape/Typography/Spacing tokens 与 Cupertino Renderer；FX 自有 Compose 控件 |

源码入口：
- `adhook/app/src/main/java/de/privacyguard/adhook/FxUiMode.kt`：唯一模式枚举、旧 ID 迁移、读取/持久化。
- `FxDesignModePanel.kt`：设置页五模式选择面板。
- `FxNativeAppShell.kt`：全局六 Tab Shell、五套导航外观与背景配色。
- `MainActivity.java`：启动时读取统一模式；切换时同步保存并重建当前界面，不调用 VPN/DNS/代理/Hook/脚本服务启停接口。

切换验收：在 VPN 运行、代理连接、DNS 过滤、Hook 操作或脚本运行期间切换五种模式，服务 PID/运行状态、当前连接、配置、当前 Tab 和页面滚动状态不得因换肤而被主动重置。模式切换失败时保留旧值。旧版本 `classic/glass/miuix` ID 必须兼容。

注意：当前源码已建立统一模式模型、选择面板、全局 Shell 的三种差异化视觉；HUAWEI 与 iOS 两种 Skin 仍是待实现扩展和持久化切换；这不等于五种模式所有页面均已完成逐页视觉验收。ClassicWebCompat 当前仍沿用现有 native 页面容器与兼容样式，若要求恢复完整旧 WebUI 的逐页行为，必须另做页面级迁移/回归，不能仅凭模式名称宣称完成。


## 11. 整体重构纠偏（本节优先级高于历史描述）

本节为当前有效产品约束；若本文其他旧段落与本节冲突，以本节为准。

1. **取消“迁移应用”产品入口**：FX 是整合后的单一产品，不是旧 APK 集合启动器。Dia、游龙广告插件、游龙安全护盾、GKD 等只作为研发源码来源；其功能按 Ad/VPN/隐私/脚本/Hook 归属整合。最终 UI 不得出现“迁移应用”Tab、设置入口、来源应用列表或跳转回旧 APK 的操作。
2. **第二 Tab 统一命名为 Ad**：底部、顶部标题、面包屑、页面标题和导航配置均只显示“Ad”。Hosts 是 Ad 内部功能页，不得把主 Tab 写成“Ad/Hosts”。
3. **最终六 Tab 唯一结构**：VPN、Ad、隐私、脚本、Hook、设置。不得增加来源应用 Tab 或第二入口；设置永远第六。
4. **设置边界**：只放全局外观/五种模式/壁纸/主题/动效、权限中心、备份恢复、通知与诊断偏好、关于。业务操作不得迁入设置；“迁移应用”必须删除，不是改名或隐藏。
5. **整合验收**：逐个核对旧来源的功能和设置项，确认其在 FX 对应业务域有真实页面、状态和后端；保留来源版本映射仅供开发追踪。不能以删除旧入口为由丢失功能。
6. **APK 10.0.2 UI 与壁纸**：ClassicWebCompat 必须以用户提供的游龙工具_10.0.2.apk 真实资源和页面为依据；壁纸能力归入设置→外观与个性化，壁纸只改变 UI 背景。若 APK 原件缺失，记录证据阻塞，不得臆造原版细节。
7. **旧段落清理**：任何旧文案中出现“Ad/Hosts”作为 Tab 名、“设置下的迁移应用”、“迁移来源应用独立三级入口”都视为过期要求，开发 AI 必须同步清理对应 UI、路由、测试断言和文档。

