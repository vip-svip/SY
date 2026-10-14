// ============================================================
//
//	importcfg.go — 多格式配置导入
//	· 分享链接 / base64 订阅
//	· Clash / mihomo YAML（proxies / proxy-groups / rules / rule-providers / dns）
//	· Shadowrocket / Surge .conf（[General] [Proxy] [Proxy Group] [Rule] [Host]）
//	· sing-box JSON（outbounds / route.rules）
//
//	统一落到 Profile 模型。
//
// ============================================================
package main

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strings"

	"gopkg.in/yaml.v3"
)

// DetectFormat 识别配置文本的格式
func DetectFormat(text string) string {
	t := strings.TrimSpace(text)
	if t == "" {
		return "empty"
	}
	// base64 订阅
	if !strings.Contains(t, ":") && !strings.Contains(t, "\n") || isLikelyB64(t) {
		if dec, ok := b64Any(strings.ReplaceAll(t, "\n", "")); ok {
			inner := string(dec)
			if strings.Contains(inner, "://") || strings.Contains(inner, "proxies:") ||
				strings.Contains(inner, "[Proxy]") {
				return "base64-sub"
			}
		}
	}
	if strings.HasPrefix(t, "{") {
		if strings.Contains(t, "\"outbounds\"") {
			return "singbox-json"
		}
		return "json-unknown"
	}
	if strings.Contains(t, "[General]") || strings.Contains(t, "[Proxy]") ||
		strings.Contains(t, "[Rule]") || strings.Contains(t, "[Proxy Group]") {
		return "shadowrocket-conf"
	}
	// YAML：出现顶格的关键字
	for _, line := range strings.Split(t, "\n") {
		l := strings.TrimRight(line, "\r")
		if strings.HasPrefix(l, "proxies:") || strings.HasPrefix(l, "proxy-groups:") ||
			strings.HasPrefix(l, "rules:") || strings.HasPrefix(l, "rule-providers:") ||
			strings.HasPrefix(l, "proxy-providers:") {
			return "clash-yaml"
		}
	}
	// 分享链接
	linkRe := regexp.MustCompile(`(?m)^\s*(vmess|vless|trojan|ss|ssr|hysteria2|hy2|tuic|socks5?)://`)
	if linkRe.MatchString(t) {
		return "share-links"
	}
	return "unknown"
}

func isLikelyB64(s string) bool {
	s = strings.ReplaceAll(strings.TrimSpace(s), "\n", "")
	if len(s) < 16 {
		return false
	}
	for _, c := range s {
		if !(c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' ||
			c == '+' || c == '/' || c == '=' || c == '-' || c == '_') {
			return false
		}
	}
	return true
}

// ImportConfig 按格式导入为 Profile
func ImportConfig(text, hint string) (*Profile, error) {
	format := hint
	if format == "" || format == "auto" {
		format = DetectFormat(text)
	}
	switch format {
	case "base64-sub":
		dec, ok := b64Any(strings.ReplaceAll(strings.TrimSpace(text), "\n", ""))
		if !ok {
			return nil, fmt.Errorf("base64 订阅无法解码")
		}
		return ImportConfig(string(dec), "auto")
	case "share-links":
		nodes, errs := ParseLinks(text)
		p := &Profile{Nodes: nodes, Source: "share-links"}
		p.Warnings = append(p.Warnings, errs...)
		finishProfile(p)
		return p, nil
	case "clash-yaml":
		return importClashYAML(text)
	case "shadowrocket-conf":
		return importShadowrocketConf(text)
	case "singbox-json":
		return importSingBoxJSON(text)
	case "empty":
		return nil, fmt.Errorf("内容为空")
	}
	return nil, fmt.Errorf("无法识别的配置格式（%s）", format)
}

