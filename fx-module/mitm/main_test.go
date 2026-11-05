package main

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"
)

func TestRoundTripWithTimeoutCancelsStalledResponseBody(t *testing.T) {
	server := http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		if f, ok := w.(http.Flusher); ok { f.Flush() }
		<-r.Context().Done()
	})}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil { t.Fatal(err) }
	defer listener.Close()
	go func() { _ = server.Serve(listener) }()
	defer server.Close()

	tr := &http.Transport{ResponseHeaderTimeout: time.Second, DisableKeepAlives: true}
	defer tr.CloseIdleConnections()
	req, err := http.NewRequest(http.MethodGet, "http://"+listener.Addr().String()+"/stall", nil)
	if err != nil { t.Fatal(err) }
	resp, cancel, err := roundTripWithTimeout(tr, req, 150*time.Millisecond)
	if err != nil { t.Fatalf("RoundTrip before headers should succeed: %v", err) }
	defer cancel()
	start := time.Now()
	_, err = io.ReadAll(resp.Body)
	_ = resp.Body.Close()
	if err == nil { t.Fatal("expected timeout while reading stalled response body") }
	if elapsed := time.Since(start); elapsed > 2*time.Second {
		t.Fatalf("stalled body was not cancelled promptly: %s", elapsed)
	}
}

func TestExecuteScriptHonorsSharedStageDeadline(t *testing.T) {
	modDir := t.TempDir()
	runner := filepath.Join(modDir, "scripts", "jsruntime", "runner.sh")
	if err := os.MkdirAll(filepath.Dir(runner), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(runner, []byte("#!/system/bin/sh\nsleep 30\n"), 0o700); err != nil {
		t.Fatal(err)
	}
	e := &engine{modDir: modDir}
	ctx, cancel := context.WithTimeout(context.Background(), 150*time.Millisecond)
	defer cancel()
	start := time.Now()
	_, err := e.executeScriptContext(ctx, scriptSpec{path: filepath.Join(modDir, "slow.js")}, scriptEvent{Stage: "request"})
	if err == nil {
		t.Fatal("expected shared stage deadline to cancel script")
	}
	if elapsed := time.Since(start); elapsed > 3*time.Second {
		t.Fatalf("script did not stop promptly after shared deadline: %s", elapsed)
	}
}

func TestBoundedBufferCapsOutputWithoutBlockingWriter(t *testing.T) {
	b := &boundedBuffer{limit: 5}
	n, err := b.Write([]byte("abcdefgh"))
	if err != nil || n != 8 {
		t.Fatalf("Write returned n=%d err=%v", n, err)
	}
	if b.String() != "abcde" || !b.truncated {
		t.Fatalf("bounded output = %q truncated=%v", b.String(), b.truncated)
	}
	// Later writes must still be drained but must not grow the retained buffer.
	if n, err = b.Write([]byte("XYZ")); err != nil || n != 3 {
		t.Fatalf("second Write returned n=%d err=%v", n, err)
	}
	if b.Len() != 5 {
		t.Fatalf("buffer exceeded limit: %d", b.Len())
	}
}

func TestScriptCancellationKillsRunnerProcessGroup(t *testing.T) {
	pidFile := filepath.Join(t.TempDir(), "child.pid")
	ctx, cancel := context.WithTimeout(context.Background(), 150*time.Millisecond)
	defer cancel()
	cmd := exec.CommandContext(ctx, "sh", "-c", "sleep 30 & echo $! > "+pidFile+"; wait")
	configureCommandProcessGroup(cmd)
	_ = cmd.Run() // Context cancellation is expected.
	data, err := os.ReadFile(pidFile)
	if err != nil {
		t.Fatalf("child PID was not recorded: %v", err)
	}
	pidText := strings.TrimSpace(string(data))
	if pidText == "" {
		t.Fatal("child PID is empty")
	}
	pid := mustAtoi(t, pidText)
	for i := 0; i < 20; i++ {
		// A killed orphan can briefly remain as a zombie while PID 1 reaps it;
		// it is no longer executing and must not fail the cancellation contract.
		if !linuxProcessIsRunning(pid) {
			return
		}
		time.Sleep(25 * time.Millisecond)
	}
	t.Fatalf("runner child process %s survived cancellation", pidText)
}

func linuxProcessIsRunning(pid int) bool {
	data, err := os.ReadFile(fmt.Sprintf("/proc/%d/stat", pid))
	if err == nil {
		fields := strings.Fields(string(data))
		if len(fields) > 2 && fields[2] == "Z" {
			return false
		}
	}
	err = syscall.Kill(pid, 0)
	return err == nil || err == syscall.EPERM
}

func mustAtoi(t *testing.T, s string) int {
	t.Helper()
	var n int
	if _, err := fmt.Sscanf(s, "%d", &n); err != nil {
		t.Fatalf("invalid PID %q: %v", s, err)
	}
	return n
}

func TestLoadScriptSpecsLoadsMoreThanThirtyTwoEnabledHooks(t *testing.T) {
	root := t.TempDir()
	const count = 40
	for i := 0; i < count; i++ {
		name := filepath.Join(root, fmt.Sprintf("script-%02d.js", i))
		source := "// FX-SCRIPT-TYPE: response\n// FX-SCRIPT-MATCH: ^https://example\\.com/.*\n$done({body: $response.body});\n"
		if err := os.WriteFile(name, []byte(source), 0600); err != nil {
			t.Fatalf("write script %d: %v", i, err)
		}
	}
	loaded := loadScriptSpecsFrom(root)
	if len(loaded) != count {
		t.Fatalf("enabled hooks silently omitted: got %d, want %d", len(loaded), count)
	}
}

func TestMITMHostnameAllowlistExactWildcardAndEmptySafety(t *testing.T) {
	if !mitmHostAllowed("api.example.com", []string{"api.example.com"}) {
		t.Fatal("exact hostname should be allowed")
	}
	if mitmHostAllowed("other.example.com", []string{"api.example.com"}) {
		t.Fatal("exact hostname entry widened to sibling host")
	}
	if !mitmHostAllowed("a.b.example.com", []string{"*.example.com"}) {
		t.Fatal("wildcard should match a subdomain")
	}
	if mitmHostAllowed("example.com", []string{"*.example.com"}) {
		t.Fatal("wildcard unexpectedly matched apex domain")
	}
	if mitmHostAllowed("api.example.com", nil) {
		t.Fatal("empty allowlist must never enable MITM")
	}
}

func TestLoadMITMHostsRejectsInvalidPatternAndDeduplicates(t *testing.T) {
	p := filepath.Join(t.TempDir(), "hosts.conf")
	if err := os.WriteFile(p, []byte("api.example.com\n*.example.org\napi.example.com\n"), 0600); err != nil {
		t.Fatal(err)
	}
	got, err := loadMITMHosts(p)
	if err != nil || len(got) != 2 {
		t.Fatalf("allowlist got=%v err=%v", got, err)
	}
	if err := os.WriteFile(p, []byte("api.*.example.com\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := loadMITMHosts(p); err == nil {
		t.Fatal("invalid wildcard pattern accepted")
	}
}

func TestReadClientHelloSNIAndReplayPrefix(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	go func() {
		c := tls.Client(client, &tls.Config{ServerName: "api.example.com", InsecureSkipVerify: true})
		_ = c.Handshake()
	}()
	prefix, sni, err := readClientHelloSNI(server)
	if err != nil {
		t.Fatal(err)
	}
	if sni != "api.example.com" {
		t.Fatalf("SNI parsed as %q", sni)
	}
	if len(prefix) < 9 || prefix[0] != 22 || prefix[5] != 1 {
		t.Fatalf("captured ClientHello prefix looks invalid: %x", prefix[:min(len(prefix), 10)])
	}
}

func TestReadNonTLSHeaderIsPreservedForPassthrough(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	defer server.Close()
	want := []byte("HELLO-PLAINTEXT")
	go func() { _, _ = client.Write(want) }()
	prefix, sni, err := readClientHelloSNI(server)
	if err != nil {
		t.Fatal(err)
	}
	if sni != "" || len(prefix) != 5 {
		t.Fatalf("non-TLS sniff result: prefix=%q sni=%q", prefix, sni)
	}
	replay := &replayConn{Conn: server, reader: io.MultiReader(strings.NewReader(string(prefix)), server)}
	got := make([]byte, len(want))
	if _, err := io.ReadFull(replay, got); err != nil {
		t.Fatal(err)
	}
	if string(got) != string(want) {
		t.Fatalf("prefix replay lost or reordered bytes: got=%q want=%q", got, want)
	}
}

func TestDeviceLocalCAAndLeaf(t *testing.T) {
	d := t.TempDir()
	ca, key, err := loadOrCreateCA(d)
	if err != nil {
		t.Fatal(err)
	}
	if !ca.IsCA || ca.KeyUsage&x509.KeyUsageCertSign == 0 {
		t.Fatal("CA constraints missing")
	}
	st, err := os.Stat(filepath.Join(d, "ca-key.pem"))
	if err != nil {
		t.Fatal(err)
	}
	if st.Mode().Perm() != 0600 {
		t.Fatalf("private key mode %o", st.Mode().Perm())
	}
	e := &engine{ca: ca, key: key, certs: map[string]*tls.Certificate{}}
	leaf, err := leafFor(e, "example.com")
	if err != nil {
		t.Fatal(err)
	}
	parsed, err := x509.ParseCertificate(leaf.Certificate[0])
	if err != nil {
		t.Fatal(err)
	}
	if len(parsed.DNSNames) != 1 || parsed.DNSNames[0] != "example.com" {
		t.Fatalf("unexpected SAN: %#v", parsed.DNSNames)
	}
	if err = parsed.CheckSignatureFrom(ca); err != nil {
		t.Fatalf("leaf not signed by local CA: %v", err)
	}
	if _, err = leafFor(e, "example.com"); err != nil {
		t.Fatal(err)
	}
	if len(e.certs) != 1 {
		t.Fatalf("leaf cache size=%d", len(e.certs))
	}
	b, err := os.ReadFile(filepath.Join(d, "ca.pem"))
	if err != nil {
		t.Fatal(err)
	}
	if p, _ := pem.Decode(b); p == nil || p.Type != "CERTIFICATE" {
		t.Fatal("invalid CA PEM")
	}
}

func TestLocalCATrustSubjectMatchesAndroidSubmodule(t *testing.T) {
	d := t.TempDir()
	ca, _, err := loadOrCreateCA(d)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := ca.Subject.String(), (pkix.Name{Country: []string{"CN"}, Organization: []string{"PrivacyGuard Project"}, CommonName: "PrivacyGuard MITM Detection CA"}).String(); got != want {
		t.Fatalf("CA subject %q does not match stable system trust subject %q", got, want)
	}
}

func TestExistingCAMismatchRejected(t *testing.T) {
	d := t.TempDir()
	_, _, err := loadOrCreateCA(d)
	if err != nil {
		t.Fatal(err)
	}
	other, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(other)})
	if err = os.WriteFile(filepath.Join(d, "ca-key.pem"), keyPEM, 0600); err != nil {
		t.Fatal(err)
	}
	if _, _, err = loadOrCreateCA(d); err == nil {
		t.Fatal("expected mismatched CA/key pair to be rejected")
	}
}

