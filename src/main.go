// ============================================================
//
//	abserver — 广告拦截·内核增强版 服务组件
//	单文件多子命令: fetch | ca | proxy | serve | token | version
//	纯 Go 静态编译，无 CGO 依赖，适配 Android arm64/arm/amd64
//
// ============================================================
package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/md5"
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"flag"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const version = "1.0.0"

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}
	switch os.Args[1] {
	case "fetch":
		cmdFetch(os.Args[2:])
	case "ca":
		cmdCA(os.Args[2:])
	case "proxy":
		cmdProxy(os.Args[2:])
	case "serve":
		cmdServe(os.Args[2:])
	case "route":
		cmdRoute(os.Args[2:])
	case "clash":
		cmdClash(os.Args[2:])
	case "geoip":
		cmdGeoip(os.Args[2:])
	case "token":
		cmdToken()
	case "version", "-v", "--version":
		fmt.Println("abserver " + version)
	default:
		usage()
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, `abserver - 广告拦截·规则路由 内核服务组件
用法:
  abserver fetch -url URL -out FILE [-timeout SEC]          HTTP(S) 下载
  abserver ca    -dir DIR [-cn NAME]                        生成根 CA
  abserver proxy -http :PORT -https :PORT -ca-key K -ca-crt C -rules R
                                                            MITM 广告改写代理
  abserver serve -addr :PORT -webroot DIR -moddir D -datadir D -token T
                                                            面板 Web 服务
  abserver route compile -profile P.json -out C.json        编译 sing-box 配置
  abserver route lint    -profile P.json                    规则体检
  abserver route test    -profile P.json -domain D          规则匹配推演
  abserver route import  -in FILE -format auto [-out P.json]  导入多格式配置
  abserver route explain -profile P.json                    规则编译对照表
  abserver clash -api ADDR {status|conn|traffic|proxies|delay|select|mode|logs}
  abserver geoip -db DIR {-ip IP | -file F | -compare A,B} [-json]
                                                            离线 IP 归属/ASN 查询与泄露对比
  abserver token                                            生成访问令牌
  abserver version`)
}

// ============================================================
//
//	fetch — HTTP(S) 下载 (纯 Go，支持 HTTPS/跳转/超时)
//
// ============================================================
func cmdFetch(args []string) {
	fs := flag.NewFlagSet("fetch", flag.ExitOnError)
	url := fs.String("url", "", "下载地址")
	out := fs.String("out", "", "输出文件")
	to := fs.Int("timeout", 30, "超时秒")
	fs.Parse(args)
	if *url == "" || *out == "" {
		fmt.Fprintln(os.Stderr, "ERR: 缺少 -url 或 -out")
		os.Exit(2)
	}
	client := &http.Client{Timeout: time.Duration(*to) * time.Second}
	req, err := http.NewRequest("GET", *url, nil)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR:", err)
		os.Exit(1)
	}
	req.Header.Set("User-Agent", "SY/1.0 (+https://github.com)")
	resp, err := client.Do(req)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR:", err)
		os.Exit(1)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		fmt.Fprintf(os.Stderr, "ERR: HTTP %d\n", resp.StatusCode)
		os.Exit(1)
	}
	tmp := *out + ".part"
	f, err := os.Create(tmp)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR:", err)
		os.Exit(1)
	}
	n, err := io.Copy(f, resp.Body)
	f.Close()
	if err != nil {
		os.Remove(tmp)
		fmt.Fprintln(os.Stderr, "ERR:", err)
		os.Exit(1)
	}
	if err := os.Rename(tmp, *out); err != nil {
		fmt.Fprintln(os.Stderr, "ERR:", err)
		os.Exit(1)
	}
	fmt.Printf("OK %d bytes -> %s\n", n, *out)
}

// ============================================================
//
//	ca — 生成根 CA 证书 (RSA 2048, 10 年)
//
// ============================================================
func cmdCA(args []string) {
	fs := flag.NewFlagSet("ca", flag.ExitOnError)
	dir := fs.String("dir", ".", "CA 输出目录")
	cn := fs.String("cn", "SY Root CA", "Common Name")
	cacerts := fs.String("cacerts", "", "系统证书目录(写入 <hash>.0)")
	fs.Parse(args)
	os.MkdirAll(*dir, 0700)

	keyPath := filepath.Join(*dir, "ca.key")
	crtPath := filepath.Join(*dir, "ca.crt")
	if fileExists(keyPath) && fileExists(crtPath) {
		if data, e := os.ReadFile(crtPath); e == nil {
			emitHash(crtPath, data, *cacerts)
		} else {
			fmt.Println("OK: CA 已存在")
		}
		return
	}

	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR:", err)
		os.Exit(1)
	}
	serial, _ := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	tmpl := &x509.Certificate{
		SerialNumber: serial,
		Subject: pkix.Name{
			CommonName:   *cn,
			Organization: []string{"SY"},
			Country:      []string{"CN"},
		},
		NotBefore:             time.Now().Add(-24 * time.Hour),
		NotAfter:              time.Now().AddDate(10, 0, 0),
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign | x509.KeyUsageDigitalSignature,
		BasicConstraintsValid: true,
		IsCA:                  true,
		MaxPathLen:            2,
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &priv.PublicKey, priv)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR:", err)
		os.Exit(1)
	}
	writePEM(keyPath, "RSA PRIVATE KEY", x509.MarshalPKCS1PrivateKey(priv), 0600)
	writePEM(crtPath, "CERTIFICATE", der, 0644)
	emitHash(crtPath, der, *cacerts)
}

// certHashName 计算 Android 系统证书所需文件名 <subject_hash_old>.0
// 算法: MD5(cert.RawSubject) 取前 4 字节按小端拼成 uint32，十六进制小写 + ".0"
func certHashName(der []byte) (string, error) {
	raw := der
	if block, _ := pem.Decode(der); block != nil {
		raw = block.Bytes
	}
	c, err := x509.ParseCertificate(raw)
	if err != nil {
		return "", err
	}
	h := md5.Sum(c.RawSubject)
	v := uint32(h[0]) | uint32(h[1])<<8 | uint32(h[2])<<16 | uint32(h[3])<<24
	return fmt.Sprintf("%08x.0", v), nil
}

// emitHash 输出 HASH= 供脚本解析；若指定 cacerts 目录则直接写入系统证书区
func emitHash(crtPath string, der []byte, cacerts string) {
	name, err := certHashName(der)
	if err != nil || name == "" {
		name = "sy.0"
	}
	if cacerts != "" {
		os.MkdirAll(cacerts, 0755)
		pb := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
		os.WriteFile(filepath.Join(cacerts, name), pb, 0644)
	}
	fmt.Printf("OK: CA %s HASH=%s\n", crtPath, name)
}

func writePEM(path, typ string, der []byte, mode os.FileMode) {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, mode)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ERR:", err)
		os.Exit(1)
	}
	pem.Encode(f, &pem.Block{Type: typ, Bytes: der})
	f.Close()
}

// ============================================================
//
//	token — 生成随机访问令牌
//
// ============================================================
func cmdToken() {
	b := make([]byte, 16)
	rand.Read(b)
	fmt.Printf("%x\n", b)
}

// ============================================================
//
//	共享工具
//
// ============================================================
func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

var _ = exec.Command
var _ = sync.Mutex{}
var _ = tls.VersionTLS12
var _ = net.Dial
var _ = ecdsa.PrivateKey{}
var _ = elliptic.P256
var _ = strings.TrimSpace