// finishProfile 补齐缺省值
func finishProfile(p *Profile) {
	if len(p.General.LogLevel) == 0 {
		p.General.LogLevel = "warn"
	}
	if p.General.MixedPort == 0 {
		p.General.MixedPort = 2080
	}
	if p.General.TunStack == "" {
		p.General.TunStack = "mixed"
	}
	if p.General.ClashAPIPort == 0 {
		p.General.ClashAPIPort = 9090
	}
	// 没有任何规则时，给出一个最小可用规则集
	if len(p.Rules) == 0 && len(p.Nodes) > 0 {
		p.Rules = []Rule{
			{Kind: RGeoSite, Payload: "category-ads-all", Policy: PolicyReject, Enabled: true, Note: "默认：拦截广告域名"},
			{Kind: RGeoSite, Payload: "cn", Policy: PolicyDirect, Enabled: true, Note: "默认：国内域名直连"},
			{Kind: RGeoIP, Payload: "cn", Policy: PolicyDirect, Enabled: true, Note: "默认：国内 IP 直连"},
			{Kind: RMatch, Payload: "*", Policy: PolicyProxy, Enabled: true, Note: "默认：其余走代理"},
		}
		p.Warnings = append(p.Warnings, "导入内容没有规则，已套用默认规则集（广告拦截 / 国内直连 / 其余走代理）")
	}
}

// ---------- Clash / mihomo YAML ----------

type clashDoc struct {
	Port           int                       `yaml:"port"`
	SocksPort      int                       `yaml:"socks-port"`
	MixedPort      int                       `yaml:"mixed-port"`
	AllowLan       bool                      `yaml:"allow-lan"`
	Mode           string                    `yaml:"mode"`
	LogLevel       string                    `yaml:"log-level"`
	ExternalCtrl   string                    `yaml:"external-controller"`
	Secret         string                    `yaml:"secret"`
	DNS            map[string]any            `yaml:"dns"`
	Proxies        []map[string]any          `yaml:"proxies"`
	ProxyGroups    []map[string]any          `yaml:"proxy-groups"`
	Rules          []string                  `yaml:"rules"`
	RuleProviders  map[string]map[string]any `yaml:"rule-providers"`
	ProxyProviders map[string]map[string]any `yaml:"proxy-providers"`
	Tun            map[string]any            `yaml:"tun"`
}

