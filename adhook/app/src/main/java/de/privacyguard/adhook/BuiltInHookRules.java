package de.privacyguard.adhook;

import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * Conservative built-in app-specific ad rules.
 * Tokens are only evaluated inside the listed app package and when the
 * matching category toggle is enabled. Broad tokens such as "ad" or "vip"
 * are intentionally excluded to reduce false positives.
 */
final class BuiltInHookRules {
    private static final Map<String, Map<String, Set<String>>> RULES;
    // Resolve explicit category evidence before generic tokens such as "ad_view".
    // Otherwise "launchscreenad_view" accidentally matches the feed token "ad_view"
    // and violates the independent splash/feed switches.
    private static final String[] SPLASH_EVIDENCE = {
            "splash", "launch_ad", "launchad", "launchscreenad", "open_ad", "openad", "welcome_ad"
    };
    private static final String[] OVERLAY_EVIDENCE = {
            "interstitial", "rewardedad", "rewarded_ad", "fullscreenad",
            "full_screen_ad", "ad_dialog", "ad_popup", "adpopup", "overlay_ad"
    };

    static {
        Map<String, Map<String, Set<String>>> apps = new HashMap<>();
        add(apps, "com.tencent.mm",
                new String[]{"splash_ad", "launch_ad", "welcome_ad"},
                new String[]{"ad_view", "ad_container", "ad_banner", "banner_ad"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.ss.android.ugc.aweme",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "tv.danmaku.bili",
                new String[]{"splash_ad", "launch_ad", "splash_container"},
                new String[]{"ad_view", "ad_container", "ad_card", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.taobao.taobao",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "ad_banner", "banner_ad"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.zhihu.android",
                new String[]{"splash_ad", "launch_ad"},
                new String[]{"ad_view", "ad_container", "ad_card", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.xingin.xhs",
                new String[]{"splash_ad", "launch_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});

        // Common Chinese apps: keep rules limited to explicit ad resource/class tokens.
        // These are best-effort compatibility hints, not guaranteed app-version signatures.
        add(apps, "com.sina.weibo",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner", "promoted_card"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.tencent.mobileqq",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.tencent.news",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.ss.android.article.news",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.baidu.tieba",
                new String[]{"splash_ad", "launch_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner", "promoted_card"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.jingdong.app.mall",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner", "promotion_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.smile.gifmaker",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.kuaishou.nebula",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});

        add(apps, "com.eg.android.AlipayGphone",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.baidu.searchbox",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner", "promoted_card"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.sankuai.meituan",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner", "promotion_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.qiyi.video",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.youku.phone",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.tencent.qqlive",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.ximalaya.ting.android",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.UCMobile",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});

        // Additional common Chinese apps. Keep these signatures conservative:
        // they are package-scoped evidence hints, not universal ad-block guarantees.
        add(apps, "com.ss.android.ugc.aweme.lite",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.ss.android.article.lite",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.xunmeng.pinduoduo",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner", "promotion_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.taobao.idlefish",
                new String[]{"splash_ad", "launch_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner", "promotion_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.baidu.netdisk",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.tencent.mtt",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.tencent.qqmusic",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.netease.cloudmusic",
                new String[]{"splash_ad", "launch_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.dragon.read",
                new String[]{"splash_ad", "launch_ad", "open_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner", "promotion_banner"},
                new String[]{"ad_dialog", "ad_popup"});
        add(apps, "com.tencent.wework",
                new String[]{"splash_ad", "launch_ad"},
                new String[]{"ad_view", "ad_container", "feed_ad", "ad_banner"},
                new String[]{"ad_dialog", "ad_popup"});

        Map<String, Map<String, Set<String>>> frozen = new HashMap<>();
        for (Map.Entry<String, Map<String, Set<String>>> app : apps.entrySet()) {
            Map<String, Set<String>> categories = new HashMap<>();
            for (Map.Entry<String, Set<String>> category : app.getValue().entrySet()) {
                categories.put(category.getKey(),
                        Collections.unmodifiableSet(new HashSet<>(category.getValue())));
            }
            frozen.put(app.getKey(), Collections.unmodifiableMap(categories));
        }
        RULES = Collections.unmodifiableMap(frozen);
    }

    private BuiltInHookRules() {}

    static boolean matches(String packageName, String evidence, UnifiedHookConfigParser.Target target) {
        if (packageName == null || evidence == null || target == null) return false;
        Map<String, Set<String>> categories = RULES.get(packageName);
        if (categories == null) return false;
        String normalized = evidence.toLowerCase(Locale.ROOT);
        // Category-specific signatures take precedence over overlapping generic
        // tokens. This keeps category toggles semantically independent.
        if (containsAny(normalized, SPLASH_EVIDENCE)) return target.splash;
        if (containsAny(normalized, OVERLAY_EVIDENCE)) return target.overlay;
        for (Map.Entry<String, Set<String>> category : categories.entrySet()) {
            if (!isEnabled(category.getKey(), target)) continue;
            for (String token : category.getValue()) {
                if (normalized.contains(token)) return true;
            }
        }
        return false;
    }

    private static boolean containsAny(String value, String[] tokens) {
        for (String token : tokens) if (value.contains(token)) return true;
        return false;
    }

    private static boolean isEnabled(String category, UnifiedHookConfigParser.Target target) {
        switch (category) {
            case "splash": return target.splash;
            case "feed": return target.feed;
            case "overlay": return target.overlay;
            default: return false;
        }
    }

    private static void add(Map<String, Map<String, Set<String>>> apps, String pkg,
                            String[] splash, String[] feed, String[] overlay) {
        Map<String, Set<String>> categories = new HashMap<>();
        categories.put("splash", set(splash));
        categories.put("feed", set(feed));
        categories.put("overlay", set(overlay));
        apps.put(pkg, categories);
    }

    private static Set<String> set(String[] values) {
        Set<String> result = new HashSet<>();
        Collections.addAll(result, values);
        return result;
    }
}
