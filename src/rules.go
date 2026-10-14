// ============================================================
//
//	rules.go — 规则引擎
//	解析 Shadowrocket / Clash / Surge 规则语法，
//	提供体检（lint）与匹配推演（test）。
//
//	语法超集：
//	  TYPE,PAYLOAD,POLICY[,MODIFIER...]
//	  AND,((TYPE,PAYLOAD),(TYPE,PAYLOAD)),POLICY
//	  MATCH,POLICY / FINAL,POLICY
//
// ============================================================
package main

import (
	"fmt"
	"net"
	"regexp"
	"strconv"
	"strings"
)

// ---------- 规则类型元信息 ----------

type ruleKindInfo struct {
	// sing-box 目标字段；空字符串表示无法直接编译
	SBField string
	// 是否需要目标 IP 才能判定
	NeedsIP bool
	// 是否只能匹配域名
	NeedsDomain bool
	// 在 sing-box 路由里是否可表达
	Supported bool
	// 说明（用于体检报告）
	Note string
}

var ruleKinds = map[string]ruleKindInfo{
	RDomain:           {SBField: "domain", NeedsDomain: true, Supported: true},
	RDomainSuffix:     {SBField: "domain_suffix", NeedsDomain: true, Supported: true},
	RDomainKeyword:    {SBField: "domain_keyword", NeedsDomain: true, Supported: true},
	RDomainRegex:      {SBField: "domain_regex", NeedsDomain: true, Supported: true},
	RDomainWildcard:   {SBField: "domain_regex", NeedsDomain: true, Supported: true, Note: "通配符会被翻译为正则"},
	RIPCIDR:           {SBField: "ip_cidr", NeedsIP: true, Supported: true},
	RIPCIDR6:          {SBField: "ip_cidr", NeedsIP: true, Supported: true},
	RIPASN:            {NeedsIP: true, Supported: false, Note: "sing-box 无 ASN 匹配，需转换为 IP-CIDR 规则集"},
	RGeoIP:            {SBField: "rule_set", NeedsIP: true, Supported: true, Note: "编译为 geoip 规则集引用"},
	RGeoSite:          {SBField: "rule_set", NeedsDomain: true, Supported: true, Note: "编译为 geosite 规则集引用"},
	RSrcIPCIDR:        {SBField: "source_ip_cidr", Supported: true},
	RSrcPort:          {SBField: "source_port", Supported: true},
	RDstPort:          {SBField: "port", Supported: true},
	RInPort:           {Supported: false, Note: "sing-box 用 inbound 标签匹配，需改写为 inbound 规则"},
	RProcessName:      {SBField: "process_name", Supported: true, Note: "Android 上等效字段为 package_name"},
	RProcessPath:      {SBField: "process_path", Supported: true},
	RProcessNameRegex: {SBField: "process_path_regex", Supported: true},
	RUserAgent:        {Supported: false, Note: "sing-box 不嗅探 User-Agent，无法表达"},
	RURLRegex:         {Supported: false, Note: "sing-box 只匹配域名不匹配完整 URL，无法表达"},
	RHeader:           {Supported: false, Note: "sing-box 不支持按 HTTP 头匹配"},
	RProtocol:         {SBField: "protocol", Supported: true},
	RNetwork:          {SBField: "network", Supported: true},
	RDeviceName:       {Supported: false, Note: "sing-box 不支持设备名匹配"},
	RSubnet:           {Supported: false, Note: "sing-box 不支持子网标签匹配"},
	RCellRadio:        {Supported: false, Note: "sing-box 不支持蜂窝制式匹配"},
	RRuleSet:          {SBField: "rule_set", Supported: true},
	RMatch:            {Supported: true, Note: "编译为 route.final"},
	RFinal:            {Supported: true, Note: "编译为 route.final"},
	RAnd:              {Supported: true, Note: "编译为 logical/and"},
	ROr:               {Supported: true, Note: "编译为 logical/or"},
	RNot:              {Supported: true, Note: "编译为 logical/not(invert)"},
}

// RuleKindSupported 该规则类型能否编译到 sing-box
func RuleKindSupported(kind string) bool {
	ki, ok := ruleKinds[kind]
	return ok && ki.Supported
}

