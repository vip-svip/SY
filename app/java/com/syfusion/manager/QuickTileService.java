package com.syfusion.manager;

import android.graphics.drawable.Icon;
import android.os.Build;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/**
 * 快捷设置磁贴：下拉状态栏一键看状态 / 一键启停。
 * 极客用户的常规操作路径，比每次开 App 快得多。
 */
public class QuickTileService extends TileService {

    @Override
    public void onStartListening() {
        super.onStartListening();
        refresh();
    }

    @Override
    public void onClick() {
        super.onClick();
        final Tile t = getQsTile();
        if (t == null) return;
        final boolean wasOn = t.getState() == Tile.STATE_ACTIVE;
        t.setState(Tile.STATE_UNAVAILABLE);
        t.setLabel(getString(R.string.tile_label));
        t.updateTile();

        new Thread(new Runnable() {
            @Override
            public void run() {
                if (wasOn) {
                    RootShell.stopCore();
                } else {
                    // 面板没起就一并拉起，否则 App 打开是空白页
                    if (!PanelApi.ping(PanelApi.DEFAULT_PORT, 1200)) {
                        RootShell.startPanel();
                    }
                    RootShell.startCore();
                }
                try {
                    Thread.sleep(1200);
                } catch (InterruptedException ignored) {
                }
                refreshOnUi();
            }
        }, "tile-toggle").start();
    }

    private void refresh() {
        new Thread(new Runnable() {
            @Override
            public void run() {
                final boolean up = isCoreUp();
                final Tile t = getQsTile();
                if (t == null) return;
                t.setState(up ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
                t.setLabel(getString(R.string.tile_label));
                if (Build.VERSION.SDK_INT >= 29) {
                    t.setSubtitle(up ? "运行中" : "已停止");
                }
                t.updateTile();
            }
        }, "tile-refresh").start();
    }

    private void refreshOnUi() {
        refresh();
    }

    private boolean isCoreUp() {
        String json = PanelApi.get(PanelApi.DEFAULT_PORT, "/api/clash?sub=status", 2000);
        return json != null && PanelApi.bool(json, "ok");
    }

    @SuppressWarnings("unused")
    private Icon icon() {
        return Icon.createWithResource(this, R.mipmap.ic_launcher);
    }
}
