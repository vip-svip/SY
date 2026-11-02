package de.privacyguard.adhook

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.ComposeView
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.theme.ColorSchemeMode
import top.yukonga.miuix.kmp.theme.MiuixTheme
import top.yukonga.miuix.kmp.theme.ThemeController

private val FxInk = Color(0xFF17212B)
private val FxMuted = Color(0xFF718091)
private val FxBlue = Color(0xFF2878D0)
private val FxCanvas = Color(0xFFF2F5F8)
private val FxCard = Color(0xFFFFFFFF)

fun installFxNativeDashboard(
    view: ComposeView,
    pageIndex: Int,
    mode: String,
    onOpenHook: () -> Unit,
    onOpenSettings: () -> Unit
) {
    view.setContent {
        val controller = remember { ThemeController(ColorSchemeMode.System) }
        MiuixTheme(controller = controller) {
            FxDashboardPage(pageIndex.coerceIn(0, 3), mode, onOpenHook, onOpenSettings)
        }
    }
}

@Composable
private fun FxDashboardPage(
    page: Int,
    mode: String,
    onOpenHook: () -> Unit,
    onOpenSettings: () -> Unit
) {
    val glass = mode == "glass"
    val miuix = mode == "miuix"
    Column(
        Modifier.fillMaxSize()
            .background(if (glass) Color(0xFFEAF1F7) else if (miuix) Color(0xFFF1F4FA) else FxCanvas)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        when (page) {
            0 -> VpnPage()
            1 -> HostsPage()
            2 -> PrivacyPage(onOpenHook)
            3 -> ScriptPage()
        }
        Spacer(Modifier.height(84.dp))
    }
}

@Composable
private fun PageHeader(eyebrow: String, title: String, description: String) {
    Column(Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 4.dp)) {
        Text(eyebrow.uppercase(), color = FxBlue, fontSize = 11.sp, fontWeight = FontWeight.Bold)
        Text(title, color = FxInk, fontSize = 26.sp, fontWeight = FontWeight.Bold)
        Text(description, color = FxMuted, fontSize = 13.sp)
    }
}

@Composable
private fun FxCard(content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth()
            .background(FxCard, RoundedCornerShape(22.dp))
            .border(BorderStroke(1.dp, Color(0x142C4358)), RoundedCornerShape(22.dp))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) { content() }
}

@Composable
private fun FxPill(text: String, active: Boolean = false, onClick: (() -> Unit)? = null) {
    Box(
        Modifier
            .background(if (active) Color(0xFFE2F0FF) else Color(0xFFF0F3F6), RoundedCornerShape(50))
            .then(if (onClick != null) Modifier.clickable { onClick() } else Modifier)
            .padding(horizontal = 14.dp, vertical = 9.dp)
    ) {
        Text(text, color = if (active) FxBlue else FxMuted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun StatusLine(label: String, value: String, positive: Boolean = false) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = FxMuted, fontSize = 13.sp, modifier = Modifier.weight(1f))
        Text(value, color = if (positive) Color(0xFF16845B) else FxInk, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun VpnPage() {
    var enabled by remember { mutableStateOf(false) }
    var mode by remember { mutableStateOf("直连") }
    var node by remember { mutableStateOf("未选择节点") }
    PageHeader("Network", "VPN 控制中心", "原生页面布局 · 后端状态接入待后续迁移")
    FxCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("代理总开关", color = FxInk, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                Text(if (enabled) "界面预览：已打开" else "界面预览：已关闭", color = FxMuted, fontSize = 12.sp)
            }
            FxSwitch(enabled) { enabled = it }
        }
        StatusLine("运行状态", "尚未连接真实 VPN 后端")
        StatusLine("当前模式", mode)
        StatusLine("流量接管", "等待后端接入")
    }
    FxCard {
        Text("节点选择", color = FxInk, fontSize = 17.sp, fontWeight = FontWeight.Bold)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(node, color = FxInk, fontSize = 14.sp)
                Text("订阅节点列表将在原生数据层接入", color = FxMuted, fontSize = 11.sp)
            }
            FxPill("选择节点") { node = "节点选择器 UI 已打开" }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FxPill("导入订阅")
            FxPill("更新节点")
            FxPill("节点管理")
        }
    }
    FxCard {
        Text("代理模式", color = FxInk, fontSize = 17.sp, fontWeight = FontWeight.Bold)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("直连", "全局", "规则").forEach { item ->
                Box(Modifier.weight(1f)) { FxPill(item, mode == item) { mode = item } }
            }
        }
        Text("直连不需要节点；全局与规则模式需要有效节点。当前模式切换仅用于 UI 验收。", color = FxMuted, fontSize = 12.sp)
    }
    FxCard {
        Text("连接诊断", color = FxInk, fontSize = 17.sp, fontWeight = FontWeight.Bold)
        StatusLine("VPN 服务", "未连接")
        StatusLine("DNS", "未读取")
        StatusLine("上游延迟", "—")
        StatusLine("最近错误", "暂无")
        FxPill("查看连接日志")
    }
}

