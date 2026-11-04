package de.privacyguard.adhook.imported.ad;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

import de.privacyguard.adhook.RootAccess;

import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Yulong 7.0.1 Tasker compatibility.
 * Legacy TASKER_START/STOP control the FX unified VPN route; AD_FILTER actions
 * independently control only the Yulong ad-filter master switch.
 */
public final class FxYulongAdTaskerReceiver extends BroadcastReceiver {
    private static final AtomicBoolean AD_REQUEST_PENDING = new AtomicBoolean(false);
    private static final AtomicBoolean VPN_REQUEST_PENDING = new AtomicBoolean(false);

    public static final String ACTION_ENABLE = "de.privacyguard.adhook.AD_FILTER_ENABLE";
    public static final String ACTION_DISABLE = "de.privacyguard.adhook.AD_FILTER_DISABLE";
    public static final String ACTION_VPN_START = "de.privacyguard.adhook.VPN_START";
    public static final String ACTION_VPN_STOP = "de.privacyguard.adhook.VPN_STOP";
    public static final String ACTION_RESULT = "de.privacyguard.adhook.AD_FILTER_RESULT";

    public static final String LEGACY_ACTION_START = "app.pwhs.blockads.TASKER_START";
    public static final String LEGACY_ACTION_STOP = "app.pwhs.blockads.TASKER_STOP";

    private static String modulePrefix() {
        return "MP=''; for d in /data/adb/modules/privacyguard "
                + "/data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard "
                + "/data/adb/modules/pg; do "
                + "if [ -s \"$d/module.prop\" ] && grep -q '^id=privacyguard$' \"$d/module.prop\"; "
                + "then MP=\"$d\"; break; fi; done; "
                + "[ -n \"$MP\" ] || exit 20; ";
    }

    @Override public void onReceive(Context context, Intent intent) {
        if (context == null || intent == null) return;
        String action = intent.getAction();

        final boolean adFilterAction;
        final int enabled;
        if (ACTION_ENABLE.equals(action)) {
            adFilterAction = true;
            enabled = 1;
        } else if (ACTION_DISABLE.equals(action)) {
            adFilterAction = true;
            enabled = 0;
        } else if (LEGACY_ACTION_START.equals(action) || ACTION_VPN_START.equals(action)) {
            adFilterAction = false;
            enabled = 1;
        } else if (LEGACY_ACTION_STOP.equals(action) || ACTION_VPN_STOP.equals(action)) {
            adFilterAction = false;
            enabled = 0;
        } else {
            return;
        }

        // Serialize only within the same control plane. Ad-master writes also
        // use the shared UI/tile transaction gate; VPN changes use their own
        // module lifecycle lock and must not block independent ad-filter actions.
        final AtomicBoolean requestPending =
                adFilterAction ? AD_REQUEST_PENDING : VPN_REQUEST_PENDING;
        if (!requestPending.compareAndSet(false, true)) {
            publishResult(context, action, adFilterAction, enabled, false, 75, "请求繁忙");
            return;
        }

        // Only ad-master writes share the ad transaction gate. VPN route changes
        // use the module-side yulong-vpn-control.sh lock.
        final long gateToken = adFilterAction ? FxYulongAdOperationGate.tryAcquire() : 0L;
        if (adFilterAction && gateToken == 0L) {
            requestPending.set(false);
            publishResult(context, action, true, enabled, false, 75, "广告过滤正在被其他入口修改");
            return;
        }

        final PendingResult pending;
        try {
            pending = goAsync();
        } catch (RuntimeException unavailable) {
            if (gateToken != 0L) FxYulongAdOperationGate.release(gateToken);
            requestPending.set(false);
            publishResult(context, action, adFilterAction, enabled, false, 127, "无法启动后台任务");
            return;
        }

        try {
            new Thread(() -> {
                int code = 127;
                String output = "";
                try {
                    String operation = adFilterAction
                            ? "sh \"$MP/scripts/yulong-ad-control.sh\" ad-master " + enabled
                            : "sh \"$MP/scripts/yulong-vpn-control.sh\" \"$MP\" /data/adb/privacyguard "
                                    + (enabled == 1 ? "start" : "stop");
                    RootAccess.Result result = RootAccess.execute(modulePrefix() + operation,
                            adFilterAction ? 90000L : 150000L, 512 * 1024);
                    code = result.exitCode;
                    output = result.output == null ? "" : result.output.trim();
                    if (code == 0 && !adFilterAction) FxYulongAdWidgetProvider.refreshAll(context);
                } catch (Throwable failure) {
                    output = failure.getClass().getSimpleName() + ": "
                            + (failure.getMessage() == null ? "Root 操作失败" : failure.getMessage());
                }
                try {
                    publishResult(context, action, adFilterAction, enabled, code == 0, code, output);
                } finally {
                    if (gateToken != 0L) FxYulongAdOperationGate.release(gateToken);
                    requestPending.set(false);
                    pending.finish();
                }
            }, "fx-yulong-tasker-command").start();
        } catch (RuntimeException startError) {
            if (gateToken != 0L) FxYulongAdOperationGate.release(gateToken);
            requestPending.set(false);
            try {
                publishResult(context, action, adFilterAction, enabled, false, 127,
                        startError.getClass().getSimpleName());
            } finally {
                pending.finish();
            }
        }
    }

    private static void publishResult(Context context, String action, boolean adFilterAction,
                                      int enabled, boolean success, int exitCode, String detail) {
        try {
            Intent reply = new Intent(ACTION_RESULT);
            reply.putExtra("source_action", action);
            reply.putExtra("target", adFilterAction ? "ad_filter" : "vpn");
            reply.putExtra("requested_enabled", enabled);
            reply.putExtra("success", success);
            reply.putExtra("exit_code", exitCode);
            reply.putExtra("detail", detail == null ? "" : detail);
            reply.setPackage(context.getPackageName());
            context.sendBroadcast(reply);
        } catch (RuntimeException ignored) { }
    }
}
