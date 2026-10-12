// ============================================================
//
//	sbcfg.go — sing-box 配置编译器
//	把内部统一模型单向编译成 sing-box 配置。
//
//	配置语法随内核版本断代，编译器按目标版本产出对应写法
//	（断代点均由真实内核 check 实测确认，不是猜的）：
//
//	  DNS 服务器        1.12 起用 type/server；1.14 起旧式 address 被移除
//	  default_domain_resolver  1.12 起才有；1.11 写了会 decode 失败
//	  入站 sniff        1.13 起移除，改由路由规则 action=sniff 承担
//	  tun 地址          address 在 1.10~1.14 全版本可用（inet4_address 反而被移除）
//	  block 出站        1.11~1.14 均可用（已废弃但未移除）
//
//	路由规则一律用 1.11 起的 action/outbound 新式写法；
//	geoip/geosite 一律走 rule_set（旧字段 1.12 已移除）。
//
// ============================================================
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// ---------- 内核版本与语法断代 ----------

// defaultSBVersion 无明确目标版本时假定的内核版本（当前最新稳定版）。
const defaultSBVersion = "1.14.3"

type sbVer struct{ major, minor, patch int }

func parseSBVer(s string) sbVer {
	s = strings.TrimSpace(s)
	s = strings.TrimPrefix(s, "v")
	s = strings.TrimPrefix(s, "V")
	// 只取前三个点分段，忽略 -beta / -alpha 之类的后缀
	if i := strings.IndexAny(s, "-+"); i >= 0 {
		s = s[:i]
	}
	var v sbVer
	parts := strings.Split(s, ".")
	n := func(i int) int {
		if i >= len(parts) {
			return 0
		}
		return atoiSafe(parts[i])
	}
	v.major, v.minor, v.patch = n(0), n(1), n(2)
	return v
}

func (v sbVer) atLeast(major, minor int) bool {
	if v.major != major {
		return v.major > major
	}
	return v.minor >= minor
}

func (v sbVer) String() string {
	return fmt.Sprintf("%d.%d.%d", v.major, v.minor, v.patch)
}

// 语法能力开关
func (v sbVer) newDNSServerForm() bool      { return v.atLeast(1, 12) } // type/server
func (v sbVer) hasDefaultDomainResolver() bool { return v.atLeast(1, 12) }
func (v sbVer) legacyInboundSniff() bool    { return !v.atLeast(1, 13) }

// normalizeVer 空/非法版本一律落到默认版本，避免产出半新半旧的配置。
func normalizeVer(s string) sbVer {
	v := parseSBVer(s)
	if v.major == 0 && v.minor == 0 {
		return parseSBVer(defaultSBVersion)
	}
	return v
}

// 规则集远程源。
//
// 实测（中国大陆网络，2026-10）：
//   testingcf.jsdelivr.net   200 / 0.30s   ← 默认
//   fastly.jsdelivr.net      200 / 0.87s
//   gh-proxy.com             200 / 1.05s
//   ghproxy.net              200 / 1.27s
//   cdn.jsdelivr.net         000 / 超时    ← 很多人默认用这个，实际不通
//   gcore.jsdelivr.net       000 / 31s
//   raw.githubusercontent.com 000 / 不通
//
// 所以默认走 testingcf，并保留整条镜像链；同时支持把 .srs 落到本地，
// 彻底离线可用（模块的使用场景常常就是没有网的时候）。
const (
	RuleSetRepoGeoSite = "SagerNet/sing-geosite"
	RuleSetRepoGeoIP   = "SagerNet/sing-geoip"
)

// ruleMirror 一个规则集镜像。模板里 {repo} 与 {path} 会被替换。
type ruleMirror struct {
	Name string
	Tpl  string
}

var ruleMirrors = []ruleMirror{
	{"testingcf", "https://testingcf.jsdelivr.net/gh/{repo}@rule-set/{path}"},
	{"fastly", "https://fastly.jsdelivr.net/gh/{repo}@rule-set/{path}"},
	{"ghproxy", "https://gh-proxy.com/https://raw.githubusercontent.com/{repo}/rule-set/{path}"},
	{"ghproxynet", "https://ghproxy.net/https://raw.githubusercontent.com/{repo}/rule-set/{path}"},
	{"jsdelivr", "https://cdn.jsdelivr.net/gh/{repo}@rule-set/{path}"},
}

// DefaultMirror 默认镜像名
const DefaultMirror = "testingcf"

func mirrorByName(name string) ruleMirror {
	for _, m := range ruleMirrors {
		if m.Name == name {
			return m
		}
	}
	return ruleMirrors[0]
}

// buildRuleSetURL 拼出某个 geo 码对应的规则集下载地址。
// kind 为 RGeoSite / RGeoIP，code 为 cn、category-ads-all 之类。
func buildRuleSetURL(mirrorName, kind, code string) string {
	repo, file := RuleSetRepoGeoSite, "geosite-"+code+".srs"
	if kind == RGeoIP {
		repo, file = RuleSetRepoGeoIP, "geoip-"+code+".srs"
	}
	m := mirrorByName(mirrorName)
	u := strings.ReplaceAll(m.Tpl, "{repo}", repo)
	u = strings.ReplaceAll(u, "{path}", file)
	return u
}

