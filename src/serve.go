// ============================================================
//
//	serve.go — 一体化在线管理面板 Web 服务 (第三层界面能力)
//	功能: 静态面板托管、REST API 网关(鉴权)、命令执行桥、
//	      本地 + 局域网访问、多端自适应
//
// ============================================================
package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// 命令执行硬超时: 防止网络阻塞导致面板请求长期挂起(UI 卡死)
const execTimeout = 120 * time.Second

func randReader() io.Reader { return rand.Reader }

func randInt() (*big.Int, error) {
	return rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
}

type serverCtx struct {
	webroot string
	moddir  string
	datadir string
	token   string
}

func cmdServe(args []string) {
	fs := flag.NewFlagSet("serve", flag.ExitOnError)
	addr := fs.String("addr", ":8848", "监听地址")
	webroot := fs.String("webroot", "webroot", "静态目录")
	moddir := fs.String("moddir", ".", "模块目录")
	datadir := fs.String("datadir", "/data/adb/SY", "数据目录")
	token := fs.String("token", "", "访问令牌")
	fs.Parse(args)

	ctx := &serverCtx{webroot: *webroot, moddir: *moddir, datadir: *datadir, token: *token}
	mux := http.NewServeMux()

	// 静态资源(带内嵌 token 注入)
	mux.HandleFunc("/", ctx.serveStatic)
	// 公共: 健康检查 / 令牌校验
	mux.HandleFunc("/api/ping", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, map[string]interface{}{"ok": true, "v": version, "auth": ctx.token != ""})
	})
	mux.HandleFunc("/api/auth", ctx.handleAuth)
	// 受保护 API
	mux.HandleFunc("/api/", ctx.auth(ctx.handleAPI))
	// 命令桥(执行脚本子命令)
	mux.HandleFunc("/api/exec", ctx.auth(ctx.handleExec))

	srv := &http.Server{Addr: *addr, Handler: mux, ReadHeaderTimeout: 10 * time.Second}
	fmt.Println("panel listen", *addr)
	if err := srv.ListenAndServe(); err != nil {
		fmt.Fprintln(os.Stderr, "ERR:", err)
		os.Exit(1)
	}
}

func writeJSON(w http.ResponseWriter, v interface{}) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	json.NewEncoder(w).Encode(v)
}

// ---------- 鉴权中间件 ----------
func (c *serverCtx) auth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 同源 WebUI 通过 ?token= 或 Header 携带；局域网需令牌
		tk := r.Header.Get("X-Auth-Token")
		if tk == "" {
			tk = r.URL.Query().Get("token")
		}
		if c.token != "" && tk != c.token {
			w.WriteHeader(http.StatusUnauthorized)
			writeJSON(w, map[string]interface{}{"ok": false, "err": "unauthorized"})
			return
		}
		next(w, r)
	}
}

func (c *serverCtx) handleAuth(w http.ResponseWriter, r *http.Request) {
	tk := r.Header.Get("X-Auth-Token")
	if tk == "" {
		tk = r.URL.Query().Get("token")
	}
	writeJSON(w, map[string]interface{}{"ok": c.token == "" || tk == c.token})
}

// ---------- 静态面板 ----------
func (c *serverCtx) serveStatic(w http.ResponseWriter, r *http.Request) {
	p := r.URL.Path
	if p == "/" {
		p = "/index.html"
	}
	// 防目录穿越
	clean := filepath.Clean("/" + p)
	full := filepath.Join(c.webroot, clean)
	if !strings.HasPrefix(full, filepath.Clean(c.webroot)) {
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}
	b, err := os.ReadFile(full)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	if strings.HasSuffix(full, ".html") {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// 关键: 向 index.html 注入当前令牌, 让同源访问无需手动拼 ?token=
		if c.token != "" {
			inj := []byte("<script>window.__SY_TOKEN__=" + strconv.Quote(c.token) + ";</script>")
			if bytes.Contains(b, []byte("<head>")) {
				b = bytes.Replace(b, []byte("<head>"), append([]byte("<head>"), inj...), 1)
			} else {
				b = append(inj, b...)
			}
		}
	} else if strings.HasSuffix(full, ".css") {
		w.Header().Set("Content-Type", "text/css; charset=utf-8")
	} else if strings.HasSuffix(full, ".js") {
		w.Header().Set("Content-Type", "application/javascript; charset=utf-8")
	}
	w.Write(b)
}

