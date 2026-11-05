package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const (
	cosmeticBodyLimit       = 4 << 20
	cosmeticRemoteListLimit = 8 << 20
	cosmeticRuleLimit       = 12000
	cosmeticCSSLimit        = 1 << 20
)

// Accept ordinary CSS selectors (including attribute selectors, descendant/child
// combinators and standard pseudo-classes) while excluding declaration blocks,
// HTML tags and CSS constructs that could escape the injected <style> element.
var safeCosmeticSelector = regexp.MustCompile(`^[A-Za-z0-9_#.*\-\[\]="'^$~|:(), >+/\\]+$`)
var safeCosmeticDomain = regexp.MustCompile(`^(?:[a-z0-9-]+|\*)(?:\.(?:[a-z0-9-]+|\*))*$`)
var cosmeticStyleSuffix = regexp.MustCompile(`(?i):style\(([^()]*)\)$`)
var safeCosmeticStyleValue = regexp.MustCompile(`(?i)^(?:none|0(?:px|em|rem|%)?|hidden|visible|(?:0|0?\.[0-9]{1,3})|rotate\(-?[0-9]{1,3}deg\)|auto|initial|unset|transparent)(?:\s*!important)?$`)

type cosmeticRule struct {
	domain       string
	selector     string
	declarations string
	exception    bool
}

func (e *engine) cosmeticListEnabled(name string) bool {
	pg := os.Getenv("PG")
	if pg == "" {
		pg = "/data/adb/privacyguard"
	}
	b, err := os.ReadFile(filepath.Join(pg, "settings.conf"))
	if err != nil {
		return false
	}
	inRules := false
	for _, raw := range strings.Split(string(b), "\n") {
		line := strings.TrimSpace(raw)
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			inRules = line == "[list:rule]"
			continue
		}
		if !inRules || line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(line, "|")
		if len(fields) >= 3 && strings.TrimSpace(fields[0]) == name && strings.TrimSpace(fields[len(fields)-1]) == "1" {
			return true
		}
	}
	return false
}

// enabledRuleSources returns HTTPS lists explicitly registered and enabled in
// [list:rule]. Network I/O never happens on an intercepted request; the updater
// owns downloads and the engines consume only checksum-verified cache.
func enabledRuleSources() []string {
	pg := os.Getenv("PG")
	if pg == "" {
		pg = "/data/adb/privacyguard"
	}
	b, err := os.ReadFile(filepath.Join(pg, "settings.conf"))
	if err != nil {
		return nil
	}
	inRules := false
	var out []string
	seen := map[string]bool{}
	for _, raw := range strings.Split(string(b), "\n") {
		line := strings.TrimSpace(raw)
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			inRules = line == "[list:rule]"
			continue
		}
		if !inRules || line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.Split(line, "|")
		if len(fields) < 3 || strings.TrimSpace(fields[len(fields)-1]) != "1" {
			continue
		}
		key := strings.TrimSpace(fields[0])
		if strings.HasPrefix(strings.ToLower(key), "https://") && !seen[key] {
			seen[key] = true
			out = append(out, key)
		}
	}
	return out
}

// enabledCosmeticSources is a narrower view than enabledRuleSources: lists that
// contain only request/domain filters must not force every HTML page through the
// cosmetic body rewrite path. Mixed EasyList/uBlock/AdGuard sources are included.
func enabledCosmeticSources() []string {
	var out []string
	for _, source := range enabledRuleSources() {
		if enabledCosmeticSource(source) {
			out = append(out, source)
		}
	}
	return out
}

