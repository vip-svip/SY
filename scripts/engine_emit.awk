# ============================================================
#  engine_emit.awk — 将规范化记录发射为分类输出文件
#  POSIX awk。输入: records.tsv  输出: OUTDIR 下的分类文件
#  参数: -v OUT=目录  -v CLIENT=  -v CTAG=  -v STRICT=0|1
# ============================================================
BEGIN { FS = "\t"; OFS = "\t" }

function f(name) { return OUT "/" name }

function has_tok(mods, want,   n, a, i) {
    if (mods == "") return 0
    n = split(mods, a, ",")
    for (i = 1; i <= n; i++) if (a[i] == want) return 1
    return 0
}

# 取出指定修饰符的值 (csp=/removeparam=/redirect=/cookie=/header=)
function mod_val(mods, prefix,   n, a, i) {
    if (mods == "") return ""
    n = split(mods, a, ",")
    for (i = 1; i <= n; i++) if (index(a[i], prefix) == 1) return substr(a[i], length(prefix) + 1)
    return ""
}

# 作用域判定: 返回 1=跳过该规则
function scoped_out(cli, ctag) {
    if (STRICT != "1") return 0
    if (cli != "") {
        if (CLIENT == "") return 1
        if (index("," cli ",", "," CLIENT ",") == 0) return 1
    }
    if (ctag != "") {
        if (CTAG == "") return 1
        if (index("," ctag ",", "," CTAG ",") == 0) return 1
    }
    return 0
}

$1 == "N" {
    kind = $2; imp = $3; form = $4; val = $5; mods = $6; cli = $7; ctag = $8; deny = $9
    if (val == "") next
    if (scoped_out(cli, ctag)) { skipped++; next }
    if (form == "D") {
        if (kind == "E") fname = (imp == "1") ? "allow_imp.txt" : "allow.txt"
        else             fname = (imp == "1") ? "block_imp.txt" : "block.txt"
        print val >> f(fname)
        if (deny != "") print val "|" deny >> f("allow_deny.txt")
        cnt[fname]++
    }
    else if (form == "P") {
        fname = (kind == "E") ? "pattern_allow.txt" : "pattern_block.txt"
        print val, mods, cli, ctag >> f(fname)
        cnt[fname]++
        if ($11 == "1") {
            fname2 = (kind == "E") ? "heuristic_allow.txt" : "heuristic_block.txt"
            print val >> f(fname2)
            cnt[fname2]++
            if (kind == "E" && deny != "") print val "|" deny >> f("allow_deny.txt")
        }
    }
    else if (form == "R") {
        fname = (kind == "E") ? "regex_allow.txt" : "regex_block.txt"
        # 记录中存的是裸正则，输出时补回 AdGuard/uBO 的 /.../ 定界符
        print "/" val "/" >> f(fname)
        cnt[fname]++
    }
    next
}

$1 == "W" {
    val = $5; rw = $10; cli = $7; ctag = $8
    if (val == "" || rw == "") next
    if (scoped_out(cli, ctag)) { skipped++; next }
    print val "|" rw "|" $3 >> f("rewrite.txt")
    cnt["rewrite.txt"]++
    next
}

$1 == "C" {
    kind = $2; val = $5
    if (val == "") next
    if (kind == "H")      { print val >> f("cosmetic_hide.txt"); cnt["cosmetic_hide.txt"]++ }
    else if (kind == "U") { print val >> f("cosmetic_unhide.txt"); cnt["cosmetic_unhide.txt"]++ }
    else if (kind == "S") { print val >> f("scriptlets.txt"); cnt["scriptlets.txt"]++ }
    else if (kind == "J") { print val >> f("js_inject.txt"); cnt["js_inject.txt"]++ }
    else if (kind == "K") { print val >> f("css_inject.txt"); cnt["css_inject.txt"]++ }
    else if (kind == "E2"){ print val >> f("ext_css.txt"); cnt["ext_css.txt"]++ }
    else if (kind == "F") { print val >> f("html_filter.txt"); cnt["html_filter.txt"]++ }
    next
}

$1 == "X" { bad++; next }

END {
    # 修饰符型规则 (供 MITM / 注入层消费)
    printf "%d\t%d\n", skipped + 0, bad + 0 > f(".emit_meta")
    close(f(".emit_meta"))
}
