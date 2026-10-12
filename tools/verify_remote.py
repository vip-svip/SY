# -*- coding: utf-8 -*-
"""逐项比对远端 tree 与本地 HEAD 的 (path, mode, blob sha)，找出任何差异。

用法: python tests/_verify_remote.py <token> <owner/repo> <commit>
"""
import json, subprocess, sys, urllib.request, urllib.error

TOKEN, REPO, COMMIT = sys.argv[1:4]
API = "https://api.github.com"


def api(path):
    req = urllib.request.Request(API + path)
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", "sy-adgh-verify")
    with urllib.request.urlopen(req, timeout=90) as r:
        return json.loads(r.read().decode("utf-8"))


remote = {}
for e in api("/repos/%s/git/trees/%s?recursive=1" % (REPO, COMMIT))["tree"]:
    if e["type"] == "blob":
        remote[e["path"]] = (e["mode"], e["sha"])

local = {}
out = subprocess.run(["git", "ls-tree", "-r", "HEAD"], capture_output=True,
                     text=True, encoding="utf-8", errors="replace").stdout
for ln in out.splitlines():
    if not ln.strip():
        continue
    meta, path = ln.split("\t", 1)
    mode, typ, sha = meta.split()
    local[path] = (mode, sha)

only_remote = sorted(set(remote) - set(local))
only_local = sorted(set(local) - set(remote))
diff = sorted(p for p in (set(remote) & set(local)) if remote[p] != local[p])

print(u"远端文件 %d 个 | 本地文件 %d 个" % (len(remote), len(local)))
print(u"仅远端存在: %s" % (only_remote or u"无"))
print(u"仅本地存在: %s" % (only_local or u"无"))
if diff:
    print(u"内容/权限不一致 %d 项：" % len(diff))
    for p in diff:
        print(u"  %-34s 远端=%s %s   本地=%s %s"
              % (p, remote[p][0], remote[p][1][:12], local[p][0], local[p][1][:12]))
else:
    print(u"内容/权限不一致: 无")
print(u"\n结论: %s" % (u"远端与本地逐项完全一致"
                      if not (only_remote or only_local or diff) else u"存在差异，见上"))
