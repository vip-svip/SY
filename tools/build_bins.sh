#!/bin/sh
# ============================================================
#  tools/build_bins.sh — 交叉编译三架构 abserver
#
#  为什么不用 goreleaser / make：这个模块只需要一个静态二进制，
#  一条 go build 就够，加构建系统反而是负债。
#
#  用法: sh tools/build_bins.sh [输出目录，默认 bin]
# ============================================================
set -eu

MOD="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$MOD/bin}"
GO="${GO:-C:/Users/admin/.workbuddy-ai/toolchains/go/go/bin/go.exe}"
[ -x "$GO" ] || GO="go"

export GOCACHE="${GOCACHE:-C:/Users/admin/.workbuddy-ai/toolchains/gocache}"
export GOMODCACHE="${GOMODCACHE:-C:/Users/admin/.workbuddy-ai/toolchains/gomodcache}"
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
export GOFLAGS="-mod=mod"
export CGO_ENABLED=0

mkdir -p "$OUT"
cd "$MOD/src"

build() { # GOARCH GOARM 输出名
  arch="$1"; arm="$2"; name="$3"
  if [ -n "$arm" ]; then
    GOOS=linux GOARCH="$arch" GOARM="$arm" "$GO" build -trimpath -ldflags "-s -w" -o "$OUT/$name" .
  else
    GOOS=linux GOARCH="$arch" "$GO" build -trimpath -ldflags "-s -w" -o "$OUT/$name" .
  fi
  printf '  %-16s %s 字节\n' "$name" "$(wc -c < "$OUT/$name" | tr -d ' ')"
}

echo "构建目标目录: $OUT"
build arm64 ""  abserver-arm64
build arm   7   abserver-arm
build amd64 ""  abserver-amd64
chmod 0755 "$OUT"/abserver-* 2>/dev/null || true

# 校验 ELF magic，避免误把 host 二进制当交叉产物发出去
echo "校验 ELF 头:"
bad=0
for f in abserver-arm64 abserver-arm abserver-amd64; do
  magic="$(head -c 4 "$OUT/$f" | od -An -tx1 | tr -d ' \n')"
  if [ "$magic" = "7f454c46" ]; then
    printf '  ok   %s (ELF)\n' "$f"
  else
    printf '  FAIL %s magic=%s\n' "$f" "$magic"
    bad=1
  fi
done
[ $bad -eq 0 ] || exit 1
echo "OK: 三架构二进制就绪"