@Composable
private fun HostsPage() {
    var section by remember { mutableStateOf("本地 Hosts") }
    var query by remember { mutableStateOf("") }
    PageHeader("Filtering", "广告与 Hosts", "统一入口 · 本地 Hosts、订阅规则与系统 Hosts 分区管理")
    FxCard {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf("本地 Hosts", "订阅规则", "系统 Hosts").forEach {
                Box(Modifier.weight(1f)) { FxPill(it, section == it) { section = it } }
            }
        }
        Text(section, color = FxInk, fontSize = 18.sp, fontWeight = FontWeight.Bold)
        Text(
            when (section) {
                "本地 Hosts" -> "编辑设备本地 hosts 文本；与订阅规则分离。"
                "订阅规则" -> "管理导入的过滤订阅、更新时间与启用状态。"
                else -> "查看系统 hosts 当前状态、应用结果与回滚入口。"
            }, color = FxMuted, fontSize = 12.sp
        )
        BasicTextField(
            value = query, onValueChange = { query = it },
            modifier = Modifier.fillMaxWidth().background(Color(0xFFF2F5F8), RoundedCornerShape(12.dp)).padding(13.dp),
            singleLine = true,
            decorationBox = { inner -> if (query.isEmpty()) Text("搜索域名 / 规则 / 订阅", color = FxMuted, fontSize = 13.sp); inner() }
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FxPill("打开编辑器")
            FxPill("从外部编辑器同步")
        }
    }
    FxCard {
        Text("过滤总开关", color = FxInk, fontSize = 17.sp, fontWeight = FontWeight.Bold)
        StatusLine("当前状态", "等待读取模块状态")
        StatusLine("本地文件", "/system/etc/hosts")
        StatusLine("订阅规则", "未读取")
        StatusLine("上次应用", "—")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FxPill("保存")
            FxPill("应用规则")
            FxPill("回滚")
        }
    }
    FxCard {
        Text("常用管理", color = FxInk, fontSize = 17.sp, fontWeight = FontWeight.Bold)
        StatusLine("广告过滤", "统一管理")
        StatusLine("跟踪器拦截", "统一管理")
        StatusLine("自定义白名单", "可配置")
        StatusLine("规则冲突检查", "待读取")
    }
}

@Composable
private fun PrivacyPage(onOpenHook: () -> Unit) {
    PageHeader("Privacy", "隐私保护", "查看保护项目、权限状态与应用级 Hook 配置")
    FxCard {
        Text("保护状态总览", color = FxInk, fontSize = 17.sp, fontWeight = FontWeight.Bold)
        StatusLine("Root 授权", "状态待检查")
        StatusLine("LSPosed", "状态待检查")
        StatusLine("无障碍服务", "可选 · 状态待检查")
        FxPill("打开 Hook 应用管理", onClick = onOpenHook)
    }
    val groups = listOf(
        "应用标识与追踪" to listOf("广告标识符保护", "设备标识符保护", "剪贴板读取保护"),
        "传感器与硬件" to listOf("加速度计 / 陀螺仪", "麦克风访问保护", "相机访问保护"),
        "位置与网络" to listOf("被动位置访问", "Wi-Fi 扫描保护", "网络标识保护"),
        "数据与通知" to listOf("通知读取保护", "通知权限隐藏", "EXIF 元数据清理")
    )
    groups.forEach { (title, items) ->
        FxCard {
            Text(title, color = FxInk, fontSize = 16.sp, fontWeight = FontWeight.Bold)
            items.forEach { item ->
                Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(item, color = FxInk, fontSize = 14.sp)
                        Text("按应用配置 · 状态待读取", color = FxMuted, fontSize = 11.sp)
                    }
                    FxPill("配置")
                }
            }
        }
    }
}

@Composable
private fun ScriptPage() {
    var selected by remember { mutableStateOf("全部脚本") }
    var query by remember { mutableStateOf("") }
    PageHeader("Automation", "脚本中心", "脚本管理、运行记录、MITM 与证书入口")
    FxCard {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("全部脚本", "运行中", "已停用").forEach { FxPill(it, selected == it) { selected = it } }
        }
        BasicTextField(
            value = query, onValueChange = { query = it },
            modifier = Modifier.fillMaxWidth().background(Color(0xFFF2F5F8), RoundedCornerShape(12.dp)).padding(13.dp),
            singleLine = true,
            decorationBox = { inner -> if (query.isEmpty()) Text("搜索脚本名称或内容", color = FxMuted, fontSize = 13.sp); inner() }
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FxPill("导入脚本")
            FxPill("新建脚本")
            FxPill("刷新列表")
        }
    }
    FxCard {
        Text("脚本列表", color = FxInk, fontSize = 17.sp, fontWeight = FontWeight.Bold)
        Text("当前尚未从模块脚本目录读取数据。", color = FxMuted, fontSize = 12.sp)
        StatusLine("脚本数量", "待读取")
        StatusLine("运行任务", "待读取")
        StatusLine("最近错误", "暂无数据")
    }
    FxCard {
        Text("执行环境", color = FxInk, fontSize = 17.sp, fontWeight = FontWeight.Bold)
        StatusLine("QuickJS-NG", "ARM64 · 待接入 UI")
        StatusLine("MITM 证书", "状态待读取")
        StatusLine("脚本权限", "按脚本授权")
        FxPill("查看运行日志")
        FxPill("MITM 与证书设置")
    }
}

@Composable
private fun FxSwitch(checked: Boolean, onChanged: (Boolean) -> Unit) {
    Box(
        Modifier.size(width = 54.dp, height = 32.dp)
            .background(if (checked) FxBlue else Color(0xFFD5DDE5), CircleShape)
            .clickable { onChanged(!checked) }
            .padding(3.dp),
        contentAlignment = if (checked) Alignment.CenterEnd else Alignment.CenterStart
    ) {
        Box(Modifier.size(26.dp).background(Color.White, CircleShape))
    }
}
