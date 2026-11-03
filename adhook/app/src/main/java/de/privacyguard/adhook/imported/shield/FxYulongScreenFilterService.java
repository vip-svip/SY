package de.privacyguard.adhook.imported.shield;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ColorMatrix;
import android.graphics.ColorMatrixColorFilter;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.os.Build;
import android.os.IBinder;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;

/** User-controlled Yulong Shield screen-filter overlay with an owned non-touchable window. */
public final class FxYulongScreenFilterService extends Service {
    public static final String ACTION_START = "de.privacyguard.adhook.screenfilter.START";
    public static final String ACTION_APPLY = "de.privacyguard.adhook.screenfilter.APPLY";
    public static final String ACTION_STOP = "de.privacyguard.adhook.screenfilter.STOP";
    private static final String PREFS = "shield_prefs";
    private static final String CHANNEL = "fx_yulong_screen_filter";
    private static final int NOTIFICATION_ID = 0x7d1;

    private WindowManager windowManager;
    private FilterOverlay overlay;

    private boolean volumeReceiverRegistered;
    private final BroadcastReceiver volumeKeyReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            if (intent == null) return;
            SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
            if (!prefs.getBoolean("screen_filter_enabled", false)
                    || !prefs.getBoolean("screen_filter_volume_adjust_enabled", false)) return;
            int direction = intent.getIntExtra("direction", 0);
            if (direction != 1 && direction != -1) return;
            int brightness = prefs.getInt("screen_filter_brightness", 100);
            brightness = Math.max(0, Math.min(200, brightness + direction * 5));
            prefs.edit().putInt("screen_filter_brightness", brightness).apply();
            applySettings();
        }
    };

    @Override public void onCreate() {
        super.onCreate();
        windowManager = (WindowManager) getSystemService(Context.WINDOW_SERVICE);
        IntentFilter volumeFilter = new IntentFilter(
                de.privacyguard.adhook.FxAccessibilityService.ACTION_VOLUME_KEY);
        try {
            if (Build.VERSION.SDK_INT >= 33)
                registerReceiver(volumeKeyReceiver, volumeFilter, Context.RECEIVER_NOT_EXPORTED);
            else registerReceiver(volumeKeyReceiver, volumeFilter);
            volumeReceiverRegistered = true;
        } catch (Throwable ignored) {
            volumeReceiverRegistered = false;
        }
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationManager manager = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
            if (manager != null) {
                NotificationChannel channel = new NotificationChannel(
                        CHANNEL, "FX 屏幕滤镜", NotificationManager.IMPORTANCE_LOW);
                channel.setDescription("显示当前已启用的屏幕滤镜，并允许用户停止");
                manager.createNotificationChannel(channel);
            }
        }
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? ACTION_START : intent.getAction();
        if (ACTION_STOP.equals(action)) {
            getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                    .putBoolean("screen_filter_enabled", false).apply();
            stopSelf();
            return START_NOT_STICKY;
        }
        if (!Settings.canDrawOverlays(this)
                || !getSharedPreferences(PREFS, MODE_PRIVATE)
                    .getBoolean("screen_filter_enabled", false)) {
            getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                    .putBoolean("screen_filter_enabled", false).apply();
            stopSelf();
            return START_NOT_STICKY;
        }
        startForeground(NOTIFICATION_ID, buildNotification());
        try {
            ensureOverlay();
            applySettings();
        } catch (Throwable failure) {
            getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                    .putBoolean("screen_filter_enabled", false).apply();
            removeOverlay();
            stopForeground(true);
            stopSelf();
        }
        return START_NOT_STICKY;
    }

    private Notification buildNotification() {
        Intent open = new Intent(this, FxYulongScreenFilterActivity.class);
        PendingIntent content = PendingIntent.getActivity(this, 8831, open,
                PendingIntent.FLAG_UPDATE_CURRENT
                        | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0));
        Intent stop = new Intent(this, FxYulongScreenFilterService.class);
        stop.setAction(ACTION_STOP);
        PendingIntent stopPending = PendingIntent.getService(this, 8832, stop,
                PendingIntent.FLAG_UPDATE_CURRENT
                        | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0));
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(this, CHANNEL) : new Notification.Builder(this);
        return builder.setSmallIcon(android.R.drawable.ic_menu_gallery)
                .setContentTitle("FX 屏幕滤镜已启用")
                .setContentText("点击打开设置，或使用通知中的停止按钮移除滤镜。")
                .setContentIntent(content)
                .setOngoing(true)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "停止滤镜", stopPending)
                .build();
    }

    private void ensureOverlay() {
        if (overlay != null) return;
        if (windowManager == null) throw new IllegalStateException("WindowManager unavailable");
        overlay = new FilterOverlay(this);
        int type = Build.VERSION.SDK_INT >= 26
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_PHONE;
        int flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS;
        WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                type, flags, PixelFormat.TRANSLUCENT);
        params.gravity = Gravity.TOP | Gravity.START;
        windowManager.addView(overlay, params);
    }

    private void applySettings() {
        if (overlay == null) return;
        SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        overlay.apply(
                prefs.getInt("screen_filter_preset", 0),
                prefs.getInt("screen_filter_brightness", 100),
                prefs.getInt("screen_filter_contrast", 100),
                prefs.getInt("screen_filter_saturation", 100),
                prefs.getInt("screen_filter_temperature", 50));
    }

    private void removeOverlay() {
        if (overlay == null) return;
        try {
            if (windowManager != null) windowManager.removeViewImmediate(overlay);
        } catch (Throwable ignored) { }
        overlay = null;
    }

    @Override public void onDestroy() {
        removeOverlay();
        if (volumeReceiverRegistered) {
            try { unregisterReceiver(volumeKeyReceiver); } catch (Throwable ignored) { }
            volumeReceiverRegistered = false;
        }
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                .putBoolean("screen_filter_enabled", false).apply();
        stopForeground(true);
        super.onDestroy();
    }

    @Override public IBinder onBind(Intent intent) { return null; }

    private static final class FilterOverlay extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private int alpha = 6;

        FilterOverlay(Context context) {
            super(context);
            setFocusable(false);
            setFocusableInTouchMode(false);
            setClickable(false);
            setEnabled(false);
            setLayerType(View.LAYER_TYPE_HARDWARE, paint);
        }

        void apply(int preset, int brightness, int contrast, int saturation, int temperature) {
            float db = (clamp(brightness, 0, 200) - 100f) / 100f;
            float dc = (clamp(contrast, 0, 200) - 100f) / 100f;
            float ds = (clamp(saturation, 0, 200) - 100f) / 100f;
            float dt = (clamp(temperature, 0, 100) - 50f) / 50f;
            float[] matrix = preset == 1
                    ? new float[]{1.06f,0,0,0,5, 0,1.05f,0,0,5, 0,0,1.07f,0,4, 0,0,0,1,0}
                    : new float[]{1.05f,0,0,0,8, 0,1.05f,0,0,8, 0,0,1.04f,0,6, 0,0,0,1,0};
            matrix[4] += db * 10f + dt * 16f;
            matrix[9] += db * 10f;
            matrix[14] += db * 8f - dt * 16f;
            paint.setColorFilter(new ColorMatrixColorFilter(new ColorMatrix(matrix)));
            float amount = (Math.abs(db) * 0.5f + Math.abs(dc) * 0.25f
                    + Math.abs(ds) * 0.25f + Math.abs(dt) * 0.5f) * 10f + 6f;
            alpha = Math.max(0, Math.min(20, Math.round(amount)));
            invalidate();
        }

        @Override protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            if (alpha >= 2) canvas.drawColor(Color.argb(alpha, 245, 245, 245));
        }

        private static int clamp(int value, int min, int max) {
            return Math.max(min, Math.min(max, value));
        }
    }
}
