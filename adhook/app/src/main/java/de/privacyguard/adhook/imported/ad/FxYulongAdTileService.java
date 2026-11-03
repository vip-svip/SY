package de.privacyguard.adhook.imported.ad;

import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;
import de.privacyguard.adhook.RootAccess;

/** Quick Settings toggle bound to the FX ad-filter master key. */
public final class FxYulongAdTileService extends TileService {
    private String command(String args) {
        return "MP=''; for d in /data/adb/modules/privacyguard /data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard /data/adb/modules/pg; do "
                + "if [ -s \\"$d/module.prop\\" ] && grep -q '^id=privacyguard$' \\"$d/module.prop\\"; then MP=\\"$d\\"; break; fi; done; "
                + "[ -n \\"$MP\\" ] || exit 20; sh \\"$MP/scripts/yulong-ad-control.sh\\" " + args;
    }
    private int readState() {
        RootAccess.Result r=RootAccess.execute(command("list"),30000L,128*1024);
        if(r.exitCode!=0||r.output==null)return Tile.STATE_UNAVAILABLE;
        for(String line:r.output.split("\\\\r?\\\\n"))
            if(line.startsWith("AD_MASTER|"))return line.endsWith("|1")?Tile.STATE_ACTIVE:Tile.STATE_INACTIVE;
        return Tile.STATE_INACTIVE;
    }
    private void updateTileState() {
        Tile tile=getQsTile();if(tile==null)return;
        int state=readState();tile.setState(state);tile.setLabel("FX 广告过滤");
        tile.setSubtitle(state==Tile.STATE_ACTIVE?"已开启":"已关闭");tile.updateTile();
    }
    @Override public void onStartListening(){super.onStartListening();updateTileState();}
    @Override public void onClick(){
        super.onClick();Tile tile=getQsTile();if(tile==null)return;
        int next=readState()==Tile.STATE_ACTIVE?0:1;
        RootAccess.Result r=RootAccess.execute(command("ad-master "+next),90000L,128*1024);
        if(r.exitCode==0)updateTileState();
        else{tile.setState(Tile.STATE_UNAVAILABLE);tile.setSubtitle("Root 应用失败");tile.updateTile();}
    }
}