func importClashYAML(text string) (*Profile, error) {
	var d clashDoc
	if err := yaml.Unmarshal([]byte(text), &d); err != nil {
		return nil, fmt.Errorf("解析 Clash YAML 失败: %v", err)
	}
	p := &Profile{Source: "clash-yaml"}

	// 节点
	for _, m := range d.Proxies {
		n, err := clashProxyToNode(m)
		if err != nil {
			p.Warnings = append(p.Warnings, fmt.Sprintf("节点 %v 跳过：%v", m["name"], err))
			continue
		}
		p.Nodes = append(p.Nodes, n)
	}
	// 策略组
	for _, m := range d.ProxyGroups {
		g := ProxyGroup{
			Name:    str(m, "name"),
			Type:    strings.ToLower(str(m, "type")),
			Proxies: strSlice(m["proxies"]),
			URL:     str(m, "url"),
			Icon:    str(m, "icon"),
		}
		if v, ok := m["interval"].(int); ok {
			g.Interval = v
		}
		if v, ok := m["tolerance"].(int); ok {
			g.Tolerance = v
		}
		g.Strategy = str(m, "strategy")
		if g.Name == "" {
			continue
		}
		if g.Type == "" {
			g.Type = GroupSelect
		}
		p.Groups = append(p.Groups, g)
	}
	// 规则
	for i, line := range d.Rules {
		r, err := ParseRuleLine(line, i+1)
		if err != nil {
			p.Warnings = append(p.Warnings, fmt.Sprintf("规则第 %d 条跳过：%v", i+1, err))
			continue
		}
		p.Rules = append(p.Rules, r)
	}
	// 规则集
	for name, m := range d.RuleProviders {
		rs := RuleSet{
			Name:     name,
			Type:     "remote",
			URL:      str(m, "url"),
			Path:     str(m, "path"),
			Format:   "source",
			Category: str(m, "behavior"),
			Enabled:  true,
		}
		if v, ok := m["interval"].(int); ok {
			rs.Interval = v
		}
		p.RuleSets = append(p.RuleSets, rs)
	}
	for name, m := range d.ProxyProviders {
		rs := RuleSet{
			Name: name, Type: "remote", URL: str(m, "url"),
			Path: str(m, "path"), Format: "source", Category: "proxy", Enabled: true,
		}
		p.RuleSets = append(p.RuleSets, rs)
	}

	// DNS
	if d.DNS != nil {
		p.DNS.Enabled = boolOf(d.DNS["enable"])
		if p.DNS.Enabled {
			mode := strings.ToLower(str(d.DNS, "enhanced-mode"))
			if mode == "fake-ip" {
				p.DNS.FakeIP = true
				p.DNS.FakeIPRange = orDefault(str(d.DNS, "fake-ip-range"), "198.18.0.0/15")
				p.DNS.FakeIPFilter = strSlice(d.DNS["fake-ip-filter"])
			}
			if v := strSlice(d.DNS["nameserver"]); len(v) > 0 {
				for i, a := range v {
					p.DNS.Servers = append(p.DNS.Servers, DNSServer{
						Tag: fmt.Sprintf("ns%d", i+1), Address: a, Detour: "proxy",
					})
				}
			}
			if v := strSlice(d.DNS["fallback"]); len(v) > 0 {
				for i, a := range v {
					p.DNS.Servers = append(p.DNS.Servers, DNSServer{
						Tag: fmt.Sprintf("fb%d", i+1), Address: a, Detour: "direct",
					})
				}
			}
			if str(d.DNS, "fallback-dns-server") != "" {
				p.DNS.Servers = append(p.DNS.Servers, DNSServer{
					Tag: "sys", Address: str(d.DNS, "fallback-dns-server"),
				})
			}
			if len(p.DNS.Servers) == 0 {
				p.DNS.Servers = []DNSServer{
					{Tag: "proxy-dns", Address: "https://1.1.1.1/dns-query", Detour: "proxy"},
					{Tag: "local-dns", Address: "223.5.5.5", Detour: "direct"},
				}
			}
			if len(p.DNS.Servers) > 0 {
				p.DNS.Final = p.DNS.Servers[0].Tag
			}
		}
	}

	// 通用
	if d.MixedPort > 0 {
		p.General.MixedPort = d.MixedPort
	} else if d.Port > 0 {
		p.General.MixedPort = d.Port
	}
	p.General.LogLevel = orDefault(d.LogLevel, "warn")
	p.General.DefaultMode = orDefault(d.Mode, "rule")
	if d.ExternalCtrl != "" {
		p.General.ClashAPI = true
		if i := strings.LastIndex(d.ExternalCtrl, ":"); i > 0 {
			p.General.ClashAPIPort = atoiSafe(d.ExternalCtrl[i+1:])
		}
		p.General.ClashAPISecret = d.Secret
	}
	if d.Tun != nil && boolOf(d.Tun["enable"]) {
		p.General.TunEnabled = true
		p.General.TunStack = orDefault(strings.ToLower(str(d.Tun, "stack")), "mixed")
		if v, ok := d.Tun["mtu"].(int); ok {
			p.General.TunMTU = v
		}
	}

	p.Nodes = dedupNodes(p.Nodes, p)
	finishProfile(p)
	return p, nil
}

