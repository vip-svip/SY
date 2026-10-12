// ============================================================
//
//	proxy.go — MITM 透明代理引擎 (第二层)
//	功能: 动态签发证书、HTTPS 解密、内容级广告字段删除、
//	      空图替换、广告JS屏蔽、按应用/域名生效范围、统计输出
//
// ============================================================
package main

import (
	"bufio"
	"bytes"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"flag"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// 1x1 透明 GIF
var blankGIF = []byte{
	0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00,
	0x00, 0xff, 0xff, 0xff, 0x00, 0x00, 0x00, 0x21, 0xf9, 0x04, 0x01, 0x00,
	0x00, 0x00, 0x00, 0x2c, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
	0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3b,
}

// 广告域名/路径关键词 (用于资源级判定)
var adURLRe = regexp.MustCompile(`(?i)(/ad[/_.?&=-]|/ads[/_.?&=-]|/advert|/banner|adserver|doubleclick|/splash|ad_?pic|/promotion|/gdt|/adx|/openads|/api/ad|reportAd|advertise)`)
var adJSRe = regexp.MustCompile(`(?i)(adsbygoogle|pagead|googlesyndication|umeng.*ad|tencent.*gdt|adn\.|/ad\.js|/ads\.js)`)
var imgExtRe = regexp.MustCompile(`(?i)\.(png|jpe?g|gif|webp|bmp)(\?|$)`)
var adJSONKeyRe = regexp.MustCompile(`(?i)"(ad|ads|adinfo|ad_info|advert|advertisement|adlist|ad_list|ad_data|banner|promotion|promotions|adconfig|ad_config|splash_ad|launch_ad|feed_ad|native_ad)"\s*:`)

type proxyStats struct {
	Requests   int64 `json:"requests"`
	Https      int64 `json:"https_decrypted"`
	Blocked    int64 `json:"blocked"`
	BlankImg   int64 `json:"blank_images"`
	AdJS       int64 `json:"blocked_js"`
	FieldsTrim int64 `json:"fields_trimmed"`
}

type caManager struct {
	key     *rsa.PrivateKey
	caCert  *x509.Certificate
	cache   map[string]*tls.Certificate
	mu      sync.Mutex
	leafKey *rsa.PrivateKey
}

func loadCA(keyPath, crtPath string) (*caManager, error) {
	kb, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, err
	}
	block, _ := pem.Decode(kb)
	if block == nil {
		return nil, fmt.Errorf("bad key pem")
	}
	var key *rsa.PrivateKey
	if k, e := x509.ParsePKCS1PrivateKey(block.Bytes); e == nil {
		key = k
	} else if k2, e := x509.ParsePKCS8PrivateKey(block.Bytes); e == nil {
		if rk, ok := k2.(*rsa.PrivateKey); ok {
			key = rk
		}
	}
	if key == nil {
		return nil, fmt.Errorf("unsupported key")
	}
	cb, err := os.ReadFile(crtPath)
	if err != nil {
		return nil, err
	}
	cblock, _ := pem.Decode(cb)
	if cblock == nil {
		return nil, fmt.Errorf("bad cert pem")
	}
	caCert, err := x509.ParseCertificate(cblock.Bytes)
	if err != nil {
		return nil, err
	}
	leafKey, _ := rsa.GenerateKey(randReader(), 2048)
	return &caManager{key: key, caCert: caCert, cache: map[string]*tls.Certificate{}, leafKey: leafKey}, nil
}

func (m *caManager) certFor(host string) (*tls.Certificate, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if c, ok := m.cache[host]; ok {
		return c, nil
	}
	serial, _ := randInt()
	tmpl := &x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: host},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().AddDate(1, 0, 0),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	if ip := net.ParseIP(host); ip != nil {
		tmpl.IPAddresses = []net.IP{ip}
	} else {
		tmpl.DNSNames = []string{host}
	}
	der, err := x509.CreateCertificate(randReader(), tmpl, m.caCert, &m.leafKey.PublicKey, m.key)
	if err != nil {
		return nil, err
	}
	cert := &tls.Certificate{
		Certificate: [][]byte{der, m.caCert.Raw},
		PrivateKey:  m.leafKey,
	}
	m.cache[host] = cert
	return cert, nil
}

