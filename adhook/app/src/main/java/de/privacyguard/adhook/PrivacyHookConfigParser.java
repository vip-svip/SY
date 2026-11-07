package de.privacyguard.adhook;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * Strict, side-effect-free reader for the legacy FX privacy-hook configuration.
 *
 * Supports top-level key=value entries and [conf:name]/[list:name] sections.
 * Parsing is transactional: malformed input never produces a partially active
 * configuration. This class deliberately does not install hooks.
 */
public final class PrivacyHookConfigParser {
    private static final Set<String> NEVER_HOOK = Collections.unmodifiableSet(new HashSet<>(Arrays.asList(
            "android", "system", "de.privacyguard.hook",
            "de.privacyguard.adhook", "org.lsposed.manager")));
    private static final Set<String> RISKY = Collections.unmodifiableSet(new HashSet<>(Arrays.asList(
            "block_process_list", "block_pm_query", "block_mounts", "hide_mounts",
            "block_netstats", "block_net_ifaces", "block_cell_info", "block_mediastore",
            "usagestats_off", "k_task", "app_list", "hide_su", "hide_magisk", "hide_ksu",
            "block_rootcheck_libs", "hide_sysfs_nodes", "hide_kernel_debug", "block_logcat",
            "fs_attrs", "fs_hide", "fs_rootlist", "fs_isolate", "fs_vfs",
            "block_notif_listen", "hide_notif_perm", "block_ime_logging", "a11y_hide",
            "syssvc_hide", "clipboard", "clipboard_isolate", "ad_id_unify",
            "block_wifi_scan", "vpn_hide", "block_kernel_version")));
    private static final Set<String> STANDARD = Collections.unmodifiableSet(new HashSet<>(Arrays.asList(
            "hide_su", "hide_magisk", "hide_ksu", "hide_sysfs_nodes",
            "hide_kernel_debug", "block_rootcheck_libs", "ad_id_unify")));

    private PrivacyHookConfigParser() {}

    public static final class Result {
        public final Map<String, String> switches;
        public final Map<String, List<String>> sections;
        public final String profile;

        private Result(Map<String, String> switches,
                       Map<String, List<String>> sections, String profile) {
            this.switches = Collections.unmodifiableMap(new LinkedHashMap<>(switches));
            Map<String, List<String>> copy = new LinkedHashMap<>();
            for (Map.Entry<String, List<String>> entry : sections.entrySet()) {
                copy.put(entry.getKey(), Collections.unmodifiableList(
                        new ArrayList<>(entry.getValue())));
            }
            this.sections = Collections.unmodifiableMap(copy);
            this.profile = profile;
        }

        public boolean enabled(String key) {
            // The master switch gates every feature, including profile-derived risky keys.
            if (!"1".equals(switches.get("lsposed_enabled"))) return false;
            if (RISKY.contains(key) && !"custom".equals(profile)) {
                if ("compat".equals(profile)) return false;
                if ("standard".equals(profile)) return STANDARD.contains(key);
                if ("aggressive".equals(profile)) return true;
            }
            return "1".equals(switches.get(key));
        }

        public List<String> lines(String section) {
            List<String> result = sections.get(section);
            return result == null ? Collections.emptyList() : result;
        }

        public boolean inScope(String packageName) {
            if (packageName == null || NEVER_HOOK.contains(packageName)) return false;
            List<String> allow = lines("conf:lsposed_scope");
            if (allow.isEmpty()) return true; // LSPosed manager scope remains authoritative.
            for (String row : allow) {
                for (String token : row.split(",")) {
                    String candidate = token.trim();
                    if (candidate.isEmpty() || candidate.startsWith("#")) continue;
                    if (candidate.equals(packageName)) return true;
                    if (candidate.endsWith("*")
                            && packageName.startsWith(candidate.substring(0, candidate.length() - 1))) {
                        return true;
                    }
                }
            }
            return false;
        }
    }

    public static Result parse(String text) {
        if (text == null) throw new IllegalArgumentException("null config");
        String[] rows = text.split("\\R", -1);
        if (rows.length > 10001) throw new IllegalArgumentException("config exceeds 10000 lines");
        Map<String, String> switches = new LinkedHashMap<>();
        Map<String, List<String>> sections = new LinkedHashMap<>();
        String current = null;
        for (String raw : rows) {
            String line = raw.trim();
            if (line.isEmpty() || line.startsWith("#")) continue;
            if (line.startsWith("[") || line.endsWith("]")) {
                if (!(line.startsWith("[") && line.endsWith("]") && line.length() > 2)) {
                    throw new IllegalArgumentException("malformed section header");
                }
                String name = line.substring(1, line.length() - 1).trim();
                if (!(name.startsWith("conf:") || name.startsWith("list:"))
                        || name.length() <= 5) {
                    throw new IllegalArgumentException("unsupported section");
                }
                current = name;
                sections.computeIfAbsent(current, ignored -> new ArrayList<>());
                continue;
            }
            if (current == null) {
                int eq = line.indexOf('=');
                if (eq <= 0) throw new IllegalArgumentException("malformed top-level option");
                String key = line.substring(0, eq).trim();
                String value = line.substring(eq + 1).trim();
                if (!key.matches("[A-Za-z0-9_.-]+") || value.isEmpty()) {
                    throw new IllegalArgumentException("invalid top-level option");
                }
                if (switches.putIfAbsent(key, value) != null) {
                    throw new IllegalArgumentException("duplicate top-level option: " + key);
                }
            } else {
                sections.get(current).add(line);
            }
        }
        String master = switches.get("lsposed_enabled");
        if (!"0".equals(master) && !"1".equals(master)) {
            throw new IllegalArgumentException("missing or invalid lsposed_enabled");
        }
        String requested = switches.getOrDefault("lsposed_profile", "custom")
                .trim().toLowerCase(Locale.ROOT);
        String profile = ("compat".equals(requested) || "standard".equals(requested)
                || "aggressive".equals(requested)) ? requested : "custom";
        return new Result(switches, sections, profile);
    }
}