func clashProxyToNode(m map[string]any) (Node, error) {
	n := Node{Name: str(m, "name"), Source: "clash"}
	typ := strings.ToLower(str(m, "type"))
	n.Server = str(m, "server")
	n.Port = intOf(m["port"])
	n.SNI = orDefault(str(m, "sni"), str(m, "servername"))
	n.Insecure = boolOf(m["skip-cert-verify"])
	n.Network = strings.ToLower(str(m, "network"))
	n.WSPath = str(m, "ws-path")
	if hdrs, ok := m["ws-headers"].(map[string]any); ok {
		n.WSHost = str(hdrs, "Host")
	}
	// Clash 的 ws-opts 是嵌套对象：{path: "/x", headers: {Host: "h"}}
	if wso, ok := m["ws-opts"].(map[string]any); ok {
		if v := str(wso, "path"); v != "" {
			n.WSPath = v
		}
		if hdrs, ok := wso["headers"].(map[string]any); ok {
			if v := orDefault(str(hdrs, "Host"), str(hdrs, "host")); v != "" {
				n.WSHost = v
			}
		}
	}
	// grpc-opts 同理
	if go_, ok := m["grpc-opts"].(map[string]any); ok {
		if v := str(go_, "grpc-service-name"); v != "" {
			n.GRPCService = v
		}
	}
	// 部分配置把 ws path 直接写成 ws-path，已在上面处理
	n.GRPCService = orDefault(n.GRPCService, str(m, "grpc-service-name"))
	if alpn := strSlice(m["alpn"]); len(alpn) > 0 {
		n.ALPN = alpn
	}

	switch typ {
	case "ss", "shadowsocks":
		n.Type = "shadowsocks"
		n.Method = str(m, "cipher")
		n.Password = str(m, "password")
		n.Plugin = str(m, "plugin")
		n.PluginOpts = str(m, "plugin-opts")
	case "ssr":
		n.Type = "shadowsocksr"
		n.Method = str(m, "cipher")
		n.Password = str(m, "password")
		n.SSRProtocol = str(m, "protocol")
		n.SSRObfs = str(m, "obfs")
	case "vmess":
		n.Type = "vmess"
		n.UUID = str(m, "uuid")
		n.AlterID = intOf(m["alterId"])
		n.Method = str(m, "cipher")
		n.TLS = boolOf(m["tls"])
	case "vless":
		n.Type = "vless"
		n.UUID = str(m, "uuid")
		n.Flow = str(m, "flow")
		n.TLS = boolOf(m["tls"])
		if ro, ok := m["reality-opts"].(map[string]any); ok {
			n.RealityPBK = str(ro, "public-key")
			n.RealitySID = str(ro, "short-id")
		}
	case "trojan":
		n.Type = "trojan"
		n.Password = str(m, "password")
		n.TLS = true
	case "hysteria2", "hysteria":
		n.Type = "hysteria2"
		n.Password = str(m, "password")
		n.TLS = true
		if obfs := str(m, "obfs"); obfs != "" {
			n.Obfs = obfs
			n.ObfsPass = str(m, "obfs-password")
		}
	case "tuic":
		n.Type = "tuic"
		n.UUID = str(m, "uuid")
		n.Password = str(m, "password")
		n.TLS = true
	case "http", "https":
		n.Type = "http"
		n.Username = str(m, "username")
		n.Password = str(m, "password")
		n.TLS = typ == "https"
	case "socks5", "socks":
		n.Type = "socks"
		n.Username = str(m, "username")
		n.Password = str(m, "password")
	case "wireguard":
		n.Type = "wireguard"
		n.PrivateKey = str(m, "private-key")
		n.PeerPublicKey = str(m, "public-key")
		n.PreSharedKey = str(m, "pre-shared-key")
		n.MTU = intOf(m["mtu"])
	case "direct":
		n.Type = "direct"
	case "snell":
		return n, fmt.Errorf("sing-box 不支持 snell 协议")
	default:
		return n, fmt.Errorf("未知节点类型 %q", typ)
	}
	if n.Name == "" {
		n.Name = n.Server
	}
	if n.Server == "" || n.Port == 0 {
		return n, fmt.Errorf("缺少 server 或 port")
	}
	return n, nil
}

func dedupNodes(in []Node, p *Profile) []Node {
	seen := map[string]int{}
	out := make([]Node, 0, len(in))
	for _, n := range in {
		n.Name = uniqueName(seen, n.Name)
		out = append(out, n)
	}
	return out
}

// ---------- Shadowrocket / Surge .conf ----------