// KnownRuleKind 是否为已知规则类型
func KnownRuleKind(kind string) bool {
	_, ok := ruleKinds[kind]
	return ok
}

// kindAliases 各家客户端的同义写法 → 内部规范类型。
//
// 为什么必须有这层：
//
//	Shadowrocket / Surge / Quantumult X / Clash 的规则类型名互不相同，
//	用户从网上抄来的规则经常因为一个连字符或一个同义词就被判成
//	"未知规则类型"而整条丢弃 —— 这正是"多语法多规则"里最容易踩的坑。
//	统一收口在这里，导入 / 手写 / 追加规则三条路径都能受益。
var kindAliases = map[string]string{
	// 端口
	"DST-PORT":         RDstPort, // Shadowrocket / Clash 写法
	"DEST-PORT":        RDstPort,
	"DESTINATION-PORT": RDstPort,
	"INBOUND-PORT":     RInPort,
	"IN-PORT":          RInPort,
	// Surge 的 HOST 家族
	"HOST":          RDomain,
	"HOST-SUFFIX":   RDomainSuffix,
	"HOST-KEYWORD":  RDomainKeyword,
	"HOST-WILDCARD": RDomainWildcard,
	"DOMAIN-SET":    RRuleSet, // Shadowrocket 域名集
	"IP-SET":        RRuleSet, // Shadowrocket IP 集
	"RULE-SET":      RRuleSet,
	"URL":           RURLRegex,
	"URL-REGEX":     RURLRegex,
	// 地址
	"SRC-IP":         RSrcIPCIDR,
	"SOURCE-IP-CIDR": RSrcIPCIDR,
	"IP6-CIDR":       RIPCIDR6,
	"IPV6-CIDR":      RIPCIDR6,
	"GEO-SITE":       RGeoSite,
	"GEO-IP":         RGeoIP,
	"ASN":            RIPASN,
	// 进程 / 设备
	"PROCESS":            RProcessName,
	"PROCESS-NAME-REGEX": RProcessNameRegex,
	// 兜底
	"FINAL-MATCH": RMatch,
	"MATCH-ALL":   RMatch,
}

// NormalizeKind 把各家写法归一成内部规范类型（大小写不敏感）
func NormalizeKind(k string) string {
	k = strings.ToUpper(strings.TrimSpace(k))
	if v, ok := kindAliases[k]; ok {
		return v
	}
	return k
}

// ---------- 解析 ----------

// splitRuleFields 按逗号切分，但保留 ((...),(...)) 里的括号层级
func splitRuleFields(s string) []string {
	var out []string
	depth := 0
	cur := strings.Builder{}
	for _, c := range s {
		switch c {
		case '(':
			depth++
			cur.WriteRune(c)
		case ')':
			depth--
			cur.WriteRune(c)
		case ',':
			if depth > 0 {
				cur.WriteRune(c)
			} else {
				out = append(out, strings.TrimSpace(cur.String()))
				cur.Reset()
			}
		default:
			cur.WriteRune(c)
		}
	}
	out = append(out, strings.TrimSpace(cur.String()))
	return out
}