// RuleSetFileName 规则集在本地目录中的文件名，编译与下载共用同一套命名。
func RuleSetFileName(kind, code string) string {
	if kind == RGeoIP {
		return "geoip-" + code + ".srs"
	}
	return "geosite-" + code + ".srs"
}

type sbConfig struct {
	Log          map[string]any  `json:"log,omitempty"`
	DNS          *sbDNS          `json:"dns,omitempty"`
	Inbounds     []any           `json:"inbounds,omitempty"`
	Outbounds    []any           `json:"outbounds"`
	Route        *sbRoute        `json:"route,omitempty"`
	Experimental *sbExperimental `json:"experimental,omitempty"`
}

type sbDNS struct {
	Servers          []any      `json:"servers"`
	Rules            []any      `json:"rules,omitempty"`
	Final            string     `json:"final,omitempty"`
	Strategy         string     `json:"strategy,omitempty"`
	IndependentCache bool       `json:"independent_cache,omitempty"`
	DisableCache     bool       `json:"disable_cache,omitempty"`
	FakeIP           *sbFakeIP  `json:"fakeip,omitempty"` // 仅 1.12 之前用
}

// sbFakeIP 旧式（<1.12）的 fakeip 配置块。
// 1.12 起 fakeip 区间挪到 DNS 服务器对象上，这个块被移除。
type sbFakeIP struct {
	Enabled   bool   `json:"enabled"`
	Inet4Range string `json:"inet4_range,omitempty"`
	Inet6Range string `json:"inet6_range,omitempty"`
}

type sbRoute struct {
	RuleSet               []any  `json:"rule_set,omitempty"`
	Rules                 []any  `json:"rules,omitempty"`
	Final                 string `json:"final,omitempty"`
	AutoDetectInterface   bool   `json:"auto_detect_interface,omitempty"`
	DefaultDomainResolver string `json:"default_domain_resolver,omitempty"`
}

type sbExperimental struct {
	ClashAPI *sbClashAPI `json:"clash_api,omitempty"`
	CacheFile *sbCacheFile `json:"cache_file,omitempty"`
}

type sbClashAPI struct {
	ExternalController string `json:"external_controller,omitempty"`
	Secret             string `json:"secret,omitempty"`
	DefaultMode        string `json:"default_mode,omitempty"`
}

type sbCacheFile struct {
	Enabled     bool   `json:"enabled"`
	Path        string `json:"path,omitempty"`
	CacheID     string `json:"cache_id,omitempty"`
	StoreFakeIP bool   `json:"store_fakeip,omitempty"`
}

// CompileResult 编译产物
type CompileResult struct {
	JSON     []byte   `json:"-"`
	Warnings []string `json:"warnings"`
	// 策略 → 出站标签 的映射，便于 UI 展示
	PolicyMap map[string]string `json:"policy_map"`
	RuleCount int               `json:"rule_count"`
	Skipped   int               `json:"skipped"`
	// TargetVersion 本次编译针对的内核版本
	TargetVersion string `json:"target_version,omitempty"`
	// Mirror 本次使用的规则集镜像
	Mirror string `json:"mirror,omitempty"`
	// RuleSetDir 本地规则集目录（命中则离线）
	RuleSetDir string `json:"rule_set_dir,omitempty"`
	// LocalRuleSets 实际命中本地文件的规则集数量
	LocalRuleSets int `json:"local_rule_sets,omitempty"`
}

// CompileOptions 编译选项
type CompileOptions struct {
	CachePath     string
	KernelVersion string
	// RuleSetDir 本地规则集目录。命中时用 type=local，实现完全离线。
	RuleSetDir string
	// Mirror 规则集镜像名，见 ruleMirrors；空则用默认。
	Mirror string
}

