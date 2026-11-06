# FX QuickJS-NG 脚本运行时

- 引擎：QuickJS-NG v0.17.0，Android `arm64-v8a`，最低 Android API 24。
- 入口：`sh scripts/jsruntime/runner.sh <脚本.js> [事件.json]`。
- 手动运行入口：`sh scripts/jsruntime/runner.sh <脚本.js> [事件.json]`；相对路径从 `/data/adb/privacyguard/scripts/` 解析，偏好数据写入 `/data/adb/privacyguard/jsruntime/prefs.json`。
- MITM 实时请求/响应钩子目录：`/data/adb/privacyguard/jsruntime/scripts/`。已启用的 HTTPS 脚本订阅会由 `sync-subs.sh` 下载到该目录，逐文件 SHA-256 校验；失败时保留最后一次有效缓存。脚本必须在文件开头添加 `// FX-SCRIPT-TYPE: request|response|both` 与 `// FX-SCRIPT-MATCH: <正则>` 两行；引擎启动时读取，匹配 URL 后在请求发送前或响应返回前执行，`$done({url,method,headers,body})` 的受支持字段会回写当前 HTTP/1.1 流量。修改 URL 只允许同源，避免绕过 TLS SNI/Host 校验。MITM 在每个新 TLS 连接开始时重载 hook 清单；已有 TLS 连接不会在请求之间重新载入。
- 事件 JSON 可提供 `request` 与 `response` 对象；脚本可读取全局 `$request`、`$response`。
- 启用的 HTTPS 脚本订阅由 `sync-subs.sh` 更新到 `/data/adb/privacyguard/jsruntime/scripts/`；只激活带 `FX-SCRIPT-TYPE` + `FX-SCRIPT-MATCH`，或带 `@match` / `@include` / `@url` HTTPS URL 元数据的脚本。更新文件会写入本地 SHA-256 sidecar，加载时重新核对；更新失败时尽可能恢复上一份有效文件。MITM 每个新 TLS 连接重新读取 hook 清单，成功刷新后不必重启监听器。开机服务会启动轻量轮询器，默认每 24 小时刷新一次；`script_auto_update_h` 可配置为 1–168 小时。
- 宿主 API：`$done(value)`（首次调用生效；无参数时提交当前 `$request` 或 `$response` 对象）、`$prefs`、`$persistentStore.read/write/remove`、`$httpClient` 常见 HTTP 方法回调、`$task.fetch(...).then(...).catch(...)`、`$notify` / `$notification.post` 通知记录、`$environment` / `$script` / `$argument` / `$input`，以及 `$surge` / `$loon` / `$stash` / `$rocket` 的有限兼容别名。
- HTTP bridge 仅允许 `http://` 与 `https://`，单次 `$httpClient` 请求超时会限制在 1–20 秒、响应最多 8 MiB；为了防止不同 `wget` 实现的重定向协议限制不一致，HTTP bridge 没有 curl 时会失败关闭，不再回退到 wget。脚本订阅下载同样要求设备有 `curl`。
- **安全边界（FX 加固版 QuickJS-NG）：** 宿主预加载可信桥接代码并捕获内部 `std` / `os` 引用后，运行时会在模块缓存查询之前拒绝 `qjs:std`、`qjs:os`、`qjs:bjson` 动态导入，并拒绝加载 `.so` 原生模块；全局别名仍会隐藏。回归探针验证了绕过路径被拦截，同时 `$task.fetch`、`$prefs`、`$done` 正常工作。此改动关闭的是这条特权模块导入路径，**不是 Android/内核级进程沙箱**：脚本仍能经 FX 暴露的 HTTP API 发请求并修改自身偏好设置，因此订阅脚本仍应只使用可信来源，不能把本改动描述成对任意恶意代码的完整隔离。

## Egern 脚本兼容入口（扩展子集）

