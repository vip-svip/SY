package de.privacyguard.adhook.imported.dia;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;
import android.content.SharedPreferences;
import android.os.Build;

import de.privacyguard.adhook.RootAccess;

import java.net.IDN;
import java.util.Locale;

/** Dia Wi-Fi proxy quick-settings toggle migrated into the single FX APK. */
public final class FxDiaWifiProxyTileService extends TileService {
    private static final String PREFS = "fx_dia_wifi_proxy";
    private final ThreadPoolExecutor worker = new ThreadPoolExecutor(
            1, 1, 30L, TimeUnit.SECONDS, new ArrayBlockingQueue<>(2),
            r -> { Thread t = new Thread(r, "fx-dia-wifi-proxy-tile"); t.setDaemon(true); return t; },
            new ThreadPoolExecutor.AbortPolicy());

    private void submitWorker(Runnable task) {
        try {
            worker.execute(task);
        } catch (RejectedExecutionException full) {
            new android.os.Handler(getMainLooper()).post(() -> {
                android.widget.Toast.makeText(this,
                        "Dia 快速设置任务繁忙，本次操作未执行；请稍后重试。",
                        android.widget.Toast.LENGTH_LONG).show();
                refreshTile();
            });
        }
    }

    private SharedPreferences prefs() {
        return getSharedPreferences(PREFS, MODE_PRIVATE);
    }
    private String quote(String value) {
        return "'" + value.replace("'", "'\\''") + "'";
    }
    private void refreshTile(FxDiaWifiProxyState.Status state) {
        Tile tile = getQsTile();
        if (tile == null) return;
        boolean active = state == FxDiaWifiProxyState.Status.ACTIVE;
        tile.setState(active ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        tile.setLabel("FX 系统代理");
        switch (state) {
            case ACTIVE:
                tile.setSubtitle("已启用");
                tile.setContentDescription("FX 系统 HTTP 代理与记录一致，点击恢复原设置");
                break;
            case EXTERNALLY_CHANGED:
                tile.setSubtitle("系统值已外部更改");
                tile.setContentDescription("系统代理已被外部更改，FX 不会覆盖；请打开 FX 系统代理页面解除管理");
                break;
            case UNKNOWN:
                tile.setSubtitle("状态未知");
                tile.setContentDescription("无法读取系统代理状态，请检查 KernelSU Root 授权");
                break;
            default:
                tile.setSubtitle("已关闭");
                tile.setContentDescription("FX 系统 HTTP 代理已关闭，点击启用");
                break;
        }
        tile.updateTile();
    }

    private FxDiaWifiProxyState.Status queryLiveState() {
        String current = readCurrentProxy();
        if (current == null) return FxDiaWifiProxyState.Status.UNKNOWN;
        return FxDiaWifiProxyState.evaluate(prefs().getBoolean("active", false),
                current, prefs().getString("applied", ""), true);
    }

    private String readCurrentProxy() {
        RootAccess.Result result = RootAccess.execute(
                "settings get global http_proxy 2>/dev/null | tr -d '\\r'", 12000L, 4096);
        if (result.exitCode != 0 || result.output == null) return null;
        return result.output.trim();
    }

    private void showMessage(String message) {
        new android.os.Handler(getMainLooper()).post(() ->
                android.widget.Toast.makeText(this, message,
                        android.widget.Toast.LENGTH_LONG).show());
    }

    @Override public void onStartListening() {
        super.onStartListening();
        submitWorker(() -> {
            FxDiaWifiProxyState.Status live = queryLiveState();
            android.os.Handler handler = new android.os.Handler(getMainLooper());
            handler.post(() -> refreshTile(live));
        });
    }

    @Override public void onClick() {
        super.onClick();
        unlockAndRun(() -> submitWorker(() -> toggleProxy()));
    }

    private void toggleProxy() {
        SharedPreferences p = prefs();
        String expected = p.getString("applied", "");
        String previous = p.getString("previous", "null");
        String target;
        String current = readCurrentProxy();
        if (current == null) {
            showMessage("无法读取系统代理，未执行切换；请检查 KernelSU Root 授权。");
            refreshTile(FxDiaWifiProxyState.Status.UNKNOWN);
            return;
        }
        FxDiaWifiProxyState.Status before = FxDiaWifiProxyState.evaluate(
                p.getBoolean("active", false), current, expected, true);
        if (before == FxDiaWifiProxyState.Status.EXTERNALLY_CHANGED) {
            showMessage("系统代理已被其他程序或用户更改。FX 为避免覆盖外部设置，本次切换未执行；请打开代理管理页面解除 FX 管理。");
            refreshTile(before);
            return;
        }
        boolean active = FxDiaWifiProxyState.mayRestore(before);

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
            } else {
                android.util.Log.w("FXDiaProxyTile", "restore failed: " + safe(result.output));
                showMessage(result.output != null && result.output.contains("FX_PROXY_CONFLICT")
                        ? "系统代理在切换期间被外部更改，FX 未恢复或覆盖。"
                        : "恢复系统代理失败：" + safe(result.output));
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
                android.util.Log.w("FXDiaProxyTile", "apply failed: " + safe(result.output));
                showMessage("启用系统代理失败：" + safe(result.output));
            }
        }
        FxDiaWifiProxyState.Status after = queryLiveState();
        android.os.Handler handler = new android.os.Handler(getMainLooper());
        handler.post(() -> refreshTile(after));
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
