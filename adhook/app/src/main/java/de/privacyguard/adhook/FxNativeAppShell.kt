package de.privacyguard.adhook

import android.view.View
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.setContent
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.viewinterop.AndroidView
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.kyant.backdrop.drawBackdrop
import com.kyant.backdrop.effects.blur
import com.kyant.backdrop.effects.lens
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.theme.ColorSchemeMode
import top.yukonga.miuix.kmp.theme.MiuixTheme
import top.yukonga.miuix.kmp.theme.ThemeController

fun installFxNativeAppShell(
    view: ComposeView,
    pageContent: View,
    selectedIndex: Int,
    mode: String,
    onTabSelected: (Int) -> Unit
) {
    view.setContent {
        FxNativeAppShell(pageContent, selectedIndex, mode, onTabSelected)
    }
}

@Composable
private fun FxNativeAppShell(
    pageContent: View,
    selectedIndex: Int,
    mode: String,
    onTabSelected: (Int) -> Unit
) {
    val labels = listOf("VPN", "Ad", "隐私", "脚本", "Hook", "设置")
    val controller = remember { ThemeController(ColorSchemeMode.System) }
    val backdrop = rememberLayerBackdrop()
    var selected by remember { mutableIntStateOf(selectedIndex.coerceIn(0, 5)) }
    LaunchedEffect(selectedIndex) { selected = selectedIndex.coerceIn(0, 5) }

    MiuixTheme(controller = controller) {
        Box(Modifier.background(Color(0xFFF4F6F8))) {
            // Record the real page beneath the translucent navigation surface.
            // Unlike a gradient placeholder, this samples the actual AndroidView content.
            AndroidView(
                factory = { pageContent },
                modifier = Modifier
                    .fillMaxSize()
                    .layerBackdrop(backdrop),
                update = {}
            )
            val barShape = RoundedCornerShape(26.dp)
            val barModifier = if (mode == "glass") {
                Modifier.drawBackdrop(
                    backdrop = backdrop,
                    shape = { barShape },
                    effects = {
                        blur(18.dp.toPx())
                        lens(18.dp.toPx(), 22.dp.toPx())
                    },
                    onDrawSurface = { drawRect(Color.White.copy(alpha = 0.34f)) }
                )
            } else {
                Modifier.background(
                    if (mode == "classic") Color(0xFFF7F8FA) else Color.White.copy(alpha = 0.94f),
                    barShape
                )
            }

            Row(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .height(72.dp)
                    .padding(horizontal = 8.dp, vertical = 4.dp)
                    .then(barModifier)
                    .padding(horizontal = 4.dp, vertical = 3.dp),
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
                            effects = { lens(7.dp.toPx(), 9.dp.toPx()) },
                            onDrawSurface = { drawRect(Color.White.copy(alpha = 0.50f)) }
                        )
                    } else if (active) {
                        Modifier.background(Color(0x223478F6), tabShape)
                    } else Modifier
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(64.dp)
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