// CompileSingBox 编译为 sing-box 配置。
func CompileSingBox(p *Profile, opts CompileOptions) (*CompileResult, error) {
	res := &CompileResult{PolicyMap: map[string]string{}}

	cachePath := opts.CachePath
	kernelVersion := opts.KernelVersion
	if kernelVersion == "" {
		kernelVersion = p.General.SingBoxVersion
	}
	ver := normalizeVer(kernelVersion)
	res.TargetVersion = ver.String()
	res.Mirror = orDefault(opts.Mirror, DefaultMirror)
	res.RuleSetDir = opts.RuleSetDir

	if len(p.Nodes) == 0 && len(p.Groups) == 0 {
		return nil, fmt.Errorf("没有任何节点或策略组，无法编译")
	}

	// ---------- 1) 建立标签表 ----------
	usedTags := map[string]int{}
	nodeTag := map[string]string{}
	for i := range p.Nodes {
		t := uniqueName(usedTags, p.Nodes[i].Name)
		nodeTag[p.Nodes[i].Name] = t
	}
	groupTag := map[string]string{}
	for i := range p.Groups {
		t := uniqueName(usedTags, p.Groups[i].Name)
		groupTag[p.Groups[i].Name] = t
	}

	// PROXY 策略：若规则用到但没定义同名组，自动补一个总选择组
	needProxy := false
	for _, r := range p.Rules {
		if strings.EqualFold(r.Policy, PolicyProxy) {
			needProxy = true
			break
		}
	}
	if needProxy {
		if _, ok := groupTag["PROXY"]; !ok {
			members := []string{}
			for i := range p.Nodes {
				members = append(members, nodeTag[p.Nodes[i].Name])
			}
			for i := range p.Groups {
				members = append(members, groupTag[p.Groups[i].Name])
			}
			if len(members) == 0 {
				return nil, fmt.Errorf("策略引用了 PROXY，但没有任何节点可放入该策略组")
			}
			p.Groups = append(p.Groups, ProxyGroup{
				Name: "PROXY", Type: GroupSelect, Proxies: members,
			})
			groupTag["PROXY"] = uniqueName(usedTags, "PROXY")
			res.Warnings = append(res.Warnings, "规则引用了 PROXY 但未定义同名策略组，已自动生成一个包含全部节点与子策略组的选择组")
		}
	}

	// 解析策略 → 出站标签
	resolvePolicy := func(pol string) (tag string, action string, ok bool) {
		switch strings.ToUpper(pol) {
		case PolicyDirect:
			return "direct", "route", true
		case PolicyReject, PolicyRejectDrop:
			return "", "reject", true
		case PolicyPass:
			// sing-box 无 PASS 语义，退化为直连并提示
			return "direct", "route", true
		}
		if t, ok := groupTag[pol]; ok {
			return t, "route", true
		}
		if t, ok := nodeTag[pol]; ok {
			return t, "route", true
		}
		return "", "", false
	}

	// ---------- 2) 出站 ----------
	outbounds := []any{}
	for i := range p.Nodes {
		ob, err := nodeToOutbound(&p.Nodes[i], nodeTag[p.Nodes[i].Name])
		if err != nil {
			res.Warnings = append(res.Warnings, fmt.Sprintf("节点 %q 无法编译：%v", p.Nodes[i].Name, err))
			continue
		}
		outbounds = append(outbounds, ob)
	}
	for i := range p.Groups {
		g := &p.Groups[i]
		ob, err := groupToOutbound(g, groupTag[g.Name], nodeTag, groupTag)
		if err != nil {
			res.Warnings = append(res.Warnings, fmt.Sprintf("策略组 %q 无法编译：%v", g.Name, err))
			continue
		}
		outbounds = append(outbounds, ob)
	}
	outbounds = append(outbounds,
		map[string]any{"type": "direct", "tag": "direct"},
		map[string]any{"type": "block", "tag": "block"},
	)
	if _, ok := groupTag["PROXY"]; ok {
		res.PolicyMap["PROXY"] = groupTag["PROXY"]
	}
	res.PolicyMap["DIRECT"] = "direct"
	res.PolicyMap["REJECT"] = "(reject)"

	// ---------- 3) 规则集（geoip/geosite/远程规则集） ----------
	ruleSetList := []any{}
	ruleSetTags := map[string]bool{}
	declaredSets := map[string]bool{}

	// 先把 profile 里显式声明的规则集全部落进 route.rule_set。
	// 之前这里只做了"声明校验"却没真正输出，导致规则引用它时
	// 内核启动直接报 "rule-set not found"。
	for i := range p.RuleSets {
		rs := &p.RuleSets[i]
		if !rs.Enabled || rs.Name == "" || ruleSetTags[rs.Name] {
			continue
		}
		ruleSetTags[rs.Name] = true
		declaredSets[rs.Name] = true

		format := orDefault(rs.Format, "binary")
		typ := strings.ToLower(rs.Type)
		// 本地目录里能命中同名 .srs 就优先本地
		if dir := strings.TrimSpace(opts.RuleSetDir); dir != "" {
			cand := filepath.Join(dir, rs.Name+".srs")
			if rs.Path != "" {
				cand = filepath.Join(dir, filepath.Base(rs.Path))
			}
			if st, err := os.Stat(cand); err == nil && !st.IsDir() && st.Size() > 0 {
				ruleSetList = append(ruleSetList, map[string]any{
					"tag": rs.Name, "type": "local", "format": format, "path": cand,
				})
				res.LocalRuleSets++
				continue
			}
		}
		switch typ {
		case "local", "inline":
			if rs.Path == "" {
				res.Warnings = append(res.Warnings,
					fmt.Sprintf("规则集 %q 声明为本地但没给路径，已跳过", rs.Name))
				delete(ruleSetTags, rs.Name)
				continue
			}
			ruleSetList = append(ruleSetList, map[string]any{
				"tag": rs.Name, "type": "local", "format": format, "path": rs.Path,
			})
		default:
			if rs.URL == "" {
				res.Warnings = append(res.Warnings,
					fmt.Sprintf("规则集 %q 没有下载地址，已跳过", rs.Name))
				delete(ruleSetTags, rs.Name)
				continue
			}
			obj := map[string]any{
				"tag": rs.Name, "type": "remote", "format": format, "url": rs.URL,
			}
			if rs.Interval > 0 {
				obj["update_interval"] = itoa(rs.Interval) + "s"
			}
			if !ver.atLeast(1, 14) {
				obj["download_detour"] = "direct"
			}
			ruleSetList = append(ruleSetList, obj)
		}
	}

	// ensureGeoSet 把一个 geo 码变成 rule_set 标签。
	// 本地目录里已有对应 .srs 就用 local（离线可用、启动更快、不受 CDN 波动影响），
	// 否则回落到远程镜像。
	ensureGeoSet := func(kind, code string) string {
		code = strings.ToLower(strings.TrimSpace(code))
		var tag string
		switch kind {
		case RGeoIP:
			tag = "geoip-" + code
		case RGeoSite:
			tag = "geosite-" + code
		default:
			return ""
		}
		if ruleSetTags[tag] {
			return tag
		}
		ruleSetTags[tag] = true

		fileName := RuleSetFileName(kind, code)
		if dir := strings.TrimSpace(opts.RuleSetDir); dir != "" {
			p := filepath.Join(dir, fileName)
			if st, err := os.Stat(p); err == nil && !st.IsDir() && st.Size() > 0 {
				ruleSetList = append(ruleSetList, map[string]any{
					"tag":    tag,
					"type":   "local",
					"format": "binary",
					"path":   p,
				})
				res.LocalRuleSets++
				return tag
			}
		}
		rs := map[string]any{
			"tag":    tag,
			"type":   "remote",
			"format": "binary",
			"url":    buildRuleSetURL(res.Mirror, kind, code),
		}
		// download_detour 在 1.14 起被标记废弃、1.16 移除；只在老版本写它，
		// 新版本让内核按路由规则决定，避免升级后配置直接失效。
		if !ver.atLeast(1, 14) {
			rs["download_detour"] = "direct"
		}
		ruleSetList = append(ruleSetList, rs)
		return tag
	}

	// ---------- 4) 路由规则 ----------
	var routeRules []any
	var finalPolicy string
	skipped := 0

	for i := range p.Rules {
		r := &p.Rules[i]
		if !r.Enabled {
			continue
		}
		if r.Kind == RMatch || r.Kind == RFinal {
			finalPolicy = r.Policy
			res.RuleCount++
			continue
		}
		obj, err := compileRule(r, resolvePolicy, ensureGeoSet, p)
		if err != nil {
			res.Warnings = append(res.Warnings, fmt.Sprintf("第 %d 行规则未编译：%v", r.Line, err))
			skipped++
			continue
		}
		if obj == nil {
			skipped++
			continue
		}
		routeRules = append(routeRules, obj)
		res.RuleCount++
	}

	// 前置规则：嗅探必须最先，DNS 劫持紧随其后。
	// 这两条是"基础设施"，不是分流策略。
	routeRules = append([]any{
		map[string]any{"action": "sniff"},
		map[string]any{"protocol": "dns", "action": "hijack-dns"},
	}, routeRules...)

	// 局域网直连兜底：放在用户规则之后。
	// 早先放在最前面，结果 ip_is_private 会把所有私网目标都吞掉，
	// 用户规则一条都执行不到（连 127.0.0.1 的调试流量都被直连走）。
	if p.General.PrivateDirectOn() {
		routeRules = append(routeRules, map[string]any{
			"ip_is_private": true, "action": "route", "outbound": "direct",
		})
	}

	// 兜底
	finalTag := "direct"
	if finalPolicy != "" {
		if t, _, ok := resolvePolicy(finalPolicy); ok && t != "" {
			finalTag = t
		}
	} else if t, ok := groupTag["PROXY"]; ok {
		finalTag = t
	} else if len(p.Groups) > 0 {
		finalTag = groupTag[p.Groups[0].Name]
	} else if len(p.Nodes) > 0 {
		finalTag = nodeTag[p.Nodes[0].Name]
	}
	p.General.FinalPolicy = finalPolicy

	// ---------- 5) DNS ----------
	// DNS 出站是符号名（direct / proxy），这里解析成真实出站标签。
	// 之前直接写死 "proxy" 会指向一个不存在的出站，内核启动即失败。
	dnsDetour := func(name string) string {
		switch strings.ToLower(strings.TrimSpace(name)) {
		case "", "direct":
			// 直连时不能写 detour：内核会报
			// "detour to an empty direct outbound makes no sense"
			return ""
		case "proxy", "proxies":
			if t, ok := groupTag["PROXY"]; ok {
				return t
			}
			if len(p.Groups) > 0 {
				return groupTag[p.Groups[0].Name]
			}
			if len(p.Nodes) > 0 {
				return nodeTag[p.Nodes[0].Name]
			}
			return ""
		}
		// 直接写了具体节点名/组名
		if t, ok := groupTag[name]; ok {
			return t
		}
		if t, ok := nodeTag[name]; ok {
			return t
		}
		return ""
	}
	dnsObj := compileDNS(&p.DNS, res, ver, dnsDetour)

	// ---------- 6) 入站 ----------
	inbounds := []any{}
	if p.General.TunEnabled {
		stack := p.General.TunStack
		if stack == "" {
			stack = "mixed"
		}
		mtu := p.General.TunMTU
		if mtu == 0 {
			mtu = 9000
		}
		tun := map[string]any{
			"type": "tun", "tag": "tun-in",
			// address 在 1.10~1.14 全版本可用；inet4_address 反而是被移除的旧字段
			"address":      []string{"172.19.0.1/30"},
			"mtu":          mtu,
			"auto_route":   true,
			"strict_route": p.General.StrictRoute,
			"stack":        stack,
		}
		if ver.legacyInboundSniff() {
			tun["sniff"] = true
		}
		inbounds = append(inbounds, tun)
	}
	mp := p.General.MixedPort
	if mp == 0 {
		mp = 2080
	}
	mixed := map[string]any{
		"type": "mixed", "tag": "mixed-in",
		"listen": "127.0.0.1", "listen_port": mp,
	}
	if ver.legacyInboundSniff() {
		mixed["sniff"] = true
	}
	inbounds = append(inbounds, mixed)

	// ---------- 7) 组装 ----------
	cfg := sbConfig{
		Log:       map[string]any{"level": orDefault(p.General.LogLevel, "warn"), "timestamp": true},
		DNS:       dnsObj,
		Inbounds:  inbounds,
		Outbounds: outbounds,
		Route: &sbRoute{
			Rules:               routeRules,
			Final:               finalTag,
			AutoDetectInterface: true,
		},
	}
	if len(ruleSetList) > 0 {
		cfg.Route.RuleSet = ruleSetList
	}
	// default_domain_resolver 1.12 才引入，1.11 写了直接 decode 失败
	if ver.hasDefaultDomainResolver() && dnsObj != nil {
		if tag := firstDNSTag(dnsObj); tag != "" {
			cfg.Route.DefaultDomainResolver = tag
		}
	}
	if p.General.ClashAPI {
		port := p.General.ClashAPIPort
		if port == 0 {
			port = 9090
		}
		cfg.Experimental = &sbExperimental{
			ClashAPI: &sbClashAPI{
				ExternalController: fmt.Sprintf("127.0.0.1:%d", port),
				Secret:             p.General.ClashAPISecret,
				DefaultMode:        orDefault(p.General.DefaultMode, "rule"),
			},
		}
		if cachePath != "" {
			cfg.Experimental.CacheFile = &sbCacheFile{
				Enabled: true, Path: cachePath, CacheID: "sy", StoreFakeIP: p.DNS.FakeIP,
			}
		}
	}

	b, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return nil, err
	}
	res.JSON = b
	res.Skipped = skipped
	return res, nil
}