// ParseRuleLine 解析一行规则。返回 error 表示语法不合法。
func ParseRuleLine(line string, ln int) (Rule, error) {
	r := Rule{Enabled: true, Line: ln}
	raw := strings.TrimSpace(line)
	// 去注释
	if i := strings.Index(raw, "//"); i >= 0 {
		raw = strings.TrimSpace(raw[:i])
	}
	if i := strings.Index(raw, "#"); i >= 0 {
		raw = strings.TrimSpace(raw[:i])
	}
	r.Raw = raw
	if raw == "" {
		return r, fmt.Errorf("空规则")
	}

	fields := splitRuleFields(raw)
	if len(fields) < 2 {
		return r, fmt.Errorf("字段不足（至少需要 类型,载荷 或 类型,策略）")
	}
	kind := NormalizeKind(fields[0])
	r.Kind = kind

	if !KnownRuleKind(kind) {
		return r, fmt.Errorf("未知规则类型 %q", kind)
	}

	// 逻辑规则
	if kind == RAnd || kind == ROr || kind == RNot {
		if len(fields) < 3 {
			return r, fmt.Errorf("%s 需要 ((子规则),...) 与策略两段", kind)
		}
		r.Mode = map[string]string{RAnd: "and", ROr: "or", RNot: "not"}[kind]
		subs, err := parseLogicalSub(fields[1])
		if err != nil {
			return r, err
		}
		if len(subs) == 0 {
			return r, fmt.Errorf("%s 没有子规则", kind)
		}
		r.Rules = subs
		r.Policy = normalizePolicy(fields[2])
		applyModifiers(&r, fields[3:])
		return r, nil
	}

	// MATCH / FINAL 只有策略
	if kind == RMatch || kind == RFinal {
		r.Policy = normalizePolicy(fields[1])
		r.Payload = "*"
		applyModifiers(&r, fields[2:])
		return r, nil
	}

	r.Payload = strings.TrimSpace(fields[1])
	if r.Payload == "" {
		return r, fmt.Errorf("%s 的载荷为空", kind)
	}
	if len(fields) >= 3 && strings.TrimSpace(fields[2]) != "" {
		r.Policy = normalizePolicy(fields[2])
	} else {
		// Shadowrocket 允许省略策略，默认走代理
		r.Policy = PolicyProxy
		r.Note = "未写策略，按 PROXY 处理"
	}
	applyModifiers(&r, fields[3:])
	return r, nil
}

// parseLogicalSub 解析 ((A,b),(C,d)) 形式的子规则
func parseLogicalSub(s string) ([]Rule, error) {
	s = strings.TrimSpace(s)
	s = strings.TrimPrefix(s, "(")
	s = strings.TrimSuffix(s, ")")
	parts := splitRuleFields(s)
	var subs []Rule
	for _, p := range parts {
		p = strings.TrimSpace(p)
		p = strings.TrimPrefix(p, "(")
		p = strings.TrimSuffix(p, ")")
		if p == "" {
			continue
		}
		f := splitRuleFields(p)
		if len(f) < 2 {
			return nil, fmt.Errorf("逻辑子规则 %q 字段不足", p)
		}
		kind := NormalizeKind(f[0])
		if !KnownRuleKind(kind) {
			return nil, fmt.Errorf("逻辑子规则含未知类型 %q", kind)
		}
		if kind == RAnd || kind == ROr || kind == RNot {
			return nil, fmt.Errorf("逻辑子规则不支持再嵌套逻辑规则")
		}
		sub := Rule{Kind: kind, Payload: strings.TrimSpace(f[1]), Enabled: true}
		if len(f) >= 3 {
			// 子规则里第三段可能是策略也可能是修饰符，忽略策略
			if !isModifier(f[2]) {
				sub.Policy = normalizePolicy(f[2])
			} else {
				sub.NoResolve = true
			}
		}
		subs = append(subs, sub)
	}
	return subs, nil
}

func isModifier(s string) bool {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "no-resolve", "src", "ext", "force-remote-dns", "pre-matching":
		return true
	}
	return false
}

func applyModifiers(r *Rule, mods []string) {
	for _, m := range mods {
		switch strings.ToLower(strings.TrimSpace(m)) {
		case "no-resolve":
			r.NoResolve = true
		case "src":
			r.Src = true
		case "ext", "force-remote-dns", "pre-matching":
			// 对 sing-box 无对应语义，仅记录
		}
	}
}

func normalizePolicy(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return PolicyProxy
	}
	up := strings.ToUpper(s)
	switch up {
	case "DIRECT", "REJECT", "REJECT-DROP", "PASS", "PROXY", "REJECT-TINYGIF", "REJECT-NO-DROP":
		if up == "REJECT-TINYGIF" || up == "REJECT-NO-DROP" {
			return PolicyReject
		}
		return up
	}
	// 组名/节点名保持原样
	return s
}

// ParseRules 解析规则块，返回规则与逐行错误
func ParseRules(text string) ([]Rule, []string) {
	var rules []Rule
	var errs []string
	ln := 0
	for _, raw := range strings.Split(text, "\n") {
		ln++
		line := strings.TrimSpace(strings.TrimSuffix(raw, "\r"))
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, "//") || strings.HasPrefix(line, ";") {
			continue
		}
		r, err := ParseRuleLine(line, ln)
		if err != nil {
			errs = append(errs, fmt.Sprintf("第 %d 行: %s", ln, err.Error()))
			continue
		}
		rules = append(rules, r)
	}
	return rules, errs
}

