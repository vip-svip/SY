package main

import (
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const maxNetworkFilterRules = 50000

var (
	abpDomainPattern = regexp.MustCompile(`(?i)^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$`)
	adIntentDomain   = regexp.MustCompile(`(?i)(^|[.-])(?:ad|ads|advert|advertising|banner|pop|popup|popunder|track|tracker|tracking|traffic|promo|promote|affiliate|aff|click|redirect|offer|exchange|impression|monetiz|campaign|sponsor|exoclick|exosrv|juicyads|trafficjunky|propellerads|hilltopads|adsterra|ero-advertising)([.-]|$)`)
)

type networkFilterRule struct {
	host           string
	path           *regexp.Regexp
	exception      bool
	thirdParty     int // 1=third-party, -1=first-party, 0=unrestricted
	popup          bool
	includeDomains []string
	excludeDomains []string
	includeTypes   map[string]bool
	excludeTypes   map[string]bool
}

// enabledNetworkSources limits URL-level ABP parsing to rulesets which actually
// carry request filters. Pure DNS/hosts collections are already compiled into the
// routing layer and may contain millions of domain-only records; reading them a
// second time in every MITM path adds cost without preserving any extra semantics.
func enabledNetworkSource(url string) bool {
	u := strings.ToLower(url)
	for _, marker := range []string{
		// Adult-site element hiding and general cosmetic-only lists are handled by
		// cosmetic.go. Request-level parsing is restricted to actual network/popup
		// lists so large element catalogs are not pointlessly re-parsed here.
		"easylist_adult/adult_adservers.txt", "easylist_adult/adult_adservers_popup.txt",
		"easylist_adult/adult_allowlist.txt", "easylist_adult/adult_specific_block.txt",
		"easylist_adult/adult_specific_block_popup.txt", "easylist_adult/adult_thirdparty.txt",
		"easylist_adult/adult_thirdparty_popup.txt", "adult_annoyance_list.txt",
		"easylist-downloads.adblockplus.org/easylist",
		"easylist-downloads.adblockplus.org/easyprivacy", "easylist-downloads.adblockplus.org/antiadblockfilters",
		"easylist-downloads.adblockplus.org/easylistchina", "easylist.to/easylist/",
		"ublockorigin/uassets/filters/", "filters.adtidy.org/extension/ublock/filters/11.txt",
		"filters.adtidy.org/extension/ublock/filters/13.txt", "filters.adtidy.org/extension/ublock/filters/14.txt",
		"filters.adtidy.org/extension/ublock/filters/207", "filters.adtidy.org/extension/ublock/filters/224.txt",
		"filters.adtidy.org/extension/ublock/filters/260.txt", "tg-twilight/awavenue-ads-rule/",
		"fenglingback/cxfllist/", "runningcheese-firefox/master/restore/adblock_popup.txt",
		"noappdownload.txt", "dandelionsprout/adfilt/master/stayingonbrowser/",
		"yokoffing/filterlists/",
	} {
		if strings.Contains(u, marker) {
			return true
		}
	}
	return false
}

func parseABPNetworkRule(raw string) (networkFilterRule, bool) {
	line := strings.TrimSpace(strings.TrimSuffix(raw, "\r"))
	if line == "" || strings.HasPrefix(line, "!") || strings.HasPrefix(line, "[") || strings.HasPrefix(line, "#") ||
		strings.Contains(line, "##") || strings.Contains(line, "#@#") || strings.Contains(line, "#?#") ||
		strings.Contains(line, "#$#") || strings.Contains(line, "#%#") {
		return networkFilterRule{}, false
	}
	rule := networkFilterRule{includeTypes: map[string]bool{}, excludeTypes: map[string]bool{}}
	if strings.HasPrefix(line, "@@") {
		rule.exception = true
		line = strings.TrimSpace(line[2:])
	}
	pattern := line
	options := ""
	if i := strings.IndexByte(line, '$'); i >= 0 {
		pattern, options = line[:i], line[i+1:]
	}
	if !strings.HasPrefix(pattern, "||") {
		// EasyList adult_allowlist contains a small number of source-scoped path
		// exceptions (for example @@/api/models?$domain=tik.porn). These are safe
		// to support only as exceptions and only when a source domain is specified;
		// they must never become global block rules.
		if !rule.exception || !strings.HasPrefix(pattern, "/") || !strings.Contains(strings.ToLower(options), "domain=") {
			return networkFilterRule{}, false
		}
		quoted := regexp.QuoteMeta(pattern)
		quoted = strings.ReplaceAll(quoted, `\*`, `.*`)
		if len(quoted) > 4096 {
			return networkFilterRule{}, false
		}
		compiled, err := regexp.Compile("(?i)^" + quoted)
		if err != nil {
			return networkFilterRule{}, false
		}
		rule.path = compiled
	} else {
		rest := strings.TrimPrefix(pattern[2:], "*.")
		cut := len(rest)
		for i, c := range rest {
			if c == '/' || c == '^' || c == '*' || c == '|' {
				cut = i
				break
			}
		}
		host := strings.ToLower(strings.TrimSuffix(rest[:cut], "."))
		if strings.HasPrefix(host, "*.") {
			host = host[2:]
		}
		if !abpDomainPattern.MatchString(host) || strings.Contains(host, "..") {
			return networkFilterRule{}, false
		}
		rule.host = host
		pathPattern := rest[cut:]
		// A bare ^ after the hostname is an ABP separator, not a URL path.
		if strings.HasPrefix(pathPattern, "^") {
			pathPattern = pathPattern[1:]
		}
		if pathPattern != "" {
			// Do not broaden a path-constrained filter to its entire hostname.
			// Wildcards are converted to a simple regular expression after escaping.
			if !strings.HasPrefix(pathPattern, "/") && !strings.HasPrefix(pathPattern, "*") {
				return networkFilterRule{}, false
			}
			quoted := regexp.QuoteMeta(pathPattern)
			quoted = strings.ReplaceAll(quoted, `\*`, `.*`)
			quoted = strings.ReplaceAll(quoted, `\^`, `(?:[^A-Za-z0-9_.%-]|$)`)
			if len(quoted) > 4096 {
				return networkFilterRule{}, false
			}
			compiled, err := regexp.Compile("(?i)^" + quoted)
			if err != nil {
				return networkFilterRule{}, false
			}
			rule.path = compiled
		}
	}
	knownTypes := map[string]bool{
		"script": true, "image": true, "stylesheet": true, "object": true, "xmlhttprequest": true,
		"xhr": true, "subdocument": true, "document": true, "media": true, "font": true,
		"other": true, "ping": true, "websocket": true, "webrtc": true,
	}
	for _, rawOpt := range strings.Split(options, ",") {
		opt := strings.ToLower(strings.TrimSpace(rawOpt))
		if opt == "" || opt == "important" || opt == "match-case" {
			continue
		}
		if opt == "badfilter" || strings.HasPrefix(opt, "redirect=") || strings.HasPrefix(opt, "redirect-rule=") ||
			strings.HasPrefix(opt, "removeparam") || strings.HasPrefix(opt, "csp=") || strings.HasPrefix(opt, "replace=") {
			return networkFilterRule{}, false
		}
		if opt == "third-party" || opt == "3p" {
			rule.thirdParty = 1
			continue
		}
		if opt == "~third-party" || opt == "~3p" {
			rule.thirdParty = -1
			continue
		}
		if opt == "popup" {
			rule.popup = true
			continue
		}
		if strings.HasPrefix(opt, "domain=") {
			for _, rawDomain := range strings.Split(strings.TrimPrefix(opt, "domain="), "|") {
				d := strings.TrimSpace(rawDomain)
				if d == "" {
					return networkFilterRule{}, false
				}
				neg := strings.HasPrefix(d, "~")
				if neg {
					d = d[1:]
				}
				d = strings.TrimPrefix(strings.ToLower(d), "*.")
				if !abpDomainPattern.MatchString(d) {
					return networkFilterRule{}, false
				}
				if neg {
					rule.excludeDomains = append(rule.excludeDomains, d)
				} else {
					rule.includeDomains = append(rule.includeDomains, d)
				}
			}
			continue
		}
		neg := strings.HasPrefix(opt, "~")
		name := strings.TrimPrefix(opt, "~")
		if !knownTypes[name] {
			// Unsupported modifiers have conditions we cannot reproduce reliably;
			// skip the whole rule instead of silently widening its scope.
			return networkFilterRule{}, false
		}
		if neg {
			rule.excludeTypes[name] = true
		} else {
			rule.includeTypes[name] = true
		}
	}
	// Safety guard: a plain apex-domain rule without an ad-like name, request type,
	// first/third-party condition, or source-domain scope may be a real adult site.
	// Such rules must not blank a whole site when imported from a broad filter list.
	// Never turn a whole-host request rule into site breakage. A common filter-list
	// pitfall is accepting `||www.content-site.example^` merely because it has three
	// labels, or accepting `||content-site.example^$script` and then breaking every
	// script needed by the player. Without a path, explicit first/third-party context,
	// popup navigation, or source-domain scope, only an unmistakable ad/track hostname
	// is admitted. Resource-type modifiers alone do not make a whole-host rule safe.
	contextual := rule.path != nil || rule.thirdParty != 0 || rule.popup || len(rule.includeDomains) > 0 || len(rule.excludeDomains) > 0
	if !rule.exception && !contextual && !adIntentDomain.MatchString(rule.host) {
		return networkFilterRule{}, false
	}
	// A source-domain modifier alone is not enough to make a whole-host rule
	// safe when the target host is itself one of the sites whose content must
	// remain available. For example, `||thegay.com^$script,domain=thegay.com`
	// can disable the site's own player scripts. Accept this pattern only when
	// the destination has an explicit path, the request is cross-site/popup
	// scoped, or the host unmistakably names an ad/track endpoint.
	if !rule.exception && rule.path == nil && rule.thirdParty == 0 && !rule.popup &&
		!adIntentDomain.MatchString(rule.host) {
		for _, domain := range rule.includeDomains {
			if domainSuffixMatch(domain, rule.host) || domainSuffixMatch(rule.host, domain) {
				return networkFilterRule{}, false
			}
		}
	}
	return rule, true
}

func siteKey(host string) string {
	host = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(host)), ".")
	labels := strings.Split(host, ".")
	if len(labels) <= 2 {
		return host
	}
	twoLevel := map[string]bool{
		"co.uk": true, "org.uk": true, "ac.uk": true, "gov.uk": true, "com.au": true,
		"net.au": true, "org.au": true, "co.nz": true, "org.nz": true, "co.jp": true,
		"ne.jp": true, "or.jp": true, "com.cn": true, "net.cn": true, "org.cn": true,
		"gov.cn": true, "com.sg": true, "com.hk": true, "com.tw": true, "co.kr": true,
	}
	suffix := labels[len(labels)-2] + "." + labels[len(labels)-1]
	need := 2
	if twoLevel[suffix] {
		need = 3
	}
	if len(labels) < need {
		return host
	}
	return strings.Join(labels[len(labels)-need:], ".")
}

