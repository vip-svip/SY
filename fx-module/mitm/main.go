// PrivacyGuard experimental transparent HTTPS MITM engine.
// Only use on devices/networks you own or are authorized to inspect.
// Supports transparent TCP/443 interception for HTTP/1.1 over TLS. It does not
// bypass certificate pinning, QUIC/HTTP3, client certificates, or custom TLS stacks.
package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"math/big"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

const (
	defaultDir               = "/data/adb/privacyguard/mitm"
	originalDstOpt           = 80 // SO_ORIGINAL_DST
	maxCachedCertificates    = 512
	maxConcurrentConnections = 128
)

type engine struct {
	ca       *x509.Certificate
	key      *rsa.PrivateKey
	mu       sync.Mutex
	scriptMu sync.RWMutex
	certs    map[string]*tls.Certificate
	sem      chan struct{}
	logFile  *os.File
	modDir   string
	scripts  []scriptSpec
	// Cosmetic selectors are shared across concurrent HTML requests. Cache their
	// parsed snapshot briefly so hundreds of simple selectors do not cause repeated
	// settings/rulefile reads on every page request; configuration changes propagate
	// within one second.
	cosmeticMu       sync.Mutex
	cosmeticLoadedAt time.Time
	cosmeticCached   []cosmeticRule
	networkMu        sync.Mutex
	networkLoadedAt  time.Time
	networkCached    []networkFilterRule
	networkByHost    map[string][]networkFilterRule
	networkGlobal    []networkFilterRule
}

type scriptSpec struct {
	path  string
	kind  string
	match *regexp.Regexp
}

type scriptRequest struct {
	URL     string            `json:"url"`
	Method  string            `json:"method"`
	Headers map[string]string `json:"headers"`
	Body    string            `json:"body"`
}
type scriptResponse struct {
	Status     int               `json:"status"`
	StatusCode int               `json:"statusCode"`
	Headers    map[string]string `json:"headers"`
	Body       string            `json:"body"`
}
type scriptEvent struct {
	Stage    string         `json:"stage"`
	Request  scriptRequest  `json:"request"`
	Response scriptResponse `json:"response"`
}
type scriptResult struct {
	OK     bool            `json:"ok"`
	Done   bool            `json:"done"`
	Result json.RawMessage `json:"result"`
	Error  string          `json:"error"`
}

func secureMkdir(p string) error {
	if err := os.MkdirAll(p, 0700); err != nil {
		return err
	}
	return os.Chmod(p, 0700)
}

// loadExistingCA is a read-only CA loader for status reporting. Unlike
// loadOrCreateCA it never creates directories/files or changes key permissions.
func loadExistingCA(dir string) (*x509.Certificate, *rsa.PrivateKey, error) {
	certPath, keyPath := filepath.Join(dir, "ca.pem"), filepath.Join(dir, "ca-key.pem")
	certPEM, err := os.ReadFile(certPath)
	if err != nil {
		return nil, nil, fmt.Errorf("read existing CA certificate: %w", err)
	}
	keyPEM, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, nil, fmt.Errorf("read existing CA private key: %w", err)
	}
	cb, _ := pem.Decode(certPEM)
	kb, _ := pem.Decode(keyPEM)
	if cb == nil || cb.Type != "CERTIFICATE" || kb == nil || kb.Type != "RSA PRIVATE KEY" {
		return nil, nil, errors.New("invalid CA PEM")
	}
	cert, err := x509.ParseCertificate(cb.Bytes)
	if err != nil {
		return nil, nil, err
	}
	key, err := x509.ParsePKCS1PrivateKey(kb.Bytes)
	if err != nil {
		return nil, nil, err
	}
	if !cert.IsCA || !cert.BasicConstraintsValid || cert.KeyUsage&x509.KeyUsageCertSign == 0 {
		return nil, nil, errors.New("configured certificate lacks valid CA constraints or cert-sign usage")
	}
	expectedSubject := pkix.Name{Country: []string{"CN"}, Organization: []string{"PrivacyGuard Project"}, CommonName: "PrivacyGuard MITM Detection CA"}
	if cert.Subject.String() != expectedSubject.String() {
		return nil, nil, errors.New("CA subject mismatch; explicit rotate-ca required before system trust sync")
	}
	if time.Now().Before(cert.NotBefore) || time.Now().After(cert.NotAfter) {
		return nil, nil, errors.New("configured CA certificate is not currently valid")
	}
	pub, ok := cert.PublicKey.(*rsa.PublicKey)
	if !ok || pub.E != key.PublicKey.E || pub.N.Cmp(key.PublicKey.N) != 0 {
		return nil, nil, errors.New("CA certificate and private key do not match")
	}
	return cert, key, nil
}