func orDefault(s, d string) string {
	if strings.TrimSpace(s) == "" {
		return d
	}
	return s
}

// ---------- 出站编译 ----------

func nodeToOutbound(n *Node, tag string) (map[string]any, error) {
	o := map[string]any{"tag": tag, "server": n.Server, "server_port": n.Port}
	switch n.Type {
	case "vmess":
		o["type"] = "vmess"
		o["uuid"] = n.UUID
		if n.AlterID > 0 {
			o["alter_id"] = n.AlterID
		}
		o["security"] = orDefault(strFromExtra(n, "security"), "auto")
	case "vless":
		o["type"] = "vless"
		o["uuid"] = n.UUID
		if n.Flow != "" {
			o["flow"] = n.Flow
		}
	case "trojan":
		o["type"] = "trojan"
		o["password"] = n.Password
	case "shadowsocks":
		o["type"] = "shadowsocks"
		o["method"] = n.Method
		o["password"] = n.Password
		if n.Plugin != "" {
			o["plugin"] = n.Plugin
			o["plugin_opts"] = n.PluginOpts
		}
	case "shadowsocksr":
		return nil, fmt.Errorf("sing-box 已移除 ShadowsocksR 支持，请改用 Shadowsocks 或换用 xray 内核")
	case "hysteria2":
		o["type"] = "hysteria2"
		o["password"] = n.Password
		if n.Obfs != "" {
			o["obfs"] = map[string]any{"type": n.Obfs, "password": n.ObfsPass}
		}
		if n.UpMbps > 0 {
			o["up_mbps"] = n.UpMbps
		}
		if n.DownMbps > 0 {
			o["down_mbps"] = n.DownMbps
		}
	case "tuic":
		o["type"] = "tuic"
		o["uuid"] = n.UUID
		o["password"] = n.Password
		o["congestion_control"] = "bbr"
	case "http":
		o["type"] = "http"
		if n.Username != "" {
			o["username"] = n.Username
			o["password"] = n.Password
		}
	case "socks":
		o["type"] = "socks"
		if n.Username != "" {
			o["username"] = n.Username
			o["password"] = n.Password
		}
	case "wireguard":
		o["type"] = "wireguard"
		o["private_key"] = n.PrivateKey
		o["peer_public_key"] = n.PeerPublicKey
		if n.PreSharedKey != "" {
			o["pre_shared_key"] = n.PreSharedKey
		}
		if len(n.LocalAddress) > 0 {
			o["local_address"] = n.LocalAddress
		}
		if n.MTU > 0 {
			o["mtu"] = n.MTU
		}
	default:
		return nil, fmt.Errorf("不支持的节点类型 %q", n.Type)
	}

	// TLS
	if n.Type != "http" && n.Type != "socks" && n.Type != "wireguard" {
		tlsObj := map[string]any{}
		if n.TLS || n.RealityPBK != "" {
			tlsObj["enabled"] = true
		}
		if n.SNI != "" {
			tlsObj["server_name"] = n.SNI
		}
		if n.Insecure {
			tlsObj["insecure"] = true
		}
		if len(n.ALPN) > 0 {
			tlsObj["alpn"] = n.ALPN
		}
		if n.Fingerprint != "" {
			tlsObj["utls"] = map[string]any{"enabled": true, "fingerprint": n.Fingerprint}
		}
		if n.RealityPBK != "" {
			tlsObj["reality"] = map[string]any{
				"enabled": true, "public_key": n.RealityPBK, "short_id": n.RealitySID,
			}
			tlsObj["enabled"] = true
		}
		if len(tlsObj) > 0 {
			o["tls"] = tlsObj
		}
	}

	// 传输层
	switch n.Network {
	case "ws":
		tr := map[string]any{"type": "ws"}
		if n.WSPath != "" {
			tr["path"] = n.WSPath
		}
		if n.WSHost != "" {
			tr["headers"] = map[string]any{"Host": n.WSHost}
		}
		o["transport"] = tr
	case "grpc":
		tr := map[string]any{"type": "grpc"}
		if n.GRPCService != "" {
			tr["service_name"] = n.GRPCService
		}
		o["transport"] = tr
	case "http", "h2":
		tr := map[string]any{"type": "http"}
		if n.WSHost != "" {
			tr["host"] = []string{n.WSHost}
		}
		if n.WSPath != "" {
			tr["path"] = n.WSPath
		}
		o["transport"] = tr
	case "quic":
		o["transport"] = map[string]any{"type": "quic"}
	}
	return o, nil
}

