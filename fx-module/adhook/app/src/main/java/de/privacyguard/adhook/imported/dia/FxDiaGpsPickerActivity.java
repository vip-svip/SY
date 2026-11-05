package de.privacyguard.adhook.imported.dia;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Bundle;
import android.text.InputType;
import android.webkit.SslErrorHandler;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.net.http.SslError;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.Locale;

/**
 * Native FX migration of Dia 23.11 GPSActivity:
 * embeds the original AMap coordinate picker and returns the original AMap
 * coordinate pair (GCJ-02; no WGS84 conversion) to the selected app's
 * existing LSPosed test-location editor.
 *
 * No Javascript bridge is exposed. Only HTTPS AMap pages may be navigated.
 */
public final class FxDiaGpsPickerActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    private static final String PICKER_URL = "https://lbs.amap.com/console/show/picker";
    private WebView webView;
    private EditText pairInput;
    private EditText latitudeInput;
    private EditText longitudeInput;
    private TextView status;
    private static final String STATE_PAIR = "fx_dia_gps_pair";
    private static final String STATE_LATITUDE = "fx_dia_gps_latitude";
    private static final String STATE_LONGITUDE = "fx_dia_gps_longitude";
    private static final String STATE_STATUS = "fx_dia_gps_status";

    private int dp(float value) {
        return (int)(value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private TextView label(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        if (bold) view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        view.setPadding(dp(4), dp(5), dp(4), dp(5));
        return view;
    }

    private Button button(String value, Runnable action) {
        Button button = new Button(this);
        button.setAllCaps(false);
        button.setText(value);
        button.setOnClickListener(v -> action.run());
        return button;
    }

    private EditText decimalInput(String hint, String value) {
        EditText input = new EditText(this);
        input.setSingleLine(true);
        input.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_SIGNED
                | InputType.TYPE_NUMBER_FLAG_DECIMAL);
        input.setHint(hint);
        input.setText(value == null ? "" : value);
        return input;
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(4), dp(12), dp(4));
        header.addView(button("‹ 返回 Hook", this::finish));
        header.addView(label("Hook · GPS 地图选点", 18, 0xff17212b, true),
                new LinearLayout.LayoutParams(0, -2, 1));
        root.addView(header);

        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(14), dp(6), dp(14), dp(8));

        pairInput = new EditText(this);
        pairInput.setSingleLine(true);
        pairInput.setHint("粘贴高德坐标：经度,纬度");
        pairInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        form.addView(pairInput);

        LinearLayout coordinateRow = new LinearLayout(this);
        coordinateRow.setOrientation(LinearLayout.HORIZONTAL);
        String initialLatitude = state == null
                ? getIntent().getStringExtra("latitude")
                : state.getString(STATE_LATITUDE, getIntent().getStringExtra("latitude"));
        String initialLongitude = state == null
                ? getIntent().getStringExtra("longitude")
                : state.getString(STATE_LONGITUDE, getIntent().getStringExtra("longitude"));
        latitudeInput = decimalInput("纬度 -90 至 90", initialLatitude);
        longitudeInput = decimalInput("经度 -180 至 180", initialLongitude);
        if (state != null) pairInput.setText(state.getString(STATE_PAIR, ""));
        coordinateRow.addView(longitudeInput, new LinearLayout.LayoutParams(0, -2, 1));
        coordinateRow.addView(latitudeInput, new LinearLayout.LayoutParams(0, -2, 1));
        form.addView(coordinateRow);

        TextView note = label("使用方法：在下方高德地图选择位置，把地图显示的“经度,纬度”（高德 GCJ-02 坐标）复制到上方输入框，再点“解析坐标”。也可以直接分别输入经度和纬度。按原 Dia 行为直接使用高德返回值，不做 WGS84 转换；坐标只会回填到当前选择的 debuggable 目标应用，不会改变系统真实定位。", 12, 0xff647282, false);
        form.addView(note);
        status = label(state == null ? "等待地图坐标。"
                : state.getString(STATE_STATUS, "已恢复上次编辑状态。"), 12, 0xff526170, false);
        form.addView(status);

        LinearLayout buttons = new LinearLayout(this);
        buttons.addView(button("解析高德坐标", this::parsePair),
                new LinearLayout.LayoutParams(0, -2, 1));
        buttons.addView(button("确认并返回", this::returnCoordinates),
                new LinearLayout.LayoutParams(0, -2, 1));
        form.addView(buttons);
        root.addView(form);

        webView = new WebView(this);
        configureWebView(webView);
        root.addView(webView, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentViewWithNativeTabs(root, 4);

        boolean restoredMap = false;
        if (state != null) {
            try {
                restoredMap = webView.restoreState(state) != null && webView.getUrl() != null;
            } catch (RuntimeException restoreFailed) {
                status.setText("地图页面恢复失败；坐标输入已恢复，可重新加载地图。");
            }
        }
        if (!restoredMap) webView.loadUrl(PICKER_URL);
    }

    private void configureWebView(WebView view) {
        WebSettings settings = view.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setSupportZoom(true);
        settings.setBuiltInZoomControls(true);
        settings.setDisplayZoomControls(false);
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setAllowFileAccessFromFileURLs(false);
        settings.setAllowUniversalAccessFromFileURLs(false);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        settings.setSupportMultipleWindows(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        view.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView web, WebResourceRequest request) {
                return !isAllowedMapUrl(request == null || request.getUrl() == null
                        ? null : request.getUrl());
            }
            @Override public boolean shouldOverrideUrlLoading(WebView web, String url) {
                Uri uri;
                try { uri = Uri.parse(url); } catch (Exception invalid) { return true; }
                return !isAllowedMapUrl(uri);
            }
            @Override public void onReceivedSslError(WebView web, SslErrorHandler handler, SslError error) {
                handler.cancel();
                status.setText("高德地图 TLS 证书校验失败，已阻止不安全连接。");
            }
        });
    }

    private boolean isAllowedMapUrl(Uri uri) {
        if (uri == null || !"https".equalsIgnoreCase(uri.getScheme())) return false;
        String host = uri.getHost();
        return host != null && (host.equalsIgnoreCase("amap.com")
                || host.toLowerCase(Locale.ROOT).endsWith(".amap.com")
                || host.equalsIgnoreCase("gaode.com")
                || host.toLowerCase(Locale.ROOT).endsWith(".gaode.com"));
    }

    private void parsePair() {
        String raw = pairInput.getText() == null ? "" : pairInput.getText().toString();
        try {
            FxDiaGpsCoordinateParser.Coordinates coordinates =
                    FxDiaGpsCoordinateParser.parseAmapPair(raw);
            setCoordinates(coordinates.latitude, coordinates.longitude);
            status.setText("已解析高德坐标（经度,纬度）。");
        } catch (IllegalArgumentException invalid) {
            status.setText("坐标无效：" + invalid.getMessage());
        }
    }

    private void setCoordinates(double latitude, double longitude) {
        latitudeInput.setText(Double.toString(latitude));
        longitudeInput.setText(Double.toString(longitude));
    }

    private void returnCoordinates() {
        try {
            FxDiaGpsCoordinateParser.Coordinates coordinates =
                    FxDiaGpsCoordinateParser.parseSeparate(
                            latitudeInput.getText().toString(),
                            longitudeInput.getText().toString());
            Intent result = new Intent();
            result.putExtra("latitude", Double.toString(coordinates.latitude));
            result.putExtra("longitude", Double.toString(coordinates.longitude));
            setResult(RESULT_OK, result);
            finish();
        } catch (IllegalArgumentException invalid) {
            status.setText(invalid.getMessage() == null ? "请输入有效坐标。" : invalid.getMessage());
        }
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        if (pairInput != null) outState.putString(STATE_PAIR, pairInput.getText().toString());
        if (latitudeInput != null) outState.putString(STATE_LATITUDE, latitudeInput.getText().toString());
        if (longitudeInput != null) outState.putString(STATE_LONGITUDE, longitudeInput.getText().toString());
        if (status != null) outState.putString(STATE_STATUS, status.getText().toString());
        if (webView != null) {
            try { webView.saveState(outState); } catch (RuntimeException ignored) { }
        }
        super.onSaveInstanceState(outState);
    }

    @Override protected void onDestroy() {
        if (webView != null) {
            webView.stopLoading();
            webView.setWebViewClient(null);
            webView.destroy();
            webView = null;
        }
        super.onDestroy();
    }
}
