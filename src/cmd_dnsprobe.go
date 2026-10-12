// ============================================================
//
//	cmd_dnsprobe.go — DNS 上游真实测速
//
//	为什么要自己发 DNS 包：
//	  "这个 DNS 快不快" 只能靠真实查询延迟回答。ping 一个
//	  DNS 服务器只测了 ICMP，跟解析耗时完全是两回事。
//
//	支持三种上游：
//	  · 明文 UDP  223.5.5.5
//	  · DoT       tls://dns.google:853
//	  · DoH       https://1.1.1.1/dns-query   (RFC 8484 wire format)
//
//	用法:
//	  abserver route dnsprobe [-domain www.baidu.com] [-servers a,b,c]
//	                          [-timeout 4] [-json]
//
// ============================================================
package main

import (
	"context"
	"crypto/tls"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"math/rand"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"
)

type dnsProbeResult struct {
	Server  string   `json:"server"`
	Kind    string   `json:"kind"`
	OK      bool     `json:"ok"`
	Millis  int64    `json:"millis"`
	Answers []string `json:"answers,omitempty"`
	Err     string   `json:"error,omitempty"`
}

// defaultProbeServers 覆盖国内三家公共 DNS + 两家境外 + 加密上游
var defaultProbeServers = []string{
	"223.5.5.5",
	"119.29.29.29",
	"180.76.76.76",
	"114.114.114.114",
	"1.1.1.1",
	"8.8.8.8",
	"https://dns.alidns.com/dns-query",
	"https://1.1.1.1/dns-query",
	"tls://dns.google:853",
}

// ---------- DNS 报文 ----------

// buildDNSQuery 手工拼一条 A 记录查询报文（不引入外部 DNS 库）
func buildDNSQuery(id uint16, domain string) []byte {
	domain = strings.TrimSuffix(strings.TrimSpace(domain), ".")
	if domain == "" {
		return nil
	}
	buf := make([]byte, 12, 128)
	binary.BigEndian.PutUint16(buf[0:], id)
	binary.BigEndian.PutUint16(buf[2:], 0x0100) // RD=1
	binary.BigEndian.PutUint16(buf[4:], 1)      // QDCOUNT
	for _, part := range strings.Split(domain, ".") {
		if len(part) == 0 || len(part) > 63 {
			return nil
		}
		buf = append(buf, byte(len(part)))
		buf = append(buf, part...)
	}
	buf = append(buf, 0x00, 0x00, 0x01, 0x00, 0x01) // 根标签 + QTYPE=A + QCLASS=IN
	return buf
}

// skipDNSName 跳过（可能带压缩指针的）域名，返回下一字段偏移
func skipDNSName(msg []byte, off int) int {
	for off < len(msg) {
		l := int(msg[off])
		if l == 0 {
			return off + 1
		}
		if l&0xC0 == 0xC0 {
			return off + 2
		}
		off += 1 + l
	}
	return off
}

// parseDNSAnswers 只抽 A / AAAA 记录，够用了
func parseDNSAnswers(msg []byte) []string {
	if len(msg) < 12 {
		return nil
	}
	qd := int(binary.BigEndian.Uint16(msg[4:6]))
	an := int(binary.BigEndian.Uint16(msg[6:8]))
	off := 12
	for i := 0; i < qd; i++ {
		off = skipDNSName(msg, off)
		off += 4
	}
	out := []string{}
	for i := 0; i < an && off+10 <= len(msg); i++ {
		off = skipDNSName(msg, off)
		if off+10 > len(msg) {
			break
		}
		typ := binary.BigEndian.Uint16(msg[off:])
		rdlen := int(binary.BigEndian.Uint16(msg[off+8:]))
		off += 10
		if off+rdlen > len(msg) {
			break
		}
		switch typ {
		case 1:
			if rdlen == 4 {
				out = append(out, net.IP(msg[off:off+4]).String())
			}
		case 28:
			if rdlen == 16 {
				out = append(out, net.IP(msg[off:off+16]).String())
			}
		}
		off += rdlen
	}
	return out
}

// ---------- 三种上游的探测 ----------

func probeUDP(server string, query []byte, timeout time.Duration) ([]string, error) {
	addr := server
	if _, _, err := net.SplitHostPort(addr); err != nil {
		addr = net.JoinHostPort(server, "53")
	}
	conn, err := net.DialTimeout("udp", addr, timeout)
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(timeout))
	if _, err := conn.Write(query); err != nil {
		return nil, err
	}
	buf := make([]byte, 4096)
	n, err := conn.Read(buf)
	if err != nil {
		return nil, err
	}
	return parseDNSAnswers(buf[:n]), nil
}