- 运行器支持顶层默认导出的异步或同步函数，包括带函数名的形式；请求/响应上下文只在 HTTP request/response 事件中提供。
- 提供 ctx.script、ctx.env、ctx.app、ctx.device、ctx.cron、ctx.widgetFamily、ctx.request、ctx.response、ctx.http、ctx.storage、ctx.notify 和 ctx.log。对请求/响应对象的受支持修改会作用于原始 Hook 对象，并通过 $done() 结果回传。
- HTTP 支持 GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS；响应提供 status、headers、text() 和 json()。请求头支持多值；存储支持 get、set、getJSON、setJSON 和 delete；HTTP 超时按毫秒接收并由 FX 限制。
- `FX-SCRIPT-NAME` 会映射到 `ctx.script.name`；`FX-SCRIPT-ENV-JSON` 会并入 `ctx.env`，事件自身环境字段优先。设备、cron 和 widget 字段仅透传事件实际提供的值。通知目前写入 FX 脚本日志，不会调用 Android 通知栏。
- 当前是 Egern 兼容子集：不支持 ESM import、流/二进制正文、SSH、lookupIP、压缩、ctx.respond()、ctx.abort()、重定向策略、代理策略和 Egern 私有网络服务；HTTP 底层同步执行，只提供 Promise 兼容层。
- 文件导入器识别 `.yaml` / `.yml` 的 `scriptings:`：只迁移 `http_request` / `http_response` 的 HTTPS `script_url`，支持 `name`、`match`、`disabled` 与 `body_required`；重复项按 URL/类型/匹配式/正文标记去重。
- `schedule`、`generic`、`network` 不会伪装成 MITM HTTP Hook；带 `env`、`binary_body: true`、或非默认 `timeout` / `max_size` / `update_interval` 的记录会跳过，因为当前订阅协议不能无损保存这些配置。`body_required` 会编码为 FX 元数据并由订阅同步器生成 `FX-SCRIPT-REQUIRES-BODY` 标记。

## 明确的能力边界

额外提供 `$utils` 常用子集：Base64 编解码、URL 编解码、JSON parse/stringify、UUID 和持久化存储转发；`$httpClient` 请求超时会限制在 1–20 秒，并补充常见 `statusText`。这些 API 属于通用子集，不等于任一客户端的完整 API。

这是实际可执行的 JS 运行时与 HTTP 宿主桥接，并补充了常见跨客户端 API 适配层；不等于完整复刻 Shadowrocket、Surge、Loon、Stash 或 Quantumult X 的全部 API。`$task.fetch` 当前返回原生 Promise，但底层 HTTP 请求在返回 Promise 前同步完成，因此 Promise 链可以处理完成结果，却不代表真正的非阻塞网络 I/O。依赖定时器、WebSocket、二进制流、客户端私有对象或特定客户端扩展的脚本可能不兼容；每种 API 兼容性需要逐项实测。

实时钩子会下载已启用的脚本 URL；模块转换器支持识别常见 Surge/Loon 风格 `[Script]` 中的 `type=http-request|http-response`、`pattern`、`script-path=https://...`，并将触发条件编码为 FX 元数据。`#!url`、`#!name`、`#!desc` 等模块头信息会忽略；`requires-body=1` 的响应脚本会触发对匹配请求的 `Accept-Encoding: identity` 协商，尽力提供可编辑正文。脚本仍必须通过安全下载与元数据校验；缺少有效 FX 元数据或支持的 URL glob 的脚本会被跳过。请求/响应正文编辑限制为未压缩、可识别的文本/JSON/XML/form 类型且正文不超过 1 MiB；二进制、压缩正文或超限正文不做正文改写。MITM 脚本执行目前采用 25 秒单脚本硬时限，并受 30 秒共享阶段总时限约束；多个脚本匹配同一 URL 时执行耗时会累加，不再以 32 个为固定加载上限。若多个脚本同时匹配同一 URL，执行耗时会累加，因此应避免大量重复匹配。MITM 本身仍只支持 TCP/443、TLS HTTP/1.1，不支持 QUIC/HTTP3、证书固定绕过、客户端证书或自定义 TLS 栈。`$task.fetch` 返回原生 Promise，QuickJS 会处理常规 Promise job；但网络请求在 Promise 创建前同步执行，因此不具备真正的非阻塞网络 I/O。`$notify` / `$notification.post` 当前将通知写入 FX 的 `notifications.jsonl`，并不调用 Android 系统通知栏；`$surge` / `$loon` / `$stash` / `$rocket` 只是有限别名，不含各客户端全部模块、策略组、数据库、脚本配置和 UI API。定时器、WebSocket、二进制流与客户端私有 API 仍不保证兼容。第三方脚本需逐个适配与真机验证，不能宣称 Shadowrocket / Surge / Loon / Stash 全量兼容。

