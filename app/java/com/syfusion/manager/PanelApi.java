package com.syfusion.manager;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 与模块内置面板（abserver serve）通信的极简客户端。
 *
 * 为什么不用 OkHttp / AndroidX：
 *   本 App 走 aapt2 + d8 手工构建，没有 Gradle 依赖解析，
 *   引入第三方库会让构建链路复杂化。HttpURLConnection 足够。
 *
 * 令牌：面板会把当前令牌注入到 index.html 的
 *   window.__SY_TOKEN__="..." 里，这里抓一次缓存起来。
 *   令牌变了（重启面板）会自动重新抓。
 */
public final class PanelApi {

    public static final int DEFAULT_PORT = 8848;

    private static final Pattern TOKEN_RE =
            Pattern.compile("window\\.__SY_TOKEN__\\s*=\\s*\"([^\"]*)\"");
    private static final Pattern PORT_RE =
            Pattern.compile("\"port\"\\s*:\\s*(\\d+)");

    private static volatile String sToken = "";
    private static volatile int sTokenPort = -1;
    private static volatile long sTokenAt = 0L;

    private PanelApi() {}

    public static String base(int port) {
        return "http://127.0.0.1:" + port;
    }

    /** 抓取面板首页并解析注入的令牌；失败返回 null。 */
    public static synchronized String token(int port, int timeoutMs) {
        long now = System.currentTimeMillis();
        if (sTokenPort == port && now - sTokenAt < 60000L) {
            return sToken;
        }
        try {
            String html = rawGet(base(port) + "/", timeoutMs);
            if (html == null) return null;
            Matcher m = TOKEN_RE.matcher(html);
            sToken = m.find() ? m.group(1) : "";
            sTokenPort = port;
            sTokenAt = now;
            return sToken;
        } catch (Exception e) {
            return null;
        }
    }

    /** 面板是否在线，并返回其端口（端口可从 panel.sh status 里读到）。 */
    public static boolean ping(int port, int timeoutMs) {
        try {
            String r = rawGet(base(port) + "/api/ping", timeoutMs);
            return r != null && r.contains("\"ok\":true");
        } catch (Exception e) {
            return false;
        }
    }

    /** 调面板受保护 API，自动带令牌。path 形如 "/api/clash?sub=status"。 */
    public static String get(int port, String path, int timeoutMs) {
        String tk = token(port, timeoutMs);
        if (tk == null) return null;
        String url = base(port) + path;
        if (tk.length() > 0) {
            url += (path.indexOf('?') >= 0 ? "&" : "?") + "token=" + enc(tk);
        }
        try {
            return rawGet(url, timeoutMs);
        } catch (Exception e) {
            return null;
        }
    }

    public static String enc(String s) {
        try {
            return URLEncoder.encode(s, "UTF-8");
        } catch (Exception e) {
            return s;
        }
    }

    private static String rawGet(String url, int timeoutMs) throws Exception {
        HttpURLConnection c = null;
        try {
            c = (HttpURLConnection) new URL(url).openConnection();
            c.setConnectTimeout(timeoutMs);
            c.setReadTimeout(timeoutMs);
            c.setRequestMethod("GET");
            c.setUseCaches(false);
            int code = c.getResponseCode();
            if (code != 200) return null;
            InputStream in = c.getInputStream();
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) {
                bos.write(buf, 0, n);
                if (bos.size() > 4 * 1024 * 1024) break;
            }
            in.close();
            return new String(bos.toByteArray(), "UTF-8");
        } finally {
            if (c != null) c.disconnect();
        }
    }

    // ---------- 从 JSON 里抠字段（避免为几个字段引入 JSON 库） ----------

    public static String str(String json, String key) {
        if (json == null) return "";
        Matcher m = Pattern.compile("\"" + Pattern.quote(key) + "\"\\s*:\\s*\"([^\"]*)\"")
                .matcher(json);
        return m.find() ? m.group(1) : "";
    }

    public static long num(String json, String key) {
        if (json == null) return 0L;
        Matcher m = Pattern.compile("\"" + Pattern.quote(key) + "\"\\s*:\\s*(-?\\d+)")
                .matcher(json);
        if (!m.find()) return 0L;
        try {
            return Long.parseLong(m.group(1));
        } catch (Exception e) {
            return 0L;
        }
    }

    public static boolean bool(String json, String key) {
        if (json == null) return false;
        return json.matches("(?s).*\"" + Pattern.quote(key) + "\"\\s*:\\s*true.*");
    }

    /** 人类可读速率 */
    public static String speed(long bps) {
        if (bps < 1024) return bps + " B/s";
        if (bps < 1024 * 1024) return String.format("%.1f K/s", bps / 1024.0);
        return String.format("%.2f M/s", bps / 1048576.0);
    }

    /** 人类可读流量 */
    public static String bytes(long b) {
        if (b < 1024) return b + " B";
        if (b < 1024 * 1024) return String.format("%.1f KB", b / 1024.0);
        if (b < 1024L * 1024 * 1024) return String.format("%.1f MB", b / 1048576.0);
        return String.format("%.2f GB", b / 1073741824.0);
    }
}
