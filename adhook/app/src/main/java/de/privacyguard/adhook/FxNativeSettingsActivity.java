package de.privacyguard.adhook;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.compose.ui.platform.ComposeView;
import androidx.lifecycle.ViewTreeLifecycleOwner;
import androidx.lifecycle.ViewTreeViewModelStoreOwner;
import androidx.savedstate.ViewTreeSavedStateRegistryOwner;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

/** App-wide preferences for FX's six-page native shell. */
public final class FxNativeSettingsActivity extends FxNativeTabActivity {
    private static final int REQUEST_WALLPAPER_PICKER = 0x6f51;
    private final ExecutorService wallpaperExecutor = Executors.newSingleThreadExecutor(r -> {
        Thread thread = new Thread(r, "fx-wallpaper-settings");
        thread.setDaemon(true);
        return thread;
    });
    private final AtomicBoolean wallpaperBusy = new AtomicBoolean(false);
    private LinearLayout content;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        ScrollView scroll = new ScrollView(this);
        scroll.setTag("fx-page-root");
        scroll.setClipToPadding(false);
        scroll.setFillViewport(true);
        content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(14), dp(8), dp(14), dp(26));
        scroll.addView(content);

        TextView title = text("设置", 23, true);
        title.setTag("fx-title:23");
        title.setPadding(dp(4), dp(10), dp(4), dp(6));
        content.addView(title);
        TextView intro = text(
                "全局界面模式、壁纸、备份恢复、系统授权和运行诊断。VPN、Ad、隐私、脚本与 Hook 的具体功能仍在各自主页面管理。",
                12, false);
        intro.setTag("fx-card-detail");
        intro.setPadding(dp(4), 0, dp(4), dp(14));
        content.addView(intro);

        section("界面模式");
        TextView modeNote = text(
                "Default 是独立的基础原生模式；另有 Classic 网页兼容、FX Liquid、Miuix、HarmonyStyle 与 CupertinoStyle 五种皮肤。切换只改变展示层，不启停 VPN、DNS、代理、Hook 或脚本服务。",
                12, false);
        modeNote.setTag("fx-card-detail");
        modeNote.setPadding(dp(4), 0, dp(4), dp(8));
        content.addView(modeNote);

        ComposeView modePanel = new ComposeView(this);
        modePanel.setTag("fx-card");
        ViewTreeLifecycleOwner.set(modePanel, this);
        ViewTreeViewModelStoreOwner.set(modePanel, this);
        ViewTreeSavedStateRegistryOwner.set(modePanel, this);
        FxDesignModePanelKt.installFxDesignModePanel(
                modePanel, FxUiMode.read(this).getStorageId(), selected -> {
                    if (selected == null) return kotlin.Unit.INSTANCE;
                    FxUiMode next = FxUiMode.fromStorageId(selected);
                    if (next == FxUiMode.read(FxNativeSettingsActivity.this)) {
                        return kotlin.Unit.INSTANCE;
                    }
                    if (!FxUiMode.write(FxNativeSettingsActivity.this, next)) {
                        Toast.makeText(FxNativeSettingsActivity.this,
                                "界面模式保存失败，当前设置保持不变。", Toast.LENGTH_LONG).show();
                        return kotlin.Unit.INSTANCE;
                    }
                    Toast.makeText(FxNativeSettingsActivity.this,
                            "已切换到 " + next.getTitle(), Toast.LENGTH_SHORT).show();
                    recreate();
                    return kotlin.Unit.INSTANCE;
                });
        content.addView(modePanel, new LinearLayout.LayoutParams(-1, dp(560)));

        section("壁纸与背景");
        addActionCard("壁纸随心换",
                FxWallpaperStore.currentPath(this) == null
                        ? "尚未设置自定义壁纸，当前使用默认背景。"
                        : "已设置自定义壁纸；图片保存在 FX 应用私有目录。",
                "管理壁纸", this::showWallpaperManager);

        section("位置与定位");
        addActionCard("自定义位置",
                "为选中的应用写入真实坐标系：Hook 会把这里的经纬度构造成带精度与时间戳的"
                        + " Location 交还给该应用，地图、距离与围栏都按它走。不修改系统定位。",
                "设置自定义位置",
                () -> startActivity(new Intent(this, FxNativeLocationActivity.class)));

        section("备份与恢复");
        addActionCard("FX 配置备份",
                "管理模块配置、FX Hook 与安全防护偏好的本地加密备份、GitHub 与 WebDAV 备份。恢复前会显示覆盖范围并要求确认。",
                "打开备份管理",
                () -> startActivity(new Intent(this,
                        de.privacyguard.adhook.imported.dia.FxDiaBackupActivity.class)));

        section("系统授权");
        addActionCard("Android 无障碍服务",
                "GKD 自动化与辅助功能需要用户在 Android 设置中手动授权。FX 不会绕过系统授权。",
                "打开无障碍设置",
                () -> openSystemSettings(Settings.ACTION_ACCESSIBILITY_SETTINGS, "无障碍设置"));
        addActionCard("FX 应用信息",
                "查看通知、后台运行、电池优化等 Android 应用级权限与系统选项。",
                "打开应用信息", this::openAppDetails);
        addActionCard("LSPosed 管理",
                "管理 FX Hook 模块启用状态与目标应用作用域。保存配置不代表目标进程已经注入。",
                "打开 Hook 工具与运行设置",
                () -> startActivity(new Intent(this,
                        de.privacyguard.adhook.imported.dia.FxDiaGlobalSettingsActivity.class)));

        section("运行诊断");
        addActionCard("Hook 观察日志",
                "查看 FX Hook 的本地观察记录；日志只用于诊断，不代表目标应用已经成功加载 Hook。",
                "查看日志",
                () -> startActivity(new Intent(this, FxHookObservationLogsActivity.class)));
        addActionCard("Dia 崩溃报告",
                "查看本机 Dia 工具运行过程中记录的崩溃与异常信息。",
                "查看崩溃报告",
                () -> startActivity(new Intent(this,
                        de.privacyguard.adhook.imported.dia.FxDiaCrashReportActivity.class)));

        section("开源许可与关于");
        addActionCard("第三方开源许可",
                "查看随 FX 1.0 APK 分发的第三方组件许可证和版权声明。",
                "查看开源许可证",
                () -> startActivity(new Intent(this, FxOpenSourceLicensesActivity.class)));
        TextView version = text("FX 1.0.0 · 单一应用包 · de.privacyguard.adhook", 11, false);
        version.setTag("fx-card-detail");
        version.setGravity(Gravity.CENTER);
        version.setPadding(0, dp(12), 0, dp(8));
        content.addView(version);

        setContentViewWithNativeTabs(scroll, 5);
    }

    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private TextView text(String value, int size, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(0xff263344);
        if (bold) view.setTypeface(null, android.graphics.Typeface.BOLD);
        return view;
    }

    private Button button(String label, Runnable action) {
        Button view = new Button(this);
        view.setTag("fx-action-row");
        view.setAllCaps(false);
        view.setText(label);
        view.setOnClickListener(v -> action.run());
        return view;
    }

    private void section(String label) {
        TextView heading = text(label, 16, true);
        heading.setTag("fx-section:" + label);
        heading.setPadding(dp(4), dp(16), dp(4), dp(7));
        content.addView(heading);
    }

    private void addActionCard(String title, String summary, String actionLabel, Runnable action) {
        LinearLayout card = new LinearLayout(this);
        card.setTag("fx-card");
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(12), dp(10), dp(12), dp(10));
        card.setBackgroundColor(0xfff1f4f8);
        TextView heading = text(title, 14, true);
        heading.setTag("fx-card-title");
        card.addView(heading);
        TextView detail = text(summary, 11, false);
        detail.setTag("fx-card-detail");
        detail.setPadding(0, dp(4), 0, dp(4));
        card.addView(detail);
        card.addView(button(actionLabel, action));
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.bottomMargin = dp(8);
        content.addView(card, params);
    }

    private void showWallpaperManager() {
        LinearLayout panel = new LinearLayout(this);
        panel.setTag("fx-card");
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(16), dp(8), dp(16), dp(4));
        boolean hasWallpaper = FxWallpaperStore.currentPath(this) != null;
        TextView status = text(hasWallpaper ? "当前已设置自定义壁纸" : "当前使用默认背景", 12, false);
        status.setTag("fx-card-detail");
        status.setPadding(0, 0, 0, dp(8));
        panel.addView(status);

        ImageView preview = new ImageView(this);
        preview.setScaleType(ImageView.ScaleType.CENTER_CROP);
        preview.setAdjustViewBounds(false);
        preview.setClipToOutline(true);
        preview.setVisibility(hasWallpaper ? View.VISIBLE : View.GONE);
        panel.addView(preview, new LinearLayout.LayoutParams(-1, dp(156)));

        AtomicReference<Bitmap> previewBitmap = new AtomicReference<>();
        androidx.appcompat.app.AlertDialog dialog = FxNativeSkin.builder(this)
                .setTitle("壁纸随心换")
                .setView(panel)
                .setPositiveButton("上传本地图片", (d, which) -> openWallpaperPicker())
                .setNeutralButton("恢复默认壁纸", (d, which) -> restoreWallpaper())
                .setNegativeButton("关闭", null)
                .create();
        dialog.setOnDismissListener(ignored -> {
            preview.setImageDrawable(null);
            Bitmap old = previewBitmap.getAndSet(null);
            if (old != null && !old.isRecycled()) old.recycle();
        });
        FxNativeSkin.showDialog(this, dialog);

        if (hasWallpaper) {
            wallpaperExecutor.execute(() -> {
                Bitmap bitmap = FxWallpaperStore.loadPreview(this);
                runOnUiThread(() -> {
                    if (bitmap == null) return;
                    if (isFinishing() || isDestroyed() || !dialog.isShowing()) {
                        bitmap.recycle();
                        return;
                    }
                    Bitmap old = previewBitmap.getAndSet(bitmap);
                    if (old != null && !old.isRecycled()) old.recycle();
                    preview.setImageBitmap(bitmap);
                });
            });
        }
    }

    private void openWallpaperPicker() {
        if (wallpaperBusy.get()) {
            Toast.makeText(this, "壁纸正在处理中，请稍后再试。", Toast.LENGTH_LONG).show();
            return;
        }
        Intent picker = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        picker.addCategory(Intent.CATEGORY_OPENABLE);
        picker.setType("image/*");
        picker.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        try {
            startActivityForResult(picker, REQUEST_WALLPAPER_PICKER);
        } catch (Exception error) {
            Toast.makeText(this, "无法打开系统图片选择器：" + error.getMessage(),
                    Toast.LENGTH_LONG).show();
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_WALLPAPER_PICKER) return;
        Uri uri = resultCode == Activity.RESULT_OK && data != null ? data.getData() : null;
        if (uri == null) {
            Toast.makeText(this, "未选择壁纸图片。", Toast.LENGTH_SHORT).show();
            return;
        }
        importWallpaper(uri);
    }

    private void importWallpaper(Uri uri) {
        if (!wallpaperBusy.compareAndSet(false, true)) {
            Toast.makeText(this, "已有壁纸操作正在进行。", Toast.LENGTH_LONG).show();
            return;
        }
        androidx.appcompat.app.AlertDialog progress = FxNativeSkin.builder(this)
                .setMessage("正在处理并保存壁纸…")
                .setCancelable(false)
                .create();
        FxNativeSkin.showDialog(this, progress);
        wallpaperExecutor.execute(() -> {
            String savedPath = null;
            Exception failure = null;
            try {
                savedPath = FxWallpaperStore.saveFromUri(this, uri);
            } catch (Exception error) {
                failure = error;
            }
            final String resultPath = savedPath;
            final Exception resultFailure = failure;
            runOnUiThread(() -> {
                wallpaperBusy.set(false);
                progress.dismiss();
                if (isFinishing() || isDestroyed()) return;
                if (resultFailure != null || resultPath == null) {
                    String reason = resultFailure == null ? "未知错误" : resultFailure.getMessage();
                    FxNativeSkin.builder(this)
                            .setTitle("壁纸保存失败")
                            .setMessage(reason == null ? "无法保存所选图片。" : reason)
                            .setPositiveButton("知道了", null)
                            .show();
                    return;
                }
                Toast.makeText(this, "壁纸已保存并应用", Toast.LENGTH_SHORT).show();
                recreate();
            });
        });
    }

    private void restoreWallpaper() {
        if (wallpaperBusy.get()) {
            Toast.makeText(this, "壁纸正在处理中，请稍后再试。", Toast.LENGTH_LONG).show();
            return;
        }
        if (!FxWallpaperStore.clear(this)) {
            Toast.makeText(this, "恢复默认壁纸失败，原壁纸设置保持不变。",
                    Toast.LENGTH_LONG).show();
            return;
        }
        Toast.makeText(this, "已恢复默认壁纸", Toast.LENGTH_SHORT).show();
        recreate();
    }

    private void openAppDetails() {
        try {
            Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
            intent.setData(Uri.parse("package:" + getPackageName()));
            startActivity(intent);
        } catch (Exception error) {
            Toast.makeText(this, "无法打开应用信息：" + error.getMessage(),
                    Toast.LENGTH_LONG).show();
        }
    }

    private void openSystemSettings(String action, String label) {
        try {
            startActivity(new Intent(action));
        } catch (Exception error) {
            Toast.makeText(this, "无法打开" + label + "：" + error.getMessage(),
                    Toast.LENGTH_LONG).show();
        }
    }

    @Override protected void onDestroy() {
        wallpaperExecutor.shutdown();
        super.onDestroy();
    }
}