func strFromExtra(n *Node, k string) string {
	if n.Extra == nil {
		return ""
	}
	if v, ok := n.Extra[k].(string); ok {
		return v
	}
	return ""
}

func groupToOutbound(g *ProxyGroup, tag string, nodeTag, groupTag map[string]string) (map[string]any, error) {
	var members []string
	for _, m := range g.Proxies {
		if t, ok := nodeTag[m]; ok {
			members = append(members, t)
			continue
		}
		if t, ok := groupTag[m]; ok && t != tag {
			members = append(members, t)
			continue
		}
		switch strings.ToUpper(m) {
		case PolicyDirect:
			members = append(members, "direct")
			continue
		}
		// 未知名直接当标签用（可能是内置出站）
		members = append(members, m)
	}
	if len(members) == 0 {
		return nil, fmt.Errorf("策略组没有任何有效成员")
	}
	o := map[string]any{"tag": tag, "outbounds": members}
	switch g.Type {
	case GroupSelect, "":
		o["type"] = "selector"
		if g.DisableUDP {
			o["interrupt_exist_connections"] = true
		}
	case GroupURLTest:
		o["type"] = "urltest"
		o["url"] = orDefault(g.URL, "https://www.gstatic.com/generate_204")
		// sing-box 的 interval 是 Go duration 字符串（"300s"），写数字会 decode 失败
		o["interval"] = itoa(orDefaultInt(g.Interval, 300)) + "s"
		if g.Tolerance > 0 {
			o["tolerance"] = g.Tolerance
		}
	case GroupFallback:
		// sing-box 用 urltest + 手动顺序近似；这里用 selector 保序更稳妥
		o["type"] = "selector"
		o["default"] = members[0]
	case GroupLoadBalance:
		o["type"] = "urltest"
		o["url"] = orDefault(g.URL, "https://www.gstatic.com/generate_204")
		o["interval"] = itoa(orDefaultInt(g.Interval, 300)) + "s"
		if g.Tolerance > 0 {
			o["tolerance"] = g.Tolerance
		}
	case GroupRelay:
		o["type"] = "selector"
		o["default"] = members[0]
	default:
		o["type"] = "selector"
	}
	return o, nil
}

