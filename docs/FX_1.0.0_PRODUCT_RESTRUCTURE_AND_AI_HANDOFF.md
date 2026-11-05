# FX 1.0.0 / FX Hook — 产品重构总方案与跨 AI 接管提示词

> 状态：需求基线 / 架构与 UI 重构方案（不是已实现声明）
> 仓库：`vip-svip/SY`
> 分支：`fx-v1.0.0-unified-hook-integration`
> 产品版本固定：FX 1.0.0（versionName=1.0.0、versionCode=10000；修改前必须核实）
> 本文件用途：让新的 AI 在不依赖当前聊天上下文的情况下，理解产品目标、边界、页面结构、技术路线、验收标准，并直接接管实施。
> 当前唯一可直接复制的跨 AI 总接管提示词：docs/FX_1.0.0_AUTONOMOUS_CROSS_AI_HANDOFF_PROMPT.md。新接手 AI 必须先读取该文件；若本文历史段落与该提示词或实时状态文件冲突，以提示词中的 UI/功能边界和实时状态事实为准。
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
   - 对游龙广告插件自身已确认的 7.0.1、9.9.60 等版本差异做版本映射；**小火箭_10.10.62_src 不属于游龙广告插件版本，严禁归入游龙广告版本矩阵**。
   - 每个功能记录：原始类/页面、数据格式、权限、FX 对应页面、后端、验证状态。

### 五份指定源码的来源归属（强制约束）

以下五项是用户指定的独立源码来源，功能审计与迁移必须分别建账，不得混淆：

| 用户指定来源 | FX 归属 | 来源使用原则 |
|---|---|---|
| 游龙广告插件 | Ad | 完整审计广告过滤、DNS、Hosts/重定向、防火墙、白名单、统计、订阅、计划任务及原有设置/自动化能力 |
| 游龙安全插件（游龙安全护盾） | 隐私 | 完整审计安全总览、扫描、病毒库/特征库、风险处置、屏幕过滤、完整性、救援、白名单等能力 |
| Dia | Hook / 脚本 | 完整审计其工具、Frida 环境与生命周期、脚本、DEX/方法、监控和扩展能力 |
| GKD | Hook | 完整审计规则/selector、订阅、无障碍执行、快照、日志、配置与数据层 |
| **小火箭_10.10.62_src** | **VPN** | **VPN 的第一手源码依据；逐文件、逐模块审计其代理内核、协议、节点/订阅、规则路由、DNS、MITM、脚本、配置、UI 与生命周期，再建立 FX 对应实现和验收矩阵** |

特别约束：
- 小火箭_10.10.62_src 明确归属 VPN，不能误标为游龙广告插件版本，也不能仅作为“功能参考”或以相似 UI/基础代理替代源码级审计。
- VPN 必须以该源码实际包含的功能、接口、协议和数据结构建立迁移清单；对无法直接复用的部分，记录原因、替代实现、兼容差异和测试证据。
- 五份源码均须记录仓库/Release 来源、压缩包文件名、SHA-256、解压目录、源码版本/提交、许可证、模块清单、功能矩阵和审计状态。未实际下载、解压和读取的项目标记“待审计”，不得声称已完整覆盖。
- “方案列出功能”不等于“源码已审计”；“源码已审计”不等于“功能已迁移”；“功能已迁移”不等于“构建/真机验收通过”。

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


### 3.3.1 Magisk / KernelSU 隐私控制中心：完整开关目录与实现方案

**定位：** 本节是 FX 隐私 Tab 的产品需求与技术方案，不代表功能已经开发或已在设备上可用。目标是统一规划 Magisk 模块、KernelSU 模块/内核能力、Zygisk、LSPosed/Framework Hook、Android 公共 API、AppOps、SELinux、iptables/nftables/netfilter 等控制路径。每项功能均需独立配置、显示作用范围、验证真实生效状态，并支持关闭、恢复和故障回退。

**统一开关模型：**
- 每项包含稳定 ID、名称、分类、全局/单应用范围、执行后端、框架依赖、权限、Android/ROM/内核适配范围、风险等级、默认值、配置值、实际生效值、最近验证时间、失败原因和恢复动作。
- 配置状态与运行状态分离：关闭、已配置待生效、生效中、已生效、部分生效、不支持、权限不足、冲突、失败、待重启。不得仅凭配置文件存在就显示已生效。
- 支持全局策略、单应用覆盖、白名单/例外、模板、导入导出、变更预览、批量启停和恢复默认；高风险操作逐项确认。
- 显示实际后端：Android API、AppOps、Magisk service/overlay、Zygisk、LSPosed、KSU 用户态模块、内核模块、sysfs、netfilter 等。不能静默切换后端。
- 配置采用版本化 schema 和原子写入；启动时检查依赖、权限、模块来源/签名和配置完整性。失败保留上一个可用配置；关闭或卸载时恢复 FX 管理的变更。
- Magisk 不等于应用进程注入或内核任意 Hook；KernelSU 不代表任意设备都具有内核补丁、KPM、sysfs 或 netfilter 扩展；Zygisk 是 Magisk 注入路径，KernelSU 设备必须独立探测可选注入框架；LSPosed 必须分别验证安装、scope、进程加载和 Hook 实际触发。

#### A. 设备信息、标识符与设备指纹
1. 型号、device、品牌、产品名、厂商属性：先提供属性来源、分区和覆盖状态审计；属性覆盖仅限合法测试镜像和明确授权测试设备，不承诺全局/单应用伪装。
2. Android 版本、SDK、Build fingerprint、硬件名、CPU/主板信息：显示系统 API 与属性值差异；不得伪造系统版本、系统签名或设备完整性结论。
3. Android ID：展示作用域和应用可见性，提供官方数据重置说明；自有测试应用可验证测试标识，不冒充其他设备。
4. 序列号、基带版本/编号、IMEI1/2、MEID、SIM 序列号、IMSI：只做权限、API 可见性和访问审计；不提供真机身份修改或向第三方应用返回虚假电信身份。
5. Wi-Fi/蓝牙 MAC：展示 Android/ROM 随机 MAC 配置和附近设备权限；使用系统正式随机化机制，不伪造硬件地址。
6. 存储总量/可用量、屏幕分辨率/DPI、电池容量/健康/充电状态：显示应用可见 API 与真实设备值；只允许 FX 自有测试应用使用模拟数据，不向第三方服务伪造硬件能力或电池安全状态。
7. 全局/单应用信息隔离：展示每个应用可访问字段、权限和真实后端；全局属性覆盖不得冒充单应用隔离。

#### B. 位置与无线环境
1. 全局定位状态与快捷入口：读取 Android/ROM 定位总开关和应用授权状态，跳转系统设置。
2. 单应用精确/模糊位置、后台定位：使用 Android 运行时权限、AppOps 和系统设置能力，撤销后回读验证。
3. Mock Location：通过 Android 开发者选项/Mock Location Provider，仅用于 FX 自有或授权测试应用；界面始终标记模拟状态。
4. GPS 精度、被动定位、网络定位、AGPS：做公开 API、权限和数据流审计；不可观测时明确标记，不承诺全 ROM 通用拦截。
5. GNSS 卫星数量/SNR：仅对自有测试程序展示真实测量数据，不伪造卫星环境。
6. Wi-Fi 扫描列表：管理附近设备/Wi-Fi/定位权限，显示扫描访问审计；不能承诺对所有系统服务统一拦截。
7. 基站 LAC/CID、运营商和蜂窝信息：管理电话相关权限并审计 Telephony API；不伪造基站、SIM 或运营商身份，不影响紧急通信。

#### C. 传感器与生物识别
1. 加速度计、陀螺仪、磁力计、光线、距离、压力、温湿度：盘点 SensorManager、传感器清单和可观测访问；Android 对部分传感器没有统一运行时权限，不能承诺系统级一键阻断。
2. 传感器阻断/模拟、采样率限制：仅对 FX 自有采集服务或明确授权测试应用提供数据源、限频和降采样；不全局伪造设备运动/环境数据。
3. 指纹/人脸：展示 BiometricPrompt 和系统认证器能力/调用状态；不伪造硬件缺失、不伪造认证成功、不绕过生物识别。
4. 麦克风/摄像头等隐私控制状态：读取 Android/ROM 正式隐私开关及权限状态。

#### D. 权限与 Framework API
1. 剪贴板：访问提醒、FX 自身敏感内容提示和主动清理；不向第三方应用返回伪造内容。
2. 运行中进程列表、已安装应用列表：审计 Android 应用可见性、QUERY_ALL_PACKAGES 和系统权限；不伪造空列表/自定义列表或进程状态。
3. 网络接口、本地 IP、网卡信息：展示真实接口和权限边界，结合 VPN/DNS 泄漏检测；不伪造网络身份。
4. logcat、/proc/version、cpuinfo、net、pid、mount、内核版本/编译信息：做权限、SELinux 和 Root 暴露面诊断；不伪造日志、进程、挂载或内核数据，不屏蔽安全审计。
5. PackageManager 签名/版本查询：审计应用可见性与签名权限；不伪造签名、版本或安装来源。
6. TelephonyManager、NetworkStats：显示权限/AppOps/Usage Access 状态与访问路径；不返回虚假号码、运营商、流量数据。
7. MediaStore：使用分区存储、系统照片选择器和媒体权限，支持仅授权所选媒体。
8. getSystemService：只诊断 FX 自身服务依赖和权限失败，不对第三方应用返回假服务对象或伪造能力。

#### E. 网络与连接隐私
1. 自定义 DNS、DoT/DoH：由 FX DNS 服务或实际支持的代理内核提供；验证上游、证书校验、IPv4/IPv6、失败回退和 DNS 泄漏，不能把配置存在当成加密已生效。
2. 域名/IP/CIDR 追踪列表：Hosts、DNS、规则订阅或防火墙执行，提供白名单、命中统计、误拦回滚；保护系统更新、紧急通信和必要服务。
3. 应用级网络访问控制：按设备 VPN 槽位、Root 路径、内核能力和第三方 VPN 占用状态选择真实通道。
4. UDP 控制：按应用/目标/端口制定规则；不默认无差别禁用 UDP，避免破坏 DNS、QUIC、语音和游戏。
5. TCP 时间戳、源端口随机化、ICMP：先只读探测内核默认值和支持状态；任何变更都需设备验证并提示 PMTU、IPv6、诊断等副作用。
6. TCP/IP 栈指纹：只提供暴露面说明，不伪装成其他操作系统或设备。
7. WebRTC 本地 IP 泄漏：仅对 FX 自有浏览器/WebView 可控策略提供控制和测试；不宣称能全局控制所有第三方浏览器。
8. 全局代理自动切换：使用 FX 内核、规则组、健康检查和回退；明确 Android VPN 槽位限制。
9. DNS/网络日志：默认脱敏，用户可查看、导出和清理。

#### F. Root、模块与系统完整性
- Magisk：安装状态、版本、模块列表、来源/签名、服务脚本、挂载状态、sepolicy 变更和启动结果。
- KernelSU：管理器/ksud 状态、内核支持、模块列表、模块来源、授权记录、内核接口和启动结果。
- Zygisk：启用状态、ABI、模块加载、目标进程加载、Hook 实际触发分别显示。
- LSPosed/其他 Framework：框架版本、scope、目标进程、模块加载、方法匹配和执行结果分别显示。
- Root 暴露面、su 路径、挂载点、调试状态和属性差异仅用于用户自查与兼容性排障；提供模块停用/卸载、权限最小化和恢复指导。
- Bootloader、Verified Boot、系统签名、安全补丁、内核调试标志只读展示真实状态；sepolicy 显示 FX 自身添加的规则及撤销方式；sysfs 显示设备真实节点。
- 不提供针对金融、支付、反诈、反作弊或企业设备管理的 Root/模块隐藏、检测规避、伪造 su/mount/proc/sys 输出、隐藏安全日志或伪造系统完整性状态。

