package de.privacyguard.adhook

import android.content.Context

import java.util.Locale

/**
 * The independent default renderer and five app-wide visual skins. These are presentation modes only:
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
    DEFAULT_STANDARD(
        "default",
        "默认模式 · Default",
        "FX 标准原生界面：独立于五种皮肤的基础 renderer，首次安装默认使用。",
        Renderer.NATIVE_DEFAULT
    ),
    CLASSIC_WEB_COMPAT(
        "classic",
        "旧网页模式 · Classic",
        "经典网页兼容皮肤：显示内置原版 WebUI，保留原有页面结构与交互。",
        Renderer.WEB_COMPAT
    ),
    FX_LIQUID_NATIVE(
        "glass",
        "原生液态玻璃 · Glass",
        "FX 原生液态玻璃皮肤：使用原生 Android 页面、液态玻璃导航与动态背景效果。",
        Renderer.NATIVE_LIQUID
    ),
    MIUIX_STYLE(
        "miuix",
        "Miuix · 小米澎湃风格",
        "独立 Miuix 皮肤：使用 Miuix 组件、主题色和 HyperOS 风格布局。",
        Renderer.NATIVE_MIUIX
    ),
    HUAWEI_HARMONY_STYLE(
        "huawei",
        "HarmonyStyle · 华为风格",
        "独立 HarmonyStyle 皮肤：采用鸿蒙视觉语言，运行于 Android 公共 API。",
        Renderer.NATIVE_HARMONY
    ),
    IOS_CUPERTINO_STYLE(
        "ios",
        "CupertinoStyle · iOS 风格",
        "独立 Cupertino 皮肤：采用分组列表、轻量分隔线和 Cupertino 式底部导航；并非 iOS 客户端。",
        Renderer.NATIVE_CUPERTINO
    );

    enum class Renderer { NATIVE_DEFAULT, WEB_COMPAT, NATIVE_LIQUID, NATIVE_MIUIX, NATIVE_HARMONY, NATIVE_CUPERTINO }

    companion object {
        private const val PREFS = "fx_ui"
        private const val KEY_MODE = "mode"

        @JvmStatic
        fun fromStorageId(value: String?): FxUiMode = when (value?.trim()?.lowercase(Locale.ROOT)) {
            "default", "fxdefault", "fx_default" -> DEFAULT_STANDARD
            "glass", "fxliquidnative", "fx_liquid_native" -> FX_LIQUID_NATIVE
            "miuix", "miuixstyle", "miuix_style" -> MIUIX_STYLE
            "huawei", "harmonystyle", "huawei harmonystyle", "harmony", "harmony_style" -> HUAWEI_HARMONY_STYLE
            "ios", "cupertinostyle", "ios cupertinostyle", "cupertino", "cupertino_style" -> IOS_CUPERTINO_STYLE
            // "web" was an experimental alias; map it to the explicit compatibility mode.
            "classic", "web", "classicwebcompat", "classic_web_compat" -> CLASSIC_WEB_COMPAT
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