// ---------- 体检 ----------

type Issue struct {
	Level string `json:"level"` // error / warn / info
	Line  int    `json:"line,omitempty"`
	Rule  string `json:"rule,omitempty"`
	Code  string `json:"code"`
	Msg   string `json:"msg"`
}

// LintRules 规则体检
func LintRules(p *Profile) []Issue {
	var out []Issue
	seen := map[string]int{}
	firstMatch := -1
	// 记录每种类型的已覆盖范围，用于遮蔽检测
	type cover struct {
		idx    int
		kind   string
		policy string
	}
	var covers []cover

	for i := range p.Rules {
		r := &p.Rules[i]
		if !r.Enabled {
			continue
		}
		ki := ruleKinds[r.Kind]

		// 1) 编译可行性
		if !ki.Supported {
			out = append(out, Issue{Level: "warn", Line: r.Line, Rule: r.Raw, Code: "unsupported",
				Msg: fmt.Sprintf("%s 无法编译到 sing-box：%s", r.Kind, ki.Note)})
		}

		// 2) 载荷合法性
		switch r.Kind {
		case RIPCIDR, RIPCIDR6, RSrcIPCIDR:
			if _, _, err := net.ParseCIDR(r.Payload); err != nil {
				// 允许裸 IP
				if ip := net.ParseIP(r.Payload); ip == nil {
					out = append(out, Issue{Level: "error", Line: r.Line, Rule: r.Raw, Code: "bad-cidr",
						Msg: fmt.Sprintf("不是合法的 CIDR 或 IP：%s", r.Payload)})
				}
			}
		case RDomainRegex, RURLRegex, RProcessNameRegex:
			if _, err := regexp.Compile(r.Payload); err != nil {
				out = append(out, Issue{Level: "error", Line: r.Line, Rule: r.Raw, Code: "bad-regex",
					Msg: fmt.Sprintf("正则无法编译：%s", err.Error())})
			}
		case RDstPort, RSrcPort:
			if _, err := parsePortSpec(r.Payload); err != nil {
				out = append(out, Issue{Level: "error", Line: r.Line, Rule: r.Raw, Code: "bad-port",
					Msg: err.Error()})
			}
		case RDomain, RDomainSuffix:
			if strings.ContainsAny(r.Payload, "*/?") {
				out = append(out, Issue{Level: "warn", Line: r.Line, Rule: r.Raw, Code: "domain-wildcard",
					Msg: "该类型不支持通配符，请改用 DOMAIN-WILDCARD"})
			}
		case RProtocol:
			switch strings.ToLower(r.Payload) {
			case "tls", "http", "quic", "stun", "dns", "ssh", "rdp", "bittorrent", "dtls":
			default:
				out = append(out, Issue{Level: "warn", Line: r.Line, Rule: r.Raw, Code: "protocol-value",
					Msg: fmt.Sprintf("sing-box 可能不识别协议 %q", r.Payload)})
			}
		case RNetwork:
			switch strings.ToLower(r.Payload) {
			case "tcp", "udp", "icmp":
			default:
				out = append(out, Issue{Level: "error", Line: r.Line, Rule: r.Raw, Code: "network-value",
					Msg: fmt.Sprintf("network 只能是 tcp / udp / icmp，收到 %q", r.Payload)})
			}
		}

		// 3) 策略可达性
		if r.Kind != RMatch && r.Kind != RFinal {
			if !p.validPolicy(r.Policy) {
				out = append(out, Issue{Level: "error", Line: r.Line, Rule: r.Raw, Code: "unknown-policy",
					Msg: fmt.Sprintf("策略 %q 既不是内置策略，也不是已知节点或策略组", r.Policy)})
			}
		}

		// 4) 重复
		key := r.Kind + "\x00" + r.Payload + "\x00" + r.Policy
		if prev, ok := seen[key]; ok {
			out = append(out, Issue{Level: "warn", Line: r.Line, Rule: r.Raw, Code: "duplicate",
				Msg: fmt.Sprintf("与第 %d 行完全重复，永不生效", prev)})
		} else {
			seen[key] = r.Line
		}

		// 5) 遮蔽检测（同类型、同策略、更宽的载荷在前面）
		for _, c := range covers {
			if c.kind == r.Kind && c.policy == r.Policy && r.Kind != RAnd && r.Kind != ROr && r.Kind != RNot {
				if ruleCovers(c.kind, p.Rules[c.idx].Payload, r.Payload) {
					out = append(out, Issue{Level: "info", Line: r.Line, Rule: r.Raw, Code: "shadowed",
						Msg: fmt.Sprintf("被第 %d 行的更宽规则完全覆盖，此条永不生效", p.Rules[c.idx].Line)})
					break
				}
			}
		}

		// 6) MATCH / FINAL 位置
		if r.Kind == RMatch || r.Kind == RFinal {
			if firstMatch < 0 {
				firstMatch = i
			}
			if i != len(p.Rules)-1 {
				out = append(out, Issue{Level: "warn", Line: r.Line, Rule: r.Raw, Code: "match-not-last",
					Msg: "MATCH/FINAL 之后的规则永远不会被求值"})
			}
		}

		covers = append(covers, cover{idx: i, kind: r.Kind, policy: r.Policy})
	}

	// 没有兜底规则
	hasFallback := false
	for i := range p.Rules {
		if (p.Rules[i].Kind == RMatch || p.Rules[i].Kind == RFinal) && p.Rules[i].Enabled {
			hasFallback = true
		}
	}
	if !hasFallback && len(p.Rules) > 0 {
		out = append(out, Issue{Level: "info", Code: "no-fallback",
			Msg: "没有 MATCH/FINAL 兜底规则，未命中流量将走 route.final（默认策略）"})
	}
	if len(p.Rules) == 0 {
		out = append(out, Issue{Level: "info", Code: "no-rules", Msg: "规则列表为空，全部流量走默认策略"})
	}

	return out
}

