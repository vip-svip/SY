# SY v2 重建方案（MagicNet 契约）

> 本文件记录架构决策与迁移动因。Hindsight 知识库当前不可用（API key 未配置，401），
> 因此决策记录在本仓库内，可追可查。

## 一、为什么要重建（真机实测证据，非推测）

设备：小米 23076RA4BC ／ Android 13 (SDK 33) ／ arm64-v8a ／ KernelSU ／ MIUI V140。

| # | 旧架构断点 | 真机证据 | 后果 |
|---|---|---|---|
| 1 | **DNS 拦截从未生效** | 引擎生成 hosts 12 行，但 `/system/etc/hosts` 仍是 3 行 localhost；
|   |                     | 模块 `system/` overlay 里**没有** `etc/hosts` 副本；测试规则在系统 hosts 里 0 条 | 所有 DNS/hosts 拦截形同不存在 |
| 2 | 内核无法执行 | `bin/sing-box` 在 ZIP 内是 `100644`；重启后 KernelSU 按 ZIP 权限重挂，
|   |              | `chmod` 白做 → `can't execute: Permission denied` | 代理内核、防泄露全部不可用 |
| 3 | 开机脚本无环境 | `service.sh` 只 source 配置、未 source `common.sh` → `bg_spawn: not found` | 守护进程起不来 |
| 4 | **mksh 参数展开差异** | Android sh 是 MIRBSD KSH R59：`${x%%\|*}` / `${x##*\|}` **返回空**
|   |                        | （本机 ash/busybox 上正常） | offline/ruleset 的 4 处解析全空 |
| 5 | 断网判据全错 | 旧版读 `/proc/net/route` 找 `00000000`（Android 多路由表，默认路由不在该文件）
|   |              | 且读 `net.dns1`（Android 10+ 已废弃，实测为空） | 有网也报 `no-route` |
| 6 | 本机 IP 取错 | `ip route get 1 \| awk '{print $7}'` 依赖固定字段位；真机多了 `table` 字段 | 面板显示 `wlan0` 而非 `192.168.0.16` |
| 7 | dpm 子命令不存在 | Android 13 的 `dpm` 只有 `help`/`is-operation-safe`；`dpm list packages` 返回用法文本 | 体检把帮助文本当设备管理员列表 |
| 8 | `grep -c` 双输出 | `grep -c` 无匹配时输出 0 但退出码 1，`\|\| echo 0` 追加一行 | 变量含换行，显示成两行 |

结论：旧架构不是"缺功能"，而是**多个断点叠加导致功能只生成不生效**。

## 二、重建目标（按 MagicNet 契约）

```text
WebUI / App / CLI
      |
      v
  统一控制面（机器可读 JSON，schema=1，状态与错误都可解析）
      |
      v
  文件型状态平面（一域一文件、原子替换、可回滚）
      |
      v
  显式数据面（tun / 用户态端口；不再依赖"挂载 hosts 就算完成"）
```

### 硬性契约（照搬 MagicNet 的失败边界）

1. **进程存活 ≠ 就绪**：`service.status` 分三层报告（process / api / dataplane），
   只有 `api.ready && dataplane.ready` 才算 ready；**未知一律不升级为就绪**。
2. **进程与资源按精确归属识别**：不用 `pkill -f sing-box` 这种模糊匹配清理无关进程。
3. **配置激活要事务**：候选 → `sing-box check` → 原子替换；失败保留上一份可用配置。
4. **数据面必须可验证**：TUN 看接口是否真在 sysfs；用户态看端口是否真在监听。
     不再把"写了配置文件"当作"生效"。
5. **DNS 必须真的接管**：要么挂载到 `/system/etc/hosts`（并验证挂载生效），
     要么走 sing-box 的 DNS 路径（并验证解析确实被改写）。**验证不到就报未就绪**。

## 三、用户要求的功能（全部登记，逐项验收）

| 要求 | 落地方式 | 验收判据 |
|---|---|---|
| 三份规则内置 | `rulesets/builtin/{watermark,antiadblock,noappdownload}.txt` | 文件在包内、面板可读 |
| 规则可查看/编辑/启停 | 每份规则一个独立页：开关 + 内容编辑 + 生效统计 | 面板能改、状态能读、**按生效方式分开统计** |
| `##` 元素隐藏生效 | MITM 注入 CSS（需根证书 + 目标域匹配） | 面板显示"实际注入条数"，不是"配置条数" |
| 三层规则都要生效 | hosts 类走 DNS；网络类走 DNS/iptables；`##` 类走 MITM | 三类各自独立统计与状态 |
| FX 深度抵抗完善 | 上报端点 + 安装清单收敛 + 能力面 | report 如实列出做了/没做 |
| 三份归档内容内置 | GuardShield / privacy-guard-extension / privacy-guard-skill | 规则与脚本并入，App 侧脚本并入 APK |
| 堆栈式导航（类微信） | 入口 → 工作区 → 子页，返回逐层回退 | 真机返回键逐层可退 |
| App 承载 Xposed + 无障碍 | `SYManager.apk` 双通道，各自开关 | 真机验证 Hook 生效与无障碍跳广告 |

## 四、验收纪律

- 每项功能**在真机上验证**，不靠"静态检查通过"就宣布完成。
- 无法验证的（如需另一台设备、需特定 ROM）**如实标注**，不编造。
- 已确认不成立的路径（如"只写 hosts 文件不挂载就宣称 DNS 生效"）**直接删除**，
  不留着当空壳。