#### G. 摄像头、麦克风与音频
1. 摄像头全局隐私开关、单应用 CAMERA 权限：读取系统/ROM 状态、AppOps 和授权结果。
2. 黑帧/测试画面、静音/测试音频：仅作为 FX 自有测试数据源或授权测试应用的输入，不向任意第三方应用注入假设备流。
3. 摄像头/麦克风硬件清单：只读展示 CameraManager/AudioManager 真实设备能力，不伪造硬件存在性。
4. EXIF 清理：FX 导出/分享副本前预览并移除 GPS、设备型号等元数据；原文件不静默修改。
5. 音频回放采集：遵守 AudioPlaybackCapture 授权与 DRM 限制，不拦截受保护音频或绕过用户授权。

#### H. 存储、文件与应用数据隔离
1. 应用存储权限：使用分区存储、照片选择器、SAF 和媒体权限，按应用授权范围管理。
2. 指定文件/目录：对 FX 自身管理目录使用 SAF、应用沙箱和明确授权；不承诺 Root 后可安全隔离所有第三方私有目录。
3. 应用私有目录隔离：优先使用 Android UID 沙箱、工作资料/多用户/应用分身等正式机制；不虚构全局虚拟存储隔离。
4. 存储根目录列表、文件属性：做访问审计；只允许用户对 FX 导出副本清理可识别元数据，不篡改原文件时间以伪造来源。
5. /proc、/sys 虚拟挂载：只做真实挂载/接口诊断，不伪造内核信息视图。
6. FX 文件保险箱：本地加密容器、用户明确导入/导出、密钥本地保护、恢复与备份策略。

#### I. 通知、剪贴板与输入隐私
1. 剪贴板清理、敏感内容提示和 FX 自身应用内隔离；Android 没有统一第三方应用剪贴板沙箱 API，不宣称全局隔离已实现。
2. NotificationListenerService 授权状态、可读取通知的应用清单、系统设置撤销入口；不隐藏通知访问授权状态。
3. 锁屏通知敏感内容和应用通知渠道设置，按系统能力跳转。
4. 当前输入法、切换入口、FX 自有键盘安全提示；不 Hook 第三方输入法窃取/篡改按键。
5. Accessibility 已启用服务、来源和权限范围审计；不隐藏无障碍服务状态或规避安全审计。

#### J. KernelSU/内核侧高级能力（条件开放）
1. sysfs 传感器节点控制：仅当设备驱动公开可写节点、权限允许且内核版本适配时逐设备开放。
2. read/openat 等文件访问控制：需要专用内核实现、ABI/内核适配、稳定回滚；不伪造/隐藏第三方安全审计数据。
3. ioctl 设备访问控制：仅用于限制未授权设备访问，不伪造摄像头、麦克风或生物识别结果。
4. netfilter/nftables/内核网络过滤：用于透明的用户网络访问策略、DNS/IP 过滤和连接保护，记录命中和回滚。
5. 内核栈随机化、task 结构体隐藏、伪造进程视图：不作为 FX 隐私开关交付，避免破坏调试、稳定性和安全审计。
6. KPM/内核模块：仅在目标 KernelSU/内核真实支持时显示；记录签名/来源、加载状态、版本依赖、冲突和崩溃回退。

#### K. 系统遥测、使用统计与其他
1. UsageStats：显示 Usage Access 特殊权限和官方撤销入口，不伪造统计数据。
2. Crash/ANR：可控制 FX 自身诊断收集/上传；系统或厂商日志只提供官方设置说明，不强制改写。
3. 开机时间戳、系统属性随机化：只读显示真实启动信息；不随机伪造系统身份、运行时序或硬件属性。
4. 安全补丁版本：只读真实 SPL 和更新状态，不伪造补丁级别。
5. 无障碍检测和系统服务查询：显示真实授权与服务状态，不返回虚假检测结果。
6. FX 自身遥测：独立总开关和分类开关、字段预览、保留周期、导出/删除；默认最小化，未经同意不上传。

#### L. 功能分级、优先级与验收
- **P0：** 权限中心、AppOps/特殊访问、精确/模糊定位、麦克风/摄像头权限、通知访问、Usage Access、媒体选择器、剪贴板提示、FX 遥测控制、DNS/过滤状态、Root/模块状态诊断、配置备份恢复。
- **P1：** Magisk 属性/挂载/服务脚本管理、KernelSU 模块状态、Zygisk/LSPosed 运行态诊断、应用级隐私策略、传感器访问审计、应用网络策略、EXIF 清理、应用权限管理。
- **P2：** 设备适配后的 sysfs 传感器控制、内核网络过滤扩展、专用测试传感器/音频/相机数据源、特定 Framework API adapter。
- **不作为 FX 通用开关：** 真机 IMEI/MEID/IMSI/SIM 身份伪装；伪造系统签名、安全补丁、Bootloader/Verified Boot、生物识别结果；伪造进程、包签名、挂载、内核和安全日志；针对金融、支付、反诈、反作弊或企业设备管理的 Root/Hook 隐藏、监测规避和安全告警屏蔽；随机化系统身份/内核任务视图；无差别拦截所有 UDP/ICMP 或全局传感器数据。
- 兼容矩阵记录 Magisk/KernelSU 版本、内核版本/配置、Android API、ROM/厂商、ABI、Zygisk/LSPosed 版本、目标应用版本、后端、权限条件、测试结果和副作用。状态只允许：原生支持、适配器支持、仅诊断、部分支持、不支持、待验证。
- 真机验收覆盖开关启停、重启持久化、单应用作用域、应用更新、权限撤销、模块卸载、OTA/内核变化、FX VPN/第三方 VPN/无障碍/LSPosed 冲突、崩溃回滚和系统恢复。模拟器不能替代真机；静态代码命中不能代替运行态验证。

**UI 组织：** 隐私 Tab → 隐私控制中心 → 应用权限、设备标识、位置与无线、传感器、网络隐私、摄像头与麦克风、存储与文件、通知与输入、Root/模块状态、内核高级、诊断与恢复。每类支持搜索、收藏、按应用筛选和不支持原因说明。分类总开关只控制明确列出的子项，不得暗中联动其他系统功能。

**实施约束：** 本节只定义方案和验收标准。未完成源码迁移、设备适配与测试的项目不得标记为已实现；后续源码实施须另行授权。


### 3.3.2 原始隐私开关逐项需求追踪表

本表确保用户原始清单中的每个项目都有独立需求 ID，不因实现难度而从产品需求中消失。状态需分别标记为：可按 Android 正式机制实现、需设备/ROM/内核适配、仅自有或授权测试、只读审计、不提供该类伪装或规避实现。UI 必须显示状态和原因；不得将未实现标为已实现。

**一、设备信息与指纹**
- D01 型号 model/device；D02 厂商 manufacturer；D03 Android/SDK 版本；D04 serial；D05 Android ID（全局/单应用范围）；D06 Build fingerprint；D07 CPU/主板/ro.hardware；D08 基带版本/编号；D09 蓝牙 MAC；D10 Wi-Fi MAC；D11 IMEI1/IMEI2/MEID；D12 SIM 序列号/IMSI；D13 品牌/产品名；D14 存储总量/可用量；D15 分辨率/DPI；D16 电池容量/健康/充电状态。
- 实现备注：真实值审计、权限可见性、系统正式随机化、测试数据源分别建项。电信身份、系统完整性和设备安全属性不提供第三方应用伪装。

**二、位置隐私**
- L01 全局 Mock Location；L02 单应用独立位置；L03 GPS 精度；L04 被动/网络定位访问；L05 AGPS 数据路径；L06 GNSS 卫星数/SNR；L07 Wi-Fi 扫描列表；L08 基站 LAC/CID。
- 实现备注：系统定位权限、精确/模糊位置、后台定位、Mock Provider、附近设备权限和访问审计分别建项；模拟位置仅用于自有/授权测试。

**三、传感器隐私**
- S01 加速度计；S02 陀螺仪；S03 磁力计；S04 光线传感器；S05 距离传感器；S06 压力/温度/湿度；S07 指纹硬件能力；S08 人脸硬件能力；S09 传感器采样率/精度。
- 实现备注：分别探测 SensorManager、HAL、驱动和可写 sysfs 节点；仅在实际支持时开放控制。生物识别只展示真实能力和授权状态。

**四、权限与 API**
- A01 剪贴板；A02 运行中进程列表；A03 已安装应用列表；A04 网络接口/IP/网卡；A05 logcat；A06 /proc/version、cpuinfo、net、pid；A07 mount/overlay；A08 内核版本/编译信息；A09 PackageManager 签名/版本查询；A10 TelephonyManager；A11 NetworkStats；A12 MediaStore。
- 实现备注：权限、AppOps、Package Visibility、SELinux、媒体选择器和系统访问审计分别建项；不返回虚假系统、进程、签名或日志数据。

**五、网络隐私**
- N01 自定义 DNS；N02 DoT；N03 UDP 策略；N04 TCP timestamps；N05 TCP/IP 栈指纹；N06 WebRTC 本地 IP；N07 全局代理自动切换；N08 追踪域名规则/Hosts；N09 TCP 源端口；N10 ICMP。
- 实现备注：DNS/DoT、域名/IP 过滤、按应用网络策略、代理健康检查和泄漏测试列为独立功能；UDP/ICMP/TCP 参数需逐设备验证副作用；不提供伪装其他设备或操作系统网络身份。

**六、Root/模块状态**
- R01 Magisk 文件/二进制状态；R02 KernelSU 节点/ksud 状态；R03 su 状态；R04 Magisk 挂载/overlay；R05 sepolicy 加载记录；R06 sysfs 节点；R07 Root 检测库；R08 Bootloader 状态；R09 内核 debug/补丁标识。
- 实现备注：模块管理、授权管理、来源/签名检查、挂载诊断、策略审计、停用/卸载/恢复分别建项；不提供针对金融、支付、反诈、反作弊或企业安全检测的隐藏、伪装或规避功能。

**七、音频与摄像头**
- M01 摄像头黑帧/测试图像源；M02 麦克风静音/测试音频源；M03 摄像头硬件清单；M04 麦克风硬件清单；M05 EXIF 清理（GPS/型号/时间）；M06 音频回放采集权限。
- 实现备注：摄像头/麦克风系统隐私开关、运行时权限、FX 自有测试数据源、导出副本 EXIF 清理分别建项；不向任意第三方应用注入虚假硬件或音频设备。

**八、存储与文件**
- F01 应用私有目录隔离；F02 指定文件/文件夹访问；F03 SD 卡/内部存储根目录；F04 文件修改时间/属性；F05 /proc、/sys 虚拟挂载。
- 实现备注：Android UID 沙箱、工作资料/多用户、SAF、分区存储、媒体权限和 FX 自有加密保险箱分别建项；不伪造文件来源或内核信息。

**九、通知、剪贴板与输入**
- P01 应用间剪贴板隔离；P02 NotificationListener 通知访问；P03 输入法/输入记录隐私；P04 通知访问授权状态检测。
- 实现备注：系统授权管理、通知访问清单、锁屏敏感内容、输入法来源审计分别建项；不隐藏无障碍或通知访问真实授权状态。

**十、KernelSU/内核侧**
- K01 sysfs 传感器控制；K02 read 路径及 /proc、/sys 访问控制；K03 ioctl 设备访问控制；K04 内核栈信息；K05 netfilter 网络过滤；K06 task/进程信息。
- 实现备注：按 KernelSU 版本、内核配置、驱动接口、ABI 和设备节点建立兼容矩阵；仅对经过验证的访问控制和网络过滤能力开放；不伪造进程或安全审计视图。

