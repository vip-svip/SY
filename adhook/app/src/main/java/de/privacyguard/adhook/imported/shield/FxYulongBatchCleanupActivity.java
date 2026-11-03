package de.privacyguard.adhook.imported.shield;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.Set;

/**
 * Sequential, user-confirmed Android uninstaller queue migrated from
 * Yulong Shield. Queue position survives configuration/process recreation.
 * The app never presses the Android uninstall confirmation on the user's behalf.
 */
public final class FxYulongBatchCleanupActivity extends Activity {
    private static final int REQUEST_UNINSTALL = 0x59b1;
    private static final int MAX_QUEUE_ITEMS = 100;

    private static final String STATE_PACKAGES = "fx_batch_packages";
    private static final String STATE_LABELS = "fx_batch_labels";
    private static final String STATE_REASONS = "fx_batch_reasons";
    private static final String STATE_REMOVED = "fx_batch_removed";
    private static final String STATE_INDEX = "fx_batch_index";

    private final ArrayList<String> packages = new ArrayList<>();
    private final ArrayList<String> labels = new ArrayList<>();
    private final ArrayList<String> reasons = new ArrayList<>();
    private final Set<String> noLongerInstalled = new HashSet<>();

    private int index;
    private TextView state;
    private TextView current;
    private Button uninstall;
    private Button next;

    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        if (bold) view.setTypeface(null, android.graphics.Typeface.BOLD);
        view.setPadding(dp(4), dp(6), dp(4), dp(6));
        return view;
    }

    private Button button(String label, Runnable action) {
        Button view = new Button(this);
        view.setAllCaps(false);
        view.setText(label);
        view.setOnClickListener(v -> action.run());
        return view;
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        if (savedInstanceState != null) {
            restoreQueue(savedInstanceState);
        } else {
            restoreQueue(getIntent().getExtras());
        }
        index = Math.max(0, Math.min(index, packages.size()));

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(12), dp(8), dp(12), dp(8));
        header.addView(button("‹ 返回扫描", this::finish));
        header.addView(text("批量清理 · 逐项确认", 19, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        ScrollView scroll = new ScrollView(this);
        LinearLayout body = new LinearLayout(this);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(14), dp(8), dp(14), dp(20));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        body.addView(text(
                "每项都会打开 Android 系统卸载确认。取消卸载不会自动继续；FX 不会静默卸载、强停或冻结应用。",
                12, 0xff8a5b12, false));
        state = text("", 13, 0xff617080, false);
        current = text("", 15, 0xff17212b, true);
        uninstall = button("打开当前应用的系统卸载确认", this::requestCurrent);
        next = button("跳过当前项，查看下一项", this::advance);
        body.addView(state);
        body.addView(current);
        body.addView(uninstall);
        body.addView(next);
        body.addView(button("结束批量处理", this::finish));

        setContentView(root);
        render();
    }

    private void restoreQueue(Bundle source) {
        if (source == null) return;
        ArrayList<String> inputPackages = source.getStringArrayList(
                source.containsKey(STATE_PACKAGES) ? STATE_PACKAGES : "packages");
        ArrayList<String> inputLabels = source.getStringArrayList(
                source.containsKey(STATE_LABELS) ? STATE_LABELS : "labels");
        ArrayList<String> inputReasons = source.getStringArrayList(
                source.containsKey(STATE_REASONS) ? STATE_REASONS : "reasons");

        if (inputPackages == null || inputLabels == null) return;
        int count = Math.min(Math.min(inputPackages.size(), inputLabels.size()), MAX_QUEUE_ITEMS);
        for (int i = 0; i < count; i++) {
            String pkg = inputPackages.get(i);
            if (pkg == null || !pkg.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")
                    || packages.contains(pkg)) continue;
            packages.add(pkg);
            String label = inputLabels.get(i);
            labels.add(label == null || label.trim().isEmpty() ? pkg : label);
            String reason = inputReasons != null && inputReasons.size() > i
                    ? inputReasons.get(i) : "";
            reasons.add(reason == null ? "" : reason);
        }

        ArrayList<String> removed = source.getStringArrayList(STATE_REMOVED);
        if (removed != null) noLongerInstalled.addAll(removed);
        index = source.getInt(STATE_INDEX, 0);
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        outState.putStringArrayList(STATE_PACKAGES, new ArrayList<>(packages));
        outState.putStringArrayList(STATE_LABELS, new ArrayList<>(labels));
        outState.putStringArrayList(STATE_REASONS, new ArrayList<>(reasons));
        outState.putStringArrayList(STATE_REMOVED, new ArrayList<>(noLongerInstalled));
        outState.putInt(STATE_INDEX, index);
    }

    private boolean isInstalled(String packageName) {
        try {
            getPackageManager().getApplicationInfo(packageName, 0);
            return true;
        } catch (Throwable ignored) {
            return false;
        }
    }

    private void advancePastMissingApps() {
        while (index < packages.size() && !isInstalled(packages.get(index))) {
            noLongerInstalled.add(packages.get(index));
            index++;
        }
    }

    private void render() {
        advancePastMissingApps();
        if (index >= packages.size()) {
            state.setText("队列完成。已不存在 " + noLongerInstalled.size()
                    + " / " + packages.size() + " 项。");
            current.setText("没有剩余项目。");
            uninstall.setEnabled(false);
            next.setEnabled(false);
            return;
        }

        String packageName = packages.get(index);
        state.setText("第 " + (index + 1) + " / " + packages.size()
                + " 项 · 已不存在 " + noLongerInstalled.size() + " 项。");
        current.setText(labels.get(index) + "\n" + packageName
                + (reasons.get(index).isEmpty() ? "" : "\n" + reasons.get(index)));
        uninstall.setEnabled(true);
        uninstall.setText("打开 Android 系统卸载确认");
        next.setEnabled(true);
    }

    private void requestCurrent() {
        if (index >= packages.size()) {
            render();
            return;
        }
        String packageName = packages.get(index);
        if (!isInstalled(packageName)) {
            render();
            return;
        }

        new AlertDialog.Builder(this)
                .setTitle("确认打开系统卸载界面")
                .setMessage(labels.get(index) + "\n" + packageName
                        + "\n\nFX 不会自动点击系统确认按钮。")
                .setNegativeButton("取消", null)
                .setPositiveButton("继续", (dialog, which) -> {
                    try {
                        Intent uninstallIntent = new Intent(
                                Intent.ACTION_DELETE, Uri.parse("package:" + packageName));
                        uninstallIntent.putExtra(Intent.EXTRA_RETURN_RESULT, true);
                        startActivityForResult(uninstallIntent, REQUEST_UNINSTALL);
                    } catch (Throwable error) {
                        state.setText("无法打开系统卸载界面："
                                + error.getClass().getSimpleName());
                    }
                })
                .show();
    }

    private void advance() {
        if (index < packages.size()) index++;
        render();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_UNINSTALL || index >= packages.size()) return;

        String packageName = packages.get(index);
        if (!isInstalled(packageName)) {
            noLongerInstalled.add(packageName);
            state.setText("系统已移除当前应用，正在更新队列位置…");
            index++;
            render();
        } else if (resultCode == RESULT_OK) {
            state.setText("系统返回成功，但应用仍在清单中；请刷新确认后再继续。");
            uninstall.setEnabled(true);
            next.setEnabled(true);
        } else {
            state.setText("卸载未完成或已取消。可重新确认或跳过此项。");
            uninstall.setEnabled(true);
            next.setEnabled(true);
        }
    }
}
