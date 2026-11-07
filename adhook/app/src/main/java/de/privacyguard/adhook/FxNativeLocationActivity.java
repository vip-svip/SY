package de.privacyguard.adhook;

import android.os.Bundle;
import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import de.privacyguard.adhook.imported.ad.FxYulongRootModuleCommand;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.regex.Pattern;

/**
 * Custom location picker.
 *
 * Writes real per-target coordinates into the module's hook target row, which the
 * hook then delivers as a constructed {@link android.location.Location} to the
 * selected app. This is not a "report a fake value" page: the coordinates below are
 * the ones the injected fix carries.
 *
 * The screen deliberately keeps the write path narrow:
 *  - package and coordinates are validated here and again in the module script;
 *  - the module script performs the atomic settings.conf update;
 *  - only a successful helper result is reported as saved.
 */
public final class FxNativeLocationActivity extends FxNativeTabActivity {

    /** Latitude ±90 with optional decimals; the module script repeats this check. */
    private static final Pattern LATITUDE =
            Pattern.compile("^-?[0-9]{1,2}(\\.[0-9]{1,8})?$|^-?90(\\.0{1,8})?$");
    private static final Pattern LONGITUDE =
            Pattern.compile("^-?[1-9]?[0-9]{1,2}(\\.[0-9]{1,8})?$|^-?1[0-7][0-9](\\.[0-9]{1,8})?$|^-?180(\\.0{1,8})?$");
    private static final Pattern ACCURACY =
            Pattern.compile("^[0-9]{1,4}(\\.[0-9]{1,3})?$");
    private static final Pattern PACKAGE =
            Pattern.compile("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+$");

