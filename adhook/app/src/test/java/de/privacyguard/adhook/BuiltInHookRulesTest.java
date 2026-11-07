package de.privacyguard.adhook;

import org.junit.Test;

import java.util.Collections;

import static org.junit.Assert.*;

public class BuiltInHookRulesTest {
    @Test
    public void knownPackageMatchesBuiltInFeedTokenWhenFeedEnabled() {
        UnifiedHookConfigParser.Target target = new UnifiedHookConfigParser.Target(
                false, true, false, false, false, false, false, false, false, false, Collections.emptyMap());
        assertTrue(BuiltInHookRules.matches("tv.danmaku.bili", "com.example.Ad_Container", target));
    }

    @Test
    public void builtInRuleDoesNotCrossPackageBoundary() {
        UnifiedHookConfigParser.Target target = new UnifiedHookConfigParser.Target(
                false, true, false, false, false, false, false, false, false, false, Collections.emptyMap());
        assertFalse(BuiltInHookRules.matches("com.example.other", "ad_container", target));
    }

    @Test
    public void disabledCategoryDoesNotApplyItsBuiltInRules() {
        UnifiedHookConfigParser.Target target = new UnifiedHookConfigParser.Target(
                true, false, false, false, false, false, false, false, false, false, Collections.emptyMap());
        assertFalse(BuiltInHookRules.matches("tv.danmaku.bili", "ad_container", target));
    }

    @Test
    public void splashRuleRequiresSplashToggle() {
        UnifiedHookConfigParser.Target target = new UnifiedHookConfigParser.Target(
                false, true, false, false, false, false, false, false, false, false, Collections.emptyMap());
        assertFalse(BuiltInHookRules.matches("com.tencent.mm", "launchscreenad_view", target));
    }

    @Test
    public void explicitSplashSignatureDoesNotFallThroughToFeedWhenSplashIsDisabled() {
        UnifiedHookConfigParser.Target feedOnly = new UnifiedHookConfigParser.Target(
                false, true, false, false, false, false, false, false, false, false, Collections.emptyMap());
        assertFalse(BuiltInHookRules.matches("com.tencent.mm", "launchscreenad_view", feedOnly));
        assertTrue(BuiltInHookRules.matches("com.tencent.mm", "ordinary_ad_container", feedOnly));
    }

    @Test
    public void explicitOverlaySignatureRequiresOverlayToggle() {
        UnifiedHookConfigParser.Target feedOnly = new UnifiedHookConfigParser.Target(
                false, true, false, false, false, false, false, false, false, false, Collections.emptyMap());
        UnifiedHookConfigParser.Target overlayOnly = new UnifiedHookConfigParser.Target(
                false, false, true, false, false, false, false, false, false, false, Collections.emptyMap());
        assertFalse(BuiltInHookRules.matches("tv.danmaku.bili", "rewarded_ad_dialog", feedOnly));
        assertTrue(BuiltInHookRules.matches("tv.danmaku.bili", "rewarded_ad_dialog", overlayOnly));
    }

    @Test
    public void addedWeiboPresetMatchesOnlyWhenItsFeedCategoryIsEnabled() {
        UnifiedHookConfigParser.Target enabled = new UnifiedHookConfigParser.Target(
                false, true, false, false, false, false, false, false, false, false, Collections.emptyMap());
        UnifiedHookConfigParser.Target disabled = new UnifiedHookConfigParser.Target(
                true, false, false, false, false, false, false, false, false, false, Collections.emptyMap());
        assertTrue(BuiltInHookRules.matches("com.sina.weibo", "com.sina.weibo.feed_ad_card", enabled));
        assertFalse(BuiltInHookRules.matches("com.sina.weibo", "com.sina.weibo.feed_ad_card", disabled));
    }

    @Test
    public void addedJdPresetDoesNotTreatGenericPromotionTextAsAnAd() {
        UnifiedHookConfigParser.Target target = new UnifiedHookConfigParser.Target(
                false, true, false, false, false, false, false, false, false, false, Collections.emptyMap());
        assertFalse(BuiltInHookRules.matches("com.jingdong.app.mall", "com.jd.PromotionView", target));
        assertTrue(BuiltInHookRules.matches("com.jingdong.app.mall", "com.jd.promotion_banner", target));
    }


    @Test
    public void additionalAppPresetsArePackageScopedAndCategoryScoped() {
        UnifiedHookConfigParser.Target enabled = new UnifiedHookConfigParser.Target(
                false, true, false, false, false, false, false, false, false, false, Collections.emptyMap());
        UnifiedHookConfigParser.Target disabled = new UnifiedHookConfigParser.Target(
                true, false, false, false, false, false, false, false, false, false, Collections.emptyMap());
        assertTrue(BuiltInHookRules.matches("com.baidu.searchbox", "com.baidu.searchbox.feed_ad_card", enabled));
        assertTrue(BuiltInHookRules.matches("com.sankuai.meituan", "com.meituan.ad_banner", enabled));
        assertTrue(BuiltInHookRules.matches("com.tencent.qqlive", "com.tencent.video.ad_container", enabled));
        assertFalse(BuiltInHookRules.matches("com.example.unrelated", "com.baidu.searchbox.feed_ad_card", enabled));
        assertFalse(BuiltInHookRules.matches("com.baidu.searchbox", "com.baidu.searchbox.feed_ad_card", disabled));
    }


    @Test
    public void everyPublishedPresetHasAnActiveFeedSelector() {
        String[] packages = {
                "com.tencent.mm", "com.ss.android.ugc.aweme", "tv.danmaku.bili",
                "com.taobao.taobao", "com.zhihu.android", "com.xingin.xhs",
                "com.sina.weibo", "com.tencent.mobileqq", "com.tencent.news",
                "com.ss.android.article.news", "com.baidu.tieba", "com.jingdong.app.mall",
                "com.smile.gifmaker", "com.kuaishou.nebula", "com.eg.android.AlipayGphone",
                "com.baidu.searchbox", "com.sankuai.meituan", "com.qiyi.video",
                "com.youku.phone", "com.tencent.qqlive", "com.ximalaya.ting.android",
                "com.UCMobile", "com.ss.android.ugc.aweme.lite", "com.ss.android.article.lite",
                "com.xunmeng.pinduoduo", "com.taobao.idlefish", "com.baidu.netdisk",
                "com.tencent.mtt", "com.tencent.qqmusic", "com.netease.cloudmusic",
                "com.dragon.read", "com.tencent.wework"
        };
        UnifiedHookConfigParser.Target target = new UnifiedHookConfigParser.Target(
                false, true, false, false, false, false, false, false, false, false, Collections.emptyMap());
        for (String pkg : packages) {
            assertTrue("missing or inactive preset for " + pkg,
                    BuiltInHookRules.matches(pkg, "com.example.ad_container", target));
        }
    }

}
