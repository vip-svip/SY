

### FX 模块应用白名单批量事务 AWK 分区匹配修正（2026-11-07）

- 代码提交：`3a5ef228a9aa6ac960990fd5626842b79023e7d0`。
- 文件：`fx-module/scripts/yulong-app-whitelist.sh`。
- 删除批量白名单事务 AWK 程序中残留的旧 section 匹配行，避免与新匹配条件叠加形成不完整的 AWK 模式/动作块。
- 保留模块版批量添加/移除、PackageManager 过期项清理、锁、配置快照与失败回滚实现；未将较短的规范脚本覆盖模块版。
- 按用户要求未执行白名单脚本、测试、静态检查、构建、CI 或设备验证。

### FX Unbound 私有状态目录权限失败关闭（2026-11-07）

- 代码提交：`2f5b0ef5996ace336f12e72002c7660f8bdf0177`。
- 文件：`fx-module/scripts/unbound.sh`。
- `_prepare_state_dirs()` 不再忽略 `chmod 700` 失败；无法确保 Unbound 状态目录与工作目录为私有权限时，立即中止启动并给出明确错误。
- 避免在目录权限未收紧的情况下继续使用可能包含解析器状态与缓存数据的目录；原有路径符号链接检查、运行文件 SHA-256 校验和健康探测逻辑不变。
- 按用户要求未执行 Unbound 脚本、测试、静态检查、构建、CI 或设备验证。


### FX 模块应用白名单批量事务 Shell 续行修正（2026-11-07）

- 代码提交：`40a63fd20d7b40a8709bfaa2e6c7c7419f267fe3`。
- 文件：`fx-module/scripts/yulong-app-whitelist.sh`。
- 修正批量添加/移除与过期项清理事务中的四处多重行尾反斜杠，将 Shell 命令续行恢复为单个反斜杠，避免续行符被转义后导致后续 `&&` 条件链脱离原命令。
- 保留现有批量名单写入、PackageManager 快照校验、锁内事务、配置备份与 apply 失败回滚实现。
- 按用户要求未运行脚本、测试、静态检查、构建、CI 或设备验证。


### FX 模块应用防火墙 UID 在事务锁内二次核验（2026-11-07）

- 代码提交：`b475885e4694aab1de44d1c965afdf26d9768e76`。
- 文件：`fx-module/scripts/yulong-app-firewall.sh`。
- 在 `mutate_transaction()` 已取得防火墙配置锁后，对 `set_item_value` 与 `set_rule_value` 再次读取 PackageManager UID 快照并核对包名/UID。
- CLI 入锁前校验仍作为快速拒绝；锁内复核消除等待锁期间应用卸载或 UID 变化导致陈旧 UID 写入配置的窗口。其他事务操作不受影响。
- 按用户要求未运行脚本、测试、静态检查、构建、CI 或设备验证。


### FX 模块 DNS reconcile 与设置写入统一串行化（2026-11-07）

- 代码提交：`e331d1383af6ecaa34bb68915125aee6e4e733f1`。
- 文件：`fx-module/scripts/native-dns-settings.sh`。
- 将 `reconcile` 从无锁直接调用改为通过既有 `with_lock` 执行 `reconcile_locked`，使完整 DNS 服务协调与 `set` / `set-many` 设置事务共用同一把锁。
- 避免用户触发的重新协调与并发设置写入交错执行，减少旧配置运行态覆盖新配置的竞态窗口；状态输出仍在协调成功后返回。
- 按用户要求未运行脚本、测试、静态检查、构建、CI 或设备验证。


### FX AdGuard Home 私有状态目录权限失败关闭（2026-11-07）

- 代码提交：`ebebf3e26999f90913452462d6e7b2b2cd916eb8`。
- 文件：`fx-module/scripts/adguardhome.sh`。
- 将状态目录与工作目录的 `chmod 700` 从忽略失败改为失败关闭；无法收紧目录权限时，停止后续配置渲染和服务启动并报告错误。
- 与 Unbound 对应的私有目录保护保持一致，避免在权限未能收紧时继续使用包含 DNS 配置、缓存和运行状态的目录。
- 按用户要求未运行 AdGuard Home 脚本、测试、静态检查、构建、CI 或设备验证。


### FX Unbound 配置文件私有权限依赖安全暂存（2026-11-07）

- 代码提交：`05ca5a85220ddba33641d67dd10f9d9293762072`。
- 文件：`fx-module/scripts/unbound.sh`。
- 移除配置原子替换后重复执行且忽略失败的 `chmod 600`；配置文件在写入前已由 `_new_private_temp()` 使用 `umask 077` 创建并强制设置为 600，原子重命名会保留该权限。
- 避免权限设置失败被静默忽略，同时不引入配置文件删除/重建窗口。AdGuard Home 对应路径已采用明确失败返回，无需重复修改。
- 按用户要求未运行脚本、测试、静态检查、构建、CI 或设备验证。


### FX AdGuard Home 配置原子发布保留私有权限（2026-11-07）

- 代码提交：`bc1a02c2328206d22c285dc3d0a824fbf1c06867`。
- 文件：`fx-module/scripts/adguardhome.sh`。
- 移除配置文件原子重命名发布后的重复 `chmod 600`；渲染文件由 `_new_private_temp()` 在发布前通过 `umask 077` 创建并强制设为 600，原子重命名保留其权限。
- 避免配置已发布后因冗余权限命令失败而使启动流程报错，同时不增加配置删除/重建窗口。
- 按用户要求未运行 AdGuard Home 脚本、测试、静态检查、构建、CI 或设备验证。
