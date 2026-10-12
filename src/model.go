// ============================================================
//
//	model.go — 统一数据模型
//	节点 / 策略组 / 规则 / 规则集 / DNS / 通用配置
//
//	设计目标：把 Shadowrocket、Clash、Surge、sing-box 四家的
//	表达统一到一套内部模型上，再单向编译成 sing-box 配置。
//	内部模型只做"表达"，不绑定任何一家内核的字段名。
//
// ============================================================
package main

import (
	"sort"
	"strings"
)

// ---------- 节点 ----------

// Node 一个代理节点。字段覆盖 Shadowrocket 支持的协议集。
type Node struct {
	Name    string `json:"name"`
	Type    string `json:"type"` // vmess vless trojan shadowsocks hysteria2 tuic http socks wireguard ssh
	Server  string `json:"server"`
	Port    int    `json:"port"`
	UUID    string `json:"uuid,omitempty"`
	AlterID int    `json:"alter_id,omitempty"`
	Flow    string `json:"flow,omitempty"`
	// shadowsocks / ssr
	Method     string `json:"method,omitempty"`
	Password   string `json:"password,omitempty"`
	SSRProtocol string `json:"ssr_protocol,omitempty"`
	SSRProtocolParam string `json:"ssr_protocol_param,omitempty"`
	SSRObfs    string `json:"ssr_obfs,omitempty"`
	SSRObfsParam string `json:"ssr_obfs_param,omitempty"`
	Plugin     string `json:"plugin,omitempty"`
	PluginOpts string `json:"plugin_opts,omitempty"`
	// tls 家族
	TLS         bool     `json:"tls,omitempty"`
	SNI         string   `json:"sni,omitempty"`
	Insecure    bool     `json:"insecure,omitempty"`
	ALPN        []string `json:"alpn,omitempty"`
	Fingerprint string   `json:"fingerprint,omitempty"`
	RealityPBK  string   `json:"reality_public_key,omitempty"`
	RealitySID  string   `json:"reality_short_id,omitempty"`
	// 传输层
	Network     string `json:"network,omitempty"` // tcp ws grpc http h2 quic
	WSPath      string `json:"ws_path,omitempty"`
	WSHost      string `json:"ws_host,omitempty"`
	GRPCService string `json:"grpc_service,omitempty"`
	// hysteria2 / tuic
	UpMbps   int    `json:"up_mbps,omitempty"`
	DownMbps int    `json:"down_mbps,omitempty"`
	Obfs     string `json:"obfs,omitempty"`
	ObfsPass string `json:"obfs_password,omitempty"`
	// http / socks
	Username string `json:"username,omitempty"`
	// wireguard
	PrivateKey string `json:"private_key,omitempty"`
	PeerPublicKey string `json:"peer_public_key,omitempty"`
	PreSharedKey string `json:"pre_shared_key,omitempty"`
	LocalAddress []string `json:"local_address,omitempty"`
	MTU          int      `json:"mtu,omitempty"`
	// 元数据
	Source  string `json:"source,omitempty"` // 来源：manual / sub:<url> / file
	RawLink string `json:"raw_link,omitempty"`
	// Extra 承载各家内核的私有/新增字段，编译时按需读取，
	// 避免每加一个字段就动结构体。
	Extra map[string]any `json:"extra,omitempty"`
}

// ---------- 策略组 ----------

const (
	GroupSelect      = "select"
	GroupURLTest     = "url-test"
	GroupFallback    = "fallback"
	GroupLoadBalance = "load-balance"
	GroupRelay       = "relay"
)

// ProxyGroup 一个策略组。proxies 里的名字既可指节点也可指另一个组。
type ProxyGroup struct {
	Name      string   `json:"name"`
	Type      string   `json:"type"`
	Proxies   []string `json:"proxies"`
	URL       string   `json:"url,omitempty"`
	Interval  int      `json:"interval,omitempty"`
	Tolerance int      `json:"tolerance,omitempty"`
	Strategy  string   `json:"strategy,omitempty"` // load-balance: consistent-hashing / round-robin / sticky-sessions
	Lazy      bool     `json:"lazy,omitempty"`
	DisableUDP bool    `json:"disable_udp,omitempty"`
	Icon      string   `json:"icon,omitempty"`
}

// ---------- 规则 ----------