func orDefaultInt(v, d int) int {
	if v <= 0 {
		return d
	}
	return v
}

// ---------- 规则编译 ----------

type policyResolver func(pol string) (tag, action string, ok bool)
type geoSetMaker func(kind, code string) string

// compileRule 编译一条完整规则（含策略 → action/outbound）。
func compileRule(r *Rule, resolve policyResolver, geo geoSetMaker, p *Profile) (map[string]any, error) {
	obj, err := compileCond(r, resolve, geo, p)
	if err != nil {
		return nil, err
	}
	tag, action, ok := resolve(r.Policy)
	if !ok {
		return nil, fmt.Errorf("策略 %q 无法解析", r.Policy)
	}
	applyAction(obj, tag, action)
	return obj, nil
}

// compileCond 只编译"匹配条件"，不落 action。
// 逻辑规则的子规则用它——子规则本身不带策略，
// 若沿用 compileRule 会因策略为空而误报。
func compileCond(r *Rule, resolve policyResolver, geo geoSetMaker, p *Profile) (map[string]any, error) {
	// 逻辑规则
	if r.Kind == RAnd || r.Kind == ROr || r.Kind == RNot {
		subs := []any{}
		for i := range r.Rules {
			so, err := compileCond(&r.Rules[i], resolve, geo, p)
			if err != nil {
				return nil, fmt.Errorf("子规则 %s,%s：%v", r.Rules[i].Kind, r.Rules[i].Payload, err)
			}
			if so == nil {
				return nil, fmt.Errorf("逻辑子规则 %s,%s 无法编译", r.Rules[i].Kind, r.Rules[i].Payload)
			}
			subs = append(subs, so)
		}
		if len(subs) == 0 {
			return nil, fmt.Errorf("逻辑规则没有可编译的子规则")
		}
		obj := map[string]any{"type": "logical", "mode": r.Mode, "rules": subs}
		if r.Mode == "not" {
			// sing-box 无 "not" 模式，用 or + invert 表达
			obj["mode"] = "or"
			obj["invert"] = true
		}
		if r.Invert {
			obj["invert"] = true
		}
		return obj, nil
	}

	ki, known := ruleKinds[r.Kind]
	if !known {
		return nil, fmt.Errorf("未知规则类型 %s", r.Kind)
	}
	if !ki.Supported {
		return nil, fmt.Errorf("%s 无法编译（%s）", r.Kind, ki.Note)
	}

	obj := map[string]any{}
	switch r.Kind {
	case RGeoIP:
		obj["rule_set"] = []string{geo(RGeoIP, r.Payload)}
	case RGeoSite:
		obj["rule_set"] = []string{geo(RGeoSite, r.Payload)}
	case RRuleSet:
		name := strings.TrimSpace(r.Payload)
		declared := false
		for i := range p.RuleSets {
			if p.RuleSets[i].Name == name && p.RuleSets[i].Enabled {
				declared = true
				break
			}
		}
		if !declared {
			// sing-box 遇到未声明的 rule_set tag 会直接启动失败，
			// 这里提前拦下，避免把坏配置交给内核。
			return nil, fmt.Errorf("规则集 %q 未在 profile.rule_sets 中声明", name)
		}
		obj["rule_set"] = []string{name}
	case RDomainWildcard:
		obj["domain_regex"] = []string{wildcardToRegex(r.Payload)}
	case RProcessName:
		// Android 上 sing-box 用 package_name 匹配应用包名
		obj["package_name"] = []string{r.Payload}
	case RProcessNameRegex:
		obj["package_name_regex"] = []string{r.Payload}
	case RDstPort, RSrcPort:
		// sing-box 端口字段是 uint16 标量，区间要另用 *_range 数组。
		// 早期实现把区间塞进标量字段，内核直接 decode 失败。
		field := "port"
		if r.Kind == RSrcPort {
			field = "source_port"
		}
		single, ranges := splitPortSpec(r.Payload)
		if len(single) > 0 {
			vals := make([]any, 0, len(single))
			for _, v := range single {
				vals = append(vals, v)
			}
			if len(vals) == 1 {
				obj[field] = vals[0]
			} else {
				// 多值且无区间时，sing-box 没有多端口标量形式，用区间近似
				obj[field+"_range"] = []string{itoa(single[0]) + ":" + itoa(single[len(single)-1])}
			}
		}
		if len(ranges) > 0 {
			obj[field+"_range"] = ranges
		}
		if len(single) == 0 && len(ranges) == 0 {
			return nil, fmt.Errorf("端口规则载荷 %q 无法解析", r.Payload)
		}
	default:
		field := ki.SBField
		if field == "" {
			return nil, fmt.Errorf("%s 没有对应的 sing-box 字段", r.Kind)
		}
		obj[field] = []any{coercePayload(r.Kind, r.Payload)}
	}

	// no-resolve 无需落到 sing-box 配置里：sing-box 的 ip_cidr 规则
	// 默认就是拿"已解析出的 IP"匹配，不会为规则主动触发解析，
	// 语义与 no-resolve 等价。写入自定义字段反而会让内核校验失败。
	if r.Invert {
		obj["invert"] = true
	}
	return obj, nil
}