// ruleCovers 判断 a 是否覆盖 b（同为同类型载荷）
func ruleCovers(kind, a, b string) bool {
	if a == b {
		return true
	}
	switch kind {
	case RDomainSuffix:
		// a=.com 覆盖 b=google.com
		return strings.HasSuffix(strings.TrimPrefix(b, "."), strings.TrimPrefix(a, ".")) &&
			strings.HasSuffix(b, a)
	case RDomainKeyword:
		return strings.Contains(b, a)
	case RIPCIDR, RIPCIDR6, RSrcIPCIDR:
		_, an, errA := net.ParseCIDR(a)
		_, bn, errB := net.ParseCIDR(b)
		if errA != nil || errB != nil {
			return false
		}
		return an.Contains(bn.IP) && an.Contains(bn.IP.Mask(bn.Mask)) && maskContains(an, bn)
	}
	return false
}

// maskContains 判断 a 的网段是否包含 b 的网段
func maskContains(a, b *net.IPNet) bool {
	onesA, bitsA := a.Mask.Size()
	onesB, bitsB := b.Mask.Size()
	if bitsA != bitsB {
		return false
	}
	return onesA <= onesB && a.Contains(b.IP)
}

// ---------- 匹配推演 ----------

// MatchRequest 一次匹配请求
type MatchRequest struct {
	Domain   string
	DestIP   string
	DestPort int
	SrcIP    string
	SrcPort  int
	Process  string
	Protocol string
	Network  string
	UA       string
	URL      string
}

// MatchStep 一条规则的求值结果
type MatchStep struct {
	Index   int    `json:"index"`
	Line    int    `json:"line"`
	Rule    string `json:"rule"`
	Kind    string `json:"kind"`
	Matched bool   `json:"matched"`
	Detail  string `json:"detail"`
}

// MatchResult 匹配推演结果
type MatchResult struct {
	Matched  bool        `json:"matched"`
	Policy   string      `json:"policy"`
	RuleRaw  string      `json:"rule_raw,omitempty"`
	RuleLine int         `json:"rule_line,omitempty"`
	Steps    []MatchStep `json:"steps"`
	Final    string      `json:"final"`
	Notes    []string    `json:"notes,omitempty"`
}

