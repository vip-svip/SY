// ============================================================
//
//	geoip — 本地 IP 归属 / 注册 / 云厂商 查询（离线，无外网请求）
//
//	用途：隐私防泄露的「真实出口核对」。把当前出口公网 IP 与代理节点
//	出口 IP 做多源归属对比，若不一致，说明存在真实 IP 泄露或分流旁路。
//	全部查询走本地数据（.mmdb / RIR 授权库 / IP2Location / 云厂商网段），
//	不产生任何外部请求，天然不泄露查询行为。
//
//	数据源（均随模块离线打包）：
//	  · DB-IP Lite country/asn/city (.mmdb)   —— 主归属
//	  · RIR delegated 授权库 (ripencc/apnic/arin/lacnic/afrinic .txt) —— 注册局与分配日期
//	  · IP2Location LITE DB1 (.csv)           —— 交叉校验国家
//	  · AWS ip-ranges (.json)                 —— 识别云 / CDN 出口
//
//	用法:
//	  abserver geoip -db DIR -ip IP[,IP...] [-json]
//	  abserver geoip -db DIR -file ips.txt [-json]
//	  abserver geoip -db DIR -compare A,B [-json]     对比两个出口归属，判定泄露
//	  abserver geoip -db DIR -owner IP                查 RIR 注册局 / 分配日期
//	  abserver geoip -db DIR -cloud IP                查是否为 AWS 云出口
//	  abserver geoip -db DIR -xdb IP                  IP2Location 交叉国家
//
//	注意：仅做归属地/注册判读，不构成任何投资/法律建议。
// ============================================================
package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"

	"github.com/oschwald/maxminddb-golang"
)

type geoResult struct {
	IP        string `json:"ip"`
	Country   string `json:"country,omitempty"`
	CountryEn string `json:"country_en,omitempty"`
	City      string `json:"city,omitempty"`
	ASN       uint32 `json:"asn,omitempty"`
	ASOrg     string `json:"as_org,omitempty"`
	DB        string `json:"db,omitempty"`
	Error     string `json:"error,omitempty"`
}

type countryRec struct {
	Country struct {
		ISOCode string `maxminddb:"iso_code"`
		Names   struct {
			En string `maxminddb:"en"`
		} `maxminddb:"names"`
	} `maxminddb:"country"`
}

type asnRec struct {
	ASN uint32 `maxminddb:"autonomous_system_number"`
	Org string `maxminddb:"autonomous_system_organization"`
}

type cityRec struct {
	City struct {
		Names struct {
			En string `maxminddb:"en"`
		} `maxminddb:"names"`
	} `maxminddb:"city"`
}

var (
	dbCacheMu sync.Mutex
	dbCache   = map[string]*maxminddb.Reader{}
)

func openMMDB(path string) (*maxminddb.Reader, error) {
	dbCacheMu.Lock()
	defer dbCacheMu.Unlock()
	if r, ok := dbCache[path]; ok {
		return r, nil
	}
	r, err := maxminddb.Open(path)
	if err != nil {
		return nil, err
	}
	dbCache[path] = r
	return r, nil
}

