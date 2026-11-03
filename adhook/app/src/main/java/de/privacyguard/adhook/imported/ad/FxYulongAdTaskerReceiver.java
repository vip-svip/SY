package de.privacyguard.adhook.imported.ad;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import de.privacyguard.adhook.RootAccess;
import java.util.concurrent.atomic.AtomicBoolean;

/** Tasker-compatible, allowlisted toggle for the one FX ad-filter master switch. */
public final class FxYulongAdTaskerReceiver extends BroadcastReceiver {
    // The receiver is exported for Tasker compatibility; never allow concurrent Root writers.
    private static final AtomicBoolean REQUEST_PENDING = new AtomicBoolean(false);
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

        // Tasker broadcasts are externally callable. A burst must not create an
        // unbounded number of threads or race multiple settings.conf mutations.
        if(!REQUEST_PENDING.compareAndSet(false,true)){
            publishResult(context,action,enabled,false,75);
            return;
        }
        final long gateToken = FxYulongAdOperationGate.tryAcquire();
        if (gateToken == 0L) {
            REQUEST_PENDING.set(false);
            publishResult(context, action, enabled, false, 75);
            return;
        }

        final PendingResult pending;
        try{
            pending=goAsync();
        }catch(RuntimeException error){
            FxYulongAdOperationGate.release(gateToken);
            REQUEST_PENDING.set(false);
            publishResult(context,action,enabled,false,127);
            return;
        }

        try{
            new Thread(()->{
                int code=127;
                try{
                    String command="MP=''; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do "
                            +"if [ -s \\"$d/module.prop\\" ] && grep -q '^id=privacyguard$' \\"$d/module.prop\\"; then MP=\\"$d\\"; break; fi; done; "
                            +"[ -n \\"$MP\\" ] || exit 20; sh \\"$MP/scripts/yulong-ad-control.sh\\" ad-master "+enabled;
                    RootAccess.Result result=RootAccess.execute(command,90000L,128*1024);
                    code=result.exitCode;
                    if(code==0)FxYulongAdWidgetProvider.refreshAll(context);
                }catch(Throwable ignored){}
                try{
                    publishResult(context,action,enabled,code==0,code);
                }finally{
                    FxYulongAdOperationGate.release(gateToken);
                    REQUEST_PENDING.set(false);
                    pending.finish();
                }
            },"fx-yulong-tasker-toggle").start();
        }catch(RuntimeException startError){
            FxYulongAdOperationGate.release(gateToken);
            REQUEST_PENDING.set(false);
            try{
                publishResult(context,action,enabled,false,127);
            }finally{
                pending.finish();
            }
        }
    }

    private static void publishResult(Context context,String action,int enabled,
                                      boolean success,int exitCode){
        try{
            Intent reply=new Intent(ACTION_RESULT);
            reply.putExtra("source_action",action);
            reply.putExtra("requested_enabled",enabled);
            reply.putExtra("success",success);
            reply.putExtra("exit_code",exitCode);
            reply.setPackage(context.getPackageName());
            context.sendBroadcast(reply);
        }catch(RuntimeException ignored){}
    }
}
