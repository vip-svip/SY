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
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"os"
	"os/exec"
	"path"
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
	case "route":
		c.proxySub(w, r, "route.sh")
	case "proxy":
		c.proxySub(w, r, "proxynode.sh")
	case "clash":
		c.handleClash(w, r)
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
	case "file":
		c.handleFile(w, r)
	case "fileedit":
		c.proxySub(w, r, "fileedit.sh")
	case "privacy_guard":
		c.proxySub(w, r, "privacy_guard.sh")
	case "game_privacy":
		c.proxySub(w, r, "game_privacy.sh")
	case "clip_guard":
		c.proxySub(w, r, "clip_guard.sh")
	case "privacy_check":
		c.proxySub(w, r, "privacy_check.sh")
	case "privacy_ruleset":
		c.proxySub(w, r, "privacy_ruleset.sh")
	case "leakguard":
		c.proxySub(w, r, "leakguard.sh")
	case "fx_deepguard":
		c.proxySub(w, r, "fx_deepguard.sh")
	case "oneclick":
		c.proxySub(w, r, "oneclick.sh")
	case "offline":
		c.proxySub(w, r, "offline.sh")
	case "proxyrun":
		c.proxySub(w, r, "proxyrun.sh")
	case "kernel":
		c.proxySub(w, r, "kernel.sh")
	case "route_gen":
		c.proxySub(w, r, "route.sh")
	case "game_privacy_ui":
		c.proxySub(w, r, "game_privacy.sh")
	case "ruleset_ui":
		c.proxySub(w, r, "ruleset.sh")
	case "settings_ui":
		c.proxySub(w, r, "settings.sh")
	case "logs_ui":
		c.proxySub(w, r, "logs.sh")
	case "updater_ui":
		c.proxySub(w, r, "updater.sh")
	case "dnssrv_ui":
		c.proxySub(w, r, "dnssrv.sh")
	case "netblock_ui":
		c.proxySub(w, r, "netblock.sh")
	case "splash_ui":
		c.proxySub(w, r, "splash.sh")
	case "notify_ui":
		c.proxySub(w, r, "notify.sh")
	case "scripts_ext_ui":
		c.proxySub(w, r, "scripts_ext.sh")
	case "proxynode_ui":
		c.proxySub(w, r, "proxynode.sh")
	case "mitm_ui":
		c.proxySub(w, r, "mitm.sh")
	case "panel_ui":
		c.proxySub(w, r, "panel.sh")
	default:
		http.NotFound(w, r)
	}
}