func domainSuffixMatch(host, domain string) bool {
	host = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(host)), ".")
	domain = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")
	return host != "" && domain != "" && (host == domain || strings.HasSuffix(host, "."+domain))
}

func requestResourceTypes(req *http.Request) map[string]bool {
	got := map[string]bool{}
	if req == nil {
		return got
	}
	dest := strings.ToLower(strings.TrimSpace(req.Header.Get("Sec-Fetch-Dest")))
	switch dest {
	case "document":
		got["document"] = true
	case "iframe", "frame", "embed", "object":
		got["subdocument"] = true
	case "script", "worker", "serviceworker":
		got["script"] = true
	case "image", "img":
		got["image"] = true
	case "style":
		got["stylesheet"] = true
	case "font":
		got["font"] = true
	case "audio", "video", "track":
		got["media"] = true
	}
	accept := strings.ToLower(req.Header.Get("Accept"))
	if strings.Contains(accept, "text/html") || strings.Contains(accept, "application/xhtml+xml") {
		got["document"] = true
	}
	if strings.Contains(accept, "image/") {
		got["image"] = true
	}
	if strings.Contains(accept, "text/css") {
		got["stylesheet"] = true
	}
	if strings.Contains(accept, "javascript") || strings.Contains(accept, "ecmascript") {
		got["script"] = true
	}
	if strings.Contains(accept, "font/") || strings.Contains(accept, "woff") {
		got["font"] = true
	}
	if strings.Contains(accept, "audio/") || strings.Contains(accept, "video/") {
		got["media"] = true
	}
	if strings.Contains(accept, "application/json") || strings.Contains(accept, "text/plain") || strings.Contains(accept, "*/*") {
		got["xmlhttprequest"] = true
	}
	if strings.HasSuffix(strings.ToLower(req.URL.Path), ".js") || strings.HasSuffix(strings.ToLower(req.URL.Path), ".mjs") {
		got["script"] = true
	}
	if strings.HasSuffix(strings.ToLower(req.URL.Path), ".css") {
		got["stylesheet"] = true
	}
	if ext := strings.ToLower(filepath.Ext(req.URL.Path)); ext == ".png" || ext == ".jpg" || ext == ".jpeg" || ext == ".gif" || ext == ".webp" || ext == ".svg" || ext == ".avif" {
		got["image"] = true
	}
	if ext := strings.ToLower(filepath.Ext(req.URL.Path)); ext == ".mp4" || ext == ".webm" || ext == ".m3u8" || ext == ".mpd" || ext == ".mp3" || ext == ".aac" || ext == ".ts" {
		got["media"] = true
	}
	if len(got) == 0 {
		got["other"] = true
	}
	return got
}

