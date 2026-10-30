package de.privacyguard.adhook;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * Strict parser for the tiny, root-generated FXAdHook Remote Files payload.
 *
 * The payload intentionally contains only hook_ads_enabled and the explicit
 * [list:hook_targets] section. Parsing is transactional: callers get a Result
 * only if the entire file is valid, so one malformed row cannot leave a
 * partially active target list.
 */
public final class HookTargetConfigParser {
    private static final Set<String> NEVER = Collections.unmodifiableSet(new HashSet<>(Arrays.asList(
            "android", "system", "de.privacyguard.hook", "de.privacyguard.adhook", "org.lsposed.manager")));

    private HookTargetConfigParser() {}

    public static final class Target {
        public final boolean splash;
        public final boolean feed;
        public final boolean overlay;
        public final boolean memberDiag;

        Target(boolean splash, boolean feed, boolean overlay, boolean memberDiag) {
            this.splash = splash;
            this.feed = feed;
            this.overlay = overlay;
            this.memberDiag = memberDiag;
        }

        public boolean enabled() {
            return splash || feed || overlay || memberDiag;
        }
    }

    public static final class Result {
        public final boolean adsEnabled;
        public final Map<String, Target> targets;

        private Result(boolean adsEnabled, Map<String, Target> targets) {
            this.adsEnabled = adsEnabled;
            this.targets = Collections.unmodifiableMap(new LinkedHashMap<>(targets));
        }

        /** Ad filtering is gated by its own master switch. */
        public boolean isAdFilteringEnabledFor(String packageName) {
            Target target = targets.get(packageName);
            return adsEnabled && target != null
                    && (target.splash || target.feed || target.overlay);
        }

        /** Read-only membership diagnostics are deliberately independent of ad filtering. */
        public boolean isMemberDiagnosticsEnabledFor(String packageName) {
            Target target = targets.get(packageName);
            return target != null && target.memberDiag;
        }

        public boolean isAnyFeatureEnabledFor(String packageName) {
            return isAdFilteringEnabledFor(packageName)
                    || isMemberDiagnosticsEnabledFor(packageName);
        }
    }

    public static Result parse(String text) {
        if (text == null) throw new IllegalArgumentException("null config");
        String[] lines = text.split("\\R", -1);
        if (lines.length > 1001) throw new IllegalArgumentException("config exceeds 1000 lines");

        Map<String, Target> parsedTargets = new LinkedHashMap<>();
        boolean masterSeen = false;
        boolean parsedAdsEnabled = false;
        boolean targetSectionSeen = false;
        String section = "";

        for (String raw : lines) {
            String line = raw.trim();
            if (line.isEmpty() || line.startsWith("#")) continue;

            if (line.startsWith("[") || line.endsWith("]")) {
                if (!(line.startsWith("[") && line.endsWith("]") && line.length() > 2)) {
                    throw new IllegalArgumentException("malformed section header");
                }
                String nextSection = line.substring(1, line.length() - 1).trim();
                if (!"list:hook_targets".equals(nextSection)) {
                    throw new IllegalArgumentException("unsupported section");
                }
                if (targetSectionSeen) throw new IllegalArgumentException("duplicate target section");
                targetSectionSeen = true;
                section = nextSection;
                continue;
            }

            if (section.isEmpty()) {
                int eq = line.indexOf('=');
                if (eq <= 0) throw new IllegalArgumentException("malformed top-level option");
                String key = line.substring(0, eq).trim();
                String value = line.substring(eq + 1).trim();
                if (!"hook_ads_enabled".equals(key)) {
                    throw new IllegalArgumentException("unsupported top-level option");
                }
                if (masterSeen) throw new IllegalArgumentException("duplicate hook_ads_enabled");
                if (!("0".equals(value) || "1".equals(value))) {
                    throw new IllegalArgumentException("invalid hook_ads_enabled value");
                }
                masterSeen = true;
                parsedAdsEnabled = "1".equals(value);
                continue;
            }

            // FX list rows allow human-readable metadata after the first '|'.
            int metadata = line.indexOf('|');
            String config = (metadata >= 0 ? line.substring(0, metadata) : line).trim();
            String[] parts = config.split(",", -1);
            if (parts.length < 2) throw new IllegalArgumentException("malformed target row");

            String pkg = parts[0].trim();
            if (!validPackage(pkg) || NEVER.contains(pkg)) {
                throw new IllegalArgumentException("invalid or protected target package");
            }
            if (parsedTargets.containsKey(pkg)) throw new IllegalArgumentException("duplicate target package");

            boolean splash = false;
            boolean feed = false;
            boolean overlay = false;
            boolean memberDiag = false;
            Set<String> seenKeys = new HashSet<>();
            for (int i = 1; i < parts.length; i++) {
                int eq = parts[i].indexOf('=');
                if (eq <= 0) throw new IllegalArgumentException("malformed target option");
                String key = parts[i].substring(0, eq).trim();
                String value = parts[i].substring(eq + 1).trim();
                if (!seenKeys.add(key)) throw new IllegalArgumentException("duplicate target option");
                if (!("0".equals(value) || "1".equals(value))) {
                    throw new IllegalArgumentException("invalid target option value");
                }
                boolean enabled = "1".equals(value);
                switch (key) {
                    case "splash": splash = enabled; break;
                    case "feed": feed = enabled; break;
                    case "overlay": overlay = enabled; break;
                    case "member_diag": memberDiag = enabled; break;
                    default: throw new IllegalArgumentException("unsupported target option");
                }
            }
            parsedTargets.put(pkg, new Target(splash, feed, overlay, memberDiag));
        }

        if (!masterSeen) throw new IllegalArgumentException("missing hook_ads_enabled");
        return new Result(parsedAdsEnabled, parsedTargets);
    }

    private static boolean validPackage(String pkg) {
        return pkg != null && pkg.matches("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+");
    }
}
