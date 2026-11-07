package de.privacyguard.adhook.imported.dia;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;


import de.privacyguard.adhook.FxNativeTabActivity;

import java.util.Locale;

/** Native entry hub for the remaining self-contained Dia 23.11 utilities. */
public final class FxDiaToolsActivity extends FxNativeTabActivity {
    private static final int REQUEST_GPS_PICKER = 0x6d31;
    private LinearLayout body;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this); root.setTag("fx-page-root");
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);

        LinearLayout header = new LinearLayout(this); header.setTag("fx-toolbar");
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(6), dp(12), dp(6));
        Button back = button("‹ 返回 Hook", this::finish); back.setTag("fx-toolbar-action"); header.addView(back);
        TextView pageTitle = text("Hook · Dia 工具箱", 18, 0xff17212b, true); pageTitle.setTag("fx-toolbar-title");
        header.addView(pageTitle,
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        body = new LinearLayout(this); body.setTag("fx-card-group");
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(0, dp(4), 0, dp(18));
        scroll.addView(body);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));

        section("应用与进程只读检查");
        card("数据库结构检查",
                "选择已安装应用，读取其数据库文件元数据及只读 SQLite schema；不会修改数据库内容。",
                button("打开数据库检查器", () -> openInspector("database")));
        card("进程内存元数据",
                "选择目标应用后读取进程状态、内存统计和有限的 maps 元数据。仅展示元数据，不读取进程内存内容。",
                button("打开进程检查器", () -> openInspector("memory")));
        card("APK 签名与版本",
                "只读查看已安装应用的包名、版本、签名证书、SHA 指纹和签名者历史。",
                button("查看 APK 签名", () -> open(FxDiaSignatureActivity.class)));
        section("数据与文件工具");
        card("JSON 浏览与转换",
                "通过 Android 系统文件选择器导入/导出 JSON；提供语法校验、格式化和 JSON 路径查询。",
                button("打开 JSON 工具", () -> open(FxDiaJsonActivity.class)));
        card("授权文件与 SO 浏览",
                "仅访问用户通过系统文件选择器明确授权的目录；APK/SO 信息仅针对可调试的用户应用，只读列出，不加载或执行 SO。",
                button("打开文件与 SO 浏览器", () -> open(FxDiaFileActivity.class)));
        section("系统扩展");
        card("系统安装来源与代理",
                "打开 Dia 系统扩展迁移页；Wi-Fi/HTTP 代理交给 FX 专用代理页，未知来源安装由 Android 系统按安装来源单独授权。",
                button("打开系统扩展", () -> open(FxDiaSystemExpandActivity.class)));
        section("坐标辅助");
        card("GPS 地图选点",
                "在高德地图选择 GCJ-02 坐标并回传经纬度；此工具只复制坐标，不更改系统真实定位，也不代表 FX 已启用应用级位置模拟。",
                button("打开地图并复制坐标", this::openGpsPicker));

        setContentViewWithNativeTabs(root, 4);
    }

    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        if (bold) view.setTypeface(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD);
        view.setPadding(dp(4), dp(4), dp(4), dp(4));
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

    private void section(String title) {
        TextView heading = text(title, 16, 0xff17212b, true); heading.setTag("fx-section:" + title);
        heading.setPadding(dp(16), dp(14), dp(16), dp(6));
        body.addView(heading);
    }

    private void card(String title, String description, Button action) {
        LinearLayout panel = new LinearLayout(this); panel.setTag("fx-card");
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(13), dp(9), dp(13), dp(9));
        panel.setBackgroundColor(0xfff0f3f7);
        TextView cardTitle = text(title, 14, 0xff17212b, true); cardTitle.setTag("fx-card-title"); panel.addView(cardTitle);
        TextView cardDetail = text(description, 12, 0xff617080, false); cardDetail.setTag("fx-card-detail"); panel.addView(cardDetail);
        panel.addView(action);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.setMargins(dp(12), dp(4), dp(12), dp(4));
        body.addView(panel, params);
    }

    private void open(Class<?> activity) {
        startActivity(new Intent(this, activity));
    }

    private void openInspector(String mode) {
        Intent intent = new Intent(this, FxDiaInspectorActivity.class);
        intent.putExtra("dia_mode", mode);
        startActivity(intent);
    }

    private void openGpsPicker() {
        try {
            startActivityForResult(new Intent(this, FxDiaGpsPickerActivity.class), REQUEST_GPS_PICKER);
        } catch (RuntimeException error) {
            Toast.makeText(this, "无法打开 GPS 地图选点：" + error.getClass().getSimpleName(),
                    Toast.LENGTH_LONG).show();
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_GPS_PICKER || resultCode != Activity.RESULT_OK || data == null) return;
        String latitude = data.getStringExtra("latitude");
        String longitude = data.getStringExtra("longitude");
        try {
            double lat = Double.parseDouble(latitude);
            double lon = Double.parseDouble(longitude);
            if (!Double.isFinite(lat) || !Double.isFinite(lon)
                    || lat < -90d || lat > 90d || lon < -180d || lon > 180d) {
                throw new IllegalArgumentException("坐标超出有效范围");
            }
            String pair = String.format(Locale.ROOT, "%.8f,%.8f", lat, lon);
            ClipboardManager clipboard = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            if (clipboard == null) throw new IllegalStateException("系统剪贴板不可用");
            clipboard.setPrimaryClip(ClipData.newPlainText("FX GCJ-02 latitude,longitude", pair));
            fxDialogBuilder()
                    .setTitle("地图坐标已复制")
                    .setMessage("纬度：" + latitude + "\n经度：" + longitude
                            + "\n\n已按“纬度,经度”复制到剪贴板。坐标是高德 GCJ-02，不做 WGS84 转换。")
                    .setPositiveButton("知道了", null)
                    .show();
        } catch (RuntimeException error) {
            Toast.makeText(this, "未能读取有效坐标：" + error.getMessage(),
                    Toast.LENGTH_LONG).show();
        }
    }
}
