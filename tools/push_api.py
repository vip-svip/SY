# -*- coding: utf-8 -*-
"""通过 GitHub REST API 推送本地提交（Git 直连被限速时的替代通道）

步骤：git/blobs -> git/trees(base_tree) -> git/commits -> PATCH git/refs
注意：Contents API 不返回 mode，必须用 blobs + trees 显式指定 100755/100644，
否则 .sh 会丢失可执行位。

用法: python tools/push_api.py <token> <owner/repo> <branch> <base_tree> <local_tree> [消息文件]
      <base_tree>  = 远端 main 当前提交的 tree（脚本会核对远端 tree 是否与之一致，不一致即中止）
      <local_tree> = 本地 HEAD 的 tree
      取法: git rev-parse HEAD^{tree} / git rev-parse HEAD~1^{tree}
      父提交自动取远端 ref 指向的提交，无需手填。
"""
import base64, json, os, subprocess, sys, urllib.request, urllib.error

TOKEN, REPO, BRANCH, BASE_TREE, LOCAL_TREE = sys.argv[1:6]
MSG_FILE = sys.argv[6] if len(sys.argv) > 6 else None
API = "https://api.github.com"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

if MSG_FILE:
    import io
    MSG = io.open(MSG_FILE, "r", encoding="utf-8").read()
else:
    MSG = u"通过 REST API 推送的提交"


def api(method, path, payload=None):
    body = None
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(API + path, data=body, method=method)
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", "sy-adgh-push")
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            raw = r.read()
            if not raw:
                return {}
            return json.loads(raw.decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")
        raise SystemExit("HTTP %s %s %s\n%s" % (e.code, method, path, detail[:900]))


def git(*a):
    return subprocess.run(["git"] + list(a), cwd=ROOT, capture_output=True,
                          text=True, encoding="utf-8", errors="replace").stdout


# 1) 远端当前 main
ref = api("GET", "/repos/%s/git/refs/heads/%s" % (REPO, BRANCH))
remote_commit = ref["object"]["sha"]
remote_tree = api("GET", "/repos/%s/git/commits/%s" % (REPO, remote_commit))["tree"]["sha"]
print(u"远端 %s = %s" % (BRANCH, remote_commit))
print(u"远端 tree        = %s" % remote_tree)
print(u"本地基准 tree    = %s" % BASE_TREE)
print(u"本地目标 tree    = %s" % LOCAL_TREE)
if remote_tree != BASE_TREE:
    raise SystemExit(u"远端 tree 与本地基准不一致，中止（需人工核对）")
print(u"[ok] 远端内容与本地基准一致，可安全在其上追加提交\n")

# 2) 变更清单
names = [l.strip() for l in
         git("diff", "--name-only", BASE_TREE, LOCAL_TREE).splitlines() if l.strip()]
if not names:
    raise SystemExit(u"没有变更")
print(u"待推送文件 %d 个：" % len(names))

# 3) 逐个上传 blob
tree_items = []
for p in names:
    with open(os.path.join(ROOT, p), "rb") as f:
        data = f.read()
    sha = api("POST", "/repos/%s/git/blobs" % REPO, {
        "content": base64.b64encode(data).decode("ascii"),
        "encoding": "base64"})["sha"]
    mode = "100755" if p.endswith(".sh") else "100644"
    tree_items.append({"path": p, "mode": mode, "type": "blob", "sha": sha})
    print(u"  %-34s %s  %s  %d B" % (p, mode, sha[:12], len(data)))

# 4) 新 tree
new_tree = api("POST", "/repos/%s/git/trees" % REPO,
               {"base_tree": remote_tree, "tree": tree_items})["sha"]
print(u"\n新 tree = %s" % new_tree)

# 5) 新 commit
commit = api("POST", "/repos/%s/git/commits" % REPO,
             {"message": MSG, "tree": new_tree, "parents": [remote_commit]})
print(u"新 commit = %s" % commit["sha"])

# 6) 更新 ref
api("PATCH", "/repos/%s/git/refs/heads/%s" % (REPO, BRANCH),
    {"sha": commit["sha"], "force": False})
print(u"已更新 refs/heads/%s" % BRANCH)