func loadOrCreateCA(dir string) (*x509.Certificate, *rsa.PrivateKey, error) {
	certPath, keyPath := filepath.Join(dir, "ca.pem"), filepath.Join(dir, "ca-key.pem")
	_, certStatErr := os.Stat(certPath)
	_, keyStatErr := os.Stat(keyPath)
	certExists, keyExists := certStatErr == nil, keyStatErr == nil
	if certExists != keyExists {
		return nil, nil, errors.New("incomplete CA pair: certificate or private key is missing; restore the pair or use explicit recovery")
	}
	if !certExists && (!os.IsNotExist(certStatErr) || !os.IsNotExist(keyStatErr)) {
		return nil, nil, fmt.Errorf("cannot inspect existing CA pair: cert=%v key=%v", certStatErr, keyStatErr)
	}
	certPEM, ce := os.ReadFile(certPath)
	keyPEM, ke := os.ReadFile(keyPath)
	if ce == nil && ke == nil {
		cb, _ := pem.Decode(certPEM)
		kb, _ := pem.Decode(keyPEM)
		if cb == nil || kb == nil {
			return nil, nil, errors.New("invalid CA PEM")
		}
		cert, err := x509.ParseCertificate(cb.Bytes)
		if err != nil {
			return nil, nil, err
		}
		key, err := x509.ParsePKCS1PrivateKey(kb.Bytes)
		if err != nil {
			return nil, nil, err
		}
		if !cert.IsCA || !cert.BasicConstraintsValid || cert.KeyUsage&x509.KeyUsageCertSign == 0 {
			return nil, nil, errors.New("configured certificate lacks valid CA constraints or cert-sign usage")
		}
		expectedSubject := pkix.Name{Country: []string{"CN"}, Organization: []string{"PrivacyGuard Project"}, CommonName: "PrivacyGuard MITM Detection CA"}
		if cert.Subject.String() != expectedSubject.String() {
			return nil, nil, errors.New("CA subject mismatch; explicit rotate-ca required before system trust sync")
		}
		if time.Now().Before(cert.NotBefore) || time.Now().After(cert.NotAfter) {
			return nil, nil, errors.New("configured CA certificate is not currently valid")
		}
		pub, ok := cert.PublicKey.(*rsa.PublicKey)
		if !ok || pub.E != key.PublicKey.E || pub.N.Cmp(key.PublicKey.N) != 0 {
			return nil, nil, errors.New("CA certificate and private key do not match")
		}
		if err := os.Chmod(keyPath, 0600); err != nil {
			return nil, nil, fmt.Errorf("secure CA private key permissions: %w", err)
		}
		return cert, key, nil
	}
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return nil, nil, err
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 120))
	if err != nil {
		return nil, nil, err
	}
	now := time.Now()
	tmpl := &x509.Certificate{SerialNumber: serial, Subject: pkix.Name{Country: []string{"CN"}, Organization: []string{"PrivacyGuard Project"}, CommonName: "PrivacyGuard MITM Detection CA"}, NotBefore: now.Add(-5 * time.Minute), NotAfter: now.AddDate(10, 0, 0), KeyUsage: x509.KeyUsageCertSign | x509.KeyUsageCRLSign | x509.KeyUsageDigitalSignature, BasicConstraintsValid: true, IsCA: true, MaxPathLen: 0}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		return nil, nil, err
	}
	cert, err := x509.ParseCertificate(der)
	if err != nil {
		return nil, nil, err
	}
	if err = os.WriteFile(keyPath, pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)}), 0600); err != nil {
		return nil, nil, err
	}
	if err = os.WriteFile(certPath, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), 0644); err != nil {
		return nil, nil, err
	}
	return cert, key, nil
}

// rotateCA preserves the last known keypair and refuses to overwrite an
// existing recovery pair. It restores the original pair if generation fails.
func rotateCA(dir string) (*x509.Certificate, error) {
	if err := secureMkdir(dir); err != nil {
		return nil, err
	}
	certPath, keyPath := filepath.Join(dir, "ca.pem"), filepath.Join(dir, "ca-key.pem")
	prevCert, prevKey := certPath+".previous", keyPath+".previous"
	_, certErr := os.Stat(certPath)
	_, keyErr := os.Stat(keyPath)
	if certErr == nil && keyErr != nil || certErr != nil && keyErr == nil {
		return nil, errors.New("incomplete existing CA pair; refusing rotation to preserve recoverability")
	}
	if _, err := os.Stat(prevCert); err == nil {
		return nil, errors.New("recovery certificate already exists; archive it before another rotation")
	}
	if _, err := os.Stat(prevKey); err == nil {
		return nil, errors.New("recovery private key already exists; archive it before another rotation")
	}
	if certErr == nil {
		if err := os.Rename(certPath, prevCert); err != nil {
			return nil, err
		}
		if err := os.Rename(keyPath, prevKey); err != nil {
			_ = os.Rename(prevCert, certPath)
			return nil, err
		}
	}
	cert, _, err := loadOrCreateCA(dir)
	if err != nil {
		_ = os.Remove(certPath)
		_ = os.Remove(keyPath)
		if _, e := os.Stat(prevCert); e == nil {
			_ = os.Rename(prevCert, certPath)
		}
		if _, e := os.Stat(prevKey); e == nil {
			_ = os.Rename(prevKey, keyPath)
		}
		return nil, fmt.Errorf("CA rotation failed; previous pair restored: %w", err)
	}
	return cert, nil
}

