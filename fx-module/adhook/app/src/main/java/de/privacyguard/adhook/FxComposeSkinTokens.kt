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

internal object FxDefaultComposeTokens {
    fun create() = FxComposeShellTokens(
        pageBackground = Color(0xFFF7F8FC),
        wallpaperOverlay = Color(0xFFF7F8FC).copy(alpha = 0.24f),
        barBackground = Color(0xFFFFFFFF),
        barBorder = Color(0xFFE0E6EF),
        accent = Color(0xFF315B9A),
        selectedText = Color(0xFF315B9A),
        inactiveText = Color(0xFF687789),
        selectedTabBackground = Color(0x1F315B9A),
        barCornerRadiusDp = 18,
        tabCornerRadiusDp = 14,
        tabBarHeightDp = 66,
        tabItemHeightDp = 58,
        horizontalInsetDp = 8,
        verticalInsetDp = 4,
        itemSpacingDp = 2,
        labelSizeSp = 13,
        useLiquidTabsRenderer = false
    )
}

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
        pageBackground = Color(HarmonySkinTokens.HarmonyColorTokens.BACKGROUND),
        wallpaperOverlay = Color(HarmonySkinTokens.HarmonyColorTokens.WALLPAPER_TINT).copy(alpha = 0.25f),
        barBackground = Color(HarmonySkinTokens.HarmonyColorTokens.NAV_SURFACE),
        barBorder = Color(HarmonySkinTokens.HarmonyColorTokens.DIVIDER),
        accent = Color(HarmonySkinTokens.HarmonyColorTokens.ACCENT),
        selectedText = Color(HarmonySkinTokens.HarmonyColorTokens.ACCENT),
        inactiveText = Color(HarmonySkinTokens.HarmonyColorTokens.SECONDARY_TEXT),
        selectedTabBackground = Color(HarmonySkinTokens.HarmonyColorTokens.SELECTED_TAB_SURFACE),
        barCornerRadiusDp = HarmonySkinTokens.HarmonyShapeTokens.NAV_BAR_RADIUS_DP,
        tabCornerRadiusDp = HarmonySkinTokens.HarmonyShapeTokens.TAB_RADIUS_DP,
        tabBarHeightDp = HarmonySkinTokens.HarmonySpacingTokens.NAV_HEIGHT_DP,
        tabItemHeightDp = HarmonySkinTokens.HarmonySpacingTokens.TAB_HEIGHT_DP,
        horizontalInsetDp = HarmonySkinTokens.HarmonySpacingTokens.NAV_OUTER_HORIZONTAL_DP,
        verticalInsetDp = HarmonySkinTokens.HarmonySpacingTokens.NAV_OUTER_VERTICAL_DP,
        itemSpacingDp = 4,
        labelSizeSp = HarmonySkinTokens.HarmonyTypographyTokens.TAB_LABEL_SP.toInt(),
        useLiquidTabsRenderer = false
    )
}

internal object FxCupertinoComposeTokens {
    fun create() = FxComposeShellTokens(
        pageBackground = Color(CupertinoSkinTokens.CupertinoColorTokens.BACKGROUND),
        wallpaperOverlay = Color(CupertinoSkinTokens.CupertinoColorTokens.WALLPAPER_TINT).copy(alpha = 0.30f),
        barBackground = Color(CupertinoSkinTokens.CupertinoColorTokens.NAV_SURFACE),
        barBorder = Color(CupertinoSkinTokens.CupertinoColorTokens.DIVIDER),
        accent = Color(CupertinoSkinTokens.CupertinoColorTokens.ACCENT),
        selectedText = Color(CupertinoSkinTokens.CupertinoColorTokens.ACCENT),
        inactiveText = Color(CupertinoSkinTokens.CupertinoColorTokens.SECONDARY_TEXT),
        selectedTabBackground = Color(CupertinoSkinTokens.CupertinoColorTokens.SELECTED_TAB_SURFACE),
        barCornerRadiusDp = CupertinoSkinTokens.CupertinoShapeTokens.NAV_BAR_RADIUS_DP,
        tabCornerRadiusDp = CupertinoSkinTokens.CupertinoShapeTokens.TAB_RADIUS_DP,
        tabBarHeightDp = CupertinoSkinTokens.CupertinoSpacingTokens.NAV_HEIGHT_DP,
        tabItemHeightDp = CupertinoSkinTokens.CupertinoSpacingTokens.TAB_HEIGHT_DP,
        horizontalInsetDp = CupertinoSkinTokens.CupertinoSpacingTokens.NAV_OUTER_HORIZONTAL_DP,
        verticalInsetDp = CupertinoSkinTokens.CupertinoSpacingTokens.NAV_OUTER_VERTICAL_DP,
        itemSpacingDp = 4,
        labelSizeSp = CupertinoSkinTokens.CupertinoTypographyTokens.TAB_LABEL_SP.toInt(),
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
    "default" -> FxDefaultComposeTokens.create()
    "classic" -> FxClassicComposeTokens.create()
    "glass" -> FxLiquidComposeTokens.create()
    "miuix" -> FxMiuixComposeTokens.create(
        miuixBackground, miuixSurface, miuixPrimary,
        miuixSelectedText, miuixInactiveText, miuixSelectedSurface
    )
    "huawei" -> FxHarmonyComposeTokens.create()
    "ios" -> FxCupertinoComposeTokens.create()
    else -> FxDefaultComposeTokens.create()
}
