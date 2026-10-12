#!/bin/bash
# 下载 Android / Go 构建工具链到隔离目录（不污染用户环境）
set -u
BASE="C:/Users/admin/.workbuddy-ai/toolchains"
DL="$BASE/_dl"
mkdir -p "$DL"
cd "$DL" || exit 1

fetch() { # name url
  n="$1"; u="$2"
  if [ -s "$n" ]; then echo "[skip] $n 已存在"; return 0; fi
  echo "[get ] $n"
  curl -sL --retry 3 --retry-delay 3 -m 1800 -o "$n.part" "$u" && mv "$n.part" "$n" && echo "[ok  ] $n $(stat -c%s "$n" 2>/dev/null || echo '?') bytes" || echo "[FAIL] $n"
}

# 1) JDK 17 (Microsoft OpenJDK，解压后约 300MB)
fetch "jdk17.zip" "https://aka.ms/download-jdk/microsoft-jdk-17-windows-x64.zip"

# 2) Android 命令行工具
fetch "cmdline-tools.zip" "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"

# 3) Android build-tools 34 (aapt2 / d8 / zipalign / apksigner)
fetch "build-tools-34.zip" "https://dl.google.com/android/repository/build-tools_r34-windows.zip"

# 4) Android platform 34 (android.jar)
fetch "platform-34.zip" "https://dl.google.com/android/repository/platform-34_r03.zip"

# 5) Go 1.23.4 (用于扩展 abserver)
fetch "go.zip" "https://dl.google.com/go/go1.23.4.windows-amd64.zip"

echo "=== 下载完成 ==="
ls -la "$DL"
