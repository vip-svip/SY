// ============================================================
//
//	cmd_route.go — route / clash 子命令
//
//	abserver route compile -profile P.json -out C.json [-cache PATH]
//	abserver route lint    -profile P.json [-json]
//	abserver route test    -profile P.json -domain D [-ip I] [-port N] ...
//	abserver route import  -in FILE -format auto [-out P.json] [-merge P.json]
//	abserver route explain -profile P.json
//	abserver clash         -api ADDR [-secret S] {status|conn|traffic|...}
//
// ============================================================
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

// httpGetBytes 带超时与重定向的简单 GET，用于抓规则集与镜像探测。
func httpGetBytes(url string, timeout time.Duration) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "abserver/"+version)
	client := &http.Client{Timeout: timeout}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	return io.ReadAll(io.LimitReader(resp.Body, 64<<20))
}

func readAllPath(path string) ([]byte, error) {
	if path == "-" || path == "" {
		return io.ReadAll(os.Stdin)
	}
	return os.ReadFile(path)
}

func loadProfile(path string) (*Profile, error) {
	b, err := readAllPath(path)
	if err != nil {
		return nil, fmt.Errorf("读取配置失败: %v", err)
	}
	var p Profile
	if err := json.Unmarshal(b, &p); err != nil {
		return nil, fmt.Errorf("配置不是合法的 profile JSON: %v", err)
	}
	// profile.json 是面板里可以直接手改的"唯一事实源"，所以这里必须
	// 把各家客户端的写法（DST-PORT / HOST-SUFFIX / DOMAIN-SET …）归一化，
	// 否则用户抄来的规则会在编译期被判成"未知类型"而整条丢掉。
	for i := range p.Rules {
		p.Rules[i].Kind = NormalizeKind(p.Rules[i].Kind)
		for j := range p.Rules[i].Rules {
			p.Rules[i].Rules[j].Kind = NormalizeKind(p.Rules[i].Rules[j].Kind)
		}
	}
	return &p, nil
}

func writeOut(path string, b []byte) error {
	if path == "" || path == "-" {
		_, err := os.Stdout.Write(b)
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, b, 0644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// ---------- route ----------

func cmdRoute(args []string) {
	if len(args) < 1 {
		routeUsage()
		os.Exit(2)
	}
	switch args[0] {
	case "compile":
		routeCompile(args[1:])
	case "lint":
		routeLint(args[1:])
	case "test":
		routeTest(args[1:])
	case "import":
		routeImport(args[1:])
	case "explain":
		routeExplain(args[1:])
	case "mirrors":
		routeMirrors(args[1:])
	case "fetch-rules":
		routeFetchRules(args[1:])
	case "set":
		routeSet(args[1:])
	case "summary":
		routeSummary(args[1:])
	case "add-node":
		routeAddNode(args[1:])
	case "add-rule":
		routeAddRule(args[1:])
	case "dnsprobe":
		cmdDNSProbe(args[1:])
	default:
		routeUsage()
		os.Exit(2)
	}
}

func routeUsage() {
	fmt.Fprintln(os.Stderr, `用法:
  abserver route compile     -profile P.json -out C.json [选项]
        -sb-version V      目标内核版本（决定配置语法断代）
        -kernel PATH       指向内核二进制，自动读版本
        -ruleset-dir DIR   本地 .srs 目录，命中则离线使用
        -mirror NAME       规则集镜像，见 route mirrors
        -cache PATH        内核 cache_file 路径
  abserver route lint        -profile P.json [-json]
  abserver route test        -profile P.json -domain D [-ip I] [-port N] [-process S] [-json]
  abserver route import      -in FILE -format auto [-out P.json] [-merge P.json]
  abserver route explain     -profile P.json [-json]
  abserver route mirrors     [-probe] [-json]
  abserver route fetch-rules -dir DIR [-codes cn,category-ads-all] [-mirror NAME] [-geoip]
  abserver route set         -profile P.json [-mixed-port N] [-tun on|off] [-final PROXY]
  abserver route summary     -profile P.json
  abserver route add-node    -profile P.json [-link URL] [-in FILE] [-group G]
  abserver route add-rule    -profile P.json [-rule LINE] [-in FILE]
  abserver route dnsprobe    [-domain D] [-servers a,b,c] [-timeout 4] [-json]`)
}

func routeCompile(args []string) {
	fs := flag.NewFlagSet("route compile", flag.ExitOnError)
	in := fs.String("profile", "", "profile JSON")
	out := fs.String("out", "", "输出 sing-box 配置")
	cache := fs.String("cache", "", "内核 cache_file 路径")
	sbver := fs.String("sb-version", "", "目标内核版本（默认取 profile，再默认最新稳定版）")
	kernel := fs.String("kernel", "", "直接指向内核二进制，自动读出版本")
	rulesetDir := fs.String("ruleset-dir", "", "本地 .srs 规则集目录，命中则离线使用")
	mirror := fs.String("mirror", "", "规则集镜像（testingcf/fastly/ghproxy/ghproxynet/jsdelivr）")
	mixedPort := fs.Int("mixed-port", -1, "覆盖混合入站端口（-1 表示不改）")
	tun := fs.String("tun", "", "覆盖 TUN 开关：on/off")
	clashAPI := fs.String("clash-api", "", "覆盖 Clash API 开关：on/off")
	clashPort := fs.Int("clash-port", 0, "覆盖 Clash API 端口")
	quiet := fs.Bool("quiet", false, "不输出摘要")
	fs.Parse(args)
	if *in == "" {
		fmt.Fprintln(os.Stderr, "ERR: 缺少 -profile")
		os.Exit(2)
	}
	kv := *sbver
	if kv == "" && *kernel != "" {
		if v, err := detectKernelVersion(*kernel); err == nil {
			kv = v
		} else {
			fmt.Fprintf(os.Stderr, "warn: 无法从 %s 读出版本：%v\n", *kernel, err)
		}
	}
	p, err := loadProfile(*in)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR:", err)
		os.Exit(1)
	}
	if *mixedPort >= 0 {
		p.General.MixedPort = *mixedPort
	}
	switch strings.ToLower(*tun) {
	case "on", "true", "1":
		p.General.TunEnabled = true
	case "off", "false", "0":
		p.General.TunEnabled = false
	}
	switch strings.ToLower(*clashAPI) {
	case "on", "true", "1":
		p.General.ClashAPI = true
	case "off", "false", "0":
		p.General.ClashAPI = false
	}
	if *clashPort > 0 {
		p.General.ClashAPI = true
		p.General.ClashAPIPort = *clashPort
	}
	res, err := CompileSingBox(p, CompileOptions{
		CachePath:     *cache,
		KernelVersion: kv,
		RuleSetDir:    *rulesetDir,
		Mirror:        *mirror,
	})
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR:", err)
		os.Exit(1)
	}
	if err := writeOut(*out, res.JSON); err != nil {
		fmt.Fprintln(os.Stderr, "ERR: 写出失败:", err)
		os.Exit(1)
	}
	// 摘要写到 stderr，保证 stdout 干净可重定向
	if !*quiet {
		fmt.Fprintf(os.Stderr, "OK 目标内核 %s，规则 %d 条，跳过 %d 条，警告 %d 条，出站已生成\n",
			res.TargetVersion, res.RuleCount, res.Skipped, len(res.Warnings))
		if res.LocalRuleSets > 0 {
			fmt.Fprintf(os.Stderr, "   规则集：%d 个走本地（%s）\n", res.LocalRuleSets, res.RuleSetDir)
		}
		fmt.Fprintf(os.Stderr, "   规则集镜像：%s\n", res.Mirror)
		for _, w := range res.Warnings {
			fmt.Fprintf(os.Stderr, "  warn: %s\n", w)
		}
	}
}