func importShadowrocketConf(text string) (*Profile, error) {
	p := &Profile{Source: "shadowrocket-conf"}
	section := ""
	seen := map[string]int{}

	for _, raw := range strings.Split(text, "\n") {
		line := strings.TrimSpace(strings.TrimSuffix(raw, "\r"))
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, ";") {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			section = strings.ToLower(strings.Trim(line, "[]"))
			continue
		}
		switch section {
		case "general":
			k, v, ok := splitKV(line)
			if !ok {
				continue
			}
			applyGeneralKV(&p.General, &p.DNS, strings.ToLower(k), v)
		case "proxy":
			name, val, ok := splitKV(line)
			if !ok {
				continue
			}
			n, err := shadowrocketProxyToNode(name, val)
			if err != nil {
				p.Warnings = append(p.Warnings, fmt.Sprintf("节点 %q 跳过：%v", name, err))
				continue
			}
			if n.Type == "direct" || n.Type == "reject" {
				continue
			}
			n.Name = uniqueName(seen, n.Name)
			p.Nodes = append(p.Nodes, n)
		case "proxy group":
			name, val, ok := splitKV(line)
			if !ok {
				continue
			}
			g := shadowrocketGroupToGroup(name, val)
			if g != nil {
				p.Groups = append(p.Groups, *g)
			}
		case "rule":
			r, err := ParseRuleLine(line, 0)
			if err != nil {
				p.Warnings = append(p.Warnings, fmt.Sprintf("规则 %q 跳过：%v", firstToken(line, 40), err))
				continue
			}
			p.Rules = append(p.Rules, r)
		case "host":
			p.Warnings = append(p.Warnings, fmt.Sprintf("Host 映射规则 %q 未导入（hosts 由 DNS 拦截模块统一管理）", firstToken(line, 40)))
		case "url rewrite":
			p.Warnings = append(p.Warnings, fmt.Sprintf("URL 重写规则 %q 未导入（sing-box 无对应能力）", firstToken(line, 40)))
		case "mitm":
			p.Warnings = append(p.Warnings, "MITM 段落未导入（本模块的 MITM 由独立引擎负责，见「MITM 解密」页）")
		}
	}
	if len(p.Nodes) == 0 && len(p.Groups) == 0 {
		return nil, fmt.Errorf("没有解析到任何节点或策略组")
	}
	finishProfile(p)
	return p, nil
}

func splitKV(line string) (string, string, bool) {
	i := strings.Index(line, "=")
	if i < 0 {
		return "", "", false
	}
	return strings.TrimSpace(line[:i]), strings.TrimSpace(line[i+1:]), true
}

func applyGeneralKV(g *GeneralConfig, d *DNSConfig, k, v string) {
	switch k {
	case "dns-server":
		for i, a := range strings.Split(v, ",") {
			a = strings.TrimSpace(a)
			if a == "" {
				continue
			}
			if a == "system" {
				a = "local"
			}
			d.Enabled = true
			d.Servers = append(d.Servers, DNSServer{
				Tag: fmt.Sprintf("dns%d", i+1), Address: a, Detour: "direct",
			})
		}
	case "fallback-dns-server":
		for i, a := range strings.Split(v, ",") {
			a = strings.TrimSpace(a)
			if a == "" || a == "system" {
				continue
			}
			d.Enabled = true
			d.Servers = append(d.Servers, DNSServer{
				Tag: fmt.Sprintf("fb%d", i+1), Address: a, Detour: "proxy",
			})
		}
	case "ipv6", "prefer-ipv6":
		if strings.EqualFold(v, "true") {
			d.Strategy = "prefer_ipv6"
		} else if d.Strategy == "" {
			d.Strategy = "prefer_ipv4"
		}
	case "log-level":
		g.LogLevel = v
	case "skip-proxy", "bypass-system", "tun-excluded-routes", "dns-direct-system":
		// 这些是 Shadowrocket 的系统级旁路设置，本模块由防泄露链与路由规则承担
	}
}