**十一、其他**
- O01 开机时间戳；O02 系统 crash 日志上传；O03 ANR 日志收集；O04 系统属性随机化；O05 安全补丁版本；O06 UsageStats；O07 Accessibility 状态；O08 getSystemService 查询。
- 实现备注：FX 自身诊断数据开关、Usage Access 管理、无障碍授权审计和真实系统状态展示分别建项；不伪造启动时间、系统补丁、服务或授权状态。

**统一验收与 UI 要求：** 以上 D01–D16、L01–L08、S01–S09、A01–A12、N01–N10、R01–R09、M01–M06、F01–F05、P01–P04、K01–K06、O01–O08 全部进入隐私控制中心的需求清单。每个 ID 独立显示：开关/只读状态、作用范围、后端（Magisk、KernelSU、Zygisk、LSPosed、Android API/AppOps、驱动/sysfs、netfilter）、依赖、设备支持、风险、验证结果、失败原因和恢复方式。配置状态与实际运行状态分离；重启、OTA、模块卸载、权限撤销、第三方 VPN 冲突和故障回滚均纳入验收。此表是方案追踪，不表示源码已经实现。

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

**进一步补齐：不止脚本语法，还要覆盖配置、订阅、自动化与跨内核迁移**

- **其他代理客户端配置来源**：评估 v2rayNG、NekoBox/NekoRay、Hiddify、FlClash、Clash Verge Rev、SagerNet 系客户端及其他公开客户端的可导入配置；它们是配置/订阅来源，不应被误称为脚本平台。按真实格式分别支持 URI 分享链接、批量节点链接、Base64 订阅、Clash YAML、sing-box JSON、V2Ray JSON 和各客户端自有导出格式。
- **节点与订阅协议**：覆盖常见的 ss://、ssr://（仅在选定内核实际支持时）、vmess://、vless://、trojan://、hysteria2://、tuic://、socks://、http(s)://、wireguard:// 等链接/配置；解析器必须校验字段、加密方式、传输层、TLS、Reality、SNI、ALPN、指纹、插件参数和 UDP 能力，未知字段保留并在转换报告中列出。
- **规则生态补齐**：除通用域名/IP/CIDR 外，纳入 GeoIP/GeoSite、进程名/UID、端口、网络类型、入站/出站、规则集远程引用、规则提供器、DNS 路由、Fake-IP/真实 IP 模式、嗅探规则、策略组/代理组、负载均衡、故障转移和健康检查等配置语义。每个语义按内核 capability 决定支持情况，不得把解析成功当作执行成功。
- **DNS 与过滤列表来源**：兼容 AdGuard DNS filter、ABP/uBO 列表、Hosts、域名/IP/CIDR 列表、RPZ（若适用）、DNSCrypt/DoH/DoT/DoQ 配置和本地/远程规则集；对订阅更新、ETag/Last-Modified、签名/哈希、去重、冲突优先级、过期缓存、失败回退和白名单建立统一管理。
- **脚本语言与执行宿主**：JavaScript 是首要通用脚本运行时；对 Lua、Python、WASM 等只建立可插拔 Runtime Provider，只有依赖、许可证、沙箱、权限模型和实际 API 桥接通过验证后才开放。不得因为能运行某种语言就宣称兼容 Surge/Loon 等宿主 API；语言兼容与宿主 API 兼容必须分开评级。
- **自动化生态**：除各代理客户端的定时任务外，评估 Android Tasker、MacroDroid、Automate、系统快捷方式/Quick Settings Tile、App Shortcuts、Widget、Intent/deep link、通知动作和 FX 自身计划任务。所有外部触发必须经过用户授权、参数校验、去重、权限检查和审计；不允许静默执行高风险 Root/证书/网络配置操作。
- **脚本/规则分发与更新**：支持 Git 仓库、HTTPS URL、本地文件、压缩包和受支持的订阅源；记录来源、版本、提交/ETag、SHA-256、签名状态、许可证、更新策略和变更差异。导入未知来源时先预览权限和动作，不自动执行。
- **跨格式迁移**：提供“导入 → 解析 → 能力检测 → 转换预览 → 用户确认 → 备份 → 应用 → 回归检查”的事务流程；保留原文件、注释、未知字段和来源元数据。转换失败必须回滚；不能表达的语义列入差异报告，不得静默丢弃或用近似行为冒充等价。
- **兼容矩阵必须覆盖真实版本**：平台/客户端、版本、配置格式版本、脚本 API、规则语法、内核能力、Android API/ABI、执行通道、权限、测试用例和已知限制均需独立记录。每项标注“原生支持 / 适配器支持 / 仅导入解析 / 部分支持 / 不支持 / 待验证”，并附测试证据。新增平台通过格式探测和 Provider 插件接入，不以本轮列举名单作为封闭白名单。
- **禁止虚假兼容**：只识别文件扩展名、读取到配置段、成功导入节点或脚本语法通过，均不代表任务可运行。必须验证任务触发、API 返回值、网络请求、响应修改、持久化、定时触发、取消、错误隔离及升级后的行为。

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
- **Domain**：Ad、VPN、Privacy、Hook、Script、Settings 等产品业务接口和用例；来源 APK 导入/差异比对仅属于开发期 Source Intake 流程，不是用户业务域。
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
2. 从设置选择模式后，先同步保存偏好，再只重建当前 Activity 的展示层；保留当前 Tab、滚动位置、表单草稿、节点/规则选择和业务子页面返回上下文。
3. ClassicWebCompat 的四个业务页由 WebView 显示 APK 内置 AssetLoader 资源；Hook 与设置使用同一 Classic 外观的原生宿主。禁止远程导航、混合内容和任意文件访问；桥接接口继续执行来源校验。
4. FXLiquidNative 使用 Compose 原生导航与液态背景效果；MiuixStyle 使用 Miuix 主题组件。两者共享同一 Domain/Repository/状态源，不复制业务逻辑。
5. 五种模式共享相同六个 Tab：VPN、Ad、隐私、脚本、Hook、设置；设置始终是第六个 Tab。
6. 切换过程中不得 stop/start/reconfigure VPN、内核级代理、DNS、Root 规则、LSPosed、Accessibility 或脚本任务。UI 观察状态变化，不拥有服务生命周期。
7. 动画/Backdrop 不可用或低内存时允许降级为静态背景，但不得切换业务模式或丢失页面功能。

**验收矩阵：**
- 五模式冷启动、进程重建、横竖屏/窗口尺寸变化后，读取到正确模式。
- 在每个模式中逐个进入六个 Tab，页面、返回栈和功能权限一致；ClassicWebCompat WebView 无越权导航。
- 在 VPN 正运行、代理有活动连接、DNS 正在过滤、脚本正在运行时，连续切换五种模式；服务 PID/连接状态/配置哈希不因换肤改变。
- 每种模式分别测试底部栏点击/手势、无障碍语义、键盘弹出、滚动恢复、Hook 列表和各业务二级页面。
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

### P2 — 来源功能逐项归并（仅限开发期，不形成来源应用入口）
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
- QuickJS/QuickJS-NG 首要运行时及多平台 API adapter；按 Surge、Quantumult X、Loon、Shadowrocket、Stash、Egern、Surfboard、Clash/Mihomo、sing-box、UserScript 等生态逐项验收；补齐规则/订阅格式解析、自动化集成、跨内核配置迁移和 MITM 脚本接入。
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

**唯一正式提示词：** `docs/FX_1.0.0_AUTONOMOUS_CROSS_AI_HANDOFF_PROMPT.md`。请将该文件全文交给新接手 AI；本文件只保留产品规格、架构和验收依据，不再复制维护第二份提示词。

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

注意：当前源码已建立五模式模型、持久化与选择面板；Shell 已有五种导航/背景外观，FxNativeSkin 已覆盖主 Activity 和共享迁入 Activity 的基础页面表面。HUAWEI/iOS 的全局 Skin 仍属基础接入，六个 Tab 的完整控件 token 化、深浅色/字体缩放/大屏/无障碍逐页验收尚未完成。ClassicWebCompat 当前显示 FX APK 中打包的 WebUI 页面；虽然已检查游龙工具 10.0.2 APK 的壁纸与界面模式行为，但其原始完整 UI 资源/交互并未全部复刻，禁止把兼容入口名称写成 10.0.2 完整界面已逐页还原。


## 11. 整体重构纠偏（本节优先级高于历史描述）

本节为当前有效产品约束；若本文其他旧段落与本节冲突，以本节为准。

1. **取消“迁移应用”产品入口**：FX 是整合后的单一产品，不是旧 APK 集合启动器。Dia、游龙广告插件、游龙安全护盾、GKD 等只作为研发源码来源；其功能按 Ad/VPN/隐私/脚本/Hook 归属整合。最终 UI 不得出现“迁移应用”Tab、设置入口、来源应用列表或跳转回旧 APK 的操作。
2. **第二 Tab 统一命名为 Ad**：底部、顶部标题、面包屑、页面标题和导航配置均只显示“Ad”。Hosts 是 Ad 内部功能页，不得把主 Tab 写成“Ad/Hosts”。
3. **最终六 Tab 唯一结构**：VPN、Ad、隐私、脚本、Hook、设置。不得增加来源应用 Tab 或第二入口；设置永远第六。
4. **设置边界**：只放全局外观/五种模式/壁纸/主题/动效、权限中心、备份恢复、通知与诊断偏好、关于。业务操作不得迁入设置；“迁移应用”必须删除，不是改名或隐藏。
5. **整合验收**：逐个核对旧来源的功能和设置项，确认其在 FX 对应业务域有真实页面、状态和后端；保留来源版本映射仅供开发追踪。不能以删除旧入口为由丢失功能。
6. **APK 10.0.2 UI 与壁纸**：ClassicWebCompat 必须以用户提供的游龙工具_10.0.2.apk 真实资源和页面为依据；壁纸能力归入设置→外观与个性化，壁纸只改变 UI 背景。若 APK 原件缺失，记录证据阻塞，不得臆造原版细节。
7. **旧段落清理**：任何旧文案中出现“Ad/Hosts”作为 Tab 名、“设置下的迁移应用”、“迁移来源应用独立三级入口”都视为过期要求，开发 AI 必须同步清理对应 UI、路由、测试断言和文档。



## 12. 当前实际业务入口与 Tab 归属（2026-11-05，优先于旧映射表）

固定 Tab 索引（从 0 开始）：VPN=0、Ad=1、隐私=2、脚本=3、Hook=4、设置=5。所有二级 Activity 的导航高亮和返回文案必须跟随其实际业务归属，而不是沿用来源 APK 的原 Tab。

- **Ad（1）**：游龙广告插件来源能力融入 FX Ad；包括广告控制中心、通用设置与备份格式兼容、DNS 日志、防火墙、应用白名单、本机统计/摘要、过滤列表、域名名单和计划任务。用户可见标题只显示 FX Ad/Ad，不显示“游龙广告插件 7.0.1”。
- **VPN（0）**：系统 HTTP 代理编辑页归 VPN；节点/代理/TUN/路由/DNS/MITM 继续由 VPN 业务管理。不要把系统 HTTP 代理归入 Hook 或 Settings。
- **隐私（2）**：安全防护中心及屏幕滤镜、每日安全总结、病毒库、扫描、风险详情、批量清理、完整性、救援、白名单/管控名单等 Shield 子页统一高亮“隐私”；通知监听/权限提示策略与 Toast 文本过滤也保留在隐私页，返回按钮回到隐私业务链。
- **脚本（3）**：Frida JavaScript 脚本库归脚本页；浏览器 UserScript/扩展和其他脚本生态能力也归此页。
- **Hook（4）**：已安装应用列表与逐应用 Hook；Dia 来源的 Frida 环境/注入、DEX 浏览与方法选取、Activity 入口、文件/so、JSON、Inspector、监控事件、Frida 会话日志、签名信息、系统扩展、Hook 工具全局设置、自定义 Hook、Dialog 对话框 Hook 和按键动作 Hook。Dialog/按键从 Hook Hub 进入逐应用目标配置，页面始终高亮 Hook；用户可见名称以“Hook”命名，不暴露 Dia 旧应用品牌。
- **设置（5）**：五种 Skin、壁纸、主题/动效、全局权限/诊断偏好、FX 统一备份恢复、关于。备份页由设置入口直达；不要重复出现在 Hook 工具页。

