# ============================================================
#  engine_test.awk — 规则命中诊断（完整优先级求值）
#  单域模式: -v REC=records.tsv -v DOMAIN=xxx        → 输出 JSON 单行
#  批量模式: -v REC=records.tsv -v CASES=域名清单文件 → 输出 TSV 多行
#            (列: 域名 \t 结果 \t 优先级名 \t 命中规则 \t 浏览器侧规则数)
#  可选: -v CLIENT= -v CTAG= -v STRICT=0|1
#  入参可为裸域名、host/path 或完整 URL
#  优先级: 4=重要放行 > 3=重要拦截/重要重写 > 2=普通放行/普通重写 > 1=普通拦截 > 0=未命中
# ============================================================
BEGIN {
    FS = "\t"

    # ---------- 入参防护 ----------
    if (REC == "") {
        if (CASES != "") print "ERR\t\t\trecords.tsv 未指定"
        else print "{\"error\":\"REC not set\"}"
        exit 1
    }

    # ---------- 第一遍: 装载规则（一次性）----------
    while ((getline ln < REC) > 0) {
        n = split(ln, F, "\t")
        if (n < 13) continue
        type = F[1]; kind = F[2]; imp = F[3]; form = F[4]; val = F[5]
        mods = F[6]; cli = F[7]; ctag = F[8]; deny = F[9]; rwv = F[10]
        raw = (n >= 15) ? F[15] : val
        if (val == "") continue
        if (STRICT == "1") {
            if (cli != "" && (CLIENT == "" || index("," cli ",", "," CLIENT ",") == 0)) continue
            if (ctag != "" && (CTAG == "" || index("," ctag ",", "," CTAG ",") == 0)) continue
        }
        if (type == "C") {
            # cosmetic / 注入规则：val 形如 scope##body（解析器统一用 ## 连接）
            p = index(val, "##")
            nc++
            if (p > 0) { CSCOPE[nc] = substr(val, 1, p - 1); CBODY[nc] = substr(val, p + 2) }
            else       { CSCOPE[nc] = ""; CBODY[nc] = val }
            CKIND[nc] = kind
            continue
        }
        if (type == "N" || type == "W") {
            if (form == "D") {
                tag = (type == "W" ? "W" : kind) imp
                DSET[tag SUBSEP val] = 1
                DRULE[tag SUBSEP val] = raw
                DMODS[tag SUBSEP val] = mods
                DDENY[tag SUBSEP val] = deny
                if (type == "W") DRW[tag SUBSEP val] = rwv
            } else {
                np++
                PT[np] = form; PV[np] = val; PK[np] = kind; PI[np] = imp
                PM[np] = mods; PR[np] = raw; PW[np] = rwv
                PTYPE[np] = type; PDENY[np] = deny
                # 启发式域：与 hosts 生成保持一致的域名级判定
                if (form == "P" && F[11] == "1") {
                    htag = kind imp
                    DSET[htag SUBSEP val] = 1
                    DRULE[htag SUBSEP val] = raw
                    DMODS[htag SUBSEP val] = mods
                    DDENY[htag SUBSEP val] = deny
                }
            }
        }
    }
    close(REC)

    # ---------- 批量模式 ----------
    if (CASES != "") {
        while ((getline c < CASES) > 0) {
            sub(/\r$/, "", c)
            if (c == "") continue
            if (substr(c, 1, 1) == "#") continue
            nc = split(c, cc, "\t")
            d = tolower(cc[1])
            gsub(/^[ \t]+|[ \t]+$/, "", d)
            if (d == "") continue
            evaluate(d)
            printf "%s\t%s\t%s\t%s\t%s\n", d, BESTRES, PNAME, BESTRULE, COSN + 0
        }
        close(CASES)
        exit
    }

    # ---------- 单域模式 ----------
    d = tolower(DOMAIN)
    gsub(/^[ \t]+|[ \t]+$/, "", d)
    evaluate(d)
    printf "{\"domain\":\"%s\",\"result\":\"%s\",\"priority\":\"%s\",\"rule\":\"%s\",\"mods\":\"%s\",\"rewrite\":\"%s\",\"url_rules\":%d,\"cosmetic\":%d,\"cosmetic_rules\":\"%s\"}\n", \
        esc(d), esc(BESTRES), PNAME, esc(BESTRULE), esc(BESTMODS), esc(BESTRW), np + 0, COSN + 0, esc(COSLIST)
}

# 统计作用于该域名的 cosmetic / 注入规则（DNS 层不拦截，但浏览器侧会生效）
function cos_scan(   i) {
    COSN = 0; COSLIST = ""
    for (i = 1; i <= nc; i++) {
        if (!cos_scope_hit(CSCOPE[i])) continue
        COSN++
        if (COSN <= 3) COSLIST = COSLIST (COSN > 1 ? " | " : "") CKIND[i] ":" CBODY[i]
    }
    if (COSN > 3) COSLIST = COSLIST " | …"
}