func probeDoT(server string, query []byte, timeout time.Duration) ([]string, error) {
	host := strings.TrimPrefix(server, "tls://")
	if _, _, err := net.SplitHostPort(host); err != nil {
		host = net.JoinHostPort(host, "853")
	}
	h, _, _ := net.SplitHostPort(host)
	d := &net.Dialer{Timeout: timeout}
	conn, err := tls.DialWithDialer(d, "tcp", host, &tls.Config{ServerName: h})
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(timeout))
	// DoT 需要在报文前加 2 字节长度前缀
	frame := make([]byte, 2+len(query))
	binary.BigEndian.PutUint16(frame, uint16(len(query)))
	copy(frame[2:], query)
	if _, err := conn.Write(frame); err != nil {
		return nil, err
	}
	lenBuf := make([]byte, 2)
	if _, err := io.ReadFull(conn, lenBuf); err != nil {
		return nil, err
	}
	n := int(binary.BigEndian.Uint16(lenBuf))
	if n <= 0 || n > 4096 {
		return nil, fmt.Errorf("响应长度异常 %d", n)
	}
	body := make([]byte, n)
	if _, err := io.ReadFull(conn, body); err != nil {
		return nil, err
	}
	return parseDNSAnswers(body), nil
}

func probeDoH(server string, query []byte, timeout time.Duration) ([]string, error) {
	u, err := url.Parse(server)
	if err != nil {
		return nil, err
	}
	qs := u.Query()
	qs.Set("dns", base64.RawURLEncoding.EncodeToString(query))
	u.RawQuery = qs.Encode()
	cli := &http.Client{Timeout: timeout}
	req, err := http.NewRequest("GET", u.String(), nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/dns-message")
	req.Header.Set("User-Agent", "SY-AdGH/dnsprobe")
	resp, err := cli.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 8192))
	return parseDNSAnswers(body), nil
}

// probeOne 自动按前缀选协议
func probeOne(server, domain string, timeout time.Duration) dnsProbeResult {
	r := dnsProbeResult{Server: server}
	switch {
	case strings.HasPrefix(server, "https://"), strings.HasPrefix(server, "http://"):
		r.Kind = "doh"
	case strings.HasPrefix(server, "tls://"):
		r.Kind = "dot"
	default:
		r.Kind = "udp"
	}
	query := buildDNSQuery(uint16(rand.Intn(65535)), domain)
	if query == nil {
		r.Err = "域名不合法"
		return r
	}
	t0 := time.Now()
	var ans []string
	var err error
	switch r.Kind {
	case "doh":
		ans, err = probeDoH(server, query, timeout)
	case "dot":
		ans, err = probeDoT(server, query, timeout)
	default:
		ans, err = probeUDP(server, query, timeout)
	}
	ms := time.Since(t0).Milliseconds()
	r.Millis = ms
	if err != nil {
		r.Err = err.Error()
		return r
	}
	r.OK = true
	r.Answers = ans
	return r
}

func cmdDNSProbe(args []string) {
	fs := flag.NewFlagSet("route dnsprobe", flag.ExitOnError)
	domain := fs.String("domain", "www.baidu.com", "测试域名")
	servers := fs.String("servers", "", "逗号分隔的服务器列表；留空用内置清单")
	timeout := fs.Int("timeout", 4, "单个查询超时秒数")
	asJSON := fs.Bool("json", false, "以 JSON 输出")
	fs.Parse(args)

	list := defaultProbeServers
	if strings.TrimSpace(*servers) != "" {
		list = nil
		for _, s := range strings.Split(*servers, ",") {
			if s = strings.TrimSpace(s); s != "" {
				list = append(list, s)
			}
		}
	}
	if len(list) == 0 {
		fmt.Fprintln(os.Stderr, "ERR: 服务器列表为空")
		os.Exit(2)
	}
	to := time.Duration(*timeout) * time.Second

	results := make([]dnsProbeResult, len(list))
	var wg sync.WaitGroup
	for i, s := range list {
		wg.Add(1)
		go func(i int, s string) {
			defer wg.Done()
			results[i] = probeOne(s, *domain, to)
		}(i, s)
	}
	wg.Wait()

	if *asJSON {
		b, _ := json.MarshalIndent(map[string]any{
			"domain": *domain, "results": results,
		}, "", "  ")
		fmt.Println(string(b))
		return
	}
	fmt.Printf("DNS 上游测速  域名=%s  超时=%ds\n\n", *domain, *timeout)
	fmt.Printf("%-34s %-5s %-9s %s\n", "服务器", "协议", "耗时", "结果")
	fmt.Println(strings.Repeat("-", 78))
	for _, r := range results {
		st := "ok"
		detail := strings.Join(r.Answers, ", ")
		if !r.OK {
			st = "FAIL"
			detail = r.Err
		}
		ms := fmt.Sprintf("%d ms", r.Millis)
		if !r.OK {
			ms = "-"
		}
		if len(detail) > 34 {
			detail = detail[:33] + "…"
		}
		fmt.Printf("%-34s %-5s %-9s %s %s\n", r.Server, r.Kind, ms, st, detail)
	}
	_ = context.Background
}
