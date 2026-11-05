package main

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	maxClientHelloBytes = 64 << 10
	maxTLSRecordBytes   = 18 << 10
)

// replayConn replays bytes consumed while sniffing SNI, then reads from the
// original socket. Writes and deadlines continue to use the underlying socket.
type replayConn struct {
	net.Conn
	reader io.Reader
}

func (c *replayConn) Read(p []byte) (int, error) { return c.reader.Read(p) }
func (c *replayConn) CloseWrite() error {
	if cw, ok := c.Conn.(interface{ CloseWrite() error }); ok {
		return cw.CloseWrite()
	}
	return nil
}

func mitmHostnameManifestPath() string {
	pg := strings.TrimSpace(os.Getenv("PG"))
	if pg == "" {
		pg = "/data/adb/privacyguard"
	}
	return filepath.Join(pg, "mitm", "hostnames.conf")
}

func normalizeMITMHostPattern(raw string) (string, error) {
	p := strings.ToLower(strings.TrimSpace(raw))
	p = strings.TrimSuffix(p, ".")
	if strings.HasPrefix(p, "*.") {
		base, err := normalizeHostname(strings.TrimPrefix(p, "*."))
		if err != nil || net.ParseIP(base) != nil {
			return "", errors.New("invalid wildcard hostname")
		}
		return "*." + base, nil
	}
	if strings.Contains(p, "*") {
		return "", errors.New("wildcard is permitted only as leading *.")
	}
	return normalizeHostname(p)
}

func loadMITMHosts(path string) ([]string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil // safe default: no hosts means TLS passthrough
		}
		return nil, err
	}
	seen := make(map[string]struct{})
	out := make([]string, 0)
	for n, raw := range bytes.Split(b, []byte{'\n'}) {
		line := strings.TrimSpace(string(raw))
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		host, err := normalizeMITMHostPattern(line)
		if err != nil {
			return nil, fmt.Errorf("invalid MITM hostname at line %d: %w", n+1, err)
		}
		if _, ok := seen[host]; ok {
			continue
		}
		seen[host] = struct{}{}
		out = append(out, host)
		if len(out) > 1024 {
			return nil, errors.New("MITM hostname allowlist exceeds 1024 entries")
		}
	}
	return out, nil
}

func mitmHostAllowed(host string, allowlist []string) bool {
	if len(allowlist) == 0 {
		return false
	}
	h, err := normalizeHostname(host)
	if err != nil || net.ParseIP(h) != nil {
		return false
	}
	for _, entry := range allowlist {
		if entry == h {
			return true
		}
		if strings.HasPrefix(entry, "*.") {
			base := strings.TrimPrefix(entry, "*.")
			if h != base && strings.HasSuffix(h, "."+base) {
				return true
			}
		}
	}
	return false
}

// readClientHelloSNI consumes and returns a bounded TLS prefix for replay. It
// supports ClientHello messages split across TLS handshake records. Empty SNI
// and non-TLS traffic are not errors: callers must safely tunnel them through.
func readClientHelloSNI(conn net.Conn) ([]byte, string, error) {
	prefix := make([]byte, 0, 4096)
	handshake := make([]byte, 0, 4096)
	for len(prefix) < maxClientHelloBytes {
		hdr := make([]byte, 5)
		if _, err := io.ReadFull(conn, hdr); err != nil {
			return prefix, "", err
		}
		prefix = append(prefix, hdr...)
		if hdr[0] != 22 { // Not a TLS handshake record; preserve and tunnel it.
			return prefix, "", nil
		}
		length := int(binary.BigEndian.Uint16(hdr[3:5]))
		if length <= 0 || length > maxTLSRecordBytes || len(prefix)+length > maxClientHelloBytes {
			// The 5-byte header is already preserved; remaining bytes stay unread.
			return prefix, "", nil
		}
		payload := make([]byte, length)
		n, err := io.ReadFull(conn, payload)
		if err != nil {
			prefix = append(prefix, payload[:n]...)
			return prefix, "", err
		}
		prefix = append(prefix, payload...)
		handshake = append(handshake, payload...)
		if len(handshake) < 4 {
			continue
		}
		if handshake[0] != 1 { // Not a ClientHello: safe passthrough.
			return prefix, "", nil
		}
		bodyLen := int(handshake[1])<<16 | int(handshake[2])<<8 | int(handshake[3])
		if bodyLen < 34 || bodyLen > maxClientHelloBytes-4 {
			return prefix, "", nil
		}
		if len(handshake) >= bodyLen+4 {
			host, err := parseClientHelloSNI(handshake[:bodyLen+4])
			if err != nil {
				return prefix, "", nil // malformed hello falls back to passthrough
			}
			return prefix, host, nil
		}
	}
	return prefix, "", nil
}