# cosmetic 作用域命中判定：支持空作用域(全域)、逗号列表、~ 取反、实体通配 (*)
# 父域继承语义与 uBO/AdGuard 一致: scope=example.com 同时作用于 sub.example.com
function cos_scope_hit(s,   n2, sa, j, t, L) {
    if (s == "") return 1
    n2 = split(s, sa, ",")
    for (j = 1; j <= n2; j++) {
        t = sa[j]
        gsub(/^[ \t]+|[ \t]+$/, "", t)
        if (t == "") continue
        if (substr(t, 1, 1) == "~") continue
        if (index(t, "*") > 0) {
            if (dom ~ ("(^|\\.)" ent_re(t) "$")) return 1
            continue
        }
        if (dom == t) return 1
        L = length(t)
        if (length(dom) > L + 1 && substr(dom, length(dom) - L + 1) == t && \
            substr(dom, length(dom) - L, 1) == ".") return 1
    }
    return 0
}

# 实体通配 → 正则: example.* => example\.[^.]*
function ent_re(t,   r, i, c, n) {
    r = ""; n = length(t)
    for (i = 1; i <= n; i++) {
        c = substr(t, i, 1)
        if (c == "*") r = r "[^.]*"
        else if (index(".\\^$[]|(){}+?", c) > 0) r = r "\\" c
        else r = r c
    }
    return r
}

# ---------- 单域求值 ----------
# 入参可以是裸域名、host/path，或完整 URL；据此推导 dom 与 url
function evaluate(d,   i, hit, t) {
    t = d
    if (t ~ /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//) {
        url = t
        sub(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//, "", t)
    } else if (index(t, "/") > 0) {
        url = "http://" t
    } else {
        url = "http://" t "/"
    }
    dom = t
    sub(/[?#].*$/, "", dom)
    sub(/\/.*$/, "", dom)
    sub(/^[^@]*@/, "", dom)
    sub(/:[0-9]+$/, "", dom)
    dom = tolower(dom)
    if (dom == "") dom = tolower(d)
    cos_scan()
    BESTP = 0; BESTRES = "none"; BESTRULE = ""; BESTMODS = ""; BESTRW = ""
    dcheck("E1", 4, 1)
    dcheck("B1", 3, 0)
    dcheck("W1", 3, 0)
    dcheck("E0", 2, 1)
    dcheck("W0", 2, 0)
    dcheck("B0", 1, 0)
    for (i = 1; i <= np; i++) {
        hit = 0
        if (PT[i] == "R") { if (url ~ PV[i] || dom ~ PV[i]) hit = 1 }
        else hit = pat_hit(PV[i], url, dom)
        if (!hit) continue
        if (PK[i] == "E" && PDENY_ok(i) == 0) continue
        if (PTYPE[i] == "W") { consider(1, PR[i], PM[i], PW[i]); continue }
        if (PK[i] == "E") consider((PI[i] == "1") ? 4 : 2, PR[i], PM[i], "")
        else consider((PI[i] == "1") ? 3 : 1, PR[i], PM[i], "")
    }
    if (BESTRES == "allow") PNAME = (BESTP == 4) ? "important-allow" : "allow"
    else if (BESTRES == "rewrite") PNAME = (BESTP == 3) ? "important-rewrite" : "dnsrewrite"
    else if (BESTRES == "block") PNAME = (BESTP == 3) ? "important-block" : "block"
    else PNAME = "none"
}

function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); gsub(/[\r\n\t]/, " ", s); return s }

function consider(p, r, m, w) {
    if (p > BESTP) {
        BESTP = p; BESTRULE = r; BESTMODS = m; BESTRW = w
        if (w != "") BESTRES = "rewrite"
        else if (p == 4 || p == 2) BESTRES = "allow"
        else BESTRES = "block"
    }
}

function PDENY_ok(i) {
    if (PDENY[i] == "") return 1
    return (deny_hit(dom, PDENY[i]) == 0)
}

function dcheck(tag, pri, isexc,   p, i, k, d) {
    if (pri <= BESTP) return
    p = dom
    while (1) {
        k = tag SUBSEP p
        if (k in DSET) {
            d = DDENY[k]
            if (!(isexc && d != "" && deny_hit(dom, d))) {
                consider(pri, DRULE[k], DMODS[k], (k in DRW) ? DRW[k] : "")
                return
            }
        }
        i = index(p, ".")
        if (i == 0) break
        p = substr(p, i + 1)
    }
}

function deny_hit(d, deny,   n, a, i, t, p, j) {
    n = split(deny, a, "|")
    for (i = 1; i <= n; i++) {
        t = a[i]
        gsub(/[ \t]/, "", t)
        if (t == "") continue
        if (d == t) return 1
        p = d
        while ((j = index(p, ".")) > 0) { p = substr(p, j + 1); if (p == t) return 1 }
    }
    return 0
}

function pat_hit(pat, url, dom,   re) {
    re = abp_re(pat)
    if (re == "") return 0
    if (url ~ re) return 1
    if (dom ~ re) return 1
    return 0
}

function abp_re(p,   r, i, c, n, end, trail) {
    r = ""; n = length(p)
    if (n == 0) return ""
    if (substr(p, 1, 2) == "||") { r = "^[a-z]+://([^/]+\\.)?"; i = 3 }
    else if (substr(p, 1, 1) == "|") { r = "^"; i = 2 }
    else i = 1
    trail = (substr(p, n, 1) == "|")
    end = trail ? n - 1 : n
    for (; i <= end; i++) {
        c = substr(p, i, 1)
        if (c == "*") r = r ".*"
        else if (c == "^") r = r "([^a-zA-Z0-9_.%-]|$)"
        else if (index("\\^$.[]|(){}+?", c) > 0) r = r "\\" c
        else r = r c
    }
    if (trail) r = r "$"
    return r
}
