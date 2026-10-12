// ============================================================
//
//	nodes.go — 分享链接解析
//	ss / ssr / vmess / vless / trojan / hysteria2 / tuic / socks / http
//	链接格式参考 Shadowrocket 与 SIP002 规范。
//
// ============================================================
package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/url"
	"strconv"
	"strings"
)

// b64Any 宽容的 base64 解码：自动补 padding，兼容 URL-safe
func b64Any(s string) ([]byte, bool) {
	s = strings.TrimSpace(s)
	s = strings.ReplaceAll(s, "-", "+")
	s = strings.ReplaceAll(s, "_", "/")
	if i := strings.IndexAny(s, "\r\n"); i >= 0 {
		s = s[:i]
	}
	for _, enc := range []*base64.Encoding{base64.StdEncoding, base64.RawStdEncoding} {
		if b, err := enc.DecodeString(s); err == nil {
			return b, true
		}
	}
	// 补 padding 再试
	if m := len(s) % 4; m != 0 {
		s2 := s + strings.Repeat("=", 4-m)
		if b, err := base64.StdEncoding.DecodeString(s2); err == nil {
			return b, true
		}
	}
	return nil, false
}

// ParseShareLink 解析一条分享链接
func ParseShareLink(link string) (Node, error) {
	link = strings.TrimSpace(link)
	n := Node{RawLink: link, Source: "manual"}
	lower := strings.ToLower(link)
	switch {
	case strings.HasPrefix(lower, "vmess://"):
		return parseVMess(link)
	case strings.HasPrefix(lower, "vless://"):
		return parseVless(link)
	case strings.HasPrefix(lower, "trojan://"):
		return parseTrojan(link)
	case strings.HasPrefix(lower, "ssr://"):
		return parseSSR(link)
	case strings.HasPrefix(lower, "ss://"):
		return parseSS(link)
	case strings.HasPrefix(lower, "hysteria2://"), strings.HasPrefix(lower, "hy2://"):
		return parseHysteria2(link)
	case strings.HasPrefix(lower, "tuic://"):
		return parseTUIC(link)
	case strings.HasPrefix(lower, "socks://"), strings.HasPrefix(lower, "socks5://"):
		return parseSocksLike(link, "socks")
	case strings.HasPrefix(lower, "http://"), strings.HasPrefix(lower, "https://"):
		return parseSocksLike(link, "http")
	}
	return n, fmt.Errorf("不支持的分享链接协议: %s", firstToken(link, 24))
}

func firstToken(s string, n int) string {
	if len(s) > n {
		return s[:n] + "…"
	}
	return s
}

// nameFromFragment 取 # 后面的备注名
func nameFromFragment(u *url.URL, def string) string {
	if u.Fragment != "" {
		if s, err := url.QueryUnescape(u.Fragment); err == nil && s != "" {
			return s
		}
		return u.Fragment
	}
	return def
}

func parseVMess(link string) (Node, error) {
	n := Node{Type: "vmess"}
	body := link[len("vmess://"):]
	if i := strings.Index(body, "#"); i >= 0 {
		if s, err := url.QueryUnescape(body[i+1:]); err == nil && s != "" {
			n.Name = s
		}
		body = body[:i]
	}
	dec, ok := b64Any(body)
	if !ok {
		return n, fmt.Errorf("vmess 链接的 base64 无法解码")
	}
	var v map[string]any
	if err := json.Unmarshal(dec, &v); err != nil {
		return n, fmt.Errorf("vmess 链接的 JSON 非法: %v", err)
	}
	n.Server = jstr(v, "add")
	n.Port = jnum(v, "port")
	n.UUID = jstr(v, "id")
	n.AlterID = jnum(v, "aid")
	n.Network = strings.ToLower(jstr(v, "net"))
	if n.Network == "" {
		n.Network = "tcp"
	}
	n.WSHost = jstr(v, "host")
	n.WSPath = jstr(v, "path")
	n.SNI = jstr(v, "sni")
	tls := strings.ToLower(jstr(v, "tls"))
	n.TLS = tls == "tls" || tls == "true" || tls == "reality"
	if fp := jstr(v, "fp"); fp != "" {
		n.Fingerprint = fp
	}
	if s := jstr(v, "scy"); s != "" {
		n.Extra = map[string]any{"security": s}
	}
	if n.Name == "" {
		n.Name = jstr(v, "ps")
	}
	if n.Name == "" {
		n.Name = n.Server
	}
	if n.Server == "" || n.Port == 0 {
		return n, fmt.Errorf("vmess 链接缺少服务器或端口")
	}
	return n, nil
}

