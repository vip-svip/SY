package roro.stellar.manager.authorization;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.Message;
import android.os.Messenger;
import android.os.RemoteException;

import de.privacyguard.adhook.RootAccess;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Private asynchronous Binder transport for the migrated Stellar authorization UI.
 * It brokers the allowlisted FX command backend; it does not impersonate the
 * original separate IStellarService/StellarProvider daemon.
 */
public final class StellarAuthorizationService extends Service {
    public static final int PROTOCOL_VERSION = 1;
    public static final int MSG_HELLO = 1;
    public static final int MSG_READY = 2;
    public static final int MSG_EXECUTE = 3;
    public static final int MSG_RESULT = 4;
    public static final int MSG_PERMISSION_REQUEST = 5;
    public static final int MSG_PERMISSION_RESULT = 6;
    public static final String KEY_PROTOCOL_VERSION = "protocol_version";
    public static final String KEY_REQUEST_ID = "request_id";
    public static final String KEY_SHELL_ARGS = "shell_args";
    public static final String KEY_EXIT_CODE = "exit_code";
    public static final String KEY_OUTPUT = "output";
    public static final String KEY_DENIED = "denied";
    public static final String KEY_UID = "uid";
    public static final String KEY_PID = "pid";
    public static final String KEY_REQUEST_CODE = "requestCode";
    public static final String KEY_PERMISSION = "permission";
    public static final String KEY_SOURCE_PACKAGE = "sourcePackage";
    public static final String KEY_PERMISSION_REPLY = "permission_reply";
    public static final String REPLY_ALLOWED = "stellar:request-permission-reply-allowed";
    public static final String REPLY_ONE_TIME = "stellar:request-permission-reply-is-onetime";
    public static final String REPLY_PERMISSION = "stellar:request-permission-reply-permission";
    private static final String PERMISSION_CHANNEL = "fx_stellar_permission_requests";
    private static final String PERMISSION_NOTIFICATION_TAG = "fx-stellar-permission";
    private static final AtomicLong PERMISSION_REQUEST_IDS = new AtomicLong(1L);
    public static final int MAX_SHELL_ARGS = 8192;
    private static final long COMMAND_TIMEOUT_MS = 60000L;
    private static final int OUTPUT_LIMIT = 256 * 1024;

    private final ThreadPoolExecutor commands = new ThreadPoolExecutor(
            1, 1, 0L, TimeUnit.MILLISECONDS, new ArrayBlockingQueue<>(16),
            runnable -> {
                Thread thread = new Thread(runnable, "fx-stellar-binder");
                thread.setDaemon(true);
                return thread;
            }, new ThreadPoolExecutor.AbortPolicy());

    private final Handler incoming = new Handler(Looper.getMainLooper(), this::handleMessage);
    private final Messenger endpoint = new Messenger(incoming);

    @Override public IBinder onBind(Intent intent) {
        return endpoint.getBinder();
    }

    private boolean handleMessage(Message message) {
        if (message.what == MSG_HELLO) {
            sendReady(message.replyTo);
            return true;
        }
        if (message.what == MSG_PERMISSION_REQUEST) {
            handlePermissionRequest(message);
            return true;
        }
        if (message.what != MSG_EXECUTE) return true;

        Bundle data = message.getData();
        long requestId = data == null ? -1L : data.getLong(KEY_REQUEST_ID, -1L);
        String args = data == null ? null : data.getString(KEY_SHELL_ARGS);
        Messenger replyTo = message.replyTo;
        if (replyTo == null) return true;
        if (requestId < 0 || args == null || args.isEmpty() || args.length() > MAX_SHELL_ARGS) {
            sendResult(replyTo, requestId, RootAccess.failure(2,
                    "Stellar Binder 请求无效或超过大小限制；未执行。"));
            return true;
        }
        try {
            commands.execute(() -> {
                RootAccess.Result result = RootAccess.execute(
                        buildCommand(args), COMMAND_TIMEOUT_MS, OUTPUT_LIMIT);
                sendResult(replyTo, requestId, result);
            });
        } catch (RejectedExecutionException full) {
            sendResult(replyTo, requestId, RootAccess.failure(75,
                    "Stellar Binder 执行队列已满；本次请求未执行。"));
        }
        return true;
    }

