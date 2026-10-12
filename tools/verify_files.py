# -*- coding: utf-8 -*-
"""通过 Contents API 校验若干关键文件与本地是否逐字节一致。

（raw.githubusercontent.com 在部分网络下不稳定，改用 API 取 base64 内容。）

用法: python tools/verify_files.py <token> <owner/repo> <ref> <文件...>
"""
import base64, hashlib, io, json, os, sys, urllib.request

TOKEN, REPO, REF = sys.argv[1:4]
FILES = sys.argv[4:]
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def api(path):
    r = urllib.request.Request("https://api.github.com" + path)
    r.add_header("Authorization", "Bearer " + TOKEN)
    r.add_header("Accept", "application/vnd.github+json")
    r.add_header("X-GitHub-Api-Version", "2022-11-28")
    r.add_header("User-Agent", "sy-adgh-verify-files")
    with urllib.request.urlopen(r, timeout=120) as resp:
        return json.loads(resp.read().decode("utf-8"))


allok = True
for path in FILES:
    j = api("/repos/%s/contents/%s?ref=%s" % (REPO, path, REF))
    remote = base64.b64decode(j["content"])
    lp = os.path.join(ROOT, path)
    if not os.path.isfile(lp):
        print(u"  %-24s 本地不存在" % path)
        allok = False
        continue
    local = io.open(lp, "rb").read()
    same = remote == local
    if not same:
        allok = False
    print(u"  %-24s 远端=%8d B  本地=%8d B  %s" %
          (path, len(remote), len(local), u"一致" if same else u"不一致"))
    if not same:
        print(u"     远端 sha256: %s" % hashlib.sha256(remote).hexdigest())
        print(u"     本地 sha256: %s" % hashlib.sha256(local).hexdigest())

print(u"\n结论: %s" % (u"全部一致" if allok else u"存在不一致"))
sys.exit(0 if allok else 1)