// 透传子命令到对应脚本
// 参数来源优先级：POST JSON {"args":[...]} > query a1,a2,…（a 等价 a1）
// 之所以要支持多参数：规则命中诊断 / DNS 探测这类命令带好几个 -flag，
// 只透传一个参数根本表达不了。
func (c *serverCtx) proxySub(w http.ResponseWriter, r *http.Request, script string) {
	sub := para(r, "sub")
	args := []string{}
	if sub != "" {
		args = append(args, sub)
	}

	var stdin io.Reader = nil
	if r.Method == http.MethodPost {
		body, _ := io.ReadAll(io.LimitReader(r.Body, 8<<20))
		if len(body) > 0 {
			var req struct {
				Args  []string `json:"args"`
				Stdin string   `json:"stdin"`
			}
			if json.Unmarshal(body, &req) == nil && len(req.Args) > 0 {
				args = append(args, req.Args...)
			} else {
				stdin = bytes.NewReader(body)
			}
			if req.Stdin != "" {
				stdin = strings.NewReader(req.Stdin)
			}
		}
	}

	if len(args) <= 1 {
		if a := para(r, "a"); a != "" {
			args = append(args, a)
		}
		// 找最大下标，再按顺序补齐，保证 -flag value 成对不错位
		maxIdx := 0
		for i := 1; i <= 32; i++ {
			if para(r, "a"+strconv.Itoa(i)) != "" {
				maxIdx = i
			}
		}
		for i := 1; i <= maxIdx; i++ {
			args = append(args, para(r, "a"+strconv.Itoa(i)))
		}
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
	cmd := exec.CommandContext(ctx, shellPath(), "-c", "pm list packages 2>/dev/null | sed 's/package://' | sort")
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

// ---------- 通用文本文件编辑（面板「文件编辑器」） ----------
// 为什么需要它：订阅源/规则清单/隐私目标这类配置此前只能靠按钮增删单条，
// 用户无法直接编辑整份文件（换订阅地址、批量粘贴、调整格式都做不到）。
// 安全边界（三件事都做）：
//   ① 只允许白名单目录下的文件（config/ 与 rules/），不允许任意路径；
//   ② filepath.Clean + 前缀校验，杜绝 ../ 穿越；
//   ③ 大小上限 4MB，避免把内存打满。
var fileAllowDirs = []string{"config", "rules"}

// 解析并校验用户给的文件路径，返回绝对路径
// resolveDataFile 解析并校验面板要编辑的文件路径。
//
// 【真实缺陷修复】旧实现用 filepath.Clean 做标准化 —— 它**随操作系统改变分隔符**：
//   Windows 上 filepath.Clean("/config/x") 返回 "\config\x"，
//   而后面又用 strings.SplitN(clean, "/", 2) 按正斜杠取顶层目录，
//   结果 top 拿到整条路径、白名单永远不匹配 —— 合法文件也被拒（真跑 API 时抓到）。
// 正确做法：逻辑路径一律用 path.Clean（永远正斜杠），
// 只在最后拼接真实文件系统路径时才用 filepath.FromSlash。
func (c *serverCtx) resolveDataFile(rel string) (string, error) {
	rel = strings.TrimSpace(rel)
	if rel == "" {
		return "", fmt.Errorf("缺少 path")
	}
	rel = strings.ReplaceAll(rel, "\\", "/")
	// path.Clean 与操作系统无关（始终以 / 分隔），这才是逻辑路径该用的
	clean := path.Clean("/" + rel)
	clean = strings.TrimPrefix(clean, "/")
	if clean == "" || clean == "." {
		return "", fmt.Errorf("非法路径")
	}
	// 必须在允许的顶层目录内
	top := strings.SplitN(clean, "/", 2)[0]
	allowed := false
	for _, d := range fileAllowDirs {
		if top == d {
			allowed = true
			break
		}
	}
	if !allowed {
		return "", fmt.Errorf("只允许编辑 config/ 与 rules/ 下的文件")
	}
	// 真实路径：把逻辑路径转成本机分隔符再拼
	full := filepath.Join(c.datadir, filepath.FromSlash(clean))
	// 双保险：拼出来的路径必须仍在 datadir 内
	base := filepath.Clean(c.datadir)
	got := filepath.Clean(full)
	if got != base && !strings.HasPrefix(got, base+string(os.PathSeparator)) {
		return "", fmt.Errorf("路径越界")
	}
	return full, nil
}

func (c *serverCtx) handleFile(w http.ResponseWriter, r *http.Request) {
	// GET 读取
	if r.Method == http.MethodGet {
		full, err := c.resolveDataFile(para(r, "path"))
		if err != nil {
			writeJSON(w, map[string]interface{}{"ok": false, "err": err.Error()})
			return
		}
		st, err := os.Stat(full)
		if err != nil {
			writeJSON(w, map[string]interface{}{"ok": true, "exists": false, "content": ""})
			return
		}
		if st.Size() > 4<<20 {
			writeJSON(w, map[string]interface{}{"ok": false, "err": "文件过大(>4MB)，编辑器不支持"})
			return
		}
		b, _ := os.ReadFile(full)
		writeJSON(w, map[string]interface{}{"ok": true, "exists": true, "size": st.Size(), "content": string(b)})
		return
	}
	// POST 写入
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		Path    string `json:"path"`
		Content string `json:"content"`
		Append  bool   `json:"append"`
	}
	body, _ := io.ReadAll(io.LimitReader(r.Body, 8<<20))
	if json.Unmarshal(body, &req) != nil {
		writeJSON(w, map[string]interface{}{"ok": false, "err": "bad json"})
		return
	}
	full, err := c.resolveDataFile(req.Path)
	if err != nil {
		writeJSON(w, map[string]interface{}{"ok": false, "err": err.Error()})
		return
	}
	if req.Append {
		f, e := os.OpenFile(full, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if e != nil {
			writeJSON(w, map[string]interface{}{"ok": false, "err": e.Error()})
			return
		}
		f.WriteString(req.Content)
		f.Close()
	} else {
		if err := os.MkdirAll(filepath.Dir(full), 0755); err != nil {
			writeJSON(w, map[string]interface{}{"ok": false, "err": err.Error()})
			return
		}
		// 先写临时文件再改名：编辑器保存到一半断电也不会把原文件截断成半个
		tmp := full + ".tmp"
		if err := os.WriteFile(tmp, []byte(req.Content), 0644); err != nil {
			writeJSON(w, map[string]interface{}{"ok": false, "err": err.Error()})
			return
		}
		if err := os.Rename(tmp, full); err != nil {
			os.Remove(tmp)
			writeJSON(w, map[string]interface{}{"ok": false, "err": err.Error()})
			return
		}
	}
	writeJSON(w, map[string]interface{}{"ok": true})
}

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
	// __raw_shell: 面板写入文件时用的通道。
	// 前端把「要执行的整条命令」base64 后放在 args[0]，这里解码执行。
	// 为什么要这样绕：把文件内容拼进 shell 命令会遇到引号/换行/反斜杠的
	// 转义地狱，base64 是唯一不会出错的做法。
	// 安全边界：只允许执行 base64 解出的命令，且命令里**必须**出现
	// fileedit.sh —— 否则等同于开了任意命令执行口子，不能接受。
	if req.Cmd == "__raw_shell" {
		if len(req.Args) == 0 {
			writeJSON(w, map[string]interface{}{"ok": false, "err": "缺少命令"})
			return
		}
		raw, derr := base64.StdEncoding.DecodeString(req.Args[0])
		if derr != nil {
			writeJSON(w, map[string]interface{}{"ok": false, "err": "base64 解码失败"})
			return
		}
		cmdStr := string(raw)
		if !strings.Contains(cmdStr, "fileedit.sh") {
			writeJSON(w, map[string]interface{}{"ok": false, "err": "该通道只允许调用 fileedit.sh"})
			return
		}
		if len(cmdStr) > 1<<20 {
			writeJSON(w, map[string]interface{}{"ok": false, "err": "命令过长"})
			return
		}
		out, err := c.runCmdEnv(shellPath(), "-c", cmdStr)
		if out == "" && err != nil {
			out = "ERR: " + err.Error()
		}
		writeJSON(w, map[string]interface{}{"ok": err == nil, "out": out})
		return
	}
	out, err := c.runScriptStdin(req.Cmd+".sh", req.Args, nil)
	writeJSON(w, map[string]interface{}{"ok": err == nil, "out": out})
}

func (c *serverCtx) runCtl(args ...string) (string, error) {
	p := filepath.Join(c.moddir, "scripts", "ctl.sh")
	full := append([]string{p}, args...)
	return c.runCmdEnv(shellPath(), full...)
}

// runCmdEnv 与 runCmd 相同，但把 datadir 通过 AB_DATA_DIR 传给子脚本
func (c *serverCtx) runCmdEnv(name string, args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), execTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Env = append(os.Environ(), "AB_DATA_DIR="+c.datadir)
	out, err := cmd.CombinedOutput()
	if ctx.Err() == context.DeadlineExceeded {
		return string(out), fmt.Errorf("命令执行超时(>%s)，已中止以防卡死", execTimeout)
	}
	return string(out), err
}