func (r networkFilterRule) matches(req *http.Request) bool {
	if req == nil || req.URL == nil {
		return false
	}
	host := strings.ToLower(req.URL.Hostname())
	if r.host != "" && (host == "" || !domainSuffixMatch(host, r.host)) {
		return false
	}
	if r.path != nil {
		path := req.URL.EscapedPath()
		if r.host == "" {
			// Hostless ABP exceptions are source-domain-scoped and can apply to
			// a path on a different destination host; RequestURI includes query.
			path = req.URL.RequestURI()
		}
		if !r.path.MatchString(path) {
			return false
		}
	}
	refHost := ""
	if ref := req.Referer(); ref != "" {
		if u, err := url.Parse(ref); err == nil {
			refHost = strings.ToLower(u.Hostname())
		}
	}
	if refHost == "" {
		if origin := req.Header.Get("Origin"); origin != "" && origin != "null" {
			if u, err := url.Parse(origin); err == nil {
				refHost = strings.ToLower(u.Hostname())
			}
		}
	}
	if r.thirdParty != 0 {
		if refHost == "" {
			return false
		}
		third := siteKey(refHost) != siteKey(host)
		if (r.thirdParty == 1 && !third) || (r.thirdParty == -1 && third) {
			return false
		}
	}
	for _, domain := range r.includeDomains {
		if refHost == "" || !domainSuffixMatch(refHost, domain) {
			return false
		}
	}
	for _, domain := range r.excludeDomains {
		if refHost != "" && domainSuffixMatch(refHost, domain) {
			return false
		}
	}
	if r.popup {
		if refHost == "" || siteKey(refHost) == siteKey(host) {
			return false
		}
		types := requestResourceTypes(req)
		if !types["document"] {
			return false
		}
	}
	types := requestResourceTypes(req)
	if len(r.includeTypes) > 0 {
		matched := false
		for t := range r.includeTypes {
			if types[t] {
				matched = true
				break
			}
		}
		if !matched {
			return false
		}
	}
	for t := range r.excludeTypes {
		if types[t] {
			return false
		}
	}
	return true
}

