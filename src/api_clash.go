// ============================================================
//
//	api_clash.go — 面板用的 Clash API 直连端点
//
//	为什么不让前端去 shell 调 abserver：
//	  面板的连接列表 / 实时流量 / 策略组是每秒刷新的，
//	  每次都 fork 一个进程太浪费，在服务进程内直接发 HTTP
//	  到内核的 Clash API 更省资源也更稳。
//
//	端点: /api/clash?sub=status|conn|traffic|proxies|delay|select|mode|logs|close
//
// ============================================================
package main

import (
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// clashPort 读取内核 Clash API 端口，优先用 sy.conf 里的配置。
func (c *serverCtx) clashPort() int {
	port := 9090
	b, err := os.ReadFile(filepath.Join(c.datadir, "config", "sy.conf"))
	if err == nil {
		for _, line := range strings.Split(string(b), "\n") {
			line = strings.TrimSpace(line)
			if !strings.HasPrefix(line, "CLASH_API_PORT") {
				continue
			}
			if i := strings.Index(line, "="); i > 0 {
				if v := atoiSafe(strings.TrimSpace(line[i+1:])); v > 0 {
					port = v
				}
			}
		}
	}
	return port
}

func (c *serverCtx) handleClash(w http.ResponseWriter, r *http.Request) {
	sub := para(r, "sub")
	if sub == "" {
		sub = "status"
	}
	port := c.clashPort()
	if p := atoiSafe(para(r, "port")); p > 0 {
		port = p
	}
	secret := para(r, "secret")
	cli := NewClashClient("127.0.0.1:"+strconv.Itoa(port), secret)

	switch sub {
	case "status":
		ver, err := cli.Version()
		if err != nil {
			writeJSON(w, map[string]interface{}{
				"ok": false, "err": "内核 API 不可达：" + err.Error(),
			})
			return
		}
		m, _ := cli.Mode()
		up, down, _ := cli.TrafficSample()
		out := map[string]interface{}{
			"ok": true, "version": ver, "mode": m,
			"up": up, "down": down,
		}
		if conns, err := cli.Connections(); err == nil {
			out["conn_count"] = len(conns.Connections)
			out["upload_total"] = conns.UploadTotal
			out["download_total"] = conns.DownloadTotal
			out["memory"] = conns.Memory
		}
		writeJSON(w, out)

	case "conn":
		conns, err := cli.Connections()
		if err != nil {
			writeJSON(w, map[string]interface{}{"ok": false, "err": err.Error()})
			return
		}
		writeJSON(w, map[string]interface{}{
			"ok": true, "connections": conns.Connections,
			"upload_total": conns.UploadTotal, "download_total": conns.DownloadTotal,
			"memory": conns.Memory,
		})

	case "traffic":
		up, down, err := cli.TrafficSample()
		if err != nil {
			writeJSON(w, map[string]interface{}{"ok": false, "err": err.Error()})
			return
		}
		writeJSON(w, map[string]interface{}{
			"ok": true, "up": up, "down": down,
			"up_h": humanSpeed(up), "down_h": humanSpeed(down),
		})

	case "proxies":
		px, err := cli.Proxies()
		if err != nil {
			writeJSON(w, map[string]interface{}{"ok": false, "err": err.Error()})
			return
		}
		writeJSON(w, map[string]interface{}{"ok": true, "proxies": px})

	case "delay":
		name := para(r, "name")
		if name == "" {
			writeJSON(w, map[string]interface{}{"ok": false, "err": "缺少 name"})
			return
		}
		url := para(r, "url")
		if url == "" {
			url = "http://www.gstatic.com/generate_204"
		}
		to := atoiSafe(para(r, "timeout"))
		if to <= 0 {
			to = 5000
		}
		d, err := cli.DelayTest(name, url, to)
		if err != nil {
			writeJSON(w, map[string]interface{}{"ok": false, "err": err.Error(), "name": name})
			return
		}
		writeJSON(w, map[string]interface{}{"ok": true, "name": name, "delay": d})

	case "select":
		group, to := para(r, "group"), para(r, "to")
		if group == "" || to == "" {
			writeJSON(w, map[string]interface{}{"ok": false, "err": "需要 group 与 to"})
			return
		}
		if err := cli.Select(group, to); err != nil {
			writeJSON(w, map[string]interface{}{"ok": false, "err": err.Error()})
			return
		}
		writeJSON(w, map[string]interface{}{"ok": true, "group": group, "now": to})

	case "mode":
		if m := para(r, "mode"); m != "" {
			if err := cli.SetMode(m); err != nil {
				writeJSON(w, map[string]interface{}{"ok": false, "err": err.Error()})
				return
			}
			writeJSON(w, map[string]interface{}{"ok": true, "mode": m})
			return
		}
		m, err := cli.Mode()
		if err != nil {
			writeJSON(w, map[string]interface{}{"ok": false, "err": err.Error()})
			return
		}
		writeJSON(w, map[string]interface{}{"ok": true, "mode": m})

	case "logs":
		level := para(r, "level")
		if level == "" {
			level = "info"
		}
		n := atoiSafe(para(r, "lines"))
		if n <= 0 {
			n = 50
		}
		ls, err := cli.Logs(level, n, 3*time.Second)
		if err != nil {
			writeJSON(w, map[string]interface{}{"ok": false, "err": err.Error()})
			return
		}
		writeJSON(w, map[string]interface{}{"ok": true, "logs": ls})

	case "close":
		id := para(r, "id")
		if err := cli.CloseConnection(id); err != nil {
			writeJSON(w, map[string]interface{}{"ok": false, "err": err.Error()})
			return
		}
		writeJSON(w, map[string]interface{}{"ok": true})

	default:
		b, _ := json.Marshal(map[string]interface{}{
			"ok": false, "err": "未知子命令 " + sub,
			"subs": []string{"status", "conn", "traffic", "proxies", "delay", "select", "mode", "logs", "close"},
		})
		w.Header().Set("Content-Type", "application/json")
		w.Write(b)
	}
}
