// ============================================================
//
//	clashapi.go — Clash API 客户端
//	sing-box 的 experimental.clash_api 提供了与 mihomo 一致的
//	REST 接口，这里直接复用它，避免自造一套统计通道。
//
//	覆盖：连接列表 / 实时流量 / 策略组读写 / 节点延迟测速 / 日志流 / 模式切换
//
// ============================================================
package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// ClashClient Clash API 客户端
type ClashClient struct {
	Base   string
	Secret string
	HTTP   *http.Client
}

// NewClashClient 默认连本机 9090
func NewClashClient(base, secret string) *ClashClient {
	if base == "" {
		base = "127.0.0.1:9090"
	}
	if !strings.Contains(base, "://") {
		base = "http://" + base
	}
	return &ClashClient{
		Base:   strings.TrimRight(base, "/"),
		Secret: secret,
		HTTP:   &http.Client{Timeout: 8 * time.Second},
	}
}

func (c *ClashClient) do(method, path string, body []byte) ([]byte, error) {
	var rdr io.Reader
	if body != nil {
		rdr = bytes.NewReader(body)
	}
	req, err := http.NewRequest(method, c.Base+path, rdr)
	if err != nil {
		return nil, err
	}
	if c.Secret != "" {
		req.Header.Set("Authorization", "Bearer "+c.Secret)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, fmt.Errorf("内核 API 不可达（%s）：%v", c.Base, err)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if resp.StatusCode >= 400 {
		msg := strings.TrimSpace(string(b))
		if len(msg) > 200 {
			msg = msg[:200]
		}
		return nil, fmt.Errorf("HTTP %d %s", resp.StatusCode, msg)
	}
	return b, nil
}

// ---------- 数据结构 ----------

type ClashConn struct {
	ID       string `json:"id"`
	Upload   int64  `json:"upload"`
	Download int64  `json:"download"`
	Start    string `json:"start"`
	Chains   []string `json:"chains"`
	Rule     string `json:"rule"`
	RulePayload string `json:"rulePayload"`
	Metadata struct {
		Network         string `json:"network"`
		Type            string `json:"type"`
		SourceIP        string `json:"sourceIP"`
		DestinationIP   string `json:"destinationIP"`
		SourcePort      string `json:"sourcePort"`
		DestinationPort string `json:"destinationPort"`
		Host            string `json:"host"`
		ProcessPath     string `json:"processPath"`
		Process         string `json:"process"`
		SniffHost       string `json:"sniffHost"`
		SpecialProxy    string `json:"specialProxy"`
	} `json:"metadata"`
}

type ClashConnections struct {
	DownloadTotal int64        `json:"downloadTotal"`
	UploadTotal   int64        `json:"uploadTotal"`
	Memory        int64        `json:"memory"`
	Connections   []ClashConn `json:"connections"`
}

type ClashProxy struct {
	Type    string `json:"type"`
	Now     string `json:"now"`
	All     []string `json:"all"`
	History []struct {
		Time  string `json:"time"`
		Delay int    `json:"delay"`
	} `json:"history"`
	UDP  bool `json:"udp"`
	Alive bool `json:"alive"`
}

// Connections 当前连接
func (c *ClashClient) Connections() (*ClashConnections, error) {
	b, err := c.do("GET", "/connections", nil)
	if err != nil {
		return nil, err
	}
	var out ClashConnections
	if err := json.Unmarshal(b, &out); err != nil {
		return nil, fmt.Errorf("连接列表解析失败: %v", err)
	}
	return &out, nil
}

// CloseConnection 关闭一条连接；id 为空则全部关闭
func (c *ClashClient) CloseConnection(id string) error {
	p := "/connections"
	if id != "" {
		p += "/" + url.PathEscape(id)
	}
	_, err := c.do("DELETE", p, nil)
	return err
}

// TrafficSample 采样一次实时流量。Clash API 的 /traffic 是流式接口，
// 这里读一行后立即断开，得到瞬时值。
func (c *ClashClient) TrafficSample() (up, down int64, err error) {
	req, err := http.NewRequest("GET", c.Base+"/traffic", nil)
	if err != nil {
		return 0, 0, err
	}
	if c.Secret != "" {
		req.Header.Set("Authorization", "Bearer "+c.Secret)
	}
	cl := &http.Client{Timeout: 6 * time.Second}
	resp, err := cl.Do(req)
	if err != nil {
		return 0, 0, fmt.Errorf("流量接口不可达：%v", err)
	}
	defer resp.Body.Close()
	sc := bufio.NewScanner(resp.Body)
	sc.Buffer(make([]byte, 4096), 1<<20)
	if sc.Scan() {
		var v struct {
			Up   int64 `json:"up"`
			Down int64 `json:"down"`
		}
		if err := json.Unmarshal(sc.Bytes(), &v); err == nil {
			return v.Up, v.Down, nil
		}
		return 0, 0, fmt.Errorf("流量数据解析失败")
	}
	return 0, 0, fmt.Errorf("流量接口无数据返回")
}

// Proxies 全部代理与策略组
func (c *ClashClient) Proxies() (map[string]ClashProxy, error) {
	b, err := c.do("GET", "/proxies", nil)
	if err != nil {
		return nil, err
	}
	var wrap struct {
		Proxies map[string]ClashProxy `json:"proxies"`
	}
	if err := json.Unmarshal(b, &wrap); err != nil {
		return nil, fmt.Errorf("代理列表解析失败: %v", err)
	}
	return wrap.Proxies, nil
}

// DelayTest 对单个节点/组测延迟
func (c *ClashClient) DelayTest(name, testURL string, timeoutMs int) (int, error) {
	if testURL == "" {
		testURL = "https://www.gstatic.com/generate_204"
	}
	if timeoutMs <= 0 {
		timeoutMs = 5000
	}
	p := "/proxies/" + url.PathEscape(name) + "/delay?timeout=" + strconv.Itoa(timeoutMs) +
		"&url=" + url.QueryEscape(testURL)
	b, err := c.do("GET", p, nil)
	if err != nil {
		return 0, err
	}
	var out struct {
		Delay   int    `json:"delay"`
		Message string `json:"message"`
	}
	if err := json.Unmarshal(b, &out); err != nil {
		return 0, fmt.Errorf("测速结果解析失败: %v", err)
	}
	if out.Message != "" {
		return 0, fmt.Errorf("%s", out.Message)
	}
	return out.Delay, nil
}

// Select 在策略组里切换到某个成员
func (c *ClashClient) Select(group, member string) error {
	body, _ := json.Marshal(map[string]string{"name": member})
	_, err := c.do("PUT", "/proxies/"+url.PathEscape(group), body)
	return err
}

// Mode 读取当前模式
func (c *ClashClient) Mode() (string, error) {
	b, err := c.do("GET", "/configs", nil)
	if err != nil {
		return "", err
	}
	var out struct {
		Mode string `json:"mode"`
	}
	json.Unmarshal(b, &out)
	return out.Mode, nil
}

// SetMode 切换 rule / global / direct
func (c *ClashClient) SetMode(mode string) error {
	body, _ := json.Marshal(map[string]string{"mode": mode})
	_, err := c.do("PATCH", "/configs", body)
	return err
}

// Version 内核版本
func (c *ClashClient) Version() (string, error) {
	b, err := c.do("GET", "/version", nil)
	if err != nil {
		return "", err
	}
	var out struct {
		Version string `json:"version"`
		Meta    bool   `json:"meta"`
	}
	json.Unmarshal(b, &out)
	return out.Version, nil
}

// LogLine 一行内核日志
type LogLine struct {
	Type    string `json:"type"`
	Payload string `json:"payload"`
}

// Logs 采集若干行日志后返回（level: info/warning/error/debug）
func (c *ClashClient) Logs(level string, max int, dur time.Duration) ([]LogLine, error) {
	if level == "" {
		level = "info"
	}
	if max <= 0 {
		max = 50
	}
	if dur <= 0 {
		dur = 3 * time.Second
	}
	req, err := http.NewRequest("GET", c.Base+"/logs?level="+level, nil)
	if err != nil {
		return nil, err
	}
	if c.Secret != "" {
		req.Header.Set("Authorization", "Bearer "+c.Secret)
	}
	cl := &http.Client{Timeout: dur + 3*time.Second}
	resp, err := cl.Do(req)
	if err != nil {
		return nil, fmt.Errorf("日志接口不可达：%v", err)
	}
	defer resp.Body.Close()
	var out []LogLine
	deadline := time.Now().Add(dur)
	sc := bufio.NewScanner(resp.Body)
	sc.Buffer(make([]byte, 8192), 1<<20)
	for sc.Scan() && len(out) < max && time.Now().Before(deadline) {
		var l LogLine
		if err := json.Unmarshal(sc.Bytes(), &l); err == nil && l.Payload != "" {
			out = append(out, l)
		}
	}
	return out, nil
}

// ---------- 格式化输出 ----------

func humanBytes(n int64) string {
	const unit = 1024
	if n < unit {
		return fmt.Sprintf("%d B", n)
	}
	units := []string{"KB", "MB", "GB", "TB", "PB"}
	f := float64(n)
	i := -1
	for f >= unit && i < len(units)-1 {
		f /= unit
		i++
	}
	return fmt.Sprintf("%.2f %s", f, units[i])
}

func humanSpeed(bps int64) string {
	return humanBytes(bps) + "/s"
}
