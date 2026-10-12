# -*- coding: utf-8 -*-
"""把本地工作树整体推成一个提交（Git 直连不可达时的替代通道）

与 push_api.py 的区别：
  push_api.py  假定本地基准 tree 就是远端 tree（能 git diff），只能追加"变更文件"。
  push_full.py 不依赖本地有远端历史 —— 直接按路径逐一比对远端 tree，
               本地新增 / 修改 / 删除都能正确反映，且显式带 mode（保住 .sh 的可执行位）。

流程：GET refs -> GET commits -> GET trees(recursive) -> POST blobs -> POST trees -> POST commits -> PATCH refs

用法: python tools/push_full.py <token> <owner/repo> <branch> <消息文件>
"""
import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

TOKEN, REPO, BRANCH, MSG_FILE = sys.argv[1:5]
API = "https://api.github.com"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

with open(MSG_FILE, "r", encoding="utf-8") as fh:
    MSG = fh.read().rstrip() + "\n"


def api(method, path, payload=None):
    body = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(API + path, data=body, method=method)
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", "sy-adgh-push-full")
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            raw = r.read()
            return json.loads(raw.decode("utf-8")) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")
        raise SystemExit("HTTP %s %s %s\n%s" % (e.code, method, path, detail[:900]))


def git(*a):
    p = subprocess.run(["git"] + list(a), cwd=ROOT, capture_output=True)
    if p.returncode != 0:
        raise SystemExit("git %s 失败: %s" % (" ".join(a), p.stderr.decode("utf-8", "replace")[:400]))
    return p.stdout


# ---------- 1) 本地清单（tracked 文件的 mode + blob sha）----------
local = {}
for line in git("ls-files", "-s").decode("utf-8").splitlines():
    if not line.strip():
        continue
    meta, path = line.split("\t", 1)
    mode, sha, _stage = meta.split()
    local[path] = (mode, sha)
print(u"本地文件 %d 个" % len(local))

# ---------- 2) 远端 tree ----------
ref = api("GET", "/repos/%s/git/refs/heads/%s" % (REPO, BRANCH))
parent = ref["object"]["sha"]
base_tree = api("GET", "/repos/%s/git/commits/%s" % (REPO, parent))["tree"]["sha"]
print(u"远端 %s = %s" % (BRANCH, parent))
print(u"远端 tree = %s" % base_tree)

remote = {}
tr = api("GET", "/repos/%s/git/trees/%s?recursive=1" % (REPO, base_tree))
if tr.get("truncated"):
    raise SystemExit(u"远端 tree 被截断，无法安全比对")
for e in tr["tree"]:
    if e["type"] == "blob":
        remote[e["path"]] = (e["mode"], e["sha"])
print(u"远端文件 %d 个" % len(remote))

# ---------- 3) 计算增 / 改 / 删 ----------
added = sorted(set(local) - set(remote))
modified = sorted(p for p in set(local) & set(remote) if local[p] != remote[p])
deleted = sorted(set(remote) - set(local))
print(u"\n新增 %d / 修改 %d / 删除 %d" % (len(added), len(modified), len(deleted)))
for p in added:
    print(u"  + %s" % p)
for p in modified:
    print(u"  ~ %s" % p)
for p in deleted:
    print(u"  - %s" % p)
if not (added or modified or deleted):
    print(u"\n远端已是最新，无需推送")
    sys.exit(0)

# ---------- 4) 建 blob（只对新增/修改）----------
entries = []
for path in added + modified:
    data = open(os.path.join(ROOT, path), "rb").read()
    blob = api("POST", "/repos/%s/git/blobs" % REPO, {
        "content": base64.b64encode(data).decode("ascii"),
        "encoding": "base64",
    })
    entries.append({"path": path, "mode": local[path][0], "type": "blob", "sha": blob["sha"]})
    print(u"  blob %s %s (%d B)" % (local[path][0], path, len(data)))

# 删除：sha 置 null
for path in deleted:
    entries.append({"path": path, "mode": remote[path][0], "type": "blob", "sha": None})

# ---------- 5) 建 tree / commit / 移动 ref ----------
new_tree = api("POST", "/repos/%s/git/trees" % REPO, {"base_tree": base_tree, "tree": entries})
print(u"\n新 tree = %s" % new_tree["sha"])

commit = api("POST", "/repos/%s/git/commits" % REPO, {
    "message": MSG,
    "tree": new_tree["sha"],
    "parents": [parent],
})
print(u"新 commit = %s" % commit["sha"])

api("PATCH", "/repos/%s/git/refs/heads/%s" % (REPO, BRANCH), {
    "sha": commit["sha"],
    "force": False,
})
print(u"\n[ok] 已推送 %s -> %s" % (BRANCH, commit["sha"]))