当前代码入口：
- MainActivity.buildNativeAdPage()：Ad 主页面及广告来源功能子页入口。
- MainActivity.buildNativePrivacyPage()：安全防护中心入口。
- MainActivity.showHookHub()：Hook 工具与调试入口、授权状态。
- MainActivity.buildNativeScriptPage()：Frida JavaScript 脚本库入口。
- MainActivity.showSettings()：壁纸/五 Skin/全局备份恢复等系统级配置。
- FxNativeTabActivity：通过统一 FxUiMode.read() 和共享 Shell 提供五 Skin；每个子页必须明确业务 Tab 索引。

回归要求：验证 Settings 无迁移应用、六个主 Tab 标签固定、Ad/Shield/Dia 页面不暴露旧来源品牌、Shield/Toast/通知隐私策略选中隐私、Frida/Dia Dialog/Dia 按键 Hook 工具选中 Hook、Frida JS 脚本库选中脚本、备份选中设置、HTTP 代理选中 VPN；这些页面映射必须在业务页中真实可达，不可只保留死的旧路由。


## 12. GKD-XA 1.4.8 来源固定与单 APK 融合约束

用户指定的 GKD-XA 融合版现已固定为 Git submodule `vendor/GKD-XA`，上游 `84593320z/GKD-XA`，tag `v1.4.8`，commit `8a6ce935da11671dac7e1a7595416ec99ee07436`。许可为 GPL-3.0，分发时须保留相应源代码、许可证、版权和修改记录。

GKD-XA 包含独立 Application/MainActivity/AppRoot、Room 数据库、AIDL 特权接口、隐藏 API、Kotlin Multiplatform selector、Accessibility runtime、订阅规则、快照与 AI 生成流程。它不能作为第二 APK 或第二主界面接入。先处理 FX (AGP 9.1.1 / Kotlin 2.4.21 / Java17) 与 GKD-XA (AGP9.4.1 / Kotlin2.4.20 / JVM21) 构建差异，完成 Manifest/服务/数据库/权限兼容性 spike，再迁移 selector、订阅仓库、无障碍 runtime 与页面路由。

完整技术与验收要求见 `docs/FX_GKD_XA_1.4.8_INTEGRATION_PLAN.md`。当前只有源代码锁定和审计文档，**GKD-XA 的运行时、服务、UI、数据库与 selector 均未合入 FX APK**。不得把来源锁定说成完整功能迁移。


## 10.0.2 参考 APK 已取得的证据（2026-11-05 更新）

- 资料库原件：`/游龙工具_10.0.2.apk`，大小 92,008,250 bytes。
- SHA-256：`c2d7bb1b8e688232888a927d5b81affcf5c28832f9e6420e27e800e54f5fee75`。
- APK ZIP 目录可见 `classes.dex`、`resources.arsc`、`AndroidManifest.xml`，以及 `assets/bizhi.png`、`assets/index.java`、`assets/apk.tar.xz` 等资源；其中 index.java 和 bizhi.png 经常规文件识别显示为非明文数据，不能直接当作可用 HTML/PNG 导入。
- DEX 字符串/类符号能确认存在 `com.youlong.gj.MiuixScreenKt`、`MiuixUiRoot`、`MiuixWallpaperDialog` 和 Miuix 组件引用，说明 10.0.2 内含 Miuix 原生页面实现；`assets/apk.tar.xz` 内含 `hd.apk`、`ylads.apk`、`cj.apk` 三个嵌套 APK 名称。
- 已从 Wallpaper 实现证据确认的用户可见行为：弹窗名“壁纸随心换”，操作为“上传本地图片”和“恢复默认壁纸”；所选图复制到应用私有目录，最长边压至 1920 px，JPEG quality 85，使用 SharedPreferences `native_wallpaper_prefs/wallpaper_path` 保存文件路径。FX 已在 `FxWallpaperStore` 与全局六 Tab Compose 壳接入该契约。
- 证据边界：当前已核验 APK 文件哈希、ZIP 成员清单和 DEX 符号；尚未完成完整 JADX/资源解密与原版逐页截图审计，不能声称 ClassicWebCompat 已逐像素复制 10.0.2 原 WebUI，也不能直接把加密的 index.java/bizhi.png 当普通网页和图片资源复制。
- 下一步：继续以该哈希作为不可变参考原件，对 DEX/加密资产/内嵌 APK 做受控提取；建立 10.0.2 的六 Tab/页面/壁纸与 FX 映射表，再决定哪些原始资源可合法复用，哪些应重建。


---

## 13. 2026-11-05 导航清理落地记录与功能完成边界

### 产品导航更正

- 最终用户产品只有一个 FX APK、一个启动入口、六个固定 Tab：VPN、Ad、隐私、脚本、Hook、设置。
- 禁止“迁移应用”页面、来源 APK 启动器、来源套件首页/分类树、来源应用并列入口。Dia、游龙广告插件、游龙安全护盾、GKD-XA 只保留在开发证据、许可证、功能映射与诊断记录中。
- 设置仅放外观与个性化（五 Skin/壁纸/主题/动效）、权限、统一备份恢复、通知/诊断偏好和关于；Root/模块/LSPosed 的业务控制归隐私或 Hook，不得以“迁移应用”为父级。
- 第二 Tab 的所有可见标签必须是 Ad。Hosts 是 Ad 内的页面/编辑器/重定向层。旧 WebView 的 pageHosts 仅允许作为历史 DOM ID 兼容别名；新的主导航和路由必须使用 pageAd。
- Tab 索引：VPN=0、Ad=1、隐私=2、脚本=3、Hook=4、设置=5。不得添加“Ad/Hosts”并列标题。

### 本批源码改动（GitHub 已提交）

- MainActivity 已删除旧来源应用目录的顶层、分类、子页待迁移占位和来源应用返回栈代码；DEX 选择后回到统一 Hook 目标/应用列表，不再回到 Dia 来源分类树。代码提交：6d4bda992cd4172243509db69bcd8b6e3acf0dd2。
- Web 兼容路由将 pageAd 设为 Ad 的标准页面 ID，pageHosts 只作旧资源兼容别名；导航标签归一到 ad。该改动包含在上述 MainActivity 提交中。
- scripts/tests/fx-unified-navigation-regression.sh 新增断言：Ad 主路由、旧 pageHosts 兼容别名、Settings 无来源应用入口、MainActivity 不再含旧 migration hub 符号。提交：9423cd6cece752e3fc8f32e452a2667f9e758947。
- scripts/tests/fx-imported-suite-back-navigation-regression.sh 已改为检查旧来源应用目录已移除，并检查 Ad/隐私/Hook/脚本功能仍留在对应业务入口。提交：c08c17c6eecfc826c05fc286db8a33a5262da60c。
- 这些源码改动属于导航和路由清理，不代表所有来源应用功能已完整迁移，更不等于真实后端已全部完成。

### 当前功能状态必须如实报告

- Ad：FX Ad 页面可达，具备 Hosts、本地/订阅规则管理入口，并接入部分游龙广告来源页面。不得仅凭 Activity 可打开就声明 DNS 多层、所有 Firewall/Tasker/Widget/Tile/计划任务已完整运行。
- VPN：存在原生控制页面、节点/订阅/分应用配置和若干代理/网络组件；必须继续验证内核级主数据面与第三方 VPN 共存、防回环、防 DNS/IPv6 泄漏、断线保护及真实待机耗电。
- 隐私：已有原生隐私页与部分 Shield 来源页面/扫描实现；完整扫描覆盖率、数据库更新、后台守护和全部安全护盾行为仍须以代码与实测逐项验收。
- Hook：Dia 工具中的部分页面已映射到 Hook，Frida/LSPosed 能力必须区分页面入口、Runtime 存在、目标进程注入和真实执行；不能用配置已保存替代注入成功。
- GKD-XA：目前仓库锁定上游 v1.4.8 源码并有融合计划；不等于其 UI、selector、数据库、Accessibility runtime 已并入 FX APK。
- 脚本：已有 Frida JS 脚本库入口；Loon/Shadowrocket 等代理脚本、MITM request/response 和浏览器 UserScript/扩展必须分别证明解析、API 适配和实际执行，不得只做格式导入。
- UI：五 Skin 的模式 ID、选择器和全局导航基础分支已存在；HUAWEI/iOS 独立组件 tokens、六 Tab 逐页 renderer、截图与设备验收仍未全部完成。
- 壁纸：已按 10.0.2 已核验的“壁纸随心换”上传/恢复契约建设 FX 私有壁纸层；裁剪/定位/模糊/遮罩等超出原版证据的功能必须标注为 FX 扩展，不可误称为 10.0.2 原版能力。

### 永久禁止的完成声明

- 不得宣称“全部功能已迁入”，除非每项均有 UI、真实业务逻辑、权限与持久化、错误处理、生命周期和匹配风险等级的验证证据。
- 不得宣称 Android 的 Always-on VPN 零耗电或与 iOS 生命周期完全相同；只能提交设备测得的待机功耗和唤醒数据。
- 不得承诺任何第三方应用必定信任用户/系统 CA；证书锁定、自定义信任库、QUIC/HTTP3 和应用内 TLS 实现需单独列出兼容性。
- 不得承诺 Root/模块/LSPosed 对所有应用绝对隐藏；按 Android 版本、ROM、框架、目标进程和检测方式记录结果。
- “Hook VIP”只能用于合法授权、用户自有应用和测试 entitlement；不伪造付费资格、不绕过付费授权。
- 自定义位置仅按用户明确授权的 Android 测试/隐私模拟场景实现；不保证第三方服务接受或把模拟坐标宣称为真实 GPS。

### 跨 AI 执行文件

新接手的 AI 必须以 docs/FX_1.0.0_AUTONOMOUS_CROSS_AI_HANDOFF_PROMPT.md 为可执行提示词，以本文件为产品规格，以 docs/FX_1.0.0_LIVE_CONTINUATION_STATE.md 为事实进度。旧的 Library 提示词若要求 Settings 下出现迁移应用、使用 Ad/Hosts Tab 名或保留来源应用目录，均视为过期，不得照做。


---

# 2026-11-05 用户最终需求基线：全功能清单、页面布局与逐项验收（优先级最高）

> 本节是本轮用户明确提出的完整产品需求核对表。若历史章节遗漏细节，以本节补充；若与 Android 平台能力、许可或安全边界冲突，必须保留需求意图并明确记录可实现范围，禁止虚报“全部支持”。

## A. 产品形态与导航硬约束