func parseVless(link string) (Node, error) {
	n := Node{Type: "vless", Network: "tcp"}
	u, err := url.Parse(link)
	if err != nil {
		return n, fmt.Errorf("vless 链接无法解析: %v", err)
	}
	n.UUID = u.User.Username()
	n.Server = u.Hostname()
	n.Port = atoiSafe(u.Port())
	n.Name = nameFromFragment(u, n.Server)
	q := u.Query()
	sec := strings.ToLower(q.Get("security"))
	n.TLS = sec == "tls" || sec == "reality" || sec == "xtls"
	n.SNI = q.Get("sni")
	if n.SNI == "" {
		n.SNI = q.Get("peer")
	}
	n.Flow = q.Get("flow")
	n.Fingerprint = q.Get("fp")
	n.Network = strings.ToLower(q.Get("type"))
	if n.Network == "" {
		n.Network = "tcp"
	}
	n.WSPath = q.Get("path")
	n.WSHost = q.Get("host")
	n.GRPCService = q.Get("serviceName")
	if n.GRPCService == "" {
		n.GRPCService = q.Get("service")
	}
	n.RealityPBK = q.Get("pbk")
	n.RealitySID = q.Get("sid")
	if alpn := q.Get("alpn"); alpn != "" {
		n.ALPN = strings.Split(alpn, ",")
	}
	if q.Get("allowInsecure") == "1" || q.Get("insecure") == "1" {
		n.Insecure = true
	}
	if n.Server == "" || n.Port == 0 {
		return n, fmt.Errorf("vless 链接缺少服务器或端口")
	}
	if n.UUID == "" {
		return n, fmt.Errorf("vless 链接缺少 UUID")
	}
	return n, nil
}

func parseTrojan(link string) (Node, error) {
	n := Node{Type: "trojan", TLS: true, Network: "tcp"}
	u, err := url.Parse(link)
	if err != nil {
		return n, fmt.Errorf("trojan 链接无法解析: %v", err)
	}
	n.Password = u.User.Username()
	if pw, ok := u.User.Password(); ok && pw != "" {
		n.Password = n.Password + ":" + pw
	}
	n.Server = u.Hostname()
	n.Port = atoiSafe(u.Port())
	n.Name = nameFromFragment(u, n.Server)
	q := u.Query()
	n.SNI = q.Get("sni")
	if n.SNI == "" {
		n.SNI = q.Get("peer")
	}
	n.Network = strings.ToLower(q.Get("type"))
	if n.Network == "" {
		n.Network = "tcp"
	}
	n.WSPath = q.Get("path")
	n.WSHost = q.Get("host")
	n.GRPCService = q.Get("serviceName")
	if alpn := q.Get("alpn"); alpn != "" {
		n.ALPN = strings.Split(alpn, ",")
	}
	if q.Get("allowInsecure") == "1" || q.Get("insecure") == "1" {
		n.Insecure = true
	}
	if n.Server == "" || n.Port == 0 {
		return n, fmt.Errorf("trojan 链接缺少服务器或端口")
	}
	return n, nil
}

