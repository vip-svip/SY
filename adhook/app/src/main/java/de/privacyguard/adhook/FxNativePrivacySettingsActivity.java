package de.privacyguard.adhook;

import de.privacyguard.adhook.imported.ad.FxYulongRootModuleCommand;

import android.os.Bundle;
import android.graphics.Typeface;
import android.view.View;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Native global privacy controls backed by the module's allowlisted settings.conf.
 * The JSON asset is presentation metadata only; root-side default.conf is the authority.
 */
public final class FxNativePrivacySettingsActivity extends FxNativeTabActivity {
    private final ExecutorService worker = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "fx-privacy-settings"); t.setDaemon(true); return t;
    });
    private final Map<String, CheckBox> controls = new LinkedHashMap<>();
    private final Map<String, String> titles = new LinkedHashMap<>();
    private LinearLayout content;
    private TextView status;
    private boolean loading;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        content = new LinearLayout(this); content.setTag("fx-card-group");
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(16), dp(18), dp(16), dp(20));
        TextView title = new TextView(this);
        title.setTag("fx-title:24");
        title.setText("隐私设置");
        title.setTextSize(24);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        content.addView(title);
        TextView note = new TextView(this);
        note.setTag("fx-card-detail");
        note.setText("全局模块开关 · 设置写入 settings.conf 并触发快速应用；未被模块声明的选项不会显示。");
        note.setTextSize(12);
        note.setPadding(0, dp(6), 0, dp(12));
        content.addView(note);
        status = new TextView(this);
        status.setTag("fx-loading-state");
        status.setText("正在读取模块设置…");
        status.setTextSize(12);
        content.addView(status);
        Button refresh = new Button(this); refresh.setTag("fx-action-row");
        refresh.setText("刷新模块状态");
        refresh.setOnClickListener(v -> loadSettings());
        content.addView(refresh);
        ScrollView scroll = new ScrollView(this); scroll.setTag("fx-page-root");
        scroll.addView(content);
        setContentViewWithNativeTabs(scroll, 2);
        loadMetadata();
        loadSettings();
    }

    private int dp(float value) {
        return (int)(value * getResources().getDisplayMetrics().density + .5f);
    }

    private void loadMetadata() {
        try (InputStream in = getAssets().open("native-privacy-settings.json");
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[4096];
            int count;
            while ((count = in.read(buffer)) != -1) out.write(buffer, 0, count);
            JSONObject root = new JSONObject(new String(out.toByteArray(), java.nio.charset.StandardCharsets.UTF_8));
            JSONArray panels = root.optJSONArray("panels");
            if (panels == null) throw new IllegalStateException("隐私设置面板定义缺失");
            for (int i = 0; i < panels.length(); i++) {
                JSONObject panel = panels.optJSONObject(i);
                if (panel == null) continue;
                String panelTitle = panel.optString("title", "隐私设置");
                TextView heading = new TextView(this);
                heading.setTag("fx-section:" + panelTitle);
                heading.setText(panelTitle);
                heading.setTextSize(17);
                heading.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
                heading.setPadding(0, dp(16), 0, dp(6));
                content.addView(heading);
                JSONArray items = panel.optJSONArray("items");
                if (items == null) continue;
                for (int j = 0; j < items.length(); j++) {
                    JSONObject item = items.optJSONObject(j);
                    if (item == null) continue;
                    String key = item.optString("key", "");
                    if (!key.matches("[A-Za-z0-9_.-]{1,96}") || titles.containsKey(key)) continue;
                    String label = item.optString("title", key);
                    String description = item.optString("description", "");
                    titles.put(key, label);
                    CheckBox box = new CheckBox(this);
                    box.setText(label);
                    box.setTextSize(14);
                    box.setTag("fx-switch-row");
                    controls.put(key, box);
                    content.addView(box);
                    if (!description.isEmpty()) {
                        TextView detail = new TextView(this);
                        detail.setTag("fx-card-detail");
                        detail.setText(description);
                        detail.setTextSize(11);
                        detail.setPadding(dp(34), 0, dp(4), dp(6));
                        content.addView(detail);
                    }
                    box.setOnCheckedChangeListener((button, checked) -> {
                        if (loading) return;
                        button.setEnabled(false);
                        status.setText("正在应用：" + label);
                        status.setTag("fx-loading-state");
                        worker.execute(() -> {
                            RootAccess.Result result = runHelper("set " + key + " " + (checked ? "1" : "0"));
                            runOnUiThread(() -> {
                                if (isFinishing() || isDestroyed()) return;
                                button.setEnabled(true);
                                if (result.exitCode == 0) {
                                    status.setText(label + "：已保存并应用");
                                    status.setTag("fx-success-state");
                                    Toast.makeText(this, "已应用：" + label, Toast.LENGTH_SHORT).show();
                                } else {
                                    loading = true;
                                    button.setChecked(!checked);
                                    loading = false;
                                    status.setText("应用失败：" + shortMessage(result.output));
                                    status.setTag("fx-error-state");
                                    Toast.makeText(this, "设置未生效，请查看模块状态", Toast.LENGTH_LONG).show();
                                }
                            });
                        });
                    });
                }
            }
        } catch (Exception error) {
            status.setText("隐私设置定义读取失败：" + error.getClass().getSimpleName());
            status.setTag("fx-error-state");
        }
    }

    private void loadSettings() {
        if (loading) return;
        loading = true;
        status.setText("正在读取模块设置…");
        status.setTag("fx-loading-state");
        worker.execute(() -> {
            RootAccess.Result result = runHelper("list");
            Map<String, Boolean> values = new LinkedHashMap<>();
            if (result.exitCode == 0 && result.output != null) {
                for (String line : result.output.split("\\r?\\n")) {
                    int split = line.indexOf('=');
                    if (split <= 0) continue;
                    String key = line.substring(0, split).trim();
                    String value = line.substring(split + 1).trim();
                    if (key.matches("[A-Za-z0-9_.-]{1,96}") && ("0".equals(value) || "1".equals(value))) {
                        values.put(key, "1".equals(value));
                    }
                }
            }
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                loading = true;
                int available = 0;
                for (Map.Entry<String, CheckBox> entry : controls.entrySet()) {
                    Boolean value = values.get(entry.getKey());
                    CheckBox box = entry.getValue();
                    box.setEnabled(value != null);
                    if (value != null) {
                        box.setChecked(value);
                        available++;
                    } else {
                        box.setChecked(false);
                    }
                }
                loading = false;
                if (result.exitCode == 0) {
                    status.setText("已连接模块设置 · " + available + " 项可用；未声明的选项已自动隐藏/禁用。");
                    status.setTag("fx-success-state");
                } else {
                    status.setText("无法读取模块设置：" + shortMessage(result.output));
                    status.setTag("fx-error-state");
                }
            });
        });
    }

    private RootAccess.Result runHelper(String arguments) {
        // Restrict callers to the two supported operations before adding the text
        // to a Root shell command. Setting keys come from the local metadata asset.
        if (arguments == null || !("list".equals(arguments)
                || arguments.matches("set [A-Za-z0-9_.-]{1,96} [01]"))) {
            return RootAccess.failure(2, "无效的隐私设置命令");
        }
        // Reuse FX's canonical, fail-closed module resolver: module ID, fixed
        // FX 1.0.0 version, non-symlinked path, and helper file are checked.
        String command = FxYulongRootModuleCommand.prefix("native-privacy-settings.sh")
                + "MP=\"$MP\" PG='/data/adb/privacyguard' "
                + "sh \"$MP/scripts/native-privacy-settings.sh\" " + arguments;
        return RootAccess.execute(command, 30000L, 32768);
    }

    private String shortMessage(String message) {
        if (message == null || message.trim().isEmpty()) return "无模块返回信息";
        String value = message.trim().replace('\n', ' ');
        return value.length() > 180 ? value.substring(0, 180) : value;
    }

    @Override protected void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }
}
