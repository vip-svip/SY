#!/system/bin/sh
# ============================================================
#  build_apk.sh — 手工构建内置管理器 APK（跨平台：Linux / macOS / Windows）
#
#  为什么不走 Gradle：
#    模块的打包链路要能在没有 Android Studio、没有网络的机器上跑通。
#    Gradle 会拉一大堆依赖，而本 App 刻意只用框架 API、零第三方依赖，
#    所以 aapt2 + javac + d8 + zipalign + apksigner 五步就够了。
#
#  用法:
#    tools/build_apk.sh                 # 构建并输出到 app/SYManager.apk
#    SY_APK_OUT=/path/x.apk tools/build_apk.sh
#
#  依赖（均可用环境变量覆盖；不设则自动在 PATH / 常见位置探测）：
#    SY_JDK          JDK 根目录（含 bin/javac）
#    SY_BUILDTOOLS   Android build-tools 目录（含 aapt2/d8/zipalign/apksigner）
#    SY_ANDROID_JAR  android.jar
#    SY_BUILDTOOLS_BIN / SY_JDK_BIN  直接指定可执行文件所在目录
#
#  说明：旧版脚本把 javac.exe / d8.bat / C:/... 全部写死，只能在 Windows 上跑；
#        本版按 uname 自动选择可执行后缀与路径分隔，Linux/macOS/Windows 通用。
# ============================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
APP="$ROOT/app"

OS=$(uname -s 2>/dev/null || echo unknown)
case "$OS" in
  MINGW*|MSYS*|CYGWIN*) EXE=".exe"; BATE=".bat"; WIN=1 ;;
  *)                    EXE="";    BATE="";    WIN=0 ;;
esac

TC="${SY_TOOLCHAIN:-}"
JDK="${SY_JDK:-${TC:+$TC/jdk17/jdk-17.0.20.1+1}}"
BT="${SY_BUILDTOOLS:-${TC:+$TC/build-tools/android-15}}"
AJAR="${SY_ANDROID_JAR:-${TC:+$TC/android-sdk/platforms/android-34/android.jar}}"

find_bin() { # name -> echo path or empty
  n="$1"
  # 1) explicit bin dirs
  for d in "${SY_JDK_BIN:-}" "${SY_BUILDTOOLS_BIN:-}"; do
    [ -n "$d" ] && [ -x "$d/$n$EXE" ] && { echo "$d/$n$EXE"; return; }
  done
  # 2) JDK / build-tools roots
  [ -n "$JDK" ] && [ -x "$JDK/bin/$n$EXE" ] && { echo "$JDK/bin/$n$EXE"; return; }
  [ -n "$BT" ] && [ -x "$BT/$n$EXE" ] && { echo "$BT/$n$EXE"; return; }
  [ -n "$BT" ] && [ -x "$BT/$n$BATE" ] && { echo "$BT/$n$BATE"; return; }
  # 3) PATH
  command -v "$n" 2>/dev/null
}

JAVAC=$(find_bin javac); KEYTOOL=$(find_bin keytool)
AAPT2=$(find_bin aapt2); D8=$(find_bin d8)
ZIPALIGN=$(find_bin zipalign); APKSIGNER=$(find_bin apksigner)

OUTDIR="${SY_APK_DIR:-$APP/build}"
OUT="${SY_APK_OUT:-$APP/SYManager.apk}"
KS="${SY_KEYSTORE:-$OUTDIR/sy-debug.keystore}"
VCODE="${SY_VCODE:-1}"; VNAME="${SY_VNAME:-1.0.0}"

fail() { echo "ERR: $*" >&2; exit 1; }

echo "== 构建内置管理器 APK ($OS) =="
for f in "$JAVAC" "$AAPT2" "$ZIPALIGN" "$APKSIGNER"; do
  [ -n "$f" ] && [ -x "$f" ] || fail "缺少构建工具: ${f:-未找到}"
done
[ -n "$D8" ] && [ -x "$D8" ] || fail "缺少 d8"
[ -b "$AJAR" ] 2>/dev/null || [ -f "$AJAR" ] || fail "缺少 android.jar: ${AJAR:-未设置}"
[ -f "$APP/AndroidManifest.xml" ] || fail "缺少 AndroidManifest.xml"

rm -rf "$OUTDIR/obj" "$OUTDIR/gen" "$OUTDIR/classes" "$OUTDIR/dex"
mkdir -p "$OUTDIR/obj" "$OUTDIR/gen" "$OUTDIR/classes" "$OUTDIR/dex"

echo "-- aapt2 compile"
"$AAPT2" compile --dir "$APP/res" -o "$OUTDIR/res.zip" || fail "资源编译失败"