func TestInitCARefusesIncompletePairWithoutOverwritingSurvivor(t *testing.T) {
	for _, survivor := range []string{"ca.pem", "ca-key.pem"} {
		t.Run(survivor, func(t *testing.T) {
			d := t.TempDir()
			want := []byte("preserve-this-incomplete-file")
			if err := os.WriteFile(filepath.Join(d, survivor), want, 0600); err != nil {
				t.Fatal(err)
			}
			if _, _, err := loadOrCreateCA(d); err == nil {
				t.Fatal("expected incomplete CA pair to be rejected")
			}
			got, err := os.ReadFile(filepath.Join(d, survivor))
			if err != nil {
				t.Fatal(err)
			}
			if string(got) != string(want) {
				t.Fatalf("surviving CA file was overwritten: got %q", got)
			}
		})
	}
}

func TestNormalizeHostname(t *testing.T) {
	cases := []struct{ in, want string }{
		{"Example.COM.", "example.com"},
		{"example.com:443", "example.com"},
		{"[2001:db8::1]", "2001:db8::1"},
		{"2001:db8::1", "2001:db8::1"},
	}
	for _, tc := range cases {
		got, err := normalizeHostname(tc.in)
		if err != nil || got != tc.want {
			t.Errorf("normalizeHostname(%q) = %q, %v; want %q", tc.in, got, err, tc.want)
		}
	}
	for _, in := range []string{"", "bad/name", "bad host", "-bad.example", "bad..example", "example.com%2f.evil"} {
		if got, err := normalizeHostname(in); err == nil {
			t.Errorf("normalizeHostname(%q) unexpectedly accepted %q", in, got)
		}
	}
}

func TestLeafCacheIsBounded(t *testing.T) {
	d := t.TempDir()
	ca, key, err := loadOrCreateCA(d)
	if err != nil {
		t.Fatal(err)
	}
	e := &engine{ca: ca, key: key, certs: map[string]*tls.Certificate{}}
	for i := 0; i < maxCachedCertificates; i++ {
		e.certs[fmt.Sprintf("seed-%d.invalid", i)] = &tls.Certificate{}
	}
	if _, err := leafFor(e, "cache-limit-test.example"); err != nil {
		t.Fatal(err)
	}
	if len(e.certs) != maxCachedCertificates {
		t.Fatalf("cache grew beyond limit: %d", len(e.certs))
	}
}

func TestRotateCARefusesToOverwriteRecoveryPair(t *testing.T) {
	d := t.TempDir()
	ca, _, err := loadOrCreateCA(d)
	if err != nil {
		t.Fatal(err)
	}
	certPath, keyPath := filepath.Join(d, "ca.pem"), filepath.Join(d, "ca-key.pem")
	prevCert, prevKey := certPath+".previous", keyPath+".previous"
	if err = os.WriteFile(prevCert, []byte("recovery-cert"), 0600); err != nil {
		t.Fatal(err)
	}
	if err = os.WriteFile(prevKey, []byte("recovery-key"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err = rotateCA(d); err == nil {
		t.Fatal("expected rotation to refuse overwriting recovery pair")
	}
	got, err := os.ReadFile(certPath)
	if err != nil {
		t.Fatal(err)
	}
	block, _ := pem.Decode(got)
	if block == nil {
		t.Fatal("current CA was lost")
	}
	current, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatal(err)
	}
	if current.SerialNumber.Cmp(ca.SerialNumber) != 0 {
		t.Fatal("current CA changed despite refused rotation")
	}
	b, _ := os.ReadFile(prevCert)
	if string(b) != "recovery-cert" {
		t.Fatal("recovery certificate overwritten")
	}
}

func TestRotateCAKeepsPreviousPairAndCreatesNewPair(t *testing.T) {
	d := t.TempDir()
	old, _, err := loadOrCreateCA(d)
	if err != nil {
		t.Fatal(err)
	}
	cert, err := rotateCA(d)
	if err != nil {
		t.Fatal(err)
	}
	if old.SerialNumber.Cmp(cert.SerialNumber) == 0 {
		t.Fatal("rotation retained old certificate")
	}
	for _, p := range []string{"ca.pem.previous", "ca-key.pem.previous", "ca.pem", "ca-key.pem"} {
		if _, err := os.Stat(filepath.Join(d, p)); err != nil {
			t.Fatalf("expected %s: %v", p, err)
		}
	}
	if _, err := rotateCA(d); err == nil {
		t.Fatal("second rotation should refuse to overwrite previous pair")
	}
}

func TestLoadExistingCAIsReadOnlyAndDoesNotCreateMissingState(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "not-created")
	if _, _, err := loadExistingCA(missing); err == nil {
		t.Fatal("expected missing CA state to be reported")
	}
	if _, err := os.Stat(missing); !os.IsNotExist(err) {
		t.Fatalf("status loader created missing directory: %v", err)
	}

	d := t.TempDir()
	if _, _, err := loadOrCreateCA(d); err != nil {
		t.Fatal(err)
	}
	keyPath := filepath.Join(d, "ca-key.pem")
	if err := os.Chmod(keyPath, 0644); err != nil {
		t.Fatal(err)
	}
	if _, _, err := loadExistingCA(d); err != nil {
		t.Fatal(err)
	}
	st, err := os.Stat(keyPath)
	if err != nil {
		t.Fatal(err)
	}
	if st.Mode().Perm() != 0644 {
		t.Fatalf("read-only status changed key permissions: %o", st.Mode().Perm())
	}
}

