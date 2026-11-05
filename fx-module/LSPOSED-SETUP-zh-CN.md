# FX 1.0.0：LSPosed 安装边界说明

FX 安装时会自动尝试安装 `FXAdHook.apk` 作为普通 Android 应用，并把 FX 的目标配置写入模块配置。**这不等于 LSPosed 框架或 LSPosed 管理器已安装。**

KernelSU 本身没有内置 Zygisk。LSPosed 必须依赖兼容的 Zygisk 实现，且需要把框架作为独立模块安装并重启；FX 无法安全地从自己的安装脚本里无条件刷入框架，因为框架版本、Android 版本和 Zygisk 实现不兼容时可能导致模块不启动甚至开机异常。

官方资料：
- LSPosed 项目及安装说明：https://github.com/LSPosed/LSPosed
- KernelSU FAQ（Zygisk/LSPosed）：https://kernelsu.org/guide/faq

检查顺序：
1. 在 KernelSU 中安装与设备当前 Android 版本匹配的 ZygiskNext。
2. 再安装明确支持当前 Android 版本的 LSPosed 框架模块并重启。
3. 打开 LSPosed 管理器，启用 `FXAdHook`，选择同样的目标 App Scope。
4. 在 FX 的 Hook 页面选中这些 App 并启用 FX Hook 主开关，然后强行停止并重新打开目标 App。
5. FX 状态页“目标已发布”只表示配置写入 Remote Files 成功，不能证明 Hook 已注入。

本项目不会自动刷入官方旧版 LSPosed 框架。当前打包环境无法在 OnePlus 12 真机上确认兼容性，不能声称 LSPosed 框架已自动安装。
