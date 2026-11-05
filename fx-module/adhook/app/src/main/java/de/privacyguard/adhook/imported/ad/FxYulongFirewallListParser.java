package de.privacyguard.adhook.imported.ad;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.regex.Pattern;

/** Strict parser for the Root-owned FXYULONGFW2 firewall list protocol. */
public final class FxYulongFirewallListParser {
    private static final String HEADER = "FXYULONGFW2";
    private static final Pattern PACKAGE = Pattern.compile(
            "^[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_-]+)+$");
    private static final Pattern TIME = Pattern.compile(
            "^(?:[01][0-9]|2[0-3]):[0-5][0-9]$");

    private FxYulongFirewallListParser() { }

    public static final class Rule {
        public final int uid;
        public final boolean enabled, blockWifi, blockMobile, scheduleEnabled;
        public final String startTime, endTime;
        private Rule(int uid, boolean enabled, boolean blockWifi, boolean blockMobile,
                     boolean scheduleEnabled, String startTime, String endTime) {
            this.uid = uid;
            this.enabled = enabled;
            this.blockWifi = blockWifi;
            this.blockMobile = blockMobile;
            this.scheduleEnabled = scheduleEnabled;
            this.startTime = startTime;
            this.endTime = endTime;
        }
    }

    public static final class Snapshot {
        public final boolean masterEnabled;
        public final Map<String, Rule> rules;
        private Snapshot(boolean masterEnabled, Map<String, Rule> rules) {
            this.masterEnabled = masterEnabled;
            this.rules = Collections.unmodifiableMap(new HashMap<>(rules));
        }
    }

    public static Snapshot parse(String output) {
        if (output == null) throw new IllegalArgumentException("missing firewall list response");
        int phase = 0;
        boolean masterEnabled = false;
        Map<String, Rule> rules = new HashMap<>();
        for (String line : output.split("\\r?\\n", -1)) {
            if (line.isEmpty()) continue;
            if (phase == 0) {
                if (!HEADER.equals(line)) throw new IllegalArgumentException("invalid firewall list header");
                phase = 1;
                continue;
            }
            if (phase == 1) {
                if (!line.startsWith("master=")) throw new IllegalArgumentException("missing firewall master state");
                String value = line.substring(7);
                if (!"0".equals(value) && !"1".equals(value))
                    throw new IllegalArgumentException("invalid firewall master state");
                masterEnabled = "1".equals(value);
                phase = 2;
                continue;
            }
            if (line.startsWith("master=") || HEADER.equals(line))
                throw new IllegalArgumentException("duplicate firewall header/state");

            String[] fields = line.split("\\|", -1);
            if (fields.length != 8 || !PACKAGE.matcher(fields[0]).matches())
                throw new IllegalArgumentException("invalid firewall rule row");
            final int uid;
            try {
                uid = Integer.parseInt(fields[1]);
            } catch (NumberFormatException invalidUid) {
                throw new IllegalArgumentException("invalid firewall rule UID");
            }
            if (uid <= 0 || !bit(fields[2]) || !bit(fields[3]) || !bit(fields[4])
                    || !bit(fields[5]) || !TIME.matcher(fields[6]).matches()
                    || !TIME.matcher(fields[7]).matches())
                throw new IllegalArgumentException("invalid firewall rule fields");
            if (rules.containsKey(fields[0]))
                throw new IllegalArgumentException("duplicate firewall package rule");
            rules.put(fields[0], new Rule(uid, "1".equals(fields[2]), "1".equals(fields[3]),
                    "1".equals(fields[4]), "1".equals(fields[5]), fields[6], fields[7]));
        }
        if (phase != 2) throw new IllegalArgumentException("incomplete firewall list response");
        return new Snapshot(masterEnabled, rules);
    }

    private static boolean bit(String value) {
        return "0".equals(value) || "1".equals(value);
    }
}