// detectKernelVersion 跑一次 `sing-box version` 读出版本号。
// 配置语法随版本断代，这一步决定产出哪一代写法。
func detectKernelVersion(path string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, path, "version")
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	if err := cmd.Run(); err != nil {
		return "", err
	}
	re := regexp.MustCompile(`(?m)^sing-box version\s+v?([0-9]+\.[0-9]+\.[0-9]+)`)
	m := re.FindStringSubmatch(buf.String())
	if len(m) < 2 {
		return "", fmt.Errorf("版本号格式未识别")
	}
	return m[1], nil
}

func routeLint(args []string) {
	fs := flag.NewFlagSet("route lint", flag.ExitOnError)
	in := fs.String("profile", "", "profile JSON")
	asJSON := fs.Bool("json", false, "以 JSON 输出")
	fs.Parse(args)
	if *in == "" {
		fmt.Fprintln(os.Stderr, "ERR: 缺少 -profile")
		os.Exit(2)
	}
	p, err := loadProfile(*in)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR:", err)
		os.Exit(1)
	}
	issues := LintRules(p)
	if *asJSON {
		b, _ := json.MarshalIndent(map[string]any{
			"issues": issues, "rules": len(p.Rules),
			"nodes": len(p.Nodes), "groups": len(p.Groups),
		}, "", "  ")
		fmt.Println(string(b))
	} else {
		nErr, nWarn, nInfo := 0, 0, 0
		for _, i := range issues {
			switch i.Level {
			case "error":
				nErr++
			case "warn":
				nWarn++
			default:
				nInfo++
			}
		}
		fmt.Printf("规则体检：共 %d 条规则，错误 %d，警告 %d，提示 %d\n\n",
			len(p.Rules), nErr, nWarn, nInfo)
		for _, i := range issues {
			mark := map[string]string{"error": "错误", "warn": "警告", "info": "提示"}[i.Level]
			loc := ""
			if i.Line > 0 {
				loc = fmt.Sprintf("第%d行 ", i.Line)
			}
			fmt.Printf("  [%s] %s%s\n", mark, loc, i.Msg)
			if i.Rule != "" {
				fmt.Printf("         %s\n", i.Rule)
			}
		}
		if len(issues) == 0 {
			fmt.Println("  没有发现问题")
		}
	}
	// 有 error 时以非零退出，便于脚本判断
	for _, i := range issues {
		if i.Level == "error" {
			os.Exit(1)
		}
	}
}