func enabledCosmeticSource(source string) bool {
	u := strings.ToLower(source)
	// Known DNS/hosts-only sources do not need to make every HTML document
	// identity-encoded; known EasyList adult request-only files are handled by the
	// request engine. Unknown/user-defined sources remain eligible for cosmetics
	// so existing custom subscriptions continue to work.
	for _, marker := range []string{
		"easylist_adult/adult_adservers.txt", "easylist_adult/adult_adservers_popup.txt",
		"easylist_adult/adult_specific_block.txt", "easylist_adult/adult_specific_block_popup.txt",
		"easylist_adult/adult_thirdparty.txt", "easylist_adult/adult_thirdparty_popup.txt",
		"easylist_adult/adult_allowlist.txt",
		"filters.adtidy.org/extension/ublock/filters/11.txt",
		"adguardteam/adguardsdnsfilter/", "adguardteam/adguardsdnsfilter/master/filters/",
		"adaway.github.io/master/hosts.txt", "10007_auto/master/all", "andryou/block/raw/master/chibi",
		"hostlistsregistry/assets/filter_24.txt", "hagezi/dns-blocklists/",
		"ultimate-hosts-blacklist/yoyo.org_domains/", "yoyo.org_domains/master/domains.list",
		"easylist_adult/adult_allowlist_popup.txt",
	} {
		if strings.Contains(u, marker) {
			return false
		}
	}
	return true
}

func cksumURLKey(url string) string {
	cmd := exec.Command("cksum")
	cmd.Stdin = strings.NewReader(url)
	b, err := cmd.Output()
	if err != nil {
		return ""
	}
	fields := strings.Fields(string(b))
	if len(fields) < 1 || fields[0] == "" {
		return ""
	}
	return fields[0]
}

func readVerifiedCosmeticCache(pg, url string) ([]byte, error) {
	key := cksumURLKey(url)
	if key == "" {
		return nil, fmt.Errorf("cannot calculate subscription cache key")
	}
	base := filepath.Join(pg, "cache", "rules", key)
	st, err := os.Stat(base)
	if err != nil || !st.Mode().IsRegular() || st.Size() <= 0 || st.Size() > cosmeticRemoteListLimit {
		return nil, fmt.Errorf("no bounded cached content")
	}
	data, err := os.ReadFile(base)
	if err != nil {
		return nil, err
	}
	sumBytes, err := os.ReadFile(base + ".sha256")
	if err != nil {
		return nil, fmt.Errorf("cache digest missing")
	}
	fields := strings.Fields(string(sumBytes))
	if len(fields) == 0 || len(fields[0]) != 64 {
		return nil, fmt.Errorf("cache digest malformed")
	}
	want, err := hex.DecodeString(fields[0])
	if err != nil {
		return nil, fmt.Errorf("cache digest malformed")
	}
	got := sha256.Sum256(data)
	if !bytes.Equal(want, got[:]) {
		return nil, fmt.Errorf("cache digest mismatch")
	}
	return data, nil
}

func sanitizeCosmeticDomainList(raw string) (string, bool) {
	raw = strings.ToLower(strings.TrimSpace(raw))
	if raw == "" {
		return "", true
	}
	items := strings.Split(raw, ",")
	for _, item := range items {
		item = strings.TrimSpace(item)
		if item == "" {
			return "", false
		}
		item = strings.TrimPrefix(item, "~")
		if item == "" || !safeCosmeticDomain.MatchString(item) || strings.Contains(item, "..") {
			return "", false
		}
	}
	return raw, true
}

func sanitizeCosmeticSelector(raw string) (selector, declarations string, ok bool) {
	selector = strings.TrimSpace(raw)
	if m := cosmeticStyleSuffix.FindStringSubmatch(selector); len(m) == 2 {
		declarations, ok = sanitizeCosmeticDeclarations(m[1])
		if !ok {
			return "", "", false
		}
		selector = strings.TrimSpace(selector[:len(selector)-len(m[0])])
	}
	if selector == "" || len(selector) > 512 || !safeCosmeticSelector.MatchString(selector) {
		return "", "", false
	}
	lower := strings.ToLower(selector)
	if strings.Contains(lower, "</") || strings.Contains(lower, "url(") || strings.Contains(lower, "expression(") || strings.Contains(lower, "javascript:") || strings.ContainsAny(selector, "{};`\r\n") {
		return "", "", false
	}
	// Browser CSS accepts these natively. Procedural uBO modifiers such as
	// :has-text(), :contains() and +js are not ordinary CSS and are deliberately
	// skipped rather than emitted as invalid CSS or pretending JS hooks ran.
	for _, marker := range []string{":has-text(", ":contains(", ":matches-css(", ":upward(", "+js("} {
		if strings.Contains(strings.ToLower(selector), marker) {
			return "", "", false
		}
	}
	if declarations == "" {
		declarations = "display:none!important;visibility:hidden!important"
	}
	return selector, declarations, true
}