func findDB(dir string, names ...string) string {
	for _, n := range names {
		p := filepath.Join(dir, n)
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	for _, n := range names {
		base := strings.TrimSuffix(n, ".mmdb")
		prefix := base
		if i := strings.LastIndex(base, "-lite"); i >= 0 {
			prefix = base[:i+5]
		}
		matches, _ := filepath.Glob(filepath.Join(dir, prefix+"*.mmdb"))
		if len(matches) > 0 {
			return matches[0]
		}
	}
	return ""
}

func lookupGeo(dir, ip string) geoResult {
	res := geoResult{IP: ip}
	parsed := net.ParseIP(ip)
	if parsed == nil {
		res.Error = "invalid ip"
		return res
	}
	if c := findDB(dir, "dbip-country-lite.mmdb", "dbip-country-lite-ipv6.mmdb"); c != "" {
		if r, err := openMMDB(c); err == nil {
			var rec countryRec
			if err := r.Lookup(parsed, &rec); err == nil {
				res.Country = rec.Country.ISOCode
				res.CountryEn = rec.Country.Names.En
				res.DB = filepath.Base(c)
			}
		}
	}
	if c := findDB(dir, "dbip-city-lite.mmdb", "dbip-city-lite-ipv6.mmdb"); c != "" {
		if r, err := openMMDB(c); err == nil {
			var rec cityRec
			if err := r.Lookup(parsed, &rec); err == nil {
				res.City = rec.City.Names.En
			}
		}
	}
	if a := findDB(dir, "dbip-asn-lite.mmdb", "dbip-asn-lite-ipv6.mmdb"); a != "" {
		if r, err := openMMDB(a); err == nil {
			var rec asnRec
			if err := r.Lookup(parsed, &rec); err == nil {
				res.ASN = rec.ASN
				res.ASOrg = rec.Org
			}
		}
	}
	if res.Country == "" && res.ASN == 0 && res.City == "" {
		res.Error = "not in database"
	}
	return res
}

// ---------------- RIR 注册局查询 ----------------
type rirHit struct {
	Registry  string `json:"registry"`
	CC        string `json:"cc"`
	Type      string `json:"type"`
	Start     string `json:"start"`
	Value     string `json:"value"`
	Date      string `json:"date"`
	Status    string `json:"status"`
	OpaqueID  string `json:"opaque_id"`
}

// lookupRIR 扫描 delegated-*-extended-latest 文本，找到包含该 IP 的最小网段记录。
// 格式: registry|cc|type|start|value|date|status|...
func lookupRIR(dir, ipStr string) *rirHit {
	parsed := net.ParseIP(ipStr)
	if parsed == nil {
		return nil
	}
	v4 := parsed.To4()
	var best *rirHit
	var bestSize uint64 = 1<<64 - 1
	rirDir := filepath.Join(dir, "rir")
	files, _ := filepath.Glob(filepath.Join(rirDir, "*.txt"))
	for _, f := range files {
		fh, err := os.Open(f)
		if err != nil {
			continue
		}
		sc := bufio.NewScanner(fh)
		sc.Buffer(make([]byte, 1024*1024), 1024*1024)
		for sc.Scan() {
			line := sc.Text()
			if len(line) == 0 || line[0] == '#' {
				continue
			}
			if strings.HasPrefix(line, "2|") || strings.HasPrefix(line, "version|") {
				continue
			}
			parts := strings.Split(line, "|")
			if len(parts) < 7 {
				continue
			}
			typ := parts[2]
			start := parts[3]
			val := parts[4]
			// IPv4 只在 type==ipv4 时比较；asn 记录跳过
			if typ != "ipv4" {
				continue
			}
			base := net.ParseIP(start)
			if base == nil {
				continue
			}
			b4 := base.To4()
			if b4 == nil || v4 == nil {
				continue
			}
			count, err := strconv.ParseUint(val, 10, 64)
			if err != nil || count == 0 {
				continue
			}
			startInt := ip4ToUint(b4)
			endInt := startInt + count - 1
			cur := ip4ToUint(v4)
			if cur >= startInt && cur <= endInt {
				if count < bestSize {
					bestSize = count
					best = &rirHit{
						Registry: parts[0], CC: parts[1], Type: typ,
						Start: start, Value: val, Date: parts[5], Status: parts[6],
					}
					if len(parts) > 7 {
						best.OpaqueID = parts[7]
					}
				}
			}
		}
		fh.Close()
	}
	return best
}

func ip4ToUint(b []byte) uint64 {
	return uint64(b[0])<<24 | uint64(b[1])<<16 | uint64(b[2])<<8 | uint64(b[3])
}

// ---------------- AWS 云网段 ----------------
type awsPrefix struct {
	IPPrefix string `json:"ip_prefix"`
	Region   string `json:"region"`
	Service  string `json:"service"`
}
type awsDoc struct {
	Prefixes []awsPrefix `json:"prefixes"`
}

// ---------------- 云 / CDN 网段（AWS + GCP + Cloudflare） ----------------
type cloudHit struct {
	Provider string `json:"provider"`
	Region   string `json:"region,omitempty"`
	Service  string `json:"service,omitempty"`
	Prefix   string `json:"prefix"`
}

type gcpPrefix struct {
	IPv4Prefix string `json:"ipv4Prefix"`
	IPv6Prefix string `json:"ipv6Prefix"`
	Service    string `json:"service"`
	Scope      string `json:"scope"`
}
type gcpDoc struct {
	Prefixes []gcpPrefix `json:"prefixes"`
}

func cidrContains(ipStr, cidr string) bool {
	parsed := net.ParseIP(ipStr)
	if parsed == nil || cidr == "" {
		return false
	}
	_, ipnet, err := net.ParseCIDR(cidr)
	if err != nil {
		return false
	}
	return ipnet.Contains(parsed)
}

// lookupCloud 依次查 AWS / GCP / Cloudflare 网段，返回命中的云出口描述。
func lookupCloud(dir, ipStr string) *cloudHit {
	if b, err := os.ReadFile(filepath.Join(dir, "cloud", "aws-ip-ranges.json")); err == nil {
		var doc awsDoc
		if json.Unmarshal(b, &doc) == nil {
			for i := range doc.Prefixes {
				if cidrContains(ipStr, doc.Prefixes[i].IPPrefix) {
					return &cloudHit{Provider: "AWS", Region: doc.Prefixes[i].Region,
						Service: doc.Prefixes[i].Service, Prefix: doc.Prefixes[i].IPPrefix}
				}
			}
		}
	}
	for _, name := range []string{"gcloud.txt", "goog.txt"} {
		if b, err := os.ReadFile(filepath.Join(dir, "cloud", name)); err == nil {
			var doc gcpDoc
			if json.Unmarshal(b, &doc) == nil {
				for i := range doc.Prefixes {
					cidr := doc.Prefixes[i].IPv4Prefix
					if cidr == "" {
						cidr = doc.Prefixes[i].IPv6Prefix
					}
					if cidrContains(ipStr, cidr) {
						svc := doc.Prefixes[i].Service
						if svc == "" {
							svc = "google"
						}
						return &cloudHit{Provider: "GCP", Region: doc.Prefixes[i].Scope,
							Service: svc, Prefix: cidr}
					}
				}
			}
		}
	}
	for _, name := range []string{"cloudflare-v4.txt", "cloudflare-v6.txt"} {
		if b, err := os.ReadFile(filepath.Join(dir, "cloud", name)); err == nil {
			for _, line := range strings.Split(string(b), "\n") {
				cidr := strings.TrimSpace(line)
				if cidr != "" && cidrContains(ipStr, cidr) {
					return &cloudHit{Provider: "Cloudflare", Prefix: cidr}
				}
			}
		}
	}
	return nil
}

func lookupAWS(dir, ipStr string) *awsPrefix {
	parsed := net.ParseIP(ipStr)
	v4 := parsed.To4()
	if v4 == nil {
		return nil
	}
	path := filepath.Join(dir, "cloud", "aws-ip-ranges.json")
	b, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var doc awsDoc
	if json.Unmarshal(b, &doc) != nil {
		return nil
	}
	cur := ip4ToUint(v4)
	for i := range doc.Prefixes {
		_, ipnet, err := net.ParseCIDR(doc.Prefixes[i].IPPrefix)
		if err != nil {
			continue
		}
		ip4 := ipnet.IP.To4()
		if ip4 == nil {
			continue
		}
		start := ip4ToUint(ip4)
		mask, _ := ipnet.Mask.Size()
		size := uint64(1) << uint(32-mask)
		if cur >= start && cur < start+size {
			return &doc.Prefixes[i]
		}
	}
	return nil
}

// ---------------- IP2Location 交叉国家 ----------------
type ipRange struct {
	start uint32
	end   uint32
	cc    string
}

var (
	xdbOnce sync.Once
	xdbList []ipRange
)

func loadXDB(dir string) {
	path := filepath.Join(dir, "ip2location-lite-db1.csv")
	f, err := os.Open(path)
	if err != nil {
		return
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1024*1024), 1024*1024)
	first := true
	for sc.Scan() {
		line := sc.Text()
		if first { // 头行 "start_ip_int,end_ip_int,country_code,country_name"
			first = false
			if strings.Contains(line, "start") {
				continue
			}
		}
		parts := strings.Split(line, ",")
		if len(parts) < 3 {
			continue
		}
		s, e := parseU32(parts[0]), parseU32(parts[1])
		if s == 0 && e == 0 {
			continue
		}
		xdbList = append(xdbList, ipRange{start: s, end: e, cc: parts[2]})
	}
	sort.Slice(xdbList, func(i, j int) bool { return xdbList[i].start < xdbList[j].start })
}