func routeTest(args []string) {
	fs := flag.NewFlagSet("route test", flag.ExitOnError)
	in := fs.String("profile", "", "profile JSON")
	domain := fs.String("domain", "", "目标域名")
	ip := fs.String("ip", "", "目标 IP")
	port := fs.Int("port", 0, "目标端口")
	srcIP := fs.String("src-ip", "", "源 IP")
	srcPort := fs.Int("src-port", 0, "源端口")
	process := fs.String("process", "", "进程名或包名")
	proto := fs.String("protocol", "", "协议 tls/http/quic")
	network := fs.String("network", "", "网络类型 tcp/udp")
	ua := fs.String("ua", "", "User-Agent")
	rawURL := fs.String("url", "", "完整 URL")
	asJSON := fs.Bool("json", false, "以 JSON 输出")
	verbose := fs.Bool("v", false, "显示全部求值步骤")
	fs.Parse(args)
	if *in == "" {
		fmt.Fprintln(os.Stderr, "ERR: 缺少 -profile")
		os.Exit(2)
	}
	if *domain == "" && *ip == "" {
		fmt.Fprintln(os.Stderr, "ERR: 至少要给出 -domain 或 -ip")
		os.Exit(2)
	}
	p, err := loadProfile(*in)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR:", err)
		os.Exit(1)
	}
	req := MatchRequest{
		Domain: *domain, DestIP: *ip, DestPort: *port,
		SrcIP: *srcIP, SrcPort: *srcPort, Process: *process,
		Protocol: *proto, Network: *network, UA: *ua, URL: *rawURL,
	}
	res := MatchRules(p, req)

	if *asJSON {
		b, _ := json.MarshalIndent(res, "", "  ")
		fmt.Println(string(b))
		return
	}

	fmt.Printf("查询：")
	var bits []string
	if req.Domain != "" {
		bits = append(bits, "域名="+req.Domain)
	}
	if req.DestIP != "" {
		bits = append(bits, "IP="+req.DestIP)
	}
	if req.DestPort > 0 {
		bits = append(bits, "端口="+itoa(req.DestPort))
	}
	if req.Process != "" {
		bits = append(bits, "进程="+req.Process)
	}
	if req.Network != "" {
		bits = append(bits, "网络="+req.Network)
	}
	fmt.Println(strings.Join(bits, "  "))
	fmt.Println()

	if *verbose {
		fmt.Println("求值过程：")
		for _, s := range res.Steps {
			mark := "·"
			if s.Matched {
				mark = "命中"
			}
			detail := s.Detail
			if detail != "" {
				detail = "  ← " + detail
			}
			fmt.Printf("  %-4s 第%3d行  %-58s%s\n", mark, s.Line, firstToken(s.Rule, 58), detail)
		}
		fmt.Println()
	}

	if res.Matched {
		fmt.Printf("结果：命中第 %d 行规则 → 策略 %s\n", res.RuleLine, res.Policy)
		fmt.Printf("规则：%s\n", res.RuleRaw)
	} else {
		fmt.Printf("结果：未命中任何规则 → 兜底策略 %s\n", res.Policy)
	}
	for _, n := range res.Notes {
		fmt.Printf("  note: %s\n", n)
	}
}

func routeImport(args []string) {
	fs := flag.NewFlagSet("route import", flag.ExitOnError)
	in := fs.String("in", "", "输入文件（- 表示 stdin）")
	format := fs.String("format", "auto", "auto|clash-yaml|shadowrocket-conf|singbox-json|share-links")
	out := fs.String("out", "", "输出 profile JSON")
	merge := fs.String("merge", "", "合并进已有的 profile JSON")
	quiet := fs.Bool("quiet", false, "不打印摘要")
	fs.Parse(args)
	if *in == "" {
		fmt.Fprintln(os.Stderr, "ERR: 缺少 -in")
		os.Exit(2)
	}
	b, err := readAllPath(*in)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR: 读取失败:", err)
		os.Exit(1)
	}
	p, err := ImportConfig(string(b), *format)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR:", err)
		os.Exit(1)
	}
	if *merge != "" {
		base, err := loadProfile(*merge)
		if err == nil && base != nil {
			p = mergeProfiles(base, p)
		}
	}
	j, err := json.MarshalIndent(p, "", "  ")
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR: 序列化失败:", err)
		os.Exit(1)
	}
	if err := writeOut(*out, append(j, '\n')); err != nil {
		fmt.Fprintln(os.Stderr, "ERR: 写出失败:", err)
		os.Exit(1)
	}
	if !*quiet {
		counts := p.nodeTypeCounts()
		fmt.Fprintf(os.Stderr, "OK 节点 %d（", len(p.Nodes))
		ks := sortedKeys(counts)
		for i, k := range ks {
			if i > 0 {
				fmt.Fprint(os.Stderr, " ")
			}
			fmt.Fprintf(os.Stderr, "%s=%d", k, counts[k])
		}
		fmt.Fprintf(os.Stderr, "）策略组 %d 规则 %d 规则集 %d\n",
			len(p.Groups), len(p.Rules), len(p.RuleSets))
		for _, w := range p.Warnings {
			fmt.Fprintf(os.Stderr, "  warn: %s\n", w)
		}
	}
}

// mergeProfiles 把 add 合并进 base：节点按名字去重，组与规则追加
func mergeProfiles(base, add *Profile) *Profile {
	seen := map[string]bool{}
	for _, n := range base.Nodes {
		seen[n.Name] = true
	}
	for _, n := range add.Nodes {
		if seen[n.Name] {
			continue
		}
		seen[n.Name] = true
		base.Nodes = append(base.Nodes, n)
	}
	gseen := map[string]bool{}
	for _, g := range base.Groups {
		gseen[g.Name] = true
	}
	for _, g := range add.Groups {
		if gseen[g.Name] {
			continue
		}
		gseen[g.Name] = true
		base.Groups = append(base.Groups, g)
	}
	rseen := map[string]bool{}
	for _, r := range base.Rules {
		rseen[r.Kind+"\x00"+r.Payload+"\x00"+r.Policy] = true
	}
	for _, r := range add.Rules {
		k := r.Kind + "\x00" + r.Payload + "\x00" + r.Policy
		if rseen[k] {
			continue
		}
		rseen[k] = true
		base.Rules = append(base.Rules, r)
	}
	base.RuleSets = append(base.RuleSets, add.RuleSets...)
	base.Warnings = append(base.Warnings, add.Warnings...)
	return base
}

