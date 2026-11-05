package de.privacyguard.adhook

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

internal data class FxGkdRule(
    val id: String,
    val packageName: String,
    val selector: String,
    val cooldownMillis: Long,
    val enabled: Boolean
)

/**
 * Small local-only store for user-authored GKD selector rules.
 *
 * Remote subscriptions, AI providers, snapshots and cloud sync are deliberately
 * not enabled by this first runtime slice.
 */
internal object FxGkdRuleStore {
    private const val PREFS = "fx_gkd_automation"
    private const val KEY_MASTER_ENABLED = "enabled"
    private const val KEY_RULES = "rules_json"
    const val MAX_RULES = 128
    const val MIN_COOLDOWN_MS = 1_000L
    const val MAX_COOLDOWN_MS = 60_000L
    const val DEFAULT_COOLDOWN_MS = 3_000L

    @JvmStatic
    @Synchronized
    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_MASTER_ENABLED, false)

    @JvmStatic
    @Synchronized
    fun hasEnabledRule(context: Context, packageName: String): Boolean {
        if (!isEnabled(context) || !isValidPackageName(packageName)) return false
        return getRules(context).any { it.enabled && it.packageName == packageName }
    }

    @JvmStatic
    @Synchronized
    fun isRuleEnabled(context: Context, id: String, packageName: String): Boolean {
        if (!isEnabled(context)) return false
        return getRules(context).any { it.enabled && it.id == id && it.packageName == packageName }
    }

    @JvmStatic
    fun hasEnabledRule(context: Context, packageName: String): Boolean {
        if (!isEnabled(context) || !isValidPackageName(packageName)) return false
        return getRules(context).any { it.enabled && it.packageName == packageName }
    }

    @JvmStatic
    fun isRuleEnabled(context: Context, id: String, packageName: String): Boolean {
        if (!isEnabled(context)) return false
        return getRules(context).any {
            it.enabled && it.id == id && it.packageName == packageName
        }
    }

    @JvmStatic
    @Synchronized
    fun setEnabled(context: Context, enabled: Boolean): Boolean {
        val hasRules = getRules(context).any { it.enabled }
        if (enabled && !hasRules) return false
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_MASTER_ENABLED, enabled).commit()
    }

    @JvmStatic
    @Synchronized
    fun getRules(context: Context): List<FxGkdRule> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_RULES, "[]") ?: "[]"
        return try {
            val array = JSONArray(raw)
            buildList {
                for (index in 0 until minOf(array.length(), MAX_RULES)) {
                    val item = array.optJSONObject(index) ?: continue
                    val id = item.optString("id").takeIf { it.length in 1..64 } ?: continue
                    val pkg = item.optString("package").takeIf(::isValidPackageName) ?: continue
                    val selector = item.optString("selector").takeIf { it.isNotBlank() && it.length <= 512 } ?: continue
                    val cooldown = item.optLong("cooldown_ms", DEFAULT_COOLDOWN_MS)
                        .coerceIn(MIN_COOLDOWN_MS, MAX_COOLDOWN_MS)
                    add(FxGkdRule(id, pkg, selector, cooldown, item.optBoolean("enabled", true)))
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    @JvmStatic
    @Synchronized
    fun addRule(
        context: Context,
        packageName: String,
        selector: String,
        cooldownMillis: Long = DEFAULT_COOLDOWN_MS
    ): FxGkdRule? {
        val pkg = packageName.trim()
        val expression = selector.trim()
        if (!isValidPackageName(pkg) || expression.isEmpty() || expression.length > 512) return null
        val compiled = FxGkdSelectorEngine.compile(expression)
        if (!compiled.isValid) return null
        val existing = getRules(context)
        if (existing.size >= MAX_RULES) return null
        val rule = FxGkdRule(
            id = UUID.randomUUID().toString(),
            packageName = pkg,
            selector = expression,
            cooldownMillis = cooldownMillis.coerceIn(MIN_COOLDOWN_MS, MAX_COOLDOWN_MS),
            enabled = true
        )
        val next = existing + rule
        return if (writeRules(context, next)) rule else null
    }

    @JvmStatic
    @Synchronized
    fun setRuleEnabled(context: Context, id: String, enabled: Boolean): Boolean {
        val rules = getRules(context)
        if (rules.none { it.id == id }) return false
        return writeRules(context, rules.map { if (it.id == id) it.copy(enabled = enabled) else it })
    }

    @JvmStatic
    @Synchronized
    fun removeRule(context: Context, id: String): Boolean {
        val rules = getRules(context)
        val next = rules.filterNot { it.id == id }
        if (next.size == rules.size) return false
        return writeRules(context, next)
    }

    @JvmStatic
    fun isValidPackageName(value: String): Boolean =
        value.length in 3..255 &&
            value.matches(Regex("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+"))

    private fun writeRules(context: Context, rules: List<FxGkdRule>): Boolean {
        if (rules.size > MAX_RULES) return false
        val array = JSONArray()
        rules.forEach { rule ->
            array.put(JSONObject()
                .put("id", rule.id)
                .put("package", rule.packageName)
                .put("selector", rule.selector)
                .put("cooldown_ms", rule.cooldownMillis)
                .put("enabled", rule.enabled))
        }
        val editor = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_RULES, array.toString())
        if (rules.none { it.enabled }) editor.putBoolean(KEY_MASTER_ENABLED, false)
        return editor.commit()
    }
}
