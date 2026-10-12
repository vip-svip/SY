package com.syfusion.manager;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;

/**
 * 常驻状态通知。
 *
 * 目的：不用打开 App 也能看到内核在不在跑、当前速率多少。
 * 这是"内置 App"相对 WebUI 的核心增量 —— WebUI 只有打开时才存在。
 *
 * 数据源走面板的 /api/clash，而不是直连内核的 Clash API：
 *   内核端口是可配置的，而面板端口固定且自带鉴权注入，
 *   从 App 侧看面板是唯一稳定入口。
 */
public class CoreService extends Service {

    public static final String CH = "sy_status";
    public static final int NID = 0x5359;

    private final Handler ui = new Handler(Looper.getMainLooper());
    private volatile boolean running = false;
    private int port = PanelApi.DEFAULT_PORT;
    private long totalUp = 0, totalDown = 0;

    private final Runnable tick = new Runnable() {
        @Override
        public void run() {
            fetch();
            ui.postDelayed(this, 3000);
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        port = getSharedPreferences("sy", MODE_PRIVATE).getInt("port", PanelApi.DEFAULT_PORT);
        createChannel();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (!running) {
            running = true;
            startForeground(NID, build("正在连接…", "—", "—", false));
            ui.post(tick);
        }
        return START_STICKY;
    }

    private void fetch() {
        new Thread(new Runnable() {
            @Override
            public void run() {
                final String json = PanelApi.get(port, "/api/clash?sub=status", 2500);
                final boolean ok = json != null && PanelApi.bool(json, "ok");
                String title, sub;
                if (ok) {
                    totalUp = PanelApi.num(json, "upload_total");
                    totalDown = PanelApi.num(json, "download_total");
                    title = "代理运行中 · " + orDash(PanelApi.str(json, "mode"));
                    sub = "↑ " + PanelApi.speed(PanelApi.num(json, "up"))
                            + "   ↓ " + PanelApi.speed(PanelApi.num(json, "down"))
                            + "   连接 " + PanelApi.num(json, "conn_count")
                            + "   累计 ↑" + PanelApi.bytes(totalUp)
                            + " ↓" + PanelApi.bytes(totalDown);
                } else {
                    title = "内核未运行";
                    sub = "点按打开管理器启动";
                }
                final Notification n = build(title, sub, "", ok);
                ui.post(new Runnable() {
                    @Override
                    public void run() {
                        try {
                            NotificationManager nm =
                                    (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
                            nm.notify(NID, n);
                        } catch (Exception ignored) {
                        }
                    }
                });
            }
        }, "notify-poll").start();
    }

    private static String orDash(String s) {
        return (s == null || s.length() == 0) ? "—" : s;
    }

    private void createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationManager nm =
                    (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            NotificationChannel c = new NotificationChannel(
                    CH, getString(R.string.notify_channel), NotificationManager.IMPORTANCE_LOW);
            c.setDescription(getString(R.string.notify_channel_desc));
            c.setShowBadge(false);
            c.enableVibration(false);
            nm.createNotificationChannel(c);
        }
    }

    @SuppressWarnings("deprecation")
    private Notification build(String title, String text, String ignored, boolean ok) {
        Intent open = new Intent(this, MainActivity.class);
        open.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pi = PendingIntent.getActivity(this, 0, open,
                Build.VERSION.SDK_INT >= 23
                        ? PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
                        : PendingIntent.FLAG_UPDATE_CURRENT);

        Notification.Builder b;
        if (Build.VERSION.SDK_INT >= 26) {
            b = new Notification.Builder(this, CH);
        } else {
            b = new Notification.Builder(this);
        }
        b.setContentTitle(title)
                .setContentText(text)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentIntent(pi)
                .setOngoing(true)
                .setShowWhen(false);
        if (Build.VERSION.SDK_INT >= 21) {
            b.setVisibility(Notification.VISIBILITY_PUBLIC);
        }
        if (Build.VERSION.SDK_INT >= 16) {
            Notification.InboxStyle st = new Notification.InboxStyle();
            st.addLine(text);
            b.setStyle(st);
        }
        return b.build();
    }

    @Override
    public void onDestroy() {
        running = false;
        ui.removeCallbacks(tick);
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