func sanitizeCosmeticDeclarations(raw string) (string, bool) {
	var out []string
	for _, part := range strings.Split(raw, ";") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		kv := strings.SplitN(part, ":", 2)
		if len(kv) != 2 {
			return "", false
		}
		prop := strings.ToLower(strings.TrimSpace(kv[0]))
		val := strings.TrimSpace(kv[1])
		switch prop {
		case "display":
			if !regexp.MustCompile(`(?i)^(?:none|block|inline|inline-block|flex|grid|initial|unset)(?:\s*!important)?$`).MatchString(val) {
				return "", false
			}
		case "visibility":
			if !regexp.MustCompile(`(?i)^(?:hidden|visible|collapse)(?:\s*!important)?$`).MatchString(val) {
				return "", false
			}
		case "background-image":
			if !safeCosmeticStyleValue.MatchString(val) || !strings.EqualFold(strings.TrimSpace(strings.TrimSuffix(strings.ToLower(val), "!important")), "none") {
				return "", false
			}
		case "height", "width", "max-height", "max-width", "min-height", "min-width", "opacity", "overflow", "overflow-x", "overflow-y", "transform", "pointer-events", "padding", "margin":
			if !safeCosmeticStyleValue.MatchString(val) {
				return "", false
			}
		default:
			return "", false
		}
		if strings.ContainsAny(val, "{}<>`\\") || strings.Contains(strings.ToLower(val), "url(") || strings.Contains(strings.ToLower(val), "expression(") {
			return "", false
		}
		out = append(out, prop+":"+val)
	}
	if len(out) == 0 {
		return "", false
	}
	return strings.Join(out, ";"), true
}

// splitCosmeticSelectorGroups splits only top-level commas. Commas inside
// attribute values, :is(), :not(), or :has() are part of one selector group.
// It prevents a targeted rule such as "#ad-slot, body" from hiding the whole page.
func splitCosmeticSelectorGroups(selector string) ([]string, bool) {
	var groups []string
	start, square, round := 0, 0, 0
	var quote byte
	escaped := false
	for i := 0; i < len(selector); i++ {
		c := selector[i]
		if escaped {
			escaped = false
			continue
		}
		if c == '\\' {
			escaped = true
			continue
		}
		if quote != 0 {
			if c == quote {
				quote = 0
			}
			continue
		}
		if c == '\'' || c == '"' {
			quote = c
			continue
		}
		switch c {
		case '[':
			square++
		case ']':
			square--
			if square < 0 {
				return nil, false
			}
		case '(':
			round++
		case ')':
			round--
			if round < 0 {
				return nil, false
			}
		case ',':
			if square == 0 && round == 0 {
				part := strings.TrimSpace(selector[start:i])
				if part == "" {
					return nil, false
				}
				groups = append(groups, part)
				start = i + 1
			}
		}
	}
	if quote != 0 || square != 0 || round != 0 || escaped {
		return nil, false
	}
	part := strings.TrimSpace(selector[start:])
	if part == "" {
		return nil, false
	}
	groups = append(groups, part)
	return groups, true
}

var cosmeticAdIntentWord = regexp.MustCompile(`(?i)(^|[^a-z0-9])(?:ad|ads|advert|advertisement|advertising|banner-ad|ad-banner|ad-container|ad-wrapper|ad-slot|ad-popup|popup-ad|ad-overlay|overlay-ad|adblock|adsbygoogle|splash-ad|splashad|splashpage|open[_-]?app|app-open|appopen|launch[_-]?app|launch-ad|launchad|startup-ad|startupad|download[_-]?app|app[_-]?download|appdownload|qrcode-ad|qr-code-ad|watermark|water-mark|water_mark|wm_|wm-|pop-up|popup|popunder|anti-ad|antiad|interstitial|sponsor|sponsored|advertorial|app[_-]?install|install[_-]?app)(?:$|[^a-z0-9])`)
var cosmeticStrongAdName = regexp.MustCompile(`(?i)(?:^|[.#])(?:ad|ads|adv)(?:[-_]|(?:container|wrapper|banner|slot|unit|sidebar|footer|header|mobile|desktop|popup|overlay|block|box|area|content|top|bottom|right|left|under|over|native|video|image|text|zone|placement|frame|insert|server|view|item|list|row|column|close|button|notice|tip|label|card|placeholder|sponsor|reward|interstitial))`)