// routeExplain 展示每条规则编译后的 sing-box 形态
func routeExplain(args []string) {
	fs := flag.NewFlagSet("route explain", flag.ExitOnError)
	in := fs.String("profile", "", "profile JSON")
	asJSON := fs.Bool("json", false, "以 JSON 输出编译结果")
	fs.Parse(args)
	if *in == "" {
		fmt.Fprintln(os.Stderr, "ERR: 缺少 -profile")
		os.Exit(2)
	}
	p, err := loadProfile(*in)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR:", err)
		os.Exit(1)
	}
	resolve := func(pol string) (string, string, bool) {
		switch strings.ToUpper(pol) {
		case PolicyDirect:
			return "direct", "route", true
		case PolicyReject, PolicyRejectDrop:
			return "", "reject", true
		}
		return pol, "route", true
	}
	geo := func(kind, code string) string {
		code = strings.ToLower(strings.TrimSpace(code))
		if kind == RGeoIP {
			return "geoip-" + code
		}
		return "geosite-" + code
	}
	if *asJSON {
		out := []map[string]any{}
		for i := range p.Rules {
			r := &p.Rules[i]
			item := map[string]any{
				"line": r.Line, "kind": r.Kind, "payload": r.Payload, "policy": r.Policy,
			}
			obj, err := compileRule(r, resolve, geo, p)
			if err != nil {
				item["error"] = err.Error()
			} else {
				item["compiled"] = obj
			}
			out = append(out, item)
		}
		b, _ := json.MarshalIndent(out, "", "  ")
		fmt.Println(string(b))
		return
	}
	fmt.Printf("%-4s %-20s %-30s %-10s %s\n", "行", "类型", "载荷", "策略", "编译结果")
	fmt.Println(strings.Repeat("-", 118))
	okN, failN := 0, 0
	for i := range p.Rules {
		r := &p.Rules[i]
		obj, err := compileRule(r, resolve, geo, p)
		status := ""
		if err != nil {
			status = "✗ " + err.Error()
			failN++
		} else {
			b, _ := json.Marshal(obj)
			status = "✓ " + string(b)
			okN++
		}
		fmt.Printf("%-4d %-20s %-30s %-10s %s\n",
			r.Line, r.Kind, firstToken(r.Payload, 30), r.Policy, firstToken(status, 60))
	}
	fmt.Printf("\n可编译 %d 条，失败 %d 条\n", okN, failN)
}

// ---------- clash ----------