// 规则类型（Shadowrocket / Clash / Surge 语法超集）
const (
	RDomain        = "DOMAIN"
	RDomainSuffix  = "DOMAIN-SUFFIX"
	RDomainKeyword = "DOMAIN-KEYWORD"
	RDomainWildcard = "DOMAIN-WILDCARD"
	RDomainRegex   = "DOMAIN-REGEX"
	RIPCIDR        = "IP-CIDR"
	RIPCIDR6       = "IP-CIDR6"
	RIPASN         = "IP-ASN"
	RGeoIP         = "GEOIP"
	RGeoSite       = "GEOSITE"
	RSrcIPCIDR     = "SRC-IP-CIDR"
	RSrcPort       = "SRC-PORT"
	RDstPort       = "DEST-PORT"
	RInPort        = "IN-PORT"
	RProcessName   = "PROCESS-NAME"
	RProcessPath   = "PROCESS-PATH"
	RProcessNameRegex = "PROCESS-NAME-REGEX"
	RUserAgent     = "USER-AGENT"
	RURLRegex      = "URL-REGEX"
	RHeader        = "HEADER"
	RProtocol      = "PROTOCOL"
	RNetwork       = "NETWORK"
	RDeviceName    = "DEVICE-NAME"
	RSubnet        = "SUBNET"
	RCellRadio     = "CELLULAR-RADIO"
	RRuleSet       = "RULE-SET"
	RMatch         = "MATCH"
	RFinal         = "FINAL"
	RAnd           = "AND"
	ROr            = "OR"
	RNot           = "NOT"
)

// 特殊策略
const (
	PolicyDirect     = "DIRECT"
	PolicyReject     = "REJECT"
	PolicyRejectDrop = "REJECT-DROP"
	PolicyPass       = "PASS"
	PolicyProxy      = "PROXY"
)

// Rule 一条路由规则。逻辑规则（AND/OR/NOT）使用 Rules 字段嵌套子规则。
type Rule struct {
	Kind      string `json:"kind"`
	Payload   string `json:"payload"`
	Policy    string `json:"policy"`
	NoResolve bool   `json:"no_resolve,omitempty"`
	Src       bool   `json:"src,omitempty"`     // IP-CIDR 加 src 前缀时匹配源地址
	Invert    bool   `json:"invert,omitempty"`  // 取反（sing-box 的 invert）
	Mode      string `json:"mode,omitempty"`    // 逻辑规则：and / or / not
	Rules     []Rule `json:"rules,omitempty"`   // 逻辑规则的子规则
	Raw       string `json:"raw,omitempty"`
	Line      int    `json:"line,omitempty"`
	Enabled   bool   `json:"enabled"`
	// 编译诊断（不参与匹配）
	Note string `json:"note,omitempty"`
}

// ---------- 规则集 ----------

// RuleSet 一个远程或本地规则集。对应 sing-box 的 rule_set / Clash 的 rule-provider。
type RuleSet struct {
	Name     string `json:"name"`
	Type     string `json:"type"` // inline / local / remote
	Format   string `json:"format,omitempty"` // source / binary
	Path     string `json:"path,omitempty"`
	URL      string `json:"url,omitempty"`
	Interval int    `json:"interval,omitempty"`
	// 规则集内容类别：domain / ipcidr / mixed（决定它能被哪些规则引用）
	Category string `json:"category,omitempty"`
	Enabled  bool   `json:"enabled"`
}

// ---------- DNS ----------

type DNSServer struct {
	Tag        string   `json:"tag,omitempty"`
	Address    string   `json:"address"`
	Detour     string   `json:"detour,omitempty"`
	Domains    []string `json:"domains,omitempty"`
	Strategy   string   `json:"strategy,omitempty"`
	ClientSubnet string `json:"client_subnet,omitempty"`
}

type DNSConfig struct {
	Enabled     bool        `json:"enabled"`
	Servers     []DNSServer `json:"servers"`
	Final       string      `json:"final,omitempty"`
	Strategy    string      `json:"strategy,omitempty"` // prefer_ipv4 / ipv4_only / prefer_ipv6 / ipv6_only
	FakeIP      bool        `json:"fake_ip,omitempty"`
	FakeIPRange string      `json:"fake_ip_range,omitempty"`
	FakeIPFilter []string   `json:"fake_ip_filter,omitempty"`
	IndependentCache bool   `json:"independent_cache,omitempty"`
	DisableCache bool       `json:"disable_cache,omitempty"`
	Rules       []Rule      `json:"rules,omitempty"` // DNS 专用规则（domain → server）
}

// ---------- 通用 ----------

