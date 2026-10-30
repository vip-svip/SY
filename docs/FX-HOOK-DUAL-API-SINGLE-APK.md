# FX Hook 单 APK 双 API 兼容性审计（2026-10-30）

## 当前事实

- API 82 旧入口位于本地原始工作树 `lsposed/app`，包名 `de.privacyguard.hook`，入口 `de.privacyguard.hook.MainHook`，注册文件 `assets/xposed_init`。
- 旧模块使用 `de.robv.android.xposed:api:82`（compileOnly），Java 11，minSdk 27；Manifest 含 `xposedmodule`、`xposedminversion=93`、`xposedscope` 元数据。
- API 101 新入口位于 `adhook/app`，包名 `de.privacyguard.adhook`，入口 `de.privacyguard.adhook.AdVisibilityHook`，注册文件 `META-INF/xposed/java_init.list`。
- 新模块使用 `io.github.libxposed:api:101.0.1`（compileOnly），Java 17，当前 minSdk 28；`module.prop` 声明 `minApiVersion=101`。
- 两套 Hook 当前不是一个 APK；仓库云端验证分支目前只包含 API 101 项目。API 82 完整源码仍在 FX 工作树中，尚未同步到该分支。

## 可行的单 APK 方向（待验证）

把两套入口、配置适配层和模块元数据合入同一个 Android application：
1. 统一 applicationId、版本号、图标、设置页和目标应用配置。
2. 同时保留 `assets/xposed_init` 与 `META-INF/xposed/java_init.list` 两种入口注册。
3. 同时提供旧框架需要的 Manifest 元数据和现代框架需要的 `module.prop/scope.list`。
4. 同时以 compileOnly 引入 legacy API 82 与 libxposed API 101，禁止将框架 API 类打入 APK。
5. 旧框架走 MainHook；API 101+ 框架走 AdVisibilityHook。两条入口必须通过同一配置模型协调，且不能在同一进程重复安装等价 Hook。
6. 先将 minSdk 统一评估为 27；不能仅凭 API 库可编译就宣称 Android 8.1 真机兼容。

## 必须验证的兼容性矩阵

| 框架环境 | 预期加载入口 | 必须通过的验证 |
|---|---|---|
| Legacy Xposed/LSPosed API 93–100 | `assets/xposed_init` | 模块可发现、入口实例化、作用域可配置、配置可读、Hook 可启停 |
| libxposed API 101+ | `META-INF/xposed/java_init.list` | 模块可发现、入口实例化、Remote Files、动态作用域、Hook 可启停 |
| API 101+ 但旧 Manifest 元数据同时存在 | 现代入口优先 | 不因旧元数据而被拒绝或重复加载 |
| 同一 APK 跨框架升级/降级 | 对应单一入口 | applicationId/数据目录/配置不丢失 |

## 关键风险

- API 101 不再注入 Zygote，生命周期与 legacy API 不同；不能把旧入口机械包装成新 API。
- 两种入口可能被不同框架版本识别，但必须实测模块发现与加载行为；目前没有证据证明仅把两个 metadata 文件放入 APK 就足够。
- 新 API 的 Remote Files 配置与旧 API 的 `/data/local/tmp/privacyguard/xposed.conf` 不是同一配置通道。需要统一 schema 和双端读取/生成适配。
- 同一进程内只能有一条等价 Hook 注册路径；需要共享 Hook feature registry 或明确分区，防止重复拦截。
- 不能把 API 101 APK 的成功构建当作 API 82/API 101 已合并。

## 当前结论

采用“单 APK、双入口、共享配置协议”的方案继续做原型验证；在旧框架与新框架加载矩阵验证通过前，不宣称已合并，也不替换现有 Hook APK 或 FX KernelSU ZIP。

## 新增审计结果