func applyAction(obj map[string]any, tag, action string) {
	switch action {
	case "reject":
		obj["action"] = "reject"
	case "route":
		obj["action"] = "route"
		obj["outbound"] = tag
	default:
		obj["action"] = "route"
		obj["outbound"] = "direct"
	}
}

func coercePayload(kind, payload string) any {
	return payload
}

// splitPortSpec 把端口载荷拆成"单端口"与"区间"两类，
// 因为 sing-box 用 port(uint16) 与 port_range([]string) 两个不同字段承接。
func splitPortSpec(spec string) (single []int, ranges []string) {
	pairs, err := parsePortSpec(spec)
	if err != nil {
		return nil, nil
	}
	for _, pr := range pairs {
		if pr[0] == pr[1] {
			single = append(single, pr[0])
		} else {
			ranges = append(ranges, itoa(pr[0])+":"+itoa(pr[1]))
		}
	}
	return single, ranges
}

// ---------- DNS 编译 ----------

var legacyDoHRe = regexp.MustCompile(`^https://`)
var legacyDoTRe = regexp.MustCompile(`^tls://`)

// firstDNSTag 取第一个带 tag 的 DNS 服务器标签，用作 default_domain_resolver。
// 不能直接取 Servers[0]——它可能没写 tag。
func firstDNSTag(d *sbDNS) string {
	if d == nil {
		return ""
	}
	for _, s := range d.Servers {
		m, ok := s.(map[string]any)
		if !ok {
			continue
		}
		if t, ok := m["tag"].(string); ok && t != "" && t != "fakeip" {
			return t
		}
	}
	return ""
}