func parseSS(link string) (Node, error) {
	n := Node{Type: "shadowsocks"}
	body := link[len("ss://"):]
	if i := strings.Index(body, "#"); i >= 0 {
		if s, err := url.QueryUnescape(body[i+1:]); err == nil && s != "" {
			n.Name = s
		}
		body = body[:i]
	}
	// 去掉 query（plugin 等）
	var query string
	if i := strings.Index(body, "?"); i >= 0 {
		query = body[i+1:]
		body = body[:i]
	}
	var userinfo, hostport string
	if i := strings.LastIndex(body, "@"); i >= 0 {
		userinfo = body[:i]
		hostport = body[i+1:]
		// userinfo 可能是 base64
		if dec, ok := b64Any(userinfo); ok && strings.Contains(string(dec), ":") {
			userinfo = string(dec)
		}
	} else {
		dec, ok := b64Any(body)
		if !ok {
			return n, fmt.Errorf("ss 链接无法解码")
		}
		full := string(dec)
		i := strings.LastIndex(full, "@")
		if i < 0 {
			return n, fmt.Errorf("ss 链接缺少 @")
		}
		userinfo = full[:i]
		hostport = full[i+1:]
	}
	if i := strings.Index(userinfo, ":"); i >= 0 {
		n.Method = userinfo[:i]
		n.Password = userinfo[i+1:]
	} else {
		return n, fmt.Errorf("ss 链接缺少加密方式")
	}
	host, port, err := splitHostPort(hostport)
	if err != nil {
		return n, err
	}
	n.Server = host
	n.Port = port
	if n.Name == "" {
		n.Name = n.Server
	}
	if query != "" {
		if q, err := url.ParseQuery(query); err == nil {
			n.Plugin = q.Get("plugin")
			if n.Plugin != "" {
				n.PluginOpts = strings.ReplaceAll(q.Get("plugin"), ";", "|")
			}
		}
	}
	return n, nil
}

func parseSSR(link string) (Node, error) {
	n := Node{Type: "shadowsocksr"}
	body := link[len("ssr://"):]
	dec, ok := b64Any(body)
	if !ok {
		return n, fmt.Errorf("ssr 链接无法解码")
	}
	full := string(dec)
	main := full
	var params string
	if i := strings.Index(full, "/?"); i >= 0 {
		main = full[:i]
		params = full[i+2:]
	}
	parts := strings.Split(main, ":")
	if len(parts) < 6 {
		return n, fmt.Errorf("ssr 链接字段不足（需要 host:port:protocol:method:obfs:password）")
	}
	n.Server = parts[0]
	n.Port = atoiSafe(parts[1])
	n.SSRProtocol = parts[2]
	n.Method = parts[3]
	n.SSRObfs = parts[4]
	pw := strings.Join(parts[5:], ":")
	if b, ok := b64Any(pw); ok {
		pw = string(b)
	}
	n.Password = pw
	n.Name = n.Server
	if params != "" {
		q, err := url.ParseQuery(params)
		if err == nil {
			if v := q.Get("remarks"); v != "" {
				if b, ok := b64Any(v); ok {
					n.Name = string(b)
				} else {
					n.Name = v
				}
			}
			if v := q.Get("protoparam"); v != "" {
				if b, ok := b64Any(v); ok {
					n.SSRProtocolParam = string(b)
				}
			}
			if v := q.Get("obfsparam"); v != "" {
				if b, ok := b64Any(v); ok {
					n.SSRObfsParam = string(b)
				}
			}
		}
	}
	return n, nil
}

func parseHysteria2(link string) (Node, error) {
	n := Node{Type: "hysteria2", TLS: true}
	u, err := url.Parse(link)
	if err != nil {
		return n, fmt.Errorf("hysteria2 链接无法解析: %v", err)
	}
	if u.User != nil {
		n.Password = u.User.Username()
		if pw, ok := u.User.Password(); ok && pw != "" {
			n.Password += ":" + pw
		}
	}
	n.Server = u.Hostname()
	n.Port = atoiSafe(u.Port())
	n.Name = nameFromFragment(u, n.Server)
	q := u.Query()
	n.SNI = q.Get("sni")
	n.Insecure = q.Get("insecure") == "1"
	n.Obfs = q.Get("obfs")
	n.ObfsPass = q.Get("obfs-password")
	if v := q.Get("up"); v != "" {
		n.UpMbps = atoiSafe(strings.TrimSuffix(strings.ToLower(v), "mbps"))
	}
	if v := q.Get("down"); v != "" {
		n.DownMbps = atoiSafe(strings.TrimSuffix(strings.ToLower(v), "mbps"))
	}
	if alpn := q.Get("alpn"); alpn != "" {
		n.ALPN = strings.Split(alpn, ",")
	}
	if n.Server == "" || n.Port == 0 {
		return n, fmt.Errorf("hysteria2 链接缺少服务器或端口")
	}
	return n, nil
}

