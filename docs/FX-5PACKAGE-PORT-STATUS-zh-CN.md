# 五个反编译包的移植状态（实测）

生成时间：2026-11-08
方法：从 `vip-svip/APK` release `1.0.0` 用 HTTP Range 读取各 zip 的中央目录与
`AndroidManifest.xml`，按清单组件（Activity / Service / Receiver / Provider）逐一对照
FX 实现。未下载整个压缩包（277MB，链路实测约 22KB/s）。

## 一、五个包的真实形态

| 资产 | 大小 | 包名 | 反编译形态 | 应用类数 |
|---|---|---|---|---|
| `Dia_23.11_src.zip` | 50.0MB | `dialog.box` | 30098 个 .smali | 15027 |
| `GKD-XA_1.4.8_src.zip` | 33.4MB | `li.songe.gkdx` | 12290 个 .smali | 8548 |
| `_10.10.62_src.zip` | 52.7MB | `com.v2cross.proxy` | 9505 个 .smali | 9208 |
| `_7.0.1_src.zip` | 44.7MB | `com.youlong.ad` | 8374 个 .smali | 5878 |
| `_9.9.60_src.zip` | 96.6MB | `com.youlong.hd` | 37766 个 .smali | 9416 |

**五个包全部是 smali 反编译，没有一个带 Java 源码。** 这一点决定了移植方式：不能按类
名对照，只能按清单组件（功能的真实边界）对照。

## 二、按组件的覆盖矩阵

| 包 | 组件 | 有实现 | 框架基础设施 | 缺口 | 未判定 | 覆盖 |
|---|---|---|---|---|---|---|
| Dia | 69 | 64 | 1 | 2 | 2 | 94% |
| GKD-XA | 30 | 18 | 4 | 6 | 2 | 73% |
| v10.10.62 (v2rayNG) | 72 | 42 | 25 | 1 | 4 | 93% |
| v7.0.1 (玉龙广告) | 20 | 8 | 10 | 0 | 2 | 90% |
| v9.9.60 (玉龙安全) | 44 | 28 | 13 | 1 | 2 | 93% |
| **合计** | **235** | **160** | **53** | **10** | **12** | **90%** |

「框架基础设施」指 FileProvider、AndroidX Startup、androidx.work、Firebase、Sentry、
Play Core、Shizuku Provider、Room 等第三方管道组件 —— 它们不是应用功能，不构成缺口。

## 三、明确的 10 项功能缺口

| 包 | 组件 | 缺什么 |
|---|---|---|
| Dia | `MicroCommunityActivity` | 社区/论坛浏览 |
| Dia | `MarkdownActivity` | Markdown 渲染查看 |
| GKD-XA | `SelectToSpeakService` | 选中朗读无障碍服务 |
| GKD-XA | `EventService` | GKD 事件源 |
| GKD-XA | `TrackService` | GKD 事件追踪 |
| GKD-XA | `ExposeService` | GKD 暴露端点 |
| GKD-XA | `PrivilegeAdbPairingService` | ADB 无线配对（Shizuku 式提权） |
| GKD-XA | `PrivilegeHandshakeProvider` | 权限握手 Provider |
| v10.10.62 | `PayReturnActivity` | 支付回跳处理 |
| v9.9.60 | `PiracyWarningActivity` | 盗版警告页 |

## 四、需要说明的判断

**1. VPN 组件按内核路径计为已覆盖。** v2rayNG 的 `V2RayVpnService`、
`ManagedConfigDnsService0..3` 是 Android `VpnService` 的按网络注册；FX 走内核
（sing-box + TUN + 共存仲裁），不使用 VpnService 槽位，因此这些组件在 FX 中没有同名
对应物，但能力等价。这不等于"移植了 v2rayNG 的 Java 实现"——FX 用的是自己的 shell +
sing-box 路径。

**2. smali 到 Java 的逐类移植没有做。** 目前 FX 的 92 个 `imported/*` 类继承自已合并的
旧分支代码，不是本轮从这五个 zip 里抽取的。若要按类移植，需要先把目标类从 smali 反编译
成 Java（jadx 逆向）再重写，工作量按类计。

**3. 覆盖率是"组件级"的，不是"代码级"的。** 一个 Activity 在 FX 中有对应实现，不代表
该 Activity 的全部功能、全部分支都已移植。真实代码级覆盖率需要逐类比对，本轮未做。

## 五、下一步可选路径

1. **补齐 10 项缺口**：其中 6 项在 GKD-XA，需要 ADB 配对与事件链路，工作量最大
2. **按类移植关键类**：先从 `com.youlong.hd` 的分应用联网控制、`dialog.box` 的规则引擎
   开始，这两处是功能密度最高的
3. **核对 v2rayNG 的协议覆盖**：FX 的 vpncore.sh 已支持 18 个协议，可与 v2rayNG 的
   `com.v2ray.ang` 配置解析逐项对比

## 六、复现方式

```
python runner/pull_manifest.py <包名>     # 从远端 zip 取 AndroidManifest.xml
python runner/matrix_final.py             # 输出本报告的矩阵
```

缓存文件在 `F:\BUG\fxwork\src5\`：`<包名>-AndroidManifest.xml`、`<包名>-entries.json`。
