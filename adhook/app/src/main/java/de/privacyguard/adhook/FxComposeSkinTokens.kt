package de.privacyguard.adhook

import androidx.compose.ui.graphics.Color

/**
 * Presentation-only design tokens for the shared six-destination shell.
 *
 * Every mode has its own palette, geometry and navigation measurements. The
 * business page, ViewModels and running services are deliberately not inputs.
 */
internal data class FxComposeShellTokens(
    val pageBackground: Color,
    val wallpaperOverlay: Color,
    val barBackground: Color,
    val barBorder: Color,
    val accent: Color,
    val selectedText: Color,
    val inactiveText: Color,
    val selectedTabBackground: Color,
    val barCornerRadiusDp: Int,
    val tabCornerRadiusDp: Int,
    val tabBarHeightDp: Int,
    val tabItemHeightDp: Int,
    val horizontalInsetDp: Int,
    val verticalInsetDp: Int,
    val itemSpacingDp: Int,
    val labelSizeSp: Int,
    val useLiquidTabsRenderer: Boolean
)

internal object FxClassicComposeTokens {
    fun create() = FxComposeShellTokens(
        pageBackground = Color(0xFFF4F6F8),
        wallpaperOverlay = Color.White.copy(alpha = 0.24f),
        barBackground = Color(0xFFF7F8FA),
        barBorder = Color.Transparent,
        accent = Color(0xFF1769AA),
        selectedText = Color(0xFF1769AA),
        inactiveText = Color(0xFF526170),
        selectedTabBackground = Color(0x223478F6),
        barCornerRadiusDp = 8,
        tabCornerRadiusDp = 8,
        tabBarHeightDp = 60,
        tabItemHeightDp = 50,
        horizontalInsetDp = 4,
        verticalInsetDp = 3,
        itemSpacingDp = 0,
        labelSizeSp = 13,
        useLiquidTabsRenderer = false
    )
}

internal object FxLiquidComposeTokens {
    fun create() = FxComposeShellTokens(
        pageBackground = Color(0xFFE8EEF4),
        wallpaperOverlay = Color.White.copy(alpha = 0.24f),
        barBackground = Color.White.copy(alpha = 0.30f),
        barBorder = Color.White.copy(alpha = 0.42f),
        accent = Color(0xFF0088FF),
        selectedText = Color(0xFF0088FF),
        inactiveText = Color(0xFF526170),
        selectedTabBackground = Color(0x223478F6),
        barCornerRadiusDp = 26,
        tabCornerRadiusDp = 20,
        tabBarHeightDp = 72,
        tabItemHeightDp = 64,
        horizontalInsetDp = 12,
        verticalInsetDp = 4,
        itemSpacingDp = 2,
        labelSizeSp = 12,
        useLiquidTabsRenderer = true
    )
}

internal object FxMiuixComposeTokens {
    fun create(
        background: Color,
        surface: Color,
        primary: Color,
        selectedText: Color,
        inactiveText: Color,
        selectedSurface: Color
    ) = FxComposeShellTokens(
        pageBackground = background,
        wallpaperOverlay = Color(0xFFF3F5FA).copy(alpha = 0.28f),
        barBackground = surface,
        barBorder = Color.Transparent,
        accent = primary,
        selectedText = selectedText,
        inactiveText = inactiveText,
        selectedTabBackground = selectedSurface,
        barCornerRadiusDp = 20,
        tabCornerRadiusDp = 18,
        tabBarHeightDp = 68,
        tabItemHeightDp = 60,
        horizontalInsetDp = 8,
        verticalInsetDp = 4,
        itemSpacingDp = 2,
        labelSizeSp = 14,
        useLiquidTabsRenderer = false
    )
}

internal object FxHarmonyComposeTokens {
    fun create() = FxComposeShellTokens(
        pageBackground = Color(0xFFF1F5FA),
        wallpaperOverlay = Color(0xFFF1F5FA).copy(alpha = 0.25f),
        barBackground = Color(0xFFF9FBFE),
        barBorder = Color(0x332878D0),
        accent = Color(0xFF2878D0),
        selectedText = Color(0xFF2878D0),
        inactiveText = Color(0xFF64788F),
        selectedTabBackground = Color(0x332878D0),
        barCornerRadiusDp = 18,
        tabCornerRadiusDp = 14,
        tabBarHeightDp = 72,
        tabItemHeightDp = 64,
        horizontalInsetDp = 10,
        verticalInsetDp = 4,
        itemSpacingDp = 4,
        labelSizeSp = 14,
        useLiquidTabsRenderer = false
    )
}

internal object FxCupertinoComposeTokens {
    fun create() = FxComposeShellTokens(
        pageBackground = Color(0xFFF2F2F7),
        wallpaperOverlay = Color.White.copy(alpha = 0.30f),
        barBackground = Color(0xF9FFFFFF),
        barBorder = Color(0x1F8E8E93),
        accent = Color(0xFF007AFF),
        selectedText = Color(0xFF007AFF),
        inactiveText = Color(0xFF6C6C70),
        selectedTabBackground = Color(0x1A007AFF),
        barCornerRadiusDp = 24,
        tabCornerRadiusDp = 20,
        tabBarHeightDp = 76,
        tabItemHeightDp = 68,
        horizontalInsetDp = 12,
        verticalInsetDp = 4,
        itemSpacingDp = 4,
        labelSizeSp = 13,
        useLiquidTabsRenderer = false
    )
}

internal fun fxComposeShellTokens(
    mode: String,
    miuixBackground: Color,
    miuixSurface: Color,
    miuixPrimary: Color,
    miuixSelectedText: Color,
    miuixInactiveText: Color,
    miuixSelectedSurface: Color
): FxComposeShellTokens = when (mode) {
    "glass" -> FxLiquidComposeTokens.create()
    "miuix" -> FxMiuixComposeTokens.create(
        miuixBackground, miuixSurface, miuixPrimary,
        miuixSelectedText, miuixInactiveText, miuixSelectedSurface
    )
    "huawei" -> FxHarmonyComposeTokens.create()
    "ios" -> FxCupertinoComposeTokens.create()
    else -> FxClassicComposeTokens.create()
}
