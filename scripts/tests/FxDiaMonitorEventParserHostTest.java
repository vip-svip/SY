package de.privacyguard.adhook.imported.dia;

import java.util.List;
import java.util.Map;

/** Standalone JDK regression for the Dia monitor parser; no Android runtime required. */
public final class FxDiaMonitorEventParserHostTest {
    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    public static void main(String[] args) {
        String line = "[DIA_APPENTRY] stage=newActivity activity=com.example.MainActivity "
                + "action=android.intent.action.MAIN intentPackage=com.example.app "
                + "extras=sessionToken data=https://example.com/path component=secret.Component";
        List<FxDiaMonitorEventParser.Event> events = FxDiaMonitorEventParser.parse(line);
        require(events.size() == 1, "APPENTRY event must be retained");
        FxDiaMonitorEventParser.Event event = events.get(0);
        require("Activity 入口".equals(event.category), "APPENTRY category missing");
        require("newActivity".equals(event.fields.get("stage")), "stage field missing");
        require("com.example.MainActivity".equals(event.fields.get("activity")), "Activity class missing");
        require("android.intent.action.MAIN".equals(event.fields.get("action")), "action metadata missing");
        require("com.example.app".equals(event.fields.get("intentPackage")), "Intent package metadata missing");
        require(!event.fields.containsKey("extras"), "Intent extras must never be retained");
        require(!event.fields.containsKey("data"), "Intent URI/data must never be retained");
        require(!event.fields.containsKey("component"), "component object must never be retained");
        require(!event.toDisplayString().contains("sessionToken"), "secret leaked into display string");
        require(!event.toDisplayString().contains("https://"), "URI leaked into display string");

        List<FxDiaMonitorEventParser.Event> filtered = FxDiaMonitorEventParser.parse(
                "[DIA_APPENTRY] stage=callActivityOnCreate activity=com.example.HomeActivity "
                + "action=android.intent.action.VIEW intentPackage=com.example.app "
                + "uri=https://evil.example data=private extras=password");
        require(filtered.size() == 1, "second APPENTRY event dropped");
        Map<String, String> fields = filtered.get(0).fields;
        require(fields.size() == 4, "APPENTRY allowlist must contain exactly four metadata fields");

        require(FxDiaMonitorEventParser.parse("[DIA_UNTRUSTED] token=secret").isEmpty(),
                "unknown event tags must remain ignored");
        System.out.println("PASS: Activity entry observer events render as safe metadata");
    }
}