func TestParseScriptSpecRequiresExplicitTypeAndMatch(t *testing.T) {
	valid, ok, err := parseScriptSpec("rewrite.js", "// FX-SCRIPT-TYPE: response\n// FX-SCRIPT-MATCH: ^https://example\\.com/\n$done({body:'ok'});\n")
	if err != nil || !ok {
		t.Fatalf("expected valid script spec, got ok=%v err=%v", ok, err)
	}
	if valid.kind != "response" || !valid.match.MatchString("https://example.com/path") || valid.match.MatchString("https://elsewhere.test/") {
		t.Fatal("script type or URL matcher incorrect")
	}
	if _, ok, err := parseScriptSpec("no-trigger.js", "$done({body:'ok'});\n"); err != nil || ok {
		t.Fatalf("script without explicit trigger must stay inactive: ok=%v err=%v", ok, err)
	}
	if _, ok, err := parseScriptSpec("bad-regex.js", "// FX-SCRIPT-TYPE: both\n// FX-SCRIPT-MATCH: [\n"); err == nil || ok {
		t.Fatalf("invalid regex must be rejected: ok=%v err=%v", ok, err)
	}
}

func TestParseScriptSpecNormalizesEscapedURLSeparatorsFromProxyModules(t *testing.T) {
	cases := []struct {
		name    string
		source  string
		matches []string
		misses  []string
	}{
		{
			name:    "Bilibili response script",
			source:  "// FX-SCRIPT-TYPE: response\n// FX-SCRIPT-MATCH: ^https?:\\/\\/app\\.bilibili\\.com\\/x\\/v2\\/feed\\/index.*\n$done({body: $response.body});\n",
			matches: []string{"https://app.bilibili.com/x/v2/feed/index", "http://app.bilibili.com/x/v2/feed/index?device=1"},
			misses:  []string{"https://api.bilibili.com/x/v2/feed/index", "https://app.bilibili.com/x/v2/account/mine"},
		},
		{
			name:    "Aloha response script",
			source:  "// FX-SCRIPT-TYPE: response\n// FX-SCRIPT-MATCH: ^https?:\\/\\/api\\.alohaprofile\\.com\\/v1/profile_info$\n$done({body: $response.body});\n",
			matches: []string{"https://api.alohaprofile.com/v1/profile_info"},
			misses:  []string{"https://api.alohaprofile.com/v1/profile_info/extra", "https://evil.example/v1/profile_info"},
		},
		{
			name:    "double-escaped Bilibili module metadata",
			source:  "// FX-SCRIPT-TYPE: response\n// FX-SCRIPT-MATCH: ^https?:\\\\/\\\\/app\\\\.bilibili\\\\.com\\\\/x\\\\/v2\\\\/feed\\\\/index.*\n$done({body: $response.body});\n",
			matches: []string{"https://app.bilibili.com/x/v2/feed/index", "http://app.bilibili.com/x/v2/feed/index?device=1"},
			misses:  []string{"https://api.bilibili.com/x/v2/feed/index", "https://app.bilibili.com/x/v2/account/mine"},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			spec, ok, err := parseScriptSpec(tc.name+".js", tc.source)
			if err != nil || !ok {
				t.Fatalf("script spec rejected: ok=%v err=%v", ok, err)
			}
			for _, value := range tc.matches {
				if !spec.match.MatchString(value) {
					t.Errorf("normalized pattern %q did not match %q", spec.match.String(), value)
				}
			}
			for _, value := range tc.misses {
				if spec.match.MatchString(value) {
					t.Errorf("pattern %q unexpectedly matched %q", spec.match.String(), value)
				}
			}
		})
	}
}

func TestPatchHeadersRejectsCRLFInjection(t *testing.T) {
	h := http.Header{}
	if err := patchHeaders(h, json.RawMessage(`{"X-Good":"yes","X-Bad":"a\r\nb"}`)); err != nil {
		t.Fatal(err)
	}
	if h.Get("X-Good") != "yes" {
		t.Fatal("valid header was not applied")
	}
	if h.Get("X-Bad") != "" {
		t.Fatal("CRLF header value was applied")
	}
}

func TestPatchHeadersRejectsRuntimeManagedHeaders(t *testing.T) {
	h := http.Header{}
	err := patchHeaders(h, json.RawMessage(`{"X-FX":"ok","Content-Length":"1","Transfer-Encoding":"chunked","Content-Encoding":"gzip","Connection":"close","Host":"evil.example"}`))
	if err == nil || !strings.Contains(err.Error(), "runtime-managed headers") {
		t.Fatalf("expected rejected managed headers to be diagnosed, got %v", err)
	}
	if h.Get("X-FX") != "ok" {
		t.Fatal("safe script header did not apply alongside rejected headers")
	}
	for _, name := range []string{"Content-Length", "Transfer-Encoding", "Content-Encoding", "Connection", "Host"} {
		if got := h.Get(name); got != "" {
			t.Fatalf("script was allowed to set runtime-managed header %s=%q", name, got)
		}
	}
}

func TestResponseScriptCannotCorruptHTTPFramingHeaders(t *testing.T) {
	patch, _ := json.Marshal(map[string]any{"headers": map[string]string{
		"Content-Length": "1", "Transfer-Encoding": "chunked", "Content-Encoding": "gzip", "Connection": "close", "X-Script": "ok",
	}})
	output, _ := json.Marshal(map[string]any{"ok": true, "done": true, "result": json.RawMessage(patch)})
	e := testScriptEngine(t, string(output), "response")
	req, err := http.NewRequest(http.MethodGet, "https://example.com/api", nil)
	if err != nil {
		t.Fatal(err)
	}
	body := "unmodified response body"
	resp := &http.Response{StatusCode: http.StatusOK, Status: "200 OK", Header: http.Header{
		"Content-Type": []string{"text/plain"}, "Content-Length": []string{fmt.Sprint(len(body))},
	}, Body: io.NopCloser(strings.NewReader(body)), ContentLength: int64(len(body))}
	e.applyResponseScripts(req, resp)
	gotBody, err := io.ReadAll(resp.Body)
	if err != nil || string(gotBody) != body {
		t.Fatalf("response body was changed/corrupted: body=%q err=%v", gotBody, err)
	}
	if resp.Header.Get("Content-Length") != fmt.Sprint(len(body)) || resp.ContentLength != int64(len(body)) {
		t.Fatalf("script corrupted Content-Length: headers=%v contentLength=%d", resp.Header, resp.ContentLength)
	}
	if resp.Header.Get("Transfer-Encoding") != "" || resp.Header.Get("Content-Encoding") != "" || resp.Header.Get("Connection") != "" {
		t.Fatalf("script changed managed framing headers: %v", resp.Header)
	}
	if resp.Header.Get("X-Script") != "ok" {
		t.Fatal("safe custom header was not applied")
	}
}

func TestParseScriptSpecSupportsCommonUserscriptURLGlobs(t *testing.T) {
	spec, ok, err := parseScriptSpec("common.js", "// @name Example\n// @match https://example.com/*\n// @include https://api.example.org/v1/*\n$done({body:'ok'});\n")
	if err != nil || !ok {
		t.Fatalf("expected supported @match metadata, ok=%v err=%v", ok, err)
	}
	if spec.kind != "both" || !spec.match.MatchString("https://example.com/a") || !spec.match.MatchString("https://api.example.org/v1/items") || spec.match.MatchString("https://evil.example.com/a") {
		t.Fatalf("URL glob matching is incorrect: kind=%s pattern=%s", spec.kind, spec.match.String())
	}
}

func TestManagedScriptRequiresMatchingSHA256Manifest(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "pgsub_123.js")
	body := []byte(`// FX-SCRIPT-TYPE: request
// FX-SCRIPT-MATCH: ^https://example\.com/
$done({});
`)
	if err := os.WriteFile(path, body, 0600); err != nil {
		t.Fatal(err)
	}
	if validManagedScriptHash(path) {
		t.Fatal("managed subscription without manifest must not be trusted")
	}
	sum := sha256.Sum256(body)
	manifest := fmt.Sprintf("%x  %s\n", sum, filepath.Base(path))
	if err := os.WriteFile(path+".sha256", []byte(manifest), 0600); err != nil {
		t.Fatal(err)
	}
	if !validManagedScriptHash(path) {
		t.Fatal("valid SHA-256 manifest rejected")
	}
	if err := os.WriteFile(path, append(body, []byte("// tampered\n")...), 0600); err != nil {
		t.Fatal(err)
	}
	if validManagedScriptHash(path) {
		t.Fatal("tampered managed subscription accepted")
	}
}

