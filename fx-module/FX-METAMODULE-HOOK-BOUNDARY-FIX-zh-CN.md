# FX 1.0.0：两个 Hook 部署边界处理结果

## 处理结果

1. **Hook APK 不再要求 KernelSU metamodule 提供 `/system/priv-app` 挂载。** `FXAdHook.apk` 与旧 `PrivacyGuardHook.apk` 已放在 `optional/`；安装器使用 Android PackageManager 将其安装为普通应用，并校验 APK SHA-256、跳过未变化的 APK、更新后重装、失败重试并记录日志。安装失败不阻断 FX 主服务，也不修改 DNS、VPN、路由或防火墙。卸载脚本只卸载被 FX 安装器登记的应用。
2. **GitHub 源码 PR 已合并。** PR #1：<https://github.com/vip-svip/SY/pull/1>。合并提交：`554080bc01f38998951ca2c738499df3a015298d`。合并前的 GitHub Actions 构建验证成功：<https://github.com/vip-svip/SY/actions/runs/40549975411>；验证包含安装器回归、Hook parser 单元测试、APK 组装与签名检查。

## 当前验证

- 从最终 ZIP 重新解压后执行：旧测试集 229 项 + 新增 Hook 安装/升级/卸载测试 1 项，共 **230/230 通过**。
- 275 个 Shell 脚本通过 `busybox ash -n` 语法检查。
- 7 个独立 JavaScript 文件通过 `node --check`。
- 两个 Hook APK 的独立 SHA-256 清单均匹配；ZIP 完整性检查通过。
- `module.prop` 仍为 `id=privacyguard`、`version=1.0.0`、`versionCode=10000`。
- Hook APK 已不在 `system/priv-app` 下；包内唯一的 `system` 文件是 `system/etc/hosts`。

## 尚未宣称完成的验收

`system/etc/hosts` 的系统级覆盖仍依赖 KernelSU 兼容 metamodule 的挂载机制；本次解决的是 Hook APK 部署依赖，并未把系统 hosts 功能重构为本地 DNS 过滤。OnePlus 12 真机的 KernelSU 安装、PackageManager 安装、LSPosed 识别/注入、作用域生效和网络实际访问仍未现场验证，因此不能保证真机上绝对无故障。若 PackageManager 拒绝 APK，原因与日志应从 `/data/adb/privacyguard/adhook-install.log` 核对；主模块启动不会因 Hook 安装失败而被短路。