func cmdClash(args []string) {
	fs := flag.NewFlagSet("clash", flag.ExitOnError)
	api := fs.String("api", "127.0.0.1:9090", "Clash API 地址")
	secret := fs.String("secret", "", "API 密钥")
	name := fs.String("name", "", "节点/策略组名")
	group := fs.String("group", "", "策略组名")
	to := fs.String("to", "", "切换到该成员")
	testURL := fs.String("url", "", "测速地址")
	timeout := fs.Int("timeout", 5000, "测速超时毫秒")
	mode := fs.String("mode", "", "切换到该模式 rule/global/direct")
	level := fs.String("level", "info", "日志级别")
	lines := fs.Int("lines", 40, "日志行数")
	secs := fs.Int("secs", 3, "采样秒数")
	asJSON := fs.Bool("json", false, "以 JSON 输出")
	closeID := fs.String("close", "", "关闭指定连接（空字符串表示全部）")

	// 两段式解析：先吃掉子命令前面的全局选项（-api/-secret），
	// 再拿子命令后面的选项（-group/-to/-name…）。
	// Go 的 flag 包遇到第一个非选项参数就会停下，一次 Parse 拿不全。
	fs.Parse(args)
	rest := fs.Args()
	if len(rest) == 0 {
		fmt.Fprintln(os.Stderr, `用法: abserver clash -api ADDR [-secret S] <子命令>
  status              内核版本、模式、流量
  conn                当前连接列表
  traffic [-secs N]   实时上下行速率
  proxies             策略组与成员
  delay -name X       测延迟
  select -group G -to M   切换策略组成员
  mode [-mode rule]   读取或切换模式
  logs [-level L] [-lines N]  采集内核日志
  close [-close ID]   关闭连接`)
		os.Exit(2)
	}
	sub := rest[0]
	if len(rest) > 1 {
		if err := fs.Parse(rest[1:]); err != nil {
			fmt.Fprintln(os.Stderr, "ERR:", err)
			os.Exit(2)
		}
	}
	c := NewClashClient(*api, *secret)

	switch sub {
	case "status":
		ver, err := c.Version()
		if err != nil {
			fmt.Fprintln(os.Stderr, "ERR:", err)
			os.Exit(1)
		}
		m, _ := c.Mode()
		up, down, terr := c.TrafficSample()
		if *asJSON {
			b, _ := json.MarshalIndent(map[string]any{
				"version": ver, "mode": m, "up": up, "down": down,
			}, "", "  ")
			fmt.Println(string(b))
			return
		}
		fmt.Printf("内核版本   %s\n", ver)
		fmt.Printf("运行模式   %s\n", orDefault(m, "unknown"))
		if terr == nil {
			fmt.Printf("实时流量   ↑ %s   ↓ %s\n", humanSpeed(up), humanSpeed(down))
		}
		conns, err := c.Connections()
		if err == nil {
			fmt.Printf("活动连接   %d 条\n", len(conns.Connections))
			fmt.Printf("累计流量   ↑ %s   ↓ %s\n",
				humanBytes(conns.UploadTotal), humanBytes(conns.DownloadTotal))
		}

	case "conn":
		conns, err := c.Connections()
		if err != nil {
			fmt.Fprintln(os.Stderr, "ERR:", err)
			os.Exit(1)
		}
		if *asJSON {
			b, _ := json.MarshalIndent(conns, "", "  ")
			fmt.Println(string(b))
			return
		}
		fmt.Printf("活动连接 %d 条   累计 ↑%s ↓%s\n\n",
			len(conns.Connections), humanBytes(conns.UploadTotal), humanBytes(conns.DownloadTotal))
		fmt.Printf("%-22s %-8s %-24s %-10s %-16s %s\n",
			"目标", "网络", "来源", "上行/下行", "命中规则", "出口链路")
		fmt.Println(strings.Repeat("-", 120))
		items := conns.Connections
		sort.Slice(items, func(i, j int) bool {
			return items[i].Download+items[i].Upload > items[j].Download+items[j].Upload
		})
		for _, cn := range items {
			host := orDefault(cn.Metadata.Host, cn.Metadata.DestinationIP)
			if host == "" {
				host = cn.Metadata.SniffHost
			}
			if len(host) > 22 {
				host = host[:21] + "…"
			}
			src := cn.Metadata.SourceIP + ":" + cn.Metadata.SourcePort
			traffic := humanBytes(cn.Upload) + "/" + humanBytes(cn.Download)
			rule := cn.Rule
			if cn.RulePayload != "" {
				rule += " " + cn.RulePayload
			}
			if len(rule) > 16 {
				rule = rule[:15] + "…"
			}
			chain := strings.Join(cn.Chains, " → ")
			if len(chain) > 30 {
				chain = chain[:29] + "…"
			}
			fmt.Printf("%-22s %-8s %-24s %-10s %-16s %s\n",
				host, cn.Metadata.Network, src, traffic, rule, chain)
		}

	case "traffic":
		up, down, err := c.TrafficSample()
		if err != nil {
			fmt.Fprintln(os.Stderr, "ERR:", err)
			os.Exit(1)
		}
		if *asJSON {
			b, _ := json.MarshalIndent(map[string]any{"up": up, "down": down}, "", "  ")
			fmt.Println(string(b))
			return
		}
		if *secs > 1 {
			// 连续采样，给出波动范围
			fmt.Printf("采样 %d 秒...\n", *secs)
			maxUp, maxDown := up, down
			for i := 0; i < *secs-1; i++ {
				time.Sleep(time.Second)
				u, d, err := c.TrafficSample()
				if err != nil {
					continue
				}
				if u > maxUp {
					maxUp = u
				}
				if d > maxDown {
					maxDown = d
				}
				up, down = u, d
			}
			fmt.Printf("当前  ↑ %-12s ↓ %-12s\n", humanSpeed(up), humanSpeed(down))
			fmt.Printf("峰值  ↑ %-12s ↓ %-12s\n", humanSpeed(maxUp), humanSpeed(maxDown))
			return
		}
		fmt.Printf("↑ %s   ↓ %s\n", humanSpeed(up), humanSpeed(down))

	case "proxies":
		px, err := c.Proxies()
		if err != nil {
			fmt.Fprintln(os.Stderr, "ERR:", err)
			os.Exit(1)
		}
		if *asJSON {
			b, _ := json.MarshalIndent(px, "", "  ")
			fmt.Println(string(b))
			return
		}
		names := make([]string, 0, len(px))
		for k := range px {
			names = append(names, k)
		}
		sort.Strings(names)
		for _, n := range names {
			v := px[n]
			if v.Type == "Selector" || v.Type == "URLTest" || v.Type == "Fallback" ||
				v.Type == "LoadBalance" || v.Type == "Relay" {
				fmt.Printf("[策略组] %-24s 类型=%-12s 当前=%s\n", n, v.Type, v.Now)
				fmt.Printf("          成员: %s\n", strings.Join(v.All, ", "))
			}
		}
		fmt.Println()
		for _, n := range names {
			v := px[n]
			if v.Type == "Selector" || v.Type == "URLTest" || v.Type == "Fallback" ||
				v.Type == "LoadBalance" || v.Type == "Relay" {
				continue
			}
			delay := "-"
			if len(v.History) > 0 {
				delay = itoa(v.History[len(v.History)-1].Delay) + "ms"
			}
			fmt.Printf("[节点]   %-24s 类型=%-14s 延迟=%s\n", n, v.Type, delay)
		}

	case "delay":
		if *name == "" {
			fmt.Fprintln(os.Stderr, "ERR: 缺少 -name")
			os.Exit(2)
		}
		d, err := c.DelayTest(*name, *testURL, *timeout)
		if err != nil {
			fmt.Fprintf(os.Stderr, "ERR: %s 测速失败: %v\n", *name, err)
			os.Exit(1)
		}
		if *asJSON {
			b, _ := json.MarshalIndent(map[string]any{"name": *name, "delay": d}, "", "  ")
			fmt.Println(string(b))
			return
		}
		fmt.Printf("%s 延迟 %d ms\n", *name, d)

	case "select":
		if *group == "" || *to == "" {
			fmt.Fprintln(os.Stderr, "ERR: 需要 -group 与 -to")
			os.Exit(2)
		}
		if err := c.Select(*group, *to); err != nil {
			fmt.Fprintln(os.Stderr, "ERR:", err)
			os.Exit(1)
		}
		fmt.Printf("OK: 策略组 %s 已切换到 %s\n", *group, *to)

	case "mode":
		if *mode == "" {
			m, err := c.Mode()
			if err != nil {
				fmt.Fprintln(os.Stderr, "ERR:", err)
				os.Exit(1)
			}
			fmt.Println(m)
			return
		}
		if err := c.SetMode(*mode); err != nil {
			fmt.Fprintln(os.Stderr, "ERR:", err)
			os.Exit(1)
		}
		fmt.Printf("OK: 模式已切换为 %s\n", *mode)

	case "logs":
		ls, err := c.Logs(*level, *lines, time.Duration(*secs)*time.Second)
		if err != nil {
			fmt.Fprintln(os.Stderr, "ERR:", err)
			os.Exit(1)
		}
		if *asJSON {
			b, _ := json.MarshalIndent(ls, "", "  ")
			fmt.Println(string(b))
			return
		}
		for _, l := range ls {
			fmt.Printf("[%s] %s\n", l.Type, l.Payload)
		}

	case "close":
		if err := c.CloseConnection(*closeID); err != nil {
			fmt.Fprintln(os.Stderr, "ERR:", err)
			os.Exit(1)
		}
		fmt.Println("OK: 已关闭连接")

	default:
		fmt.Fprintf(os.Stderr, "ERR: 未知子命令 %q\n", sub)
		os.Exit(2)
	}
}

// ---------- 规则集镜像与本地化 ----------

