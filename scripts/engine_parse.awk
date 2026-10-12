# ============================================================
#  engine_parse.awk — 多语法过滤规则解析器
#  严格 POSIX awk 实现（兼容 gawk / mawk / busybox awk / toybox awk）
#  输入: 规则文本流（任意混排的 hosts / dnsmasq / AdBlock / AdGuard / uBO）
#  输出: TSV 记录（stdout），供 engine_emit.awk / engine_test.awk 消费
#
#  记录字段:
#    1  TYPE    N=网络规则  C=修饰规则(cosmetic/scriptlet/html)  W=DNS重写  X=无效
#    2  KIND    N: B=拦截 E=放行 | C: H=隐藏 U=取消隐藏 S=脚本注入 J=JS注入
#                 K=CSS注入 E2=扩展CSS F=HTML过滤 | W: rw | X: err
#    3  IMP     0|1  ($important)
#    4  FORM    D=纯域名 P=模式 R=正则   (TYPE=N/W)
#    5  VALUE   域名 / 模式 / 正则 / 选择器 / 脚本体
#    6  MODS    规范化修饰符列表(逗号分隔, 已排序)
#    7  CLIENT  $client= 作用域
#    8  CTAG    $ctag= 作用域
#    9  DENYALLOW $denyallow=
#    10 REWRITE $dnsrewrite= 值
#    11 HEUR    1=可从模式启发式提取域名
#    12 BAD     1=含 $badfilter
#    13 BKEY    badfilter 匹配键
#    14 SRC     来源文件
#    15 RAW     原始规则行
# ============================================================

BEGIN {
    OFS = "\t"
}

# ---------- 工具函数 ----------
function trim(s) { gsub(/^[ \t]+/, "", s); gsub(/[ \t]+$/, "", s); return s }
function lc(s)   { return tolower(s) }
function clean(s) { gsub(/[\t\r]/, " ", s); return s }

function is_ipv4(d) { return (d ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) }
function is_ipv6(d) { return (index(d, ":") > 0 && d ~ /^[0-9a-fA-F:]+$/) }

# 纯域名判定
function is_domain(d) {
    if (d == "") return 0
    if (index(d, ".") == 0) return 0
    if (is_ipv4(d) || is_ipv6(d)) return 0
    if (d !~ /^[a-z0-9_]([a-z0-9._-]*[a-z0-9_])?$/) return 0
    if (d !~ /\.[a-z]/) return 0
    if (index(d, "..") > 0) return 0
    if (substr(d, 1, 1) == ".") return 0
    return 1
}

# ---------- cosmetic 分隔符探测 ----------
# 结果: CSEP / CPOS；返回 1 表示命中
function find_csep(s,   seps, n, i, p, bestp, besti) {
    n = split("#@$#|#@?#|#@%#|#@#|#$#|#?#|#%#|##|$$|#@$|#@?#", seps, "|")
    bestp = 0; besti = 0
    for (i = 1; i <= n; i++) {
        p = index(s, seps[i])
        if (p > 0 && (bestp == 0 || p < bestp)) { bestp = p; besti = i }
    }
    CSEP = (besti ? seps[besti] : "")
    CPOS = bestp
    return (besti > 0)
}

# 判断 $$ 是否是 HTML 过滤分隔符（而非 URL 中的 $$）
function is_html_sep(s, p) {
    if (substr(s, p - 1, 1) == "#") return 0
    return 1
}