- 最终只有一个 FX APK、一个 Launcher、一个统一原生主界面、一个配置/数据库/权限/生命周期体系。
- 固定六个底部 Tab，顺序和索引不可变：0 VPN、1 Ad、2 隐私、3 脚本、4 Hook、5 设置。
- 第二 Tab 的所有用户可见名称只能是 **Ad**。Hosts 是 Ad 内部页面/编辑器/重定向层；不得出现“Ad/Hosts”作为 Tab、主标题或并列业务域。
- 最终产品中彻底删除“迁移应用”、来源应用启动器、旧 APK 列表入口、来源应用分类树。不能隐藏、改名或挪到设置里；旧来源仅留在研发映射表、许可证和内部诊断。
- Settings 只负责外观个性化、全局权限状态入口、统一备份恢复、通知/诊断偏好、许可证和关于。所有业务功能必须放回 VPN/Ad/隐私/脚本/Hook。
- 所有控件必须连接真实业务状态；未实现项明确标注“未接入/不支持/权限不足”，不能用假开关、假计数、假运行状态填充页面。

## B. 五种全局界面模式与游龙壁纸

五种模式为同一 APK 的全局 Skin，所有六个 Tab、二级页面、表单、列表、Dialog、Sheet、编辑器、空/加载/错误状态均需覆盖：

| 显示名称 | 内部模式/ID | 实现要求 |
|---|---|---|
| 老版本界面（网页界面） | ClassicWebCompat / classic | 以游龙工具 10.0.2 原版真实页面、资源、导航与交互为证据；无法复用的加密资源必须重建，不能臆造逐像素还原 |
| 原生界面（液态玻璃） | FXLiquidNative / glass | Compose 原生 UI、玻璃材质、模糊降级、可读性和低耗电 |
| Miuix 界面（小米澎湃风格） | MiuixStyle / miuix | Miuix/HyperOS 风格组件和布局，不依赖小米私有 API |
| 华为界面（Harmony 风格） | HUAWEI HarmonyStyle / huawei | Harmony tokens 与 renderer，普通 Android 设备可用，不冒充鸿蒙原生 |
| iOS 界面（Cupertino 风格） | iOS CupertinoStyle / ios | Cupertino tokens 与 renderer，不冒充 iOS 原生或获得 Apple 私有系统能力 |

五种模式共享完全相同的业务状态、服务、权限、数据库和路由。切换 Skin 不得停止/重启 VPN、内核级代理、DNS、Hosts、Hook、Frida、GKD、证书或脚本服务；不得丢失当前 Tab、滚动位置、编辑草稿和连接状态。

### B1. 壁纸功能（参考游龙工具 10.0.2）

- 在 设置 → 外观与个性化 → 壁纸 中提供“壁纸随心换”入口；支持上传本地图片、预览、恢复默认、清除自定义壁纸。
- 原版已核验契约：SharedPreferences `native_wallpaper_prefs` / `wallpaper_path`；复制至应用私有 files；最长边 1920 px；JPEG quality 85；文件名 `native_wallpaper_<timestamp>.jpg`。
- FX 可增加裁剪、缩放、定位、模糊、遮罩透明度、深浅色适配，但必须标为 FX 扩展，不能伪称原版功能。
- 壁纸仅改变五种 Skin 的 UI 背景，不得进入 WebView 远程资源、不上传服务器、不改变网络/安全功能；敏感页面自动保证文字对比度。
- URI/文件失效、损坏、权限撤销或升级后应安全回退默认壁纸，失败保存不得覆盖旧壁纸。

## C. Ad：六类广告过滤能力与游龙广告插件完整功能

Ad 是独立广告过滤业务域；至少包含以下五个数据处理层，分别配置、开关、状态、权限、日志、统计与失败回退：

1. **本地 DNS 层**：本地 Resolver、缓存、域名规则、CNAME、A/AAAA、IPv4/IPv6、白名单、上游策略、超时/重试、DoH/DoT（仅在真实实现时显示）、DNS 泄漏与失败回退诊断。
2. **Hosts 重定向层**：真实系统 hosts 文本文件；本地 hosts 与订阅规则分开；分页/增量编辑、搜索、外部文件变更回读、差异预览、校验、原子写入、备份/回滚；订阅不得污染本地编辑文件。
3. **应用层 Hook**：对用户授权且兼容的应用实施请求/域名过滤；准确显示 Root、LSPosed 安装/连接/作用域、目标进程注入与执行状态。
4. **Accessibility 层**：用户主动授权后，对可见 UI 做广告识别、关闭/跳过辅助；逐应用作用域、频率限制、立即停用、日志脱敏、后台耗电保护；禁止读取密码、验证码和私人消息。
5. **TUN/代理过滤层**：通过受支持的共享网络数据面过滤；不创建与第三方 VPN 冲突的第二个 VpnService；准确展示当前流量路径和过滤覆盖范围。

游龙广告插件的功能迁移不能只做主页面。必须基于可取得源码/APK 版本建立逐项矩阵，至少核对：
- Ad 总控、General 通用设置、Summary、Stats/统计、应用白名单；
- DNS 设置/日志、Firewall/应用防火墙、域名/应用名单；
- 规则订阅、规则详情、更新/失败状态、导入导出及原始配置兼容；
- Quick Settings Tile、Widget、Tasker/Automation、计划任务；
- Root Proxy、代理/网络接管相关能力；
- 每个版本的独有设置项、通知、后台服务、开机恢复、备份恢复。
每项必须有 FX 页面归属、数据存储、真实服务/系统调用、权限、生命周期、错误状态和测试。版本差异不可凭空推断；无源码/证据的条目标记待审计。

## D. VPN：小火箭类能力、内核级代理、防泄漏、低功耗与 MITM

VPN 页面负责代理节点、订阅、内核、路由、连接、DNS 路由、MITM/证书和诊断。最低功能清单：
- 节点添加/编辑/删除/分组/延迟测试；订阅导入、更新、去重、失败回滚、订阅转换/导出。
- 协议能力按实际内核矩阵提供：Shadowsocks、VMess、VLESS、Trojan、SOCKS、HTTP(S)、WireGuard、Hysteria2、TUIC 等；不支持的协议不得显示为可连接。
- 直连/全局/规则三种模式；域名、IP、CIDR、进程/应用分流；规则集管理、优先级、命中解释、绕过/直连名单。
- DNS 上游/策略、缓存、IPv4/IPv6、DoH/DoT（若支持）、防 DNS 泄漏；连接日志、流量统计、自动重连、网络切换、断线保护、启动/停止诊断。
- 内置默认内核；支持切换其他内置内核和用户上传/自定义内核。导入时校验 SHA-256/签名、许可证、ABI/架构、版本、能力、执行权限；未知内核默认隔离；切换失败回滚。
- FX 代理主实现必须是 Root/系统网络栈级数据面，目标是在不占 Android VPN 槽的情况下与第三方应用 VPN 并行。检测 VPN 接口、路由表、UID policy 和 DNS；不停止第三方 VPN、不抢占 VPN 槽、不 flush 全局规则、不覆盖未知路由。支持程度按“完全并行/受支持链式/部分兼容/不兼容”实测分级；封闭第三方 VPN 不可保证透明共存。
- 只有在 Root/系统网络栈接管不可用且 VPN 槽空闲时，才可使用 FX 自己的 VpnService 回退；第三方 VPN 已占槽时禁止抢占。
- 防泄漏测试必须包括 DNS、IPv4、IPv6、WebRTC、断网/重连、内核崩溃、Root 丢失、Wi-Fi/蜂窝切换、飞行模式、应用分流和第三方 VPN 共存；用户指定测试地址：https://who.1ms.dog/zh-cn/。记录设备、ROM、Android、内核、时间和截图/结果；单站点通过不等于无泄漏。
- Always-on 目标是降低空闲 CPU、唤醒、轮询和电量消耗，支持系统允许范围内的自动恢复；Android 不等同 iOS 网络扩展生命周期，不承诺零耗电或所有 OEM 永不杀进程。必须用真机测量 idle、屏幕关闭、活跃流量和断网恢复能耗。
- MITM：支持按用户明确允许的 App/域名启用；请求/响应脚本回调；CA 生成、私钥保护、系统/用户证书安装、信任状态、轮换、撤销、卸载、备份与失败回滚；Root 系统 CA 按 Android 版本/APEX/分区探测。必须分别记录系统 CA、用户 CA、应用私有信任库、证书锁定、QUIC/HTTP3 的兼容性。不得承诺所有 App/浏览器都无警告或无断网；默认安全关闭，允许随时停用/撤销。
- MITM Script 必须真实进入代理内核 TLS request/response hook，支持超时、取消、错误隔离、权限沙箱和可审计日志；仅有编辑器或脚本导入不算完成。

## E. 隐私：FX 既有隐私功能与游龙安全护盾

- 完整保留 FX 模块现有隐私页功能，先读取真实页面和后端，再逐项映射，禁止因重构而删除。
- 整合游龙安全护盾可合法复用能力：安全总览、扫描任务、扫描范围、风险详情、病毒库/特征库状态、屏幕过滤、每日安全总结、完整性检查、救援/恢复、白名单/管控名单、批量清理与处置记录。
- 应用隐私详情：权限、传感器、剪贴板、通知监听、权限提示、Toast 文本过滤、后台行为和网络隐私状态；逐项说明所需权限和采集范围。
- Root、模块、LSPosed/LSP、Accessibility 分别显示真实状态和连接/授权情况；隐藏或兼容策略只能对用户自有设备/授权应用配置，并提供可撤销状态。不得承诺绝对隐藏或规避金融/支付/反作弊/设备完整性安全校验。
- 病毒库不可用、扫描不完整、权限不足、数据源过期时显示未知/不完整，不得给出虚假“安全”结论。

## F. Hook：Dia、GKD、自定义 Hook 与逐应用工具

Hook 为第五 Tab，采用“已安装应用列表 → 应用详情 → 工具/规则/日志”的原生单入口结构，不再保留 Dia 第二入口或旧来源分类树。
- 广告 Hook、开屏广告识别/关闭辅助、逐应用 Hook 配置与运行状态。
- Dia 23.11 可合法迁移的全部工具按功能逐项审计：Frida 环境/服务/注入会话、脚本库、DEX 浏览/方法选择、Activity、文件/so、JSON、Inspector、监控事件、会话日志、崩溃/签名信息、系统扩展、Dialog 对话框 Hook、按键动作 Hook、全局工具设置。
- GKD-XA 1.4.8：高级 selector 语法/编译/节点匹配、订阅源/规则组/应用范围、自动点击/跳过、触发条件/次数/冷却/延迟、快照、规则编辑、AI 辅助、历史/事件日志、备份恢复、Accessibility runtime；先完成工具链、Manifest、Room、AIDL、隐藏 API 与服务生命周期兼容，不得直接复制第二个 Application/MainActivity。遵守 GPL-3.0。
- 自定义 Hook：提供多语法、多规则格式、语法校验、目标应用作用域、启停、执行结果、日志和失败回滚；支持能力必须以真实 parser/runtime 为准。
- 应用更新检测、VPN 检测、隐私检测应显示真实检测依据、权限和误报风险；用户可选择目标应用和触发时机。
- 位置功能仅提供 Android 官方 mock location/测试能力，用于用户拥有或获准测试的应用；明确 GNSS、基站、Wi-Fi、IP、传感器和账号侧可能交叉校验，不能承诺“与真实位置完全一样”。
- VIP/会员 Hook 仅用于用户自有应用、授权测试和合法 entitlement 调试；不伪造会员、不绕过支付/订阅/服务端授权。

## G. 脚本：代理脚本、规则脚本、浏览器 UserScript 与扩展