func normalizeHostname(host string) (string, error) {
	host = strings.TrimSuffix(strings.Trim(host, "[]"), ".")
	if h, _, err := net.SplitHostPort(host); err == nil {
		host = h
	}
	host = strings.ToLower(host)
	if host == "" || len(host) > 253 || strings.ContainsAny(host, "\r\n/\\ %\t") {
		return "", errors.New("invalid or empty hostname")
	}
	if net.ParseIP(host) != nil {
		return host, nil
	}
	for _, label := range strings.Split(host, ".") {
		if len(label) == 0 || len(label) > 63 || label[0] == '-' || label[len(label)-1] == '-' {
			return "", errors.New("invalid DNS label")
		}
		for _, r := range label {
			if !((r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '-') {
				return "", errors.New("invalid DNS hostname character")
			}
		}
	}
	return host, nil
}

func leafFor(e *engine, host string) (*tls.Certificate, error) {
	var err error
	host, err = normalizeHostname(host)
	if err != nil {
		return nil, err
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	if c := e.certs[host]; c != nil {
		return c, nil
	}
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return nil, err
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 120))
	if err != nil {
		return nil, err
	}
	tmpl := &x509.Certificate{SerialNumber: serial, Subject: pkix.Name{CommonName: host}, NotBefore: time.Now().Add(-5 * time.Minute), NotAfter: time.Now().AddDate(1, 0, 0), KeyUsage: x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}, BasicConstraintsValid: true}
	if ip := net.ParseIP(host); ip != nil {
		tmpl.IPAddresses = []net.IP{ip}
	} else {
		tmpl.DNSNames = []string{host}
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, e.ca, &key.PublicKey, e.key)
	if err != nil {
		return nil, err
	}
	cert := &tls.Certificate{Certificate: [][]byte{der, e.ca.Raw}, PrivateKey: key, Leaf: tmpl}
	// Bound cache growth: arbitrary SNI values must not grow memory forever.
	if len(e.certs) < maxCachedCertificates {
		e.certs[host] = cert
	}
	return cert, nil
}
func originalDestination(c net.Conn) (string, error) {
	tc, ok := c.(*net.TCPConn)
	if !ok {
		return "", errors.New("not TCP")
	}
	raw, err := tc.SyscallConn()
	if err != nil {
		return "", err
	}
	var dst string
	var inner error
	// REDIRECT preserves the original destination in conntrack. Android devices may
	// receive IPv4 and IPv6 flows, so query the family matching the accepted socket.
	is6 := false
	if la, ok := tc.LocalAddr().(*net.TCPAddr); ok && la.IP != nil {
		is6 = la.IP.To4() == nil && la.IP.To16() != nil
	}
	err = raw.Control(func(fd uintptr) {
		if is6 {
			var sa syscall.RawSockaddrInet6
			ln := uint32(unsafe.Sizeof(sa))
			_, _, errno := syscall.Syscall6(syscall.SYS_GETSOCKOPT, fd, uintptr(syscall.SOL_IPV6), uintptr(originalDstOpt), uintptr(unsafe.Pointer(&sa)), uintptr(unsafe.Pointer(&ln)), 0)
			if errno != 0 {
				inner = errno
				return
			}
			ip := net.IP(sa.Addr[:])
			port := int(sa.Port>>8) | int(sa.Port&0xff)<<8
			dst = net.JoinHostPort(ip.String(), fmt.Sprint(port))
		} else {
			var sa syscall.RawSockaddrInet4
			ln := uint32(unsafe.Sizeof(sa))
			_, _, errno := syscall.Syscall6(syscall.SYS_GETSOCKOPT, fd, uintptr(syscall.SOL_IP), uintptr(originalDstOpt), uintptr(unsafe.Pointer(&sa)), uintptr(unsafe.Pointer(&ln)), 0)
			if errno != 0 {
				inner = errno
				return
			}
			ip := net.IP(sa.Addr[:])
			port := int(sa.Port>>8) | int(sa.Port&0xff)<<8
			dst = net.JoinHostPort(ip.String(), fmt.Sprint(port))
		}
	})
	if err != nil {
		return "", err
	}
	if inner != nil {
		return "", inner
	}
	if dst == "" {
		return "", errors.New("SO_ORIGINAL_DST unavailable")
	}
	return dst, nil
}
func stripHopHeaders(h http.Header) {
	for _, k := range []string{"Connection", "Proxy-Connection", "Keep-Alive", "Proxy-Authenticate", "Proxy-Authorization", "TE", "Trailer", "Transfer-Encoding", "Upgrade"} {
		h.Del(k)
	}
}

const scriptBodyLimit = 1 << 20