## Surge/Loon [Script] 模块导入

- 在脚本中心使用“从文件导入脚本”，选择 `.conf`、`.ini`、`.sgmodule` 或 `.loon` 文件。
- 导入器只迁移 HTTPS `script-path` 且声明 `http-request` / `http-response`、`pattern` 的条目，转为 FX `FXMETA_B64` 触发元数据并写入统一脚本列表。
- 元数据按真实换行编码为四个字段：触发类型、URL 正则、是否需要响应正文、脚本显示名称；旧的两字段元数据仍可读取。同步器会输出 FX-SCRIPT-REQUIRES-BODY 与 FX-SCRIPT-NAME 头，导入名称可在列表中显示和编辑而不丢失原触发条件。导入器只迁移 `[Script]` 中具有 HTTPS `script-path`、`type=http-request|http-response` 与 `pattern` 的 HTTP 触发脚本，并将触发类型与 URL 匹配表达式封装为 FX 元数据。
- Surge/Loon 仅导入带 HTTP 触发类型与 URL 匹配条件的 HTTPS 脚本；不自动导入任务、定时任务、本地相对路径或非 HTTPS 脚本。
- 同一导入器也识别 Quantumult X `[rewrite_local]` 中的 `script-request-header`、`script-request-body`、`script-response-header`、`script-response-body` 与 `script-analyze-echo-response`，转换为 FX 请求/响应阶段元数据；仅接受 HTTPS 脚本 URL，普通 URL Rewrite / reject 动作不会被当作脚本执行。
- 响应正文与请求正文动作会保留正文需求标记；脚本名称、触发阶段、URL 正则和正文需求可在列表中展示/编辑。支持从 `.qxconf` 文件导入。

## Egern `scriptings` YAML 导入

- 脚本中心提供独立的“导入 Egern YAML HTTP 脚本”入口，支持 `.yaml` / `.yml` 文件（文件读取上限 2 MiB）。解析器迁移顶层 `scriptings:` 中的 `http_request` 与 `http_response`，保留名称、URL 匹配、HTTPS 脚本地址和禁用状态。
- 支持简单扁平字符串 `env` 键值映射，写入订阅脚本头并透传到 QuickJS 的 `ctx.env`；最多 32 项、单值 512 字符、总 JSON 2048 字符。嵌套对象/列表和无法表示的 env 结构会跳过该条目。
- `body_required: true` 对 `http_request` 与 `http_response` 项均保留，并映射为 `FX-SCRIPT-REQUIRES-BODY`；仍受 FX 未压缩文本类型和 1 MiB 正文限制。含 `binary_body: true` 的条目跳过。
- `schedule`、`generic`、`network` 不会转换为 HTTP Hook；仅接收 HTTPS 脚本 URL。Egern 的 `timeout`、`max_size`、`update_interval` 等参数不假定已经映射为 FX 控制项。
- 该导入器仅覆盖上述 HTTP YAML 子集，不是通用 YAML 解析器，也不代表 Egern 全功能运行时。

## Stash HTTP YAML 脚本导入