- 代理脚本平台：Surge、Quantumult X、Loon、Shadowrocket、小火箭、Stash、Egern、Surfboard、Clash/Mihomo、sing-box；逐版本维护解析器、API Adapter 和实际运行时矩阵。
- 必须实际实现并测试相应平台的请求/响应/定时/策略/持久化 API；例如 `$httpClient`、`$task.fetch`、`$done`、`$prefs`，不得用名称映射冒充语义兼容。
- 规则格式：AdGuard、uBlock Origin、Adblock Plus、Hosts、PAC、DNS blocklist、URL Rewrite、domain/IP/CIDR；解析、验证、冲突检查、执行分别验收。
- 浏览器脚本：UserScript 元数据、匹配规则、排除规则、运行时、脚本更新、启停、站点权限、GM_* API、跨域权限与错误日志。
- 浏览器扩展：基于具体 Android 浏览器公开的 WebExtension/扩展 API 接入；逐浏览器列出可用 API 和限制。没有扩展 API 的浏览器不声称支持；不宣称在所有浏览器全局注入。
- 统一 QuickJS/QuickJS-NG 或经验证 runtime；提供权限沙箱、网络/文件访问控制、超时、取消、内存限制、日志脱敏、版本管理、导入校验和回滚。
- MITM 请求/响应脚本由 VPN 真实 TLS hook 调用；浏览器 UserScript 由对应浏览器环境调用；二者不得混为同一运行环境。

## H. 页面布局重构要求

### 全局壳
- 顶部：当前业务标题、连接/权限/错误等必要状态摘要；不展示来源 APK 品牌。
- 主内容：卡片/列表/详情页按业务密度自适应；支持窄屏、大屏、横竖屏、键盘、系统字体缩放和 TalkBack。
- 底部：六个 Tab 固定且可见；不能被滚动内容覆盖或消失；当前项高亮；图标/文字一致。
- 全局搜索与通知入口按实际功能设计，不增加第七个业务 Tab。
- 五 Skin 使用同一导航与业务组件契约，只替换 tokens/renderer。

### VPN 首页
1. 连接总卡片：状态、当前节点/模式、连接/断开主按钮、实际数据面类型。
2. 模式切换：直连/全局/规则；节点选择与分组。
3. 当前内核、代理路径、第三方 VPN 共存状态和兼容级别。
4. 流量/速度/时长统计（真实数据）；DNS/IPv6/WebRTC 防泄漏检查入口。
5. 节点、订阅、路由规则、应用分流、DNS、MITM/证书、日志诊断作为二级页面。
6. 任何错误必须显示可恢复原因和回滚结果，不允许只显示“已连接”。

### Ad 首页
1. Ad 总开关与当前过滤覆盖状态。
2. 五层状态卡：DNS、Hosts、应用 Hook、Accessibility、TUN/代理。
3. 过滤列表/订阅、白名单、应用名单、Firewall、DNS 日志、统计摘要、计划任务。
4. Hosts 编辑器作为内部子页：本地 hosts 与订阅规则分区，分页编辑和差异预览。
5. 每层展示真实权限/服务状态、最近错误和“为何未生效”。

### 隐私首页
1. 隐私风险摘要与数据更新时间。
2. Root/模块/LSPosed/Accessibility 独立状态卡。
3. 安全护盾扫描、病毒库、屏幕过滤、完整性、救援、每日总结。
4. 应用隐私列表、权限/传感器/通知/剪贴板/Toast 策略。
5. 每项控制提供影响说明、撤销、审计与权限入口。

### Hook 首页
1. 已安装应用搜索/筛选/列表；每项显示包名、Hook 状态和授权状态。
2. 应用详情页：广告 Hook、自定义 Hook、GKD 规则、Dia 工具、应用更新/VPN/隐私检测。
3. Frida 环境与注入会话、DEX/Activity/文件/so/JSON/Inspector、监控事件、日志、Dialog/按键 Hook。
4. 每个工具显示“环境未就绪/未授权/不兼容/已注入/执行失败/运行中”等真实状态。
5. 不出现来源应用启动器，不打开第二 APK。

### 脚本首页
1. 脚本库/规则库、搜索、分类、导入/新建、编辑、版本和启停。
2. 平台筛选与兼容等级；区分可解析、部分 API、完整 API、不可执行。
3. 运行任务、定时、MITM 事件、浏览器 UserScript、扩展管理。
4. 日志/调试/权限授权/超时与错误隔离。

### 设置首页
仅有：五种界面模式、壁纸、主题/动效、全局权限总览、统一备份恢复、通知/诊断偏好、许可证、关于。不得出现迁移应用、来源 APK 列表或业务配置。

## I. 交付验收矩阵与功能状态

每个功能拆成最小验收项，状态只能为：未检查、缺失、部分实现、已实现未验证、已验证、有意不迁移（附原因）。每项必须记录：
- UI 入口与 Tab/子页路径；
- 真实业务实现类、服务/进程、数据仓库和系统 API；
- 权限、生命周期、错误/超时/取消和回滚；
- 支持的 Android/ROM/内核/目标应用/浏览器版本；
- 单元测试、Host 回归、Android 测试、Gradle、安装、UI 自动化、真机证据；
- 来源版本与许可/版权要求；
- 未实现原因、限制和下一批具体文件。

**本节只建立需求基线和验收方法，不把任何未验证项目自动标为已完成。**


## 2026-11-05 — 小火箭功能对标等级修正：完整能力，不接受“相似版”

用户明确要求：FX 的小火箭类 VPN 功能不能只做到界面相似、基础代理相似或“有同类功能”，必须按 Shadowrocket 可公开验证的功能逐项建立能力基线，并在 FX 中实现真实等价能力；不允许把“相似”作为交付完成标准。

### 强制验收原则
- **功能等价而非外观相似**：每项能力必须有可操作 UI、配置模型、真实执行路径、运行状态、错误处理、日志/诊断、持久化和自动化/人工测试证据。只有入口、开关、配置解析或文档说明一律不算实现。
- **建立完整 Shadowrocket 能力矩阵**：以可公开查证的 Shadowrocket 官方说明、配置格式/示例和实际可复现行为为基准，按功能域列出每项能力、FX 对应实现类/服务/内核 API、兼容等级、缺口、测试用例和证据链接。不得凭记忆声称“全功能”。遇到无法核验的版本特性，标记“待核实”，不能猜测。
- **覆盖域至少包括**：节点/服务器管理与订阅；全部已声明协议及其传输/认证参数；策略组与节点选择；直连/全局/规则路由；域名/IP/CIDR/进程/应用规则；规则集下载、更新、优先级、覆写和命中解释；DNS 上游、分流、缓存、映射、DoH/DoT（仅按内核真实能力）；URL Rewrite/重定向；脚本和定时任务；HTTP 请求/响应处理；MITM、证书生命周期及脚本回调；按应用代理/绕过；连接/请求/流量日志、统计、延迟测试；网络切换、自动重连、断线保护和防泄漏；配置导入/导出、远程配置更新、变量/模块和错误诊断。清单须继续依据 Shadowrocket 可核验功能扩展，不能把此处列举当作上限。
- **多生态不是只认文件后缀**：Shadowrocket、Loon、Surge、Quantumult X、Stash、Egern、Clash/Mihomo、sing-box 等每种格式分别建立 Parser、语义适配层和 Runtime 能力矩阵；“成功导入”不等于规则、脚本或策略实际兼容。对语义不等价项必须显示明确降级和转换报告。
- **多内核必须真实可切换**：每个内核单独列出 ABI、版本、协议、规则、脚本、DNS、TUN/透明代理、MITM hook 能力；切换要验证启动、流量接管、规则执行、崩溃恢复和配置回滚。不得用单一内核的 UI 别名伪装多内核。
- **第三方 VPN 共存独立验收**：优先 Root/系统网络栈级数据面，不抢占 Android VPN 槽；按完全并行、受支持链式、部分兼容、不兼容逐设备记录。不能宣称所有第三方 VPN 均可透明共存。
- **测试分层**：单元测试验证 parser/规则/API 语义；集成测试验证内核进程和真实数据面；设备测试验证 DNS/IPv4/IPv6/WebRTC 泄漏、断线保护、网络切换、应用分流、第三方 VPN 共存、MITM 证书行为和耗电。静态 grep/页面可见/导入成功均不得标记“已验证”。
- **完成状态**：每项仅能标记未检查、缺失、部分实现、已实现未验证、已验证、受平台限制（附设备/版本/限制证据）。只有功能矩阵所有基线项有真实实现或有证据的明确平台限制，才允许称“Shadowrocket 核心能力完整对标”；未覆盖项必须公开列出，不得用“类似小火箭”替代。

### 开发执行顺序
1. 先审计现有 VPN/Root Proxy/内核/配置/规则/脚本源码和已有测试，形成“已存在代码 vs 真正执行路径”矩阵；不从零重写已有能力。
2. 先补数据面 P0：内核启动/停止、路由接管、UID/app 分流、DNS、IPv4/IPv6、防回环、崩溃回滚、第三方 VPN 共存。
3. 再逐项补齐 Shadowrocket 配置语义、协议参数、策略组、规则、脚本 API、Rewrite、MITM 与诊断。
4. 每完成一个功能域，提交源码和对应自动化测试；同步更新实时状态，但不得只更新文档。



## 新增来源：qufz / AntiFraudBlock（归入隐私 Tab）

来源仓库：`https://github.com/vip-svip/qufz`，默认分支 `main`。核验时仓库 README、源码、Manifest、Xposed 元数据、逆向记录与 MIT License 已读取。其当前实现不是通用反诈扫描器，而是一个 LSPosed/libxposed modern 模块，目标包严格限定为 `com.coloros.phonemanager`（OPPO/ColorOS 手机管家）。

### 真实能力与适用边界
- 产品目标：将该能力作为 FX「隐私」Tab 内的完整反诈组件隐私控制方案，而不是资料展示页。优先提供组件识别、数据流透明化、权限与官方隐私选项管理、用户授权状态、诊断数据分类、风险提示和一键恢复。必须保留本地风险检测、诈骗识别、风险通知、弹窗、用户主动提交的举报/求助及本地记录。不得通过 Hook 屏蔽安全告警、检测结论、用户主动举报或安全处置链路；对可选诊断/分析数据，只能在系统/组件提供明确用户关闭选项或有明确授权依据时执行相应控制，不得伪造上报成功、篡改风险结果或隐藏组件运行状态。
- 源码入口：`module/src/com/eta/afb/MainHook.java`。
- Hook 链路：`AiDetectStatistics` 的 static void 上报入口；`AiVoiceDetectDCSUtils.m/n`；以及 `TrackApi.E` 对 `appId=20092` 且事件名命中反诈前缀/清单时的兜底拦截。
- 逃生阀：`/data/local/tmp/afb.disable` 存在时 Hook 透传。
- 目标作用域：`com.coloros.phonemanager`，包括该包子进程；不能默认扩展到小米、华为、三星或其他厂商。
- 仓库记录的实测环境仅为 RMX5200 / ColorOS 16 / Android 16 / PhoneManager 17.1.6。其他版本必须先核对目标类、方法签名和本地风险功能，不得宣称兼容。
- 当前 modern 模块使用 libxposed API 102（minApiVersion 101 / targetApiVersion 102），Manifest minSdk 33 / targetSdk 34；legacy API 82 版本已废弃，不迁入。
- 许可为 MIT。迁入代码时保留版权与许可声明。

### 强化后的可交付实现方案（必须落地，不是研究报告）