// normalizeProxyScriptPattern accepts both raw proxy-module regexes and regexes
// double-escaped by JSON/config generators. Go's regexp syntax does not treat
// slash as a delimiter, so "\/" is invalid and must become "/" before compile.
func normalizeProxyScriptPattern(pattern string) string {
	// If slashes are double-escaped, the full URL pattern is likely serialized
	// through an extra string layer; collapse doubled backslashes together so
	// escaped dots and path components keep their intended URL-regex meaning.
	if strings.Contains(pattern, `\\/`) {
		pattern = strings.ReplaceAll(pattern, `\\`, `\`)
	}
	return strings.ReplaceAll(pattern, `\/`, `/`)
}

func parseScriptSpec(path, source string) (scriptSpec, bool, error) {
	kind, pattern := "", ""
	var globs []string
	lines := strings.Split(source, "\n")
	if len(lines) > 80 {
		lines = lines[:80]
	}
	for _, raw := range lines {
		line := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(raw), "//"))
		upper := strings.ToUpper(line)
		if strings.HasPrefix(upper, "FX-SCRIPT-TYPE:") {
			kind = strings.ToLower(strings.TrimSpace(line[len("FX-SCRIPT-TYPE:"):]))
		}
		if strings.HasPrefix(upper, "FX-SCRIPT-MATCH:") {
			pattern = strings.TrimSpace(line[len("FX-SCRIPT-MATCH:"):])
		}
		// Common userscript metadata is accepted as a conservative URL glob.
		// Explicit FX regex metadata always takes precedence.
		for _, key := range []string{"@match", "@include", "@url"} {
			if strings.HasPrefix(line, key+" ") || strings.HasPrefix(line, key+"\t") {
				value := strings.TrimSpace(strings.TrimPrefix(line, key))
				if strings.HasPrefix(value, "http://") || strings.HasPrefix(value, "https://") {
					globs = append(globs, value)
				}
			}
		}
	}
	if pattern == "" && len(globs) > 0 {
		parts := make([]string, 0, len(globs))
		for _, glob := range globs {
			// Treat metadata as glob syntax, not arbitrary regular expressions.
			q := regexp.QuoteMeta(glob)
			q = strings.ReplaceAll(q, `\*`, `.*`)
			parts = append(parts, q)
		}
		pattern = "^(?:" + strings.Join(parts, "|") + ")$"
		if kind == "" {
			kind = "both"
		}
	}
	if kind != "request" && kind != "response" && kind != "both" {
		return scriptSpec{}, false, nil
	}
	if pattern == "" {
		return scriptSpec{}, false, nil
	}
	pattern = normalizeProxyScriptPattern(pattern)
	rx, err := regexp.Compile(pattern)
	if err != nil {
		return scriptSpec{}, false, err
	}
	return scriptSpec{path: path, kind: kind, match: rx}, true, nil
}

func loadScriptSpecs(modDir string) []scriptSpec {
	if modDir == "" {
		return nil
	}
	// PG is the persistent state directory, while FX_MODDIR points at the
	// installed module. Keep them separate so tests, relocated installs, and
	// non-default state paths load the same scripts that sync-subs publishes.
	pgDir := strings.TrimSpace(os.Getenv("PG"))
	if pgDir == "" {
		pgDir = "/data/adb/privacyguard"
	}
	return loadScriptSpecsFrom(filepath.Join(pgDir, "jsruntime", "scripts"))
}

func validManagedScriptHash(path string) bool {
	if !strings.HasPrefix(filepath.Base(path), "pgsub_") {
		return true // Manually installed local scripts are not managed by the URL updater.
	}
	content, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	manifest, err := os.ReadFile(path + ".sha256")
	if err != nil {
		return false
	}
	fields := strings.Fields(string(manifest))
	if len(fields) < 1 || len(fields[0]) != 64 {
		return false
	}
	sum := sha256.Sum256(content)
	return strings.EqualFold(fields[0], fmt.Sprintf("%x", sum))
}

func loadScriptSpecsFrom(root string) []scriptSpec {
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil
	}
	var out []scriptSpec
	for _, ent := range entries {
		if ent.IsDir() || ent.Type()&os.ModeSymlink != 0 || !strings.HasSuffix(strings.ToLower(ent.Name()), ".js") {
			continue
		}
		path := filepath.Join(root, ent.Name())
		if !validManagedScriptHash(path) {
			log.Printf("script %s: SHA-256 manifest missing or mismatched; refusing to activate", ent.Name())
			continue
		}
		f, err := os.Open(path)
		if err != nil {
			continue
		}
		buf := make([]byte, 8192)
		n, _ := f.Read(buf)
		_ = f.Close()
		spec, ok, err := parseScriptSpec(path, string(buf[:n]))
		if err != nil {
			log.Printf("script %s: invalid FX-SCRIPT-MATCH: %v", ent.Name(), err)
			continue
		}
		if ok {
			out = append(out, spec)
		}
	}
	return out
}

func scriptBodyEditable(h http.Header, size int) bool {
	encoding := strings.TrimSpace(strings.ToLower(h.Get("Content-Encoding")))
	if encoding != "" && encoding != "identity" {
		return false
	}
	ct := strings.ToLower(strings.TrimSpace(strings.SplitN(h.Get("Content-Type"), ";", 2)[0]))
	if size == 0 && ct == "" {
		return true
	}
	if strings.HasPrefix(ct, "text/") {
		return true
	}
	switch ct {
	case "application/json", "application/ld+json", "application/javascript", "application/x-javascript", "application/xml", "application/x-www-form-urlencoded", "application/graphql", "image/svg+xml":
		return true
	}
	return false
}

func (e *engine) refreshScripts() {
	loaded := loadScriptSpecs(e.modDir)
	e.scriptMu.Lock()
	e.scripts = loaded
	e.scriptMu.Unlock()
}

func (e *engine) scriptSpecs() []scriptSpec {
	e.scriptMu.RLock()
	defer e.scriptMu.RUnlock()
	return append([]scriptSpec(nil), e.scripts...)
}

func headerMap(h http.Header) map[string]string {
	m := make(map[string]string, len(h))
	for k, v := range h {
		m[k] = strings.Join(v, ", ")
	}
	return m
}

var scriptManagedHeaders = map[string]struct{}{
	// These fields describe the HTTP framing, connection, authority, or wire
	// representation. Letting untrusted scripts patch them without coordinating
	// the underlying body/transport can truncate responses or corrupt keep-alive.
	"connection": {}, "keep-alive": {}, "proxy-connection": {}, "transfer-encoding": {},
	"content-length": {}, "content-encoding": {}, "trailer": {}, "te": {}, "upgrade": {},
	"host": {}, "proxy-authenticate": {}, "proxy-authorization": {},
}

func patchHeaders(dst http.Header, raw json.RawMessage) error {
	if len(raw) == 0 || string(raw) == "null" {
		return nil
	}
	var values map[string]json.RawMessage
	if err := json.Unmarshal(raw, &values); err != nil {
		return err
	}
	var rejected []string
	for k, v := range values {
		if strings.ContainsAny(k, "\r\n") {
			continue
		}
		canonical := http.CanonicalHeaderKey(strings.TrimSpace(k))
		if canonical == "" {
			continue
		}
		if _, managed := scriptManagedHeaders[strings.ToLower(canonical)]; managed {
			rejected = append(rejected, canonical)
			continue
		}
		var text string
		if err := json.Unmarshal(v, &text); err != nil {
			var arr []string
			if json.Unmarshal(v, &arr) == nil {
				text = strings.Join(arr, ", ")
			} else {
				continue
			}
		}
		if strings.ContainsAny(text, "\r\n") {
			continue
		}
		dst.Set(canonical, text)
	}
	if len(rejected) != 0 {
		sort.Strings(rejected)
		return fmt.Errorf("ignored script changes to runtime-managed headers: %s", strings.Join(rejected, ", "))
	}
	return nil
}

// configureCommandProcessGroup ensures timeouts terminate every child started by
// the script runner, not only the shell process created by exec.CommandContext.
func configureCommandProcessGroup(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return os.ErrProcessDone
		}
		err := syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		if err == syscall.ESRCH {
			return os.ErrProcessDone
		}
		return err
	}
	cmd.WaitDelay = 2 * time.Second
}

// boundedBuffer prevents a faulty or hostile script from exhausting the MITM
// process by writing unbounded data to stdout/stderr. Write reports the input as
// consumed while retaining only the configured prefix, so child pipes cannot stall.
type boundedBuffer struct {
	buf       bytes.Buffer
	limit     int
	truncated bool
}

func (b *boundedBuffer) Write(p []byte) (int, error) {
	if b.limit <= 0 {
		b.truncated = b.truncated || len(p) > 0
		return len(p), nil
	}
	left := b.limit - b.buf.Len()
	if left > 0 {
		n := len(p)
		if n > left {
			n = left
		}
		if n > 0 {
			_, _ = b.buf.Write(p[:n])
		}
	}
	if len(p) > left {
		b.truncated = true
	}
	return len(p), nil
}
func (b *boundedBuffer) Len() int       { return b.buf.Len() }
func (b *boundedBuffer) Bytes() []byte  { return b.buf.Bytes() }
func (b *boundedBuffer) String() string { return b.buf.String() }

const scriptExecutionTimeout = 25 * time.Second
const scriptStageTimeout = 30 * time.Second

func (e *engine) executeScript(spec scriptSpec, ev scriptEvent) (json.RawMessage, error) {
	return e.executeScriptContext(context.Background(), spec, ev)
}

func (e *engine) executeScriptContext(parent context.Context, spec scriptSpec, ev scriptEvent) (json.RawMessage, error) {
	if e.modDir == "" {
		return nil, errors.New("module directory not configured")
	}
	runner := filepath.Join(e.modDir, "scripts", "jsruntime", "runner.sh")
	if _, err := os.Stat(runner); err != nil {
		return nil, err
	}
	tmp, err := os.CreateTemp("", "fx-script-event-*.json")
	if err != nil {
		return nil, err
	}
	eventPath := tmp.Name()
	defer os.Remove(eventPath)
	encErr := json.NewEncoder(tmp).Encode(ev)
	closeErr := tmp.Close()
	if encErr != nil {
		return nil, encErr
	}
	if closeErr != nil {
		return nil, closeErr
	}
	ctx, cancel := context.WithTimeout(parent, scriptExecutionTimeout)
	defer cancel()
	shell := "/system/bin/sh"
	if _, err := os.Stat(shell); err != nil {
		shell = "sh"
	}
	cmd := exec.CommandContext(ctx, shell, runner, spec.path, eventPath)
	// Scripts can start child processes through QuickJS' host bridge (for example
	// curl via $httpClient). Kill the runner process group on timeout so qjs/curl
	// cannot continue after the request hook has failed.
	configureCommandProcessGroup(cmd)
	pgDir := strings.TrimSpace(os.Getenv("PG"))
	if pgDir == "" {
		pgDir = "/data/adb/privacyguard"
	}
	cmd.Env = append(os.Environ(), "FX_MODDIR="+e.modDir, "PG="+pgDir)
	stdout := &boundedBuffer{limit: 2 << 20}
	stderr := &boundedBuffer{limit: 256 << 10}
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	if err := cmd.Run(); err != nil {
		if stderr.Len() > 0 {
			msg := strings.TrimSpace(stderr.String())
			if stderr.truncated {
				msg += " [stderr truncated at 256 KiB]"
			}
			log.Printf("script %s failed: %s", filepath.Base(spec.path), msg)
		}
		return nil, err
	}
	if stdout.truncated {
		return nil, fmt.Errorf("script %s emitted more than 2 MiB to stdout; result rejected", filepath.Base(spec.path))
	}
	var result scriptResult
	if err := json.Unmarshal(stdout.Bytes(), &result); err != nil {
		return nil, fmt.Errorf("script %s returned invalid JSON: %w", filepath.Base(spec.path), err)
	}
	if !result.OK {
		return nil, fmt.Errorf("script %s: %s", filepath.Base(spec.path), result.Error)
	}
	if !result.Done || len(result.Result) == 0 || string(result.Result) == "null" {
		return nil, nil
	}
	return result.Result, nil
}

// prepareResponseScriptRequest asks the origin for an uncompressed entity when a
// matching response hook may inspect or rewrite the body. Without this, the
// origin commonly returns gzip/br bytes and $response.body is empty, so
// requires-body style scripts silently cannot perform their intended work.
// This is limited to URLs with an active response/both hook.
func (e *engine) prepareResponseScriptRequest(req *http.Request) {
	if req == nil || req.URL == nil {
		return
	}
	for _, s := range e.scriptSpecs() {
		if (s.kind == "response" || s.kind == "both") && s.match.MatchString(req.URL.String()) {
			req.Header.Set("Accept-Encoding", "identity")
			return
		}
	}
}

func restoreHeaderValues(dst http.Header, src http.Header, key string) {
	dst.Del(key)
	for _, value := range src.Values(key) {
		dst.Add(key, value)
	}
}

func (e *engine) applyRequestScripts(req *http.Request) {
	originalFramingHeaders := req.Header.Clone()
	scripts := e.scriptSpecs()
	if len(scripts) == 0 {
		return
	}
	var selected []scriptSpec
	for _, s := range scripts {
		if (s.kind == "request" || s.kind == "both") && s.match.MatchString(req.URL.String()) {
			selected = append(selected, s)
		}
	}
	if len(selected) == 0 {
		return
	}
	hadBody := req.Body != nil && req.Body != http.NoBody
	var body []byte
	if hadBody {
		readBody, err := io.ReadAll(io.LimitReader(req.Body, scriptBodyLimit+1))
		if err != nil {
			req.Body = io.NopCloser(io.MultiReader(bytes.NewReader(readBody), req.Body))
			return
		}
		if len(readBody) > scriptBodyLimit {
			req.Body = io.NopCloser(io.MultiReader(bytes.NewReader(readBody), req.Body))
			return
		}
		_ = req.Body.Close()
		body = readBody
	}
	bodyEditable := scriptBodyEditable(req.Header, len(body))
	bodyChanged := false
	stageCtx, stageCancel := context.WithTimeout(context.Background(), scriptStageTimeout)
	defer stageCancel()
	for _, s := range selected {
		if stageCtx.Err() != nil {
			log.Printf("request scripts: stage deadline reached; skipping remaining hooks")
			break
		}
		eventBody := ""
		if bodyEditable {
			eventBody = string(body)
		}
		ev := scriptEvent{Stage: "request", Request: scriptRequest{URL: req.URL.String(), Method: req.Method, Headers: headerMap(req.Header), Body: eventBody}}
		patch, err := e.executeScriptContext(stageCtx, s, ev)
		if err != nil {
			log.Printf("request script %s: %v", filepath.Base(s.path), err)
			continue
		}
		if len(patch) == 0 {
			continue
		}
		var p map[string]json.RawMessage
		if json.Unmarshal(patch, &p) != nil {
			continue
		}
		if raw := p["url"]; len(raw) > 0 {
			var candidate string
			if json.Unmarshal(raw, &candidate) == nil {
				if u, err := url.Parse(candidate); err == nil && u.Host == req.URL.Host && u.Scheme == req.URL.Scheme {
					req.URL = u
					req.RequestURI = ""
				}
			}
		}
		if raw := p["method"]; len(raw) > 0 {
			var m string
			if json.Unmarshal(raw, &m) == nil && regexp.MustCompile(`^[A-Za-z]{1,16}$`).MatchString(m) {
				req.Method = strings.ToUpper(m)
			}
		}
		if err := patchHeaders(req.Header, p["headers"]); err != nil {
			log.Printf("request script %s: %v", filepath.Base(s.path), err)
		}
		if raw := p["body"]; len(raw) > 0 && bodyEditable {
			var b string
			if json.Unmarshal(raw, &b) == nil {
				body = []byte(b)
				bodyChanged = true
			}
		}
	}
	// Do not turn an originally bodyless request (typically GET/HEAD) into an
	// explicit Content-Length: 0 request merely because a request hook matched.
	// Some origins and intermediaries distinguish absent framing from an empty
	// entity. Reframe only if there was a body to buffer or a script added one.
	if hadBody || bodyChanged {
		req.Body = io.NopCloser(bytes.NewReader(body))
		req.ContentLength = int64(len(body))
		req.Header.Del("Transfer-Encoding")
		req.Header.Del("Trailer")
		req.Header.Set("Content-Length", fmt.Sprint(len(body)))
	} else {
		// Header patches must not manufacture contradictory framing on a request
		// that has no entity body. Preserve the caller's original framing only.
		restoreHeaderValues(req.Header, originalFramingHeaders, "Content-Length")
		restoreHeaderValues(req.Header, originalFramingHeaders, "Transfer-Encoding")
		restoreHeaderValues(req.Header, originalFramingHeaders, "Trailer")
	}
}

func (e *engine) applyResponseScripts(req *http.Request, resp *http.Response) {
	scripts := e.scriptSpecs()
	if len(scripts) == 0 {
		return
	}
	var selected []scriptSpec
	for _, s := range scripts {
		if (s.kind == "response" || s.kind == "both") && s.match.MatchString(req.URL.String()) {
			selected = append(selected, s)
		}
	}
	if len(selected) == 0 {
		return
	}
	originalFramingHeaders := resp.Header.Clone()
	originalContentLength := resp.ContentLength
	var body []byte
	if resp.Body != nil {
		readBody, err := io.ReadAll(io.LimitReader(resp.Body, scriptBodyLimit+1))
		if err != nil {
			resp.Body = io.NopCloser(io.MultiReader(bytes.NewReader(readBody), resp.Body))
			return
		}
		if len(readBody) > scriptBodyLimit {
			resp.Body = io.NopCloser(io.MultiReader(bytes.NewReader(readBody), resp.Body))
			return
		}
		_ = resp.Body.Close()
		body = readBody
	}
	// HEAD and body-forbidden statuses can carry a Content-Length describing a
	// hypothetical representation. Never turn that into Content-Length: 0 or
	// inject a body merely because a response hook ran.
	bodyEditable := scriptBodyEditable(resp.Header, len(body)) && req.Method != http.MethodHead && resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusResetContent && resp.StatusCode != http.StatusNotModified
	bodyChanged := false
	stageCtx, stageCancel := context.WithTimeout(context.Background(), scriptStageTimeout)
	defer stageCancel()
	for _, s := range selected {
		if stageCtx.Err() != nil {
			log.Printf("response scripts: stage deadline reached; skipping remaining hooks")
			break
		}
		eventBody := ""
		if bodyEditable {
			eventBody = string(body)
		}
		ev := scriptEvent{Stage: "response", Request: scriptRequest{URL: req.URL.String(), Method: req.Method, Headers: headerMap(req.Header)}, Response: scriptResponse{Status: resp.StatusCode, StatusCode: resp.StatusCode, Headers: headerMap(resp.Header), Body: eventBody}}
		patch, err := e.executeScriptContext(stageCtx, s, ev)
		if err != nil {
			log.Printf("response script %s: %v", filepath.Base(s.path), err)
			continue
		}
		if len(patch) == 0 {
			continue
		}
		var p map[string]json.RawMessage
		if json.Unmarshal(patch, &p) != nil {
			continue
		}
		if raw := p["statusCode"]; len(raw) > 0 {
			var n int
			if json.Unmarshal(raw, &n) == nil && n >= 200 && n <= 599 {
				resp.StatusCode = n
				resp.Status = http.StatusText(n)
				if resp.Status != "" {
					resp.Status = fmt.Sprintf("%d %s", n, resp.Status)
				}
			}
		} else if raw := p["status"]; len(raw) > 0 {
			var n int
			if json.Unmarshal(raw, &n) == nil && n >= 200 && n <= 599 {
				resp.StatusCode = n
				resp.Status = fmt.Sprintf("%d %s", n, http.StatusText(n))
			}
		}
		if err := patchHeaders(resp.Header, p["headers"]); err != nil {
			log.Printf("response script %s: %v", filepath.Base(s.path), err)
		}
		if raw := p["body"]; len(raw) > 0 && bodyEditable {
			var b string
			if json.Unmarshal(raw, &b) == nil {
				body = []byte(b)
				bodyChanged = true
			}
		}
	}
	// HEAD responses retain the representation length supplied by the origin,
	// but never carry a body. A script-selected 204/304 also must not retain the
	// upstream entity bytes: the status now forbids a message body. Remove
	// Content-Length for these script-selected no-content statuses rather than
	// forwarding metadata that may describe a different representation.
	if resp.StatusCode == http.StatusNoContent || resp.StatusCode == http.StatusResetContent || resp.StatusCode == http.StatusNotModified {
		// A script-selected no-content status takes precedence over the request
		// method: in particular, HEAD must not preserve framing fields that are
		// forbidden for a 204 response. Normalize the status-specific framing
		// before applying the general HEAD representation-metadata rule.
		body = nil
		bodyChanged = false
		resp.Header.Del("Content-Length")
		resp.Header.Del("Transfer-Encoding")
		resp.Header.Del("Trailer")
		resp.TransferEncoding = nil
		resp.Trailer = nil
		resp.ContentLength = 0
	} else if req.Method == http.MethodHead {
		body = nil
		bodyChanged = false
	} else if !bodyChanged {
		// Scripts may patch headers, but must not override message framing while
		// leaving the entity bytes untouched. Restore the transport's framing.
		restoreHeaderValues(resp.Header, originalFramingHeaders, "Content-Length")
		restoreHeaderValues(resp.Header, originalFramingHeaders, "Transfer-Encoding")
		restoreHeaderValues(resp.Header, originalFramingHeaders, "Trailer")
		resp.ContentLength = originalContentLength
	}
	// The body was buffered so hooks can inspect it. Restore exact bytes when
	// unchanged; framing is recalculated only for an actually patched body.
	resp.Body = io.NopCloser(bytes.NewReader(body))
	if bodyChanged {
		resp.Header.Del("Content-Encoding")
		resp.Header.Del("ETag")
		resp.Header.Del("Content-MD5")
		resp.Header.Del("Accept-Ranges")
		resp.Header.Del("Transfer-Encoding")
		resp.Header.Del("Trailer")
		resp.TransferEncoding = nil
		resp.Trailer = nil
		resp.ContentLength = int64(len(body))
		resp.Header.Set("Content-Length", fmt.Sprint(len(body)))
	}
}

func (e *engine) handle(c net.Conn) {
	defer c.Close()
	// Reload the small hook manifest per TLS connection so a successful subscription
	// refresh takes effect without bouncing the listener or its firewall redirect.
	e.refreshScripts()
	// A client may stall during TLS or HTTP parsing; bound per-connection resource use.
	_ = c.SetDeadline(time.Now().Add(60 * time.Second))
	dst, err := originalDestination(c)
	if err != nil {
		log.Printf("reject original destination: %v", err)
		return
	}
	// MITM is limited to explicitly configured hostnames. Without an allowlist,
	// or when SNI is missing/malformed/unmatched, relay the original TLS bytes
	// untouched instead of presenting the FX CA to every public HTTPS host.
	allowedHosts, allowErr := loadMITMHosts(mitmHostnameManifestPath())
	if allowErr != nil {
		log.Printf("MITM hostname allowlist invalid; passing TLS through: %v", allowErr)
		if err := tunnelTLS(c, dst); err != nil {
			log.Printf("TLS passthrough %s: %v", dst, err)
		}
		return
	}
	if len(allowedHosts) == 0 {
		if err := tunnelTLS(c, dst); err != nil {
			log.Printf("TLS passthrough %s (empty allowlist): %v", dst, err)
		}
		return
	}
	prefix, sni, peekErr := readClientHelloSNI(c)
	clientConn := &replayConn{Conn: c, reader: io.MultiReader(bytes.NewReader(prefix), c)}
	if peekErr != nil || !mitmHostAllowed(sni, allowedHosts) {
		if peekErr != nil {
			log.Printf("TLS ClientHello inspection failed; passing through %s: %v", dst, peekErr)
		} else if sni != "" {
			log.Printf("TLS passthrough for non-MITM host %q", sni)
		}
		if err := tunnelTLS(clientConn, dst); err != nil {
			log.Printf("TLS passthrough %s: %v", dst, err)
		}
		return
	}
	host, _, _ := net.SplitHostPort(dst)
	tlsConn := tls.Server(clientConn, &tls.Config{MinVersion: tls.VersionTLS12, NextProtos: []string{"http/1.1"}, GetCertificate: func(chi *tls.ClientHelloInfo) (*tls.Certificate, error) {
		s := chi.ServerName
		if s == "" {
			s = host
		}
		return leafFor(e, s)
	}})
	_ = tlsConn.SetDeadline(time.Now().Add(25 * time.Second))
	if err = tlsConn.Handshake(); err != nil {
		log.Printf("TLS handshake %s: %v", dst, err)
		return
	}
	// Keep a bounded deadline for the complete HTTP transaction as well as the
	// handshake. Clearing it here lets a client hold one of the limited MITM
	// connection slots indefinitely by dribbling request headers/body or stalling
	// while receiving the rewritten response. This engine closes after one response.
	_ = tlsConn.SetDeadline(time.Now().Add(60 * time.Second))
	br := bufio.NewReader(tlsConn)
	for {
		req, err := http.ReadRequest(br)
		if err != nil {
			if err != io.EOF {
				log.Printf("HTTP parse %s: %v", dst, err)
			}
			return
		}
		if req.Method == http.MethodConnect {
			if req.Body != nil {
				_ = req.Body.Close()
			}
			return
		}
		if req.Host == "" {
			if req.Body != nil {
				_ = req.Body.Close()
			}
			_ = writeError(tlsConn, 400, "Bad Request")
			return
		}
		upstreamHost, err := normalizeHostname(req.Host)
		if err != nil {
			if req.Body != nil {
				_ = req.Body.Close()
			}
			_ = writeError(tlsConn, 400, "Bad Request")
			return
		}
		sni := tlsConn.ConnectionState().ServerName
		if sni != "" {
			normSNI, normErr := normalizeHostname(sni)
			if normErr != nil || !strings.EqualFold(upstreamHost, normSNI) {
				if req.Body != nil {
					_ = req.Body.Close()
				}
				_ = writeError(tlsConn, 421, "Misdirected Request")
				log.Printf("reject SNI/Host mismatch: sni=%q host=%q", sni, req.Host)
				return
			}
		}
		reqURL := &url.URL{Scheme: "https", Host: req.Host, Path: req.URL.Path, RawPath: req.URL.RawPath, RawQuery: req.URL.RawQuery}
		req.URL = reqURL
		req.RequestURI = ""
		req.Close = false
		stripHopHeaders(req.Header)
		// Apply native URL-scoped rules before scripts/upstream I/O. A malformed
		// rewrite manifest disables only URL Rewrite for this request; ordinary
		// HTTPS forwarding must continue so a bad rule cannot cause broad outages.
		rewriteRules := loadURLRewriteRulesOrEmpty(urlRewriteManifestPath())
		if rwResp, handled := applyURLRewrite(req, rewriteRules); handled {
			stripHopHeaders(rwResp.Header)
			rwResp.Header.Set("Connection", "close")
			_ = rwResp.Write(tlsConn)
			if rwResp.Body != nil {
				_ = rwResp.Body.Close()
			}
			if req.Body != nil {
				_ = req.Body.Close()
			}
			return
		}
		// Request hooks may change the URL, so apply the bounded native request
		// filter against the effective URL after request-stage scripts. The filter
		// understands safe ABP host/path rules and request context (third-party,
		// resource type, popup and domain=); unsupported modifiers are skipped.
		e.applyRequestScripts(req)
		if blocked, handled := e.applyNetworkFilters(req); handled {
			stripHopHeaders(blocked.Header)
			blocked.Header.Set("Connection", "close")
			_ = blocked.Write(tlsConn)
			if blocked.Body != nil {
				_ = blocked.Body.Close()
			}
			if req.Body != nil {
				_ = req.Body.Close()
			}
			return
		}
		e.prepareResponseScriptRequest(req)
		e.prepareCosmeticRequest(req)
		tr := &http.Transport{TLSClientConfig: &tls.Config{MinVersion: tls.VersionTLS12, ServerName: upstreamHost}, Proxy: nil, ForceAttemptHTTP2: false, DisableKeepAlives: true, TLSHandshakeTimeout: 10 * time.Second, ResponseHeaderTimeout: 20 * time.Second}
		// ResponseHeaderTimeout does not bound reading an upstream response body.
		// Give the entire upstream exchange a finite context so a server that sends
		// headers and then stalls cannot pin this MITM handler indefinitely.
		resp, cancelRequest, err := roundTripWithTimeout(tr, req, 50*time.Second)
		if err != nil {
			_ = writeError(tlsConn, 502, "Bad Gateway")
			log.Printf("upstream %s: %v", req.URL.Host, err)
			tr.CloseIdleConnections()
			return
		}
		e.applyResponseScripts(req, resp)
		e.applyCosmeticFilters(req, resp)
		stripHopHeaders(resp.Header)
		resp.Header.Set("Connection", "close")
		resp.Close = true
		err = resp.Write(tlsConn)
		if resp.Body != nil {
			resp.Body.Close()
		}
		cancelRequest()
		tr.CloseIdleConnections()
		if err != nil {
			return
		}
		if req.Body != nil {
			req.Body.Close()
		}
		return
	}
}
// roundTripWithTimeout bounds both response-header acquisition and subsequent
// response-body reads. The caller must invoke cancel when it has finished writing
// or discarding the response body.
func roundTripWithTimeout(tr *http.Transport, req *http.Request, timeout time.Duration) (*http.Response, context.CancelFunc, error) {
	ctx, cancel := context.WithTimeout(req.Context(), timeout)
	resp, err := tr.RoundTrip(req.WithContext(ctx))
	if err != nil {
		cancel()
		return nil, func() {}, err
	}
	return resp, cancel, nil
}

func writeError(w io.Writer, code int, msg string) error {
	_, err := fmt.Fprintf(w, "HTTP/1.1 %d %s\r\nConnection: close\r\nContent-Length: 0\r\n\r\n", code, msg)
	return err
}
func main() {
	mode := flag.String("mode", "status", "init-ca|rotate-ca|serve|status|validate-urlrewrite")
	manifest := flag.String("manifest", "", "URL Rewrite manifest to validate")
	dir := flag.String("dir", defaultDir, "private state directory")
	listen := flag.String("listen", "127.0.0.1:18443", "loopback-only redirect target listener")
	flag.Parse()
	switch *mode {
	case "validate-urlrewrite":
		if strings.TrimSpace(*manifest) == "" {
			log.Fatal("-manifest is required for validate-urlrewrite")
		}
		rules, err := loadURLRewriteRules(*manifest)
		if err != nil {
			fmt.Fprintf(os.Stderr, "URL Rewrite validation failed: %v\n", err)
			os.Exit(2)
		}
		fmt.Printf("{\"ok\":true,\"rules\":%d}\n", len(rules))
	case "init-ca":
		if err := secureMkdir(*dir); err != nil {
			log.Fatal(err)
		}
		cert, key, err := loadOrCreateCA(*dir)
		if err != nil {
			log.Fatal(err)
		}
		fmt.Printf("{\"ok\":true,\"ca\":%q,\"key\":%q,\"subject\":%q,\"notAfter\":%q}\n", filepath.Join(*dir, "ca.pem"), filepath.Join(*dir, "ca-key.pem"), cert.Subject.String(), cert.NotAfter.UTC().Format(time.RFC3339))
		_ = key
	case "rotate-ca":
		// Never overwrite an existing recovery pair. Rotation is explicit and
		// restores the prior pair if creating the replacement fails.
		cert, err := rotateCA(*dir)
		if err != nil {
			log.Fatal(err)
		}
		fmt.Printf("{\"ok\":true,\"rotated\":true,\"ca\":%q,\"subject\":%q,\"notAfter\":%q}\n", filepath.Join(*dir, "ca.pem"), cert.Subject.String(), cert.NotAfter.UTC().Format(time.RFC3339))
	case "status":
		// Status must be observational only: never create a missing CA or alter
		// private-key permissions just because a UI polls the status endpoint.
		c, _, err := loadExistingCA(*dir)
		if err != nil {
			fmt.Printf("{\"ok\":false,\"error\":%q}\n", err.Error())
			os.Exit(2)
		}
		fmt.Printf("{\"ok\":true,\"engine\":\"experimental-http1-mitm\",\"ca\":%q,\"notAfter\":%q,\"scope\":\"TCP TLS HTTP/1.1 only; no QUIC/pinning bypass\"}\n", filepath.Join(*dir, "ca.pem"), c.NotAfter.UTC().Format(time.RFC3339))
	case "serve":
		if err := secureMkdir(*dir); err != nil {
			log.Fatal(err)
		}
		cert, key, err := loadOrCreateCA(*dir)
		if err != nil {
			log.Fatal(err)
		}
		ln, err := net.Listen("tcp", *listen)
		if err != nil {
			log.Fatal(err)
		}
		modDir := os.Getenv("FX_MODDIR")
		e := &engine{ca: cert, key: key, certs: map[string]*tls.Certificate{}, sem: make(chan struct{}, maxConcurrentConnections), modDir: modDir}
		e.refreshScripts()
		if n := len(e.scriptSpecs()); n > 0 {
			log.Printf("loaded %d FX JavaScript request/response hooks", n)
		}
		log.Printf("HTTPS MITM engine listening on %s; HTTP/1.1 only; connection_limit=%d cache_limit=%d", *listen, maxConcurrentConnections, maxCachedCertificates)
		for {
			c, err := ln.Accept()
			if err != nil {
				log.Printf("accept: %v", err)
				continue
			}
			select {
			case e.sem <- struct{}{}:
				go func(conn net.Conn) { defer func() { <-e.sem }(); e.handle(conn) }(c)
			default:
				log.Printf("connection rejected: concurrency limit reached")
				_ = c.Close()
			}
		}
	default:
		log.Fatalf("unknown mode %q", *mode)
	}
}