func parseTUIC(link string) (Node, error) {
	n := Node{Type: "tuic", TLS: true}
	u, err := url.Parse(link)
	if err != nil {
		return n, fmt.Errorf("tuic 链接无法解析: %v", err)
	}
	if u.User != nil {
		n.UUID = u.User.Username()
		if pw, ok := u.User.Password(); ok {
			n.Password = pw
		}
	}
	n.Server = u.Hostname()
	n.Port = atoiSafe(u.Port())
	n.Name = nameFromFragment(u, n.Server)
	q := u.Query()
	n.SNI = q.Get("sni")
	n.Insecure = q.Get("allow_insecure") == "1"
	n.ALPN = strings.Split(q.Get("alpn"), ",")
	if n.Server == "" || n.Port == 0 {
		return n, fmt.Errorf("tuic 链接缺少服务器或端口")
	}
	return n, nil
}

func parseSocksLike(link, typ string) (Node, error) {
	n := Node{Type: typ}
	u, err := url.Parse(link)
	if err != nil {
		return n, fmt.Errorf("%s 链接无法解析: %v", typ, err)
	}
	if u.User != nil {
		n.Username = u.User.Username()
		if pw, ok := u.User.Password(); ok {
			n.Password = pw
		}
	}
	n.Server = u.Hostname()
	n.Port = atoiSafe(u.Port())
	n.Name = nameFromFragment(u, n.Server)
	if n.Server == "" || n.Port == 0 {
		return n, fmt.Errorf("%s 链接缺少服务器或端口", typ)
	}
	return n, nil
}

func splitHostPort(s string) (string, int, error) {
	s = strings.TrimSpace(s)
	i := strings.LastIndex(s, ":")
	if i < 0 {
		return "", 0, fmt.Errorf("缺少端口：%s", s)
	}
	host := strings.Trim(s[:i], "[]")
	port := atoiSafe(s[i+1:])
	if host == "" || port == 0 {
		return "", 0, fmt.Errorf("服务器或端口非法：%s", s)
	}
	return host, port, nil
}

func jstr(m map[string]any, k string) string {
	v, ok := m[k]
	if !ok || v == nil {
		return ""
	}
	switch t := v.(type) {
	case string:
		return t
	case float64:
		return strconv.FormatInt(int64(t), 10)
	case bool:
		if t {
			return "true"
		}
		return "false"
	}
	return ""
}

func jnum(m map[string]any, k string) int {
	v, ok := m[k]
	if !ok || v == nil {
		return 0
	}
	switch t := v.(type) {
	case float64:
		return int(t)
	case string:
		return atoiSafe(t)
	}
	return 0
}

// ParseLinks 批量解析，跳过无法识别的行
func ParseLinks(text string) ([]Node, []string) {
	var nodes []Node
	var errs []string
	seen := map[string]int{}
	ln := 0
	for _, raw := range strings.Split(text, "\n") {
		ln++
		line := strings.TrimSpace(strings.TrimSuffix(raw, "\r"))
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, "//") {
			continue
		}
		n, err := ParseShareLink(line)
		if err != nil {
			errs = append(errs, fmt.Sprintf("第 %d 行: %s", ln, err.Error()))
			continue
		}
		n.Name = uniqueName(seen, n.Name)
		nodes = append(nodes, n)
	}
	return nodes, errs
}
