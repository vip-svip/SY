# FX 1.0.0 收尾状态报告（实测）

生成时间：2026-11-08
范围：本轮「补完历史所有没做的」全部工作 + 全量验证结果

## 一、全量验证：7 项检查，失败 0

| 检查项 | 结果 | 实测数据 |
|---|---|---|
| 全部 shell 脚本语法 | PASS | 508 个 `sh -n` 全通过（跳过 1 个 patch 片段） |
| 二进制 sidecar 一致性 | PASS | 7 个二进制 sha256 全部匹配 |
| 随包 APK 一致 | PASS | overlay == optional，13.0 MB |
| 规则清单规模 | PASS | `dns/block.txt` 330,436 行 |
| rule_set 齐全 | PASS | 4 份全部存在且非空 |
| 后端可达性 | PASS | 65 个：App 31 / 生命周期 33 / 开发 1 / **未接线 0** |
| 六种 UI renderer | PASS | 5 个 renderer 类（+ Classic WebUI 包装） |
| 打包产物 | PASS | 225.1 MB |

## 二、本轮修掉的真实缺陷（不是重构，是坏掉的东西）

### 语法错误 4 处 —— 脚本根本无法运行

| 文件 | 错误 | 原因 |
|---|---|---|
| `adguardhome.sh:245` | `syntax error near unexpected token '('` | awk 单引号块内字符串含撇号 `&'()*+,;=%` |
| `yulong-ad-dns-summary.sh:81` | 同上 | awk 块内注释写了 `AdGuard Home's` |
| `yulong-app-firewall.sh:268` | `syntax error near unexpected token '}'` | `resolve_uid()` 后残留重复块（7 行） |
| `fx-unified-navigation-regression.sh:24` | 引号错位 | `for file in $manifest" "$shell"` 应为 `"$manifest" "$shell"` |

### 死路径判断 4 处 —— 永不执行或永久阻塞

本地 DNS 已换 fxdns，`$PG/adguardhome/managed.pid`、`$PG/unbound/managed.pid` 永不创建：

- `apply.sh:4005` 拿它们当动作前置条件 → 死分支
- `localdns-watchdog.sh` 3 处守卫 → watchdog 永不启动

改为判断 `$PG/dns/fxdns.pid` / `fxdns.conf`。保留设置项名 `dns_engine_adguardhome`（它是 settings.conf 的键，改名会丢弃用户已保存的选择）。

### emit-rulesets 目录守卫错误 1 处

守卫检查 `rulefiles/`，但规则集在 `rulesets/` → 函数直接 return 0，输出空串。退出码 0 却什么都没声明。

### 33 万条清单未接入 1 处

`adblock_merged.json`（330,436 域名 / 6.9 MB）不在遍历列表里，随包最大清单等于没生效。

### sidecar 缺失 2 处

`bin/arm64/pg-mitm.sha256` 用二进制模式写入（`<hash> *file`），校验器按字面比较 → 哈希一致却报 MISSING。`bin/arm/pg-mitm` 完全没有 sidecar。

### CI 与二进制脱节 6 处

6 个 workflow 仍在构建 AdGuard Home / unbound，而 `bin/` 下这两个二进制**为 0 个文件**。已删除。

## 三、GitHub Actions 的真实状态

**本仓库 CI 不可用**，逐层查证：

| 证据 | 值 |
|---|---|
| 最近 30 次 run | success=0, failure=30 |
| job.runner_name | 空 |
| job.started_at → completed_at | 2 秒 |
| job.steps | 空数组（无任何 step 执行） |
| 日志 API | `BlobNotFound` |

结论：runner 从未被分配，属账户/仓库层额度或计费限制，**不是 workflow 语法问题**。

因此"自动打包"改在本地完成：
- `fx-module/scripts/autopackage.sh` —— verify / build / size 三个动词
- `runner/package_module.py` —— 实际打包（本机无 zip 工具，用 Python 实现）

新增 `fx-package-verify.yml` 只做**可校验的事**（sidecar、APK 一致、清单规模、rule_set 齐全、全量 `sh -n`），且刻意设为 `workflow_dispatch` 手动触发 —— 基础设施问题不该在每次 push 上制造红叉。

## 四、打包产物（不限制数量与大小）

```
fx-module/dist/FX-1.0.0-kernelsu.zip
  条目        1,314 个（模块树全部文件）
  原始        272.7 MB
  压缩        225.1 MB（83%）
  sha256      745ba1c03105f7fb…
```

策略：已压缩的大件（sing-box 78.9 MB、qjs、pg-mitm、两个 APK）用 **stored** 不重复压缩；文本按 deflate-9。脚本按 `.sh` 与顶层名单标记 0755（实测 508 个全部可执行）。

`dist/` 已加入 `.gitignore`，225 MB 产物不入库，可按需重新生成。

## 五、必须说明的边界

**一、未在真机刷入。** 包结构、权限、内容一致性已校验，但没有设备验证。

**二、APK 是 unsigned release。** 本机无 keystore，CI 也不可用，因此没有签名版。

**三、所有延迟数字是 Python 复现同算法所得，不是 C/Go 真机实测。** 本机无 Linux、无 Go、NDK 无 Windows libc，arm64 二进制无法执行。

**四、MITM 的 50000 条上限未改。** 我试过改 Go 常量，但无 Go 工具链无法编译验证，已完整回滚 —— 不引入未经编译验证的 Go 代码。改为在 shell 层用 `rulepriority.sh` 排序降低截断损失。

**五、`imported/*` 与五包 8.5 万类的差距仍在。** 组件级覆盖不等于代码级移植，这一点在早前的报告里已写明。

## 六、验证可复现

```
python runner/final_verify2.py        # 7 项全量检查
sh fx-module/scripts/autopackage.sh verify
python runner/package_module.py       # 打包
python runner/verify_package.py       # 包结构校验
```
