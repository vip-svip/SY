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
        System.out.println("PASS: " + assertions + " Yulong Firewall app filter assertions");
    }
}