// Shadowrocket 节点行: type, server, port, k=v, k=v ...
func shadowrocketProxyToNode(name, val string) (Node, error) {
	parts := strings.Split(val, ",")
	for i := range parts {
		parts[i] = strings.TrimSpace(parts[i])
	}
	if len(parts) == 0 {
		return Node{}, fmt.Errorf("空定义")
	}
	typ := strings.ToLower(parts[0])
	n := Node{Name: name, Source: "shadowrocket"}
	kv := map[string]string{}
	var positional []string
	for _, p := range parts[1:] {
		if strings.Contains(p, "=") {
			a := strings.SplitN(p, "=", 2)
			kv[strings.ToLower(strings.TrimSpace(a[0]))] = strings.TrimSpace(a[1])
		} else {
			positional = append(positional, p)
		}
	}
	switch typ {
	case "direct":
		n.Type = "direct"
		return n, nil
	case "reject", "reject-drop":
		n.Type = "reject"
		return n, nil
	}
	if len(positional) < 2 {
		return n, fmt.Errorf("缺少 server 或 port")
	}
	n.Server = positional[0]
	n.Port = atoiSafe(positional[1])
	if n.Port == 0 {
		// Shadowrocket 允许省略端口写在 server:port 里
		if h, pp, err := splitHostPort(positional[0]); err == nil {
			n.Server, n.Port = h, pp
		}
	}

	switch typ {
	case "ss", "shadowsocks":
		n.Type = "shadowsocks"
		n.Method = orDefault(kv["encrypt-method"], kv["method"])
		n.Password = kv["password"]
		n.Plugin = kv["obfs"]
	case "ssr":
		n.Type = "shadowsocksr"
		n.Method = kv["encrypt-method"]
		n.Password = kv["password"]
		n.SSRProtocol = kv["protocol"]
		n.SSRObfs = kv["obfs"]
	case "vmess":
		n.Type = "vmess"
		n.UUID = orDefault(kv["username"], kv["uuid"])
		n.AlterID = atoiSafe(kv["alterid"])
		n.Network = orDefault(kv["obfs"], "tcp")
		if kv["ws"] == "true" {
			n.Network = "ws"
		}
		n.WSPath = orDefault(kv["ws-path"], kv["path"])
		n.WSHost = kv["ws-headers"]
	case "vless":
		n.Type = "vless"
		n.UUID = orDefault(kv["username"], kv["uuid"])
		n.Network = orDefault(kv["obfs"], "tcp")
		if kv["ws"] == "true" {
			n.Network = "ws"
		}
		n.WSPath = kv["ws-path"]
	case "trojan":
		n.Type = "trojan"
		n.Password = kv["password"]
		n.TLS = true
	case "hysteria2", "hysteria":
		n.Type = "hysteria2"
		n.Password = kv["password"]
		n.TLS = true
		n.Obfs = kv["obfs"]
	case "tuic":
		n.Type = "tuic"
		n.UUID = kv["uuid"]
		n.Password = kv["password"]
		n.TLS = true
	case "http", "https":
		n.Type = "http"
		n.Username = kv["username"]
		n.Password = kv["password"]
		n.TLS = typ == "https"
	case "socks5", "socks":
		n.Type = "socks"
		n.Username = kv["username"]
		n.Password = kv["password"]
	case "snell":
		return n, fmt.Errorf("sing-box 不支持 snell")
	default:
		return n, fmt.Errorf("未知类型 %q", typ)
	}

	if kv["tls"] == "true" || kv["over-tls"] == "true" {
		n.TLS = true
	}
	n.SNI = orDefault(kv["sni"], kv["tls-host"])
	if kv["skip-cert-verify"] == "true" {
		n.Insecure = true
	}
	if n.Server == "" || n.Port == 0 {
		return n, fmt.Errorf("缺少 server 或 port")
	}
	return n, nil
}

// Shadowrocket 策略组行: type, member, member, ..., url=..., interval=...
func shadowrocketGroupToGroup(name, val string) *ProxyGroup {
	parts := strings.Split(val, ",")
	for i := range parts {
		parts[i] = strings.TrimSpace(parts[i])
	}
	if len(parts) < 2 {
		return nil
	}
	g := &ProxyGroup{Name: name}
	switch strings.ToLower(parts[0]) {
	case "select":
		g.Type = GroupSelect
	case "url-test":
		g.Type = GroupURLTest
	case "fallback":
		g.Type = GroupFallback
	case "load-balance":
		g.Type = GroupLoadBalance
	case "relay":
		g.Type = GroupRelay
	default:
		g.Type = GroupSelect
	}
	for _, p := range parts[1:] {
		if strings.Contains(p, "=") {
			a := strings.SplitN(p, "=", 2)
			k := strings.ToLower(strings.TrimSpace(a[0]))
			v := strings.TrimSpace(a[1])
			switch k {
			case "url":
				g.URL = v
			case "interval":
				g.Interval = atoiSafe(v)
			case "tolerance":
				g.Tolerance = atoiSafe(v)
			case "strategy":
				g.Strategy = v
			}
			continue
		}
		if p != "" {
			g.Proxies = append(g.Proxies, p)
		}
	}
	return g
}