// Camel-case names such as .sideAds and .appDownload are common in mobile-web
// filters. Match uppercase Ad/Ads/Advert segments, not lowercase words like header.
var cosmeticCamelAdName = regexp.MustCompile(`(?:^|[.#])[A-Za-z0-9_-]*(?:Ad|Ads|Advert)(?:$|[-_])`)

func cosmeticSelectorGroupContentSafe(selector string) bool {
	l := strings.ToLower(strings.TrimSpace(selector))
	if l == "" {
		return false
	}
	// Never allow a selector group that directly targets a whole page/content root.
	switch l {
	case "*", "html", "body", "main", "article", "section", "div", "span", "canvas", "video", "iframe", "svg", "img", "picture", "figure", "pre", "code":
		return false
	}
	// Strongly preserve media and core content areas, even if a third-party list
	// uses vague naming. This prevents class-name coincidences from hiding video,
	// article bodies, editor canvases, subtitles or comments.
	for _, token := range []string{"player", "video", "canvas", "article-content", "post-body", "rich-text", "chapter", "subtitle", "danmaku", "comment-list", "comment-content", "editor-bottom", "editor-toolbar", "lower-canvas", "upper-canvas"} {
		if strings.Contains(l, token) {
			return false
		}
	}
	// Source filters often use CSS classes not literally named "ad" (e.g. a site's
	// QR/app-download modal). Accept a narrow set of popup/installation intent words,
	// but do not accept arbitrary .header/.content/.password/.footer selectors.
	if cosmeticAdIntentWord.MatchString(l) {
		return true
	}
	// CamelCase app ad containers are common in mobile webviews (AdView/AdContainer).
	// Match original case for the boundary instead of looking for the substring "ad"
	// in lowercase, which would incorrectly match words such as "header" or "shadow".
	if cosmeticStrongAdName.MatchString(selector) || cosmeticCamelAdName.MatchString(selector) {
		return true
	}
	return false
}

func cosmeticSelectorContentSafe(selector, declarations string) bool {
	groups, ok := splitCosmeticSelectorGroups(selector)
	if !ok || len(groups) == 0 {
		return false
	}
	for _, group := range groups {
		if !cosmeticSelectorGroupContentSafe(group) {
			return false
		}
	}
	return true
}

func parseCosmeticRules(data []byte, seen map[string]bool, max int) []cosmeticRule {
	return parseCosmeticRulesPolicy(data, seen, max, false)
}

// parseTrustedAdultCosmeticRules trusts the domain-scoped EasyList adult element
// snapshot for ad intent, while still rejecting global/content roots and selectors
// that target player/content surfaces without an explicit ad/overlay marker. The
// general parser stays stricter for arbitrary user-supplied/remote lists.
func parseTrustedAdultCosmeticRules(data []byte, seen map[string]bool, max int) []cosmeticRule {
	return parseCosmeticRulesPolicy(data, seen, max, true)
}