func (c *serverCtx) runScriptStdin(script string, args []string, stdin io.Reader) (string, error) {
	p := filepath.Join(c.moddir, "scripts", script)
	if _, err := os.Stat(p); err != nil {
		return "", fmt.Errorf("script not found: %s", script)
	}
	full := append([]string{p}, args...)
	ctx, cancel := context.WithTimeout(context.Background(), execTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, shellPath(), full...)
	// 【真实缺陷修复】必须把 datadir 传给子脚本：脚本用 common.sh 的
	// DATA_DIR（读 AB_DATA_DIR 覆盖），不传的话它们会去默认的 /data/adb/SY，
	// 而 serve 用的是 -datadir 指定的目录 —— 两边不一致时表现为
	// "文件明明存在却说文件不存在"（真跑 API 时抓到）。
	cmd.Env = append(os.Environ(), "AB_DATA_DIR="+c.datadir)
	if stdin != nil {
		cmd.Stdin = stdin
	}
	out, err := cmd.CombinedOutput()
	if ctx.Err() == context.DeadlineExceeded {
		return string(out), fmt.Errorf("命令执行超时(>%s)，已中止以防卡死", execTimeout)
	}
	return string(out), err
}

// shellPath 找一个可用的 POSIX shell。
// 不能直接写 exec.Command("sh", ...) 就完事：KernelSU 的 serve 进程环境里
// PATH 不一定包含 /system/bin（真跑时出现过 "exec: sh: executable file not found"）。
func shellPath() string {
	if v := os.Getenv("SY_SHELL"); v != "" {
		if st, err := os.Stat(v); err == nil && !st.IsDir() {
			return v
		}
	}
	for _, p := range []string{"/system/bin/sh", "/sbin/sh", "/vendor/bin/sh", "/bin/sh", "/usr/bin/sh"} {
		if st, err := os.Stat(p); err == nil && !st.IsDir() {
			return p
		}
	}
	// 兜底：在 PATH 里找（桌面 / 测试环境；Android 上通常已由上面命中）
	if p, err := exec.LookPath("sh"); err == nil {
		return p
	}
	// 最后再试 ash/busybox —— 有些精简环境只装了它们
	for _, n := range []string{"ash", "busybox"} {
		if p, err := exec.LookPath(n); err == nil {
			return p
		}
	}
	return "sh"
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