// ---------- sing-box JSON ----------

func importSingBoxJSON(text string) (*Profile, error) {
	var doc map[string]any
	if err := json.Unmarshal([]byte(text), &doc); err != nil {
		return nil, fmt.Errorf("sing-box JSON 解析失败: %v", err)
	}
	p := &Profile{Source: "singbox-json"}
	seen := map[string]int{}

	if obs, ok := doc["outbounds"].([]any); ok {
		for _, o := range obs {
			om, ok := o.(map[string]any)
			if !ok {
				continue
			}
			typ := strings.ToLower(str(om, "type"))
			switch typ {
			case "direct", "block", "dns", "selector", "urltest":
				if typ == "selector" || typ == "urltest" {
					g := ProxyGroup{
						Name:    str(om, "tag"),
						Type:    map[string]string{"selector": GroupSelect, "urltest": GroupURLTest}[typ],
						Proxies: strSlice(om["outbounds"]),
					}
					if g.Name != "" {
						p.Groups = append(p.Groups, g)
					}
				}
				continue
			}
			n, err := singboxOutboundToNode(om)
			if err != nil {
				p.Warnings = append(p.Warnings, fmt.Sprintf("出站 %v 跳过：%v", om["tag"], err))
				continue
			}
			n.Name = uniqueName(seen, n.Name)
			p.Nodes = append(p.Nodes, n)
		}
	}
	if r, ok := doc["route"].(map[string]any); ok {
		if rules, ok := r["rules"].([]any); ok {
			for _, rr := range rules {
				rm, ok := rr.(map[string]any)
				if !ok {
					continue
				}
				if sub, err := singboxRuleToRule(rm); err == nil && sub != nil {
					p.Rules = append(p.Rules, *sub)
				}
			}
		}
		if f := str(r, "final"); f != "" {
			p.General.FinalPolicy = f
		}
	}
	if len(p.Nodes) == 0 && len(p.Groups) == 0 {
		return nil, fmt.Errorf("没有解析到任何出站")
	}
	finishProfile(p)
	return p, nil
}

func singboxOutboundToNode(om map[string]any) (Node, error) {
	n := Node{Name: str(om, "tag"), Source: "singbox-json"}
	n.Server = str(om, "server")
	n.Port = intOf(om["server_port"])
	switch strings.ToLower(str(om, "type")) {
	case "vmess":
		n.Type = "vmess"
		n.UUID = str(om, "uuid")
		n.AlterID = intOf(om["alter_id"])
	case "vless":
		n.Type = "vless"
		n.UUID = str(om, "uuid")
		n.Flow = str(om, "flow")
	case "trojan":
		n.Type = "trojan"
		n.Password = str(om, "password")
	case "shadowsocks":
		n.Type = "shadowsocks"
		n.Method = str(om, "method")
		n.Password = str(om, "password")
	case "hysteria2":
		n.Type = "hysteria2"
		n.Password = str(om, "password")
	case "tuic":
		n.Type = "tuic"
		n.UUID = str(om, "uuid")
		n.Password = str(om, "password")
	case "http":
		n.Type = "http"
		n.Username = str(om, "username")
		n.Password = str(om, "password")
	case "socks":
		n.Type = "socks"
		n.Username = str(om, "username")
		n.Password = str(om, "password")
	case "wireguard":
		n.Type = "wireguard"
		n.PrivateKey = str(om, "private_key")
		n.PeerPublicKey = str(om, "peer_public_key")
	default:
		return n, fmt.Errorf("不支持的出站类型 %q", str(om, "type"))
	}
	if tls, ok := om["tls"].(map[string]any); ok {
		n.TLS = boolOf(tls["enabled"])
		n.SNI = str(tls, "server_name")
		n.Insecure = boolOf(tls["insecure"])
		n.ALPN = strSlice(tls["alpn"])
		if ro, ok := tls["reality"].(map[string]any); ok && boolOf(ro["enabled"]) {
			n.RealityPBK = str(ro, "public_key")
			n.RealitySID = str(ro, "short_id")
		}
		if uo, ok := tls["utls"].(map[string]any); ok {
			n.Fingerprint = str(uo, "fingerprint")
		}
	}
	if tr, ok := om["transport"].(map[string]any); ok {
		n.Network = strings.ToLower(str(tr, "type"))
		n.WSPath = str(tr, "path")
		n.GRPCService = str(tr, "service_name")
		if hdrs, ok := tr["headers"].(map[string]any); ok {
			n.WSHost = str(hdrs, "Host")
		}
	}
	if n.Server == "" || n.Port == 0 {
		return n, fmt.Errorf("缺少 server 或 server_port")
	}
	return n, nil
}

