# 系统证书根证书目录 (OverlayFS 叠加目标)
# MITM 首次启动时会在此生成 <hash>.0，重启后由 KernelSU OverlayFS 叠加到
# /system/etc/security/cacerts，使系统全局信任本模块的根证书。
# 该目录随模块挂载，无需修改系统分区。
