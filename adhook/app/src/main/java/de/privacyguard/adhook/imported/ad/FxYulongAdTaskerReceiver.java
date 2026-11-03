package de.privacyguard.adhook.imported.ad;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import de.privacyguard.adhook.RootAccess;

/** Tasker-compatible, allowlisted toggle for the one FX ad-filter master switch. */
public final class FxYulongAdTaskerReceiver extends BroadcastReceiver {
    public static final String ACTION_ENABLE="de.privacyguard.adhook.AD_FILTER_ENABLE";
    public static final String ACTION_DISABLE="de.privacyguard.adhook.AD_FILTER_DISABLE";
    public static final String ACTION_RESULT="de.privacyguard.adhook.AD_FILTER_RESULT";
    public static final String LEGACY_ACTION_START="app.pwhs.blockads.TASKER_START";
    public static final String LEGACY_ACTION_STOP="app.pwhs.blockads.TASKER_STOP";

    @Override public void onReceive(Context context,Intent intent){
        if(context==null||intent==null)return;
        String action=intent.getAction();
        final int enabled;
        if(ACTION_ENABLE.equals(action)||LEGACY_ACTION_START.equals(action))enabled=1;
        else if(ACTION_DISABLE.equals(action)||LEGACY_ACTION_STOP.equals(action))enabled=0;
        else return;
        final PendingResult pending=goAsync();
        new Thread(()->{
            int code=127;
            try{
                String command="MP=''; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do "
                        +"if [ -s \\"$d/module.prop\\" ] && grep -q '^id=privacyguard$' \\"$d/module.prop\\"; then MP=\\"$d\\"; break; fi; done; "
                        +"[ -n \\"$MP\\" ] || exit 20; sh \\"$MP/scripts/yulong-ad-control.sh\\" ad-master "+enabled;
                RootAccess.Result result=RootAccess.execute(command,90000L,128*1024);
                code=result.exitCode;
                if (code == 0) FxYulongAdWidgetProvider.refreshAll(context);
            }catch(Throwable ignored){}
            Intent reply=new Intent(ACTION_RESULT);
            reply.setPackage(context.getPackageName());
            reply.putExtra("requested_enabled",enabled);
            reply.putExtra("success",code==0);
            reply.putExtra("exit_code",code);
            context.sendBroadcast(reply);
            pending.finish();
        },"fx-yulong-tasker-toggle").start();
    }
}