// sing-box 路由规则 → 内部规则（尽力而为，复杂规则可能丢失）
func singboxRuleToRule(rm map[string]any) (*Rule, error) {
	action := str(rm, "action")
	outbound := str(rm, "outbound")
	policy := PolicyProxy
	switch action {
	case "reject":
		policy = PolicyReject
	case "route":
		switch outbound {
		case "direct":
			policy = PolicyDirect
		case "block":
			policy = PolicyReject
		case "":
			policy = PolicyProxy
		default:
			policy = outbound
		}
	default:
		if action == "" || action == "sniff" || action == "hijack-dns" {
			return nil, nil
		}
	}
	type pair struct{ kind, field string }
	order := []pair{
		{RDomain, "domain"},
		{RDomainSuffix, "domain_suffix"},
		{RDomainKeyword, "domain_keyword"},
		{RDomainRegex, "domain_regex"},
		{RIPCIDR, "ip_cidr"},
		{RSrcIPCIDR, "source_ip_cidr"},
		{RDstPort, "port"},
		{RSrcPort, "source_port"},
		{RProcessName, "package_name"},
		{RProcessPath, "process_name"},
		{RProtocol, "protocol"},
		{RNetwork, "network"},
		{RRuleSet, "rule_set"},
	}
	for _, p := range order {
		v, ok := rm[p.field]
		if !ok {
			continue
		}
		items := strSlice(v)
		if len(items) == 0 {
			continue
		}
		return &Rule{Kind: p.kind, Payload: items[0], Policy: policy, Enabled: true,
			Note: "由 sing-box 配置导入，多值规则仅保留首个"}, nil
	}
	if boolOf(rm["ip_is_private"]) {
		return &Rule{Kind: RIPCIDR, Payload: "10.0.0.0/8", Policy: policy, Enabled: true,
			Note: "由 ip_is_private 近似转换"}, nil
	}
	return nil, nil
}

// ---------- YAML 取值助手 ----------

func str(m map[string]any, k string) string {
	if m == nil {
		return ""
	}
	v, ok := m[k]
	if !ok || v == nil {
		return ""
	}
	switch t := v.(type) {
	case string:
		return t
	case int:
		return itoa(t)
	case int64:
		return itoa(int(t))
	case float64:
		return trimFloat(t)
	case bool:
		if t {
			return "true"
		}
		return "false"
	case map[string]any:
		// ws-opts 之类的嵌套对象，取 host/path
		if h := str(t, "host"); h != "" {
			return h
		}
		if p := str(t, "path"); p != "" {
			return p
		}
	}
	return ""
}

func trimFloat(f float64) string {
	if f == float64(int64(f)) {
		return itoa(int(f))
	}
	return strings.TrimRight(strings.TrimRight(fmt.Sprintf("%.4f", f), "0"), ".")
}

func intOf(v any) int {
	switch t := v.(type) {
	case int:
		return t
	case int64:
		return int(t)
	case float64:
		return int(t)
	case string:
		return atoiSafe(t)
	}
	return 0
}

func boolOf(v any) bool {
	switch t := v.(type) {
	case bool:
		return t
	case string:
		return strings.EqualFold(t, "true") || t == "1"
	case int:
		return t != 0
	}
	return false
}

func strSlice(v any) []string {
	switch t := v.(type) {
	case []string:
		return t
	case []any:
		out := make([]string, 0, len(t))
		for _, x := range t {
			switch y := x.(type) {
			case string:
				out = append(out, y)
			case int:
				out = append(out, itoa(y))
			case float64:
				out = append(out, trimFloat(y))
			}
		}
		return out
	case string:
		if t == "" {
			return nil
		}
		return []string{t}
	}
	return nil
}