    private final ExecutorService worker = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "fx-location-picker");
        t.setDaemon(true);
        return t;
    });

    private EditText packageField;
    private EditText latitudeField;
    private EditText longitudeField;
    private EditText accuracyField;
    private TextView status;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout page = new LinearLayout(this);
        page.setTag("fx-page-root");
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(dp(16), dp(18), dp(16), dp(20));

        TextView title = new TextView(this);
        title.setTag("fx-title:24");
        title.setText("自定义位置");
        title.setTextSize(24);
        title.setTypeface(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD);
        page.addView(title);

        TextView note = new TextView(this);
        note.setTag("fx-card-detail");
        note.setText("为选中的应用注入真实坐标系定位：Hook 会把下面的经纬度构造成"
                + "带精度与时间戳的 Location 交还给该应用，地图、距离与围栏计算都会按这里的位置走。"
                + "坐标写入模块的 Hook 目标行，不修改系统定位。");
        note.setTextSize(12);
        note.setPadding(0, dp(6), 0, dp(12));
        page.addView(note);

        packageField = field(page, "目标应用包名", InputType.TYPE_CLASS_TEXT);
        latitudeField = field(page, "纬度（-90 ~ 90）",
                InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL
                        | InputType.TYPE_NUMBER_FLAG_SIGNED);
        longitudeField = field(page, "经度（-180 ~ 180）",
                InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL
                        | InputType.TYPE_NUMBER_FLAG_SIGNED);
        accuracyField = field(page, "精度（米，可留空，默认 5）",
                InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL);

        LinearLayout actions = new LinearLayout(this);
        actions.setTag("fx-action-row");
        actions.setGravity(Gravity.CENTER_VERTICAL);

        Button save = new Button(this);
        save.setTag("fx-primary-action");
        save.setText("保存并应用位置");
        save.setOnClickListener(v -> saveLocation());
        actions.addView(save);

        Button map = new Button(this);
        map.setTag("fx-action-row");
        map.setText("在地图中查看");
        map.setOnClickListener(v -> openMap());
        actions.addView(map);

        Button clear = new Button(this);
        clear.setTag("fx-action-row");
        clear.setText("清除该应用坐标");
        clear.setOnClickListener(v -> clearLocation());
        actions.addView(clear);

        page.addView(actions);

        status = new TextView(this);
        status.setTag("fx-loading-state");
        status.setText("填写坐标后保存；保存成功即表示目标行已写入模块配置。");
        status.setTextSize(12);
        status.setPadding(0, dp(10), 0, 0);
        page.addView(status);

        Button reload = new Button(this);
        reload.setTag("fx-action-row");
        reload.setText("读取当前已生效的目标行");
        reload.setOnClickListener(v -> loadCurrent());
        page.addView(reload);

        ScrollView scroll = new ScrollView(this);
        scroll.setTag("fx-page-root");
        scroll.addView(page);
        setContentViewWithNativeTabs(scroll, 2);

        // A caller may hand over the package it is configuring.
        String seed = getIntent() == null ? null : getIntent().getStringExtra("target_package");
        if (seed != null && PACKAGE.matcher(seed).matches()) {
            packageField.setText(seed);
            loadCurrent();
        }
    }

    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + .5f);
    }

    private EditText field(LinearLayout parent, String hint, int inputType) {
        EditText input = new EditText(this);
        input.setTag("fx-form-input");
        input.setHint(hint);
        input.setInputType(inputType);
        input.setSingleLine(true);
        input.setMinimumHeight(dp(46));
        input.setPadding(dp(14), dp(10), dp(14), dp(10));
        parent.addView(input);
        return input;
    }

    /** Open the current coordinates in a map app; the page never claims to change them. */
    private void openMap() {
        String lat = latitudeField.getText().toString().trim();
        String lon = longitudeField.getText().toString().trim();
        if (!LATITUDE.matcher(lat).matches() || !LONGITUDE.matcher(lon).matches()) {
            setStatus("请先填写合法的纬度与经度，再在地图中查看。");
            return;
        }
        try {
            Intent intent = new Intent(Intent.ACTION_VIEW,
                    Uri.parse("geo:" + lat + "," + lon + "?q=" + lat + "," + lon));
            startActivity(intent);
        } catch (Throwable unavailable) {
            setStatus("设备没有可打开地图的应用。");
        }
    }

    private void saveLocation() {
        final String pkg = packageField.getText().toString().trim();
        final String lat = latitudeField.getText().toString().trim();
        final String lon = longitudeField.getText().toString().trim();
        final String acc = accuracyField.getText().toString().trim();
        if (!PACKAGE.matcher(pkg).matches()) {
            setStatus("包名格式不正确：需要像 com.example.app 这样的完整包名。");
            return;
        }
        if (!LATITUDE.matcher(lat).matches()) {
            setStatus("纬度必须是 -90 到 90 之间的数字。");
            return;
        }
        if (!LONGITUDE.matcher(lon).matches()) {
            setStatus("经度必须是 -180 到 180 之间的数字。");
            return;
        }
        if (!acc.isEmpty() && !ACCURACY.matcher(acc).matches()) {
            setStatus("精度必须是 0 到 1000 之间的米数，或留空使用默认值。");
            return;
        }
        setStatus("正在写入目标行…");
        worker.execute(() -> {
            RootAccess.Result result = runHelper(acc.isEmpty()
                    ? "set-target " + pkg + " " + lat + " " + lon
                    : "set-target " + pkg + " " + lat + " " + lon + " " + acc);
            final String message = result.exitCode == 0 && result.output != null
                    && result.output.contains("saved=1")
                    ? "已保存：" + pkg + " → " + lat + ", " + lon
                    + (acc.isEmpty() ? "（精度默认 5 米）" : "（精度 " + acc + " 米）")
                    : "保存失败：" + shortMessage(result.output);
            runOnUiThread(() -> setStatus(message));
        });
    }

    private void clearLocation() {
        final String pkg = packageField.getText().toString().trim();
        if (!PACKAGE.matcher(pkg).matches()) {
            setStatus("请先填写要清除坐标的包名。");
            return;
        }
        setStatus("正在清除坐标…");
        worker.execute(() -> {
            RootAccess.Result result = runHelper("clear-target " + pkg);
            final String message = result.exitCode == 0
                    ? "已清除：" + pkg + " 的位置注入"
                    : "清除失败：" + shortMessage(result.output);
            runOnUiThread(() -> setStatus(message));
        });
    }

    private void loadCurrent() {
        final String pkg = packageField.getText().toString().trim();
        if (!PACKAGE.matcher(pkg).matches()) {
            setStatus("请先填写包名再读取。");
            return;
        }
        setStatus("正在读取…");
        worker.execute(() -> {
            RootAccess.Result result = runHelper("show-target " + pkg);
            final String output = result.output == null ? "" : result.output.trim();
            final String message;
            if (result.exitCode != 0) {
                message = "读取失败：" + shortMessage(output);
            } else if (output.isEmpty()) {
                message = pkg + " 目前没有 Hook 目标行。";
            } else {
                message = pkg + " 当前目标行：\n" + output;
            }
            runOnUiThread(() -> setStatus(message));
        });
    }

    private void setStatus(String message) {
        if (status != null) status.setText(message);
    }

    private RootAccess.Result runHelper(String arguments) {
        // Whitelist exactly the three coordinate operations this page needs.
        if (arguments == null || !(arguments.matches(
                "set-target [A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+ -?[0-9.]+ -?[0-9.]+( [0-9.]+)?")
                || arguments.matches("clear-target [A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+")
                || arguments.matches("show-target [A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+"))) {
            return RootAccess.failure(2, "无效的位置设置命令");
        }
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