    private void handlePermissionRequest(Message message) {
        Bundle request = message.getData();
        Messenger replyTo = message.replyTo;
        if (request == null || replyTo == null) return;
        int uid = request.getInt(KEY_UID, -1);
        int pid = request.getInt(KEY_PID, -1);
        int requestCode = request.getInt(KEY_REQUEST_CODE, -1);
        String permission = request.getString(KEY_PERMISSION, "");
        String sourcePackage = request.getString(KEY_SOURCE_PACKAGE, "");
        long requestId = PERMISSION_REQUEST_IDS.getAndIncrement();
        if (uid < 0 || pid <= 0 || requestCode < 0
                || permission == null || permission.isEmpty() || permission.length() > 255
                || !permission.matches("[A-Za-z0-9_.]+")
                || sourcePackage == null
                || !sourcePackage.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")
                || !packageBelongsToUid(sourcePackage, uid)) {
            sendPermissionResult(replyTo, requestId, uid, pid, requestCode,
                    permission == null ? "" : permission, false, true,
                    "请求身份或权限标识无效；已默认拒绝。");
            return;
        }
        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                        != PackageManager.PERMISSION_GRANTED) {
            sendPermissionResult(replyTo, requestId, uid, pid, requestCode, permission,
                    false, true, "FX 未获通知权限，无法展示安全确认请求；已默认拒绝。");
            return;
        }
        NotificationManager manager =
                (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (manager == null || !manager.areNotificationsEnabled()) {
            sendPermissionResult(replyTo, requestId, uid, pid, requestCode, permission,
                    false, true, "通知当前不可用，无法展示权限确认；已默认拒绝。");
            return;
        }
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(
                    PERMISSION_CHANNEL, "Stellar 权限请求", NotificationManager.IMPORTANCE_HIGH);
            channel.setDescription("展示由签名权限保护的应用权限申请");
            manager.createNotificationChannel(channel);
            NotificationChannel active = manager.getNotificationChannel(PERMISSION_CHANNEL);
            if (active == null || active.getImportance() == NotificationManager.IMPORTANCE_NONE) {
                sendPermissionResult(replyTo, requestId, uid, pid, requestCode, permission,
                        false, true, "Stellar 权限请求通知渠道已关闭；已默认拒绝。");
                return;
            }
        }
        int notificationId = (int) (requestId & 0x7fffffff);
        Intent prompt = new Intent(this, StellarPermissionRequestActivity.class);
        prompt.putExtra("request_id", requestId);
        prompt.putExtra(KEY_UID, uid);
        prompt.putExtra(KEY_PID, pid);
        prompt.putExtra(KEY_REQUEST_CODE, requestCode);
        prompt.putExtra(KEY_PERMISSION, permission);
        prompt.putExtra(KEY_SOURCE_PACKAGE, sourcePackage);
        prompt.putExtra("reply_messenger", replyTo);
        prompt.putExtra("notification_tag", PERMISSION_NOTIFICATION_TAG);
        prompt.putExtra("notification_id", notificationId);
        PendingIntent content = PendingIntent.getActivity(this, notificationId, prompt,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(this, PERMISSION_CHANNEL)
                : new Notification.Builder(this);
        Notification notification = builder
                .setSmallIcon(android.R.drawable.stat_sys_warning)
                .setContentTitle("应用请求 Stellar 权限")
                .setContentText(sourcePackage + " 请求 " + permission)
                .setStyle(new Notification.BigTextStyle().bigText(
                        "应用：" + sourcePackage + "\\n权限：" + permission
                                + "\\n点击查看详情并决定是否允许。"))
                .setContentIntent(content)
                .setAutoCancel(true)
                .setCategory(Notification.CATEGORY_PERMISSION)
                .build();
        manager.notify(PERMISSION_NOTIFICATION_TAG, notificationId, notification);
    }

    private boolean packageBelongsToUid(String packageName, int uid) {
        try {
            String[] packages = getPackageManager().getPackagesForUid(uid);
            if (packages == null) return false;
            for (String item : packages) if (packageName.equals(item)) return true;
        } catch (RuntimeException ignored) { }
        return false;
    }

    static void sendPermissionResult(Messenger replyTo, long requestId, int uid, int pid,
                                     int requestCode, String permission, boolean allowed,
                                     boolean oneTime, String detail) {
        if (replyTo == null) return;
        Message response = Message.obtain(null, MSG_PERMISSION_RESULT);
        Bundle data = new Bundle();
        data.putLong(KEY_REQUEST_ID, requestId);
        data.putInt(KEY_UID, uid);
        data.putInt(KEY_PID, pid);
        data.putInt(KEY_REQUEST_CODE, requestCode);
        data.putString(KEY_PERMISSION, permission == null ? "" : permission);
        data.putString("detail", detail == null ? "" : detail);
        Bundle reply = new Bundle();
        reply.putBoolean(REPLY_ALLOWED, allowed);
        reply.putBoolean(REPLY_ONE_TIME, oneTime);
        reply.putString(REPLY_PERMISSION, permission == null ? "" : permission);
        data.putBundle(KEY_PERMISSION_REPLY, reply);
        response.setData(data);
        try {
            replyTo.send(response);
        } catch (RemoteException ignored) { }
    }

    private void sendReady(Messenger replyTo) {
        if (replyTo == null) return;
        Message response = Message.obtain(null, MSG_READY);
        Bundle data = new Bundle();
        data.putInt(KEY_PROTOCOL_VERSION, PROTOCOL_VERSION);
        response.setData(data);
        try {
            replyTo.send(response);
        } catch (RemoteException ignored) { }
    }

    private void sendResult(Messenger replyTo, long requestId, RootAccess.Result result) {
        Message response = Message.obtain(null, MSG_RESULT);
        Bundle data = new Bundle();
        data.putLong(KEY_REQUEST_ID, requestId);
        data.putInt(KEY_EXIT_CODE, result.exitCode);
        data.putString(KEY_OUTPUT, result.output == null ? "" : result.output);
        data.putBoolean(KEY_DENIED, result.denied);
        response.setData(data);
        try {
            replyTo.send(response);
        } catch (RemoteException ignored) { }
    }

    private String buildCommand(String args) {
        return "MP=''; for d in /data/adb/modules/privacyguard "
                + "/data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard "
                + "/data/adb/modules/pg; do "
                + "if [ -s \"$d/module.prop\" ] && grep -q '^id=privacyguard$' \"$d/module.prop\"; "
                + "then MP=\"$d\"; break; fi; done; "
                + "[ -n \"$MP\" ] || exit 20; "
                + "sh \"$MP/scripts/yulong-stellar-control.sh\" " + args;
    }

    @Override public void onDestroy() {
        commands.shutdownNow();
        super.onDestroy();
    }
}
