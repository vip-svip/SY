# -*- coding: utf-8 -*-
"""更新 GitHub Release 附件（v1.0.0）：替换 ZIP 与 .sha256

用法: python tests/_release_update.py <token> <owner/repo> <tag>
"""
import io, json, os, sys, urllib.request, urllib.error

TOKEN, REPO, TAG = sys.argv[1:4]
API = "https://api.github.com"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def req(method, url, data=None, ctype=None):
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Authorization", "Bearer " + TOKEN)
    r.add_header("Accept", "application/vnd.github+json")
    r.add_header("X-GitHub-Api-Version", "2022-11-28")
    r.add_header("User-Agent", "sy-adgh-release")
    if ctype:
        r.add_header("Content-Type", ctype)
    try:
        with urllib.request.urlopen(r, timeout=600) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw.decode("utf-8")) if raw else {})
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")[:800]


# 1) 找到 release
st, rel = req("GET", "%s/repos/%s/releases/tags/%s" % (API, REPO, TAG))
if st != 200:
    raise SystemExit(u"取 release 失败: %s %s" % (st, rel))
print(u"release: %s (id=%s)" % (rel["name"], rel["id"]))
print(u"现有附件:")
for a in rel["assets"]:
    print(u"  %-28s %10d B  id=%s" % (a["name"], a["size"], a["id"]))

# 2) 待上传文件
files = []
for name in ("SY_v1.0.0.zip", "SY_v1.0.0.zip.sha256"):
    p = os.path.join(ROOT, "dist", name)
    if os.path.isfile(p):
        files.append((name, p, os.path.getsize(p)))
if not files:
    raise SystemExit(u"dist 下没有待上传文件")

# 3) 删旧同名附件
for name, _, _ in files:
    for a in rel["assets"]:
        if a["name"] == name:
            st, msg = req("DELETE", "%s/repos/%s/releases/assets/%s" % (API, REPO, a["id"]))
            print(u"  删除旧附件 %s -> HTTP %s" % (name, st))
            if st not in (204, 200):
                raise SystemExit(u"删除失败: %s" % msg)

# 4) 上传新附件
upload_base = rel["upload_url"].split("{")[0]
for name, path, size in files:
    with io.open(path, "rb") as f:
        data = f.read()
    st, out = req("POST", "%s?name=%s" % (upload_base, name), data,
                  "application/octet-stream")
    if st not in (200, 201):
        raise SystemExit(u"上传 %s 失败: %s %s" % (name, st, out))
    print(u"  已上传 %-28s %10d B  state=%s" % (out["name"], out["size"], out["state"]))

# 5) 复核
st, rel = req("GET", "%s/repos/%s/releases/tags/%s" % (API, REPO, TAG))
print(u"\n复核 release 附件:")
ok = True
for a in rel["assets"]:
    local = os.path.join(ROOT, "dist", a["name"])
    ls = os.path.getsize(local) if os.path.isfile(local) else -1
    match = u"一致" if ls == a["size"] else u"不一致(本地=%s)" % ls
    if ls != a["size"]:
        ok = False
    print(u"  %-28s 远端=%10d B  本地=%10d B  %s" % (a["name"], a["size"], ls, match))
print(u"\n结论: %s" % (u"Release 附件与本地 dist 完全一致" if ok else u"存在不一致"))
