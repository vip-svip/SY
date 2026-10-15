package com.syfusion.manager;

import org.json.JSONObject;

/**
 * 极简 JSON 取值工具（模块脚本的 JSON 输出解析）。
 *
 * 为什么不用 Gson 之类：本 App 刻意不依赖 AndroidX/三方库 ——
 * 模块打包走的是 aapt2 + d8 手工链路，引入 AAR 会让构建复杂化且体积膨胀。
 * org.json 是 Android 框架内置的，够用。
 *
 * 所有取值都容错：解析失败/字段缺失一律返回 "" 或 false，
 * 绝不抛异常（原生界面任何一处崩了都会让用户看到"应用已停止"）。
 */
final class Jake {
    private Jake() {}

    private static JSONObject parse(String s) {
        if (s == null) return null;
        String t = s.trim();
        // 脚本输出有时前面带一行 OK:/ERR:，取第一个 { 开始的部分
        int i = t.indexOf('{');
        if (i > 0) t = t.substring(i);
        int j = t.lastIndexOf('}');
        if (j > 0) t = t.substring(0, j + 1);
        try {
            return new JSONObject(t);
        } catch (Exception e) {
            return null;
        }
    }

    /** 取字符串字段（缺失返回 ""）。支持嵌套：readiness.overall 用 "readiness" */
    public static String str(String json, String key) {
        JSONObject o = parse(json);
        if (o == null || key == null) return "";
        try {
            if (o.has(key)) {
                Object v = o.get(key);
                return v == null ? "" : String.valueOf(v);
            }
            // 嵌套一层：key 指定父对象，返回其子对象字符串（用于 readiness/lifecycle）
            return "";
        } catch (Exception e) {
            return "";
        }
    }

    /** 取布尔（对象非空也算 true；用于 readiness 这类嵌套对象） */
    public static boolean bool(String json, String key) {
        JSONObject o = parse(json);
        if (o == null || key == null) return false;
        try {
            if (!o.has(key)) return false;
            Object v = o.get(key);
            if (v instanceof Boolean) return (Boolean) v;
            if (v instanceof JSONObject) {
                // 形如 {"overall":true}：取内部 overall / ready
                JSONObject n = (JSONObject) v;
                for (String k : new String[]{"overall", "ready", "ok"}) {
                    if (n.has(k)) {
                        Object x = n.get(k);
                        if (x instanceof Boolean) return (Boolean) x;
                        if ("true".equals(String.valueOf(x))) return true;
                    }
                }
                return n.length() > 0;
            }
            if ("true".equals(String.valueOf(v))) return true;
            if ("1".equals(String.valueOf(v))) return true;
            return false;
        } catch (Exception e) {
            return false;
        }
    }

    /** 把 proxynodes.sh list 的 JSON 渲染成人类可读的多行文本 */
    public static String prettyNodes(String json) {
        JSONObject o = parse(json);
        if (o == null) return "(读取失败)";
        StringBuilder sb = new StringBuilder();
        try {
            sb.append("模式: ").append(o.optString("mode", "?")).append("\n");
            sb.append("支持协议: ").append(o.optString("protocols", "?")).append("\n");
            org.json.JSONArray arr = o.optJSONArray("nodes");
            if (arr == null || arr.length() == 0) {
                sb.append("(暂无节点)");
                return sb.toString();
            }
            sb.append("节点数: ").append(arr.length()).append("\n\n");
            int limit = Math.min(arr.length(), 30);
            for (int i = 0; i < limit; i++) {
                JSONObject n = arr.optJSONObject(i);
                if (n == null) continue;
                sb.append(n.optString("i")).append(". [").append(n.optString("proto")).append("] ")
                  .append(n.optString("name")).append("\n");
                sb.append("   ").append(n.optString("server")).append(":").append(n.optString("port"));
                String cipher = n.optString("cipher", "");
                if (cipher.length() > 0 && !"none".equals(cipher)) sb.append("  加密 ").append(cipher);
                String sni = n.optString("sni", "");
                if (sni.length() > 0 && !"-".equals(sni)) sb.append("  SNI ").append(sni);
                String net = n.optString("net", "");
                if (net.length() > 0 && !"-".equals(net)) sb.append("  ").append(net);
                String tls = n.optString("tls", "");
                if (tls.length() > 0 && !"-".equals(tls)) sb.append("  ").append(tls);
                String ping = n.optString("ping", "");
                if (ping.length() > 0 && !"-".equals(ping)) sb.append("  延迟 ").append(ping);
                sb.append("\n");
            }
            if (arr.length() > limit) sb.append("\n… 其余 ").append(arr.length() - limit).append(" 个已省略");
        } catch (Exception e) {
            return "(解析异常)";
        }
        return sb.toString();
    }
}