// MatchRules 按顺序求值，返回首个命中的规则
func MatchRules(p *Profile, req MatchRequest) MatchResult {
	res := MatchResult{Final: p.General.FinalPolicy}
	if res.Final == "" {
		res.Final = PolicyProxy
	}
	host := strings.ToLower(strings.TrimSuffix(req.Domain, "."))

	for i := range p.Rules {
		r := &p.Rules[i]
		if !r.Enabled {
			continue
		}
		ok, detail := evalRule(r, req, host)
		res.Steps = append(res.Steps, MatchStep{
			Index: i, Line: r.Line, Rule: r.Raw, Kind: r.Kind, Matched: ok, Detail: detail,
		})
		if ok {
			res.Matched = true
			res.Policy = r.Policy
			res.RuleRaw = r.Raw
			res.RuleLine = r.Line
			return res
		}
	}
	res.Policy = res.Final
	res.Notes = append(res.Notes, "未命中任何规则，使用 route.final = "+res.Final)
	return res
}

func evalRule(r *Rule, req MatchRequest, host string) (bool, string) {
	ki := ruleKinds[r.Kind]
	switch r.Kind {
	case RMatch, RFinal:
		return true, "兜底规则，必定命中"
	case RAnd, ROr, RNot:
		return evalLogical(r, req, host)
	}

	// 需要 IP 但没有 IP
	if ki.NeedsIP && req.DestIP == "" {
		return false, "缺少目标 IP，无法判定（需先完成 DNS 解析）"
	}
	if ki.NeedsDomain && host == "" {
		return false, "缺少域名，无法判定"
	}

	switch r.Kind {
	case RDomain:
		if host == strings.ToLower(r.Payload) {
			return true, "域名完全匹配"
		}
	case RDomainSuffix:
		suf := strings.TrimPrefix(strings.ToLower(r.Payload), ".")
		if host == suf || strings.HasSuffix(host, "."+suf) {
			return true, "域名后缀匹配 " + suf
		}
	case RDomainKeyword:
		if strings.Contains(host, strings.ToLower(r.Payload)) {
			return true, "域名含关键词 " + r.Payload
		}
	case RDomainWildcard, RDomainRegex:
		pat := r.Payload
		if r.Kind == RDomainWildcard {
			pat = wildcardToRegex(pat)
		}
		if re, err := regexp.Compile("(?i)" + pat); err == nil && re.MatchString(host) {
			return true, "域名正则命中"
		}
	case RIPCIDR, RIPCIDR6, RSrcIPCIDR:
		ipStr := req.DestIP
		if r.Kind == RSrcIPCIDR || r.Src {
			ipStr = req.SrcIP
		}
		if ipStr == "" {
			return false, "缺少对应 IP"
		}
		if cidrMatch(r.Payload, ipStr) {
			return true, "IP 落在 " + r.Payload
		}
	case RGeoIP:
		// 无 geo 数据库时只能给出提示
		return false, "需要 geoip 数据库才能判定（编译后由 rule_set 处理）"
	case RGeoSite:
		return false, "需要 geosite 数据库才能判定（编译后由 rule_set 处理）"
	case RIPASN:
		return false, "需要 ASN 数据库才能判定"
	case RDstPort:
		if req.DestPort > 0 && portMatch(r.Payload, req.DestPort) {
			return true, "目标端口匹配"
		}
	case RSrcPort:
		if req.SrcPort > 0 && portMatch(r.Payload, req.SrcPort) {
			return true, "源端口匹配"
		}
	case RProcessName:
		if req.Process != "" && (req.Process == r.Payload ||
			strings.EqualFold(lastSeg(req.Process), r.Payload)) {
			return true, "进程名匹配"
		}
	case RProcessPath:
		if req.Process != "" && req.Process == r.Payload {
			return true, "进程路径匹配"
		}
	case RProcessNameRegex:
		if req.Process != "" {
			if re, err := regexp.Compile("(?i)" + r.Payload); err == nil && re.MatchString(req.Process) {
				return true, "进程名正则命中"
			}
		}
	case RUserAgent:
		if req.UA != "" && uaMatch(r.Payload, req.UA) {
			return true, "User-Agent 匹配"
		}
	case RURLRegex:
		if req.URL != "" {
			if re, err := regexp.Compile("(?i)" + r.Payload); err == nil && re.MatchString(req.URL) {
				return true, "URL 正则命中"
			}
		}
	case RProtocol:
		if strings.EqualFold(req.Protocol, r.Payload) {
			return true, "协议匹配"
		}
	case RNetwork:
		if strings.EqualFold(req.Network, r.Payload) {
			return true, "网络类型匹配"
		}
	case RRuleSet:
		return false, "规则集内容需展开后才能判定（编译后由 rule_set 处理）"
	}
	return false, ""
}

