# FX 1.0.0 — 安装包权限元数据修复记录（2026-10-27）

## 发现与修复

最新 UI 修复 ZIP 在重新打包时丢失 UNIX executable mode：service/customize/apply、QuickJS、sing-box、MITM 和脚本调度/同步入口都被标成 0644。该问题会令直接执行入口在解包后失败，即使源码语法测试通过。

本包重建 ZIP 时保留原已验证包中的 UNIX mode 元数据；仅为新增的回归脚本按 0755 设置权限，文档按 0644 设置。没有覆盖原有包。

## 安装包验证

- 通过 ZIP 目录校验并重新解包检查执行权限。
- 安装树权限回归覆盖 service.sh、customize.sh、action.sh、uninstall.sh、apply.sh、QuickJS、sing-box、MITM、HTTP 桥、订阅同步与调度入口。
- QuickJS 二进制 SHA-256 与包内 sidecar 比对。
- 随后在重新解包的新包树上执行全套 v1.0.0 回归。

## 边界

这是安装包元数据与主机回归验证；没有在 OnePlus 12 真机执行安装、SELinux、DNS/VPN/MITM 实流验收。