// ---------- API 网关 ----------
func (c *serverCtx) handleAPI(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/api/")
	switch path {
	case "status":
		out, _ := c.runCtl("status")
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(out))
	case "dns":
		c.proxySub(w, r, "dns.sh")
	case "mitm":
		c.proxySub(w, r, "mitm.sh")
	case "splash":
		c.proxySub(w, r, "splash.sh")
	case "notify":
		c.proxySub(w, r, "notify.sh")
	case "panel":
		c.proxySub(w, r, "panel.sh")
	case "scripts":
		c.proxySub(w, r, "scripts_ext.sh")
	case "backup":
		c.proxySub(w, r, "backup.sh")
	case "toggle":
		feat := para(r, "feature")
		out, _ := c.runCtl("toggle", feat)
		writeJSON(w, map[string]interface{}{"ok": true, "out": out})
	case "logs":
		which := para(r, "name")
		if which == "" {
			which = "action.log"
		}
		b, _ := os.ReadFile(filepath.Join(c.datadir, "logs", filepath.Base(which)))
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.Write(b)
	case "config":
		c.handleConfig(w, r)
	case "apps":
		c.handleApps(w, r)
	default:
		http.NotFound(w, r)
	}
}

// 透传子命令到对应脚本(参数经 sub + 其余 query)
func (c *serverCtx) proxySub(w http.ResponseWriter, r *http.Request, script string) {
	sub := para(r, "sub")
	arg1 := para(r, "a")
	args := []string{}
	if sub != "" {
		args = append(args, sub)
	}
	if arg1 != "" {
		args = append(args, arg1)
	}
	// POST body 透传到 stdin(用于 import)
	var stdin io.Reader = nil
	if r.Method == http.MethodPost {
		stdin = r.Body
	}
	out, err := c.runScriptStdin(script, args, stdin)
	resp := map[string]interface{}{"ok": err == nil, "out": out}
	if err != nil {
		resp["err"] = err.Error()
	}
	writeJSON(w, resp)
}

func (c *serverCtx) handleConfig(w http.ResponseWriter, r *http.Request) {
	cf := filepath.Join(c.datadir, "config", "sy.conf")
	if r.Method == http.MethodGet {
		b, _ := os.ReadFile(cf)
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.Write(b)
		return
	}
	// POST: 覆盖写入
	if r.Method == http.MethodPost {
		b, _ := io.ReadAll(r.Body)
		os.WriteFile(cf, b, 0644)
		writeJSON(w, map[string]interface{}{"ok": true})
	}
}

func (c *serverCtx) handleApps(w http.ResponseWriter, r *http.Request) {
	// 列出已安装应用(供 MITM 生效应用 / 开屏规则 选择)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "sh", "-c", "pm list packages 2>/dev/null | sed 's/package://' | sort")
	out, _ := cmd.Output()
	pkgs := []string{}
	for _, ln := range strings.Split(string(out), "\n") {
		ln = strings.TrimSpace(ln)
		if ln != "" {
			pkgs = append(pkgs, ln)
		}
	}
	writeJSON(w, map[string]interface{}{"ok": true, "packages": pkgs})
}

// ---------- 命令执行桥 ----------
func (c *serverCtx) handleExec(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Cmd  string   `json:"cmd"`
		Args []string `json:"args"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, map[string]interface{}{"ok": false, "err": "bad json"})
		return
	}
	// 白名单: 仅允许 ctl.sh 与 scripts 目录脚本
	if req.Cmd == "ctl" {
		out, err := c.runCtl(req.Args...)
		writeJSON(w, map[string]interface{}{"ok": err == nil, "out": out})
		return
	}
	out, err := c.runScriptStdin(req.Cmd+".sh", req.Args, nil)
	writeJSON(w, map[string]interface{}{"ok": err == nil, "out": out})
}

func (c *serverCtx) runCtl(args ...string) (string, error) {
	full := append([]string{filepath.Join(c.moddir, "scripts", "ctl.sh")}, args...)
	return runCmd("sh", full...)
}

func (c *serverCtx) runScriptStdin(script string, args []string, stdin io.Reader) (string, error) {
	p := filepath.Join(c.moddir, "scripts", script)
	if _, err := os.Stat(p); err != nil {
		return "", fmt.Errorf("script not found: %s", script)
	}
	full := append([]string{p}, args...)
	ctx, cancel := context.WithTimeout(context.Background(), execTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "sh", full...)
	if stdin != nil {
		cmd.Stdin = stdin
	}
	out, err := cmd.CombinedOutput()
	if ctx.Err() == context.DeadlineExceeded {
		return string(out), fmt.Errorf("命令执行超时(>%s)，已中止以防卡死", execTimeout)
	}
	return string(out), err
}

func runCmd(name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), execTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	out, err := cmd.CombinedOutput()
	if ctx.Err() == context.DeadlineExceeded {
		return string(out), fmt.Errorf("命令执行超时(>%s)，已中止以防卡死", execTimeout)
	}
	return string(out), err
}

func para(r *http.Request, key string) string {
	return r.URL.Query().Get(key)
}