func parseU32(s string) uint32 {
	s = strings.TrimSpace(strings.Trim(s, "\""))
	v, err := strconv.ParseUint(s, 10, 32)
	if err != nil {
		return 0
	}
	return uint32(v)
}

func lookupXDB(dir, ipStr string) string {
	xdbOnce.Do(func() { loadXDB(dir) })
	parsed := net.ParseIP(ipStr)
	v4 := parsed.To4()
	if v4 == nil {
		return ""
	}
	cur := uint32(ip4ToUint(v4))
	i := sort.Search(len(xdbList), func(i int) bool { return xdbList[i].end >= cur })
	if i < len(xdbList) && xdbList[i].start <= cur && cur <= xdbList[i].end {
		return xdbList[i].cc
	}
	return ""
}

func cmdGeoip(args []string) {
	fs := flag.NewFlagSet("geoip", flag.ExitOnError)
	dir := fs.String("db", "", "数据目录 (data/geo)")
	ipArg := fs.String("ip", "", "要查询的 IP，可逗号分隔")
	fileArg := fs.String("file", "", "从文件读取 IP（每行一个）")
	compare := fs.String("compare", "", "对比两个 IP 的出口归属 A,B（检测泄露/旁路）")
	owner := fs.String("owner", "", "查 RIR 注册局 / 分配日期")
	cloud := fs.String("cloud", "", "查是否为 AWS 云出口")
	xdb := fs.String("xdb", "", "IP2Location 交叉国家")
	asJSON := fs.Bool("json", false, "输出 JSON")
	fs.Parse(args)

	if *dir == "" {
		*dir = "data/geo"
	}
	if _, err := os.Stat(*dir); err != nil {
		fmt.Fprintf(os.Stderr, "ERR: 数据目录不存在: %s\n", *dir)
		os.Exit(2)
	}

	if *owner != "" {
		h := lookupRIR(*dir, strings.TrimSpace(*owner))
		if *asJSON {
			b, _ := json.Marshal(h)
			fmt.Println(string(b))
			return
		}
		if h == nil {
			fmt.Printf("%s  未在本地 RIR 授权库命中（仅含网段起始记录）\n", *owner)
			return
		}
		fmt.Printf("%s  registry=%s  cc=%s  %s/%s  alloc=%s  status=%s\n",
			*owner, h.Registry, h.CC, h.Start, h.Value, h.Date, h.Status)
		return
	}
	if *cloud != "" {
		h := lookupCloud(*dir, strings.TrimSpace(*cloud))
		if *asJSON {
			b, _ := json.Marshal(h)
			fmt.Println(string(b))
			return
		}
		if h == nil {
			fmt.Printf("%s  未命中 AWS/GCP/Cloudflare 网段\n", *cloud)
			return
		}
		fmt.Printf("%s  cloud=%s region=%s service=%s prefix=%s\n", *cloud, h.Provider, h.Region, h.Service, h.Prefix)
		return
	}
	if *xdb != "" {
		cc := lookupXDB(*dir, strings.TrimSpace(*xdb))
		if *asJSON {
			b, _ := json.Marshal(map[string]string{"ip": *xdb, "country": cc})
			fmt.Println(string(b))
			return
		}
		if cc == "" {
			fmt.Printf("%s  IP2Location 未命中\n", *xdb)
			return
		}
		fmt.Printf("%s  IP2Location country=%s\n", *xdb, cc)
		return
	}

	var ips []string
	if *ipArg != "" {
		for _, s := range strings.Split(*ipArg, ",") {
			if s = strings.TrimSpace(s); s != "" {
				ips = append(ips, s)
			}
		}
	}
	if *fileArg != "" {
		f, err := os.Open(*fileArg)
		if err != nil {
			fmt.Fprintln(os.Stderr, "ERR:", err)
			os.Exit(1)
		}
		sc := bufio.NewScanner(f)
		for sc.Scan() {
			if s := strings.TrimSpace(sc.Text()); s != "" && !strings.HasPrefix(s, "#") {
				ips = append(ips, s)
			}
		}
		f.Close()
	}
	if *compare != "" {
		parts := strings.Split(*compare, ",")
		if len(parts) != 2 {
			fmt.Fprintln(os.Stderr, "ERR: -compare 需要 A,B 两个 IP")
			os.Exit(2)
		}
		a := lookupGeo(*dir, strings.TrimSpace(parts[0]))
		b := lookupGeo(*dir, strings.TrimSpace(parts[1]))
		leak := judgeLeak(a, b)
		if *asJSON {
			out, _ := json.MarshalIndent(map[string]interface{}{"egress": a, "node": b, "leak": leak}, "", "  ")
			fmt.Println(string(out))
			return
		}
		fmt.Printf("真实出口 : %s  %s %s  AS%d %s\n", a.IP, a.Country, a.City, a.ASN, a.ASOrg)
		fmt.Printf("代理节点 : %s  %s %s  AS%d %s\n", b.IP, b.Country, b.City, b.ASN, b.ASOrg)
		if leak {
			fmt.Println("判定: ⚠ 出口与节点归属不一致，存在真实 IP 泄露 / 分流旁路风险")
			os.Exit(3)
		}
		fmt.Println("判定: 出口与节点归属一致，未见明显旁路")
		return
	}

	if len(ips) == 0 {
		fmt.Fprintln(os.Stderr, "usage: abserver geoip -db DIR {-ip IP | -file F | -compare A,B | -owner IP | -cloud IP | -xdb IP} [-json]")
		os.Exit(2)
	}
	results := make([]geoResult, 0, len(ips))
	for _, ip := range ips {
		r := lookupGeo(*dir, ip)
		if cc := lookupXDB(*dir, ip); cc != "" && r.Country == "" {
			r.Country = cc
			r.DB = "ip2location"
		}
		results = append(results, r)
	}
	if *asJSON {
		out, _ := json.MarshalIndent(results, "", "  ")
		fmt.Println(string(out))
		return
	}
	for _, r := range results {
		if r.Error != "" {
			fmt.Printf("%-40s  %s\n", r.IP, r.Error)
			continue
		}
		fmt.Printf("%-40s  %-3s %-18s AS%-8d %s\n", r.IP, r.Country, r.City, r.ASN, r.ASOrg)
	}
}

func judgeLeak(a, b geoResult) bool {
	if a.Error != "" || b.Error != "" {
		return false
	}
	if a.Country != "" && b.Country != "" && a.Country != b.Country {
		return true
	}
	return false
}
