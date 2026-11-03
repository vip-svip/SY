package de.privacyguard.adhook.imported.shield;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.graphics.PixelFormat;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.IBinder;
import android.provider.Settings;
import android.view.Gravity;
import android.view.WindowManager;
import android.widget.TextView;

/** User-authorized overlay entry that only opens the FX Shield hub. */
public final class FxYulongRescueOverlayService extends Service {
    private static final String CHANNEL="fx_yulong_rescue_overlay";
    private static final int ID=0x5961;
    private WindowManager manager;
    private TextView bubble;

    private int dp(float n){return (int)(n*getResources().getDisplayMetrics().density+0.5f);}

    @Override public void onCreate(){
        super.onCreate();
        manager=(WindowManager)getSystemService(WINDOW_SERVICE);
        ensureChannel();
    }

    @Override public int onStartCommand(Intent intent,int flags,int startId){
        if(!getSharedPreferences("shield_prefs",MODE_PRIVATE).getBoolean("overlay_rescue_on",false)){
            stopSelf();return START_NOT_STICKY;
        }
        if(!Settings.canDrawOverlays(this)){
            getSharedPreferences("shield_prefs",MODE_PRIVATE).edit().putBoolean("overlay_rescue_on",false).apply();
            stopSelf();return START_NOT_STICKY;
        }
        startForeground(ID,notification());
        attachBubble();
        return bubble == null ? START_NOT_STICKY : START_STICKY;
    }

    private void ensureChannel(){
        if(Build.VERSION.SDK_INT<26)return;
        NotificationManager nm=(NotificationManager)getSystemService(NOTIFICATION_SERVICE);
        if(nm==null)return;
        NotificationChannel channel=new NotificationChannel(CHANNEL,"FX 安全护盾悬浮救援入口",NotificationManager.IMPORTANCE_LOW);
        channel.setDescription("用户主动开启的可点击救援快捷入口");
        nm.createNotificationChannel(channel);
    }

    private Notification notification(){
        Intent open=new Intent(this,FxYulongShieldActivity.class);
        PendingIntent pi=PendingIntent.getActivity(this,0x5962,open,
                PendingIntent.FLAG_UPDATE_CURRENT|(Build.VERSION.SDK_INT>=23?PendingIntent.FLAG_IMMUTABLE:0));
        Notification.Builder b=Build.VERSION.SDK_INT>=26?new Notification.Builder(this,CHANNEL):new Notification.Builder(this);
        return b.setSmallIcon(android.R.drawable.ic_lock_idle_lock)
                .setContentTitle("FX 安全护盾救援入口")
                .setContentText("悬浮入口已开启；点击通知或屏幕边缘图标返回 FX。")
                .setContentIntent(pi).setOngoing(true).build();
    }

    private void attachBubble(){
        if(manager==null||bubble!=null)return;
        bubble=new TextView(this);
        bubble.setText("FX");
        bubble.setTextColor(0xffffffff);
        bubble.setTextSize(12);
        bubble.setTypeface(Typeface.DEFAULT,Typeface.BOLD);
        bubble.setGravity(Gravity.CENTER);
        GradientDrawable bg=new GradientDrawable();
        bg.setShape(GradientDrawable.OVAL);
        bg.setColor(0xff1769aa);
        bg.setStroke(dp(1),0xffdcecff);
        bubble.setBackground(bg);
        bubble.setElevation(dp(6));
        bubble.setOnClickListener(v->{
            android.content.SharedPreferences prefs = getSharedPreferences("shield_prefs", MODE_PRIVATE);
            String today = new java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.ROOT)
                    .format(new java.util.Date());
            int count = today.equals(prefs.getString("overlay_open_day", ""))
                    ? prefs.getInt("overlay_open_count_today", 0) : 0;
            prefs.edit().putString("overlay_open_day", today)
                    .putInt("overlay_open_count_today", count + 1)
                    .putInt("overlay_open_count", prefs.getInt("overlay_open_count", 0) + 1)
                    .putString("overlay_last_open_time",
                            new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.ROOT)
                                    .format(new java.util.Date()))
                    .apply();
            Intent open=new Intent(this,FxYulongShieldActivity.class);
            open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TOP);
            try{startActivity(open);}catch(Throwable ignored){}
        });
        int type=Build.VERSION.SDK_INT>=26?WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                :WindowManager.LayoutParams.TYPE_PHONE;
        WindowManager.LayoutParams lp=new WindowManager.LayoutParams(
                dp(48),dp(48),type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        |WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                        |WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT);
        lp.gravity=Gravity.END|Gravity.CENTER_VERTICAL;
        lp.x=dp(8);lp.y=dp(40);
        try{manager.addView(bubble,lp);}catch(Throwable error){
            bubble=null;
            getSharedPreferences("shield_prefs",MODE_PRIVATE).edit().putBoolean("overlay_rescue_on",false).apply();
            stopSelf();
        }
    }

    @Override public void onDestroy(){
        if(manager!=null&&bubble!=null){
            try{manager.removeView(bubble);}catch(Throwable ignored){}
        }
        bubble=null;
        stopForeground(true);
        super.onDestroy();
    }

    @Override public IBinder onBind(Intent intent){return null;}
}
