package de.privacyguard.adhook

import android.graphics.Bitmap
import android.view.View
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.onDispose
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.viewinterop.AndroidView
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import de.privacyguard.adhook.glass.components.LiquidBottomTab
import de.privacyguard.adhook.glass.components.LiquidBottomTabs
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.theme.ColorSchemeMode
import top.yukonga.miuix.kmp.theme.MiuixTheme
import top.yukonga.miuix.kmp.theme.ThemeController
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

fun installFxNativeAppShell(
    view: ComposeView,
    pageContent: View,
    selectedIndex: Int,
    mode: String,
    onTabSelected: (Int) -> Unit
) {
    val wallpaperPath = FxWallpaperStore.currentPath(view.context)
    if (wallpaperPath != null) {
        // Imported native Activities may use opaque root containers. Make only
        // that host surface transparent so the shared wallpaper layer is visible;
        // child cards and dialogs keep their own foreground surfaces.
        pageContent.setBackgroundColor(android.graphics.Color.TRANSPARENT)
    }
    view.setContent {
        FxNativeAppShell(pageContent, selectedIndex, mode, wallpaperPath, onTabSelected)
    }
}

@Composable
private fun FxNativeAppShell(
    pageContent: View,
    selectedIndex: Int,
    mode: String,
    wallpaperPath: String?,
    onTabSelected: (Int) -> Unit
) {
    val labels = listOf("VPN", "Ad", "隐私", "脚本", "Hook", "设置")
    val controller = remember { ThemeController(ColorSchemeMode.System) }
    val backdrop = rememberLayerBackdrop()
    val context = LocalContext.current
    val wallpaperBitmap by produceState<Bitmap?>(initialValue = null, wallpaperPath) {
        value = if (wallpaperPath.isNullOrBlank()) null else withContext(Dispatchers.IO) {
            FxWallpaperStore.loadForDisplay(context)
        }
    }
    val wallpaperImage = remember(wallpaperBitmap) { wallpaperBitmap?.asImageBitmap() }
    DisposableEffect(wallpaperBitmap) {
        onDispose {
            wallpaperBitmap?.let { bitmap ->
                if (!bitmap.isRecycled) bitmap.recycle()
            }
        }
    }
    var selected by remember { mutableIntStateOf(selectedIndex.coerceIn(0, 5)) }
    // Keep this provider stable across recompositions. LiquidBottomTabs keys its
    // gesture/callback effects by this function; an inline lambda resets them on
    // every selected-index change and can swallow tab navigation callbacks.
    val selectedIndexProvider: () -> Int = remember { { selected } }
    LaunchedEffect(selectedIndex) { selected = selectedIndex.coerceIn(0, 5) }

    MiuixTheme(controller = controller) {
        val miuixColors = MiuixTheme.colorScheme
        Box(
            Modifier
                .fillMaxSize()
                // Keep the six-tab bar and the active page above the soft keyboard.
                // Applying this to the shared host covers every migrated native page.
                .imePadding()
                .background(when (mode) { "miuix" -> miuixColors.background; "glass" -> Color(0xFFE8EEF4); "huawei" -> Color(0xFFF1F5FA); "ios" -> Color(0xFFF2F2F7); else -> Color(0xFFF4F6F8) })
        ) {
            wallpaperImage?.let { image ->
                Image(
                    bitmap = image,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                    alpha = 0.86f
                )
                Box(
                    Modifier.fillMaxSize().background(
                        when (mode) {
                            "ios" -> Color.White.copy(alpha = 0.30f)
                            "huawei" -> Color(0xFFF1F5FA).copy(alpha = 0.25f)
                            "miuix" -> Color(0xFFF3F5FA).copy(alpha = 0.28f)
                            else -> Color.White.copy(alpha = 0.24f)
                        }
                    )
                )
            }
            // Record the real page beneath the translucent navigation surface.
            // Unlike a gradient placeholder, this samples the actual AndroidView content.
            AndroidView(
                factory = { pageContent },
                modifier = Modifier
                    .fillMaxSize()
                    // Reserve the Android navigation gesture area and the persistent tab bar.
                    // The bar remains an overlay so Liquid Glass can sample the page backdrop.
                    .navigationBarsPadding()
                    .padding(bottom = 72.dp)
                    .layerBackdrop(backdrop),
                update = {}
            )
            val barShape = RoundedCornerShape(when (mode) { "classic" -> 10.dp; "miuix" -> 18.dp; "huawei" -> 16.dp; "ios" -> 22.dp; else -> 26.dp })
            // Glass mode is rendered exclusively by the upstream LiquidBottomTabs
            // component below; this modifier is only for the classic and Miuix bars.
            val barModifier = if (mode == "miuix") {
                Modifier.background(miuixColors.surface, barShape)
            } else {
                Modifier.background(
                    when (mode) { "classic" -> Color(0xFFF7F8FA); "huawei" -> Color(0xFFF9FBFE); "ios" -> Color(0xF9FFFFFF); else -> Color.White.copy(alpha = 0.94f) },
                    barShape
                )
            }

            if (mode == "glass") {
                // Upstream Kyant LiquidBottomTabs supports arbitrary tab counts;
                // FX keeps all six destinations and gains the original drag/lens animation.
                LiquidBottomTabs(
                    selectedTabIndex = selectedIndexProvider,
                    onTabSelected = { index ->
                        // Gesture-driven selection arrives here. Ignore the
                        // duplicate callback after a direct tab click.
                        if (index != selected) {
                            selected = index
                            onTabSelected(index)
                        }
                    },
                    backdrop = backdrop,
                    tabsCount = labels.size,
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .fillMaxWidth()
                        .navigationBarsPadding()
                        .height(72.dp)
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                ) {
                    labels.forEachIndexed { index, label ->
                        LiquidBottomTab(
                            onClick = {
                                // A direct tap is an explicit navigation request even
                                // when Compose's selected index already matches. The
                                // rendered screen may have been rebuilt independently
                                // (for example after returning from Settings/Hook), so
                                // never swallow same-tab taps at this boundary.
                                selected = index
                                onTabSelected(index)
                            },
                            modifier = Modifier.semantics { this.selected = selected == index }
                        ) {
                            Text(
                                text = label,
                                color = if (selected == index) Color(0xFF0088FF) else Color(0xFF526170),
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                }
            } else {
                Row(
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .fillMaxWidth()
                        .navigationBarsPadding()
                        .height(72.dp)
                        .padding(horizontal = 8.dp, vertical = 4.dp)
                        .then(barModifier)
                        .padding(horizontal = 4.dp, vertical = 3.dp),
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    labels.forEachIndexed { index, label ->
                        val active = selected == index
                        val tabShape = RoundedCornerShape(when (mode) { "ios" -> 18.dp; "huawei" -> 14.dp; else -> 20.dp })
                        val tabModifier = if (active && mode == "miuix") {
                            Modifier.background(miuixColors.primaryContainer, tabShape)
                        } else if (active) {
                            Modifier.background(Color(0x223478F6), tabShape)
                        } else Modifier
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .height(64.dp)
                                .then(tabModifier)
                                .semantics { this.selected = active }
                                .clickable(role = Role.Tab) {
                                    selected = index
                                    onTabSelected(index)
                                },
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = label,
                                color = when {
                                    mode == "miuix" && active -> miuixColors.onPrimaryContainer
                                    mode == "ios" && active -> Color(0xFF007AFF)
                                    mode == "huawei" && active -> Color(0xFF2878D0)
                                    mode == "miuix" -> miuixColors.onSurfaceContainerVariant
                                    active -> Color(0xFF1769AA)
                                    else -> Color(0xFF526170)
                                },
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Bold
                            )
                        }
                    }
                }
            }
        }
    }
}