// routeMirrors 列出/实测规则集镜像。国内网络下不同 CDN 差别极大，
// 与其让用户一个个试，不如直接给实测结果。
func routeMirrors(args []string) {
	fs := flag.NewFlagSet("route mirrors", flag.ExitOnError)
	probe := fs.Bool("probe", false, "逐个实测连通性与耗时")
	asJSON := fs.Bool("json", false, "以 JSON 输出")
	timeout := fs.Int("timeout", 12, "单个镜像超时秒数")
	fs.Parse(args)

	type result struct {
		Name    string `json:"name"`
		URL     string `json:"url"`
		OK      bool   `json:"ok"`
		Millis  int64  `json:"millis"`
		Size    int    `json:"size"`
		Err     string `json:"error,omitempty"`
		Default bool   `json:"default,omitempty"`
	}
	out := []result{}
	for _, m := range ruleMirrors {
		u := buildRuleSetURL(m.Name, RGeoSite, "cn")
		r := result{Name: m.Name, URL: u, Default: m.Name == DefaultMirror}
		if *probe {
			start := time.Now()
			b, err := httpGetBytes(u, time.Duration(*timeout)*time.Second)
			r.Millis = time.Since(start).Milliseconds()
			if err != nil {
				r.Err = err.Error()
			} else {
				r.OK, r.Size = true, len(b)
			}
		}
		out = append(out, r)
	}
	if *asJSON {
		b, _ := json.MarshalIndent(out, "", "  ")
		fmt.Println(string(b))
		return
	}
	if !*probe {
		for _, r := range out {
			mark := " "
			if r.Default {
				mark = "*"
			}
			fmt.Printf("%s %-11s %s\n", mark, r.Name, r.URL)
		}
		fmt.Println("\n带 * 为默认。加 -probe 实测连通性与耗时。")
		return
	}
	for _, r := range out {
		mark := " "
		if r.Default {
			mark = "*"
		}
		if r.OK {
			fmt.Printf("%s %-11s %5dms  %7d B  OK\n", mark, r.Name, r.Millis, r.Size)
		} else {
			fmt.Printf("%s %-11s %5dms  FAIL      %s\n", mark, r.Name, r.Millis, firstToken(r.Err, 70))
		}
	}
}

// 常用规则集清单：一份能覆盖绝大多数路由场景的最小集合。
var defaultGeoSiteCodes = []string{
	"cn", "geolocation-!cn", "category-ads-all", "private",
	"apple", "google", "microsoft", "telegram", "youtube",
	"netflix", "openai", "category-games", "category-media",
	"category-communication", "category-ai-chat-!cn",
}

var defaultGeoIPCodes = []string{"cn", "private"}

// routeFetchRules 把 .srs 规则集抓到本地目录，之后编译即可完全离线。
// 模块的使用场景常常是"手机上没网"，把规则集内置进去比依赖 CDN 可靠得多。
func routeFetchRules(args []string) {
	fs := flag.NewFlagSet("route fetch-rules", flag.ExitOnError)
	dir := fs.String("dir", "", "输出目录（必填）")
	codes := fs.String("codes", "", "geosite 代码，逗号分隔；空则用内置清单")
	geoipCodes := fs.String("geoip-codes", "", "geoip 代码，逗号分隔；空则用内置清单")
	mirror := fs.String("mirror", "", "优先镜像；失败时自动按顺序回退")
	noGeoIP := fs.Bool("no-geoip", false, "不抓 geoip")
	timeout := fs.Int("timeout", 30, "单个文件超时秒数")
	asJSON := fs.Bool("json", false, "以 JSON 输出")
	fs.Parse(args)

	if *dir == "" {
		fmt.Fprintln(os.Stderr, "ERR: 缺少 -dir")
		os.Exit(2)
	}
	if err := os.MkdirAll(*dir, 0o755); err != nil {
		fmt.Fprintln(os.Stderr, "ERR: 无法创建目录:", err)
		os.Exit(1)
	}

	gs := defaultGeoSiteCodes
	if *codes != "" {
		gs = splitCSV(*codes)
	}
	gi := defaultGeoIPCodes
	if *geoipCodes != "" {
		gi = splitCSV(*geoipCodes)
	}
	if *noGeoIP {
		gi = nil
	}

	// 镜像顺序：指定的优先，其余按默认顺序补齐
	order := []string{}
	if *mirror != "" {
		order = append(order, *mirror)
	} else {
		order = append(order, DefaultMirror)
	}
	for _, m := range ruleMirrors {
		dup := false
		for _, o := range order {
			if o == m.Name {
				dup = true
				break
			}
		}
		if !dup {
			order = append(order, m.Name)
		}
	}

	type item struct {
		File    string `json:"file"`
		Kind    string `json:"kind"`
		Code    string `json:"code"`
		OK      bool   `json:"ok"`
		Bytes   int    `json:"bytes"`
		Mirror  string `json:"mirror,omitempty"`
		Err     string `json:"error,omitempty"`
		Elapsed int64  `json:"elapsed_ms"`
	}
	results := []item{}
	okN, failN := 0, 0

	doOne := func(kind, code string) {
		fileName := RuleSetFileName(kind, code)
		dest := filepath.Join(*dir, fileName)
		// 已存在且非空就跳过，支持断点续抓
		if st, err := os.Stat(dest); err == nil && st.Size() > 0 {
			results = append(results, item{File: fileName, Kind: kind, Code: code, OK: true, Bytes: int(st.Size()), Mirror: "(cached)"})
			okN++
			return
		}
		var lastErr error
		for _, mname := range order {
			u := buildRuleSetURL(mname, kind, code)
			start := time.Now()
			b, err := httpGetBytes(u, time.Duration(*timeout)*time.Second)
			el := time.Since(start).Milliseconds()
			if err != nil {
				lastErr = err
				continue
			}
			if len(b) < 64 {
				lastErr = fmt.Errorf("响应过小（%d B），疑似被劫持", len(b))
				continue
			}
			if err := os.WriteFile(dest, b, 0o644); err != nil {
				lastErr = err
				continue
			}
			results = append(results, item{File: fileName, Kind: kind, Code: code, OK: true, Bytes: len(b), Mirror: mname, Elapsed: el})
			okN++
			if !*asJSON {
				fmt.Fprintf(os.Stderr, "  [ok] %-34s %8d B  %5dms  %s\n", fileName, len(b), el, mname)
			}
			return
		}
		results = append(results, item{File: fileName, Kind: kind, Code: code, Err: fmt.Sprint(lastErr)})
		failN++
		if !*asJSON {
			fmt.Fprintf(os.Stderr, "  [FAIL] %-32s %s\n", fileName, firstToken(fmt.Sprint(lastErr), 70))
		}
	}

	if !*asJSON {
		fmt.Fprintf(os.Stderr, "抓取规则集到 %s（镜像顺序：%s）\n", *dir, strings.Join(order, " > "))
	}
	for _, c := range gs {
		doOne(RGeoSite, c)
	}
	for _, c := range gi {
		doOne(RGeoIP, c)
	}

	if *asJSON {
		b, _ := json.MarshalIndent(map[string]any{
			"dir": *dir, "ok": okN, "failed": failN, "items": results,
		}, "", "  ")
		fmt.Println(string(b))
	} else {
		fmt.Fprintf(os.Stderr, "\n完成：成功 %d，失败 %d，目录 %s\n", okN, failN, *dir)
	}
	if failN > 0 {
		os.Exit(1)
	}
}