func parseCosmeticRulesPolicy(data []byte, seen map[string]bool, max int, trustedAdult bool) []cosmeticRule {
	var out []cosmeticRule
	for _, raw := range strings.Split(string(data), "\n") {
		line := strings.TrimSpace(strings.TrimSuffix(raw, "\r"))
		if line == "" || strings.HasPrefix(line, "!") || strings.HasPrefix(line, "[") || strings.HasPrefix(line, "# ") || strings.HasPrefix(line, "@@") {
			continue
		}
		sep, exception := "##", false
		if i := strings.Index(line, "#@#"); i >= 0 {
			sep, exception = "#@#", true
		} else if strings.Contains(line, "#?#") || strings.Contains(line, "#$#") || strings.Contains(line, "#%#") {
			continue
		}
		parts := strings.SplitN(line, sep, 2)
		if len(parts) != 2 {
			continue
		}
		domain, ok := sanitizeCosmeticDomainList(parts[0])
		if !ok {
			continue
		}
		selector, decl, ok := sanitizeCosmeticSelector(parts[1])
		if !ok {
			continue
		}
		// Exceptions can only disable matching cosmetics; keep syntactically-safe
		// #@# selectors even when their class name is not an obvious ad token.
		if !exception {
			if trustedAdult {
				if !cosmeticAdultUpstreamSelectorSafe(selector, decl) {
					continue
				}
			} else if !cosmeticSelectorContentSafe(selector, decl) {
				continue
			}
		}
		key := domain + sep + selector + ":" + decl
		if seen[key] {
			continue
		}
		seen[key] = true
		out = append(out, cosmeticRule{domain: domain, selector: selector, declarations: decl, exception: exception})
		if max > 0 && len(out) >= max {
			break
		}
	}
	return out
}

func cosmeticAdultUpstreamSelectorSafe(selector, declarations string) bool {
	groups, ok := splitCosmeticSelectorGroups(selector)
	if !ok || len(groups) == 0 {
		return false
	}
	for _, group := range groups {
		lower := strings.ToLower(strings.TrimSpace(group))
		if lower == "" {
			return false
		}
		// A trusted list must not hide a document root or generic semantic content
		// element, even if the same selector list contains an ad-looking fragment.
		switch lower {
		case "*", "html", "body", "main", "article", "section", "div", "span", "canvas", "video", "iframe", "svg", "img", "picture", "figure", "pre", "code":
			return false
		}
		if strings.HasPrefix(lower, "body ") || strings.HasPrefix(lower, "html ") || strings.HasPrefix(lower, "main ") || strings.HasPrefix(lower, "article ") || strings.HasPrefix(lower, "section ") {
			return false
		}
		adMarker := cosmeticAdIntentWord.MatchString(lower) || cosmeticStrongAdName.MatchString(group) || cosmeticCamelAdName.MatchString(group)
		for _, token := range []string{"player", "video", "canvas", "post-body", "rich-text", "chapter", "subtitle", "danmaku", "comment-list", "comment-content", "editor-bottom", "editor-toolbar", "lower-canvas", "upper-canvas"} {
			if strings.Contains(lower, token) && !adMarker {
				return false
			}
		}
		// Upstream's site-scoped list intentionally uses a few short class names
		// for known ad slots. Reject only generic one-word roots without any hint.
		if !adMarker {
			trimmed := strings.TrimSpace(strings.TrimPrefix(strings.TrimPrefix(lower, "."), "#"))
			switch trimmed {
			case "ad", "ads", "adv", "item", "box", "button", "content", "container", "header", "footer", "sidebar", "right", "left", "desktop", "mobile", "native", "spot", "banner", "player", "video", "image", "title", "description", "text", "main":
				return false
			}
		}
	}
	return true
}

