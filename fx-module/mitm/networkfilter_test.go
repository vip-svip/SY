package main

import (
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func requestForFilter(target, referer, dest, accept string) *http.Request {
	u, err := url.Parse(target)
	if err != nil {
		panic(err)
	}
	req := &http.Request{Method: http.MethodGet, URL: u, Header: make(http.Header), Host: u.Host}
	if referer != "" {
		req.Header.Set("Referer", referer)
	}
	if dest != "" {
		req.Header.Set("Sec-Fetch-Dest", dest)
	}
	if accept != "" {
		req.Header.Set("Accept", accept)
	}
	return req
}

func TestABPThirdPartyRuleDoesNotBlockFirstPartyVisit(t *testing.T) {
	rule, ok := parseABPNetworkRule("||faceporn.com^$third-party")
	if !ok {
		t.Fatal("expected contextual third-party rule to parse")
	}
	if rule.matches(requestForFilter("https://faceporn.com/video", "", "document", "text/html")) {
		t.Fatal("third-party rule blocked a direct visit without a referrer")
	}
	if rule.matches(requestForFilter("https://faceporn.com/assets/ad.js", "https://faceporn.com/watch", "script", "application/javascript")) {
		t.Fatal("third-party rule blocked same-site resource")
	}
	if !rule.matches(requestForFilter("https://faceporn.com/ads.js", "https://example.net/article", "script", "application/javascript")) {
		t.Fatal("third-party ad request did not match")
	}
}

func TestABPPopupRuleRequiresCrossSiteDocumentNavigation(t *testing.T) {
	rule, ok := parseABPNetworkRule("||benaughty.com^$popup")
	if !ok {
		t.Fatal("expected popup rule to parse")
	}
	if rule.matches(requestForFilter("https://benaughty.com/", "", "document", "text/html")) {
		t.Fatal("popup rule blocked a direct navigation without source context")
	}
	if rule.matches(requestForFilter("https://benaughty.com/", "https://benaughty.com/profile", "document", "text/html")) {
		t.Fatal("popup rule blocked same-site navigation")
	}
	if rule.matches(requestForFilter("https://benaughty.com/ad.js", "https://pornhub.com/watch", "script", "application/javascript")) {
		t.Fatal("popup rule matched a script instead of a document navigation")
	}
	if !rule.matches(requestForFilter("https://benaughty.com/", "https://pornhub.com/watch", "document", "text/html")) {
		t.Fatal("cross-site document popunder did not match")
	}
}

func TestABPSourceDomainScopeAndAllowlistException(t *testing.T) {
	block, ok := parseABPNetworkRule("||temu.com^$popup,domain=pornproxy.art")
	if !ok {
		t.Fatal("contextual popup rule should parse")
	}
	allowed, ok := parseABPNetworkRule("@@||temu.com^$popup,domain=pornproxy.art")
	if !ok || !allowed.exception {
		t.Fatal("matching allowlist exception should parse")
	}
	blockedReq := requestForFilter("https://temu.com/", "https://pornproxy.art/video", "document", "text/html")
	otherReq := requestForFilter("https://temu.com/", "https://xvideos.com/video", "document", "text/html")
	if !block.matches(blockedReq) || block.matches(otherReq) {
		t.Fatal("domain= source scoping was lost")
	}
	e := &engine{networkCached: []networkFilterRule{block, allowed}, networkLoadedAt: time.Now()}
	if _, matched := e.applyNetworkFilters(blockedReq); matched {
		t.Fatal("allowlist exception failed to override matching contextual block")
	}
	if _, matched := e.applyNetworkFilters(otherReq); matched {
		t.Fatal("site-scoped block leaked to an unrelated source site")
	}
}

func TestABPHostlessSourceScopedExceptionProtectsAPIPath(t *testing.T) {
	block, ok := parseABPNetworkRule("||api.external.example/api/models$xmlhttprequest")
	if !ok {
		t.Fatal("path-scoped request block should parse")
	}
	allow, ok := parseABPNetworkRule("@@/api/models?$domain=tik.porn")
	if !ok || !allow.exception || allow.host != "" {
		t.Fatal("source-scoped hostless exception should parse as an exception only")
	}
	req := requestForFilter("https://api.external.example/api/models?take=20", "https://tik.porn/watch", "empty", "application/json")
	e := &engine{networkCached: []networkFilterRule{block, allow}, networkLoadedAt: time.Now()}
	if _, matched := e.applyNetworkFilters(req); matched {
		t.Fatal("source-scoped API exception did not protect the matching request")
	}
	other := requestForFilter("https://api.external.example/api/models?take=20", "https://example.net/", "empty", "application/json")
	if _, matched := e.applyNetworkFilters(other); !matched {
		t.Fatal("source-scoped exception leaked to an unrelated page")
	}
}

func TestABPApexContentDomainNeedsContextOrAdIntent(t *testing.T) {
	if _, ok := parseABPNetworkRule("||xvideos.com^"); ok {
		t.Fatal("unscoped apex content site should be rejected by the conservative safety guard")
	}
	if _, ok := parseABPNetworkRule("||ads.example.com^"); !ok {
		t.Fatal("explicit ad subdomain should remain supported")
	}
	if _, ok := parseABPNetworkRule("||faceporn.com^$third-party"); !ok {
		t.Fatal("root domain with third-party context should remain supported")
	}
}

func TestABPSameSiteApexRequestRuleIsRejectedEvenWithDomainModifier(t *testing.T) {
	for _, line := range []string{
		"||thegay.com^$script,domain=thegay.com",
		"||xvideos.com^$script,subdocument,domain=xvideos.com|youporngay.com",
	} {
		if _, ok := parseABPNetworkRule(line); ok {
			t.Errorf("same-site apex resource rule could break the site's own scripts/player and must be rejected: %q", line)
		}
	}
	for _, line := range []string{
		"||thegay.com/assets/ad.js$script,domain=thegay.com",
		"||thegay.com^$third-party",
		"||popup.example.net^$popup,domain=thegay.com",
	} {
		if _, ok := parseABPNetworkRule(line); !ok {
			t.Errorf("path- or context-scoped filter should remain supported: %q", line)
		}
	}
}

func TestABPPathFilterDoesNotWidenToWholeHost(t *testing.T) {
	rule, ok := parseABPNetworkRule("||xvideos.com/ads/banner.js$script")
	if !ok {
		t.Fatal("path-specific network rule should parse")
	}
	if rule.matches(requestForFilter("https://xvideos.com/watch/123", "https://example.net/", "document", "text/html")) {
		t.Fatal("a path-specific rule unexpectedly matched non-ad content")
	}
	if !rule.matches(requestForFilter("https://xvideos.com/ads/banner.js", "https://example.net/", "script", "application/javascript")) {
		t.Fatal("path-specific ad script rule did not match")
	}
}

func TestABPUnsupportedModifiersFailClosed(t *testing.T) {
	for _, line := range []string{
		"||example.com^$redirect=empty",
		"||example.com^$removeparam=utm_source",
		"||example.com^$unknown-option",
		"/ads/[0-9]+/",
	} {
		if _, ok := parseABPNetworkRule(line); ok {
			t.Errorf("unsupported syntax was accepted and might be broadened: %q", line)
		}
	}
}

func TestABPUnscopedWholeContentHostRulesFailClosed(t *testing.T) {
	for _, line := range []string{
		"||www.xvideos.com^",
		"||xvideos.com^$script",
		"||www.pornhub.com^$image",
		"||xnxx.com^$document",
	} {
		if _, ok := parseABPNetworkRule(line); ok {
			t.Errorf("unscoped whole-host rule could break adult-site content and must be rejected: %q", line)
		}
	}
	for _, line := range []string{
		"||ads.example.com^",
		"||www.xvideos.com/ads/banner.js$script",
		"||xvideos.com^$third-party",
		"||popup.example.net^$popup",
	} {
		if _, ok := parseABPNetworkRule(line); !ok {
			t.Errorf("specific/contextual ad rule should remain supported: %q", line)
		}
	}
}

func TestNetworkRuleIndexReturnsOnlyHostAndParentBuckets(t *testing.T) {
	a, ok := parseABPNetworkRule("||ads.example.com^")
	if !ok {
		t.Fatal("ad host fixture should parse")
	}
	b, ok := parseABPNetworkRule("||example.com/ads.js$script")
	if !ok {
		t.Fatal("path-specific parent host fixture should parse")
	}
	c, ok := parseABPNetworkRule("||ads.other.example^")
	if !ok {
		t.Fatal("other host fixture should parse")
	}
	e := &engine{networkByHost: map[string][]networkFilterRule{
		a.host: {a}, b.host: {b}, c.host: {c},
	}}
	global, ok := parseABPNetworkRule("@@/api/models?$domain=tik.porn")
	if !ok || !global.exception || global.host != "" {
		t.Fatal("expected safe source-scoped hostless exception")
	}
	e.networkGlobal = []networkFilterRule{global}
	got := e.matchingNetworkFilterRules("cdn.ads.example.com", nil)
	if len(got) != 3 {
		t.Fatalf("expected global exception plus exact and parent-domain candidates (3), got %d", len(got))
	}
	foundGlobal := false
	for _, rule := range got {
		if rule.host == "" && rule.exception {
			foundGlobal = true
		}
		if rule.host == c.host {
			t.Fatal("unrelated host rule appeared in candidate index")
		}
	}
	if !foundGlobal {
		t.Fatal("source-scoped global exception missing from indexed candidates")
	}
}

func TestBundledAdultRequestRulesLoadOfflineAndRespectAllowlist(t *testing.T) {
	pg := t.TempDir()
	mod := t.TempDir()
	if err := os.MkdirAll(filepath.Join(mod, "rulefiles"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(pg, "rulefiles-user"), 0700); err != nil {
		t.Fatal(err)
	}
	settings := "[list:rule]\n" +
		"builtin://AdultSite_AdServers.txt|成人广告服务器|1\n" +
		"builtin://AdultSite_Allowlist.txt|成人资源白名单|1\n" +
		"builtin://AdultSite_AdServersPopup.txt|成人广告弹窗|1\n" +
		"builtin://AdultSite_SitePopup.txt|成人站点弹窗|1\n" +
		"builtin://AdultSite_ThirdPartyPopup.txt|成人第三方弹窗|1\n"
	if err := os.WriteFile(filepath.Join(pg, "settings.conf"), []byte(settings), 0600); err != nil {
		t.Fatal(err)
	}
	serverRules := "||ads.example^$third-party\n||api.external.example/api/models$xmlhttprequest\n"
	if err := os.WriteFile(filepath.Join(mod, "rulefiles", "AdultSite_AdServers.txt"), []byte(serverRules), 0600); err != nil {
		t.Fatal(err)
	}
	allowRules := "@@/api/models?$domain=tik.porn\n"
	if err := os.WriteFile(filepath.Join(mod, "rulefiles", "AdultSite_Allowlist.txt"), []byte(allowRules), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PG", pg)
	e := &engine{modDir: mod}
	loaded := e.loadNetworkFilterRules()
	if len(loaded) < 3 {
		t.Fatalf("expected bundled request/exception rules to load without a subscription cache, got %d", len(loaded))
	}
	adReq := requestForFilter("https://ads.example/pixel", "https://content.example/watch", "image", "image/webp")
	if _, matched := e.applyNetworkFilters(adReq); !matched {
		t.Fatal("bundled third-party ad server rule was not applied")
	}
	apiReq := requestForFilter("https://api.external.example/api/models?take=20", "https://tik.porn/watch", "empty", "application/json")
	if _, matched := e.applyNetworkFilters(apiReq); matched {
		t.Fatal("bundled source-scoped allowlist did not override its matching API request")
	}
	otherReq := requestForFilter("https://api.external.example/api/models?take=20", "https://example.net/watch", "empty", "application/json")
	if _, matched := e.applyNetworkFilters(otherReq); !matched {
		t.Fatal("source-scoped exception leaked to a different source site")
	}
}

func TestBundledAdultRequestListCanBeDisabled(t *testing.T) {
	pg := t.TempDir()
	mod := t.TempDir()
	if err := os.MkdirAll(filepath.Join(mod, "rulefiles"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(pg, "settings.conf"), []byte("[list:rule]\nbuiltin://AdultSite_AdServers.txt|成人广告服务器|0\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(mod, "rulefiles", "AdultSite_AdServers.txt"), []byte("||ads.example^$third-party\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PG", pg)
	e := &engine{modDir: mod}
	if got := e.loadNetworkFilterRules(); len(got) != 0 {
		t.Fatalf("disabled built-in list unexpectedly loaded %d rules", len(got))
	}
}

func TestBundledAdultNetworkRulesLoadWithoutRemoteCache(t *testing.T) {
	mod := t.TempDir()
	pg := t.TempDir()
	if err := os.MkdirAll(filepath.Join(mod, "rulefiles"), 0700); err != nil {
		t.Fatal(err)
	}
	conf := "[list:rule]\n" +
		"builtin://AdultSite_AdServers.txt|adult ads|1\n" +
		"builtin://AdultSite_Allowlist.txt|adult allowlist|1\n" +
		"builtin://AdultSite_AdServersPopup.txt|adult popup|1\n" +
		"builtin://AdultSite_SitePopup.txt|site popup|1\n" +
		"builtin://AdultSite_ThirdPartyPopup.txt|third-party popup|1\n" +
		"builtin://AdultSite_RequestRules.txt|site requests|1\n" +
		"builtin://AdultSite_ThirdParty.txt|third-party requests|1\n" +
		"builtin://AdultSite_AdServers.txt|duplicate|1\n" +
		"builtin://NotWhitelisted.txt|untrusted|1\n"
	if err := os.WriteFile(filepath.Join(pg, "settings.conf"), []byte(conf), 0600); err != nil {
		t.Fatal(err)
	}
	files := map[string]string{
		"AdultSite_AdServers.txt":       "||ads.example^$third-party\n",
		"AdultSite_Allowlist.txt":       "@@/api/models?$domain=tik.porn\n",
		"AdultSite_AdServersPopup.txt":  "||popup.example^$popup\n",
		"AdultSite_SitePopup.txt":       "||click.example/path$popup,domain=pornhub.com\n",
		"AdultSite_ThirdPartyPopup.txt": "||track.example/visit$popup,third-party\n",
		"AdultSite_RequestRules.txt":    "||static.pornhub.com/ads/ad.js$script,domain=pornhub.com\n",
		"AdultSite_ThirdParty.txt":      "||cdn.adnetwork.example/banner/$third-party\n",
	}
	for name, body := range files {
		if err := os.WriteFile(filepath.Join(mod, "rulefiles", name), []byte(body), 0600); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PG", pg)
	e := &engine{modDir: mod}
	rules := e.loadNetworkFilterRules()
	if len(rules) != 7 {
		t.Fatalf("expected 7 bundled rules and no duplicate/untrusted source, got %d", len(rules))
	}
	var foundAllow bool
	for _, r := range rules {
		if r.exception && r.path != nil && len(r.includeDomains) > 0 {
			foundAllow = true
		}
	}
	if !foundAllow {
		t.Fatal("bundled source-domain exception missing from request engine")
	}
}

func TestBundledAdultSourceSnapshotsParseOffline(t *testing.T) {
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	modDir, err := filepath.Abs(filepath.Join(cwd, ".."))
	if err != nil {
		t.Fatal(err)
	}
	pg := t.TempDir()
	lines := []string{"[list:rule]"}
	for _, name := range []string{
		"AdultSite_AdServers.txt",
		"AdultSite_Allowlist.txt",
		"AdultSite_AdServersPopup.txt",
		"AdultSite_SitePopup.txt",
		"AdultSite_ThirdPartyPopup.txt",
		"AdultSite_RequestRules.txt",
		"AdultSite_ThirdParty.txt",
	} {
		lines = append(lines, "builtin://"+name+"|测试本地快照|1")
	}
	if err := os.WriteFile(filepath.Join(pg, "settings.conf"), []byte(strings.Join(lines, "\n")+"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PG", pg)
	e := &engine{modDir: modDir}
	rules := e.loadNetworkFilterRules()
	if len(rules) < 500 {
		t.Fatalf("too few bundled EasyList adult request rules parsed offline: %d", len(rules))
	}
	var exceptions, popup, pathRules int
	for _, rule := range rules {
		if rule.exception {
			exceptions++
		}
		if rule.popup {
			popup++
		}
		if rule.path != nil {
			pathRules++
		}
	}
	if exceptions == 0 || popup < 20 || pathRules < 100 {
		t.Fatalf("request rule categories incomplete: total=%d exceptions=%d popup=%d path=%d", len(rules), exceptions, popup, pathRules)
	}
	t.Logf("bundled offline adult request parser: total=%d exceptions=%d popup=%d path=%d", len(rules), exceptions, popup, pathRules)
}
