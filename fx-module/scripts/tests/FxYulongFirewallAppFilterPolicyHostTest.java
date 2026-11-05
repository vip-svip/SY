package de.privacyguard.adhook.imported.ad;

/** Standalone JDK regression test; no Android SDK or JUnit dependency. */
public final class FxYulongFirewallAppFilterPolicyHostTest {
    private static int assertions;

    private static void check(boolean expected, boolean actual, String label) {
        assertions++;
        if (expected != actual) {
            throw new AssertionError(label + ": expected=" + expected + " actual=" + actual);
        }
    }

    private static void rejectFirewallList(String input, String label) {
        try {
            FxYulongFirewallListParser.parse(input);
        } catch (IllegalArgumentException expected) {
            assertions++;
            return;
        }
        throw new AssertionError(label + ": malformed firewall list response was accepted");
    }

    public static void main(String[] args) {
        int all = FxYulongFirewallAppFilterPolicy.ALL_APPS;
        int users = FxYulongFirewallAppFilterPolicy.USER_APPS;
        int system = FxYulongFirewallAppFilterPolicy.SYSTEM_APPS;
        int flagSystem = 1;
        int flagUpdatedSystem = 128;

        check(true, FxYulongFirewallAppFilterPolicy.includes(all, 0), "all/user");
        check(true, FxYulongFirewallAppFilterPolicy.includes(all, flagSystem), "all/system");
        check(true, FxYulongFirewallAppFilterPolicy.includes(users, 0), "users/user");
        check(false, FxYulongFirewallAppFilterPolicy.includes(users, flagSystem), "users/system");
        check(false, FxYulongFirewallAppFilterPolicy.includes(users, flagUpdatedSystem), "users/updated-system");
        check(false, FxYulongFirewallAppFilterPolicy.includes(users,
                flagSystem | flagUpdatedSystem), "users/both-system-flags");
        check(false, FxYulongFirewallAppFilterPolicy.includes(system, 0), "system/user");
        check(true, FxYulongFirewallAppFilterPolicy.includes(system, flagSystem), "system/system");
        check(true, FxYulongFirewallAppFilterPolicy.includes(system, flagUpdatedSystem), "system/updated-system");
        check(true, FxYulongFirewallAppFilterPolicy.includes(system,
                flagSystem | flagUpdatedSystem), "system/both-system-flags");
        check(false, FxYulongFirewallAppFilterPolicy.includes(99, 0), "unknown mode");
        check(true, FxYulongFirewallAppFilterPolicy.countUidMembers(
                10123, new int[]{10123, 10124, 10125}) == 1, "unique UID package count");
        check(true, FxYulongFirewallAppFilterPolicy.countUidMembers(
                10123, new int[]{10123, 10124, 10123, 10125}) == 2, "shared UID package count");
        check(true, FxYulongFirewallAppFilterPolicy.countUidMembers(
                10222, new int[]{10123, 10124}) == 0, "unknown UID package count");
        check(true, FxYulongFirewallAppFilterPolicy.countUidMembers(
                0, new int[]{0, 10123}) == 0, "invalid UID rejected");
        check(true, FxYulongFirewallAppFilterPolicy.countUidMembers(
                10123, null) == 0, "missing inventory is not treated as a shared UID");
        String validFirewallList = "FXYULONGFW2\nmaster=1\n"
                + "com.example.one|10123|1|1|0|0|22:00|06:00\n"
                + "com.example.two|10123|0|0|1|1|23:00|07:30\n";
        FxYulongFirewallListParser.Snapshot parsed = FxYulongFirewallListParser.parse(validFirewallList);
        check(true, parsed.masterEnabled, "firewall list master state");
        check(true, parsed.rules.size() == 2, "firewall list row count");
        FxYulongFirewallListParser.Rule one = parsed.rules.get("com.example.one");
        check(true, one != null && one.uid == 10123 && one.enabled && one.blockWifi
                && !one.blockMobile && !one.scheduleEnabled, "firewall list rule fields");
        FxYulongFirewallListParser.Rule two = parsed.rules.get("com.example.two");
        check(true, two != null && two.uid == 10123 && !two.enabled && !two.blockWifi
                && two.blockMobile && two.scheduleEnabled
                && "23:00".equals(two.startTime) && "07:30".equals(two.endTime),
                "shared UID entries preserve independent saved profiles");
        rejectFirewallList(null, "missing response");
        rejectFirewallList("master=0\n", "missing header");
        rejectFirewallList("FXYULONGFW2\n", "missing master");
        rejectFirewallList("FXYULONGFW2\nmaster=maybe\n", "invalid master");
        rejectFirewallList("FXYULONGFW2\nmaster=0\nmaster=1\n", "duplicate master");
        rejectFirewallList("FXYULONGFW2\nmaster=0\nnot-a-rule\n", "malformed row");
        rejectFirewallList("FXYULONGFW2\nmaster=0\ncom.example.app|0|1|1|1|0|22:00|06:00\n",
                "zero UID");
        rejectFirewallList("FXYULONGFW2\nmaster=0\ncom.example.app|uid|1|1|1|0|22:00|06:00\n",
                "non-numeric UID");
        rejectFirewallList("FXYULONGFW2\nmaster=0\ncom.example.app|10123|2|1|1|0|22:00|06:00\n",
                "invalid state bit");
        rejectFirewallList("FXYULONGFW2\nmaster=0\ncom.example.app|10123|1|1|1|0|24:00|06:00\n",
                "invalid time");
        rejectFirewallList("FXYULONGFW2\nmaster=0\ncom.example.app|10123|1|1|1|0|22:00|06:00|extra\n",
                "extra field");
        rejectFirewallList("FXYULONGFW2\nmaster=0\ncom.example.app|10123|1|1|1|0|22:00|06:00\n"
                + "com.example.app|10123|0|1|1|0|22:00|06:00\n", "duplicate package");
        rejectFirewallList("FXYULONGFW2\nmaster=0\nFXYULONGFW2\n", "duplicate header");
        System.out.println("PASS: " + assertions + " firewall policy/list protocol assertions");
    }
}