func parseClientHelloSNI(handshake []byte) (string, error) {
	if len(handshake) < 4 || handshake[0] != 1 {
		return "", errors.New("not a ClientHello")
	}
	bodyLen := int(handshake[1])<<16 | int(handshake[2])<<8 | int(handshake[3])
	if bodyLen+4 > len(handshake) || bodyLen < 34 {
		return "", errors.New("truncated ClientHello")
	}
	b := handshake[4 : bodyLen+4]
	i := 2 + 32 // legacy_version + random
	if i >= len(b) {
		return "", errors.New("truncated ClientHello session id")
	}
	sidLen := int(b[i])
	i++
	if sidLen > len(b)-i {
		return "", errors.New("invalid ClientHello session id length")
	}
	i += sidLen
	if len(b)-i < 2 {
		return "", errors.New("missing ClientHello cipher suites")
	}
	cipherLen := int(binary.BigEndian.Uint16(b[i : i+2]))
	i += 2
	if cipherLen > len(b)-i {
		return "", errors.New("invalid ClientHello cipher suites length")
	}
	i += cipherLen
	if i >= len(b) {
		return "", nil // no extensions
	}
	compLen := int(b[i])
	i++
	if compLen > len(b)-i {
		return "", errors.New("invalid ClientHello compression length")
	}
	i += compLen
	if i == len(b) {
		return "", nil
	}
	if len(b)-i < 2 {
		return "", errors.New("truncated ClientHello extensions length")
	}
	extLen := int(binary.BigEndian.Uint16(b[i : i+2]))
	i += 2
	if extLen > len(b)-i {
		return "", errors.New("invalid ClientHello extensions length")
	}
	end := i + extLen
	for i+4 <= end {
		typ := binary.BigEndian.Uint16(b[i : i+2])
		n := int(binary.BigEndian.Uint16(b[i+2 : i+4]))
		i += 4
		if n > end-i {
			return "", errors.New("invalid ClientHello extension length")
		}
		if typ == 0 { // server_name
			ext := b[i : i+n]
			if len(ext) < 2 {
				return "", errors.New("invalid SNI extension")
			}
			listLen := int(binary.BigEndian.Uint16(ext[:2]))
			if listLen > len(ext)-2 {
				return "", errors.New("invalid SNI name list")
			}
			j := 2
			for j+3 <= 2+listLen {
				nameType := ext[j]
				nameLen := int(binary.BigEndian.Uint16(ext[j+1 : j+3]))
				j += 3
				if nameLen > 2+listLen-j {
					return "", errors.New("invalid SNI hostname length")
				}
				if nameType == 0 {
					host, err := normalizeHostname(string(ext[j : j+nameLen]))
					if err != nil || net.ParseIP(host) != nil {
						return "", errors.New("invalid SNI hostname")
					}
					return host, nil
				}
				j += nameLen
			}
			return "", nil
		}
		i += n
	}
	return "", nil
}

// tunnelTLS relays an unmatched TLS connection without presenting FX's CA.
// This prevents unrelated apps and certificate-pinned hosts from being broken.
func tunnelTLS(client net.Conn, destination string) error {
	upstream, err := net.DialTimeout("tcp", destination, 8*time.Second)
	if err != nil {
		return fmt.Errorf("TLS passthrough dial %s: %w", destination, err)
	}
	defer upstream.Close()
	_ = client.SetDeadline(time.Now().Add(10 * time.Minute))
	_ = upstream.SetDeadline(time.Now().Add(10 * time.Minute))
	type copyResult struct{ err error }
	done := make(chan copyResult, 2)
	go func() {
		_, copyErr := io.Copy(upstream, client)
		if cw, ok := upstream.(interface{ CloseWrite() error }); ok {
			_ = cw.CloseWrite()
		}
		done <- copyResult{err: copyErr}
	}()
	go func() {
		_, copyErr := io.Copy(client, upstream)
		if cw, ok := client.(interface{ CloseWrite() error }); ok {
			_ = cw.CloseWrite()
		}
		done <- copyResult{err: copyErr}
	}()
	// A TCP half-close in one direction is normal: after the client finishes
	// writing its request, the server may still have a full response to send.
	// Returning after only the first io.Copy result closes upstream immediately
	// and silently truncates that response. Wait for both directions unless one
	// fails; in the latter case abort the peer direction rather than hanging.
	first := <-done
	if first.err != nil {
		_ = upstream.Close()
		_ = client.SetDeadline(time.Now())
		<-done
		return first.err
	}
	second := <-done
	return second.err
}