func evalLogical(r *Rule, req MatchRequest, host string) (bool, string) {
	results := make([]bool, 0, len(r.Rules))
	for i := range r.Rules {
		ok, _ := evalRule(&r.Rules[i], req, host)
		results = append(results, ok)
	}
	switch r.Mode {
	case "and":
		for _, b := range results {
			if !b {
				return false, "AND 子条件未全部满足"
			}
		}
		return true, "AND 子条件全部满足"
	case "or":
		for _, b := range results {
			if b {
				return true, "OR 有子条件满足"
			}
		}
		return false, "OR 子条件均不满足"
	case "not":
		if len(results) == 1 {
			return !results[0], "NOT 取反"
		}
		for _, b := range results {
			if b {
				return false, "NOT 子条件被满足"
			}
		}
		return true, "NOT 取反"
	}
	return false, ""
}

func lastSeg(s string) string {
	if i := strings.LastIndexAny(s, "/\\"); i >= 0 {
		return s[i+1:]
	}
	return s
}

func cidrMatch(cidr, ip string) bool {
	_, n, err := net.ParseCIDR(cidr)
	if err != nil {
		// 裸 IP
		a := net.ParseIP(cidr)
		b := net.ParseIP(ip)
		return a != nil && b != nil && a.Equal(b)
	}
	b := net.ParseIP(ip)
	return b != nil && n.Contains(b)
}

func portMatch(spec string, port int) bool {
	parts, err := parsePortSpec(spec)
	if err != nil {
		return false
	}
	for _, rng := range parts {
		if port >= rng[0] && port <= rng[1] {
			return true
		}
	}
	return false
}

// parsePortSpec 支持 443 / 1000-2000 / 1000:2000 / 逗号分隔
func parsePortSpec(spec string) ([][2]int, error) {
	var out [][2]int
	for _, piece := range strings.Split(spec, ",") {
		piece = strings.TrimSpace(piece)
		if piece == "" {
			continue
		}
		sep := "-"
		if strings.Contains(piece, ":") {
			sep = ":"
		}
		if strings.Contains(piece, sep) {
			kv := strings.SplitN(piece, sep, 2)
			lo, err1 := strconv.Atoi(strings.TrimSpace(kv[0]))
			hi, err2 := strconv.Atoi(strings.TrimSpace(kv[1]))
			if err1 != nil || err2 != nil {
				return nil, fmt.Errorf("端口区间非法：%s", piece)
			}
			if lo < 0 || hi > 65535 || lo > hi {
				return nil, fmt.Errorf("端口区间越界：%s", piece)
			}
			out = append(out, [2]int{lo, hi})
			continue
		}
		p, err := strconv.Atoi(piece)
		if err != nil || p < 0 || p > 65535 {
			return nil, fmt.Errorf("端口非法：%s", piece)
		}
		out = append(out, [2]int{p, p})
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("端口为空")
	}
	return out, nil
}

// uaMatch 通配符匹配 User-Agent（* 与 ?）
func uaMatch(pattern, ua string) bool {
	re := regexp.QuoteMeta(pattern)
	re = strings.ReplaceAll(re, `\*`, `.*`)
	re = strings.ReplaceAll(re, `\?`, `.`)
	c, err := regexp.Compile("(?i)^" + re + "$")
	if err != nil {
		return false
	}
	return c.MatchString(ua)
}

// wildcardToRegex 把 Shadowrocket 的域名通配符翻译成正则
func wildcardToRegex(pat string) string {
	p := strings.ToLower(strings.TrimSpace(pat))
	var b strings.Builder
	b.WriteString("^")
	for _, c := range p {
		switch c {
		case '*':
			b.WriteString(".*")
		case '?':
			b.WriteString(".")
		case '.':
			b.WriteString(`\.`)
		default:
			b.WriteString(regexp.QuoteMeta(string(c)))
		}
	}
	b.WriteString("$")
	return b.String()
}
