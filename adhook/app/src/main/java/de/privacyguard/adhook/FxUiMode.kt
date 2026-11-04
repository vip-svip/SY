package de.privacyguard.adhook

import android.content.Context

/**
 * The three app-wide visual skins. These are presentation modes only:
 * changing a skin must never start/stop VPN, DNS, proxy, Hook or script services.
 *
 * Legacy storage IDs are retained so existing 1.0.0 installations migrate in place.
 */
enum class FxUiMode(
    val storageId: String,
    val title: String,
    val description: String,
    val renderer: Renderer
) {
    CLASSIC_WEB_COMPAT(
        "classic",
        "ClassicWebCompat",
        "经典兼容模式：显示内置原版 WebUI，保留原有页面结构与交互。",
        Renderer.WEB_COMPAT
    ),
    FX_LIQUID_NATIVE(
        "glass",
        "FXLiquidNative",
        "FX 原生液态模式：原生 Android 页面、Compose 液态玻璃导航与动态背景效果。",
        Renderer.NATIVE_LIQUID
    ),
    MIUIX_STYLE(
        "miuix",
        "MiuixStyle",
        "Miuix 原生模式：使用 Miuix 组件、主题色和 HyperOS 风格布局。",
        Renderer.NATIVE_MIUIX
    );

    enum class Renderer { WEB_COMPAT, NATIVE_LIQUID, NATIVE_MIUIX }

    companion object {
        private const val PREFS = "fx_ui"
        private const val KEY_MODE = "mode"

        @JvmStatic
        fun fromStorageId(value: String?): FxUiMode = when (value) {
            "glass", "FXLiquidNative", "fx_liquid_native" -> FX_LIQUID_NATIVE
            "miuix", "MiuixStyle", "miuix_style" -> MIUIX_STYLE
            // "web" was an experimental alias; map it to the explicit compatibility mode.
            "classic", "web", "ClassicWebCompat", "classic_web_compat", null -> CLASSIC_WEB_COMPAT
            else -> CLASSIC_WEB_COMPAT
        }

        @JvmStatic
        fun normalizeStorageId(value: String?): String = fromStorageId(value).storageId

        @JvmStatic
        fun read(context: Context): FxUiMode {
            val value = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY_MODE, CLASSIC_WEB_COMPAT.storageId)
            return fromStorageId(value)
        }

        @JvmStatic
        fun write(context: Context, mode: FxUiMode): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putString(KEY_MODE, mode.storageId).commit()
    }
}
