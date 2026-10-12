#!/system/bin/sh
# ============================================================
#  build_apk.sh — 手工构建内置管理器 APK
#
#  为什么不走 Gradle：
#    模块的打包链路要能在没有 Android Studio、没有网络的机器上跑通。
#    Gradle 会拉一大堆依赖，而本 App 刻意只用框架 API、零第三方依赖，
#    所以 aapt2 + javac + d8 + zipalign + apksigner 五步就够了。
#
#  用法:
#    tools/build_apk.sh                 # 构建并输出到 app/build/SYManager.apk
#    SY_APK_OUT=/path/x.apk tools/build_apk.sh
#
#  依赖（可用环境变量覆盖）：
#    SY_JDK       JDK 根目录（含 bin/javac）
#    SY_BUILDTOOLS Android build-tools 目录（含 aapt2/d8/apksigner）
#    SY_ANDROID_JAR  android.jar
# ============================================================
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
APP="$ROOT/app"

TC="${SY_TOOLCHAIN:-C:/Users/admin/.workbuddy-ai/toolchains}"
JDK="${SY_JDK:-$TC/jdk17/jdk-17.0.20.1+1}"
BT="${SY_BUILDTOOLS:-$TC/build-tools/android-14}"
AJAR="${SY_ANDROID_JAR:-$TC/android-sdk/platforms/android-34/android.jar}"

OUTDIR="${SY_APK_DIR:-$APP/build}"
# 最终产物直接落在 app/ 下：installapp.sh 与打包脚本都按这个路径取件，
# 中间产物（class/dex/密钥）留在 app/build/ 里，打包时被排除。
OUT="${SY_APK_OUT:-$APP/SYManager.apk}"
KS="${SY_KEYSTORE:-$OUTDIR/sy-debug.keystore}"

JAVAC="$JDK/bin/javac.exe"
KEYTOOL="$JDK/bin/keytool.exe"
AAPT2="$BT/aapt2.exe"
D8="$BT/d8.bat"
ZIPALIGN="$BT/zipalign.exe"
APKSIGNER="$BT/apksigner.bat"

# d8.bat / apksigner.bat 是批处理，靠 JAVA_HOME 找 java，
# 不会继承我们用绝对路径调用 javac 的那套。
export JAVA_HOME="$JDK"
case ":$PATH:" in
  *":$JDK/bin:"*) ;;
  *) PATH="$JDK/bin:$PATH"; export PATH ;;
esac

fail() { echo "ERR: $*" >&2; exit 1; }