1. **设备识别与能力探测**：启动时枚举设备实际存在的反诈/安全组件，记录包名、版本、签名摘要、系统版本、相关权限、服务/进程可见状态及官方设置入口；所有读取均按 Android 权限与系统可见性限制执行。组件不存在时明确显示「未检测到」，不伪造检测结果。
2. **隐私数据分类**：把数据分为本地风险检测数据、用户主动提交的数据、必要安全运行数据、可选诊断/分析数据四类。FX 页面逐类说明用途、处理位置、可见控制项和影响；不得把所有通信笼统标成“遥测”后统一拦截。
3. **用户控制优先**：能通过系统设置或组件官方设置关闭的可选诊断/个性化数据，提供可跳转入口、当前状态读取和操作后复核；无官方关闭能力时如实显示「系统未提供可验证的用户关闭接口」，不伪造开关成功。
4. **Hook 安全边界**：保留 qufz 的源码审计与兼容性分析，但逐个核验 Hook 点是否属于可选诊断数据。不得仅凭方法名、事件前缀或 appId 推断其一定不是安全上报；未能证明不影响风险识别、告警、处置和用户求助链路的 Hook 点一律不启用。实现必须按版本白名单、签名/方法签名校验、进程范围和用户授权状态生效。
5. **透明状态与回滚**：卡片展示组件是否存在、兼容性、官方控制状态、LSPosed 状态、模块状态、实际生效状态、最近错误和恢复入口；提供总开关、逐组件开关、立即停用、恢复原状及重启后状态核验。关闭后必须验证控制逻辑停止，不得只改变 UI。
6. **版本适配**：OPPO/ColorOS 的 qufz 适配仅作为一个独立适配器；其他厂商必须各自建立适配器与证据，不得复用 OPPO 包名、类名或方法签名。未知版本默认关闭并提示原因。
7. **验收与交付**：分别验证组件识别准确性、官方设置跳转、权限状态读取、隐私分类展示、开关状态持久化、停用回滚、本地风险提醒/通知/记录/用户主动举报完整性，以及不支持设备的安全降级。Host 静态检查、Android 构建、模拟环境测试和对应厂商真机测试分层记录；没有真机证据不得标为已验证。

### FX 页面归属与整合要求
- 用户入口放在第三 Tab「隐私」内，作为独立功能卡片：**反诈遥测保护 / AntiFraudBlock**。展示支持状态、目标包检测、LSPosed 框架/模块启用状态、Hook 注入状态、命中统计、最近错误与紧急停用状态。
- 不新增独立来源 APK 启动入口，不在设置页增加“迁移应用”；不得把 qufz 独立 APK 当作 FX 已整合完成。
- 将其 Hook 逻辑整合进 FX 统一 LSPosed/libxposed 模块交付链；若当前工程尚无可承载 modern Xposed metadata 的统一模块产物，先补统一模块封装与构建，不得通过伪造 FX 主 APK 的普通按钮冒充注入。
- 功能必须按设备能力自动判定：目标包不存在/不是 ColorOS/版本不匹配/LSPosed 未安装或未启用/作用域未授权/Hook 失败时，显示明确原因并保持关闭；不得尝试对其他厂商包名盲目 Hook。
- 保留本地诈骗提醒、风险弹窗、检测服务和记录数据库；只阻断已核验的遥测链路。禁止用粗暴全局拦截影响普通统计、电话、通知或系统安全服务。
- 设置独立总开关、立即停用/恢复透传、版本兼容检查和回滚；默认先关闭，用户确认启用后才生效。禁用状态必须真实透传，不得只改变 UI。
- 隐私说明必须明确：这是减少特定手机管家遥测上报的设备端 Hook，不等于阻止运营商、第三方应用或系统其他组件收集/上传数据，也不保证反诈检测本身关闭。

### 验收清单
1. 对支持设备检查 LSPosed modern 模块元数据、作用域和实际注入日志；确认只 attach `com.coloros.phonemanager` 及其子进程。
2. 分别验证 `AiDetectStatistics`、`AiVoiceDetectDCSUtils.m/n` 和 `TrackApi.E` 的目标事件拦截；非反诈 appId/事件必须透传。
3. 验证本地诈骗检测服务、通知、弹窗和记录页正常工作。
4. 验证 kill switch/FX 总开关关闭后所有 Hook 透传，重启和升级后状态正确恢复。
5. 在非 OPPO/ColorOS 设备、目标版本不匹配、LSPosed 不可用场景下安全降级，不崩溃、不显示虚假的“已保护”。
6. Host 静态测试、Android 构建测试、支持设备真机验证分开记录；不能以日志字符串或模块安装成功代替真实事件拦截测试。


## 用户功能大纲差漏补充（2026-11-05，本轮仅方案）

本节按用户最新五大功能域逐项对照本文件既有方案。已覆盖的项目不重复造轮子；仅补充此前未明确写出的缺口，并把无法作绝对承诺的系统限制写清楚。

### 本轮差漏结论

- **Ad**：本地 DNS、Hosts 重定向、应用层 Hook、Accessibility 辅助、TUN/代理过滤五层及游龙广告插件完整功能矩阵，已有明确条目；本轮不重复。
- **VPN**：去广告协同、小火箭类功能、指定防泄漏测试地址、低耗电常驻优化、MITM/HTTPS 证书管理及 MITM Script，已有明确条目；本轮补充“证书常驻信任”和“MITM 流量检查按需启用”的区别。
- **隐私**：FX 原隐私功能、游龙安全护盾、Root/模块/LSPosed 状态与兼容管理已有条目；不承诺对安全检测绝对隐身，也不提供规避金融、支付、反作弊、反诈或设备完整性控制的隐藏方案。
- **Hook**：广告、Dia、GKD、应用更新/VPN/隐私状态检测、开屏广告和位置模拟已有条目；此前没有单独明确“VIP 功能 Hook”的合法边界，本轮补充。
- **脚本**：Loon/Shadowrocket 等脚本真实运行、MITM 脚本、浏览器 UserScript/WebExtensions 已有条目；按宿主真实 API 能力实现，不承诺对所有 Android 浏览器全局注入。

### 5.4 Hook：VIP/会员状态相关扩展（新增差漏项）

- 支持对用户拥有或获准测试的应用进行会员状态接口观察、Hook 调试、状态可视化、测试桩/mock entitlement、回归测试和自有应用授权流程验证。
- 仅在应用开发者授权、用户拥有测试权限或开源许可明确允许的范围内启用；记录目标包名、版本、方法签名、执行通道、规则来源和回滚方式。
- **不实现绕过第三方付费墙、伪造付费凭证、解锁未购买会员权益、破解签名/服务端订阅校验或规避授权服务器的功能。** 对第三方商业应用仅允许做不改变授权结果的兼容性观察与诊断。
- UI 必须区分“观察/测试模拟”和“真实授权”，不得将本地 mock 状态显示成真实会员权益；服务端授权仍由服务端决定。

### VPN：证书常驻与 MITM 开关语义补充

- 证书管理器可以在用户明确安装并信任后持续维护 CA 的安装状态、有效期、指纹、备份、轮换、撤销和卸载状态；这不代表 MITM 必须对所有流量持续解密。
- MITM 默认关闭；用户按目标应用/域名/场景显式授权后才检查对应 TLS 流量。可设置受控规则保持某些目标的 MITM 常开，但必须有清晰状态指示、快速总停用和回滚。
- 系统证书信任不等于所有浏览器/应用必然接受该 CA。证书锁定、自定义信任库、QUIC/HTTP3、客户端认证和 Android/OEM 安全策略可能阻止解密；失败时如实显示，不伪造“无警告/无感成功”，也不以关闭校验或削弱 TLS 安全换取兼容。
- 系统级证书部署只在设备/Android 版本明确支持、用户授权且有可恢复路径时启用；不得保证所有设备永久信任或完全无感。

### Hook/隐私/位置相关全局验收补充

- 每条 Hook 规则必须标注目标应用、版本范围、所需权限、实际执行通道（Root/LSPosed/Accessibility/测试接口）、是否改变应用行为、失败回退和卸载清理方式。
- 应用更新检测、VPN 状态检测、隐私行为检测以可观察、可解释、可授权的诊断为默认；不得伪装设备状态或帮助绕过第三方服务的安全/风控校验。
- 自定义位置只用于自有设备和获准测试；使用系统支持的模拟位置机制，界面明确标记模拟状态。不得承诺与真实 GNSS、基站、Wi-Fi、IP、传感器及账号环境不可区分。
- 本轮只是方案差漏补充，不代表 Hook、MITM、证书、位置模拟或任何业务源码已经实现/通过真机验证。

## 国家反诈中心与手机厂商反诈组件：隐私审计、用户控制与 FX 集成

### 目标与边界

本节目标是研究国家反诈中心 App 的公开资料，并审计用户设备上**实际存在**的手机厂商内置反诈/安全组件，梳理可复核的权限、运行状态、数据访问和网络通信证据，再将经过验证、合法且用户有权控制的隐私管理能力整合进 FX 隐私 Tab。**用户明确说明自己从未安装国家反诈中心 App，设备上也没有安装该 App；因此它不是用户设备的实测对象，绝不要求用户安装。**国家反诈中心 App 仅作为独立的公开资料研究对象；只有其他设备样本或公开证据可用时才做版本分析。**FX 不新增诈骗识别、诈骗号码/网址判定或替代国家反诈中心的业务。**

设备实测对象必须先通过设备包清单/系统信息确认确实存在，再按设备厂商、机型、Android/ROM 版本、组件包名、版本号和签名分别记录；不得把某一品牌/版本的结论推广到其他设备。系统组件、预装应用和第三方 App 分开建档。国家反诈中心 App 若在用户设备上未检测到，记录为“未安装/非本机审计对象”，不创建虚构的本机权限、进程、服务或通信记录。

审计只用于透明度、最小权限、数据访问说明和用户合法可用的隐私设置。不得提供用于逃避执法调查、规避反诈风控、阻断合法风险告警/求助、伪造设备状态或隐藏违法活动的定向 Hook、拦截或隐身功能；不得破坏系统安全服务。

### 1. 国家反诈中心 App 公开资料研究（非用户设备实测）

用户设备没有安装该 App。本节不安排安装、运行、抓包或真机动态测试，也不把它列入本机组件清单。仅在确有公开资料或独立合法样本时建立版本证据档案；没有证据的项目标记“公开资料未确认”，不得要求用户安装补样本。可研究的公开项目包括：
- **应用身份**：包名、版本、签名证书指纹、安装来源、安装路径、更新渠道、目标 SDK、Manifest 与实际安装版本是否一致。
- **权限**：Manifest 声明权限、运行时已授予权限、AppOps 实际模式、特殊访问权限分别列出；重点核对电话/通话状态、短信、联系人、通话记录、位置、相机/麦克风、通知、文件/媒体、后台运行及电池优化豁免等权限是否存在、是否授予、何时使用。不得把“声明权限”写成“已读取数据”。
- **后台运行**：盘点 Service/Foreground Service、JobScheduler/WorkManager、Alarm、BroadcastReceiver、ContentProvider、启动项、通知渠道、持久任务及进程唤醒；记录触发条件、前台/后台状态、运行频率、网络依赖和停止/重启行为。
- **应用扫描**：检查是否查询已安装应用、包可见性范围、安装/卸载事件监听、应用元数据读取、扫描触发时机、扫描结果本地存储和上传行为。区分系统允许的包可见性查询、用户主动发起扫描与持续后台枚举。
- **数据访问**：逐项检查联系人、通话/SMS 元数据、设备标识、位置、文件、剪贴板、通知、应用列表及其他可访问数据；记录数据来源 API、访问触发点、用途说明、保存位置、保留期限和删除方式。无法从静态代码或运行证据确认的字段标记“未知”，不得猜测。
- **通信行为**：记录请求域名/IP、协议、端口、DNS 解析、TLS 证书信息、连接时间、进程/UID、流量大小、触发操作和网络状态；在合法授权和可用条件下进一步分析请求路径、字段和响应。TLS 加密内容不可见时，只能报告元数据，不得推断具体上传字段。
- **用户可见行为**：核对通知、弹窗、风险提示、用户主动提交/举报、权限解释、隐私政策和撤回授权入口是否与实际行为一致。