func (e *engine) loadNetworkFilterRules() []networkFilterRule {
	if e == nil {
		return nil
	}
	e.networkMu.Lock()
	defer e.networkMu.Unlock()
	if !e.networkLoadedAt.IsZero() && time.Since(e.networkLoadedAt) < time.Second {
		return append([]networkFilterRule(nil), e.networkCached...)
	}
	pg := strings.TrimSpace(e.pgDir())
	var out []networkFilterRule
	// Built-in EasyList adult request lists are read from the module package first,
	// so adult-site popup/request filtering remains available without an internet
	// subscription refresh. Each source has its own Chinese-labelled toggle.
	builtins := []struct{ key, file string }{
		{"builtin://AdultSite_AdServers.txt", "AdultSite_AdServers.txt"},
		{"builtin://AdultSite_Allowlist.txt", "AdultSite_Allowlist.txt"},
		{"builtin://AdultSite_AdServersPopup.txt", "AdultSite_AdServersPopup.txt"},
		{"builtin://AdultSite_SitePopup.txt", "AdultSite_SitePopup.txt"},
		{"builtin://AdultSite_ThirdPartyPopup.txt", "AdultSite_ThirdPartyPopup.txt"},
		{"builtin://AdultSite_RequestRules.txt", "AdultSite_RequestRules.txt"},
		{"builtin://AdultSite_ThirdParty.txt", "AdultSite_ThirdParty.txt"},
	}
	seenLines := make(map[string]bool)
	for _, set := range builtins {
		if !e.cosmeticListEnabled(set.key) {
			continue
		}
		path := filepath.Join(e.modDir, "rulefiles", set.file)
		userCopy := filepath.Join(pg, "rulefiles-user", strings.TrimSuffix(set.file, filepath.Ext(set.file))+".txt")
		if st, err := os.Stat(userCopy); err == nil && st.Mode().IsRegular() && st.Size() > 0 && st.Size() <= cosmeticRemoteListLimit {
			path = userCopy
		}
		st, err := os.Stat(path)
		if err != nil || !st.Mode().IsRegular() || st.Size() <= 0 || st.Size() > cosmeticRemoteListLimit {
			continue
		}
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		for _, line := range strings.Split(string(data), "\n") {
			key := strings.TrimSpace(strings.TrimSuffix(line, "\r"))
			if key == "" || seenLines[key] {
				continue
			}
			seenLines[key] = true
			rule, ok := parseABPNetworkRule(key)
			if !ok {
				continue
			}
			out = append(out, rule)
			if len(out) >= maxNetworkFilterRules {
				break
			}
		}
		if len(out) >= maxNetworkFilterRules {
			break
		}
	}
	for _, source := range enabledRuleSources() {
		if !enabledNetworkSource(source) {
			continue
		}
		data, err := readVerifiedCosmeticCache(pg, source)
		if err != nil {
			continue
		}
		for _, line := range strings.Split(string(data), "\n") {
			lineKey := strings.TrimSpace(strings.TrimSuffix(line, "\r"))
			if lineKey == "" || seenLines[lineKey] {
				continue
			}
			seenLines[lineKey] = true
			rule, ok := parseABPNetworkRule(lineKey)
			if !ok {
				continue
			}
			out = append(out, rule)
			if len(out) >= maxNetworkFilterRules {
				break
			}
		}
		if len(out) >= maxNetworkFilterRules {
			break
		}
	}
	e.networkCached = append([]networkFilterRule(nil), out...)
	byHost := make(map[string][]networkFilterRule, len(out))
	var global []networkFilterRule
	for _, rule := range out {
		if rule.host == "" {
			global = append(global, rule)
			continue
		}
		byHost[rule.host] = append(byHost[rule.host], rule)
	}
	e.networkByHost = byHost
	e.networkGlobal = global
	e.networkLoadedAt = time.Now()
	return append([]networkFilterRule(nil), out...)
}