func cmdProxy(args []string) {
	fs := flag.NewFlagSet("proxy", flag.ExitOnError)
	httpAddr := fs.String("http", ":8080", "HTTP 透明口")
	httpsAddr := fs.String("https", ":8443", "HTTPS 透明口")
	caKey := fs.String("ca-key", "", "CA 私钥")
	caCrt := fs.String("ca-crt", "", "CA 证书")
	rules := fs.String("rules", "", "规则文件")
	apps := fs.String("apps", "", "生效应用(逗号分隔)")
	whitelist := fs.String("whitelist", "", "白名单文件")
	statsPath := fs.String("stats", "", "统计输出")
	fs.Parse(args)

	cm, err := loadCA(*caKey, *caCrt)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR: 加载CA失败:", err)
		os.Exit(1)
	}

	var st proxyStats
	var wl []string
	if *whitelist != "" {
		if b, e := os.ReadFile(*whitelist); e == nil {
			for _, ln := range strings.Split(string(b), "\n") {
				ln = strings.TrimSpace(ln)
				if ln != "" && !strings.HasPrefix(ln, "#") {
					wl = append(wl, ln)
				}
			}
		}
	}
	rs := loadRules(*rules)
	fmt.Printf("MITM rules loaded: domain=%d url=%d regex=%d\n", len(rs.blockDomain), len(rs.blockURL), len(rs.blockRe))
	// 生效应用(由 iptables 层按 UID 精确分流；此处记录以便日志与统计)
	if strings.TrimSpace(*apps) != "" {
		fmt.Println("MITM scoped apps:", *apps)
	}

	// 统计落盘
	if *statsPath != "" {
		go func() {
			for {
				time.Sleep(3 * time.Second)
				b, _ := json.Marshal(&st)
				os.WriteFile(*statsPath, b, 0644)
			}
		}()
	}

	handler := &mitmHandler{ca: cm, wl: wl, rules: rs, st: &st}
	// HTTP 透明
	go func() {
		srv := &http.Server{Addr: *httpAddr, Handler: handler}
		fmt.Println("MITM HTTP listen", *httpAddr)
		srv.ListenAndServe()
	}()
	// HTTPS 透明 (SNI 动态证书)
	l, err := net.Listen("tcp", *httpsAddr)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR: 监听失败:", err)
		os.Exit(1)
	}
	fmt.Println("MITM HTTPS listen", *httpsAddr)
	for {
		conn, err := l.Accept()
		if err != nil {
			continue
		}
		go handleTLS(conn, cm, handler)
	}
}

func handleTLS(conn net.Conn, cm *caManager, h *mitmHandler) {
	defer conn.Close()
	host := ""
	// 先 peek ClientHello 拿 SNI
	br := bufio.NewReader(conn)
	conn2 := &bufferedConn{Conn: conn, r: br}
	cfg := &tls.Config{
		GetCertificate: func(chi *tls.ClientHelloInfo) (*tls.Certificate, error) {
			host = chi.ServerName
			return cm.certFor(chi.ServerName)
		},
	}
	tlsConn := tls.Server(conn2, cfg)
	if err := tlsConn.Handshake(); err != nil {
		return
	}
	atomic.AddInt64(&h.st.Https, 1)
	// 将 TLS 连接接入 HTTP 服务
	srv := &http.Server{Handler: h}
	// 用一次性 listener 提供该连接
	ol := &oneShotListener{conn: tlsConn}
	// 目标地址写入请求 Host 由 handler 读取
	h.setAddr(tlsConn.RemoteAddr())
	srv.Serve(ol)
	_ = host
}

// 单连接 listener
type oneShotListener struct {
	conn net.Conn
	done bool
}