# ---------- 域名提取 ----------
# 结果: ED_DOM / ED_FORM(D|P|R) / ED_HEUR
function extract_domain(b,   t, sp, slash, host, haspath, colon, wild) {
    ED_DOM = ""; ED_FORM = ""; ED_HEUR = 0
    if (b == "") return
    # 正则规则 /.../ ：VALUE 存裸正则（不含定界符），便于直接参与匹配
    if (length(b) >= 2 && substr(b, 1, 1) == "/" && substr(b, length(b), 1) == "/") {
        ED_FORM = "R"; ED_DOM = substr(b, 2, length(b) - 2); return
    }
    t = b
    if (substr(t, 1, 2) == "||") t = substr(t, 3)
    else if (substr(t, 1, 1) == "|") t = substr(t, 2)
    sp = index(t, "://")
    if (sp > 0) t = substr(t, sp + 3)
    while (substr(t, 1, 2) == "*.") t = substr(t, 3)
    slash = index(t, "/")
    if (slash > 0) { host = substr(t, 1, slash - 1); haspath = 1 }
    else { host = t; haspath = 0 }
    colon = index(host, ":")
    if (colon > 0) host = substr(host, 1, colon - 1)
    sub(/\^.*$/, "", host)
    sub(/\|.*$/, "", host)
    gsub(/[ \t]/, "", host)
    host = lc(host)
    wild = (index(host, "*") > 0 || index(host, "?") > 0)
    if (wild) { ED_FORM = "P"; ED_DOM = host; ED_HEUR = 0; return }
    if (is_domain(host)) {
        if (haspath) { ED_FORM = "P"; ED_DOM = host; ED_HEUR = 1 }
        else { ED_FORM = "D"; ED_DOM = host }
        return
    }
    ED_FORM = "P"; ED_DOM = host; ED_HEUR = 0
}

# ---------- 修饰符解析 ----------
# 结果: M_IMP M_BAD M_RW M_CLIENT M_CTAG M_DENY M_DOM M_CLEAN(排序后) M_FULL
function parse_mods(mods,   n, parts, j, m, ml, toks, k, tmp, a, bb) {
    M_IMP = 0; M_BAD = 0; M_RW = ""; M_CLIENT = ""; M_CTAG = ""
    M_DENY = ""; M_DOM = ""; M_CLEAN = ""
    if (mods == "") return
    n = split(mods, parts, ",")
    k = 0
    for (j = 1; j <= n; j++) {
        m = trim(parts[j])
        if (m == "") continue
        ml = lc(m)
        if (ml == "important") { M_IMP = 1; k++; toks[k] = ml; continue }
        if (ml == "badfilter") { M_BAD = 1; continue }
        if (ml ~ /^dnsrewrite=/) { M_RW = substr(m, 12); k++; toks[k] = ml; continue }
        if (ml ~ /^client=/) { M_CLIENT = substr(m, 8); k++; toks[k] = ml; continue }
        if (ml ~ /^ctag=/) { M_CTAG = substr(m, 6); k++; toks[k] = ml; continue }
        if (ml ~ /^denyallow=/) { M_DENY = substr(m, 11); k++; toks[k] = ml; continue }
        if (ml ~ /^domain=/) { M_DOM = substr(m, 8); k++; toks[k] = ml; continue }
        k++; toks[k] = ml
    }
    # 插入排序（POSIX 无 asort）
    for (a = 2; a <= k; a++) {
        tmp = toks[a]; bb = a - 1
        while (bb >= 1 && toks[bb] > tmp) { toks[bb + 1] = toks[bb]; bb-- }
        toks[bb + 1] = tmp
    }
    M_CLEAN = ""
    for (a = 1; a <= k; a++) M_CLEAN = M_CLEAN (a > 1 ? "," : "") toks[a]
}

# ---------- 输出 ----------
function emit(type, kind, imp, form, value, mods, cli, ctag, deny, rw, heur, bad, bkey, raw) {
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", \
        type, kind, imp, form, clean(value), clean(mods), clean(cli), clean(ctag), \
        clean(deny), clean(rw), heur, bad, clean(bkey), SRC, clean(raw)
}