// matchingNetworkFilterRules narrows a request to exact-host and parent-domain
// buckets. Large upstream EasyList/uBlock subscriptions are otherwise an O(N)
// scan on every HTTP request. The fallback preserves directly-constructed test
// engines and handles an intentionally empty index safely.
func (e *engine) matchingNetworkFilterRules(host string, fallback []networkFilterRule) []networkFilterRule {
	if e == nil {
		return fallback
	}
	host = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(host)), ".")
	e.networkMu.Lock()
	defer e.networkMu.Unlock()
	if len(e.networkByHost) == 0 {
		return fallback
	}
	labels := strings.Split(host, ".")
	out := append([]networkFilterRule(nil), e.networkGlobal...)
	for i := 0; i <= len(labels)-2; i++ {
		suffix := strings.Join(labels[i:], ".")
		out = append(out, e.networkByHost[suffix]...)
	}
	return out
}

// pgDir resolves the runtime root independently of the package extraction path.
func (e *engine) pgDir() string {
	_ = e
	if p := strings.TrimSpace(os.Getenv("PG")); p != "" {
		return p
	}
	return "/data/adb/privacyguard"
}

func (e *engine) applyNetworkFilters(req *http.Request) (*http.Response, bool) {
	rules := e.loadNetworkFilterRules()
	if len(rules) == 0 || req == nil || req.URL == nil {
		return nil, false
	}
	rules = e.matchingNetworkFilterRules(req.URL.Hostname(), rules)
	if len(rules) == 0 {
		return nil, false
	}
	// Exceptions win over matching block filters, irrespective of list order.
	for _, rule := range rules {
		if rule.exception && rule.matches(req) {
			return nil, false
		}
	}
	for _, rule := range rules {
		if rule.exception || !rule.matches(req) {
			continue
		}
		resp := rewriteResponse(req, http.StatusNoContent, "", nil)
		resp.Header.Set("Cache-Control", "no-store")
		return resp, true
	}
	return nil, false
}