func (o *oneShotListener) Accept() (net.Conn, error) {
	if o.done {
		select {}
	}
	o.done = true
	return o.conn, nil
}
func (o *oneShotListener) Close() error   { return nil }
func (o *oneShotListener) Addr() net.Addr { return o.conn.LocalAddr() }

type bufferedConn struct {
	net.Conn
	r *bufio.Reader
}

func (b *bufferedConn) Read(p []byte) (int, error) { return b.r.Read(p) }

type ruleSet struct {
	blockDomain []string         // 域名后缀
	blockURL    []string         // URL 子串
	blockRe     []*regexp.Regexp // 正则
}

func (rs *ruleSet) match(host, url string) bool {
	h := strings.ToLower(stripPort(host))
	u := strings.ToLower(url)
	for _, d := range rs.blockDomain {
		if h == d || strings.HasSuffix(h, "."+d) {
			return true
		}
	}
	for _, s := range rs.blockURL {
		if s != "" && strings.Contains(u, s) {
			return true
		}
	}
	for _, re := range rs.blockRe {
		if re.MatchString(url) || re.MatchString(host) {
			return true
		}
	}
	return false
}

// loadRules 解析规则文本：支持  域名 /  ||域名^ /  子串 /  regex:正则  四种写法
func loadRules(path string) *ruleSet {
	rs := &ruleSet{}
	b, err := os.ReadFile(path)
	if err != nil {
		return rs
	}
	for _, ln := range strings.Split(string(b), "\n") {
		ln = strings.TrimSpace(ln)
		if ln == "" || strings.HasPrefix(ln, "#") || strings.HasPrefix(ln, "//") {
			continue
		}
		if strings.HasPrefix(ln, "regex:") {
			if re, e := regexp.Compile(strings.TrimSpace(ln[6:])); e == nil {
				rs.blockRe = append(rs.blockRe, re)
			}
			continue
		}
		// SY 语法 ||domain^
		if strings.HasPrefix(ln, "||") {
			d := strings.TrimSuffix(strings.TrimPrefix(ln, "||"), "^")
			d = strings.TrimSuffix(d, "^")
			if i := strings.IndexAny(d, "^/"); i > 0 {
				d = d[:i]
			}
			d = strings.ToLower(strings.TrimSpace(d))
			if d != "" {
				rs.blockDomain = append(rs.blockDomain, d)
			}
			continue
		}
		low := strings.ToLower(ln)
		if !strings.ContainsAny(low, "/?") {
			rs.blockDomain = append(rs.blockDomain, strings.TrimSuffix(low, "."))
		} else {
			rs.blockURL = append(rs.blockURL, low)
		}
	}
	// 去重
	seen := map[string]bool{}
	dd := rs.blockDomain[:0]
	for _, d := range rs.blockDomain {
		if !seen[d] {
			seen[d] = true
			dd = append(dd, d)
		}
	}
	rs.blockDomain = dd
	return rs
}

type mitmHandler struct {
	ca     *caManager
	wl     []string
	rules  *ruleSet
	st     *proxyStats
	lastAd net.Addr
	mu     sync.Mutex
}

func (h *mitmHandler) setAddr(a net.Addr) {
	h.mu.Lock()
	h.lastAd = a
	h.mu.Unlock()
}

func (h *mitmHandler) isWhitelisted(host string) bool {
	for _, w := range h.wl {
		if host == w || strings.HasSuffix(host, "."+w) {
			return true
		}
	}
	return false
}