type GeneralConfig struct {
	LogLevel     string `json:"log_level,omitempty"`
	MixedPort    int    `json:"mixed_port,omitempty"`
	TunEnabled   bool   `json:"tun_enabled,omitempty"`
	TunStack     string `json:"tun_stack,omitempty"`
	TunMTU       int    `json:"tun_mtu,omitempty"`
	AutoRoute    bool   `json:"auto_route,omitempty"`
	StrictRoute  bool   `json:"strict_route,omitempty"`
	ClashAPI     bool   `json:"clash_api,omitempty"`
	ClashAPIPort int    `json:"clash_api_port,omitempty"`
	ClashAPISecret string `json:"clash_api_secret,omitempty"`
	DefaultMode  string `json:"default_mode,omitempty"` // rule / global / direct
	SniffEnabled bool   `json:"sniff_enabled,omitempty"`
	FinalPolicy  string `json:"final_policy,omitempty"`
	// SingBoxVersion 目标内核版本，决定配置用哪一代语法。
	// 留空按最新稳定版处理。语法断代（实测得出）：
	//   DNS 服务器     1.12 起 type/server，1.14 起旧式 address 被移除
	//   域名解析器     1.12 起才有 default_domain_resolver
	//   入站 sniff     1.13 起移除，改由路由规则 action=sniff 承担
	SingBoxVersion string `json:"sing_box_version,omitempty"`
	// PrivateDirect 私网/局域网目标是否直连（默认开）。
	// 用指针是为了区分"没写"（=开）和"显式关"。
	PrivateDirect *bool `json:"private_direct,omitempty"`
}

// PrivateDirectOn 私网直连开关，未设置时默认为开。
func (g *GeneralConfig) PrivateDirectOn() bool {
	return g.PrivateDirect == nil || *g.PrivateDirect
}

// Profile 一份完整的配置档案，也是各格式导入的统一落点。
type Profile struct {
	Nodes    []Node       `json:"nodes"`
	Groups   []ProxyGroup `json:"groups"`
	Rules    []Rule       `json:"rules"`
	RuleSets []RuleSet    `json:"rule_sets,omitempty"`
	DNS      DNSConfig    `json:"dns"`
	General  GeneralConfig `json:"general"`
	// 导入诊断
	Warnings []string `json:"warnings,omitempty"`
	Source   string   `json:"source,omitempty"`
}

// ---------- 工具 ----------

// 组/节点名去重：同名时追加 #2 #3
func uniqueName(seen map[string]int, name string) string {
	if name == "" {
		name = "未命名"
	}
	seen[name]++
	if seen[name] == 1 {
		return name
	}
	return name + "#" + itoa(seen[name])
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}

func atoiSafe(s string) int {
	s = strings.TrimSpace(s)
	n := 0
	neg := false
	for i, c := range s {
		if i == 0 && (c == '-' || c == '+') {
			neg = c == '-'
			continue
		}
		if c < '0' || c > '9' {
			return 0
		}
		n = n*10 + int(c-'0')
		if n > 1<<30 {
			return 0
		}
	}
	if neg {
		return -n
	}
	return n
}

func dedupStrings(in []string) []string {
	seen := map[string]bool{}
	out := make([]string, 0, len(in))
	for _, s := range in {
		if s == "" || seen[s] {
			continue
		}
		seen[s] = true
		out = append(out, s)
	}
	return out
}

// 策略是否指向某个策略组
func (p *Profile) groupByName(name string) *ProxyGroup {
	for i := range p.Groups {
		if p.Groups[i].Name == name {
			return &p.Groups[i]
		}
	}
	return nil
}

func (p *Profile) nodeByName(name string) *Node {
	for i := range p.Nodes {
		if p.Nodes[i].Name == name {
			return &p.Nodes[i]
		}
	}
	return nil
}

// 策略名是否有效：内置策略 / 节点名 / 组名
func (p *Profile) validPolicy(pol string) bool {
	switch strings.ToUpper(pol) {
	case PolicyDirect, PolicyReject, PolicyRejectDrop, PolicyPass, PolicyProxy:
		return true
	}
	return p.groupByName(pol) != nil || p.nodeByName(pol) != nil
}

// 按类型统计节点
func (p *Profile) nodeTypeCounts() map[string]int {
	m := map[string]int{}
	for _, n := range p.Nodes {
		m[n.Type]++
	}
	return m
}

func sortedKeys(m map[string]int) []string {
	ks := make([]string, 0, len(m))
	for k := range m {
		ks = append(ks, k)
	}
	sort.Strings(ks)
	return ks
}
