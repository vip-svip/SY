package de.privacyguard.adhook

import androidx.compose.foundation.background
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.border
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.ui.semantics.Role
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.effects.lens
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
        val miuixColors = MiuixTheme.colorScheme
        fun resolveTokens(mode: String) = fxComposeShellTokens(
            mode = mode,
            miuixBackground = miuixColors.background,
            miuixSurface = miuixColors.surface,
            miuixPrimary = Color(0xFF3478F6),
            miuixSelectedText = miuixColors.onPrimaryContainer,
            miuixInactiveText = miuixColors.onSurfaceContainerVariant,
            miuixSelectedSurface = miuixColors.primaryContainer
        )
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
                Text("选择 FX 全局界面模式")
                Text(
                    "六种模式覆盖整个应用的视觉呈现。切换只改变界面渲染，不重启 VPN、DNS、代理内核、Hook 或脚本服务。"
                )
                ModeCard(FxUiMode.DEFAULT_STANDARD.storageId, FxUiMode.DEFAULT_STANDARD.title, FxUiMode.DEFAULT_STANDARD.description, currentMode, onModeSelected, resolveTokens(FxUiMode.DEFAULT_STANDARD.storageId), backdrop, false)
                ModeCard(FxUiMode.CLASSIC_WEB_COMPAT.storageId, FxUiMode.CLASSIC_WEB_COMPAT.title, FxUiMode.CLASSIC_WEB_COMPAT.description, currentMode, onModeSelected, resolveTokens(FxUiMode.CLASSIC_WEB_COMPAT.storageId), backdrop, false)
                ModeCard(FxUiMode.FX_LIQUID_NATIVE.storageId, FxUiMode.FX_LIQUID_NATIVE.title, FxUiMode.FX_LIQUID_NATIVE.description, currentMode, onModeSelected, resolveTokens(FxUiMode.FX_LIQUID_NATIVE.storageId), backdrop, true)
                ModeCard(FxUiMode.MIUIX_STYLE.storageId, FxUiMode.MIUIX_STYLE.title, FxUiMode.MIUIX_STYLE.description, currentMode, onModeSelected, resolveTokens(FxUiMode.MIUIX_STYLE.storageId), backdrop, false)
                ModeCard(FxUiMode.HUAWEI_HARMONY_STYLE.storageId, FxUiMode.HUAWEI_HARMONY_STYLE.title, FxUiMode.HUAWEI_HARMONY_STYLE.description, currentMode, onModeSelected, resolveTokens(FxUiMode.HUAWEI_HARMONY_STYLE.storageId), backdrop, false)
                ModeCard(FxUiMode.IOS_CUPERTINO_STYLE.storageId, FxUiMode.IOS_CUPERTINO_STYLE.title, FxUiMode.IOS_CUPERTINO_STYLE.description, currentMode, onModeSelected, resolveTokens(FxUiMode.IOS_CUPERTINO_STYLE.storageId), backdrop, false)
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
    tokens: FxComposeShellTokens,
    backdrop: com.kyant.backdrop.Backdrop,
    glass: Boolean
) {
    val selected = mode == currentMode
    val shape = RoundedCornerShape((tokens.barCornerRadiusDp + 4).dp)
    val surface = if (selected) tokens.selectedTabBackground else tokens.barBackground
    val outline = if (selected) tokens.accent else tokens.barBorder
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

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .then(glassModifier)
            .then(if (glass) Modifier else Modifier.background(surface, shape))
            .border(if (selected) 2.dp else 1.dp, outline, shape)
            .selectable(
                selected = selected,
                role = Role.RadioButton,
                onClick = { onModeSelected(mode) }
            )
            .padding(16.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                if (selected) "✓  $title" else title,
                color = tokens.selectedText
            )
            Text(description, color = tokens.inactiveText)
        }
    }
}