func splitCSV(s string) []string {
	out := []string{}
	for _, p := range strings.Split(s, ",") {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

// ---------- profile 修改 ----------

// routeSet 就地修改 profile 的通用配置。
// shell 侧不方便直接编辑 JSON，交给 Go 来改最稳。
func routeSet(args []string) {
	fs := flag.NewFlagSet("route set", flag.ExitOnError)
	in := fs.String("profile", "", "profile JSON（必填）")
	out := fs.String("out", "", "输出路径，留空则原地覆盖")
	mixedPort := fs.Int("mixed-port", -1, "混合入站端口")
	tun := fs.String("tun", "", "TUN：on/off")
	clashAPI := fs.String("clash-api", "", "Clash API：on/off")
	clashPort := fs.Int("clash-port", -1, "Clash API 端口")
	logLevel := fs.String("log-level", "", "日志级别")
	sbVersion := fs.String("sb-version", "", "目标内核版本")
	final := fs.String("final", "", "兜底策略")
	strictRoute := fs.String("strict-route", "", "严格路由：on/off")
	privateDirect := fs.String("private-direct", "", "私网直连：on/off")
	fs.Parse(args)

	if *in == "" {
		fmt.Fprintln(os.Stderr, "ERR: 缺少 -profile")
		os.Exit(2)
	}
	p, err := loadProfile(*in)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR:", err)
		os.Exit(1)
	}
	if *mixedPort >= 0 {
		p.General.MixedPort = *mixedPort
	}
	applyOnOff(*tun, &p.General.TunEnabled)
	applyOnOff(*clashAPI, &p.General.ClashAPI)
	applyOnOff(*strictRoute, &p.General.StrictRoute)
	if b, ok := parseOnOff(*privateDirect); ok {
		p.General.PrivateDirect = &b
	}
	if *clashPort >= 0 {
		p.General.ClashAPIPort = *clashPort
	}
	if *logLevel != "" {
		p.General.LogLevel = *logLevel
	}
	if *sbVersion != "" {
		p.General.SingBoxVersion = *sbVersion
	}
	if *final != "" {
		p.General.FinalPolicy = normalizePolicy(*final)
		// 同时改写 MATCH/FINAL 规则，保证两边一致
		found := false
		for i := range p.Rules {
			if p.Rules[i].Kind == RMatch || p.Rules[i].Kind == RFinal {
				p.Rules[i].Policy = normalizePolicy(*final)
				found = true
			}
		}
		if !found {
			p.Rules = append(p.Rules, Rule{
				Kind: RMatch, Payload: "*", Policy: normalizePolicy(*final), Enabled: true,
			})
		}
	}

	dest := *out
	if dest == "" {
		dest = *in
	}
	b, _ := json.MarshalIndent(p, "", "  ")
	if err := os.WriteFile(dest, b, 0o644); err != nil {
		fmt.Fprintln(os.Stderr, "ERR: 写入失败:", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "OK: 已更新 %s\n", dest)
}

func applyOnOff(v string, target *bool) {
	if b, ok := parseOnOff(v); ok {
		*target = b
	}
}

func parseOnOff(v string) (bool, bool) {
	switch strings.ToLower(strings.TrimSpace(v)) {
	case "on", "true", "1", "yes":
		return true, true
	case "off", "false", "0", "no":
		return false, true
	}
	return false, false
}

// routeSummary 给面板用的概览：节点/组/规则的统计与清单。
func routeSummary(args []string) {
	fs := flag.NewFlagSet("route summary", flag.ExitOnError)
	in := fs.String("profile", "", "profile JSON")
	fs.Parse(args)
	if *in == "" {
		fmt.Fprintln(os.Stderr, "ERR: 缺少 -profile")
		os.Exit(2)
	}
	p, err := loadProfile(*in)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR:", err)
		os.Exit(1)
	}
	type nodeBrief struct {
		Name   string `json:"name"`
		Type   string `json:"type"`
		Server string `json:"server"`
		Port   int    `json:"port"`
	}
	type groupBrief struct {
		Name    string   `json:"name"`
		Type    string   `json:"type"`
		Members []string `json:"members"`
	}
	type ruleBrief struct {
		Line    int    `json:"line"`
		Kind    string `json:"kind"`
		Payload string `json:"payload"`
		Policy  string `json:"policy"`
		Enabled bool   `json:"enabled"`
	}
	nb := []nodeBrief{}
	for _, n := range p.Nodes {
		nb = append(nb, nodeBrief{n.Name, n.Type, n.Server, n.Port})
	}
	gb := []groupBrief{}
	for _, g := range p.Groups {
		gb = append(gb, groupBrief{g.Name, g.Type, g.Proxies})
	}
	rb := []ruleBrief{}
	for _, r := range p.Rules {
		rb = append(rb, ruleBrief{r.Line, r.Kind, r.Payload, r.Policy, r.Enabled})
	}
	issues := LintRules(p)
	nErr, nWarn := 0, 0
	for _, i := range issues {
		switch i.Level {
		case "error":
			nErr++
		case "warn":
			nWarn++
		}
	}
	b, _ := json.MarshalIndent(map[string]any{
		"nodes": nb, "groups": gb, "rules": rb,
		"counts": map[string]any{
			"nodes": len(nb), "groups": len(gb), "rules": len(rb),
			"rule_sets": len(p.RuleSets), "errors": nErr, "warnings": nWarn,
		},
		"node_types": p.nodeTypeCounts(),
		"general":    p.General,
		"source":     p.Source,
	}, "", "  ")
	fmt.Println(string(b))
}

// routeAddNode 从分享链接/订阅批量追加节点。
func routeAddNode(args []string) {
	fs := flag.NewFlagSet("route add-node", flag.ExitOnError)
	in := fs.String("profile", "", "profile JSON")
	link := fs.String("link", "", "单个分享链接")
	from := fs.String("in", "", "含多个链接/订阅内容的文件，- 表示 stdin")
	group := fs.String("group", "", "同时加入该策略组")
	fs.Parse(args)
	if *in == "" {
		fmt.Fprintln(os.Stderr, "ERR: 缺少 -profile")
		os.Exit(2)
	}
	p, err := loadProfile(*in)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR:", err)
		os.Exit(1)
	}
	text := *link
	if *from != "" {
		b, err := readAllPath(*from)
		if err != nil {
			fmt.Fprintln(os.Stderr, "ERR: 读取失败:", err)
			os.Exit(1)
		}
		if text != "" {
			text += "\n"
		}
		text += string(b)
	}
	if strings.TrimSpace(text) == "" {
		fmt.Fprintln(os.Stderr, "ERR: 没有可导入的内容（用 -link 或 -in）")
		os.Exit(2)
	}
	nodes, errs := ParseLinks(text)
	// 订阅体可能是整体 base64
	if len(nodes) == 0 {
		if dec, ok := b64Any(text); ok && len(dec) > 0 && string(dec) != text {
			nodes, errs = ParseLinks(string(dec))
		}
	}
	if len(nodes) == 0 {
		fmt.Fprintln(os.Stderr, "ERR: 未解析出任何节点")
		for _, e := range errs {
			fmt.Fprintln(os.Stderr, "  ", e)
		}
		os.Exit(1)
	}
	added := 0
	for _, n := range nodes {
		if p.nodeByName(n.Name) != nil {
			continue
		}
		n.Source = "import"
		p.Nodes = append(p.Nodes, n)
		added++
		if *group != "" {
			if g := p.groupByName(*group); g != nil {
				g.Proxies = append(g.Proxies, n.Name)
			}
		}
	}
	b, _ := json.MarshalIndent(p, "", "  ")
	if err := os.WriteFile(*in, b, 0o644); err != nil {
		fmt.Fprintln(os.Stderr, "ERR: 写入失败:", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "OK: 新增 %d 个节点（解析失败 %d 条），当前共 %d 个\n",
		added, len(errs), len(p.Nodes))
}

// routeAddRule 追加一条或多条规则。
func routeAddRule(args []string) {
	fs := flag.NewFlagSet("route add-rule", flag.ExitOnError)
	in := fs.String("profile", "", "profile JSON")
	line := fs.String("rule", "", "单条规则，如 DOMAIN-SUFFIX,example.com,PROXY")
	from := fs.String("in", "", "含多行规则的文件，- 表示 stdin")
	fs.Parse(args)
	if *in == "" {
		fmt.Fprintln(os.Stderr, "ERR: 缺少 -profile")
		os.Exit(2)
	}
	p, err := loadProfile(*in)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR:", err)
		os.Exit(1)
	}
	text := *line
	if *from != "" {
		b, err := readAllPath(*from)
		if err != nil {
			fmt.Fprintln(os.Stderr, "ERR: 读取失败:", err)
			os.Exit(1)
		}
		if text != "" {
			text += "\n"
		}
		text += string(b)
	}
	added, failed := 0, 0
	for _, l := range strings.Split(text, "\n") {
		l = strings.TrimSpace(l)
		if l == "" || strings.HasPrefix(l, "#") || strings.HasPrefix(l, "//") {
			continue
		}
		r, err := ParseRuleLine(l, len(p.Rules)+1)
		if err != nil {
			fmt.Fprintf(os.Stderr, "  skip %q: %v\n", l, err)
			failed++
			continue
		}
		p.Rules = append(p.Rules, r)
		added++
	}
	// 保持 MATCH/FINAL 在最后
	sort.SliceStable(p.Rules, func(i, j int) bool {
		ci := p.Rules[i].Kind == RMatch || p.Rules[i].Kind == RFinal
		cj := p.Rules[j].Kind == RMatch || p.Rules[j].Kind == RFinal
		if ci != cj {
			return !ci
		}
		return false
	})
	b, _ := json.MarshalIndent(p, "", "  ")
	if err := os.WriteFile(*in, b, 0o644); err != nil {
		fmt.Fprintln(os.Stderr, "ERR: 写入失败:", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "OK: 新增 %d 条规则（跳过 %d 条），当前共 %d 条\n",
		added, failed, len(p.Rules))
}
