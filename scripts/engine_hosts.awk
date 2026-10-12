# ============================================================
#  engine_hosts.awk — hosts 生成器（AdGuard Home / uBlock 优先级语义）
#  优先级: 重要放行 > 重要拦截 > 普通放行 > 普通拦截
#  支持 $denyallow（例外规则对 denyallow 所列域不生效）
#  支持启发式域（从含路径/模式规则中提取的域名）参与放行/拦截
#  参数: -v AI= -v BI= -v AN= -v BN= -v HA= -v HB= -v ADENY= -v EXTRA=www -v NOW=
# ============================================================
BEGIN {
    load_ns(AI, "AI", 0)
    load_ns(BI, "BI", 1)
    load_ns(AN, "AN", 0)
    load_ns(BN, "BN", 1)
    load_ns(HA, "AN", 0)      # 启发式放行并入普通放行命名空间
    load_ns(HB, "BN", 1)      # 启发式拦截并入普通拦截命名空间
    load_deny(ADENY, "AN")
    ex = split(EXTRA, EXA, ",")
    print "# ============================================================"
    print "#  SY-Fusion 自动生成 hosts — AdGuard Home + uBlock Origin 融合引擎"
    print "#  生成时间: " NOW
    print "#  重要拦截=" LCNT["BI"] "  普通拦截=" LCNT["BN"] "  重要放行=" LCNT["AI"] "  普通放行=" LCNT["AN"]
    print "# ============================================================"
    print "127.0.0.1 localhost"
    print "::1 localhost"
    print "127.0.0.1 localhost.localdomain"
    print "::1 ip6-localhost ip6-loopback"
}

function load_ns(file, ns, cand,   line) {
    if (file == "") return
    while ((getline line < file) > 0) {
        gsub(/[ \t\r]/, "", line)
        if (line == "") continue
        SET[ns SUBSEP line] = 1
        LCNT[ns]++
        if (cand) CAND[line] = 1
    }
    close(file)
}

function load_deny(file, ns,   line, p, d, dl) {
    if (file == "") return
    while ((getline line < file) > 0) {
        gsub(/\r/, "", line)
        if (line == "") continue
        p = index(line, "|")
        if (p == 0) continue
        d = substr(line, 1, p - 1)
        dl = substr(line, p + 1)
        DENY[ns SUBSEP d] = DENY[ns SUBSEP d] (DENY[ns SUBSEP d] == "" ? "" : ",") dl
    }
    close(file)
}

function suf_in(ns, d,   p, i) {
    if ((ns SUBSEP d) in SET) return 1
    p = d
    while ((i = index(p, ".")) > 0) {
        p = substr(p, i + 1)
        if ((ns SUBSEP p) in SET) return 1
    }
    return 0
}

function suf_match(ns, d,   p, i) {
    if ((ns SUBSEP d) in SET) return d
    p = d
    while ((i = index(p, ".")) > 0) {
        p = substr(p, i + 1)
        if ((ns SUBSEP p) in SET) return p
    }
    return ""
}

function deny_hit(d, ns, m,   n, a, i, t, p, j) {
    if (m == "" || !((ns SUBSEP m) in DENY)) return 0
    n = split(DENY[ns SUBSEP m], a, ",")
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

function emit(d,   i, x) {
    print "0.0.0.0 " d
    for (i = 1; i <= ex; i++) {
        x = EXA[i]
        gsub(/[ \t]/, "", x)
        if (x != "") print "0.0.0.0 " x "." d
    }
}

END {
    blocked = 0; allowed = 0
    for (d in CAND) {
        if (d == "") continue
        if (suf_in("AI", d)) { allowed++; continue }
        if (suf_in("BI", d)) { emit(d); blocked++; continue }
        m = suf_match("AN", d)
        if (m != "" && !deny_hit(d, "AN", m)) { allowed++; continue }
        if (suf_in("BN", d)) { emit(d); blocked++; continue }
        allowed++
    }
}
