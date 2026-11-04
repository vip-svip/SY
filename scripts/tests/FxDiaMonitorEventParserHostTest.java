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
        List<FxDiaMonitorEventParser.Event> network = FxDiaMonitorEventParser.parse(
                "[DIA_HTTP] method=GET host=https://alice:secret@api.example.com/private status=200 "
                        + "endpoint=alice:secret@api.example.com:443\n"
                        + "[DIA_HTTP] method=GET host=api.example.com:8443 status=204\n"
                        + "[DIA_SOCKET] endpoint=socket.example.com:443 timeoutMs=1000");
        require(network.size() == 3, "network metadata rows should be retained");
        require(!network.get(0).fields.containsKey("host"), "URL credentials/path must not be displayed as host");
        require(!network.get(0).fields.containsKey("endpoint"), "URL credentials must not be displayed as endpoint");
        require("api.example.com:8443".equals(network.get(1).fields.get("host")),
                "valid host:port must be retained");
        require("socket.example.com:443".equals(network.get(2).fields.get("endpoint")),
                "valid endpoint must be retained");
        List<FxDiaMonitorEventParser.Event> invalid = FxDiaMonitorEventParser.parse(
                "[DIA_HTTP] host=api.example.com:70000 status=200\n"
                        + "[DIA_HTTP] host=192.168.1.999 status=200");
        require(!invalid.get(0).fields.containsKey("host"), "out-of-range port must be rejected");
        require(!invalid.get(1).fields.containsKey("host"), "invalid IPv4 must be rejected");
        System.out.println("PASS: Dia monitor parser hides network URL credentials and paths");
    }
}
