package de.privacyguard.adhook;

import androidx.activity.ComponentActivity;
import android.app.AlertDialog;
import android.content.Intent;
import android.net.Uri;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceError;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebChromeClient;
import android.webkit.ValueCallback;
import android.webkit.JsResult;
import android.webkit.JsPromptResult;
import android.webkit.WebView;
import androidx.webkit.WebViewAssetLoader;
import android.webkit.WebViewClient;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewParent;
import android.widget.*;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

/** Unified FX APP shell: bundled full management UI plus native per-app Hook manager. */
public final class MainActivity extends ComponentActivity {
    private LinearLayout root;
    private EditText search;
    private final List<ApplicationInfo> apps = new ArrayList<>();
    private final List<ApplicationInfo> filtered = new ArrayList<>();
    // Cache labels/icons once; search must not repeatedly query PackageManager.
    private final Map<String, String> appLabels = new HashMap<>();
    // Keep the icon cache bounded: users may page through hundreds of installed apps.
    private final Map<String, Drawable> appIcons = new LinkedHashMap<String, Drawable>(80, 0.75f, true) {
        @Override protected boolean removeEldestEntry(Map.Entry<String, Drawable> eldest) {
            return size() > 80;
        }
    };
    // Visible rows use placeholders while PackageManager decodes icons off the UI thread.
    private final Map<String, ImageView> appIconViews = new HashMap<>();
    private volatile Thread appIconLoaderThread;
    private int appIconLoadGeneration;
    private static final int MAX_APP_ROWS_PER_PAGE = 40;
    private String selectedPackage;
    private String selectedLabel;
    private WebView webView;
    private RootBridge rootBridge;
    private TextView rootStatus;
    private LinearLayout nativeVpnControls;
    private Switch nativeVpnSwitch;
    private TextView nativeVpnState;
    private boolean syncingNativeVpn;
    private final Handler nativeVpnHandler = new Handler(Looper.getMainLooper());
    private final Runnable nativeVpnPoll = new Runnable() {
        @Override public void run() {
            if (isFinishing() || hookUiVisible || settingsUiVisible || webView == null || !webUiReady) return;
            syncNativeVpnControls();
            nativeVpnHandler.postDelayed(this, 5000L);
        }
    };
    private boolean hookUiVisible;
    private boolean hookTargetVisible;
    private boolean hookHubVisible;
    private boolean settingsUiVisible;
    private String uiMode = "classic";
    private int selectedBottomTab = 0;
    private int lastWebTabIndex = 0;
    private boolean webViewLoaded;
    private boolean webUiReady;
    private String pendingWebPage;
    private String pendingRestorePackage;
    private ValueCallback<Uri[]> fileChooserCallback;
    private volatile Thread hookPublisherThread;
    private volatile Thread hookStatusThread;
    private int hookStatusGeneration;
    private volatile Thread appLoaderThread;
    private int appLoadGeneration;
    private boolean appsLoaded;
    private static final int REQUEST_FILE_PICKER = 4101;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        uiMode = normalizeUiMode(getSharedPreferences("fx_ui", MODE_PRIVATE)
                .getString("mode", "classic"));
        boolean restoreHookScreen = false;
        boolean restoreSettingsScreen = false;
        String restoreHookKind = "";
        if (state != null) {
            lastWebTabIndex = Math.max(0, Math.min(5,
                    state.getInt("fx_last_web_tab", 0)));
            selectedBottomTab = Math.max(0, Math.min(5,
                    state.getInt("fx_selected_bottom_tab", lastWebTabIndex)));
            pendingWebPage = webPageForBottomTab(lastWebTabIndex);
            restoreHookScreen = selectedBottomTab == 4;
            restoreSettingsScreen = state.getBoolean("fx_settings_screen", false);
            restoreHookKind = state.getString("fx_hook_screen", "list");
            if ("target".equals(restoreHookKind)) {
                pendingRestorePackage = state.getString("fx_selected_package");
            }
        }
        if (restoreHookScreen) {
            if ("hub".equals(restoreHookKind)) showHookHub();
            else showAppList();
        } else if (restoreSettingsScreen) {
            showSettings();
        } else {
            showDashboard();
        }
    }

    @Override protected void onResume() {
        super.onResume();
        if (!hookUiVisible && !settingsUiVisible) startNativeVpnPolling();
    }

    @Override protected void onPause() {
        stopNativeVpnPolling();
        super.onPause();
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        outState.putInt("fx_last_web_tab", lastWebTabIndex);
        outState.putInt("fx_selected_bottom_tab", selectedBottomTab);
        outState.putBoolean("fx_settings_screen", settingsUiVisible);
        if (hookUiVisible) {
            boolean restoringTarget = hookTargetVisible || pendingRestorePackage != null;
            String hookScreen = hookHubVisible ? "hub" : restoringTarget ? "target" : "list";
            outState.putString("fx_hook_screen", hookScreen);
            String targetPackage = pendingRestorePackage != null
                    ? pendingRestorePackage : selectedPackage;
            if ("target".equals(hookScreen) && targetPackage != null) {
                outState.putString("fx_selected_package", targetPackage);
            }
        }
        super.onSaveInstanceState(outState);
    }

    private static boolean isTrustedAssetUrl(Uri uri) {
        return uri != null
                && "https".equalsIgnoreCase(uri.getScheme())
                && "appassets.androidplatform.net".equalsIgnoreCase(uri.getHost())
                && uri.getPort() == -1
                && uri.getUserInfo() == null
                && uri.getPath() != null
                && uri.getPath().startsWith("/assets/");
    }

    private static boolean isTrustedDocumentUrl(Uri uri) {
        return isTrustedAssetUrl(uri)
                && "/assets/webroot/index.html".equals(uri.getPath());
    }

    private String webPageForBottomTab(int index) {
        switch (index) {
            case 1: return "pageHosts";
            case 2: return "pagePrivacy";
            case 3: return "pageScript";
            case 5: return "pageMore";
            default: return "pageVpn";
        }
    }

    private void showDashboard() { showWebDashboard(); }

    private void showWebDashboard() {
        cancelHookStatusRefresh();
        cancelAppIconLoad();
        settingsUiVisible = false;
        // A restored target is only valid while the app-list restoration is still active.
        pendingRestorePackage = null;
        hookUiVisible = false;
        hookTargetVisible = false;
        hookHubVisible = false;
        selectedBottomTab = lastWebTabIndex;
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff4f6f8);

        LinearLayout toolbar = new LinearLayout(this);
        toolbar.setGravity(Gravity.CENTER_VERTICAL);
        toolbar.setPadding(dp(14), dp(6), dp(10), dp(6));
        toolbar.setBackgroundColor(0xff101820);
        TextView brand = new TextView(this);
        brand.setText("FX");
        brand.setTextSize(20);
        brand.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        brand.setTextColor(0xffffffff);
        toolbar.addView(brand, new LinearLayout.LayoutParams(0, -2, 1));
        rootStatus = new TextView(this);
        rootStatus.setText("Root 检查中");
        rootStatus.setTextSize(10);
        rootStatus.setMaxLines(2);
        rootStatus.setEllipsize(android.text.TextUtils.TruncateAt.END);
        rootStatus.setTextColor(0xffd8e0e8);
        rootStatus.setPadding(dp(8), dp(8), dp(8), dp(8));
        rootStatus.setMaxWidth(dp(132));
        rootStatus.setGravity(Gravity.CENTER_VERTICAL | Gravity.END);
        rootStatus.setOnClickListener(v -> checkRoot(rootStatus, true));
        toolbar.addView(rootStatus, new LinearLayout.LayoutParams(dp(132), -2));
        root.addView(toolbar, new LinearLayout.LayoutParams(-1, -2));
        buildNativeVpnControls();
        nativeVpnControls.setVisibility(lastWebTabIndex == 0 ? View.VISIBLE : View.GONE);
        root.addView(nativeVpnControls, new LinearLayout.LayoutParams(-1, -2));

        if (webView == null) {
        webUiReady = false;
        webView = new WebView(this);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(false);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(true); // only user-selected content:// URIs are exposed by the native picker
        settings.setAllowFileAccessFromFileURLs(false);
        settings.setAllowUniversalAccessFromFileURLs(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        settings.setSupportMultipleWindows(false);
        settings.setSafeBrowsingEnabled(true);

        WebViewAssetLoader.AssetsPathHandler fallback =
                new WebViewAssetLoader.AssetsPathHandler(MainActivity.this);
        WebViewAssetLoader.PathHandler handler = assetPath -> {
            if ("webroot/index.html".equals(assetPath)) {
                try (InputStream in = getAssets().open(assetPath);
                     ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                    byte[] buffer = new byte[8192];
                    int n;
                    while ((n = in.read(buffer)) > 0) out.write(buffer, 0, n);
                    String html = new String(out.toByteArray(), StandardCharsets.UTF_8);
                    String shim = "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'self' data: blob:; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'none'; object-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'\">"
                        + "<script>(function(){var seq=0;window.ksu={exec:function(cmd,opts,cb){if(typeof cb==='string'){FXRoot.exec(String(cmd),cb);return null;}return new Promise(function(resolve){var n='__fxPromise_'+(++seq);window[n]=function(errno,stdout,stderr){resolve({errno:errno,stdout:stdout,stderr:stderr});};FXRoot.exec(String(cmd),n);});},fullScreen:function(){},enableEdgeToEdge:function(){}};window.KernelSU=window.ksu;window.FXNative={openHookManager:function(){FXRoot.openHookManager();}};window.showSaveFilePicker=async function(opts){var name=(opts&&opts.suggestedName)||'FX-export.txt';return {createWritable:async function(){var value='';return {write:async function(v){value=v;},close:async function(){var blob=value instanceof Blob?value:new Blob([value],{type:'text/plain;charset=utf-8'});var reader=new FileReader();reader.onloadend=function(){var data=String(reader.result||'').split(',').pop();FXRoot.saveBase64(name,data,blob.type||'text/plain');};reader.readAsDataURL(blob);}};}};};})();</script>";
                    int headEnd = html.toLowerCase().lastIndexOf("</head>");
                    if (headEnd >= 0) html = html.substring(0, headEnd)
                            + "<style id='fx-native-nav-hide'>"
                            + "#screen>.navbar,#screen .navbar,#bottomNav,#bottom-nav,.bottom-nav,"
                            + ".bottom-navbar,.bottom-tabs,.bottom-tab-bar,.tab-bar,.tabbar,"
                            + ".nav-bottom,.navigation-bottom{display:none!important}"
                            + "#screen{padding-bottom:0!important;margin-bottom:0!important}"
                            + "#vpnStatusCard .vpn-toggle-wrap,#vpnModeSeg{display:none!important}"
                            + "</style>"
                            + shim + html.substring(headEnd);
                    return new WebResourceResponse("text/html", "UTF-8",
                            new ByteArrayInputStream(html.getBytes(StandardCharsets.UTF_8)));
                } catch (Exception e) {
                    return new WebResourceResponse("text/plain", "UTF-8",
                            new ByteArrayInputStream(("FX UI asset error: " + e).getBytes(StandardCharsets.UTF_8)));
                }
            }
            return fallback.handle(assetPath);
        };
        WebViewAssetLoader loader = new WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", handler).build();
        rootBridge = new RootBridge(this, webView);
        webView.addJavascriptInterface(rootBridge, "FXRoot");
        webView.setWebChromeClient(new WebChromeClient() {
            @Override public boolean onJsAlert(WebView view, String url, String message, JsResult result) {
                new AlertDialog.Builder(MainActivity.this).setMessage(message)
                        .setPositiveButton(android.R.string.ok, (d, w) -> result.confirm())
                        .setOnCancelListener(d -> result.cancel()).show();
                return true;
            }
            @Override public boolean onJsConfirm(WebView view, String url, String message, JsResult result) {
                new AlertDialog.Builder(MainActivity.this).setMessage(message)
                        .setPositiveButton(android.R.string.ok, (d, w) -> result.confirm())
                        .setNegativeButton(android.R.string.cancel, (d, w) -> result.cancel())
                        .setOnCancelListener(d -> result.cancel()).show();
                return true;
            }
            @Override public boolean onJsPrompt(WebView view, String url, String message, String defaultValue, JsPromptResult result) {
                EditText input = new EditText(MainActivity.this);
                input.setText(defaultValue);
                new AlertDialog.Builder(MainActivity.this).setMessage(message).setView(input)
                        .setPositiveButton(android.R.string.ok, (d, w) -> result.confirm(input.getText().toString()))
                        .setNegativeButton(android.R.string.cancel, (d, w) -> result.cancel())
                        .setOnCancelListener(d -> result.cancel()).show();
                return true;
            }
            @Override public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback,
                    FileChooserParams params) {
                ValueCallback<Uri[]> previous = fileChooserCallback;
                fileChooserCallback = null;
                deliverFileChooserResult(previous, null);
                fileChooserCallback = callback;
                try {
                    Intent intent = params.createIntent();
                    startActivityForResult(intent, REQUEST_FILE_PICKER);
                    return true;
                } catch (Exception e) {
                    // WebView requires every accepted file-chooser callback to be completed,
                    // including the failure path; otherwise the page can remain stuck waiting.
                    ValueCallback<Uri[]> pending = fileChooserCallback;
                    fileChooserCallback = null;
                    deliverFileChooserResult(pending, null);
                    Toast.makeText(MainActivity.this, "无法打开文件选择器：" + e.getMessage(),
                            Toast.LENGTH_LONG).show();
                    return true;
                }
            }
        });
        webView.setWebViewClient(new WebViewClient() {
            @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                String scheme = uri.getScheme();
                if ("data".equalsIgnoreCase(scheme) || "blob".equalsIgnoreCase(scheme)) return null;
                if (!isTrustedAssetUrl(uri)) {
                    return new WebResourceResponse("text/plain", "UTF-8",
                            new ByteArrayInputStream(new byte[0]));
                }
                return loader.shouldInterceptRequest(uri);
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                // addJavascriptInterface is visible to every frame. Refuse iframe and
                // off-origin document navigations so only the packaged UI can reach RootBridge.
                return !request.isForMainFrame() || !isTrustedDocumentUrl(request.getUrl());
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view, String url) {
                return !isTrustedDocumentUrl(Uri.parse(url));
            }
            @Override public void onReceivedError(WebView view, WebResourceRequest request,
                    WebResourceError error) {
                super.onReceivedError(view, request, error);
                if (request.isForMainFrame()) {
                    webUiReady = false;
                    webViewLoaded = false;
                    pendingWebPage = webPageForBottomTab(lastWebTabIndex);
                    Toast.makeText(MainActivity.this,
                            "FX 页面加载失败，点击底部任一标签可重试。",
                            Toast.LENGTH_LONG).show();
                }
            }
            @Override public void onReceivedHttpError(WebView view, WebResourceRequest request,
                    WebResourceResponse response) {
                super.onReceivedHttpError(view, request, response);
                if (request.isForMainFrame() && response.getStatusCode() >= 400) {
                    webUiReady = false;
                    webViewLoaded = false;
                    pendingWebPage = webPageForBottomTab(lastWebTabIndex);
                    Toast.makeText(MainActivity.this,
                            "FX 页面资源异常（HTTP " + response.getStatusCode()
                                    + "），点击底部任一标签可重试。",
                            Toast.LENGTH_LONG).show();
                }
            }
            @Override public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                if (isTrustedDocumentUrl(Uri.parse(url))) {
                    webUiReady = true;
                    applyWebUiMode();
                    syncNativeVpnControls();
                    startNativeVpnPolling();
                    if (pendingWebPage != null) {
                        String pending = pendingWebPage;
                        pendingWebPage = null;
                        navigateWebPage(pending);
                    }
                }
            }
        });
        } else {
            ViewParent parent = webView.getParent();
            if (parent instanceof ViewGroup) ((ViewGroup) parent).removeView(webView);
            webView.onResume();
            webView.resumeTimers();
        }
        root.addView(webView, new LinearLayout.LayoutParams(-1, 0, 1));
        mountNativeShell(root);
        // The WebView is detached while native Hook/Settings screens are visible.
        // Re-apply the persisted mode only after it has been resumed and reattached.
        if (webUiReady) applyWebUiMode();
        if (!webViewLoaded) {
            checkRoot(rootStatus, false, () -> {
                if (!webViewLoaded) {
                    webView.loadUrl("https://appassets.androidplatform.net/assets/webroot/index.html");
                    webViewLoaded = true;
                }
            });
        } else {
            checkRoot(rootStatus, false);
        }
        startNativeVpnPolling();
    }

    private void startNativeVpnPolling() {
        nativeVpnHandler.removeCallbacks(nativeVpnPoll);
        if (!hookUiVisible && !settingsUiVisible && webUiReady && webView != null) {
            nativeVpnHandler.postDelayed(nativeVpnPoll, 1000L);
        }
    }

    private void stopNativeVpnPolling() {
        nativeVpnHandler.removeCallbacks(nativeVpnPoll);
    }

    /** Native VPN controls call the existing, validated WebUI transaction pipeline.
     *  The old HTML switch/mode strip is hidden to prevent duplicate controls. */
    private void buildNativeVpnControls() {
        nativeVpnControls = new LinearLayout(this);
        nativeVpnControls.setOrientation(LinearLayout.VERTICAL);
        nativeVpnControls.setPadding(dp(14), dp(10), dp(14), dp(10));
        nativeVpnControls.setBackgroundColor(0xfff4f6f8);

        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(14), dp(10), dp(14), dp(10));
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(0xffffffff);
        bg.setCornerRadius(dp(18));
        bg.setStroke(dp(1), 0x1f607d8b);
        card.setBackground(bg);

        LinearLayout head = new LinearLayout(this);
        head.setGravity(Gravity.CENTER_VERTICAL);
        TextView title = new TextView(this);
        title.setText("VPN 控制");
        title.setTextSize(17);
        title.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        title.setTextColor(0xff17212b);
        head.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
        nativeVpnSwitch = new Switch(this);
        nativeVpnSwitch.setText("代理总开关");
        nativeVpnSwitch.setTextColor(0xff263238);
        nativeVpnSwitch.setOnCheckedChangeListener((button, checked) -> {
            if (syncingNativeVpn || webView == null || !webUiReady) return;
            // Reuse the real WebUI master-toggle transaction; do not invent a JS API.
            webView.evaluateJavascript("(function(){var b=document.getElementById('vpnEnableToggle');if(b)b.click();return !!b})()", value -> {
                if (value == null || "false".equals(value)) Toast.makeText(this, "VPN 原生开关未找到后端控件", Toast.LENGTH_SHORT).show();
                webView.postDelayed(this::syncNativeVpnControls, 4000);
            });
        });
        head.addView(nativeVpnSwitch);
        card.addView(head);

        nativeVpnState = new TextView(this);
        nativeVpnState.setText("正在读取 VPN 后端状态…");
        nativeVpnState.setTextSize(12);
        nativeVpnState.setTextColor(0xff667784);
        nativeVpnState.setPadding(0, dp(4), 0, dp(8));
        card.addView(nativeVpnState);

        LinearLayout modes = new LinearLayout(this);
        modes.setGravity(Gravity.CENTER_VERTICAL);
        modes.setOrientation(LinearLayout.HORIZONTAL);
        modes.setWeightSum(4);
        String[] labels = {"直连", "全局", "规则"};
        String[] values = {"direct", "global", "rule"};
        for (int i = 0; i < values.length; i++) {
            final String mode = values[i];
            Button button = new Button(this);
            button.setAllCaps(false);
            button.setText(labels[i]);
            button.setTextSize(12);
            button.setMinHeight(dp(40));
            button.setPadding(dp(2), 0, dp(2), 0);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, dp(42), 1);
            lp.setMargins(dp(2), 0, dp(2), 0);
            button.setOnClickListener(v -> {
                if (webView == null || !webUiReady) {
                    Toast.makeText(this, "VPN 页面尚未就绪，请稍后重试", Toast.LENGTH_SHORT).show();
                    return;
                }
                final int modeIndex = "direct".equals(mode) ? 0 : "global".equals(mode) ? 1 : 2;
                webView.evaluateJavascript("(function(){var a=document.querySelectorAll('#vpnModeSeg > *');if(a.length<=" + modeIndex + ")return false;a[" + modeIndex + "].click();return true})()", value -> {
                    if (value == null || "false".equals(value)) Toast.makeText(this, "未找到对应 VPN 模式控件", Toast.LENGTH_SHORT).show();
                    webView.postDelayed(this::syncNativeVpnControls, 4000);
                });
            });
            modes.addView(button, lp);
        }
        card.addView(modes);
        nativeVpnControls.addView(card, new LinearLayout.LayoutParams(-1, -2));
    }

    private void syncNativeVpnControls() {
        if (webView == null || nativeVpnSwitch == null || nativeVpnState == null || !webUiReady) return;
        webView.evaluateJavascript("(function(){var p=window.PGB&&PGB.model&&PGB.model.sw||{};var m=String(p.vpn_mode||'direct');return JSON.stringify({mode:m,liveKnown:window.__pgVpnLiveKnown===true,liveOn:window.__pgVpnLiveOn===true,node:String(p.vpn_node||'')})})()", value -> {
            if (isFinishing() || value == null) return;
            try {
                Object decoded = org.json.JSONTokener.stringToValue(value);
                if (!(decoded instanceof String)) return;
                org.json.JSONObject state = new org.json.JSONObject((String) decoded);
                String mode = state.optString("mode", "direct");
                boolean configured = !"direct".equals(mode);
                boolean liveKnown = state.optBoolean("liveKnown", false);
                boolean liveOn = state.optBoolean("liveOn", false);
                syncingNativeVpn = true;
                nativeVpnSwitch.setChecked(configured && liveKnown && liveOn);
                syncingNativeVpn = false;
                String modeLabel = "direct".equals(mode) ? "直连" : "global".equals(mode) ? "全局" : "rule".equals(mode) ? "规则" : "tun".equals(mode) ? "TUN" : mode;
                String live = !configured ? "直连：未接管流量"
                        : !liveKnown ? "代理模式已保存，等待后端确认"
                        : liveOn ? "后端确认：代理正在运行" : "代理模式已选择，但后端未运行";
                String node = state.optString("node", "");
                nativeVpnState.setText("模式：" + modeLabel + " · " + live + (node.isEmpty() ? " · 尚未选择节点" : " · 节点已配置"));
            } catch (Exception ignored) {
                syncingNativeVpn = false;
                nativeVpnState.setText("VPN 状态读取失败；未将配置状态冒充为运行状态");
            }
        });
    }

    private void pauseAndDetachWebView() {
        stopNativeVpnPolling();
        if (webView == null) return;
        webView.onPause();
        webView.pauseTimers();
        ViewParent parent = webView.getParent();
        if (parent instanceof ViewGroup) ((ViewGroup) parent).removeView(webView);
    }

    private void mountNativeShell(View pageContent) {
        androidx.compose.ui.platform.ComposeView shell =
                new androidx.compose.ui.platform.ComposeView(this);
        // ComposeView is created and composed before setContentView attaches it.
        // Explicitly propagate this ComponentActivity's owners so Compose can
        // create a lifecycle-aware WindowRecomposer on all supported ROMs.
        androidx.lifecycle.ViewTreeLifecycleOwner.set(shell, this);
        androidx.lifecycle.ViewTreeViewModelStoreOwner.set(shell, this);
        androidx.savedstate.ViewTreeSavedStateRegistryOwner.set(shell, this);
        FxNativeAppShellKt.installFxNativeAppShell(
                shell, pageContent, selectedBottomTab, uiMode,
                index -> {
                    handleNativeTabSelection(index);
                    return kotlin.Unit.INSTANCE;
                });
        setContentView(shell);
    }

    private void handleNativeTabSelection(int index) {
        if (index == 5) {
            selectedBottomTab = 5;
            showSettings();
        } else if (index == 4) {
            selectedBottomTab = 4;
            showAppList();
        } else if (index >= 0 && index <= 3) {
            selectedBottomTab = index;
            lastWebTabIndex = index;
            if (nativeVpnControls != null) nativeVpnControls.setVisibility(index == 0 ? View.VISIBLE : View.GONE);
            if (index == 0) syncNativeVpnControls();
            String page = new String[]{"pageVpn", "pageHosts", "pagePrivacy", "pageScript"}[index];
            if (hookUiVisible || settingsUiVisible) showWebDashboard();
            navigateWebPage(page);
        }
    }

    private void styleBottomItem(TextView item, int index) {
        boolean selected = index == selectedBottomTab;
        int accent = "glass".equals(uiMode) ? 0xff276b9a : "miuix".equals(uiMode) ? 0xff3478f6 : 0xff1769aa;
        item.setTextColor(selected ? accent : 0xff526170);
        item.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
    }

    private void navigateWebPage(String pageId) {
        if (webView == null) return;
        if (!webUiReady) {
            pendingWebPage = pageId;
            // A failed first load must be retryable from the native tab bar.
            if (!webViewLoaded) {
                webViewLoaded = true;
                webView.loadUrl("https://appassets.androidplatform.net/assets/webroot/index.html");
            }
            return;
        }
        String tab;
        switch (pageId) {
            case "pageVpn": tab = "vpn"; break;
            case "pageHosts": tab = "hosts"; break;
            case "pageAd": tab = "ad"; break; // compatibility with older bundled WebUI builds
            case "pagePrivacy": tab = "privacy"; break;
            case "pageScript": tab = "script"; break;
            case "pageMore": tab = "more"; break;
            default: return;
        }
        String script = "(function(){"
                + "var id=" + JSONObject.quote(pageId) + ";"
                + "var page=document.getElementById(id);"
                + "if(id==='pageHosts'&&!page){id='pageAd';page=document.getElementById(id);}"
                + "if(!page||!page.children.length)return false;"
                + "var navTab='" + (tab.equals("hosts") ? "ad" : tab) + "';"
                + "var names=id==='pageHosts'?['ad','hosts']:(id==='pageAd'?['ad']:['" + tab + "']);"
                + "var b=null;for(var i=0;i<names.length&&!b;i++){"
                + "b=document.querySelector('.nav-item[data-tab='+JSON.stringify(names[i])+']');}"
                + "if(b)b.click();"
                + "var pages=document.querySelectorAll('#screen .page');"
                + "for(var p=0;p<pages.length;p++)pages[p].classList.remove('on');"
                + "page.classList.add('on');page.scrollTop=0;"
                + "var navItems=document.querySelectorAll('#screen .nav-item');"
                + "for(var n=0;n<navItems.length;n++){"
                + "navItems[n].classList.toggle('on',navItems[n].getAttribute('data-tab')===navTab);}"
                + "window.currentTab=navTab;"
                + "var title=document.getElementById('pageTitle');"
                + "var lang=window.lang==='en'?'en':'zh';"
                + "var labels={zh:{vpn:'VPN',ad:'广告',privacy:'隐私',script:'脚本'},en:{vpn:'VPN',ad:'Ad',privacy:'Privacy',script:'Scripts'}};"
                + "if(title)title.textContent=labels[lang][navTab]||navTab;"
                + "window.dispatchEvent(new Event('resize'));"
                + "return page.classList.contains('on')&&getComputedStyle(page).display!=='none';"
                + "})()";
        webView.evaluateJavascript(script, value -> {
            if (value == null || "false".equals(value) || "null".equals(value)) {
                Toast.makeText(MainActivity.this,
                        "该功能页面未能加载，请检查内置 WebUI 页面资源。",
                        Toast.LENGTH_LONG).show();
            }
        });
    }

    private void showHookHub() {
        cancelAppIconLoad();
        // Do not resurrect a stale target if the user leaves the restored app list.
        pendingRestorePackage = null;
        pauseAndDetachWebView();
        hookUiVisible = true;
        settingsUiVisible = false;
        selectedBottomTab = 4;
        hookTargetVisible = false;
        hookHubVisible = true;
        base("Hook 与系统授权");
        TextView intro = new TextView(this);
        intro.setText("统一管理应用级 Hook、LSPosed 作用域和无障碍服务。Root、LSPosed、无障碍是三种独立授权，必须分别确认状态。");
        intro.setPadding(dp(18), dp(8), dp(18), dp(16));
        intro.setTextColor(0xff536170);
        content.addView(intro);
        section("最近一次配置发布");
        android.content.SharedPreferences publishState =
                getSharedPreferences("fx_hook_publish", MODE_PRIVATE);
        String lastHash = publishState.getString("sha256", "");
        long lastPublishedAt = publishState.getLong("published_at", 0L);
        TextView publishStatus = new TextView(this);
        publishStatus.setPadding(dp(18), dp(10), dp(18), dp(12));
        if (lastHash.isEmpty() || lastPublishedAt <= 0L) {
            publishStatus.setText("尚无成功发布记录。保存配置后，这里会显示设备端写入校验结果；该记录不代表 LSPosed 已启用或目标进程已注入。");
        } else {
            java.text.DateFormat dateFormat = java.text.DateFormat.getDateTimeInstance(
                    java.text.DateFormat.MEDIUM, java.text.DateFormat.MEDIUM);
            publishStatus.setText("设备端写入成功（" + dateFormat.format(new java.util.Date(lastPublishedAt))
                    + "）\nSHA-256：" + lastHash
                    + "\nRemote Files：" + publishState.getString("remote_path", "未知")
                    + "\n此记录只证明文件写入与哈希校验成功，不证明 LSPosed 作用域、热加载或目标进程注入状态。");
        }
        content.addView(publishStatus);
        section("LSPosed Remote Files 实时状态");
        TextView remoteStatus = new TextView(this);
        remoteStatus.setText("正在读取设备端 Remote Files 状态…");
        remoteStatus.setPadding(dp(18), dp(10), dp(18), dp(12));
        content.addView(remoteStatus);
        Button refreshRemote = new Button(this);
        refreshRemote.setText("刷新 Remote Files 状态");
        refreshRemote.setOnClickListener(v -> refreshHookRemoteStatus(remoteStatus));
        content.addView(refreshRemote);
        refreshHookRemoteStatus(remoteStatus);
        section("KernelSU / Root");
        TextView rootState = new TextView(this);
        rootState.setText("正在检查 Root 授权与 FX 模块状态…");
        rootState.setPadding(dp(18), dp(12), dp(18), dp(12));
        content.addView(rootState);
        Button refreshRoot = new Button(this);
        refreshRoot.setText("刷新 Root 状态");
        refreshRoot.setOnClickListener(v -> checkRoot(rootState, false));
        content.addView(refreshRoot);
        Button requestRoot = new Button(this);
        requestRoot.setText("申请 / 重新检查 Root 权限");
        requestRoot.setOnClickListener(v -> checkRoot(rootState, true));
        content.addView(requestRoot);
        checkRoot(rootState, false);
        section("LSPosed");
        TextView ls = new TextView(this);
        ls.setText(isLsposedManagerInstalled()
                ? "已检测到 LSPosed Manager。注意：这只证明管理器已安装；框架是否运行、FX 模块是否启用、目标应用作用域及进程注入状态均无法由 FX 独立可靠读取，当前均标记为“未知”，请在 Manager 中逐项确认。"
                : "未检测到 LSPosed Manager。框架运行状态、FX 模块启用状态、目标应用作用域及进程注入状态均为未知；请先安装并配置兼容的 LSPosed 框架。");
        ls.setPadding(dp(18), dp(12), dp(18), dp(12));
        content.addView(ls);
        Button manager = new Button(this);
        manager.setText("打开 LSPosed Manager");
        manager.setOnClickListener(v -> openLsposedManager());
        content.addView(manager);
        Button targets = new Button(this);
        targets.setText("应用 Hook 配置");
        targets.setOnClickListener(v -> showAppList());
        content.addView(targets);
        section("Android 无障碍");
        TextView accessibility = new TextView(this);
        boolean accessibilityEnabled = isAccessibilityEnabled();
        android.content.SharedPreferences accessibilityPrefs =
                getSharedPreferences("fx_accessibility", MODE_PRIVATE);
        boolean accessibilityConnected = FxAccessibilityService.isConnected()
                && accessibilityPrefs.getBoolean("service_connected", false)
                && accessibilityPrefs.getInt("service_pid", -1) == android.os.Process.myPid();
        accessibility.setText(!accessibilityEnabled
                ? "无障碍服务：未启用（需由用户在系统设置中手动开启）"
                : accessibilityConnected ? "无障碍服务：系统已启用，FX 服务已连接"
                : "无障碍服务：系统已启用，等待 FX 服务连接");
        accessibility.setPadding(dp(18), dp(12), dp(18), dp(12));
        content.addView(accessibility);
        Button settings = new Button(this);
        settings.setText("打开无障碍设置");
        settings.setOnClickListener(v -> {
            try { startActivity(new Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)); }
            catch (Exception e) { Toast.makeText(this, "无法打开系统无障碍设置", Toast.LENGTH_LONG).show(); }
        });
        content.addView(settings);
        Button status = new Button(this);
        status.setText("刷新无障碍 / LSPosed 检测");
        status.setOnClickListener(v -> showHookHub());
        content.addView(status);
        Button back = new Button(this);
        back.setText("返回 FX 控制中心");
        back.setOnClickListener(v -> showWebDashboard());
        content.addView(back);
    }

    private void addModeOption(RadioGroup group, int id, String title, String detail) {
        RadioButton option = new RadioButton(this);
        option.setId(id);
        option.setText(title + "\n" + detail);
        option.setTextSize(15);
        option.setPadding(dp(14), dp(10), dp(14), dp(10));
        option.setMinHeight(dp(64));
        option.setBackground(uiPanelDrawable());
        group.addView(option, new RadioGroup.LayoutParams(-1, -2));
    }

    private void showSettings() {
        cancelHookStatusRefresh();
        cancelAppIconLoad();
        pauseAndDetachWebView();
        hookUiVisible = false;
        hookTargetVisible = false;
        hookHubVisible = false;
        settingsUiVisible = true;
        selectedBottomTab = 5;
        base("设置");
        TextView intro = new TextView(this);
        intro.setText("管理 FX Hook 的界面外观。模式会保存到本机，重新打开后继续生效；Hook 配置、VPN 和规则数据不会因切换界面而改变。");
        intro.setTextColor(0xff66727e);
        intro.setPadding(dp(18), dp(4), dp(18), dp(14));
        content.addView(intro);
        section("界面模式");
        TextView note = new TextView(this);
        note.setText("以下模式选择器由 Kotlin + Jetpack Compose 原生渲染。Miuix 使用官方 Miuix 组件；Liquid Glass 使用 Kyant Backdrop 的背景采样、模糊与 Lens 效果。当前先迁移设置中的模式选择器，其他页面将按模块逐步迁移；Web 管理内容仍是独立 WebView。");
        note.setTextColor(0xff66727e);
        note.setPadding(dp(18), dp(4), dp(18), dp(8));
        content.addView(note);
        androidx.compose.ui.platform.ComposeView designModePanel =
                new androidx.compose.ui.platform.ComposeView(this);
        // This ComposeView is a sibling of the main shell, not its descendant.
        // Bind all three owners before setContent() so the settings panel can
        // create a lifecycle-aware recomposer and resolve saved state/ViewModels.
        androidx.lifecycle.ViewTreeLifecycleOwner.set(designModePanel, this);
        androidx.lifecycle.ViewTreeViewModelStoreOwner.set(designModePanel, this);
        androidx.savedstate.ViewTreeSavedStateRegistryOwner.set(designModePanel, this);
        FxDesignModePanelKt.installFxDesignModePanel(designModePanel, uiMode, selected -> {
            if (selected == null || selected.equals(uiMode)) return kotlin.Unit.INSTANCE;
            uiMode = selected;
            getSharedPreferences("fx_ui", MODE_PRIVATE).edit()
                    .putString("mode", uiMode).apply();
            applyWebUiMode();
            Toast.makeText(MainActivity.this, "界面模式已切换", Toast.LENGTH_SHORT).show();
            showSettings();
            return kotlin.Unit.INSTANCE;
        });
        content.addView(designModePanel,
                new LinearLayout.LayoutParams(-1, dp(360)));
        section("其他设置");
        TextView legacyHint = new TextView(this);
        legacyHint.setText("VPN、Hosts、隐私、脚本及证书等完整管理选项仍保留在原有设置页面。");
        legacyHint.setTextColor(0xff66727e);
        legacyHint.setPadding(dp(18), dp(4), dp(18), dp(8));
        content.addView(legacyHint);
        Button fullSettings = new Button(this);
        fullSettings.setText("打开完整设置页面");
        fullSettings.setOnClickListener(v -> {
            lastWebTabIndex = 5;
            showWebDashboard();
            navigateWebPage("pageMore");
        });
        content.addView(fullSettings);
    }

    private void refreshHookRemoteStatus(TextView target) {
        Thread previous = hookStatusThread;
        if (previous != null) previous.interrupt();
        final int generation = ++hookStatusGeneration;
        target.setText("正在读取设备端 Remote Files 状态…");
        Thread worker = new Thread(() -> {
            RootAccess.Result result = RootAccess.execute(
                    "sh /data/adb/modules/privacyguard/scripts/status.sh json",
                    30000L, 64 * 1024);
            String display;
            if (result.exitCode != 0) {
                String detail = result.output == null ? "" : result.output.trim();
                if (detail.length() > 500) detail = detail.substring(0, 500) + "…";
                display = "Remote Files 状态读取失败（退出码 " + result.exitCode + "）。"
                        + (detail.isEmpty() ? "" : "\n" + detail);
            } else {
                try {
                    JSONObject status = new JSONObject(result.output.trim());
                    String remote = status.optString("hook_remote_status", "unknown");
                    String remoteLabel;
                    if ("ok".equals(remote)) remoteLabel = "最近一次发布成功";
                    else if ("failed".equals(remote)) remoteLabel = "最近一次发布失败";
                    else if ("framework_missing".equals(remote)) remoteLabel = "未检测到 LSPosed 框架";
                    else remoteLabel = "未知 / 尚无状态文件";
                    if (!"1".equals(status.optString("hook_native_config_found", "0"))) {
                        display = "Remote Files：" + remoteLabel
                                + "（目标数 " + status.optInt("hook_remote_targets", 0) + "）"
                                + "\n未找到原生 FX Hook 配置文件；请先保存并发布配置。"
                                + "\n此状态不证明 LSPosed 作用域或目标进程已注入。";
                    } else {
                        display = "Remote Files：" + remoteLabel
                                + "（目标数 " + status.optInt("hook_remote_targets", 0) + "）"
                                + " · 原生配置用户数 " + status.optInt("hook_native_config_users", 0)
                                + " · 原生目标数 " + status.optInt("hook_native_targets", 0)
                                + "\n通知权限提示：主开关 " + status.optString("hook_native_notification_permission_hide_enabled", "未知")
                                + "，目标数 " + status.optInt("hook_native_notification_permission_hide_targets", 0)
                                + "\n通知监听阻止：主开关 " + status.optString("hook_native_notification_listen_enabled", "未知")
                                + "，目标数 " + status.optInt("hook_native_notification_listen_targets", 0)
                                + "\n剪贴板隔离：主开关 " + status.optString("hook_native_clipboard_isolate_enabled", "未知")
                                + "，目标数 " + status.optInt("hook_native_clipboard_isolate_targets", 0)
                                + "\n会员只读诊断：启用 " + status.optString("hook_native_member_diag_enabled", "未知")
                                + "，目标数 " + status.optInt("hook_native_member_diag_targets", 0)
                                + "\n隐私 Hook：主开关 " + status.optString("hook_native_privacy_enabled", "未知")
                                + "，目标数 " + status.optInt("hook_native_privacy_targets", 0)
                                + "\nWi-Fi 扫描限制：主开关 " + status.optString("hook_native_wifi_scan_enabled", "未知")
                                + "，目标数 " + status.optInt("hook_native_wifi_scan_targets", 0)
                                + "\n此状态仅反映设备端原生配置和发布状态；不证明 LSPosed 作用域或目标进程已注入。";
                    }
                } catch (Exception malformed) {
                    // Older module revisions print key/value text instead of JSON.
                    // Show the bounded raw status rather than falsely reporting that
                    // the device-side command failed.
                    String raw = result.output == null ? "" : result.output.trim();
                    if (raw.length() > 4000) raw = raw.substring(0, 4000) + "\n…（内容已截断）";
                    display = raw.isEmpty()
                            ? "设备端状态脚本没有返回可显示的状态。"
                            : "设备端状态输出（原始格式）：\n" + raw;
                }
            }
            final String message = display;
            if (hookStatusThread == Thread.currentThread()) hookStatusThread = null;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed() || generation != hookStatusGeneration
                        || !hookUiVisible || !hookHubVisible) return;
                target.setText(message);
            });
        }, "fx-hook-remote-status");
        worker.setDaemon(true);
        hookStatusThread = worker;
        worker.start();
    }

    private void cancelHookStatusRefresh() {
        hookStatusGeneration++;
        Thread worker = hookStatusThread;
        hookStatusThread = null;
        if (worker != null) worker.interrupt();
    }

    private boolean isLsposedManagerInstalled() {
        try {
            getPackageManager().getPackageInfo("org.lsposed.manager", 0);
            return true;
        } catch (Exception ignored) {
            return false;
        }
    }

    private void openLsposedManager() {
        try {
            Intent launch = getPackageManager().getLaunchIntentForPackage("org.lsposed.manager");
            if (launch != null) startActivity(launch);
            else Toast.makeText(this, "未找到 LSPosed Manager，请确认已安装", Toast.LENGTH_LONG).show();
        } catch (Exception e) {
            Toast.makeText(this, "打开 LSPosed Manager 失败：" + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private boolean isAccessibilityEnabled() {
        String enabled = android.provider.Settings.Secure.getString(
                getContentResolver(), android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        return enabled != null && (enabled.contains(getPackageName() + "/.FxAccessibilityService")
                || enabled.contains(getPackageName() + "/" + getPackageName() + ".FxAccessibilityService"));
    }

    @Override protected void onDestroy() {
        cancelHookStatusRefresh();
        cancelAppIconLoad();
        Thread publisher = hookPublisherThread;
        hookPublisherThread = null;
        if (publisher != null) publisher.interrupt();
        Thread appLoader = appLoaderThread;
        appLoaderThread = null;
        appLoadGeneration++;
        if (appLoader != null) appLoader.interrupt();

        // Complete pending WebView callbacks before tearing down the view. Otherwise
        // a cancelled document picker can retain the old Activity across recreation.
        ValueCallback<Uri[]> pendingFileChooser = fileChooserCallback;
        fileChooserCallback = null;
        deliverFileChooserResult(pendingFileChooser, null);
        if (rootBridge != null) {
            rootBridge.close();
            rootBridge = null;
        }
        if (webView != null) {
            webView.stopLoading();
            ViewParent parent = webView.getParent();
            if (parent instanceof ViewGroup) ((ViewGroup) parent).removeView(webView);
            webView.removeJavascriptInterface("FXRoot");
            webView.setWebChromeClient(null);
            webView.setWebViewClient(null);
            webView.destroy();
            webView = null;
        }
        webViewLoaded = false;
        webUiReady = false;
        pendingWebPage = null;
        super.onDestroy();
    }

    @Override protected void onPause() {
        if (webView != null) {
            webView.onPause();
            webView.pauseTimers();
        }
        super.onPause();
    }

    @Override protected void onResume() {
        super.onResume();
        if (webView != null && !hookUiVisible) {
            webView.onResume();
            webView.resumeTimers();
        }
    }

    private static void deliverFileChooserResult(ValueCallback<Uri[]> callback, Uri[] result) {
        if (callback == null) return;
        try {
            callback.onReceiveValue(result);
        } catch (RuntimeException ignored) {
            // A stale WebView callback must never abort Activity cleanup or navigation.
        }
    }

    @Override protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_FILE_PICKER && fileChooserCallback != null) {
            ValueCallback<Uri[]> pending = fileChooserCallback;
            fileChooserCallback = null;
            Uri[] results = null;
            try {
                results = WebChromeClient.FileChooserParams.parseResult(resultCode, data);
            } catch (RuntimeException malformedResult) {
                // Always complete the accepted WebView callback, even if the picker
                // returns a malformed result or the provider disappears.
            }
            deliverFileChooserResult(pending, results);
        }
    }

    @Override public void onBackPressed() {
        if (hookTargetVisible) { showAppList(); return; }
        if (settingsUiVisible) { showDashboard(); return; }
        if (hookUiVisible && !hookHubVisible) { showHookHub(); return; }
        if (hookHubVisible) { showWebDashboard(); return; }
        if (webView != null && webView.canGoBack()) { webView.goBack(); return; }
        super.onBackPressed();
    }

    public void showAppListFromBridge() { showAppList(); }

    private void checkRoot(TextView state, boolean request) {
        checkRoot(state, request, null);
    }

    private void checkRoot(TextView state, boolean request, Runnable afterCheck) {
        state.setText(request ? "正在请求 KernelSU 授权…" : "正在检查 Root…");
        new Thread(() -> {
            RootAccess.Result result = RootAccess.execute("id -u; if [ -s /data/adb/modules/privacyguard/module.prop ] && grep -qx 'version=1.0.0' /data/adb/modules/privacyguard/module.prop; then if [ -e /data/adb/modules/privacyguard/disable ]; then echo FX_MODULE=disabled; elif [ -e /data/adb/modules/privacyguard/remove ]; then echo FX_MODULE=remove-pending; else echo FX_MODULE=enabled; fi; else echo FX_MODULE=missing; fi; (command -v ksud >/dev/null 2>&1 || test -x /data/adb/ksu/bin/ksud) && echo KSU_TOOL=present || echo KSU_TOOL=not-found");
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                if (result.exitCode == 0 && result.output.trim().startsWith("0")) {
                    String moduleState = result.output.contains("FX_MODULE=enabled") ? "模块启用标记存在"
                            : result.output.contains("FX_MODULE=disabled") ? "模块已禁用"
                            : result.output.contains("FX_MODULE=remove-pending") ? "模块待卸载"
                            : "模块缺失/版本不符";
                    state.setText("Root UID 0 · FX " + moduleState + " · KSU 工具 "
                            + (result.output.contains("KSU_TOOL=present") ? "存在" : "未检测到"));
                } else if (result.denied) {
                    state.setText("尚未获得 Root 授权。请在 KernelSU 管理器中允许 FX 应用。");
                } else {
                    state.setText("Root 不可用或请求失败：\\n" + result.output);
                }
                if (afterCheck != null) afterCheck.run();
            });
        }, "fx-root-check").start();
    }

    private String normalizeUiMode(String mode) {
        if ("miuix".equals(mode) || "glass".equals(mode) || "web".equals(mode)
                || "classic".equals(mode)) return mode;
        return "classic";
    }

    private int dp(float v) { return (int)(v * getResources().getDisplayMetrics().density + .5f); }
    private int uiBackgroundColor() {
        if ("miuix".equals(uiMode)) return 0xfff3f5fa;
        if ("glass".equals(uiMode)) return 0xffe8eef4;
        return 0xfff4f6f8;
    }
    private int uiSurfaceColor() {
        if ("miuix".equals(uiMode)) return 0xffeaf0fb;
        if ("glass".equals(uiMode)) return 0xddefffff;
        return 0xffffffff;
    }
    private GradientDrawable roundedDrawable(int color, int strokeColor) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(color);
        d.setCornerRadius(dp("glass".equals(uiMode) ? 24 : "miuix".equals(uiMode) ? 20 : 8));
        if (strokeColor != 0) d.setStroke(dp(1), strokeColor);
        return d;
    }
    private android.graphics.drawable.Drawable uiPanelDrawable() {
        return roundedDrawable(uiSurfaceColor(), "glass".equals(uiMode) ? 0x66ffffff : 0);
    }
    private void applyWebUiMode() {
        if (webView == null || !webUiReady) return;
        // Only the explicit legacy mode styles the WebView. Miuix and Liquid Glass
        // are native Compose renderers; do not imitate either with injected CSS.
        String css = "classic".equals(uiMode)
                ? "body{background:#f4f6f8!important;color:#17212b!important}" +
                  ".card,.panel,.setting-card,.section,.list-item,.config-card{border-radius:8px!important;box-shadow:none!important}" +
                  "button,.btn,input,select,textarea{border-radius:6px!important}"
                : "";
        String js = "(function(){var id='fx-interface-mode-style';var old=document.getElementById(id);if(old)old.remove();" +
                (css.isEmpty() ? "" : "var s=document.createElement('style');s.id=id;s.textContent=" + JSONObject.quote(css) + ";document.head.appendChild(s);") + "})()";
        webView.evaluateJavascript(js, null);
    }
    private TextView title(String value, int size) {
        TextView t = new TextView(this); t.setText(value); t.setTextSize(size);
        t.setTypeface(Typeface.DEFAULT, Typeface.BOLD); t.setTextColor("glass".equals(uiMode) ? 0xff24394c : "miuix".equals(uiMode) ? 0xff202b3c : 0xff17212b);
        t.setPadding(dp(18), dp(14), dp(18), dp(10)); return t;
    }
    private void base(String heading) {
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(uiBackgroundColor());
        ScrollView scroll = new ScrollView(this);
        scroll.setClipToPadding(false);
        scroll.setPadding(0, 0, 0, dp(76));
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.addView(title("FX", 25));
        TextView h = title(heading, 18);
        h.setPadding(dp(18), dp(2), dp(18), dp(12));
        content.addView(h);
        scroll.addView(content);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, -1));
        this.content = content;
        mountNativeShell(root);
    }
    private LinearLayout content;
    private void showAppList() {
        cancelHookStatusRefresh();
        cancelAppIconLoad();
        pauseAndDetachWebView();
        hookUiVisible = true;
        settingsUiVisible = false;
        hookTargetVisible = false;
        hookHubVisible = false;
        selectedPackage = null; selectedBottomTab = 4; base("选择应用");
        Button home = new Button(this); home.setText("授权状态与系统设置"); home.setOnClickListener(v -> showHookHub()); content.addView(home);
        search = new EditText(this); search.setSingleLine(true); search.setHint("搜索应用名称或包名");
        search.setPadding(dp(16), dp(10), dp(16), dp(10));
        content.addView(search, new LinearLayout.LayoutParams(-1, -2));
        TextView hint = new TextView(this); hint.setText("点击应用进入独立 Hook 配置"); hint.setTextColor(0xff66727e);
        hint.setPadding(dp(18), dp(8), dp(18), dp(8)); content.addView(hint);
        TextView loading = new TextView(this);
        loading.setText("正在后台读取已安装应用…");
        loading.setPadding(dp(18), dp(20), dp(18), dp(20));
        content.addView(loading);
        appsLoaded = false;
        search.addTextChangedListener(new TextWatcher() {
            public void beforeTextChanged(CharSequence s,int st,int c,int a) {}
            public void onTextChanged(CharSequence s,int st,int before,int count) {
                if (appsLoaded) renderApps(s.toString());
            }
            public void afterTextChanged(Editable e) {}
        });
        loadAppsAsync();
    }
    private void loadAppsAsync() {
        Thread previous = appLoaderThread;
        if (previous != null) previous.interrupt();
        final int generation = ++appLoadGeneration;
        Thread loader = new Thread(() -> {
            List<ApplicationInfo> loadedApps = new ArrayList<>();
            Map<String, String> loadedLabels = new HashMap<>();
            String failure = null;
            try {
                PackageManager pm = getPackageManager();
                for (ApplicationInfo ai : pm.getInstalledApplications(PackageManager.GET_META_DATA)) {
                    if (Thread.currentThread().isInterrupted()) return;
                    if ((ai.flags & ApplicationInfo.FLAG_SYSTEM) != 0
                            && ai.packageName.startsWith("com.android.")) continue;
                    if (ai.packageName.equals(getPackageName()) || ai.packageName.equals("android")) continue;
                    loadedApps.add(ai);
                    try {
                        CharSequence label = pm.getApplicationLabel(ai);
                        loadedLabels.put(ai.packageName, label == null ? ai.packageName : label.toString());
                    } catch (RuntimeException unavailable) {
                        // A package may disappear while the PackageManager snapshot is being read.
                        loadedLabels.put(ai.packageName, ai.packageName);
                    }
                }
                Collections.sort(loadedApps, new Comparator<ApplicationInfo>() {
                    public int compare(ApplicationInfo a, ApplicationInfo b) {
                        return loadedLabels.get(a.packageName)
                                .compareToIgnoreCase(loadedLabels.get(b.packageName));
                    }
                });
            } catch (RuntimeException error) {
                failure = error.getClass().getSimpleName() + ": " + error.getMessage();
            }
            final String loadFailure = failure;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed() || generation != appLoadGeneration
                        || !hookUiVisible || hookHubVisible || hookTargetVisible) return;
                appLoaderThread = null;
                apps.clear();
                apps.addAll(loadedApps);
                appLabels.clear();
                appLabels.putAll(loadedLabels);
                appIcons.clear();
                appsLoaded = loadFailure == null;
                while (content.getChildCount() > 5) content.removeViewAt(5);
                if (loadFailure != null) {
                    TextView error = new TextView(this);
                    error.setText("读取应用列表失败：" + loadFailure + "\n请检查应用列表权限后重试。");
                    error.setPadding(dp(18), dp(20), dp(18), dp(20));
                    content.addView(error);
                    Button retry = new Button(this);
                    retry.setText("重新读取应用列表");
                    retry.setOnClickListener(v -> loadAppsAsync());
                    content.addView(retry);
                } else {
                    renderApps(search == null ? "" : search.getText().toString());
                    if (pendingRestorePackage != null) {
                        String restorePackage = pendingRestorePackage;
                        pendingRestorePackage = null;
                        ApplicationInfo target = findApp(restorePackage);
                        if (target != null) showTarget(target);
                        else Toast.makeText(MainActivity.this,
                                "上次配置的应用已卸载，已返回应用列表。", Toast.LENGTH_LONG).show();
                    }
                }
            });
        }, "fx-app-index");
        appLoaderThread = loader;
        loader.start();
    }
    private void renderApps(String query) {
        if (!appsLoaded) return;
        cancelAppIconLoad();
        // Keep the fixed header, search field, and hint (children 0..4).
        // Replace only the loading indicator and previously rendered result rows.
        while (content.getChildCount() > 5) content.removeViewAt(5);
        filtered.clear();
        String q = query == null ? "" : query.trim().toLowerCase(Locale.ROOT);
        for (ApplicationInfo ai : apps) {
            String label = appLabels.get(ai.packageName);
            if (label == null) label = ai.packageName;
            if (label.toLowerCase(Locale.ROOT).contains(q)
                    || ai.packageName.toLowerCase(Locale.ROOT).contains(q)) filtered.add(ai);
        }
        if (filtered.isEmpty()) {
            TextView empty = new TextView(this);
            empty.setText("没有匹配的应用");
            empty.setPadding(dp(18), dp(20), dp(18), dp(20));
            content.addView(empty);
            return;
        }
        appendAppRows(0, Math.min(MAX_APP_ROWS_PER_PAGE, filtered.size()));
    }

    private void appendAppRows(int start, int end) {
        for (int i = start; i < end; i++) {
            ApplicationInfo ai = filtered.get(i);
            LinearLayout row = new LinearLayout(this);
            row.setGravity(Gravity.CENTER_VERTICAL);
            row.setPadding(dp(16), dp(10), dp(16), dp(10));
            row.setBackgroundColor(0xffffffff);
            ImageView icon = new ImageView(this);
            Drawable drawable = appIcons.get(ai.packageName);
            if (drawable != null) {
                icon.setImageDrawable(drawable);
                icon.setTag(Boolean.TRUE);
            } else {
                icon.setImageResource(android.R.drawable.sym_def_app_icon);
                icon.setTag(Boolean.FALSE);
            }
            appIconViews.put(ai.packageName, icon);
            row.addView(icon, new LinearLayout.LayoutParams(dp(42), dp(42)));
            LinearLayout labels = new LinearLayout(this);
            labels.setOrientation(LinearLayout.VERTICAL);
            labels.setPadding(dp(12), 0, 0, 0);
            TextView name = new TextView(this);
            name.setText(appLabels.containsKey(ai.packageName)
                    ? appLabels.get(ai.packageName) : ai.packageName);
            name.setTextSize(16);
            name.setTextColor(0xff17212b);
            TextView pkg = new TextView(this);
            pkg.setText(ai.packageName);
            pkg.setTextSize(11);
            pkg.setTextColor(0xff75808a);
            labels.addView(name);
            labels.addView(pkg);
            row.addView(labels, new LinearLayout.LayoutParams(0, -2, 1));
            TextView arrow = new TextView(this);
            arrow.setText("›");
            arrow.setTextSize(28);
            arrow.setTextColor(0xff637080);
            row.addView(arrow);
            row.setOnClickListener(v -> showTarget(ai));
            content.addView(row, new LinearLayout.LayoutParams(-1, -2));
            View divider = new View(this);
            divider.setBackgroundColor(0xffe8ebee);
            content.addView(divider, new LinearLayout.LayoutParams(-1, dp(1)));
        }
        if (end < filtered.size()) {
            Button more = new Button(this);
            more.setText("加载更多应用（" + (filtered.size() - end) + "）");
            more.setOnClickListener(v -> {
                int nextEnd = Math.min(end + MAX_APP_ROWS_PER_PAGE, filtered.size());
                int oldCount = content.getChildCount();
                // Remove the previous pagination control before appending the next page.
                if (oldCount > 4 && content.getChildAt(oldCount - 1) == more) {
                    content.removeViewAt(oldCount - 1);
                }
                appendAppRows(end, nextEnd);
            });
            content.addView(more, new LinearLayout.LayoutParams(-1, -2));
        }
        loadMissingAppIconsAsync();
    }

    private void loadMissingAppIconsAsync() {
        List<ApplicationInfo> missing = new ArrayList<>();
        for (ApplicationInfo ai : apps) {
            ImageView view = appIconViews.get(ai.packageName);
            if (view != null && !Boolean.TRUE.equals(view.getTag())
                    && !appIcons.containsKey(ai.packageName)) missing.add(ai);
        }
        if (missing.isEmpty()) return;
        Thread previous = appIconLoaderThread;
        if (previous != null) previous.interrupt();
        final int generation = ++appIconLoadGeneration;
        Thread worker = new Thread(() -> {
            Map<String, Drawable> loaded = new LinkedHashMap<>();
            PackageManager pm = getPackageManager();
            for (ApplicationInfo ai : missing) {
                if (Thread.currentThread().isInterrupted()) return;
                try {
                    Drawable drawable = pm.getApplicationIcon(ai);
                    if (drawable != null) loaded.put(ai.packageName, drawable);
                } catch (RuntimeException unavailable) {
                    // The package may be removed while icons are being decoded.
                }
            }
            if (Thread.currentThread().isInterrupted()) return;
            if (appIconLoaderThread == Thread.currentThread()) appIconLoaderThread = null;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed() || generation != appIconLoadGeneration
                        || !hookUiVisible || hookTargetVisible || hookHubVisible) return;
                for (Map.Entry<String, Drawable> entry : loaded.entrySet()) {
                    appIcons.put(entry.getKey(), entry.getValue());
                    ImageView target = appIconViews.get(entry.getKey());
                    if (target != null && target.getParent() != null) {
                        target.setImageDrawable(entry.getValue());
                        target.setTag(Boolean.TRUE);
                    }
                }
            });
        }, "fx-app-icons");
        worker.setDaemon(true);
        appIconLoaderThread = worker;
        worker.start();
    }

    private void cancelAppIconLoad() {
        appIconLoadGeneration++;
        Thread worker = appIconLoaderThread;
        appIconLoaderThread = null;
        if (worker != null) worker.interrupt();
        appIconViews.clear();
    }

    private String key(String feature) { return selectedPackage + ":" + feature; }
    private boolean get(String feature) { return getPreferences(0).getBoolean(key(feature), false); }
    private void showTarget(ApplicationInfo ai) {
        cancelAppIconLoad();
        try {
            // The package may have been uninstalled after the background app index was built.
            ai = getPackageManager().getApplicationInfo(ai.packageName, 0);
        } catch (PackageManager.NameNotFoundException removed) {
            Toast.makeText(this, "该应用已卸载，正在刷新应用列表。", Toast.LENGTH_LONG).show();
            showAppList();
            return;
        }
        hookUiVisible = true;
        settingsUiVisible = false;
        hookTargetVisible = true;
        hookHubVisible = false;
        selectedPackage = ai.packageName;
        try {
            CharSequence label = getPackageManager().getApplicationLabel(ai);
            selectedLabel = label == null ? ai.packageName : label.toString();
        } catch (RuntimeException unavailable) {
            selectedLabel = ai.packageName;
        }
        base(selectedLabel);
        TextView pkg=new TextView(this); pkg.setText(selectedPackage); pkg.setTextColor(0xff687582);
        pkg.setPadding(dp(18),0,dp(18),dp(12)); content.addView(pkg);
        boolean targetDebuggable = (ai.flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
        TextView scopeNotice = new TextView(this);
        scopeNotice.setText("LSPosed 模块启用和目标应用作用域必须在 LSPosed Manager 中单独设置。本页只发布 FX Hook 规则，不会自动授予或修改 LSPosed 作用域。");
        scopeNotice.setTextColor(0xff697681);
        scopeNotice.setPadding(dp(18), dp(4), dp(18), dp(12));
        content.addView(scopeNotice);
        TextView targetBuildState = new TextView(this);
        targetBuildState.setText(targetDebuggable
                ? "目标应用：可调试版本（自定义只读 Hook 可执行）"
                : "目标应用：非调试版本（自定义只读 Hook 暂不执行）");
        targetBuildState.setTextColor(0xff697681);
        targetBuildState.setPadding(dp(18),0,dp(18),dp(12));
        content.addView(targetBuildState);
        section("广告识别");
        TextView adNote=new TextView(this);
        adNote.setText("广告类型由内置识别引擎自动判断，无需按应用配置启动页、信息流或弹窗开关。");
        adNote.setTextColor(0xff697681); adNote.setPadding(dp(18),dp(2),dp(18),dp(14)); content.addView(adNote);
        section("隐私 Hook");
        toggle("隐私保护总开关", "privacy", false);
        toggle("统一广告标识（应用内）", "ad_id_unify", false);
        toggle("阻止剪贴板读取", "clipboard_read_block", false);
        toggle("隔离剪贴板", "clipboard_isolate", false);
        toggle("限制 Wi-Fi 扫描", "wifi_scan_block", false);
        toggle("阻止录音启动（会影响录音功能）", "mic_access_block", false);
        toggle("限制摄像头访问", "camera_access_block", false);
        toggle("限制位置访问", "location_access_block", false);
        toggle("清理媒体查询元数据", "media_store_query_block", false);
        toggle("清理图片/视频元数据", "exif_strip", false);
        section("麦克风保护");
        toggle("录音静音（保留录音流程）", "mic_silence", false);
        section("通知保护");
        toggle("阻止通知监听注册", "notification_listen_block", false);
        toggle("隐藏通知权限提示", "notification_permission_hide", false);
        section("传感器保护");
        toggle("限制加速度计", "sensor_accel", false);
        toggle("限制陀螺仪", "sensor_gyro", false);
        toggle("限制光线传感器", "sensor_light", false);
        toggle("限制磁场传感器", "sensor_magnet", false);
        toggle("限制气压传感器", "sensor_pressure", false);
        toggle("限制距离传感器", "sensor_prox", false);
        toggle("限制传感器采样频率", "sensor_rate_limit", false);
        section("会员诊断");
        toggle("只读会员状态诊断", "member_diag", false);
        TextView note=new TextView(this);
        note.setText("会员诊断仅记录应用内可观察状态，不修改购买结果、会员资格、令牌或服务端授权。");
        note.setTextColor(0xff697681); note.setPadding(dp(18),dp(2),dp(18),dp(14)); content.addView(note);
        section("自定义 Hook");
        TextView custom=new TextView(this);
        custom.setText("仅对可调试版本目标应用生效。自定义规则只记录方法调用、参数类型、耗时和异常类型；不记录参数/返回值，也不修改返回值、登录状态或会员资格。");
        custom.setTextColor(0xff697681); custom.setPadding(dp(18),dp(4),dp(18),dp(8)); content.addView(custom);
        Button addRule=new Button(this); addRule.setText("添加只读观察规则");
        addRule.setOnClickListener(v->showCustomRuleDialog()); content.addView(addRule);
        renderCustomRules();
        Button save=new Button(this); save.setText("保存并发布 Hook 配置");
        save.setOnClickListener(v -> {
            getPreferences(0).edit().putBoolean(key("draft_saved"),true).apply();
            publishConfig();
        });
        content.addView(save,new LinearLayout.LayoutParams(-1,-2));
        Button back=new Button(this); back.setText("返回应用列表"); back.setOnClickListener(v->showAppList());
        content.addView(back,new LinearLayout.LayoutParams(-1,-2));
    }
 

    private void showCustomRuleDialog() {
        LinearLayout form=new LinearLayout(this); form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(20),dp(8),dp(20),0);
        EditText id=new EditText(this); id.setSingleLine(true); id.setHint("规则 ID，例如 observe1");
        EditText descriptor=new EditText(this); descriptor.setSingleLine(true);
        descriptor.setHint("类名#方法()Z 或 L类路径;->方法()返回类型");
        form.addView(id); form.addView(descriptor);
        new AlertDialog.Builder(this).setTitle("新增只读 Hook 规则").setView(form)
            .setNegativeButton("取消",null).setPositiveButton("保存",(d,w)->{
                String ruleId=id.getText().toString().trim();
                String method=descriptor.getText().toString().trim();
                DeveloperHookRule rule=DeveloperHookRule.parse(ruleId+"|"+method+"|OBSERVE|0",selectedPackage);
                if(rule==null) {
                    new AlertDialog.Builder(this).setMessage("规则无效：方法必须属于当前应用包名下的类，且描述符格式正确。")
                        .setPositiveButton("知道了",null).show(); return;
                }
                for(int n=1;n<=64;n++) {
                    String existing=getPreferences(0).getString(selectedPackage+":dev_rule_"+n,null);
                    if(existing!=null && existing.startsWith(rule.id+"|")) {
                        new AlertDialog.Builder(this).setMessage("规则 ID 已存在，请换一个 ID。")
                            .setPositiveButton("知道了",null).show(); return;
                    }
                }
                int slot=1;
                while(slot<=64 && getPreferences(0).contains(selectedPackage+":dev_rule_"+slot)) slot++;
                if(slot>64) {
                    new AlertDialog.Builder(this).setMessage("每个应用最多配置 64 条自定义规则。").setPositiveButton("知道了",null).show(); return;
                }
                getPreferences(0).edit().putString(selectedPackage+":dev_rule_"+slot,
                    rule.id+"|"+rule.descriptor+"|OBSERVE|0").putBoolean(selectedPackage+":dev_hook_enabled",true).apply();
                ApplicationInfo currentTarget = findApp(selectedPackage);
                if (currentTarget == null) {
                    new AlertDialog.Builder(this).setMessage("目标应用已卸载或不再可用，请返回应用列表刷新。")
                            .setPositiveButton("知道了", null).show();
                    return;
                }
                showTarget(currentTarget);
            }).show();
    }

    private ApplicationInfo findApp(String pkg) {
        for(ApplicationInfo ai:apps) if(ai.packageName.equals(pkg)) return ai;
        return null;
    }

    private void renderCustomRules() {
        for(int i=1;i<=64;i++) {
            String value=getPreferences(0).getString(selectedPackage+":dev_rule_"+i,null);
            if(value==null) continue;
            TextView item=new TextView(this); item.setText(value); item.setTextSize(12);
            item.setTextColor(0xff596775); item.setPadding(dp(18),dp(6),dp(18),dp(6));
            content.addView(item);
            Button remove=new Button(this); remove.setText("删除 "+value.substring(0,value.indexOf('|')));
            final int slot=i; remove.setOnClickListener(v->{
                getPreferences(0).edit().remove(selectedPackage+":dev_rule_"+slot).apply();
                ApplicationInfo ai=findApp(selectedPackage); if(ai!=null) showTarget(ai);
            });
            content.addView(remove);
        }
    }

    private boolean enabled(String pkg, String feature) {
        return getPreferences(0).getBoolean(pkg + ":" + feature, false);
    }

    private void publishConfig() {
        try {
            StringBuilder cfg = new StringBuilder();
            boolean anyPrivacy=false, anyWifi=false, anyNotif=false, anyNotifPerm=false, anyClipboardIso=false;
            List<String> rows = new ArrayList<>();
            List<String> legacyManagedRows = new ArrayList<>();
            final String[][] legacyDuplicateKeys = {
                {"exif_strip","exif_strip"},
                {"clipboard_read_block","clipboard"}, {"clipboard_isolate","clipboard_isolate"},
                {"sensor_accel","sensor_accel"}, {"sensor_gyro","sensor_gyro"},
                {"sensor_light","sensor_light"}, {"sensor_magnet","sensor_magnet"},
                {"sensor_pressure","sensor_pressure"}, {"sensor_prox","sensor_prox"},
                {"sensor_rate_limit","sensor_rate_limit"}, {"wifi_scan_block","block_wifi_scan"},
                {"notification_listen_block","block_notif_listen"},
                {"notification_permission_hide","hide_notif_perm"},
                {"ad_id_unify","ad_id_unify"},
                {"mic_access_block","mic_block"},
                {"mic_silence","mic_block"}, {"mic_silence","audio_fp_block"},
                {"camera_access_block","cam_null"},
                {"location_access_block","disable_passive_loc"},
                {"media_store_query_block","block_mediastore"}
            };
            for (ApplicationInfo ai : apps) {
                String p=ai.packageName;
                String[] keys={"member_diag","privacy","exif_strip",
                    "clipboard_read_block","clipboard_isolate","wifi_scan_block","notification_listen_block",
                    "notification_permission_hide","ad_id_unify","mic_silence","camera_access_block","location_access_block",
                    "mic_access_block","media_store_query_block","sensor_accel","sensor_gyro","sensor_light",
                    "sensor_magnet","sensor_pressure","sensor_prox","sensor_rate_limit"};
                StringBuilder row=new StringBuilder(p);
                boolean has=false;
                for(String k:keys) {
                    boolean on=enabled(p,k);
                    if(on) {
                        row.append(',').append(k).append('=').append('1'); has=true;
                        if(k.equals("privacy")||k.equals("exif_strip")||k.equals("clipboard_read_block")||
                           k.equals("clipboard_isolate")||k.equals("mic_silence")||k.equals("camera_access_block")||
                           k.equals("location_access_block")||k.equals("mic_access_block")||
                           k.equals("media_store_query_block")||k.equals("ad_id_unify")||k.startsWith("sensor_")) anyPrivacy=true;
                        if(k.equals("wifi_scan_block")) anyWifi=true;
                        if(k.equals("notification_listen_block")) anyNotif=true;
                        if(k.equals("notification_permission_hide")) anyNotifPerm=true;
                        if(k.equals("clipboard_isolate")) anyClipboardIso=true;
                    }
                }
                StringBuilder legacyManaged = new StringBuilder(p);
                for (String[] mapping : legacyDuplicateKeys) {
                    if (enabled(p, mapping[0])) legacyManaged.append(',').append(mapping[1]);
                }
                if (legacyManaged.length() > p.length()) legacyManagedRows.add(legacyManaged.toString());
                boolean customEnabled=false;
                for(int n=1;n<=64;n++) {
                    String rule=getPreferences(0).getString(p+":dev_rule_"+n,null);
                    if(rule!=null) {
                        if(!customEnabled) { row.append(",dev_hook_enabled=1"); customEnabled=true; }
                        row.append(",dev_rule_").append(n).append('=').append(rule);
                        has=true;
                    }
                }
                if(has) rows.add(row.toString());
            }
            cfg.append("schema_version=1\n")
               .append("ads_enabled=1\n")
               .append("privacy_enabled=").append(anyPrivacy?'1':'0').append('\n')
               .append("wifi_scan_enabled=").append(anyWifi?'1':'0').append('\n')
               .append("notification_listen_enabled=").append(anyNotif?'1':'0').append('\n')
               .append("notification_permission_hide_enabled=").append(anyNotifPerm?'1':'0').append('\n')
               .append("clipboard_isolate_enabled=").append(anyClipboardIso?'1':'0').append('\n')
               .append("[list:targets]\n");
            for(String row:rows) cfg.append(row).append('\n');
            if(rows.size()>990) throw new IllegalStateException("目标应用配置超过 990 条上限，请缩小 Hook 作用范围。");
            byte[] configBytes=cfg.toString().getBytes("UTF-8");
            if(configBytes.length>65536) throw new IllegalStateException("Hook 配置超过 64 KiB 上限，请减少目标或自定义规则数量。");
            String expectedHash=sha256Hex(configBytes);
            String encoded=android.util.Base64.encodeToString(configBytes,android.util.Base64.NO_WRAP);
            StringBuilder managedConfig=new StringBuilder();
            for(String row:legacyManagedRows) managedConfig.append(row).append('\n');
            byte[] managedBytes=managedConfig.toString().getBytes("UTF-8");
            if(managedBytes.length>65536) throw new IllegalStateException("Hook 兼容映射超过 64 KiB 上限。");
            String managedHash=sha256Hex(managedBytes);
            String managedEncoded=android.util.Base64.encodeToString(managedBytes,android.util.Base64.NO_WRAP);
            int androidUser=android.os.Process.myUid()/100000;
            String moduleDir="/data/adb/lspd/modules/"+androidUser+"/de.privacyguard.adhook/files";
            String remote=moduleDir+"/fx-hook-targets.conf";
            String temp=remote+".tmp";
            String legacyDir="/data/local/tmp/privacyguard";
            String managedFile=legacyDir+"/fx-api101-managed.conf";
            String managedTemp=managedFile+".tmp";
            String pgDir="/data/adb/privacyguard";
            String nativeOverlay=pgDir+"/fx-native-hook-targets-"+androidUser+".conf";
            String nativeOverlayTemp=nativeOverlay+".tmp";
            String command="set -e; umask 077; mkdir -p '"+moduleDir+"' '"+legacyDir+"' '"+pgDir+"'; "
                    +"printf '%s' '"+encoded+"' | base64 -d > '"+temp+"'; "
                    +"printf '%s' '"+encoded+"' | base64 -d > '"+nativeOverlayTemp+"'; "
                    +"printf '%s' '"+managedEncoded+"' | base64 -d > '"+managedTemp+"'; "
                    +"test -s '"+temp+"' && test -s '"+nativeOverlayTemp+"'; "
                    +"actual_tmp=$(sha256sum '"+temp+"' | cut -d ' ' -f1); "
                    +"actual_native_tmp=$(sha256sum '"+nativeOverlayTemp+"' | cut -d ' ' -f1); "
                    +"actual_managed_tmp=$(sha256sum '"+managedTemp+"' | cut -d ' ' -f1); "
                    +"test \"$actual_tmp\" = '"+expectedHash+"' && test \"$actual_native_tmp\" = '"+expectedHash+"' && test \"$actual_managed_tmp\" = '"+managedHash+"'; "
                    +"chmod 0755 '"+legacyDir+"'; chmod 0644 '"+temp+"' '"+managedTemp+"'; chmod 0600 '"+nativeOverlayTemp+"'; "
                    +"chown 0:0 '"+temp+"' '"+managedTemp+"' '"+nativeOverlayTemp+"'; "
                    +"chmod 0755 '"+moduleDir+"'; chcon u:object_r:magisk_file:s0 '"+moduleDir+"' '"+temp+"' '"+pgDir+"' '"+nativeOverlayTemp+"'; "
                    +"chcon u:object_r:shell_data_file:s0 '"+legacyDir+"' '"+managedTemp+"'; sync; "
                    +"if [ -e '"+remote+"' ]; then cp -p '"+remote+"' '"+remote+".bak'; else rm -f '"+remote+".bak'; fi; "
                    +"if [ -e '"+managedFile+"' ]; then cp -p '"+managedFile+"' '"+managedFile+".bak'; else rm -f '"+managedFile+".bak'; fi; "
                    +"if [ -e '"+nativeOverlay+"' ]; then cp -p '"+nativeOverlay+"' '"+nativeOverlay+".bak'; else rm -f '"+nativeOverlay+".bak'; fi; "
                    +"mv -f '"+managedTemp+"' '"+managedFile+"'; "
                    +"if ! mv -f '"+nativeOverlayTemp+"' '"+nativeOverlay+"'; then "
                    +"if [ -e '"+managedFile+".bak' ]; then mv -f '"+managedFile+".bak' '"+managedFile+"'; else rm -f '"+managedFile+"'; fi; exit 1; fi; "
                    +"if ! mv -f '"+temp+"' '"+remote+"'; then "
                    +"if [ -e '"+nativeOverlay+".bak' ]; then mv -f '"+nativeOverlay+".bak' '"+nativeOverlay+"'; else rm -f '"+nativeOverlay+"'; fi; "
                    +"if [ -e '"+managedFile+".bak' ]; then mv -f '"+managedFile+".bak' '"+managedFile+"'; else rm -f '"+managedFile+"'; fi; exit 1; fi; "
                    +"if ! chmod 0644 '"+remote+"' '"+managedFile+"' || ! chmod 0600 '"+nativeOverlay+"' || "
                    +"! chown 0:0 '"+remote+"' '"+managedFile+"' '"+nativeOverlay+"' || "
                    +"! chmod 0755 '"+moduleDir+"' || ! chmod 0755 '"+legacyDir+"' || ! chcon u:object_r:magisk_file:s0 '"+moduleDir+"' '"+remote+"' '"+pgDir+"' '"+nativeOverlay+"' || "
                    +"! chcon u:object_r:shell_data_file:s0 '"+legacyDir+"' '"+managedFile+"'; then "
                    +"if [ -e '"+remote+".bak' ]; then mv -f '"+remote+".bak' '"+remote+"'; else rm -f '"+remote+"'; fi; "
                    +"if [ -e '"+nativeOverlay+".bak' ]; then mv -f '"+nativeOverlay+".bak' '"+nativeOverlay+"'; else rm -f '"+nativeOverlay+"'; fi; "
                    +"if [ -e '"+managedFile+".bak' ]; then mv -f '"+managedFile+".bak' '"+managedFile+"'; else rm -f '"+managedFile+"'; fi; exit 1; fi; sync; "
                    +"actual=$(sha256sum '"+remote+"' | cut -d ' ' -f1); "
                    +"actual_native=$(sha256sum '"+nativeOverlay+"' | cut -d ' ' -f1); "
                    +"actual_managed=$(sha256sum '"+managedFile+"' | cut -d ' ' -f1); "
                    +"if [ \"$actual\" != '"+expectedHash+"' ] || [ \"$actual_native\" != '"+expectedHash+"' ] || [ \"$actual_managed\" != '"+managedHash+"' ]; then "
                    +"if [ -e '"+remote+".bak' ]; then mv -f '"+remote+".bak' '"+remote+"'; else rm -f '"+remote+"'; fi; "
                    +"if [ -e '"+nativeOverlay+".bak' ]; then mv -f '"+nativeOverlay+".bak' '"+nativeOverlay+"'; else rm -f '"+nativeOverlay+"'; fi; "
                    +"if [ -e '"+managedFile+".bak' ]; then mv -f '"+managedFile+".bak' '"+managedFile+"'; else rm -f '"+managedFile+"'; fi; exit 1; fi; "
                    +"printf 'SHA256=%s\\nAPI101_OVERLAY_SHA256=%s\\nAPI101_OWNERSHIP_SHA256=%s\\n' \"$actual\" \"$actual_native\" \"$actual_managed\"";
            if(command.length()>131072) throw new IllegalStateException("Root 发布命令超过 128 KiB 上限，请减少目标或自定义规则数量。");
            if (hookPublisherThread != null && hookPublisherThread.isAlive()) {
                Toast.makeText(this, "Hook 配置正在发布，请等待当前操作完成。", Toast.LENGTH_LONG).show();
                return;
            }
            Thread publisher = new Thread(() -> {
                RootAccess.Result result = RootAccess.execute(command, 60000L, 1024 * 1024);
                if (hookPublisherThread == Thread.currentThread()) hookPublisherThread = null;
                runOnUiThread(() -> {
                    if (isFinishing() || isDestroyed()) return;
                    if(result.exitCode==0) {
                        getSharedPreferences("fx_hook_publish", MODE_PRIVATE).edit()
                                .putString("sha256", expectedHash)
                                .putString("remote_path", remote)
                                .putLong("published_at", System.currentTimeMillis())
                                .apply();
                        new AlertDialog.Builder(this).setMessage("配置已原子写入 LSPosed Remote Files，并已输出 SHA-256 校验值：\\n"+result.output+"\\n请确认 LSPosed Manager 已启用 FX 并将目标应用加入作用域，然后强制停止并重新打开目标应用。")
                            .setPositiveButton("知道了",null).show();
                    } else {
                        new AlertDialog.Builder(this).setMessage("Root 发布失败（退出码 "+result.exitCode+"）。"+result.output+"请确认 KernelSU 已授予 FX Hook Root 权限。配置仍保存在本机草稿。")
                            .setPositiveButton("知道了",null).show();
                    }
                });
            }, "fx-config-publisher");
            hookPublisherThread = publisher;
            publisher.start();
        } catch(Exception e) {
            new AlertDialog.Builder(this).setMessage("配置同步失败："+e.getClass().getSimpleName()+"。本机草稿仍已保存。")
                .setPositiveButton("知道了",null).show();
        }
    }

    private static String sha256Hex(byte[] data) throws Exception {
        byte[] digest=java.security.MessageDigest.getInstance("SHA-256").digest(data);
        char[] hex="0123456789abcdef".toCharArray();
        char[] out=new char[digest.length*2];
        for(int i=0;i<digest.length;i++) {
            int value=digest[i]&0xff;
            out[i*2]=hex[value>>>4];
            out[i*2+1]=hex[value&0x0f];
        }
        return new String(out);
    }

    private void section(String s) {
        TextView t=title(s,16);
        t.setBackground(roundedDrawable("miuix".equals(uiMode) ? 0xffe5ecf8 : "glass".equals(uiMode) ? 0xccefffff : 0xffe9eef3,
                "glass".equals(uiMode) ? 0x66ffffff : 0));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1,-2);
        lp.setMargins(dp(12), dp(10), dp(12), dp(4));
        content.addView(t,lp);
    }
    private void toggle(String label,String feature,boolean def) {
        Switch sw=new Switch(this); sw.setText(label); sw.setTextSize(15); sw.setPadding(dp(18),dp(12),dp(18),dp(12));
        sw.setBackground(uiPanelDrawable()); sw.setChecked(getPreferences(0).getBoolean(key(feature),def));
        sw.setOnCheckedChangeListener((b,on)->getPreferences(0).edit().putBoolean(key(feature),on).apply());
        content.addView(sw,new LinearLayout.LayoutParams(-1,-2));
    }
}