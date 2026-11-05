package main

import (
	"bufio"
	"bytes"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

const maxURLRewriteRules = 2048

type urlRewriteRule struct {
	pattern *regexp.Regexp
	action  string
	target  string
}

// loadURLRewriteRules reads the native FX runtime manifest. Each active line is
// `<regexp> - <action>`; blank lines and comments are ignored. The file is
// deliberately separate from DNS/domain rules because URL-scoped actions must
// never silently become host-wide blocks.
func loadURLRewriteRules(path string) ([]urlRewriteRule, error) {
	f, err := os.Open(path)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var rules []urlRewriteRule
	s := bufio.NewScanner(f)
	s.Buffer(make([]byte, 4096), 64*1024)
	lineNo := 0
	for s.Scan() {
		lineNo++
		line := strings.TrimSpace(s.Text())
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, "//") {
			continue
		}
		// Split on the final whitespace-delimited action separator so regexes
		// containing spaces are not accidentally truncated.
		i := strings.LastIndex(line, " - ")
		if i <= 0 {
			return nil, fmt.Errorf("line %d: expected '<regexp> - <action>'", lineNo)
		}
		pat, rhs := strings.TrimSpace(line[:i]), strings.TrimSpace(line[i+3:])
		if len(pat) > 4096 || len(rhs) > 8192 {
			return nil, fmt.Errorf("line %d: rule too large", lineNo)
		}
		rhsLower := strings.ToLower(rhs)
		action, target := "", ""
		for _, candidate := range []string{"reject-200", "reject-dict", "reject-array", "reject-empty", "reject-img", "redirect-302", "redirect-307", "reject", "redirect", "302", "307"} {
			if strings.HasPrefix(rhsLower, candidate) {
				action = candidate
				target = strings.TrimSpace(rhs[len(candidate):])
				break
			}
		}
		if action == "" {
			return nil, fmt.Errorf("line %d: unsupported action %q", lineNo, rhs)
		}
		if action == "302" || action == "307" || action == "redirect" || action == "redirect-302" || action == "redirect-307" {
			if target == "" {
				return nil, fmt.Errorf("line %d: redirect target missing", lineNo)
			}
		}
		rx, err := regexp.Compile(pat)
		if err != nil {
			return nil, fmt.Errorf("line %d: invalid regexp: %w", lineNo, err)
		}
		rules = append(rules, urlRewriteRule{pattern: rx, action: action, target: target})
		if len(rules) > maxURLRewriteRules {
			return nil, fmt.Errorf("too many URL rewrite rules")
		}
	}
	if err := s.Err(); err != nil {
		return nil, err
	}
	return rules, nil
}

// loadURLRewriteRulesOrEmpty is the runtime safety boundary: invalid URL Rewrite
// configuration must never disable unrelated HTTPS forwarding. The publisher
// validates candidates before atomic replacement, but this also protects against
// manual edits, storage corruption, and stale files.
func loadURLRewriteRulesOrEmpty(path string) []urlRewriteRule {
	rules, err := loadURLRewriteRules(path)
	if err != nil {
		log.Printf("URL Rewrite disabled for malformed manifest: %v", err)
		return nil
	}
	return rules
}

func applyURLRewrite(req *http.Request, rules []urlRewriteRule) (*http.Response, bool) {
	if req == nil || req.URL == nil {
		return nil, false
	}
	original := req.URL.String()
	for _, r := range rules {
		match := r.pattern.FindStringSubmatchIndex(original)
		if match == nil {
			continue
		}
		switch r.action {
		case "reject":
			return rewriteResponse(req, http.StatusForbidden, "", nil), true
		case "reject-200":
			return rewriteResponse(req, http.StatusOK, "", nil), true
		case "reject-empty":
			return rewriteResponse(req, http.StatusOK, "", nil), true
		case "reject-dict":
			return rewriteResponse(req, http.StatusOK, "application/json", []byte("{}")), true
		case "reject-array":
			return rewriteResponse(req, http.StatusOK, "application/json", []byte("[]")), true
		case "reject-img":
			return rewriteResponse(req, http.StatusOK, "image/gif", []byte{0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, 0, 0, 0, 255, 255, 255, 0, 0, 0, 0x21, 0xf9, 0x04, 0x01, 0, 0, 0, 0x2c, 0, 0, 0, 0, 1, 0, 1, 0, 0, 2, 2, 0x44, 0x01, 0, 0x3b}), true
		case "302", "redirect", "redirect-302", "307", "redirect-307":
			locBytes := r.pattern.ExpandString(nil, r.target, original, match)
			loc := string(locBytes)
			if len(loc) == 0 || len(loc) > 8192 || strings.ContainsAny(loc, "\r\n\\") {
				return rewriteResponse(req, http.StatusBadGateway, "", nil), true
			}
			u, err := url.Parse(loc)
			if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
				return rewriteResponse(req, http.StatusBadGateway, "", nil), true
			}
			code := http.StatusFound
			if r.action == "307" || r.action == "redirect-307" {
				code = http.StatusTemporaryRedirect
			}
			resp := rewriteResponse(req, code, "", nil)
			resp.Header.Set("Location", u.String())
			return resp, true
		}
	}
	return nil, false
}

func rewriteResponse(req *http.Request, status int, contentType string, body []byte) *http.Response {
	h := make(http.Header)
	h.Set("Connection", "close")
	if contentType != "" {
		h.Set("Content-Type", contentType)
	}
	if body == nil {
		body = []byte{}
	}
	h.Set("Content-Length", fmt.Sprint(len(body)))
	return &http.Response{StatusCode: status, Status: fmt.Sprintf("%d %s", status, http.StatusText(status)), Header: h, Body: ioNopCloser{Reader: bytes.NewReader(body)}, ContentLength: int64(len(body)), Request: req, Close: true}
}

type ioNopCloser struct{ *bytes.Reader }

func (r ioNopCloser) Close() error { return nil }

func urlRewriteManifestPath() string {
	pg := strings.TrimSpace(os.Getenv("PG"))
	if pg == "" {
		pg = "/data/adb/privacyguard"
	}
	return filepath.Join(pg, "mitm", "url-rewrite.conf")
}