echo "-- aapt2 link"
"$AAPT2" link -o "$OUTDIR/base.apk" -I "$AJAR" \
  --manifest "$APP/AndroidManifest.xml" --java "$OUTDIR/gen" \
  --min-sdk-version 24 --target-sdk-version 34 \
  --version-code "$VCODE" --version-name "$VNAME" "$OUTDIR/res.zip" \
  || fail "资源链接失败"

echo "-- javac"
# 源码包含 app/java 与 app/xposed_stub（编译期 Xposed 桩），gen 里的 R.java
SRCLIST="$OUTDIR/srcs.txt"; : > "$SRCLIST"
find "$APP/java" "$APP/xposed_stub" "$OUTDIR/gen" -name '*.java' 2>/dev/null | sort >> "$SRCLIST"
[ -s "$SRCLIST" ] || fail "没有找到 Java 源文件"
# JDK 版本兼容：优先 -source/-target 8，失败则退回默认
SRCOPT=""
if "$JAVAC" -version >/dev/null 2>&1; then
  for s in 8 11 17; do
    echo 'class P{}' > "$OUTDIR/P.java"
    if "$JAVAC" -source $s -target $s -d "$OUTDIR/probe" "$OUTDIR/P.java" >/dev/null 2>&1; then
      SRCOPT="-source $s -target $s"; break
    fi
  done
fi
"$JAVAC" $SRCOPT -encoding UTF-8 -nowarn -classpath "$AJAR" -d "$OUTDIR/classes" @"$SRCLIST" \
  > "$OUTDIR/javac.log" 2>&1
[ $? -eq 0 ] || { tail -40 "$OUTDIR/javac.log"; fail "Java 编译失败"; }
[ -f "$OUTDIR/classes/com/syfusion/manager/MainActivity.class" ] || fail "Java 编译未产出预期 class"

echo "-- d8"
# 排除仅用于编译的 Xposed 桩（运行期由 LSPosed 提供，避免重复类）
find "$OUTDIR/classes" -name '*.class' ! -path '*/de/robv/*' > "$OUTDIR/cls.txt"
[ -s "$OUTDIR/cls.txt" ] || fail "没有找到 class 文件"
"$D8" --min-api 24 --output "$OUTDIR/dex" --lib "$AJAR" @"$OUTDIR/cls.txt" > "$OUTDIR/d8.log" 2>&1
[ $? -eq 0 ] || { head -20 "$OUTDIR/d8.log"; fail "d8 转换失败"; }
[ -f "$OUTDIR/dex/classes.dex" ] || fail "未生成 classes.dex"

echo "-- 组装"
cp -f "$OUTDIR/base.apk" "$OUTDIR/unsigned.apk"
if command -v zip >/dev/null 2>&1; then
  ( cd "$OUTDIR/dex" && zip -q -X "$OUTDIR/unsigned.apk" classes.dex ) || fail "写入 classes.dex 失败"
else
  "$(find_bin jar)" uf "$OUTDIR/unsigned.apk" -C "$OUTDIR/dex" classes.dex || fail "写入 classes.dex 失败"
fi
# LSPosed 入口清单
if [ -f "$APP/assets/xposed_init" ]; then
  ( cd "$APP" && zip -q -X "$OUTDIR/unsigned.apk" assets/xposed_init ) 2>/dev/null || true
fi

if [ ! -f "$KS" ]; then
  mkdir -p "$(dirname "$KS")" 2>/dev/null
  "$KEYTOOL" -genkeypair -keystore "$KS" -alias sy -keyalg RSA -keysize 2048 \
    -validity 10000 -storepass android -keypass android \
    -dname "CN=SY Fusion, OU=Module, O=SY, C=CN" >/dev/null 2>&1 || fail "密钥生成失败"
fi

echo "-- zipalign"
"$ZIPALIGN" -f -p 4 "$OUTDIR/unsigned.apk" "$OUTDIR/aligned.apk" || fail "zipalign 失败"

echo "-- apksigner"
"$APKSIGNER" sign --ks "$KS" --ks-pass pass:android --key-pass pass:android --ks-key-alias sy \
  --v1-signing-enabled true --v2-signing-enabled true --out "$OUT" "$OUTDIR/aligned.apk" \
  || fail "签名失败"
"$APKSIGNER" verify "$OUT" >/dev/null 2>&1 || fail "签名校验未通过"

SZ=$(wc -c < "$OUT" | tr -d ' ')
echo
echo "OK: $OUT ($SZ 字节)"
"$APKSIGNER" verify --print-certs "$OUT" 2>/dev/null | head -4
