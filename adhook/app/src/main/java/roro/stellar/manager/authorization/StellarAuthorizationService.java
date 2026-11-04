package roro.stellar.manager.authorization;

import android.app.Service;
import android.content.Intent;
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
    public static final String KEY_PROTOCOL_VERSION = "protocol_version";
    public static final String KEY_REQUEST_ID = "request_id";
    public static final String KEY_SHELL_ARGS = "shell_args";
    public static final String KEY_EXIT_CODE = "exit_code";
    public static final String KEY_OUTPUT = "output";
    public static final String KEY_DENIED = "denied";
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