- API82 入口已在本地工作树预备统一 appId：`SELF_PKG=de.privacyguard.adhook`，同时继续排除旧包名 `de.privacyguard.hook`，防止升级后旧 Hook 将统一 Hook 自身纳入作用域。
- API82 的 `MainHook` 仍在 `handleLoadPackage` 中按包回调安装一批进程级 Hook；共享进程中多个包的回调归属可能不明确。该风险尚未修复，不能将 API82 直接并入生产 APK。
- API101 本地精确源码快照已在 Actions run `41043234124` 编译、单元测试、签名和元数据检查全部通过；APK 仍是 API101 验证产物。
- 目前未完成旧框架 API 93–100 与现代 API 101+ 的实际框架加载测试。双入口文件同时存在仅证明 APK 可打包，不证明两类框架都会正确识别或只加载一条入口。


## 2026-10-30 追加：旧入口共享进程风险与框架识别依据

### API82 旧入口代码审计

- `MainHook` 在 `handleLoadPackage` 中把包名写入实例字段 `pkg`，而不是每个回调使用不可变的局部目标上下文。
- 当前文件中，设备标识伪装、包查询过滤、广告 ID 等 Hook 回调会读取 `pkg`。如果框架在同一进程为多个包复用同一模块实例，后一次回调可能覆盖前一次包名，产生跨包策略串用。
- 旧入口没有可靠的进程内包身份注册表，也没有“共享 UID/多包进程 fail-open”的统一门禁。不能假定 API82 进程中永远只有一个 package。
- API101 端的传感器、剪贴板、Android ID 和动态 ClassLoader 观察已加入多包进程 fail-open 条件；API82 端尚未完成等价迁移。

### 框架官方接口差异

- LSPosed 现代模块文档明确区分旧 `assets/xposed_init` 与现代 `META-INF/xposed/java_init.list`，并要求现代入口继承 `XposedModule`，使用新的 interceptor chain API。参考：https://github.com/LSPosed/LSPosed/wiki/Develop-Xposed-Modules-Using-Modern-Xposed-API。
- libxposed API 101 明确不再注入 Zygote，模块只在作用域进程内加载。参考：https://libxposed.github.io/api/io/github/libxposed/api/XposedInterface.html。
- 现实项目已有“现代标准包 + 旧框架 Legacy 包”的分发做法，例如 DPIS 的模块版本说明；这说明分开构建是可行且常见的兼容路线，但不能据此断言双元数据单 APK 不可能。参考：https://modules.lsposed.org/module/io.github.kwensiu.dpis/。

### 当前决策

- 仍以用户要求的“一个 Hook 应用”为目标：统一 UI、配置 schema、applicationId 和发布版本。
- 单 APK 双入口保留为待验证原型，不直接认定可用。必须检查 API101 框架是否同时把同包识别为现代模块与 legacy 模块，是否触发双重入口；还必须确认 API93–100 能否忽略现代资源并正常加载 legacy 入口。
- 在框架源码/真实框架测试给出确定结论前，不将两个入口合并到生产 APK。若同包双识别导致重复加载，优先寻找框架侧单入口选择机制；不能靠运行时猜测框架版本或吞异常掩盖双重注册。
- 下一项代码工作：把 API82 的 `pkg` 字段依赖列出逐个迁移为 final package-scoped context；对无法准确归属调用方的进程级 Hook 先 fail-open。随后添加多包模拟回归测试。


## API82 shared-UID fail-open patch (local source; cloud build pending)

- Local working-tree `lsposed/app/.../MainHook.java` now checks `lpp.appInfo.sharedUserId` at the very start of `handleLoadPackage`. If a shared UID is declared, it logs `shared UID process: legacy hooks disabled` and returns before loading configuration or installing any Hook.
- This is deliberately conservative: packages declaring a shared UID lose API82 Hook features rather than risk process-global package attribution leaking one target's policy into another. Normal single-UID apps continue through the existing path.
- Local regression `scripts/tests/v1.0.0-api82-shared-uid-fail-open-regression.sh` passed. MainHook SHA-256: `af70deb28288105c6698deba134123d565552e90d1fb7317c02ea85b96a7c412`; regression SHA-256: `8791e0eb0b0464237485b8594c0881e4784985ad39dce50e3316e8e3bd66dc0c`.
- This change is not yet compiled against the legacy API82 Gradle project and is not yet part of the API101 GitHub artifact. Treat it as a locally patched source plus static regression only, not as a verified legacy APK.
