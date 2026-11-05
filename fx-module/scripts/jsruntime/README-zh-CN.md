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

## 明确的能力边界

额外提供 `$utils` 常用子集：Base64 编解码、URL 编解码、JSON parse/stringify、UUID 和持久化存储转发；`$httpClient` 请求超时会限制在 1–20 秒，并补充常见 `statusText`。这些 API 属于通用子集，不等于任一客户端的完整 API。

这是实际可执行的 JS 运行时与 HTTP 宿主桥接，并补充了常见跨客户端 API 适配层；不等于完整复刻 Shadowrocket、Surge、Loon、Stash 或 Quantumult X 的全部 API。`$task.fetch` 当前返回原生 Promise，但底层 HTTP 请求在返回 Promise 前同步完成，因此 Promise 链可以处理完成结果，却不代表真正的非阻塞网络 I/O。依赖定时器、WebSocket、二进制流、客户端私有对象或特定客户端扩展的脚本可能不兼容；每种 API 兼容性需要逐项实测。

实时钩子会下载已启用的脚本 URL；模块转换器支持识别常见 Surge/Loon 风格 `[Script]` 中的 `type=http-request|http-response`、`pattern`、`script-path=https://...`，并将触发条件编码为 FX 元数据。`#!url`、`#!name`、`#!desc` 等模块头信息会忽略；`requires-body=1` 的响应脚本会触发对匹配请求的 `Accept-Encoding: identity` 协商，尽力提供可编辑正文。脚本仍必须通过安全下载与元数据校验；缺少有效 FX 元数据或支持的 URL glob 的脚本会被跳过。请求/响应正文编辑限制为未压缩、可识别的文本/JSON/XML/form 类型且正文不超过 1 MiB；二进制、压缩正文或超限正文不做正文改写。MITM 脚本执行目前采用 25 秒单脚本硬时限，并受 30 秒共享阶段总时限约束；多个脚本匹配同一 URL 时执行耗时会累加，不再以 32 个为固定加载上限。若多个脚本同时匹配同一 URL，执行耗时会累加，因此应避免大量重复匹配。MITM 本身仍只支持 TCP/443、TLS HTTP/1.1，不支持 QUIC/HTTP3、证书固定绕过、客户端证书或自定义 TLS 栈。`$task.fetch` 返回原生 Promise，QuickJS 会处理常规 Promise job；但网络请求在 Promise 创建前同步执行，因此不具备真正的非阻塞网络 I/O。`$notify` / `$notification.post` 当前将通知写入 FX 的 `notifications.jsonl`，并不调用 Android 系统通知栏；`$surge` / `$loon` / `$stash` / `$rocket` 只是有限别名，不含各客户端全部模块、策略组、数据库、脚本配置和 UI API。定时器、WebSocket、二进制流与客户端私有 API 仍不保证兼容。第三方脚本需逐个适配与真机验证，不能宣称 Shadowrocket / Surge / Loon / Stash 全量兼容。

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