func (h *mitmHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	atomic.AddInt64(&h.st.Requests, 1)
	host := r.Host
	url := r.URL.String()
	if h.isWhitelisted(stripPort(host)) {
		h.forward(w, r)
		return
	}

	// 用户内容替换规则匹配 → 拦截(返回空)
	if h.rules != nil && h.rules.match(host, url) {
		atomic.AddInt64(&h.st.Blocked, 1)
		if imgExtRe.MatchString(url) {
			atomic.AddInt64(&h.st.BlankImg, 1)
			w.Header().Set("Content-Type", "image/gif")
			w.Write(blankGIF)
			return
		}
		w.Header().Set("Content-Type", "text/plain")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("/* blocked by SY */"))
		return
	}

	// 广告 JS 屏蔽
	if adJSRe.MatchString(url) {
		atomic.AddInt64(&h.st.Blocked, 1)
		atomic.AddInt64(&h.st.AdJS, 1)
		w.Header().Set("Content-Type", "application/javascript")
		w.Write([]byte("/* blocked by SY */"))
		return
	}

	// 直接返回空图(广告图片资源预加载拦截)
	if imgExtRe.MatchString(url) && adURLRe.MatchString(url) {
		atomic.AddInt64(&h.st.Blocked, 1)
		atomic.AddInt64(&h.st.BlankImg, 1)
		w.Header().Set("Content-Type", "image/gif")
		w.Write(blankGIF)
		return
	}

	resp := h.fetch(r)
	if resp == nil {
		http.Error(w, "upstream error", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	ct := resp.Header.Get("Content-Type")

	// JSON 广告字段删除
	if strings.Contains(ct, "json") || adJSONKeyRe.Match(body) {
		nb, trimmed := trimAdJSON(body)
		if trimmed > 0 {
			atomic.AddInt64(&h.st.Blocked, 1)
			atomic.AddInt64(&h.st.FieldsTrim, int64(trimmed))
			body = nb
		}
	}
	for k, vv := range resp.Header {
		for _, v := range vv {
			w.Header().Add(k, v)
		}
	}
	w.WriteHeader(resp.StatusCode)
	w.Write(body)
}

func (h *mitmHandler) forward(w http.ResponseWriter, r *http.Request) {
	resp := h.fetch(r)
	if resp == nil {
		http.Error(w, "upstream error", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()
	for k, vv := range resp.Header {
		for _, v := range vv {
			w.Header().Add(k, v)
		}
	}
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

func (h *mitmHandler) fetch(r *http.Request) *http.Response {
	u := r.URL
	target := u.String()
	if !u.IsAbs() {
		sch := "http"
		if r.TLS != nil {
			sch = "https"
		}
		target = sch + "://" + r.Host + u.RequestURI()
	}
	req, err := http.NewRequest(r.Method, target, r.Body)
	if err != nil {
		return nil
	}
	for k, vv := range r.Header {
		for _, v := range vv {
			req.Header.Add(k, v)
		}
	}
	req.Header.Del("Accept-Encoding") // 便于处理明文
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil
	}
	return resp
}

func trimAdJSON(body []byte) ([]byte, int) {
	var data interface{}
	if err := json.Unmarshal(body, &data); err != nil {
		return body, 0
	}
	removed := 0
	remove := func(obj map[string]interface{}) {
		for k := range obj {
			lk := strings.ToLower(k)
			if lk == "ad" || lk == "ads" || lk == "adinfo" || lk == "ad_info" ||
				lk == "advert" || lk == "advertisement" || lk == "banner" ||
				lk == "promotion" || lk == "promotions" || lk == "adconfig" ||
				lk == "splash_ad" || lk == "launch_ad" || lk == "feed_ad" ||
				lk == "native_ad" || strings.HasPrefix(lk, "ad_") {
				delete(obj, k)
				removed++
			}
		}
	}
	var walk func(v interface{})
	walk = func(v interface{}) {
		switch t := v.(type) {
		case map[string]interface{}:
			remove(t)
			for _, vv := range t {
				walk(vv)
			}
		case []interface{}:
			for _, vv := range t {
				walk(vv)
			}
		}
	}
	walk(data)
	if removed == 0 {
		return body, 0
	}
	nb, err := json.Marshal(data)
	if err != nil {
		return body, 0
	}
	return nb, removed
}

func stripPort(host string) string {
	if i := strings.LastIndex(host, ":"); i >= 0 {
		return host[:i]
	}
	return host
}

var _ = bytes.NewBuffer
var _ = big.NewInt
var _ = filepath.Join
