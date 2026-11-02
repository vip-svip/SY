package de.privacyguard.adhook

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.ComposeView
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.effects.lens
import top.yukonga.miuix.kmp.basic.Card
import top.yukonga.miuix.kmp.basic.CardDefaults
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.theme.ColorSchemeMode
import top.yukonga.miuix.kmp.theme.MiuixTheme
import top.yukonga.miuix.kmp.theme.ThemeController

fun installFxDesignModePanel(
    view: ComposeView,
    currentMode: String,
    onModeSelected: (String) -> Unit
) {
    view.setContent {
        FxDesignModePanel(currentMode, onModeSelected)
    }
}

@Composable
private fun FxDesignModePanel(
    currentMode: String,
    onModeSelected: (String) -> Unit
) {
    val themeController = remember { ThemeController(ColorSchemeMode.System) }
    val backdrop = rememberLayerBackdrop()

    MiuixTheme(controller = themeController) {
        Box(Modifier.fillMaxWidth()) {
            // The backdrop source is a separate sibling layer. It contains only the
            // static gradient, never the glass cards that sample it (prevents feedback).
            Box(
                Modifier
                    .fillMaxSize()
                    .drawBehind {
                        drawRect(
                            Brush.linearGradient(
                                listOf(Color(0xFFE9F2FC), Color(0xFFF2ECF8), Color(0xFFEAF5F3))
                            )
                        )
                    }
                    .layerBackdrop(backdrop)
            )
            Column(
                Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 12.dp, vertical = 6.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text("选择 FX Hook 的原生界面渲染模式")
                Text(
                    "Miuix 和 Backdrop 在这里由真实 Compose 组件渲染；Web 管理页面仍保留原有功能，不会被误称为原生 Compose 页面。"
                )
                ModeCard("classic", "经典界面", "简洁原生外观，优先兼容性", currentMode, onModeSelected, backdrop, false)
                ModeCard("miuix", "Miuix 原生界面", "使用 MiuixTheme、Card、Text 组件与系统动态配色", currentMode, onModeSelected, backdrop, false)
                ModeCard("glass", "Liquid Glass 液态玻璃", "使用 Kyant Backdrop 实时背景采样；Android 12+ 启用模糊，Android 13+ 启用 Lens 折射", currentMode, onModeSelected, backdrop, true)
                ModeCard("web", "网页原样", "Web 管理页面不注入主题样式；Hook 与设置仍使用原生界面", currentMode, onModeSelected, backdrop, false)
            }
        }
    }
}

@Composable
private fun ModeCard(
    mode: String,
    title: String,
    description: String,
    currentMode: String,
    onModeSelected: (String) -> Unit,
    backdrop: com.kyant.backdrop.Backdrop,
    glass: Boolean
) {
    val shape = RoundedCornerShape(20.dp)
    val glassModifier = if (glass) {
        Modifier.drawBackdrop(
            backdrop = backdrop,
            shape = { shape },
            effects = {
                blur(18.dp.toPx())
                lens(18.dp.toPx(), 22.dp.toPx())
            },
            onDrawSurface = { drawRect(Color.White.copy(alpha = 0.30f)) }
        )
    } else Modifier

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .then(glassModifier)
            .clickable { onModeSelected(mode) },
        colors = CardDefaults.defaultColors(
            color = if (mode == currentMode) Color(0x332F80ED) else Color(0x1AFFFFFF)
        ),
        insideMargin = PaddingValues(16.dp)
    ) {
        Text(if (mode == currentMode) "✓  $title" else title)
        Text(description)
    }
}
