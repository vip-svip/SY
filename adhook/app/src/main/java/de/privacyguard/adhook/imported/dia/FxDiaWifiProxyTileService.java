package de.privacyguard.adhook.imported.dia;

import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;
import android.content.SharedPreferences;
import android.os.Build;

import de.privacyguard.adhook.RootAccess;

import java.net.IDN;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Dia Wi-Fi proxy quick-settings toggle migrated into the single FX APK. */
public final class FxDiaWifiProxyTileService extends TileService {
    private static final String PREFS = "fx_dia_wifi_proxy";
    private final ExecutorService worker = Executors.newSingleThreadExecutor();

    private SharedPreferences prefs() {
        return getSharedPreferences(PREFS, MODE_PRIVATE);
    }
    private String quote(String value) {
        return "'" + value.replace("'", "'\\''") + "'";
    }
    private void refreshTile() {
        refreshTile(prefs().getBoolean("active", false));
    }

    private void refreshTile(boolean active) {
        Tile tile = getQsTile();
        if (tile == null) return;
        tile.setState(active ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        tile.setLabel("FX 系统代理");
        tile.setSubtitle(active ? "已启用" : "已关闭");
        tile.setContentDescription(active
                ? "FX 系统 HTTP 代理已启用，点击恢复原设置"
                : "FX 系统 HTTP 代理已关闭或已被外部更改，点击启用");
        tile.updateTile();
    }

    @Override public void onStartListening() {
        super.onStartListening();
        worker.execute(() -> {
            RootAccess.Result result = RootAccess.execute(
                    "settings get global http_proxy 2>/dev/null | tr -d '\\r'", 12000L, 4096);
            boolean active = false;
            if (result.exitCode == 0 && result.output != null) {
                String current = result.output.trim();
                String expected = prefs().getString("applied", "");
                active = prefs().getBoolean("active", false) && current.equals(expected);
            }
            final boolean liveActive = active;
            android.os.Handler handler = new android.os.Handler(getMainLooper());
            handler.post(() -> refreshTile(liveActive));
        });
    }

    @Override public void onClick() {
        super.onClick();
        unlockAndRun(() -> worker.execute(() -> toggleProxy()));
    }

    private void toggleProxy() {
        SharedPreferences p = prefs();
        boolean active = p.getBoolean("active", false);
        String expected = p.getString("applied", "");
        String previous = p.getString("previous", "null");
        String target;

        if (active) {
            String command = "set -eu; current=$(settings get global http_proxy 2>/dev/null | tr -d '\\r'); "
                    + "[ \"$current\" = " + quote(expected) + " ] || { echo FX_PROXY_CONFLICT; exit 30; }; "
                    + "if [ " + quote(previous) + " = null ]; then settings delete global http_proxy; "
                    + "else settings put global http_proxy " + quote(previous) + "; fi; "
                    + "actual=$(settings get global http_proxy 2>/dev/null | tr -d '\\r'); "
                    + "if [ " + quote(previous) + " = null ]; then "
                    + "[ -z \"$actual\" ] || [ \"$actual\" = null ] || exit 31; "
                    + "else [ \"$actual\" = " + quote(previous) + " ] || exit 31; fi; "
                    + "echo FX_PROXY_RESTORED";
            RootAccess.Result result = RootAccess.execute(command, 20000L, 8192);
            if (result.exitCode == 0 && result.output != null && result.output.contains("FX_PROXY_RESTORED")) {
                p.edit().putBoolean("active", false).remove("previous").remove("applied").apply();
            } else if (Build.VERSION.SDK_INT >= 24) {
                android.util.Log.w("FXDiaProxyTile", "restore failed: " + safe(result.output));
            }
        } else {
            try {
                String host = p.getString("host", "127.0.0.1").trim();
                if (host.startsWith("[") && host.endsWith("]")) {
                    String ipv6 = host.substring(1, host.length() - 1);
                    if (!ipv6.matches("[0-9A-Fa-f:.]+") || ipv6.indexOf(':') < 0) return;
                    host = "[" + ipv6 + "]";
                } else {
                    host = IDN.toASCII(host, IDN.USE_STD3_ASCII_RULES).toLowerCase(Locale.ROOT);
                    if (!host.matches("[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?")) return;
                    for (String label : host.split("\\.", -1))
                        if (label.isEmpty() || label.length() > 63
                                || label.startsWith("-") || label.endsWith("-")) return;
                }
                int port = Integer.parseInt(p.getString("port", "8080"));
                if (port < 1 || port > 65535) return;
                target = host + ":" + port;
            } catch (Exception invalid) { return; }

            String command = "set -eu; current=$(settings get global http_proxy 2>/dev/null | tr -d '\\r'); "
                    + "[ -n \"$current\" ] || current=null; "
                    + "settings put global http_proxy " + quote(target) + "; "
                    + "actual=$(settings get global http_proxy 2>/dev/null | tr -d '\\r'); "
                    + "if [ \"$actual\" != " + quote(target) + " ]; then "
                    + "if [ \"$current\" = null ]; then settings delete global http_proxy; "
                    + "else settings put global http_proxy \"$current\"; fi; "
                    + "echo FX_PROXY_WRITE_FAILED; exit 31; fi; "
                    + "printf 'PREVIOUS=%s\\nAPPLIED=%s\\n' \"$current\" \"$actual\"";
            RootAccess.Result result = RootAccess.execute(command, 20000L, 8192);
            if (result.exitCode == 0 && result.output != null
                    && result.output.contains("APPLIED=" + target)) {
                p.edit().putBoolean("active", true)
                        .putString("previous", extract(result.output, "PREVIOUS="))
                        .putString("applied", target).apply();
            } else {
                if (Build.VERSION.SDK_INT >= 24)
                    android.util.Log.w("FXDiaProxyTile", "apply failed: " + safe(result.output));
            }
        }
        if (Build.VERSION.SDK_INT >= 24) {
            android.os.Handler handler = new android.os.Handler(getMainLooper());
            handler.post(this::refreshTile);
        }
    }

    private String extract(String output, String prefix) {
        for (String line : output.split("\\r?\\n"))
            if (line.startsWith(prefix)) return line.substring(prefix.length());
        return "";
    }
    private String safe(String value) {
        return value == null ? "" : value.replace('\n', ' ').replace('\r', ' ');
    }

    @Override public void onStopListening() {
        super.onStopListening();
    }

    @Override public void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }
}