func TestLoadScriptSpecsFromDirectoryFiltersUnsafeOrUntriggeredFiles(t *testing.T) {
	root := t.TempDir()
	valid := "// FX-SCRIPT-TYPE: both\n// FX-SCRIPT-MATCH: ^https://example\\.com/\n$done({body:'ok'});\n"
	if err := os.WriteFile(filepath.Join(root, "valid.js"), []byte(valid), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "untriggered.js"), []byte("$done({body:'no'});\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "bad-regex.js"), []byte("// FX-SCRIPT-TYPE: request\n// FX-SCRIPT-MATCH: [\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(root, "folder.js"), 0700); err != nil {
		t.Fatal(err)
	}
	got := loadScriptSpecsFrom(root)
	if len(got) != 1 {
		t.Fatalf("loaded %d hooks, want only valid triggered script: %#v", len(got), got)
	}
	if filepath.Base(got[0].path) != "valid.js" || got[0].kind != "both" || !got[0].match.MatchString("https://example.com/path") {
		t.Fatalf("unexpected loaded hook: %#v", got[0])
	}
}

func TestScriptSpecsSnapshotIsRaceSafe(t *testing.T) {
	e := &engine{}
	e.scripts = []scriptSpec{{path: "one.js", kind: "request", match: regexp.MustCompile("example")}}
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			for n := 0; n < 100; n++ {
				e.scriptMu.Lock()
				e.scripts = []scriptSpec{{path: fmt.Sprintf("%d.js", i), kind: "request", match: regexp.MustCompile("example")}}
				e.scriptMu.Unlock()
				_ = e.scriptSpecs()
			}
		}(i)
	}
	wg.Wait()
}

func testScriptEngine(t *testing.T, output string, kind string) *engine {
	t.Helper()
	modDir := t.TempDir()
	runner := filepath.Join(modDir, "scripts", "jsruntime", "runner.sh")
	if err := os.MkdirAll(filepath.Dir(runner), 0700); err != nil {
		t.Fatal(err)
	}
	quoted := strings.ReplaceAll(output, "'", "'\\''")
	body := "#!/bin/sh\nprintf '%s\\n' '" + quoted + "'\n"
	if err := os.WriteFile(runner, []byte(body), 0700); err != nil {
		t.Fatal(err)
	}
	return &engine{modDir: modDir, scripts: []scriptSpec{{path: "fixture.js", kind: kind, match: regexp.MustCompile(`^https://example\.com/`)}}}
}

func TestRequestScriptPatchAppliedToLiveRequest(t *testing.T) {
	patch, _ := json.Marshal(map[string]any{"headers": map[string]string{"X-FX-Script": "active"}, "body": `{"x":2}`})
	output, _ := json.Marshal(map[string]any{"ok": true, "done": true, "result": json.RawMessage(patch)})
	e := testScriptEngine(t, string(output), "request")
	req, err := http.NewRequest(http.MethodPost, "https://example.com/api", strings.NewReader(`{"x":1}`))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	e.applyRequestScripts(req)
	if req.Header.Get("X-FX-Script") != "active" {
		t.Fatal("request header patch was not applied")
	}
	got, err := io.ReadAll(req.Body)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != `{"x":2}` {
		t.Fatalf("request body patch = %q", got)
	}
	if req.ContentLength != int64(len(got)) {
		t.Fatalf("content length not updated: %d vs %d", req.ContentLength, len(got))
	}
}

func TestRequestScriptDoesNotAddContentLengthToBodylessRequest(t *testing.T) {
	patch, _ := json.Marshal(map[string]any{"headers": map[string]string{"X-FX-Script": "active"}})
	output, _ := json.Marshal(map[string]any{"ok": true, "done": true, "result": json.RawMessage(patch)})
	e := testScriptEngine(t, string(output), "request")
	req, err := http.NewRequest(http.MethodGet, "https://example.com/api", nil)
	if err != nil {
		t.Fatal(err)
	}
	e.applyRequestScripts(req)
	if req.Header.Get("Content-Length") != "" {
		t.Fatalf("bodyless GET gained Content-Length: %q", req.Header.Get("Content-Length"))
	}
	if req.ContentLength != 0 {
		t.Fatalf("bodyless GET ContentLength changed to %d", req.ContentLength)
	}
	if req.Body != nil && req.Body != http.NoBody {
		t.Fatal("bodyless GET unexpectedly gained a request body")
	}
	if req.Header.Get("X-FX-Script") != "active" {
		t.Fatal("request hook header patch was not applied")
	}
}