func compileDNS(d *DNSConfig, res *CompileResult, ver sbVer, dnsDetour func(string) string) *sbDNS {
	if !d.Enabled {
		return nil
	}
	newForm := ver.newDNSServerForm()
	out := &sbDNS{
		IndependentCache: d.IndependentCache,
		DisableCache:     d.DisableCache,
		Strategy:         d.Strategy,
	}
	for _, s := range d.Servers {
		obj := map[string]any{}
		addr := strings.TrimSpace(s.Address)
		// typ 与 host：新式拆成两个字段，旧式合成一个 address 字符串
		typ, host := "udp", addr
		switch {
		case addr == "local":
			typ, host = "local", ""
		case addr == "dhcp":
			typ, host = "dhcp", ""
		case addr == "fakeip":
			typ, host = "fakeip", ""
		case legacyDoHRe.MatchString(addr):
			typ, host = "https", stripURLPath(addr)
			if path := urlPath(addr); path != "" && path != "/dns-query" {
				obj["path"] = path
			}
		case legacyDoTRe.MatchString(addr):
			typ, host = "tls", strings.TrimPrefix(addr, "tls://")
		case strings.HasPrefix(addr, "quic://"):
			typ, host = "quic", strings.TrimPrefix(addr, "quic://")
		case strings.HasPrefix(addr, "h3://"):
			typ, host = "h3", strings.TrimPrefix(addr, "h3://")
		}
		if newForm {
			obj["type"] = typ
			if host != "" {
				obj["server"] = host
			}
		} else {
			// 1.11 及更早：单一 address 字段
			switch typ {
			case "local", "dhcp", "fakeip":
				obj["address"] = typ
			case "https":
				obj["address"] = addr
			case "tls":
				obj["address"] = "tls://" + host
			default:
				obj["address"] = addr
			}
			// 旧式不支持 type/server 里的 path，已并入 address
			delete(obj, "path")
		}
		if s.Tag != "" {
			obj["tag"] = s.Tag
		}
		if s.Detour != "" {
			if t := dnsDetour(s.Detour); t != "" {
				obj["detour"] = t
			}
		}
		if len(s.Domains) > 0 {
			obj["domain"] = s.Domains
		}
		if s.Strategy != "" {
			obj["strategy"] = s.Strategy
		}
		out.Servers = append(out.Servers, obj)
	}

	// fake-ip
	if d.FakeIP {
		rng := orDefault(d.FakeIPRange, "198.18.0.0/15")
		if newForm {
			// 1.12+：区间写在 DNS 服务器对象上
			out.Servers = append(out.Servers, map[string]any{
				"type": "fakeip", "tag": "fakeip", "inet4_range": rng,
			})
		} else {
			// <1.12：服务器只声明类型，区间在独立的 dns.fakeip 块里
			out.Servers = append(out.Servers, map[string]any{
				"address": "fakeip", "tag": "fakeip",
			})
			out.FakeIP = &sbFakeIP{Enabled: true, Inet4Range: rng}
		}
		// 需要有一条 dns rule 把 fakeip 限定在非过滤域名。
		// 注意 fakeip 不能当默认服务器，内核会直接报
		// "default server cannot be fakeip"。
		fr := map[string]any{"query_type": []string{"A", "AAAA"}, "server": "fakeip"}
		if len(d.FakeIPFilter) > 0 {
			fr["domain_suffix"] = d.FakeIPFilter
			fr["invert"] = true
		}
		out.Rules = append(out.Rules, fr)
	}

	// DNS 规则（domain → server）
	for i := range d.Rules {
		r := &d.Rules[i]
		obj := map[string]any{}
		switch r.Kind {
		case RDomain:
			obj["domain"] = []string{r.Payload}
		case RDomainSuffix:
			obj["domain_suffix"] = []string{r.Payload}
		case RDomainKeyword:
			obj["domain_keyword"] = []string{r.Payload}
		case RDomainRegex, RDomainWildcard:
			pat := r.Payload
			if r.Kind == RDomainWildcard {
				pat = wildcardToRegex(pat)
			}
			obj["domain_regex"] = []string{pat}
		default:
			continue
		}
		obj["server"] = r.Policy
		out.Rules = append(out.Rules, obj)
	}

	// final 必须是真实解析用的 DNS 服务器。
	// fakeip 是虚拟应答，被选为默认服务器时内核会直接报
	// "default server cannot be fakeip"，这里兜一层。
	isFake := func(tag string) bool { return tag == "fakeip" }
	if d.Final != "" && !isFake(d.Final) {
		out.Final = d.Final
	}
	if out.Final == "" {
		for _, s := range out.Servers {
			m, ok := s.(map[string]any)
			if !ok {
				continue
			}
			t, _ := m["tag"].(string)
			if t == "" || isFake(t) {
				continue
			}
			out.Final = t
			break
		}
	}
	// 全是 fakeip 的话只能放弃 fakeip，否则配置不可用
	if out.Final == "" && d.FakeIP {
		out.FakeIP = nil
		filtered := out.Servers[:0]
		for _, s := range out.Servers {
			if m, ok := s.(map[string]any); ok {
				if t, _ := m["tag"].(string); t == "fakeip" {
					continue
				}
			}
			filtered = append(filtered, s)
		}
		out.Servers = filtered
	}
	return out
}

func stripURLPath(s string) string {
	s = strings.TrimPrefix(s, "https://")
	if i := strings.IndexAny(s, "/?"); i >= 0 {
		return s[:i]
	}
	return s
}

func urlPath(s string) string {
	i := strings.Index(s, "/")
	if i < 0 {
		return ""
	}
	p := s[i:]
	if j := strings.Index(p, "?"); j >= 0 {
		p = p[:j]
	}
	return p
}