func (e *engine) loadCosmeticRules() []cosmeticRule {
	if e.modDir == "" {
		return nil
	}
	e.cosmeticMu.Lock()
	defer e.cosmeticMu.Unlock()
	if !e.cosmeticLoadedAt.IsZero() && time.Since(e.cosmeticLoadedAt) < time.Second {
		return append([]cosmeticRule(nil), e.cosmeticCached...)
	}
	pg := os.Getenv("PG")
	if pg == "" {
		pg = "/data/adb/privacyguard"
	}
	sets := []struct{ key, file string }{
		{"builtin://NoAppDownload.txt", "NoAppDownload.txt"},
		{"builtin://Adblock_Watermark.txt", "Adblock_Watermark.txt"},
		{"builtin://RunningCheese_Watermark.txt", "RunningCheese_Watermark.txt"},
		{"builtin://RunningCheese_Popup.txt", "RunningCheese_Popup.txt"},
		{"builtin://AdultSite_Elements_EasyList.txt", "AdultSite_Elements_EasyList.txt"},
		{"builtin://AdultSite_AdPopup.txt", "AdultSite_AdPopup.txt"},
		{"builtin://Adblock_Warning_Removal.txt", "Adblock_Warning_Removal.txt"},
	}
	var out []cosmeticRule
	seen := map[string]bool{}
	for _, set := range sets {
		if !e.cosmeticListEnabled(set.key) {
			continue
		}
		path := filepath.Join(e.modDir, "rulefiles", set.file)
		id := strings.TrimSuffix(set.file, filepath.Ext(set.file))
		userCopy := filepath.Join(pg, "rulefiles-user", id+".txt")
		if st, statErr := os.Stat(userCopy); statErr == nil && st.Mode().IsRegular() && st.Size() <= cosmeticRemoteListLimit {
			path = userCopy
		}
		b, err := os.ReadFile(path)
		if err != nil || len(b) > cosmeticRemoteListLimit {
			continue
		}
		var parsed []cosmeticRule
		if set.file == "AdultSite_Elements_EasyList.txt" {
			parsed = parseTrustedAdultCosmeticRules(b, seen, cosmeticRuleLimit-len(out))
		} else {
			parsed = parseCosmeticRules(b, seen, cosmeticRuleLimit-len(out))
		}
		out = append(out, parsed...)
		if len(out) >= cosmeticRuleLimit {
			break
		}
	}
	if len(out) < cosmeticRuleLimit {
		for _, source := range enabledCosmeticSources() {
			b, err := readVerifiedCosmeticCache(pg, source)
			if err != nil {
				continue
			}
			var parsed []cosmeticRule
			if strings.Contains(strings.ToLower(source), "easylist_adult/adult_specific_hide.txt") {
				parsed = parseTrustedAdultCosmeticRules(b, seen, cosmeticRuleLimit-len(out))
			} else {
				parsed = parseCosmeticRules(b, seen, cosmeticRuleLimit-len(out))
			}
			out = append(out, parsed...)
			if len(out) >= cosmeticRuleLimit {
				break
			}
		}
	}
	e.cosmeticCached = append([]cosmeticRule(nil), out...)
	e.cosmeticLoadedAt = time.Now()
	return append([]cosmeticRule(nil), out...)
}

func domainPatternMatches(host, pattern string) bool {
	host = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(host)), ".")
	pattern = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(pattern)), ".")
	if host == "" || pattern == "" {
		return false
	}
	if !strings.Contains(pattern, "*") {
		return host == pattern || strings.HasSuffix(host, "."+pattern)
	}
	// Asterisk is accepted only as a whole label. Match one or more labels at
	// that position without letting e.g. badexample.com match example.com.
	parts := strings.Split(pattern, ".")
	hostParts := strings.Split(host, ".")
	if len(parts) != len(hostParts) {
		return false
	}
	for i, p := range parts {
		if p != "*" && p != hostParts[i] {
			return false
		}
	}
	return true
}

func cosmeticHostMatches(host, domain string) bool {
	if strings.TrimSpace(domain) == "" {
		return true
	}
	items := strings.Split(strings.ToLower(domain), ",")
	hasPositive := false
	positiveMatch := false
	for _, item := range items {
		item = strings.TrimSpace(item)
		if item == "" {
			continue
		}
		if strings.HasPrefix(item, "~") {
			if domainPatternMatches(host, strings.TrimPrefix(item, "~")) {
				return false
			}
			continue
		}
		hasPositive = true
		if domainPatternMatches(host, item) {
			positiveMatch = true
		}
	}
	return !hasPositive || positiveMatch
}

