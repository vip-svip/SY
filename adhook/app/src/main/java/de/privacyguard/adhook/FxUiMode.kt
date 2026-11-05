package de.privacyguard.adhook

import android.content.Context

/**
 * The independent default renderer and five app-wide visual skins. These are presentation modes only:
 * changing a skin must never start/stop VPN, DNS, proxy, Hook or script services.
 *
 * Legacy storage IDs are retained so existing 1.0.0 installations migrate in place.
 */
enum class FxUiMode(
    DEFAULT_STANDARD(
        "default",
        "默认模式 · Default",
        "FX 标准原生界面：独立于五种皮肤的基础 renderer，首次安装默认使用。",
        Renderer.NATIVE_DEFAULT
    ),
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
    ),
    HUAWEI_HARMONY_STYLE(
        "huawei",
        "HUAWEI HarmonyStyle",
        "华为鸿蒙视觉风格：独立色彩、圆角、导航与卡片外观，运行于 Android 公共 API。",
        Renderer.NATIVE_HARMONY
    ),
    IOS_CUPERTINO_STYLE(
        "ios",
        "iOS CupertinoStyle",
        "iOS 风格：分组列表、轻量分隔线、圆角表面与 Cupertino 式底部导航；并非 iOS 客户端。",
        Renderer.NATIVE_CUPERTINO
    );

    enum class Renderer { NATIVE_DEFAULT, WEB_COMPAT, NATIVE_LIQUID, NATIVE_MIUIX, NATIVE_HARMONY, NATIVE_CUPERTINO }

    companion object {
        private const val PREFS = "fx_ui"
        private const val KEY_MODE = "mode"

        @JvmStatic
        fun fromStorageId(value: String?): FxUiMode = when (value) {
            "default", "FXDefault", "fx_default" -> DEFAULT_STANDARD
            "glass", "FXLiquidNative", "fx_liquid_native" -> FX_LIQUID_NATIVE
            "miuix", "MiuixStyle", "miuix_style" -> MIUIX_STYLE
            "huawei", "HarmonyStyle", "HUAWEI HarmonyStyle", "harmony", "harmony_style" -> HUAWEI_HARMONY_STYLE
            "ios", "CupertinoStyle", "iOS CupertinoStyle", "cupertino", "cupertino_style" -> IOS_CUPERTINO_STYLE
            // "web" was an experimental alias; map it to the explicit compatibility mode.
            "classic", "web", "ClassicWebCompat", "classic_web_compat" -> CLASSIC_WEB_COMPAT
            null -> DEFAULT_STANDARD
            else -> DEFAULT_STANDARD
        }

        @JvmStatic
        fun normalizeStorageId(value: String?): String = fromStorageId(value).storageId

        @JvmStatic
        fun read(context: Context): FxUiMode {
            val value = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY_MODE, DEFAULT_STANDARD.storageId)
            return fromStorageId(value)
        }

        @JvmStatic
        fun write(context: Context, mode: FxUiMode): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putString(KEY_MODE, mode.storageId).commit()
    }
}
