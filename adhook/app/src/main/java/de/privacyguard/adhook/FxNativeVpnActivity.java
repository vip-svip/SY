package de.privacyguard.adhook;

import android.os.Bundle;
import android.app.AlertDialog;
import android.text.InputType;
import android.widget.EditText;
import android.widget.CheckBox;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import android.view.Gravity;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

import de.privacyguard.adhook.imported.ad.FxYulongRootModuleCommand;
import org.json.JSONObject;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Native VPN tab backed by FX's one canonical root-route controller.
 * It never creates a second Android VpnService or starts the legacy Yulong VPN.
 */
public final class FxNativeVpnActivity extends FxNativeTabActivity {
    private static final String[] MODE_VALUES = {"direct", "rule", "global", "tun"};
    private static final String[] MODE_LABELS = {"直连", "规则分流", "全局代理", "TUN"};
    private final ExecutorService worker = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "fx-native-vpn-ui"); t.setDaemon(true); return t;
    });
    private TextView status;
    private TextView detail;
    private Spinner mode;
    private Button start;
    private Button stop;
    private Button applyMode;
    private boolean busy;

    private TextView subscriptionStatus;
    private Button addSubscription;
    private Button manageSubscriptions;
    private Button refreshSubscriptions;
    private Spinner nodeSelection;
    private Button applyNode;
    private boolean subscriptionBusy;

    private EditText remoteDnsInput;
    private EditText directDnsInput;
    private EditText proxyDnsInput;
    private EditText fallbackDnsInput;
    private CheckBox fallbackSystemCheck;
    private CheckBox directSystemCheck;
    private CheckBox directFallbackProxyCheck;
    private Button applyPrivateDns;
    private TextView privateDnsStatus;
    private boolean privateDnsBusy;
    private final List<SubscriptionItem> subscriptions = new ArrayList<>();
    private final List<NodeItem> nodes = new ArrayList<>();
    private final List<NodeItem> selectableNodes = new ArrayList<>();

    private static final class SubscriptionItem {
        final int index;
        final String host;
        final String name;
        final boolean enabled;
        SubscriptionItem(int index, String host, String name, boolean enabled) {
            this.index = index; this.host = host; this.name = name; this.enabled = enabled;
        }
    }

    private static final class NodeItem {
        final int index;
        final String name;
        final String endpoint;
        final boolean selected;
        final boolean enabled;
        NodeItem(int index, String name, String endpoint, boolean selected, boolean enabled) {
            this.index = index; this.name = name; this.endpoint = endpoint;
            this.selected = selected; this.enabled = enabled;
        }
        String label() {
            return (selected ? "✓ " : "") + name + (enabled ? "" : "（已停用）");
        }
    }

    /** Reflect the existing subscription controls; a busy flag never re-enables them. */
    private void setSubscriptionControlsEnabled() {
        boolean ready = !subscriptionBusy;
        if (addSubscription != null) addSubscription.setEnabled(ready);
        if (manageSubscriptions != null) manageSubscriptions.setEnabled(ready);
        if (refreshSubscriptions != null) refreshSubscriptions.setEnabled(ready);
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this);
        root.setTag("fx-page-root");
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(16), dp(18), dp(16), dp(20));
        TextView title = new TextView(this);
        title.setTag("fx-title:24");
        title.setText("VPN");
        title.setTextSize(24);
        title.setTypeface(null, android.graphics.Typeface.BOLD);
        root.addView(title);
        TextView subtitle = new TextView(this);
        subtitle.setTag("fx-card-detail");
        subtitle.setText("统一 FX 网络路由 · DNS 过滤与节点代理共用模块状态");
        subtitle.setTextSize(12);
        subtitle.setPadding(0, dp(5), 0, dp(12));
        root.addView(subtitle);

        status = new TextView(this);
        status.setTag("fx-loading-state");
        status.setText("正在读取 VPN 状态…");
        status.setTextSize(16);
        status.setPadding(0, dp(8), 0, dp(8));
        root.addView(status);
        detail = new TextView(this);
        detail.setTag("fx-card-detail");
        detail.setTextSize(12);
        detail.setPadding(0, 0, 0, dp(12));
        root.addView(detail);

        TextView modeLabel = new TextView(this);
        modeLabel.setTag("fx-list-title");
        modeLabel.setText("路由模式");
        modeLabel.setTextSize(14);
        root.addView(modeLabel);
        mode = new Spinner(this); mode.setTag("fx-select-input");
        mode.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item, MODE_LABELS));
        root.addView(mode, new LinearLayout.LayoutParams(-1, dp(52)));
        applyMode = new Button(this); applyMode.setTag("fx-primary-action");
        applyMode.setAllCaps(false);
        applyMode.setText("应用路由模式");
        applyMode.setOnClickListener(v -> runCommand("set-mode", MODE_VALUES[mode.getSelectedItemPosition()]));
        root.addView(applyMode);

        LinearLayout actions = new LinearLayout(this);
        actions.setGravity(Gravity.CENTER_VERTICAL);
        start = new Button(this); start.setTag("fx-primary-action");
        start.setAllCaps(false);
        start.setText("启动 VPN");
        start.setOnClickListener(v -> runCommand("start", null));
        stop = new Button(this); stop.setTag("fx-action-row");
        stop.setAllCaps(false);
        stop.setText("停止 VPN");
        stop.setOnClickListener(v -> runCommand("stop", null));
        actions.addView(start, new LinearLayout.LayoutParams(0, dp(52), 1));
        actions.addView(stop, new LinearLayout.LayoutParams(0, dp(52), 1));
        root.addView(actions);

        Button refresh = new Button(this); refresh.setTag("fx-action-text");
        refresh.setAllCaps(false);
        refresh.setText("刷新状态");
        refresh.setOnClickListener(v -> refreshStatus());
        root.addView(refresh);

        TextView subscriptionsTitle = new TextView(this);
        subscriptionsTitle.setTag("fx-section:订阅与节点");
        subscriptionsTitle.setText("订阅与节点");
        subscriptionsTitle.setTextSize(18);
        subscriptionsTitle.setTypeface(null, android.graphics.Typeface.BOLD);
        subscriptionsTitle.setPadding(0, dp(18), 0, dp(6));
        root.addView(subscriptionsTitle);
        subscriptionStatus = new TextView(this);
        subscriptionStatus.setTag("fx-loading-state");
        subscriptionStatus.setText("正在读取订阅和节点…");
        subscriptionStatus.setTextSize(12);
        root.addView(subscriptionStatus);
        LinearLayout subscriptionActions = new LinearLayout(this);
        subscriptionActions.setGravity(Gravity.CENTER_VERTICAL);
        addSubscription = new Button(this); addSubscription.setTag("fx-primary-action");
        addSubscription.setAllCaps(false);
        addSubscription.setText("添加订阅");
        addSubscription.setOnClickListener(v -> showAddSubscriptionDialog());
        manageSubscriptions = new Button(this); manageSubscriptions.setTag("fx-action-text");
        manageSubscriptions.setAllCaps(false);
        manageSubscriptions.setText("管理订阅");
        manageSubscriptions.setOnClickListener(v -> showSubscriptionManager());
        subscriptionActions.addView(addSubscription, new LinearLayout.LayoutParams(0, dp(48), 1));
        subscriptionActions.addView(manageSubscriptions, new LinearLayout.LayoutParams(0, dp(48), 1));
        root.addView(subscriptionActions);
        refreshSubscriptions = new Button(this); refreshSubscriptions.setTag("fx-action-text");
        refreshSubscriptions.setAllCaps(false);
        refreshSubscriptions.setText("更新订阅");
        refreshSubscriptions.setOnClickListener(v -> runSubscriptionAction("refresh", new String[0]));
        root.addView(refreshSubscriptions);
        TextView nodeLabel = new TextView(this);
        nodeLabel.setTag("fx-list-title");
        nodeLabel.setText("当前节点");
        nodeLabel.setTextSize(14);
        nodeLabel.setPadding(0, dp(8), 0, dp(2));
        root.addView(nodeLabel);
        nodeSelection = new Spinner(this); nodeSelection.setTag("fx-select-input");
        nodeSelection.setAdapter(new ArrayAdapter<>(this, android.R.layout.simple_spinner_dropdown_item,
                new String[]{"正在读取节点…"}));
        root.addView(nodeSelection, new LinearLayout.LayoutParams(-1, dp(52)));
        applyNode = new Button(this); applyNode.setTag("fx-primary-action");
        applyNode.setAllCaps(false);
        applyNode.setText("应用所选节点");
        applyNode.setOnClickListener(v -> applySelectedNode());
        root.addView(applyNode);

        TextView privateDnsTitle = new TextView(this);
        privateDnsTitle.setTag("fx-section:私人 DNS");
        privateDnsTitle.setText("私人 DNS（小火箭式）");
        privateDnsTitle.setTextSize(18);
        privateDnsTitle.setTypeface(null, android.graphics.Typeface.BOLD);
        privateDnsTitle.setPadding(0, dp(20), 0, dp(6));
        root.addView(privateDnsTitle);

        TextView privateDnsHint = new TextView(this);
        privateDnsHint.setTag("fx-card-detail");
        privateDnsHint.setText("按域名分流：代理 DNS 解析非 .cn 查询，直连 DNS 解析 .cn 查询。每组可填写多个服务器，逗号或换行分隔。支持 UDP、TCP、DoT、DoQ、DoH、DoH3；在端点末尾添加 #proxy 可让该 DNS 连接经当前所选节点。");
        privateDnsHint.setTextSize(12);
        root.addView(privateDnsHint);

        TextView remoteDnsLabel = new TextView(this);
        remoteDnsLabel.setText("代理 / 远端 DNS");
        remoteDnsLabel.setTextSize(14);
        remoteDnsLabel.setPadding(0, dp(10), 0, dp(2));
        root.addView(remoteDnsLabel);
        remoteDnsInput = new EditText(this); remoteDnsInput.setTag("fx-form-input");
        remoteDnsInput.setSingleLine(false);
        remoteDnsInput.setMinLines(2);
        remoteDnsInput.setMaxLines(4);
        remoteDnsInput.setGravity(Gravity.TOP | Gravity.START);
        remoteDnsInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE
                | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        remoteDnsInput.setHint("1.1.1.1#proxy, https://dns.google/dns-query#proxy");
        root.addView(remoteDnsInput, new LinearLayout.LayoutParams(-1, dp(104)));

        TextView directDnsLabel = new TextView(this);
        directDnsLabel.setText("直连 / 国内 DNS");
        directDnsLabel.setTextSize(14);
        directDnsLabel.setPadding(0, dp(8), 0, dp(2));
        root.addView(directDnsLabel);
        directDnsInput = new EditText(this); directDnsInput.setTag("fx-form-input");
        directDnsInput.setSingleLine(false);
        directDnsInput.setMinLines(2);
        directDnsInput.setMaxLines(4);
        directDnsInput.setGravity(Gravity.TOP | Gravity.START);
        directDnsInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE
                | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        directDnsInput.setHint("223.5.5.5, udp://119.29.29.29");
        root.addView(directDnsInput, new LinearLayout.LayoutParams(-1, dp(104)));

        TextView proxyDnsLabel = new TextView(this);
        proxyDnsLabel.setText("代理专用 DNS（可留空）");
        proxyDnsLabel.setTextSize(14);
        proxyDnsLabel.setPadding(0, dp(8), 0, dp(2));
        root.addView(proxyDnsLabel);
        proxyDnsInput = new EditText(this); proxyDnsInput.setTag("fx-form-input");
        proxyDnsInput.setSingleLine(false);
        proxyDnsInput.setMinLines(1);
        proxyDnsInput.setMaxLines(3);
        proxyDnsInput.setGravity(Gravity.TOP | Gravity.START);
        proxyDnsInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE
                | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        proxyDnsInput.setHint("https://dns.google/dns-query, h3://cloudflare-dns.com/dns-query");
        root.addView(proxyDnsInput, new LinearLayout.LayoutParams(-1, dp(76)));

        TextView fallbackDnsLabel = new TextView(this);
        fallbackDnsLabel.setText("备用 DNS（可留空）");
        fallbackDnsLabel.setTextSize(14);
        fallbackDnsLabel.setPadding(0, dp(8), 0, dp(2));
        root.addView(fallbackDnsLabel);
        fallbackDnsInput = new EditText(this); fallbackDnsInput.setTag("fx-form-input");
        fallbackDnsInput.setSingleLine(false);
        fallbackDnsInput.setMinLines(1);
        fallbackDnsInput.setMaxLines(3);
        fallbackDnsInput.setGravity(Gravity.TOP | Gravity.START);
        fallbackDnsInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE
                | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        fallbackDnsInput.setHint("8.8.8.8, tls://1.1.1.1");
        root.addView(fallbackDnsInput, new LinearLayout.LayoutParams(-1, dp(76)));

        fallbackSystemCheck = new CheckBox(this); fallbackSystemCheck.setTag("fx-switch-row");
        fallbackSystemCheck.setText("主/备用 DNS 都失败后使用 Android 系统 DNS");
        fallbackSystemCheck.setChecked(false);
        root.addView(fallbackSystemCheck);
        directSystemCheck = new CheckBox(this); directSystemCheck.setTag("fx-switch-row");
        directSystemCheck.setText("国内直连域名直接使用 Android 系统 DNS");
        root.addView(directSystemCheck);
        directFallbackProxyCheck = new CheckBox(this); directFallbackProxyCheck.setTag("fx-switch-row");
        directFallbackProxyCheck.setText("国内直连 DNS 失败后改走代理 DNS");
        root.addView(directFallbackProxyCheck);

        applyPrivateDns = new Button(this); applyPrivateDns.setTag("fx-primary-action");
        applyPrivateDns.setAllCaps(false);
        applyPrivateDns.setText("保存并应用私人 DNS");
        applyPrivateDns.setOnClickListener(v -> applyPrivateDnsSettings());
        root.addView(applyPrivateDns);
        privateDnsStatus = new TextView(this);
        privateDnsStatus.setTag("fx-loading-state");
        privateDnsStatus.setText("正在读取私人 DNS 配置…");
        privateDnsStatus.setTextSize(12);
        privateDnsStatus.setPadding(0, dp(4), 0, dp(4));
        root.addView(privateDnsStatus);

        TextView note = new TextView(this);
        note.setTag("fx-card-detail");
        note.setText("启动和模式切换会要求模块确认节点与实际路由状态；未选节点或状态未知时拒绝盲目接管。直连模式会停止 FX 代理路由。");
        note.setTextSize(11);
        note.setPadding(0, dp(12), 0, 0);
        root.addView(note);

        ScrollView scroll = new ScrollView(this);
        scroll.addView(root);
        setContentViewWithNativeTabs(scroll, 0);
        refreshStatus();
        refreshPrivateDnsSettings();
    }

    private int dp(float value) {
        return (int)(value * getResources().getDisplayMetrics().density + .5f);
    }

    private String command(String action, String value) {
        String args = "\"$MP\" /data/adb/privacyguard " + action;
        if (value != null) args += " " + value;
        return FxYulongRootModuleCommand.command("yulong-vpn-control.sh", args);
    }

    private String privateDnsCommand(String action, String... arguments) {
        String command = FxYulongRootModuleCommand.prefix("native-vpn-config.sh")
                + "MP=\"$MP\" PG='/data/adb/privacyguard' "
                + "sh \"$MP/scripts/native-vpn-config.sh\" " + action;
        for (String argument : arguments) command += " " + shellQuote(argument);
        return command;
    }

    private static String normalizeDnsList(String raw) {
        if (raw == null) return "";
        String[] entries = raw.replace("\r", "").replace('\n', ',').split(",", -1);
        StringBuilder result = new StringBuilder();
        for (String item : entries) {
            String endpoint = item.trim();
            if (endpoint.isEmpty()) continue;
            if (result.length() > 0) result.append(',');
            result.append(endpoint);
        }
        return result.toString();
    }

    private void refreshPrivateDnsSettings() {
        if (privateDnsBusy || privateDnsStatus == null) return;
        privateDnsBusy = true;
        privateDnsStatus.setText("正在读取私人 DNS 配置…");
        privateDnsStatus.setTag("fx-loading-state");
        worker.execute(() -> {
            RootAccess.Result result = RootAccess.execute(
                    privateDnsCommand("list"), 45000L, 16384);
            String remote = null;
            String direct = null;
            String proxy = "";
            String fallback = "";
            boolean fallbackSystem = false;
            boolean directSystem = false;
            boolean directFallbackProxy = false;
            boolean proxySeen = false;
            boolean fallbackSeen = false;
            boolean fallbackSystemSeen = false;
            boolean directSystemSeen = false;
            boolean directFallbackProxySeen = false;
            boolean valid = result != null && result.exitCode == 0 && result.output != null;
            if (valid) {
                String[] lines = result.output.split("\\r?\\n");
                valid = lines.length > 0 && "FXVPNCONF1".equals(lines[0].trim());
                for (int i = 1; valid && i < lines.length; i++) {
                    String line = lines[i];
                    int split = line.indexOf('|');
                    if (split <= 0) continue;
                    String key = line.substring(0, split);
                    String value = line.substring(split + 1);
                    if ("remote_dns".equals(key)) {
                        if (remote != null) valid = false;
                        else remote = value;
                    } else if ("cn_dns".equals(key)) {
                        if (direct != null) valid = false;
                        else direct = value;
                    } else if ("proxy_dns_server".equals(key)) {
                        if (proxySeen) valid = false;
                        else { proxy = value; proxySeen = true; }
                    } else if ("fallback_dns_server".equals(key)) {
                        if (fallbackSeen) valid = false;
                        else { fallback = value; fallbackSeen = true; }
                    } else if ("dns_fallback_system".equals(key)) {
                        if (fallbackSystemSeen || !("0".equals(value) || "1".equals(value))) valid = false;
                        else { fallbackSystem = "1".equals(value); fallbackSystemSeen = true; }
                    } else if ("dns_direct_system".equals(key)) {
                        if (directSystemSeen || !("0".equals(value) || "1".equals(value))) valid = false;
                        else { directSystem = "1".equals(value); directSystemSeen = true; }
                    } else if ("dns_direct_fallback_proxy".equals(key)) {
                        if (directFallbackProxySeen || !("0".equals(value) || "1".equals(value))) valid = false;
                        else { directFallbackProxy = "1".equals(value); directFallbackProxySeen = true; }
                    }
                }
                if (remote == null || direct == null) valid = false;
            }
            final boolean ok = valid;
            final String remoteValue = remote;
            final String directValue = direct;
            final String proxyValue = proxy;
            final String fallbackValue = fallback;
            final boolean fallbackSystemValue = fallbackSystem;
            final boolean directSystemValue = directSystem;
            final boolean directFallbackProxyValue = directFallbackProxy;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                privateDnsBusy = false;
                setPrivateDnsControlsEnabled();
                if (!ok) {
                    privateDnsStatus.setText("私人 DNS 配置读取失败：" + message(result));
                    privateDnsStatus.setTag("fx-error-state");
                    return;
                }
                remoteDnsInput.setText(remoteValue);
                directDnsInput.setText(directValue);
                proxyDnsInput.setText(proxyValue);
                fallbackDnsInput.setText(fallbackValue);
                fallbackSystemCheck.setChecked(fallbackSystemValue);
                directSystemCheck.setChecked(directSystemValue);
                directFallbackProxyCheck.setChecked(directFallbackProxyValue);
                privateDnsStatus.setText("配置已读取。多服务器竞速和备用 DNS 需要 sing-box 1.14+；单个加密 DNS 端点需要 1.12+。");
                privateDnsStatus.setTag("fx-success-state");
            });
        });
    }

    private void applyPrivateDnsSettings() {
        if (privateDnsBusy) return;
        String remote = normalizeDnsList(remoteDnsInput.getText().toString());
        String direct = normalizeDnsList(directDnsInput.getText().toString());
        String proxy = normalizeDnsList(proxyDnsInput.getText().toString());
        String fallback = normalizeDnsList(fallbackDnsInput.getText().toString());
        if (remote.isEmpty() || direct.isEmpty()) {
            privateDnsStatus.setText("普通/代理 DNS 和直连 DNS 都至少需要填写一个服务器。");
            privateDnsStatus.setTag("fx-error-state");
            return;
        }
        String fallbackSystem = fallbackSystemCheck.isChecked() ? "1" : "0";
        String directSystem = directSystemCheck.isChecked() ? "1" : "0";
        String directFallbackProxy = directFallbackProxyCheck.isChecked() ? "1" : "0";
        privateDnsBusy = true;
        setPrivateDnsControlsEnabled();
        privateDnsStatus.setText("正在原子保存主 DNS、代理 DNS、备用 DNS 与回退策略…");
        privateDnsStatus.setTag("fx-loading-state");
        worker.execute(() -> {
            RootAccess.Result result = RootAccess.execute(
                    privateDnsCommand("set-many",
                            "remote_dns", remote,
                            "cn_dns", direct,
                            "proxy_dns_server", proxy,
                            "fallback_dns_server", fallback,
                            "dns_fallback_system", fallbackSystem,
                            "dns_direct_system", directSystem,
                            "dns_direct_fallback_proxy", directFallbackProxy),
                    180000L, 32768);
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                privateDnsBusy = false;
                setPrivateDnsControlsEnabled();
                if (result != null && result.exitCode == 0) {
                    privateDnsStatus.setText("私人 DNS 已保存并应用；主/代理/备用 DNS 和回退开关在同一事务中提交。");
                    privateDnsStatus.setTag("fx-success-state");
                    Toast.makeText(this, "私人 DNS 已应用", Toast.LENGTH_SHORT).show();
                    refreshStatus();
                } else {
                    privateDnsStatus.setText("私人 DNS 应用失败：" + message(result));
                    privateDnsStatus.setTag("fx-error-state");
                    Toast.makeText(this, "私人 DNS 应用失败", Toast.LENGTH_LONG).show();
                }
            });
        });
    }

    private void setPrivateDnsControlsEnabled() {
        boolean enabled = !privateDnsBusy && !busy && remoteDnsInput != null;
        if (remoteDnsInput != null) remoteDnsInput.setEnabled(enabled);
        if (directDnsInput != null) directDnsInput.setEnabled(enabled);
        if (proxyDnsInput != null) proxyDnsInput.setEnabled(enabled);
        if (fallbackDnsInput != null) fallbackDnsInput.setEnabled(enabled);
        if (fallbackSystemCheck != null) fallbackSystemCheck.setEnabled(enabled);
        if (directSystemCheck != null) directSystemCheck.setEnabled(enabled);
        if (directFallbackProxyCheck != null) directFallbackProxyCheck.setEnabled(enabled);
        if (applyPrivateDns != null) applyPrivateDns.setEnabled(enabled);
    }

    private void refreshStatus() {
        if (busy) return;
        busy = true;
        setBusy(true);
        status.setText("正在读取 VPN 状态…");
        status.setTag("fx-loading-state");
        worker.execute(() -> {
            RootAccess.Result result = RootAccess.execute(command("status", null), 45000L, 128 * 1024);
            JSONObject parsed = parse(result);
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                busy = false;
                setBusy(false);
                if (parsed == null) {
                    status.setText("VPN 状态不可用");
                    status.setTag("fx-error-state");
                    detail.setText(message(result));
                    refreshSubscriptionState();
                    return;
                }
                renderStatus(parsed);
                refreshSubscriptionState();
            });
        });
    }

    private JSONObject parse(RootAccess.Result result) {
        if (result == null || result.exitCode != 0 || result.output == null) return null;
        try { return new JSONObject(result.output.trim()); }
        catch (Exception ignored) { return null; }
    }

    private void renderStatus(JSONObject state) {
        String modeValue = state.optString("vpn_mode", "direct");
        int selected = 0;
        for (int i = 0; i < MODE_VALUES.length; i++) if (MODE_VALUES[i].equals(modeValue)) selected = i;
        mode.setSelection(selected);
        boolean running = state.optBoolean("vpn_on", false);
        boolean rootProxy = state.optBoolean("root_proxy_on", false);
        boolean rootProxyKnown = state.optBoolean("root_proxy_known", false);
        if (running) {
            status.setText("运行中 · " + modeLabel(modeValue));
            status.setTag("fx-success-state");
        } else if (rootProxyKnown && rootProxy) {
            status.setText("外部 VPN 协同保护中");
            status.setTag("fx-success-state");
        } else if ("direct".equals(modeValue)) {
            status.setText("直连 · FX VPN 已关闭");
            status.setTag("fx-empty-state");
        } else {
            status.setText("未确认运行 · " + modeLabel(modeValue));
            status.setTag("fx-error-state");
        }

        String node = state.optString("vpn_node", "");
        if (node.isEmpty()) node = "未选择节点";
        JSONObject coexistence = state.optJSONObject("vpn_coexistence");
        String coexistenceVerdict = coexistence == null ? "unknown" : coexistence.optString("verdict", "unknown");
        detail.setText("当前节点：" + node
                + "\n订阅：" + state.optInt("vpn_subs", 0)
                + " · 节点：" + state.optInt("vpn_nodes", 0)
                + "\n代理核心：" + (state.optBoolean("vpn_core", false) ? "已启用" : "未启用")
                + " · 监听：" + (state.optBoolean("vpn_listener_on", false) ? "正常" : "未确认")
                + "\nDNS 转发：" + state.optString("dns_forward_status", "unknown")
                + " · 共存判定：" + coexistenceVerdict);
    }

    private String modeLabel(String value) {
        if ("rule".equals(value)) return "规则分流";
        if ("global".equals(value)) return "全局代理";
        if ("tun".equals(value)) return "TUN";
        return "直连";
    }

    private void runCommand(String action, String value) {
        if (busy) return;
        busy = true;
        setBusy(true);
        status.setText("正在执行 VPN " + action + "…");
        status.setTag("fx-loading-state");
        worker.execute(() -> {
            RootAccess.Result result = RootAccess.execute(command(action, value), 150000L, 128 * 1024);
            RootAccess.Result statusResult = RootAccess.execute(command("status", null), 45000L, 128 * 1024);
            JSONObject parsed = parse(statusResult);
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                busy = false;
                setBusy(false);
                if (parsed != null) renderStatus(parsed);
                if (result.exitCode == 0 && parsed != null) {
                    Toast.makeText(this, "VPN 操作已确认", Toast.LENGTH_SHORT).show();
                } else {
                    status.setText("VPN 操作未确认");
                    status.setTag("fx-error-state");
                    detail.setText(message(result) + (parsed == null ? "\n状态读取失败：" + message(statusResult) : ""));
                    Toast.makeText(this, "VPN 未确认生效，请检查节点和 Root 状态", Toast.LENGTH_LONG).show();
                }
                refreshSubscriptionState();
            });
        });
    }

    private String subscriptionsCommand(String... arguments) {
        String command = FxYulongRootModuleCommand.prefix("native-vpn-subscriptions.sh")
                + "MP=\"$MP\" PG='/data/adb/privacyguard' "
                + "sh \"$MP/scripts/native-vpn-subscriptions.sh\"";
        for (String argument : arguments) command += " " + shellQuote(argument);
        return command;
    }

    private String shellQuote(String value) {
        return "'" + value.replace("'", "'\''") + "'";
    }

    private void refreshSubscriptionState() {
        if (busy || subscriptionBusy || isFinishing() || isDestroyed()) return;
        subscriptionBusy = true;
        setSubscriptionControlsEnabled();
        subscriptionStatus.setText("正在读取订阅与节点…");
        subscriptionStatus.setTag("fx-loading-state");
        worker.execute(() -> {
            File snapshot = new File(getCacheDir(), "fx-vpn-subscriptions.snapshot");
            RootAccess.Result result = RootAccess.executeToFile(
                    subscriptionsCommand("list"), 60000L, snapshot);
            List<SubscriptionItem> loadedSubscriptions = new ArrayList<>();
            List<NodeItem> loadedNodes = new ArrayList<>();
            String failure = null;
            if (result.exitCode == 0 && snapshot.isFile()) {
                try (BufferedReader reader = new BufferedReader(new InputStreamReader(
                        new FileInputStream(snapshot), StandardCharsets.UTF_8))) {
                    String header = reader.readLine();
                    if (!"FXVPNSUB1".equals(header)) {
                        failure = result.output == null ? "模块返回格式无效" : message(result);
                    } else {
                        String line;
                        while ((line = reader.readLine()) != null) {
                            String[] fields = line.split("\\|", -1);
                            try {
                                if (fields.length == 5 && "S".equals(fields[0])) {
                                    loadedSubscriptions.add(new SubscriptionItem(
                                            Integer.parseInt(fields[1]), fields[2], fields[3],
                                            "1".equals(fields[4])));
                                } else if (fields.length == 6 && "N".equals(fields[0])) {
                                    loadedNodes.add(new NodeItem(Integer.parseInt(fields[1]),
                                            fields[2], fields[3], "1".equals(fields[4]),
                                            "1".equals(fields[5])));
                                }
                            } catch (NumberFormatException ignored) {
                                // Ignore malformed rows; never turn them into selectable nodes.
                            }
                        }
                    }
                } catch (Exception error) {
                    failure = error.getClass().getSimpleName() + ": " + error.getMessage();
                }
            } else {
                failure = message(result);
            }
            snapshot.delete();
            final String loadFailure = failure;
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                subscriptionBusy = false;
                subscriptions.clear();
                subscriptions.addAll(loadedSubscriptions);
                nodes.clear();
                nodes.addAll(loadedNodes);
                updateNodeSelection();
                if (loadFailure == null) {
                    subscriptionStatus.setText("订阅 " + subscriptions.size()
                            + " 个 · 可用节点 " + countEnabledNodes() + " 个");
                    subscriptionStatus.setTag(subscriptions.isEmpty() || countEnabledNodes() == 0
                            ? "fx-empty-state" : "fx-success-state");
                } else {
                    subscriptionStatus.setText("订阅/节点读取失败：" + loadFailure);
                    subscriptionStatus.setTag("fx-error-state");
                }
                setSubscriptionControlsEnabled();
            });
        });
    }

    private int countEnabledNodes() {
        int count = 0;
        for (NodeItem node : nodes) if (node.enabled) count++;
        return count;
    }

    private void updateNodeSelection() {
        selectableNodes.clear();
        List<String> labels = new ArrayList<>();
        for (NodeItem node : nodes) {
            if (!node.enabled) continue;
            selectableNodes.add(node);
            labels.add(node.label() + " · " + node.endpoint);
        }
        if (labels.isEmpty()) labels.add(nodes.isEmpty()
                ? "暂无节点，请先添加订阅并更新" : "没有启用的节点");
        nodeSelection.setAdapter(new ArrayAdapter<>(this,
                android.R.layout.simple_spinner_dropdown_item, labels));
        int selected = 0;
        for (int i = 0; i < selectableNodes.size(); i++) {
            if (selectableNodes.get(i).selected) { selected = i; break; }
        }
        nodeSelection.setSelection(selected);
    }

    private void showAddSubscriptionDialog() {
        LinearLayout form = new LinearLayout(this);
        form.setOrientation(LinearLayout.VERTICAL);
        form.setPadding(dp(20), dp(8), dp(20), 0);
        EditText url = new EditText(this); url.setTag("fx-form-input");
        url.setSingleLine(true);
        url.setHint("https://example.com/subscribe");
        url.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI);
        form.addView(url, new LinearLayout.LayoutParams(-1, dp(54)));
        EditText name = new EditText(this); name.setTag("fx-form-input");
        name.setSingleLine(true);
        name.setHint("订阅名称（可留空）");
        form.addView(name, new LinearLayout.LayoutParams(-1, dp(54)));
        fxDialogBuilder().setTitle("添加 VPN 订阅").setView(form)
                .setNegativeButton("取消", null)
                .setPositiveButton("保存", (dialog, which) -> runSubscriptionAction(
                        "add", new String[]{url.getText().toString().trim(),
                                name.getText().toString().trim()}))
                .show();
    }

    private void showSubscriptionManager() {
        if (subscriptions.isEmpty()) {
            Toast.makeText(this, "当前没有 VPN 订阅", Toast.LENGTH_SHORT).show();
            return;
        }
        String[] labels = new String[subscriptions.size()];
        for (int i = 0; i < subscriptions.size(); i++) {
            SubscriptionItem item = subscriptions.get(i);
            labels[i] = (item.enabled ? "● " : "○ ") + item.name + " · " + item.host;
        }
        fxDialogBuilder().setTitle("管理 VPN 订阅")
                .setItems(labels, (dialog, which) -> showSubscriptionActions(subscriptions.get(which)))
                .setNegativeButton("关闭", null).show();
    }

    private void showSubscriptionActions(SubscriptionItem item) {
        String toggleLabel = item.enabled ? "停用订阅" : "启用订阅";
        CharSequence[] actions = {toggleLabel, "删除订阅"};
        fxDialogBuilder().setTitle(item.name)
                .setItems(actions, (dialog, which) -> {
                    if (which == 0) {
                        runSubscriptionAction("toggle", new String[]{
                                String.valueOf(item.index), item.enabled ? "0" : "1"});
                    } else if (which == 1) {
                        fxDialogBuilder().setTitle("删除订阅？")
                                .setMessage(item.name + " · " + item.host)
                                .setNegativeButton("取消", null)
                                .setPositiveButton("删除", (confirm, selected) ->
                                        runSubscriptionAction("delete",
                                                new String[]{String.valueOf(item.index)}))
                                .show();
                    }
                }).setNegativeButton("取消", null).show();
    }

    private void applySelectedNode() {
        if (selectableNodes.isEmpty()) {
            Toast.makeText(this, "没有可用节点，请先更新订阅", Toast.LENGTH_SHORT).show();
            return;
        }
        int position = nodeSelection.getSelectedItemPosition();
        if (position < 0 || position >= selectableNodes.size()) return;
        NodeItem selected = selectableNodes.get(position);
        runSubscriptionAction("select", new String[]{String.valueOf(selected.index)});
    }

    private void runSubscriptionAction(String action, String[] arguments) {
        if (busy || subscriptionBusy) return;
        String[] commandArguments = new String[arguments.length + 1];
        commandArguments[0] = action;
        System.arraycopy(arguments, 0, commandArguments, 1, arguments.length);
        subscriptionBusy = true;
        setSubscriptionControlsEnabled();
        subscriptionStatus.setText("正在执行：" + action);
        subscriptionStatus.setTag("fx-loading-state");
        long timeout = "refresh".equals(action) ? 300000L : 150000L;
        worker.execute(() -> {
            RootAccess.Result result = RootAccess.execute(
                    subscriptionsCommand(commandArguments), timeout, 32768);
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed()) return;
                subscriptionBusy = false;
                subscriptionStatus.setText(result.exitCode == 0
                        ? actionLabel(action) + "已提交，正在刷新状态…"
                        : actionLabel(action) + "失败：" + message(result));
                subscriptionStatus.setTag(result.exitCode == 0
                        ? "fx-loading-state" : "fx-error-state");
                setSubscriptionControlsEnabled();
                if (result.exitCode == 0) {
                    Toast.makeText(this, actionLabel(action) + "成功", Toast.LENGTH_SHORT).show();
                } else {
                    Toast.makeText(this, actionLabel(action) + "失败", Toast.LENGTH_LONG).show();
                }
                if ("select".equals(action) || "refresh".equals(action)) refreshStatus();
                else refreshSubscriptionState();
            });
        });
    }

    private String actionLabel(String action) {
        if ("add".equals(action)) return "添加订阅";
        if ("toggle".equals(action)) return "订阅状态更新";
        if ("delete".equals(action)) return "删除订阅";
        if ("select".equals(action)) return "节点选择";
        if ("refresh".equals(action)) return "订阅更新";
        return "VPN 操作";
    }

    private void setBusy(boolean value) {
        if (start != null) start.setEnabled(!value);
        if (stop != null) stop.setEnabled(!value);
        if (applyMode != null) applyMode.setEnabled(!value);
        if (mode != null) mode.setEnabled(!value);
        setSubscriptionControlsEnabled();
        setPrivateDnsControlsEnabled();
    }

    private String message(RootAccess.Result result) {
        if (result == null || result.output == null || result.output.trim().isEmpty()) return "无模块返回信息";
        String value = result.output.trim().replace('\n', ' ');
        return value.length() > 240 ? value.substring(0, 240) : value;
    }

    @Override protected void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }
}