// prepareCosmeticRequest asks the origin for an identity-encoded HTML document so
// the CSS injector never edits gzip/br/zstd bytes. This is limited to document-like
// requests and runs only while at least one cosmetic list is enabled.
func (e *engine) prepareCosmeticRequest(req *http.Request) {
	if req == nil || req.URL == nil || req.Header == nil {
		return
	}
	accept := strings.ToLower(req.Header.Get("Accept"))
	dest := strings.ToLower(strings.TrimSpace(req.Header.Get("Sec-Fetch-Dest")))
	if dest != "document" && !strings.Contains(accept, "text/html") && !strings.Contains(accept, "application/xhtml+xml") {
		return
	}
	enabled := false
	for _, key := range []string{
		"builtin://NoAppDownload.txt", "builtin://Adblock_Watermark.txt",
		"builtin://RunningCheese_Watermark.txt", "builtin://RunningCheese_Popup.txt",
		"builtin://AdultSite_Elements_EasyList.txt", "builtin://AdultSite_AdPopup.txt",
		"builtin://Adblock_Warning_Removal.txt",
	} {
		if e.cosmeticListEnabled(key) {
			enabled = true
			break
		}
	}
	if !enabled && len(enabledCosmeticSources()) == 0 {
		return
	}
	req.Header.Set("Accept-Encoding", "identity")
}

func (e *engine) applyCosmeticFilters(req *http.Request, resp *http.Response) {
	if req == nil || resp == nil || resp.Body == nil || resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return
	}
	if strings.ToLower(strings.TrimSpace(strings.SplitN(resp.Header.Get("Content-Type"), ";", 2)[0])) != "text/html" {
		return
	}
	// Document requests are changed to Accept-Encoding: identity when cosmetic
	// sources are enabled. If an origin still sends an encoded entity, preserve it
	// intact instead of rewriting compressed bytes.
	if strings.TrimSpace(resp.Header.Get("Content-Encoding")) != "" {
		return
	}
	// Inspection is bounded, but forwarding is not: restore the consumed prefix and
	// unread stream so a large HTML page is never truncated by the filter.
	body, err := io.ReadAll(io.LimitReader(resp.Body, cosmeticBodyLimit+1))
	if err != nil || len(body) > cosmeticBodyLimit {
		remaining := resp.Body
		resp.Body = struct {
			io.Reader
			io.Closer
		}{Reader: io.MultiReader(bytes.NewReader(body), remaining), Closer: remaining}
		resp.ContentLength = -1
		resp.Header.Del("Content-Length")
		return
	}
	_ = resp.Body.Close()
	rules := e.loadCosmeticRules()
	if len(rules) == 0 {
		resp.Body = io.NopCloser(bytes.NewReader(body))
		return
	}
	host := req.URL.Hostname()
	if host == "" {
		host = req.Host
	}
	// Exceptions from any enabled list override a matching selector for this host.
	exceptions := map[string]bool{}
	for _, r := range rules {
		if r.exception && cosmeticHostMatches(host, r.domain) {
			exceptions[r.selector] = true
		}
	}
	var css strings.Builder
	for _, r := range rules {
		if r.exception || exceptions[r.selector] || !cosmeticHostMatches(host, r.domain) {
			continue
		}
		if css.Len()+len(r.selector)+len(r.declarations)+8 > cosmeticCSSLimit {
			break
		}
		css.WriteString(r.selector)
		css.WriteByte('{')
		css.WriteString(r.declarations)
		css.WriteString("}\n")
	}
	if css.Len() == 0 {
		resp.Body = io.NopCloser(bytes.NewReader(body))
		return
	}
	style := []byte("<style id=\"fx-cosmetic-filters\">" + css.String() + "</style>")
	lower := bytes.ToLower(body)
	if idx := bytes.Index(lower, []byte("</head>")); idx >= 0 {
		body = append(append(append([]byte{}, body[:idx]...), style...), body[idx:]...)
	} else {
		body = append(style, body...)
	}
	resp.Header.Del("ETag")
	resp.Header.Del("Content-MD5")
	resp.Header.Del("Accept-Ranges")
	resp.Header.Del("Content-Encoding")
	resp.Header.Del("Transfer-Encoding")
	resp.ContentLength = int64(len(body))
	resp.Header.Set("Content-Length", fmt.Sprint(len(body)))
	resp.Body = io.NopCloser(bytes.NewReader(body))
}
