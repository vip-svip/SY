package de.privacyguard.adhook

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.setContent
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.effects.lens
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.theme.ColorSchemeMode
import top.yukonga.miuix.kmp.theme.MiuixTheme
import top.yukonga.miuix.kmp.theme.ThemeController

fun installFxNativeBottomBar(
    view: ComposeView,
    selectedIndex: Int,
    mode: String,
    onTabSelected: (Int) -> Unit
) {
    view.setContent {
        FxNativeBottomBar(selectedIndex, mode, onTabSelected)
    }
}

@Composable
private fun FxNativeBottomBar(
    selectedIndex: Int,
    mode: String,
    onTabSelected: (Int) -> Unit
) {
    val labels = listOf("VPN", "Ad", "隐私", "脚本", "Hook", "设置")
    val themeController = remember { ThemeController(ColorSchemeMode.System) }
    val backdrop = rememberLayerBackdrop()
    var selected by remember { mutableIntStateOf(selectedIndex.coerceIn(0, 5)) }
    LaunchedEffect(selectedIndex) {
        selected = selectedIndex.coerceIn(0, 5)
    }

    MiuixTheme(controller = themeController) {
        Box(Modifier.fillMaxSize()) {
            // Dedicated background-only sampling layer: never captures the bar or its glass tabs.
            Box(
                Modifier
                    .fillMaxSize()
                    .drawBehind {
                        drawRect(
                            Brush.linearGradient(
                                listOf(Color(0xFFEAF2FA), Color(0xFFF2EDF7), Color(0xFFEAF5F1))
                            )
                        )
                    }
                    .layerBackdrop(backdrop)
            )
            val containerShape = RoundedCornerShape(26.dp)
            val containerModifier = if (mode == "glass") {
                Modifier.drawBackdrop(
                    backdrop = backdrop,
                    shape = { containerShape },
                    effects = {
                        blur(16.dp.toPx())
                        lens(16.dp.toPx(), 18.dp.toPx())
                    },
                    onDrawSurface = { drawRect(Color.White.copy(alpha = 0.38f)) }
                )
            } else {
                Modifier.background(
                    if (mode == "classic") Color(0xFFF7F8FA) else Color.White.copy(alpha = 0.86f),
                    containerShape
                )
            }

            Row(
                modifier = Modifier
                    .align(Alignment.Center)
                    .fillMaxWidth()
                    .fillMaxHeight()
                    .padding(horizontal = 8.dp, vertical = 5.dp)
                    .then(containerModifier)
                    .padding(horizontal = 4.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(2.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                labels.forEachIndexed { index, label ->
                    val active = selected == index
                    val tabShape = RoundedCornerShape(20.dp)
                    val tabModifier = if (active && mode == "glass") {
                        Modifier.drawBackdrop(
                            backdrop = backdrop,
                            shape = { tabShape },
                            effects = {
                                lens(7.dp.toPx(), 9.dp.toPx())
                            },
                            onDrawSurface = { drawRect(Color.White.copy(alpha = 0.52f)) }
                        )
                    } else if (active) {
                        Modifier.background(Color(0x223478F6), tabShape)
                    } else Modifier

                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .then(tabModifier)
                            .clickable {
                                selected = index
                                onTabSelected(index)
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = label,
                            color = if (active) Color(0xFF1769AA) else Color(0xFF526170),
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
    }
}