- 脚本中心可导入 Stash YAML：读取顶层 `http.script` 与 `script-providers`，按 provider 名称解析 `url`，仅迁移 HTTPS request/response 脚本并写入统一 `[list:script]`。
- 支持 `match`、`type`、`require-body`、`disabled` 与 `argument`；参数会写入 `FX-SCRIPT-ARGUMENT` 并映射到 QuickJS 全局 `$argument` / `$script.argument`。正文需求生成 `FX-SCRIPT-REQUIRES-BODY`。
- 只接受默认兼容选项：provider `interval=86400`、脚本 `timeout=10`、`max-size=1048576`、`engine=auto`、`binary-mode=false`。本地 provider path、非 HTTPS URL、二进制模式、自定义引擎和非默认资源参数会跳过。
- Stash 的普通 `url-rewrite`、cron 任务、Python SCRIPT 规则和其他网络策略不会当作 JavaScript HTTP Hook 导入；这不是完整 Stash YAML 解析器。

## Native Script 混合清单批量导入

- FX JSON、Egern YAML、Surge/Loon 与 Quantumult X 的转换结果统一进入批量导入器；同一个清单允许 HTTPS 订阅 URL 与本地 JavaScript 源码混合，不再因为混入一个本地文件而退回逐项改写配置。
- UI 每批最多 512 条，并将 manifest 控制在约 7 MiB；模块端 add-batch 在单个脚本列表锁内处理 URL 与 SOURCE 两种记录，一次性提交该批 [list:script]。多批次依序推进，按批汇总新增、重复跳过及失败数。
- SOURCE 记录以 SOURCE|Base64(源码)|Base64(名称)|启用状态 传输；模块将源码保持文件流处理，按内容快照和名称去重，不将完整源码塞进 shell 变量。单文件上限 1 MiB；URL 仅接受 HTTPS，普通明文 HTTP 不导入。
- 配置批次仍以现有 settings.conf [list:script] 为唯一来源；批量接口不会另建第二份脚本数据库。模块脚本模板、运行时副本和构建恢复来源使用同一协议。
## 本地实时钩子脚本示例

```javascript
// FX-SCRIPT-TYPE: response
// FX-SCRIPT-MATCH: ^https://example\\.com/api/.*$
if ($response && $response.body) {
  $done({body: $response.body.replace('old-value', 'new-value')});
} else {
  $done();
}
```

请只放入你信任的脚本。匹配表达式按完整 URL 执行；缺少类型或匹配表达式的文件不会被自动执行。MITM 在每个新 TLS 连接开始时重载 hook 清单；已经建立的 TLS 连接不会在请求之间重新加载。第三方模块中的 `script-path` 与 `requires-body=1` 已按上述响应钩子路径处理；`timeout` 等客户端专有选项不会被完整模拟。导入的 `[MITM] hostname` 会同步到独立主机白名单，运行时只对精确主机名或明确的 `*.example.com` 通配子域做 TLS 解密；未命中、无 SNI 或清单异常时会原样透传，不会自动对所有 HTTPS 站点解密。用户仍需明确启用 MITM、安装并信任 FX CA；证书固定、QUIC/HTTP3、客户端证书或自定义 TLS 栈不保证兼容。

### 原生 URL Rewrite 执行引擎（实验性）

MITM 引擎可从 `/data/adb/privacyguard/mitm/url-rewrite.conf` 加载 URL 级规则，每行格式为 `<正则表达式> - <动作>`。支持 `reject`、`reject-200`、`reject-empty`、`reject-dict`、`reject-array`、`reject-img`，以及 `302`/`307` 后跟替换目标（支持 `$1` 等捕获组）。示例：

```text
^https://app\\.example\\.com/private(?:/.*)?$ - reject
(^https://app\\.example\\.com/old/)(.*) - 302https://app.example.com/new/$2
```

该文件只由 MITM 引擎在流量明确重定向到本引擎时执行；它不会自行开启流量重定向。第三方 `[URL Rewrite]` 可经 `modconvert.sh` 导入到独立 `[list:urlrewrite]`，由 `sync-urlrewrite.sh` 校验后原子发布；无效清单会记录错误并停用本次 URL Rewrite 规则，普通 HTTPS 转发仍继续。启用透明重定向前仍应确认 CA 信任、白名单范围和回退状态。当前引擎仅支持 IPv4 TCP/443 上的 TLS HTTP/1.1；不支持 QUIC/HTTP3、证书固定绕过或自定义 TLS 栈。