### 2. 手机厂商内置反诈组件审计项目

覆盖系统应用、ROM 服务、设备管理/安全中心、电话/短信/联系人/应用安装链路中的相关组件，以及通过系统接口提供能力的服务端。每个组件单独记录：
- 包名、版本、签名、系统分区位置、是否为 privileged/system app、是否随 OTA 更新、所属系统服务和依赖关系。
- 实际运行的进程、Service、Job、Receiver、Provider、守护进程、Binder/AIDL 接口、系统广播订阅和启动触发条件。
- Hook/框架情况：只记录有证据的 Xposed/LSPosed/libxposed 模块、系统扩展点、注入入口或运行时拦截点；同时区分“代码中存在 Hook 代码”“模块已安装启用”“目标进程实际加载”“目标方法实际执行”四种状态。不得凭类名或字符串命中就断言 Hook 正在运行。
- 系统接口：记录调用的 Android Framework、Telephony、PackageManager、Accessibility、Notification、DevicePolicy、Network、ContentResolver 等 API/Binder 服务及其调用方 UID、权限前提和触发场景。
- 权限与数据流：把权限授予者、调用组件、数据源、处理组件、存储位置、网络目的端和用户可见结果串成数据流；对跨进程/系统服务调用标注证据缺口。
- 组件间关系：区分本地规则判断、云端查询、系统电话/短信联动、厂商安全中心展示和第三方服务调用；不将整个厂商安全套件统称为一个反诈进程。

### 3. 权限与用户控制分级

每项能力必须归入以下类别，并附设备/版本实测证据：

| 类别 | 判定标准 | FX 展示与处理 |
|---|---|---|
| 用户可撤销授权 | Android 设置中可由用户撤销的运行时权限或特殊访问 | 显示当前授权状态、官方设置入口、用途和撤销后影响；由用户自行确认更改 |
| 官方设置可关闭 | App/厂商系统设置明确提供的功能开关或退出选项 | 显示官方入口、开关作用范围、恢复方式和可能影响；不模拟点击或暗中改写 |
| 系统级/受保护组件 | 依赖 privileged 权限、系统签名、设备管理、系统服务或 ROM 集成 | 标记系统级与普通 App 的差异；只提供状态说明和官方支持的管理方式，不承诺可卸载/禁用 |
| 需厂商/管理员授权 | 由设备管理策略、企业管理、家长控制或厂商服务控制 | 显示策略来源与联系管理员/厂商的正规途径，不绕过管理策略 |
| 证据不足/用途未知 | 静态或动态证据不足以判断真实用途、触发条件或控制入口 | 明确显示“未知/待验证”，禁止自动给出关闭建议或监控结论 |

关闭或撤销任何项目之前，必须说明具体影响，例如：来电/短信风险提示可能减少、应用扫描不再运行、用户主动举报/求助入口不可用、系统安全中心状态变化、通知/告警减少、后台耗电或网络流量变化。影响必须基于对应版本证据；未知影响明确标注未知。保留官方恢复路径和变更前状态记录。

FX 不提供批量强制禁用、隐藏组件、伪造服务停止状态、阻断安全告警、绕过设备管理或规避合法监测的功能。对可撤销权限，FX 仅提供说明和跳转官方系统设置；若未来支持直接调用 Android 授权 API，必须遵守平台授权流程并由用户逐项确认。

### 4. 网络与遥测审计方法及证据等级

通信分析必须采用多证据交叉验证，不能以域名出现、DNS 查询或单次连接作为“监控/上传个人数据”的结论。每条通信记录至少包含：设备与 ROM 版本、组件包名/UID、采集时间、触发操作、域名/IP、协议、TLS 状态、方向、字节数、频率、关联权限/API、证据来源及置信等级。

通信分类：
- **必要服务**：有可验证的核心功能依赖或官方文档/代码路径支持，例如更新、配置下发、用户主动请求的风险查询或必要的服务可用性请求。说明为何必要及停止后的可观察影响。
- **可选遥测**：有代码、文档或可重复动态证据表明用于诊断、统计、体验改进等非核心目的；记录是否有官方关闭选项、关闭后影响和是否仍有必要请求。
- **用途未确认**：只有域名/IP/流量元数据，或缺少调用链、字段内容、官方说明和可重复触发证据。必须保持未知状态，不得标为监控、数据出售或隐私泄露。
- **敏感数据传输已验证**：只有在合法授权下取得请求内容/字段、调用链或服务端协议证据，并能关联具体数据来源时才可使用此结论；同时记录字段、目的、加密状态、触发条件和证据范围。

证据等级：E0（仅域名/IP/字符串线索）；E1（可重复观察到进程/UID 发起连接）；E2（关联到触发操作、权限或 API 调用链）；E3（验证请求字段/数据内容及接收端）；E4（多次复现并由代码、官方资料或独立证据交叉印证）。结论必须写明等级和限制。TLS pinning、加密载荷、系统权限边界或无法复现导致的盲区必须明确披露，不得通过削弱 TLS 校验来获取证据。

对流量做对照实验：基线空闲、启动应用、打开具体功能、授予/撤销单项权限、关闭官方可选开关、网络切换和应用更新后分别采样；每轮记录设备状态和时间窗口。尽量使用本地采集、最少化保留和脱敏样本，不上传用户真实联系人、短信、通话记录或其他敏感内容。

### 5. FX 隐私 Tab 集成

新增隐私 Tab 内部页面“反诈与系统组件审计”，不是新主 Tab，也不是诈骗识别模块。页面至少包含：
1. **组件清单**：只列出本机 PackageManager/系统信息实际检测到的应用和厂商组件，按包名/版本/签名分组，区分普通应用、预装应用和系统组件。国家反诈中心 App 若未安装，只在独立的公开资料研究区标记“本机未安装”，不得混入本机实测列表。
2. **权限面板**：声明权限、实际授权、AppOps、特殊访问和最近可观察访问分别显示；不能把声明权限等同于已使用。
3. **后台运行面板**：显示已验证的服务、任务、接收器、进程和触发条件；注明静态发现还是动态运行证据。
4. **数据访问地图**：以“数据源 → 调用组件 → 本地处理/存储 → 网络目的端 → 用户可见用途”展示已验证链路；未知环节用未知标记。
5. **通信与遥测报告**：按必要服务、可选遥测、用途未确认、敏感数据传输已验证分类，展示证据等级、采样时间、限制和原始记录摘要。
6. **用户控制指南**：对每项列出控制类别、官方设置路径、关闭影响、恢复方法；只有用户有权控制且 Android/厂商官方支持的项目才提供设置跳转。
7. **审计记录与导出**：保存版本化报告、证据引用、用户操作记录和撤销/恢复说明；导出前脱敏，默认不收集或上传原始敏感数据。

所有状态必须由 PackageManager、AppOps、Usage/系统允许的诊断接口、进程/服务观测和用户授权的网络诊断结果实时或按采样时间读取。没有权限或平台 API 不允许读取时显示“不可观测”，不能伪造完整状态。不得把扫描结果接入 FX 诈骗识别、号码拦截或自动风险判定。

### 6. 验收标准

- 至少选定明确的 Android 版本、设备型号/ROM 和**本机实际存在**的厂商组件版本建立可复现样本；不同厂商分别验收，不外推。国家反诈中心 App 的公开资料研究与设备实测分开记录，不以用户安装该 App 作为验收前提。
- 权限清单同时包含声明、授予、AppOps 和实际调用证据；每项标注来源和时间。
- 后台服务清单区分静态声明、安装状态、实际运行和实际触发，不能混为一谈。
- 应用扫描结论必须说明查询范围、触发方式和是否上传扫描结果；无法确认上传内容时标记未知。
- 每条通信结论必须附进程/UID、触发场景、元数据或载荷证据、等级与限制；域名本身不能作为监控结论。
- 每个可控项目必须有官方设置入口、撤销影响和恢复路径；系统级或管理员管理项目明确标记不可由 FX 控制。
- FX 页面不得提供规避执法、反诈风控或设备管理策略的隐藏/拦截能力；不得把隐私审计包装成诈骗识别。
- 未完成动态采样、无法访问载荷或没有真机证据的条目必须标记“待验证/不可观测”，不得标记审计通过；对本机不存在的 App/组件标记“未安装/未检测到”，不要求用户安装。

## 安全执行边界（Safe Execution Boundaries）

本节适用于所有接手 FX 的 AI、自动化工具和协作者。安全边界不应成为停止正常开发的借口；在授权范围内应继续完成可安全执行的工作，并在遇到真实阻断时说明原因和替代路径。

1. **先检查，再修改**：操作前读取目标分支、最新提交、目标文件当前内容及相关工作区状态。以当前远端内容为基线；不得覆盖、丢弃或擅自重置未审查的现有改动。
2. **限定授权范围**：只操作 FX 仓库及用户明确授权的关联资源。不得擅自访问、修改或删除无关仓库、账户、设备数据或第三方资源。
3. **高影响/不可逆操作先确认**：删除或清空数据、重写 Git 历史、强制推送、覆盖发布版本、执行不可逆数据迁移、刷写分区、修改启动链或可能导致设备无法启动/断网的操作，必须先说明具体影响、恢复方案并取得用户确认。普通可回滚的源码编辑、测试和非破坏性提交可在授权范围内继续。
4. **代码与依赖安全**：不执行来源不明或未经检查的二进制文件、脚本和安装器。审查新增依赖、构建脚本、模块安装/卸载脚本及下载来源；避免恶意代码、后门、供应链风险和不必要的权限扩大。
5. **凭据与隐私保护**：不得读取、输出或提交真实密码、访问令牌、私钥、签名密钥及其他秘密。不得将凭据写入源码、日志、测试报告或构建产物；测试使用虚拟凭据或安全注入的临时凭据。
6. **Android/设备安全**：不得擅自关闭 SELinux、绕过 Android 平台权限边界、破坏系统安全服务或执行高风险系统修改。系统应用部署、privileged 权限、签名、SELinux 策略和开机服务必须遵循设备实际支持的机制；不得把放入 system 分区等同于自动获得平台签名或特权权限。
7. **VPN、DNS 与网络保护**：不得擅自接管、断开、重置或覆盖用户现有 VPN、DNS、路由和防火墙配置。只增删 FX 自己创建且可识别的规则；保存变更前状态，提供精确清理和回滚。不得使用全局 flush 等方式清空第三方规则。
8. **测试与外部目标边界**：优先使用静态检查、单元测试、隔离环境和模拟测试。未经明确授权，不扫描、攻击、压测或探测第三方设备、服务和网络；不访问无关用户数据。
9. **Git 写入与提交**：写入前核对目标分支和文件最新版本；提交前检查完整 diff、敏感信息、意外删除和测试结果。禁止未经确认强制推送、重写历史或覆盖他人提交。若远端内容已变化，先重新读取并合并差异，不得盲目覆盖。
10. **真实状态与证据**：明确区分已实现、部分实现、待实现、静态检查、主机测试、模拟测试和真机验证。没有实际执行的测试不得报告通过；没有设备证据不得声称真机兼容。
11. **遇到限制时继续安全推进**：若某项操作需要额外权限、设备确认或存在平台硬限制，暂停该项高风险动作，说明阻断点，并继续处理不受影响的源码、文档、测试或替代实现；不得通过规避安全机制来伪造完成。
12. **安全目标限制**：不得实现隐藏诈骗活动、规避合法反诈风控、逃避执法监测、破坏/屏蔽系统安全告警、伪造安全状态、绕过第三方付费授权或窃取凭据的功能。允许开展透明的权限审计、隐私说明、合法用户控制、授权测试和安全回滚。