func TestPrepareResponseScriptRequestRequestsIdentityEncoding(t *testing.T) {
	e := &engine{scripts: []scriptSpec{{kind: "response", match: regexp.MustCompile(`^https://example\.com/`)}}}
	req, err := http.NewRequest(http.MethodGet, "https://example.com/api", nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Accept-Encoding", "gzip, br")
	e.prepareResponseScriptRequest(req)
	if got := req.Header.Get("Accept-Encoding"); got != "identity" {
		t.Fatalf("Accept-Encoding = %q, want identity for body-capable response hook", got)
	}
}

func TestResponseBodyNegotiationUsesRequestHookUpdatedURL(t *testing.T) {
	patch, _ := json.Marshal(map[string]any{"url": "https://example.com/body/api"})
	output, _ := json.Marshal(map[string]any{"ok": true, "done": true, "result": json.RawMessage(patch)})
	e := testScriptEngine(t, string(output), "request")
	e.scripts = append(e.scripts, scriptSpec{path: "response.js", kind: "response", match: regexp.MustCompile(`^https://example\.com/body/`)})
	req, err := http.NewRequest(http.MethodGet, "https://example.com/no-body-hook", nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Accept-Encoding", "gzip, br")
	e.applyRequestScripts(req)
	e.prepareResponseScriptRequest(req)
	if req.URL.Path != "/body/api" {
		t.Fatalf("request hook URL = %q", req.URL.String())
	}
	if got := req.Header.Get("Accept-Encoding"); got != "identity" {
		t.Fatalf("Accept-Encoding = %q, want identity for response hook on updated URL", got)
	}
}

func TestPrepareResponseScriptRequestLeavesUnmatchedTrafficAlone(t *testing.T) {
	e := &engine{scripts: []scriptSpec{{kind: "response", match: regexp.MustCompile(`^https://example\.com/private`)}}}
	req, err := http.NewRequest(http.MethodGet, "https://example.com/public", nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Accept-Encoding", "gzip, br")
	e.prepareResponseScriptRequest(req)
	if got := req.Header.Get("Accept-Encoding"); got != "gzip, br" {
		t.Fatalf("unmatched traffic Accept-Encoding changed: %q", got)
	}
}

func TestResponseScriptPatchAppliedToLiveResponse(t *testing.T) {
	patch, _ := json.Marshal(map[string]any{"statusCode": 201, "headers": map[string]string{"X-FX-Script": "active"}, "body": `{"ok":true}`})
	output, _ := json.Marshal(map[string]any{"ok": true, "done": true, "result": json.RawMessage(patch)})
	e := testScriptEngine(t, string(output), "response")
	req, err := http.NewRequest(http.MethodGet, "https://example.com/api", nil)
	if err != nil {
		t.Fatal(err)
	}
	resp := &http.Response{StatusCode: 200, Status: "200 OK", Header: http.Header{"Content-Type": []string{"application/json"}}, Body: io.NopCloser(strings.NewReader(`{"ok":false}`)), ContentLength: 12}
	e.applyResponseScripts(req, resp)
	if resp.StatusCode != 201 || resp.Header.Get("X-FX-Script") != "active" {
		t.Fatal("response status/header patch was not applied")
	}
	got, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != `{"ok":true}` {
		t.Fatalf("response body patch = %q", got)
	}
	if resp.Header.Get("Content-Encoding") != "" {
		t.Fatal("stale content encoding remained after body rewrite")
	}
}

func TestCosmeticHostMatchesBoundaries(t *testing.T) {
	if !cosmeticHostMatches("m.example.com", "example.com") {
		t.Fatal("expected subdomain match")
	}
	if !cosmeticHostMatches("example.com", "example.com") {
		t.Fatal("expected exact match")
	}
	if cosmeticHostMatches("notexample.com", "example.com") {
		t.Fatal("suffix without label boundary must not match")
	}
}

func TestCosmeticStrongAdIdentifiersSupportAdultUpstreamsWithoutAddressFalsePositives(t *testing.T) {
	for _, selector := range []string{"#addesktop", "#admobileoutstream", ".adsnative", ".adv-sidebar", ".adContainer"} {
		if !cosmeticSelectorContentSafe(selector, "display:none!important") {
			t.Fatalf("known ad-slot identifier from adult upstream should be eligible: %q", selector)
		}
	}
	for _, selector := range []string{"#address", ".adventure-list", "#addiction", "article"} {
		if cosmeticSelectorContentSafe(selector, "display:none!important") {
			t.Fatalf("ordinary word/content surface must not be hidden by ad-name heuristic: %q", selector)
		}
	}
}

func TestCosmeticParserAcceptsAdultSpecificSelectorsButPreservesContentSelectors(t *testing.T) {
	lines := []byte(`eporner.com###addesktop
eporner.com###admobileoutstream
xnxx.com##.ad-footer
eporner.com##.commentdiv
eporner.com##.video-related
`)
	rules := parseCosmeticRules(lines, map[string]bool{}, 20)
	if len(rules) != 3 {
		t.Fatalf("expected only the three ad-specific selectors; got %d: %#v", len(rules), rules)
	}
}

func TestCosmeticRulesSupportStandardSelectorsAndRejectInjection(t *testing.T) {
	for _, s := range []string{".splash-ad", ".__water_mark__", "body .splash", "[class*=watermark]", "div > .ad-slot", "#x,body", `div[style^="left: calc"]`, `a[href^="https://"]:not(.content)`} {
		if _, _, ok := sanitizeCosmeticSelector(s); !ok {
			t.Fatalf("standard CSS selector should be accepted: %q", s)
		}
	}
	for _, s := range []string{"div{display:none}", `x</style><script>alert(1)</script>`, `div:style(background-image:url(https://evil))`, `div:style(position:fixed;z-index:999999)`} {
		if _, _, ok := sanitizeCosmeticSelector(s); ok {
			t.Fatalf("unsafe selector/style accepted: %q", s)
		}
	}
}

func TestCosmeticStyleModifierAndDomainExceptions(t *testing.T) {
	selector, declarations, ok := sanitizeCosmeticSelector(`div[class*="watermark_"]:style(background-image:none!important)`)
	if !ok || selector != `div[class*="watermark_"]` || declarations != "background-image:none!important" {
		t.Fatalf("unexpected :style parse: selector=%q declarations=%q ok=%v", selector, declarations, ok)
	}
	if !cosmeticHostMatches("www.example.com", "example.com,~bad.example.com") {
		t.Fatal("positive domain should match with unrelated exclusion")
	}
	if cosmeticHostMatches("sub.example.com", "example.com,~sub.example.com") {
		t.Fatal("negative domain must override a matching positive domain")
	}
	if !cosmeticHostMatches("360.com", "360.*") {
		t.Fatal("whole-label wildcard should match")
	}
}

func TestCosmeticParserSkipsProceduralRulesButKeepsAttributesAndExceptions(t *testing.T) {
	lines := []byte("example.com##div[class*=watermark]:style(background-image:none!important)\nexample.com#@#.legitimate-content\nexample.com##div:has-text(ad)\nexample.com##.lower-canvas\nexample.com##.player-mask\nexample.com##div:style(background-image:none!important)\n")
	rules := parseCosmeticRules(lines, map[string]bool{}, 20)
	if len(rules) != 2 {
		t.Fatalf("expected one targeted CSS rule and one exception; got %d", len(rules))
	}
	if rules[0].selector != "div[class*=watermark]" || rules[0].declarations != "background-image:none!important" || rules[1].exception != true {
		t.Fatalf("unexpected parsed rules: %#v", rules)
	}
}

func TestCosmeticSelectorListsCannotSmuggleBroadContentRoots(t *testing.T) {
	if cosmeticSelectorContentSafe("#ad-slot, body", "display:none!important") {
		t.Fatal("combined selector must not hide body with an otherwise targeted selector")
	}
	if cosmeticSelectorContentSafe(".ad-slot, article", "display:none!important") {
		t.Fatal("combined selector must not hide article content")
	}
	if !cosmeticSelectorContentSafe(`.ad-slot, [class*="ad,banner"]`, "display:none!important") {
		t.Fatal("commas inside attribute strings must not be treated as separate selector groups")
	}
	if !cosmeticSelectorContentSafe(`div:not(.notice,.floating) .ad-overlay`, "display:none!important") {
		t.Fatal("commas nested inside pseudo-class parentheses should remain in one safe selector group")
	}
}

func TestCosmeticBodyLimitPreservesWholeOversizedHTML(t *testing.T) {
	tmp := t.TempDir()
	pg := filepath.Join(tmp, "pg")
	if err := os.MkdirAll(pg, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(pg, "settings.conf"), []byte("[list:rule]\nbuiltin://Adblock_Watermark.txt|watermark|1\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PG", pg)
	original := "<html><head></head><body>" + strings.Repeat("x", cosmeticBodyLimit+4096) + "</body></html>"
	req, _ := http.NewRequest(http.MethodGet, "https://example.com/large", nil)
	resp := &http.Response{StatusCode: 200, Header: http.Header{"Content-Type": []string{"text/html"}}, ContentLength: int64(len(original)), Body: io.NopCloser(strings.NewReader(original))}
	(&engine{}).applyCosmeticFilters(req, resp)
	got, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != original {
		t.Fatalf("oversized HTML was altered/truncated: got=%d want=%d", len(got), len(original))
	}
}

func TestPrepareCosmeticRequestUsesIdentityOnlyForEnabledHTMLDocuments(t *testing.T) {
	tmp := t.TempDir()
	pg := filepath.Join(tmp, "pg")
	if err := os.MkdirAll(pg, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(pg, "settings.conf"), []byte("[list:rule]\nbuiltin://Adblock_Watermark.txt|watermark|1\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PG", pg)
	e := &engine{}
	doc, _ := http.NewRequest(http.MethodGet, "https://example.com/", nil)
	doc.Header.Set("Accept", "text/html,application/xhtml+xml")
	doc.Header.Set("Accept-Encoding", "gzip, br, zstd")
	e.prepareCosmeticRequest(doc)
	if got := doc.Header.Get("Accept-Encoding"); got != "identity" {
		t.Fatalf("document encoding = %q", got)
	}
	asset, _ := http.NewRequest(http.MethodGet, "https://example.com/image.png", nil)
	asset.Header.Set("Accept", "image/avif,image/webp,*/*")
	asset.Header.Set("Accept-Encoding", "gzip, br")
	e.prepareCosmeticRequest(asset)
	if got := asset.Header.Get("Accept-Encoding"); got != "gzip, br" {
		t.Fatalf("non-document encoding unexpectedly changed: %q", got)
	}
}

func TestCosmeticRulesDoNotHideMediaOrBroadContentSurfaces(t *testing.T) {
	for _, selector := range []string{".lower-canvas", ".upper-canvas", ".player-mask", "video", "article", "div"} {
		if cosmeticSelectorContentSafe(selector, "display:none!important") {
			t.Fatalf("broad media/content surface should be retained: %q", selector)
		}
	}
	for _, selector := range []string{".txp-watermark", ".ad-overlay", "div[class*=watermark]"} {
		if !cosmeticSelectorContentSafe(selector, "display:none!important") {
			t.Fatalf("targeted ad/watermark overlay should remain eligible: %q", selector)
		}
	}
}

func TestEnabledRemoteCosmeticSourceUsesVerifiedSubscriptionCache(t *testing.T) {
	tmp := t.TempDir()
	mod := filepath.Join(tmp, "module")
	pg := filepath.Join(tmp, "pg")
	for _, d := range []string{filepath.Join(mod, "rulefiles"), filepath.Join(pg, "cache", "rules")} {
		if err := os.MkdirAll(d, 0700); err != nil {
			t.Fatal(err)
		}
	}
	url := "https://rules.example.invalid/cosmetic.txt"
	if err := os.WriteFile(filepath.Join(pg, "settings.conf"), []byte("[list:rule]\n"+url+"|remote css|1\n"), 0600); err != nil {
		t.Fatal(err)
	}
	data := []byte("example.invalid##div[class*=watermark]:style(background-image:none!important)\n")
	key := cksumURLKey(url)
	if key == "" {
		t.Fatal("cksum utility required by the Android module should be available in test environment")
	}
	cache := filepath.Join(pg, "cache", "rules", key)
	if err := os.WriteFile(cache, data, 0600); err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(data)
	if err := os.WriteFile(cache+".sha256", []byte(hex.EncodeToString(sum[:])+"  "+key+"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PG", pg)
	e := &engine{modDir: mod}
	rules := e.loadCosmeticRules()
	if len(rules) != 1 || rules[0].selector != "div[class*=watermark]" {
		t.Fatalf("remote CSS not loaded from verified cache: %#v", rules)
	}
	if err := os.WriteFile(cache+".sha256", []byte(strings.Repeat("0", 64)), 0600); err != nil {
		t.Fatal(err)
	}
	e.cosmeticLoadedAt = time.Time{}
	if got := e.loadCosmeticRules(); len(got) != 0 {
		t.Fatalf("unverified remote CSS cache must be ignored: %#v", got)
	}
}

func TestCosmeticFilterInjectsOnlyEnabledRules(t *testing.T) {
	tmp := t.TempDir()
	mod := filepath.Join(tmp, "module")
	pg := filepath.Join(tmp, "pg")
	if err := os.MkdirAll(filepath.Join(mod, "rulefiles"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(pg, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(pg, "settings.conf"), []byte("[list:rule]\nbuiltin://NoAppDownload.txt|test|1\nbuiltin://Adblock_Watermark.txt|test|0\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(mod, "rulefiles", "NoAppDownload.txt"), []byte("##.splash-ad\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(mod, "rulefiles", "Adblock_Watermark.txt"), []byte("##.watermark\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PG", pg)
	e := &engine{modDir: mod}
	req, _ := http.NewRequest("GET", "https://example.com/", nil)
	resp := &http.Response{StatusCode: 200, Header: http.Header{"Content-Type": []string{"text/html; charset=utf-8"}}, ContentLength: int64(len("<html><head></head><body>x</body></html>")), Body: io.NopCloser(strings.NewReader("<html><head></head><body>x</body></html>"))}
	e.applyCosmeticFilters(req, resp)
	got, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(got), ".splash-ad{display:none!important") {
		t.Fatalf("enabled cosmetic selector not injected: %s", got)
	}
	if strings.Contains(string(got), ".watermark{display:none!important") {
		t.Fatalf("disabled source was injected: %s", got)
	}
}

func TestAdultSiteCosmeticRulesLoadOnlyWhenRegisteredAndRemainHostScoped(t *testing.T) {
	tmp := t.TempDir()
	mod := filepath.Join(tmp, "module")
	pg := filepath.Join(tmp, "pg")
	for _, d := range []string{filepath.Join(mod, "rulefiles"), pg} {
		if err := os.MkdirAll(d, 0700); err != nil {
			t.Fatal(err)
		}
	}
	conf := "[list:rule]\nbuiltin://AdultSite_AdPopup.txt|adult ads|1\nbuiltin://Adblock_Warning_Removal.txt|warnings|0\n"
	if err := os.WriteFile(filepath.Join(pg, "settings.conf"), []byte(conf), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(mod, "rulefiles", "AdultSite_AdPopup.txt"), []byte("pornhub.com##.ad-overlay\nxvideos.com##.ad-container\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(mod, "rulefiles", "Adblock_Warning_Removal.txt"), []byte("pornhub.com##.adblock-overlay\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PG", pg)
	e := &engine{modDir: mod}
	if got := e.loadCosmeticRules(); len(got) != 2 {
		t.Fatalf("expected 2 registered adult selectors, got %d", len(got))
	}
	resp := &http.Response{StatusCode: 200, Header: http.Header{"Content-Type": []string{"text/html"}}, Body: io.NopCloser(strings.NewReader("<html><head></head><body>content</body></html>"))}
	req, _ := http.NewRequest("GET", "https://pornhub.com/video", nil)
	e.applyCosmeticFilters(req, resp)
	b, _ := io.ReadAll(resp.Body)
	got := string(b)
	if !strings.Contains(got, ".ad-overlay{display:none!important") {
		t.Fatalf("expected adult ad slot CSS injection: %s", got)
	}
	if strings.Contains(got, ".adblock-overlay{display:none!important") {
		t.Fatal("disabled anti-adblock source was applied")
	}
	if !strings.Contains(got, "content") {
		t.Fatal("main page content was lost")
	}
	resp2 := &http.Response{StatusCode: 200, Header: http.Header{"Content-Type": []string{"text/html"}}, Body: io.NopCloser(strings.NewReader("<html><head></head><body>content</body></html>"))}
	req2, _ := http.NewRequest("GET", "https://notpornhub.com/video", nil)
	e.applyCosmeticFilters(req2, resp2)
	b2, _ := io.ReadAll(resp2.Body)
	if strings.Contains(string(b2), ".ad-overlay{display:none!important") {
		t.Fatal("adult site rule leaked to a non-matching hostname")
	}
}

func TestURLRewriteActionsStayPathScoped(t *testing.T) {
	d := t.TempDir()
	path := filepath.Join(d, "url-rewrite.conf")
	cfg := "^https://app\\.bilibili\\.com/x/resource/ip - reject\n(^https://app\\.bilibili\\.com/api/.*)([?&]foo=1)(.*) - 302$1$3\n^https://manga\\.bilibili\\.com/twirp/comic - reject-array\n"
	if err := os.WriteFile(path, []byte(cfg), 0600); err != nil {
		t.Fatal(err)
	}
	rules, err := loadURLRewriteRules(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(rules) != 3 {
		t.Fatalf("got %d rules", len(rules))
	}
	mk := func(raw string) *http.Request {
		u, _ := url.Parse(raw)
		return &http.Request{URL: u, Header: make(http.Header)}
	}
	req := mk("https://app.bilibili.com/x/resource/ip")
	resp, ok := applyURLRewrite(req, rules)
	if !ok || resp.StatusCode != http.StatusForbidden {
		t.Fatalf("reject action not applied: ok=%v resp=%v", ok, resp)
	}
	req = mk("https://app.bilibili.com/video/BV123")
	if _, ok := applyURLRewrite(req, rules); ok {
		t.Fatal("path-scoped reject matched unrelated path")
	}
	req = mk("https://app.bilibili.com/api/foo?foo=1&bar=2")
	resp, ok = applyURLRewrite(req, rules)
	if !ok || resp.StatusCode != http.StatusFound || resp.Header.Get("Location") != "https://app.bilibili.com/api/foo&bar=2" {
		t.Fatalf("capture-group redirect mismatch: ok=%v resp=%v location=%q", ok, resp, resp.Header.Get("Location"))
	}
	req = mk("https://manga.bilibili.com/twirp/comic")
	resp, ok = applyURLRewrite(req, rules)
	if !ok || resp.StatusCode != 200 || string(readTestBody(t, resp.Body)) != "[]" {
		t.Fatal("reject-array response not produced")
	}
}

func readTestBody(t *testing.T, r io.Reader) []byte {
	t.Helper()
	b, err := io.ReadAll(r)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func TestMalformedURLRewriteManifestFailsOpenForForwarding(t *testing.T) {
	path := filepath.Join(t.TempDir(), "url-rewrite.conf")
	if err := os.WriteFile(path, []byte("(broken - reject\n"), 0600); err != nil {
		t.Fatal(err)
	}
	rules := loadURLRewriteRulesOrEmpty(path)
	req, err := http.NewRequest(http.MethodGet, "https://example.com/api", nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, handled := applyURLRewrite(req, rules); handled {
		t.Fatal("malformed rewrite manifest must not synthesize a blocking response")
	}
}

func TestResponseHookDoesNotRewriteHeadContentLength(t *testing.T) {
	patch, _ := json.Marshal(map[string]any{"body": `{"injected":true}`})
	output, _ := json.Marshal(map[string]any{"ok": true, "done": true, "result": json.RawMessage(patch)})
	e := testScriptEngine(t, string(output), "response")
	req, err := http.NewRequest(http.MethodHead, "https://example.com/api", nil)
	if err != nil {
		t.Fatal(err)
	}
	resp := &http.Response{StatusCode: http.StatusOK, Status: "200 OK", Header: http.Header{"Content-Type": []string{"application/json"}, "Content-Length": []string{"1234"}}, Body: http.NoBody, ContentLength: 1234}
	e.applyResponseScripts(req, resp)
	if got := resp.Header.Get("Content-Length"); got != "1234" {
		t.Fatalf("HEAD Content-Length changed to %q", got)
	}
	if resp.ContentLength != 1234 {
		t.Fatalf("HEAD ContentLength changed to %d", resp.ContentLength)
	}
	b, err := io.ReadAll(resp.Body)
	if err != nil || len(b) != 0 {
		t.Fatalf("HEAD body should remain empty: %q, %v", b, err)
	}
}

func TestResponseHookCannotEditCompressedBodyAndPreservesEncoding(t *testing.T) {
	patch, _ := json.Marshal(map[string]any{"body": "rewritten"})
	output, _ := json.Marshal(map[string]any{"ok": true, "done": true, "result": json.RawMessage(patch)})
	e := testScriptEngine(t, string(output), "response")
	req, err := http.NewRequest(http.MethodGet, "https://example.com/api", nil)
	if err != nil {
		t.Fatal(err)
	}
	original := []byte("compressed-wire-bytes")
	resp := &http.Response{StatusCode: http.StatusOK, Status: "200 OK", Header: http.Header{"Content-Type": []string{"text/plain"}, "Content-Encoding": []string{"gzip"}, "Content-Length": []string{fmt.Sprint(len(original))}}, Body: io.NopCloser(strings.NewReader(string(original))), ContentLength: int64(len(original))}
	e.applyResponseScripts(req, resp)
	got, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != string(original) {
		t.Fatalf("compressed body was modified: %q", got)
	}
	if resp.Header.Get("Content-Encoding") != "gzip" || resp.Header.Get("Content-Length") != fmt.Sprint(len(original)) || resp.ContentLength != int64(len(original)) {
		t.Fatalf("compressed representation metadata changed: headers=%v length=%d", resp.Header, resp.ContentLength)
	}
}

func TestLoadScriptSpecsUsesPGStateDirectory(t *testing.T) {
	pg := t.TempDir()
	root := filepath.Join(pg, "jsruntime", "scripts")
	if err := os.MkdirAll(root, 0700); err != nil {
		t.Fatal(err)
	}
	source := "// FX-SCRIPT-TYPE: request\n// FX-SCRIPT-MATCH: ^https://example\\.com/\n$done({});\n"
	if err := os.WriteFile(filepath.Join(root, "local.js"), []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PG", pg)
	got := loadScriptSpecs("/some/module/path")
	if len(got) != 1 || filepath.Base(got[0].path) != "local.js" {
		t.Fatalf("loadScriptSpecs did not use PG state path: %#v", got)
	}
}

func TestResponseHookChangingStatusToNoContentDoesNotInjectBody(t *testing.T) {
	patch, _ := json.Marshal(map[string]any{"statusCode": http.StatusNoContent, "body": "must-not-appear"})
	output, _ := json.Marshal(map[string]any{"ok": true, "done": true, "result": json.RawMessage(patch)})
	e := testScriptEngine(t, string(output), "response")
	req, err := http.NewRequest(http.MethodGet, "https://example.com/api", nil)
	if err != nil {
		t.Fatal(err)
	}
	original := "original-body"
	resp := &http.Response{StatusCode: http.StatusOK, Status: "200 OK", Header: http.Header{"Content-Type": []string{"text/plain"}, "Content-Length": []string{fmt.Sprint(len(original))}}, Body: io.NopCloser(strings.NewReader(original)), ContentLength: int64(len(original))}
	e.applyResponseScripts(req, resp)
	got, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusNoContent || len(got) != 0 {
		t.Fatalf("invalid no-content result: status=%d body=%q", resp.StatusCode, got)
	}
	if resp.Header.Get("Content-Length") != "" || resp.Header.Get("Transfer-Encoding") != "" || resp.ContentLength != 0 {
		t.Fatalf("no-content response retained framing metadata: headers=%v length=%d", resp.Header, resp.ContentLength)
	}
}

func TestResponseHookResetContentNeverForwardsBody(t *testing.T) {
	patch, _ := json.Marshal(map[string]any{"statusCode": http.StatusResetContent, "body": "must-not-appear"})
	output, _ := json.Marshal(map[string]any{"ok": true, "done": true, "result": json.RawMessage(patch)})
	e := testScriptEngine(t, string(output), "response")
	req, err := http.NewRequest(http.MethodGet, "https://example.com/api", nil)
	if err != nil {
		t.Fatal(err)
	}
	resp := &http.Response{StatusCode: http.StatusOK, Status: "200 OK", Header: http.Header{"Content-Type": []string{"text/plain"}, "Content-Length": []string{"8"}}, Body: io.NopCloser(strings.NewReader("original")), ContentLength: 8}
	e.applyResponseScripts(req, resp)
	got, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusResetContent || len(got) != 0 {
		t.Fatalf("invalid reset-content result: status=%d body=%q", resp.StatusCode, got)
	}
	if resp.Header.Get("Content-Length") != "" || resp.Header.Get("Transfer-Encoding") != "" || resp.Header.Get("Trailer") != "" || resp.ContentLength != 0 || len(resp.TransferEncoding) != 0 || resp.Trailer != nil {
		t.Fatalf("reset-content response retained framing metadata: headers=%v length=%d transfer=%v trailer=%v", resp.Header, resp.ContentLength, resp.TransferEncoding, resp.Trailer)
	}
}

func TestTLSPassthroughPreservesResponseAfterHalfClose(t *testing.T) {
	upstreamListener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer upstreamListener.Close()
	upstreamDone := make(chan error, 1)
	go func() {
		conn, err := upstreamListener.Accept()
		if err != nil {
			upstreamDone <- err
			return
		}
		defer conn.Close()
		request, err := io.ReadAll(conn)
		if err != nil {
			upstreamDone <- err
			return
		}
		if string(request) != "request-body" {
			upstreamDone <- fmt.Errorf("unexpected upstream request %q", request)
			return
		}
		_, err = conn.Write([]byte("complete-response-body"))
		if err != nil {
			upstreamDone <- err
			return
		}
		if tcp, ok := conn.(*net.TCPConn); ok {
			_ = tcp.CloseWrite()
		}
		upstreamDone <- nil
	}()

	clientListener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer clientListener.Close()
	proxySideCh := make(chan net.Conn, 1)
	go func() {
		conn, e := clientListener.Accept()
		if e == nil {
			proxySideCh <- conn
		}
	}()
	appSide, err := net.Dial("tcp", clientListener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer appSide.Close()
	proxySide := <-proxySideCh
	defer proxySide.Close()
	_ = appSide.SetDeadline(time.Now().Add(3 * time.Second))
	_ = proxySide.SetDeadline(time.Now().Add(3 * time.Second))

	tunnelDone := make(chan error, 1)
	go func() { tunnelDone <- tunnelTLS(proxySide, upstreamListener.Addr().String()) }()
	if _, err := appSide.Write([]byte("request-body")); err != nil {
		t.Fatal(err)
	}
	if tcp, ok := appSide.(*net.TCPConn); ok {
		if err := tcp.CloseWrite(); err != nil {
			t.Fatal(err)
		}
	}
	response, err := io.ReadAll(appSide)
	if err != nil {
		t.Fatal(err)
	}
	if string(response) != "complete-response-body" {
		t.Fatalf("response was truncated: got %q", response)
	}
	if err := <-upstreamDone; err != nil {
		t.Fatal(err)
	}
	if err := <-tunnelDone; err != nil {
		t.Fatal(err)
	}
}

func TestBundledFullUpstreamCosmeticListsAreLoadedLocally(t *testing.T) {
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	mod, err := filepath.Abs(filepath.Join(cwd, ".."))
	if err != nil {
		t.Fatal(err)
	}
	pg := t.TempDir()
	conf := "[list:rule]\n" +
		"builtin://NoAppDownload.txt|local app prompts|1\n" +
		"builtin://RunningCheese_Watermark.txt|local watermarks|1\n" +
		"builtin://RunningCheese_Popup.txt|local popup|1\n" +
		"builtin://AdultSite_Elements_EasyList.txt|local adult cosmetics|1\n"
	if err := os.WriteFile(filepath.Join(pg, "settings.conf"), []byte(conf), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PG", pg)
	e := &engine{modDir: mod}
	rules := e.loadCosmeticRules()
	t.Logf("bundled offline cosmetic parser: accepted %d CSS/domain-scoped rules", len(rules))
	if len(rules) < 150 {
		t.Fatalf("expected broad upstream-compatible local CSS subset, got only %d rules", len(rules))
	}
	var appPrompt, watermark, adult bool
	for _, r := range rules {
		switch {
		case r.domain == "bilibili.com" && strings.Contains(strings.ToLower(r.selector), "fixed_app_download"):
			appPrompt = true
		case r.domain == "chat.deepseek.com" && strings.Contains(strings.ToLower(r.selector), "watermark"):
			watermark = true
		case r.domain == "pornhub.com" && strings.Contains(strings.ToLower(r.selector), "sideads"):
			adult = true
		}
	}
	if !appPrompt {
		t.Fatal("full NoAppDownload upstream snapshot did not expose the known Bilibili app-download selector")
	}
	if !watermark {
		t.Fatal("full RunningCheese watermark snapshot did not expose the known DeepSeek watermark selector")
	}
	if !adult {
		t.Fatal("full EasyList adult element snapshot did not expose the known Pornhub side-ad selector")
	}
}

func TestResponseHookNotModifiedSuppressesBodyAndLength(t *testing.T) {
	patch, _ := json.Marshal(map[string]any{"statusCode": http.StatusNotModified, "body": "must-not-appear"})
	output, _ := json.Marshal(map[string]any{"ok": true, "done": true, "result": json.RawMessage(patch)})
	e := testScriptEngine(t, string(output), "response")
	req, err := http.NewRequest(http.MethodGet, "https://example.com/api", nil)
	if err != nil {
		t.Fatal(err)
	}
	original := "origin-body"
	resp := &http.Response{StatusCode: http.StatusOK, Status: "200 OK", Header: http.Header{"Content-Type": []string{"text/plain"}, "Content-Length": []string{fmt.Sprint(len(original))}}, Body: io.NopCloser(strings.NewReader(original)), ContentLength: int64(len(original))}
	e.applyResponseScripts(req, resp)
	got, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusNotModified || len(got) != 0 || resp.Header.Get("Content-Length") != "" || resp.ContentLength != 0 {
		t.Fatalf("304 framing not normalized: status=%d body=%q headers=%v length=%d", resp.StatusCode, got, resp.Header, resp.ContentLength)
	}
}

func TestResponseHookHeadWithNoContentStatusClearsForbiddenFraming(t *testing.T) {
	patch, _ := json.Marshal(map[string]any{"statusCode": http.StatusNoContent})
	output, _ := json.Marshal(map[string]any{"ok": true, "done": true, "result": json.RawMessage(patch)})
	e := testScriptEngine(t, string(output), "response")
	req, err := http.NewRequest(http.MethodHead, "https://example.com/api", nil)
	if err != nil {
		t.Fatal(err)
	}
	resp := &http.Response{
		StatusCode: http.StatusOK, Status: "200 OK",
		Header: http.Header{"Content-Length": []string{"123"}, "Transfer-Encoding": []string{"chunked"}, "Trailer": []string{"X-End"}},
		Body:   io.NopCloser(strings.NewReader("origin-body")), ContentLength: 123,
		TransferEncoding: []string{"chunked"}, Trailer: http.Header{"X-End": []string{"yes"}},
	}
	e.applyResponseScripts(req, resp)
	got, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusNoContent || len(got) != 0 || resp.Header.Get("Content-Length") != "" || resp.Header.Get("Transfer-Encoding") != "" || resp.Header.Get("Trailer") != "" || resp.ContentLength != 0 || len(resp.TransferEncoding) != 0 || len(resp.Trailer) != 0 {
		t.Fatalf("HEAD + 204 framing not normalized: status=%d body=%q headers=%v length=%d transfer=%v trailer=%v", resp.StatusCode, got, resp.Header, resp.ContentLength, resp.TransferEncoding, resp.Trailer)
	}
}

func TestResponseHookCannotSelectInformationalStatus(t *testing.T) {
	patch, _ := json.Marshal(map[string]any{"statusCode": http.StatusSwitchingProtocols})
	output, _ := json.Marshal(map[string]any{"ok": true, "done": true, "result": json.RawMessage(patch)})
	e := testScriptEngine(t, string(output), "response")
	req, err := http.NewRequest(http.MethodGet, "https://example.com/api", nil)
	if err != nil {
		t.Fatal(err)
	}
	resp := &http.Response{StatusCode: http.StatusOK, Status: "200 OK", Header: make(http.Header), Body: io.NopCloser(strings.NewReader("ok")), ContentLength: 2}
	e.applyResponseScripts(req, resp)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("informational status was accepted: %d", resp.StatusCode)
	}
}

func TestRequestScriptCannotForgeFramingForBodylessRequest(t *testing.T) {
	patch, _ := json.Marshal(map[string]any{"headers": map[string]string{"Content-Length": "999", "Transfer-Encoding": "chunked", "Trailer": "X-Injected"}})
	output, _ := json.Marshal(map[string]any{"ok": true, "done": true, "result": json.RawMessage(patch)})
	e := testScriptEngine(t, string(output), "request")
	req, err := http.NewRequest(http.MethodGet, "https://example.com/api", nil)
	if err != nil {
		t.Fatal(err)
	}
	e.applyRequestScripts(req)
	if req.Header.Get("Content-Length") != "" || req.Header.Get("Transfer-Encoding") != "" || req.Header.Get("Trailer") != "" {
		t.Fatalf("script forged request framing: CL=%q TE=%q Trailer=%q", req.Header.Get("Content-Length"), req.Header.Get("Transfer-Encoding"), req.Header.Get("Trailer"))
	}
}

func TestResponseScriptCannotForgeFramingWithoutChangingBody(t *testing.T) {
	patch, _ := json.Marshal(map[string]any{"headers": map[string]string{"Content-Length": "999", "Transfer-Encoding": "chunked", "Trailer": "X-Injected"}})
	output, _ := json.Marshal(map[string]any{"ok": true, "done": true, "result": json.RawMessage(patch)})
	e := testScriptEngine(t, string(output), "response")
	req, err := http.NewRequest(http.MethodGet, "https://example.com/api", nil)
	if err != nil {
		t.Fatal(err)
	}
	resp := &http.Response{StatusCode: 200, Status: "200 OK", Header: http.Header{"Content-Length": []string{"4"}}, Body: io.NopCloser(strings.NewReader("test")), ContentLength: 4}
	e.applyResponseScripts(req, resp)
	if resp.Header.Get("Content-Length") != "4" || resp.Header.Get("Transfer-Encoding") != "" || resp.Header.Get("Trailer") != "" || resp.ContentLength != 4 {
		t.Fatalf("script forged response framing: headers=%v ContentLength=%d", resp.Header, resp.ContentLength)
	}
}

func TestResponseBodyRewriteClearsStructuredTransferFraming(t *testing.T) {
	patch, _ := json.Marshal(map[string]any{"body": "rewritten"})
	output, _ := json.Marshal(map[string]any{"ok": true, "done": true, "result": json.RawMessage(patch)})
	e := testScriptEngine(t, string(output), "response")
	req, err := http.NewRequest(http.MethodGet, "https://example.com/api", nil)
	if err != nil {
		t.Fatal(err)
	}
	resp := &http.Response{StatusCode: 200, Status: "200 OK", Header: http.Header{"Content-Type": []string{"application/json"}}, Body: io.NopCloser(strings.NewReader("origin")), ContentLength: -1, TransferEncoding: []string{"chunked"}, Trailer: http.Header{"X-End": []string{"yes"}}}
	e.applyResponseScripts(req, resp)
	if len(resp.TransferEncoding) != 0 || resp.Trailer != nil || resp.ContentLength != int64(len("rewritten")) {
		t.Fatalf("structured response framing not normalized: TE=%v Trailer=%v CL=%d", resp.TransferEncoding, resp.Trailer, resp.ContentLength)
	}
}
