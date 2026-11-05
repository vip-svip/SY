package de.privacyguard.adhook

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

data class FxGkdImportResult(
    val imported: Int,
    val skipped: Int,
    val error: String?
)

data class FxGkdRule(
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
object FxGkdRuleStore {
    const val MAX_IMPORT_BYTES = 256 * 1024
    private const val EXPORT_FORMAT = "FX-GKD-LOCAL-RULES"
    private const val EXPORT_SCHEMA_VERSION = 1
    private const val PREFS = "fx_gkd_automation"
    private const val KEY_MASTER_ENABLED = "enabled"
    private const val KEY_RULES = "rules_json"
    const val MAX_RULES = 128
    const val MIN_COOLDOWN_MS = 1_000L
    const val MAX_COOLDOWN_MS = 60_000L
    const val DEFAULT_COOLDOWN_MS = 3_000L

    // Accessibility events can arrive frequently. Cache the decoded rules by
    // their persisted JSON value so the event hot path does not rebuild a
    // JSONArray/list for every content-changed or scroll event.
    @Volatile
    private var cachedRulesRaw: String? = null
    @Volatile
    private var cachedRules: List<FxGkdRule> = emptyList()

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
        if (raw == cachedRulesRaw) return cachedRules

        val parsed = try {
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
        cachedRulesRaw = raw
        cachedRules = parsed
        return parsed
    }

    /**
     * Export only local rule configuration. No screen contents, runtime history,
     * credentials, or service state are part of this portable document.
     */
    @JvmStatic
    @Synchronized
    fun exportJson(context: Context): String {
        val exportedRules = JSONArray()
        getRules(context).forEach { rule ->
            exportedRules.put(
                JSONObject()
                    .put("id", rule.id)
                    .put("package", rule.packageName)
                    .put("selector", rule.selector)
                    .put("cooldown_ms", rule.cooldownMillis)
                    .put("enabled", rule.enabled)
            )
        }
        return JSONObject()
            .put("format", EXPORT_FORMAT)
            .put("schema_version", EXPORT_SCHEMA_VERSION)
            .put("rules", exportedRules)
            .toString(2)
    }

    /**
     * Merge a validated local export. Imported rules are always disabled,
     * regardless of the enabled field in the file. Existing rules remain intact.
     */
    @JvmStatic
    @Synchronized
    fun importJson(context: Context, raw: String): FxGkdImportResult {
        if (raw.toByteArray(Charsets.UTF_8).size > MAX_IMPORT_BYTES) {
            return FxGkdImportResult(0, 0, "导入文件超过 256 KiB。")
        }

        val document = try {
            JSONObject(raw)
        } catch (_: Exception) {
            return FxGkdImportResult(0, 0, "JSON 文件无法解析。")
        }
        if (document.optString("format") != EXPORT_FORMAT ||
            document.optInt("schema_version", -1) != EXPORT_SCHEMA_VERSION
        ) {
            return FxGkdImportResult(0, 0, "文件格式或版本不受支持。")
        }
        val sourceRules = document.optJSONArray("rules")
            ?: return FxGkdImportResult(0, 0, "文件缺少 rules 数组。")
        if (sourceRules.length() > MAX_RULES) {
            return FxGkdImportResult(0, 0, "单个文件最多允许 $MAX_RULES 条规则。")
        }

        val merged = getRules(context).toMutableList()
        val known = merged.map { it.packageName + "\u0000" + it.selector }.toMutableSet()
        var skipped = 0

        for (index in 0 until sourceRules.length()) {
            val item = sourceRules.optJSONObject(index)
            if (item == null) {
                skipped++
                continue
            }
            val packageName = item.optString("package").trim()
            val selector = item.optString("selector").trim()
            val cooldown = item.optLong("cooldown_ms", DEFAULT_COOLDOWN_MS)
            if (!isValidPackageName(packageName) || packageName == context.packageName ||
                selector.isEmpty() || selector.length > 512 ||
                cooldown !in MIN_COOLDOWN_MS..MAX_COOLDOWN_MS ||
                merged.size >= MAX_RULES ||
                !isInstalledUserApplication(context, packageName) ||
                !FxGkdSelectorEngine.compile(selector).isValid ||
                !known.add(packageName + "\u0000" + selector)
            ) {
                skipped++
                continue
            }
            // Never import an enabled action. Users must review and enable it locally.
            merged += FxGkdRule(
                id = UUID.randomUUID().toString(),
                packageName = packageName,
                selector = selector,
                cooldownMillis = cooldown,
                enabled = false
            )
        }

        val imported = merged.size - getRules(context).size
        if (imported == 0) return FxGkdImportResult(0, skipped, "没有可导入的有效新规则。")
        if (!writeRules(context, merged)) {
            return FxGkdImportResult(0, skipped, "规则写入失败，原有规则保持不变。")
        }
        return FxGkdImportResult(imported, skipped, null)
    }

    private fun isInstalledUserApplication(context: Context, packageName: String): Boolean {
        return try {
            val info = context.packageManager.getApplicationInfo(packageName, 0)
            (info.flags and (
                android.content.pm.ApplicationInfo.FLAG_SYSTEM or
                    android.content.pm.ApplicationInfo.FLAG_UPDATED_SYSTEM_APP
            )) == 0
        } catch (_: android.content.pm.PackageManager.NameNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
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
        val committed = editor.commit()
        if (committed) {
            cachedRules = rules.toList()
            cachedRulesRaw = array.toString()
        }
        return committed
    }
}
