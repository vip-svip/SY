# ============================================================
#  构建 SYManager.apk（Windows 工具链版）
#  链路：aapt2 compile/link → javac → d8 → zipalign → apksigner
#  设计说明：模块打包用不上 Gradle（无 AAR 依赖），手工链路足够且可控。
# ============================================================
param([switch]$Unsigned)
$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Parent $PSScriptRoot
$APP  = Join-Path $ROOT "app"
$SDK  = "C:\Users\admin\.workbuddy-ai\toolchain\android-sdk\build-tools\34.0.0"
$JDK  = "C:\Users\admin\.workbuddy-ai\toolchain\jdk-21.0.12.1+1"
$ANDROID_JAR = "C:\Users\admin\.workbuddy-ai\toolchain\android-sdk\platforms\android-35\android.jar"
$OUT  = Join-Path $ROOT "app\build"
$KS   = Join-Path $ROOT "app\debug.keystore"

if (-not (Test-Path $ANDROID_JAR)) {
  $alt = Get-ChildItem "C:\Users\admin\.workbuddy-ai\toolchain\android-sdk\platforms" -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName "android.jar" } | Where-Object { Test-Path $_ } | Select-Object -First 1
  if ($alt) { $ANDROID_JAR = $alt } else { throw "找不到 android.jar（platforms 目录里没有）" }
}
Write-Output "android.jar = $ANDROID_JAR"

if (Test-Path $OUT) { Remove-Item $OUT -Recurse -Force }
New-Item -ItemType Directory -Path $OUT -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OUT "compiled") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OUT "classes") -Force | Out-Null

# ① 资源编译
Write-Output "== aapt2 compile =="
& (Join-Path $SDK "aapt2.exe") compile --dir (Join-Path $APP "res") -o (Join-Path $OUT "compiled\res.zip")
if ($LASTEXITCODE -ne 0) { throw "aapt2 compile 失败" }

# ② 资源链接（生成 R.java）
Write-Output "== aapt2 link =="
& (Join-Path $SDK "aapt2.exe") link -o (Join-Path $OUT "app-unsigned.apk") 
   -I $ANDROID_JAR --manifest (Join-Path $APP "AndroidManifest.xml") 
   --java (Join-Path $OUT "classes") --auto-add-overlay 
   (Join-Path $OUT "compiled\res.zip")
if ($LASTEXITCODE -ne 0) { throw "aapt2 link 失败" }

# ③ 编译 Java（含 xposed_stub 桩；apk 里不含桩，运行期由 LSPosed 注入）
Write-Output "== javac =="
$srcs = @()
$srcs += Get-ChildItem (Join-Path $APP "java") -Recurse -Filter *.java | Select-Object -ExpandProperty FullName
$srcs += Get-ChildItem (Join-Path $APP "xposed_stub") -Recurse -Filter *.java | Select-Object -ExpandProperty FullName
$srcs += Get-ChildItem (Join-Path $OUT "classes") -Recurse -Filter *.java | Select-Object -ExpandProperty FullName
$rjava = Get-ChildItem (Join-Path $OUT "classes") -Recurse -Filter R.java -ErrorAction SilentlyContinue
$args = @("-encoding","UTF-8","-source","8","-target","8","-nowarn","-bootclasspath",$ANDROID_JAR,"-d",(Join-Path $OUT "classes"))
$args += $srcs
& (Join-Path $JDK "bin\javac.exe") @args 2>&1 | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0) { throw "javac 失败" }

# ④ d8 转 dex
Write-Output "== d8 =="
$javaclasses = Join-Path $OUT "classes"
$classFiles = Get-ChildItem $javaclasses -Recurse -Filter *.class | Select-Object -ExpandProperty FullName
# 排除 xposed_stub（桩不打包）
$classFiles = $classFiles | Where-Object { $_ -notmatch "xposed_stub" -and $_ -notmatch "\de\robv\" }
& java -cp (Join-Path $SDK "lib\d8.jar") com.android.tools.r8.D8 --min-api 24 --output (Join-Path $OUT "dex") @($classFiles) 2>&1 | ForEach-Object { Write-Output $_ }
if ($LASTEXITCODE -ne 0) { throw "d8 失败" }

# ⑤ 把 dex 与 assets 塞进 APK
Write-Output "== 组装 APK =="
Copy-Item (Join-Path $OUT "app-unsigned.apk") (Join-Path $OUT "app-final.apk") -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open((Join-Path $OUT "app-final.apk"), "Update")
foreach ($df in (Get-ChildItem (Join-Path $OUT "dex") -Filter *.dex)) {
  $e = $zip.CreateEntry("classes.dex")
  $s = $e.Open(); $b = [IO.File]::ReadAllBytes($df.FullName); $s.Write($b,0,$b.Length); $s.Close()
  break
}
foreach ($af in (Get-ChildItem (Join-Path $APP "assets") -Recurse -File)) {
  $rel = $af.FullName.Substring((Join-Path $APP "assets").Length+1).Replace("\","/")
  $e = $zip.CreateEntry("assets/$rel")
  $s = $e.Open(); $b = [IO.File]::ReadAllBytes($af.FullName); $s.Write($b,0,$b.Length); $s.Close()
}
$zip.Dispose()

# ⑥ zipalign
Write-Output "== zipalign =="
& (Join-Path $SDK "zipalign.exe") -f -p 4 (Join-Path $OUT "app-final.apk") (Join-Path $OUT "app-aligned.apk")
if ($LASTEXITCODE -ne 0) { throw "zipalign 失败" }

# ⑦ 签名
$FINAL = Join-Path $APP "SYManager.apk"
if (-not $Unsigned) {
  if (-not (Test-Path $KS)) {
    Write-Output "== 生成调试密钥库 =="
    & (Join-Path $JDK "bin\keytool.exe") -genkeypair -v -keystore $KS -storepass android -keypass android 
        -alias sydebug -keyalg RSA -keysize 2048 -validity 3650 
        -dname "CN=SY Debug, OU=SY, O=SY, L=CN, S=CN, C=CN" 2>&1 | Select-Object -Last 3 | ForEach-Object { Write-Output $_ }
  }
  Write-Output "== apksigner =="
  & java -jar (Join-Path $SDK "lib\apksigner.jar") sign --ks $KS --ks-pass pass:android --key-pass pass:android 
      --out $FINAL (Join-Path $OUT "app-aligned.apk")
  if ($LASTEXITCODE -ne 0) { throw "apksigner 失败" }
  Write-Output "== 验证签名 =="
  & java -jar (Join-Path $SDK "lib\apksigner.jar") verify --print-certs $FINAL 2>&1 | Select-Object -First 3 | ForEach-Object { Write-Output $_ }
} else {
  Copy-Item (Join-Path $OUT "app-aligned.apk") $FINAL -Force
}
Write-Output ""
Write-Output ("APK 完成: " + $FINAL + "  (" + [math]::Round((Get-Item $FINAL).Length/1KB,1) + " KB)")