# ---------- cosmetic 规则 ----------
function parse_cosmetic(line,   scope, body, sep, kind, isexc, val, b2) {
    if (!find_csep(line)) return 0
    sep = CSEP
    if (sep == "$$" && !is_html_sep(line, CPOS)) return 0
    scope = trim(substr(line, 1, CPOS - 1))
    body = trim(substr(line, CPOS + length(sep)))
    if (body == "") return 0
    # 选择器/脚本体健全性: 必须含有可用字符，纯标点视为畸形行
    if (body !~ /[A-Za-z0-9]/ && body !~ /[.#\[*:]/) return 0
    isexc = 0
    kind = ""
    if (sep == "##") {
        if (body ~ /^\+js\(/) { kind = "S" }
        else if (substr(body, 1, 1) == "^") { kind = "F" }
        else kind = "H"
    }
    else if (sep == "#@#") { kind = "U" }
    else if (sep == "#$#") { kind = "K" }
    else if (sep == "#@$#") { kind = "U"; isexc = 1 }
    else if (sep == "#?#") { kind = "E2" }
    else if (sep == "#@?#") { kind = "U"; isexc = 1 }
    else if (sep == "#%#") { kind = (body ~ /^\/\/scriptlet/) ? "S" : "J" }
    else if (sep == "#@%#") { kind = "U"; isexc = 1 }
    else if (sep == "$$") { kind = "F" }
    else if (sep == "#@$") { kind = "U"; isexc = 1 }
    else return 0
    if (kind == "S") {
        b2 = body
        sub(/^\+js\(/, "", b2); sub(/\)$/, "", b2)
        sub(/^\/\/scriptlet\(/, "", b2); sub(/\)$/, "", b2)
        gsub(/^['"]/, "", b2); gsub(/['"]$/, "", b2)
        body = b2
    }
    val = scope "##" body
    emit("C", kind, 0, "", val, "", "", "", "", "", 0, 0, "", line)
    return 1
}

# ---------- 网络规则 ----------
function parse_network(line,   base, mods, after, p, exc, i, lastsl, tail) {
    base = trim(line); mods = ""; exc = 0
    # 例外前缀先行剥离，使 @@/regex/ 也能走正则分支
    if (substr(base, 1, 2) == "@@") { exc = 1; base = substr(base, 3) }
    # ---- 分离修饰符 ----
    if (substr(base, 1, 1) == "/") {
        # 正则规则: 以最后一个 '/' 为定界符（允许 /re/$important）
        lastsl = 0
        for (i = length(base); i >= 1; i--) { if (substr(base, i, 1) == "/") { lastsl = i; break } }
        if (lastsl > 1) {
            tail = substr(base, lastsl + 1)
            if (tail == "") { base = substr(base, 1, lastsl) }
            else if (substr(tail, 1, 1) == "$") { mods = substr(tail, 2); base = substr(base, 1, lastsl) }
        }
    } else {
        # 普通规则: '$' 之后为修饰符；'$' 位于首位时同样视为修饰符起点
        p = index(base, "$")
        if (p >= 1) {
            after = substr(base, p + 1)
            if (after ~ /^[A-Za-z~]/) { mods = after; base = substr(base, 1, p - 1) }
        }
    }
    base = trim(base)
    if (base == "") { emit("X", "err", 0, "", "", "", "", "", "", "", 0, 0, "", line); return }
    parse_mods(mods)
    extract_domain(base)
    if (ED_FORM == "" || ED_DOM == "") { emit("X", "err", 0, "", "", "", "", "", "", "", 0, 0, "", line); return }
    # 模式规则健全性: 保留字符 '$' 不应出现在模式中；纯标点且无通配符的模式无意义
    if (ED_FORM == "P") {
        if (index(ED_DOM, "$") > 0) { emit("X", "err", 0, "", "", "", "", "", "", "", 0, 0, "", line); return }
        if (ED_DOM !~ /[a-z0-9]/ && ED_DOM !~ /[*?]/) { emit("X", "err", 0, "", "", "", "", "", "", "", 0, 0, "", line); return }
    }
    k = (exc ? "E" : "B") "\034" base "\034" M_CLEAN
    if (M_RW != "") { emit("W", "rw", M_IMP, ED_FORM, ED_DOM, M_CLEAN, M_CLIENT, M_CTAG, M_DENY, M_RW, ED_HEUR, M_BAD, k, line); return }
    emit("N", (exc ? "E" : "B"), M_IMP, ED_FORM, ED_DOM, M_CLEAN, M_CLIENT, M_CTAG, M_DENY, "", ED_HEUR, M_BAD, k, line)
}

# ---------- hosts 行 ----------
function parse_hosts(line,   ip, rest, n, a, i, d, rw) {
    ip = line
    sub(/[ \t].*$/, "", ip)
    rest = substr(line, length(ip) + 1)
    sub(/[ \t]+/, "", rest)
    # 去掉行内注释
    sub(/[ \t]*#.*$/, "", rest)
    rest = trim(rest)
    if (rest == "") return 0
    rw = ""
    if (is_ipv4(ip)) {
        if (ip == "0.0.0.0" || ip == "127.0.0.1") rw = ""
        else rw = "NOERROR;A;" ip
    } else if (is_ipv6(ip)) {
        if (ip == "::" || ip == "::1" || ip == "0:0:0:0:0:0:0:1" || ip == "0:0:0:0:0:0:0:0") rw = ""
        else rw = "NOERROR;AAAA;" ip
    } else return 0
    n = split(rest, a, /[ \t]+/)
    for (i = 1; i <= n; i++) {
        d = lc(trim(a[i]))
        if (!is_domain(d)) continue
        if (rw == "") emit("N", "B", 0, "D", d, "", "", "", "", "", 0, 0, "", line)
        else emit("W", "rw", 0, "D", d, "", "", "", "", rw, 0, 0, "", line)
    }
    return 1
}

# ---------- dnsmasq 行 ----------
# 支持: address=/dom1/dom2/.../IP|#    local=/dom/    server=/dom/... (上游, 不拦截)
function parse_dnsmasq(line,   t, segs, n, i, last, ip, d) {
    t = line
    if (t ~ /^address=\//) t = substr(t, 10)
    else if (t ~ /^local=\//) t = substr(t, 8)
    else if (t ~ /^server=\//) return 1          # 指定上游, 非拦截语义 → 忽略
    else if (t ~ /^bogus-nxdomain=/) return 1
    else return 0
    n = split(t, segs, "/")
    if (n == 0) return 1
    last = segs[n]
    ip = ""
    if (last == "") { n = n - 1; last = (n >= 1 ? segs[n] : "") }
    if (last == "#") { n = n - 1 }
    else if (is_ipv4(last) || is_ipv6(last)) { ip = last; n = n - 1 }
    for (i = 1; i <= n; i++) {
        d = lc(trim(segs[i]))
        if (!is_domain(d)) continue
        if (ip == "") emit("N", "B", 0, "D", d, "", "", "", "", "", 0, 0, "", line)
        else if (is_ipv4(ip)) emit("W", "rw", 0, "D", d, "", "", "", "", "NOERROR;A;" ip, 0, 0, "", line)
        else emit("W", "rw", 0, "D", d, "", "", "", "", "NOERROR;AAAA;" ip, 0, 0, "", line)
    }
    return 1
}

# ---------- 主循环 ----------
{
    line = $0
    sub(/\r$/, "", line)
    line = trim(line)
    if (line == "") next
    if (substr(line, 1, 1) == "!" || substr(line, 1, 1) == ";") next
    if (substr(line, 1, 1) == "[") next          # [Adblock Plus 2.0]

    # cosmetic / scriptlet / html（必须先于 # 注释判断）
    if (parse_cosmetic(line)) next

    if (substr(line, 1, 1) == "#") next          # 注释

    # dnsmasq
    if (substr(line, 1, 8) == "address=" || substr(line, 1, 6) == "local=" || substr(line, 1, 7) == "server=" || substr(line, 1, 15) == "bogus-nxdomain=") {
        parse_dnsmasq(line)
        next
    }

    # hosts: 以 IP 开头
    if (line ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[ \t]/) { if (parse_hosts(line)) next }
    if (line ~ /^[0-9a-fA-F:]+:[0-9a-fA-F:]+[ \t]/) { if (parse_hosts(line)) next }

    # 纯域名
    dl = lc(line)
    if (is_domain(dl)) { emit("N", "B", 0, "D", dl, "", "", "", "", "", 0, 0, "", line); next }

    # 其余按网络规则处理（||... / /regex/ / 带修饰符 / 模式）
    parse_network(line)
}