# MSYS/Git-Bash 只对命令行参数做路径转换，写进 @argfile 的路径不会转，
# 而 javac/d8 是原生 Windows 程序，认不了 /c/Users/... 这种形式。
# 统一在写入前转成 C:/Users/... 混合形式。
winpath() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1"
  else
    case "$1" in
      /[a-zA-Z]/*)
        d=$(printf '%s' "$1" | cut -c2 | tr 'a-z' 'A-Z')
        printf '%s:%s' "$d" "$(printf '%s' "$1" | cut -c3-)"
        ;;
      *) printf '%s' "$1" ;;
    esac
  fi
}

echo "== 构建内置管理器 APK =="
for f in "$JAVAC" "$AAPT2" "$ZIPALIGN"; do
  [ -x "$f" ] || fail "缺少构建工具: $f"
done
[ -f "$AJAR" ] || fail "缺少 android.jar: $AJAR"
[ -f "$APP/AndroidManifest.xml" ] || fail "缺少 AndroidManifest.xml"

rm -rf "$OUTDIR/obj" "$OUTDIR/gen" "$OUTDIR/classes" "$OUTDIR/dex"
mkdir -p "$OUTDIR/obj" "$OUTDIR/gen" "$OUTDIR/classes" "$OUTDIR/dex"

# ---------- 1) 编译资源 ----------
echo "-- aapt2 compile"
"$AAPT2" compile --dir "$APP/res" -o "$OUTDIR/obj/res.zip" \
  || fail "资源编译失败"

# ---------- 2) 链接资源 + 生成 R.java ----------
echo "-- aapt2 link"
"$AAPT2" link \
  -o "$OUTDIR/base.apk" \
  -I "$AJAR" \
  --manifest "$APP/AndroidManifest.xml" \
  --java "$OUTDIR/gen" \
  --min-sdk-version 24 \
  --target-sdk-version 34 \
  --version-code 1 \
  --version-name 1.0.0 \
  "$OUTDIR/obj/res.zip" \
  || fail "资源链接失败"

# ---------- 3) 编译 Java ----------
echo "-- javac"
# 工程路径可能含空格（"WorkBuddy AI"），直接把文件列表塞进命令行会被
# 词分割拆散，所以统一走 javac/d8 的 @argfile 机制，逐行带引号列出。
SRCLIST="$OUTDIR/srcs.txt"
: > "$SRCLIST"
find "$APP/java" "$OUTDIR/gen" -name '*.java' 2>/dev/null | while IFS= read -r f; do
  printf '"%s"\n' "$(winpath "$f")" >> "$SRCLIST"
done
[ -s "$SRCLIST" ] || fail "没有找到 Java 源文件"
# 输出重定向到文件再读：javac 的中文提示在 GBK 环境下会被 grep 当成二进制，
# 管道一过滤就看不到真实错误了。同时把语言锁成英文，避免乱码。
"$JAVAC" -encoding UTF-8 -source 8 -target 8 -nowarn \
  -J-Duser.language=en -J-Duser.country=US \
  -bootclasspath "$AJAR" -classpath "$AJAR" \
  -d "$OUTDIR/classes" "@$SRCLIST" > "$OUTDIR/javac.log" 2>&1
JRC=$?
if [ $JRC -ne 0 ]; then
  echo "javac 输出:"
  grep -v '^Note:' "$OUTDIR/javac.log" | head -40
  fail "Java 编译失败 (exit $JRC)"
fi
[ -f "$OUTDIR/classes/com/syfusion/manager/MainActivity.class" ] \
  || fail "Java 编译未产出预期 class"

# ---------- 4) 转 dex ----------
echo "-- d8"
# d8 的 @argfile 不会剥掉引号，而工程路径里有空格（"WorkBuddy AI"），
# 两条路都走不通，所以先把 class 复制到无空格的暂存目录再转。
STAGE="${SY_APK_STAGE:-/c/Users/admin/AppData/Local/Temp/syapk-stage}"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -r "$OUTDIR/classes" "$STAGE/classes" || fail "暂存 class 失败"

CLSLIST="$STAGE/classes.txt"
: > "$CLSLIST"
find "$STAGE/classes" -name '*.class' 2>/dev/null | while IFS= read -r f; do
  printf '%s\n' "$(winpath "$f")" >> "$CLSLIST"
done
[ -s "$CLSLIST" ] || fail "没有找到 class 文件"
"$D8" --min-api 24 --output "$OUTDIR/dex" --lib "$AJAR" "@$CLSLIST" \
  > "$OUTDIR/d8.log" 2>&1
DRC=$?
if [ $DRC -ne 0 ]; then
  echo "d8 输出:"; head -20 "$OUTDIR/d8.log"
  fail "d8 转换失败 (exit $DRC)"
fi
[ -f "$OUTDIR/dex/classes.dex" ] || fail "未生成 classes.dex"

# ---------- 5) 组装 APK ----------
echo "-- 组装"
cp -f "$OUTDIR/base.apk" "$OUTDIR/unsigned.apk"
# 用 jar/zip 把 classes.dex 塞进 apk 根目录
if command -v zip >/dev/null 2>&1; then
  ( cd "$OUTDIR/dex" && zip -q -X "$OUTDIR/unsigned.apk" classes.dex ) \
    || fail "写入 classes.dex 失败"
else
  "$JDK/bin/jar.exe" uf "$OUTDIR/unsigned.apk" -C "$OUTDIR/dex" classes.dex \
    || fail "写入 classes.dex 失败"
fi

# ---------- 6) 签名 ----------
if [ ! -f "$KS" ]; then
  echo "-- 生成签名密钥"
  "$KEYTOOL" -genkeypair -keystore "$KS" -alias sy -keyalg RSA -keysize 2048 \
    -validity 10000 -storepass android -keypass android \
    -dname "CN=SY Fusion, OU=Module, O=SY, C=CN" >/dev/null 2>&1 \
    || fail "密钥生成失败"
fi

echo "-- zipalign"
"$ZIPALIGN" -f -p 4 "$OUTDIR/unsigned.apk" "$OUTDIR/aligned.apk" \
  || fail "zipalign 失败"

echo "-- apksigner"
"$APKSIGNER" sign \
  --ks "$KS" --ks-pass pass:android --key-pass pass:android --ks-key-alias sy \
  --v1-signing-enabled true --v2-signing-enabled true \
  --out "$OUT" "$OUTDIR/aligned.apk" \
  || fail "签名失败"

"$APKSIGNER" verify "$OUT" >/dev/null 2>&1 || fail "签名校验未通过"

SZ=$(wc -c < "$OUT" | tr -d ' ')
echo
echo "OK: $OUT ($SZ 字节)"
"$APKSIGNER" verify --print-certs "$OUT" 2>/dev/null | head -4
