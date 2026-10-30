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
