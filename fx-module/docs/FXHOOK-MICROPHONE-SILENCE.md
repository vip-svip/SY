# FXHook AudioRecord 麦克风静音迁移记录

日期：2026-10-30

## 实现范围

- 新增按目标应用启用的 `mic_silence=1` 配置，受 FX Hook 隐私总开关 `privacy_enabled` 控制。
- API-101 仅 Hook `AudioRecord.read` 的 byte[]、short[]、float[]、ByteBuffer 缓冲区重载。
- 原始 read 调用只执行一次；仅在返回正数时清零实际读取区域，保留 offset 和 ByteBuffer position 语义。
- 同一进程关联多个包名时 fail-open；注册异常时不阻断原始录音调用。
- UI 明确标注该功能不是 Android 麦克风权限关闭。

## 明确不覆盖

MediaRecorder、Camera/CameraX 音频、原生 NDK 采集、自定义音频驱动路径及其他未枚举 API。不能声称全局禁用麦克风，也不修改系统权限状态。

## 不迁移的旧行为

不迁移旧 API-82 的 `noise` 合成噪声、`audio_fp_block` 扰动、`mic_hw_hide` 硬件隐藏及 `startRecording()` 错误伪装。

## 检查结果

- Host shell 集成回归：通过。
- Java 缓冲区 smoke test（byte[]、short[]、ByteBuffer）：通过。
- Gradle / Android 编译与 JUnit：等待 GitHub Actions 结果。
- OnePlus 12 真机 LSPosed 注入：未验证。
