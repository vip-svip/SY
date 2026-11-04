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

    public static final String PREFS_NAME = "fx_yulong_tasker";
    public static final String PREF_ALLOW_EXTERNAL = "allow_external_actions";
    public static final String PREF_LAST_ACTION = "last_action";
    public static final String PREF_LAST_TARGET = "last_target";
    public static final String PREF_LAST_ENABLED = "last_requested_enabled";
    public static final String PREF_LAST_SUCCESS = "last_success";
    public static final String PREF_LAST_EXIT_CODE = "last_exit_code";
    public static final String PREF_LAST_DETAIL = "last_detail";
    public static final String PREF_LAST_AT = "last_at";
    private static final int MAX_RESULT_DETAIL_CHARS = 2048;

    public static final String LEGACY_ACTION_START = "app.pwhs.blockads.TASKER_START";
    public static final String LEGACY_ACTION_STOP = "app.pwhs.blockads.TASKER_STOP";

    private static String modulePrefix(String requiredScript) {
        if (requiredScript == null
                || !("yulong-ad-control.sh".equals(requiredScript)
                    || "yulong-vpn-control.sh".equals(requiredScript))) {
            throw new IllegalArgumentException("不支持的游龙控制脚本。");
        }
        return "[ ! -L '/data' ] && [ ! -L '/data/adb' ] && [ -d '/data/adb' ] || exit 71; "
                + "MP=''; for d in /data/adb/modules/privacyguard "
                + "/data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard "
                + "/data/adb/modules/pg; do "
                + "if [ -d \"$d\" ] && [ ! -L \"$d\" ] "
                + "&& [ -f \"$d/module.prop\" ] && [ ! -L \"$d/module.prop\" ] "
                + "&& grep -qx 'id=privacyguard' \"$d/module.prop\" "
                + "&& grep -qx 'version=1.0.0' \"$d/module.prop\" "
                + "&& [ -d \"$d/scripts\" ] && [ ! -L \"$d/scripts\" ] "
                + "&& [ -f \"$d/scripts/" + requiredScript + "\" ] "
                + "&& [ ! -L \"$d/scripts/" + requiredScript + "\" ]; then "
                + "MP=\"$d\"; break; fi; done; "
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

        // The receiver is exported for Tasker compatibility. Because these
        // broadcasts can invoke Root-backed operations, require an explicit
        // opt-in from the FX General Settings screen before accepting any action.
        if (!context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(PREF_ALLOW_EXTERNAL, false)) {
            publishResult(context, action, adFilterAction, enabled, false, 13,
                    "外部自动化控制尚未在 FX 通用设置中授权；请求未执行。");
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
                    RootAccess.Result result = RootAccess.execute(modulePrefix(adFilterAction ? "yulong-ad-control.sh" : "yulong-vpn-control.sh") + operation,
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
        String safeDetail = detail == null ? "" : detail;
        if (safeDetail.length() > MAX_RESULT_DETAIL_CHARS) {
            safeDetail = safeDetail.substring(0, MAX_RESULT_DETAIL_CHARS) + "…（已截断）";
        }
        String target = adFilterAction ? "ad_filter" : "vpn";
        try {
            // Persist before broadcasting so the General Settings page can still
            // show the most recent result after its Activity/process was stopped.
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                    .putString(PREF_LAST_ACTION, action == null ? "" : action)
                    .putString(PREF_LAST_TARGET, target)
                    .putInt(PREF_LAST_ENABLED, enabled)
                    .putBoolean(PREF_LAST_SUCCESS, success)
                    .putInt(PREF_LAST_EXIT_CODE, exitCode)
                    .putString(PREF_LAST_DETAIL, safeDetail)
                    .putLong(PREF_LAST_AT, System.currentTimeMillis())
                    .commit();
        } catch (RuntimeException ignored) { }

        try {
            Intent reply = new Intent(ACTION_RESULT);
            reply.putExtra("source_action", action);
            reply.putExtra("target", target);
            reply.putExtra("requested_enabled", enabled);
            reply.putExtra("success", success);
            reply.putExtra("exit_code", exitCode);
            reply.putExtra("detail", safeDetail);
            reply.setPackage(context.getPackageName());
            context.sendBroadcast(reply);
        } catch (RuntimeException ignored) { }
    }
}
