#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
APP="$ROOT/adhook/app/src/main"
GRADLE="$ROOT/adhook/app/build.gradle"
MANIFEST="$APP/AndroidManifest.xml"
EDITOR="$APP/java/de/privacyguard/adhook/imported/dia/FxDiaCodeEditorActivity.java"
FRIDA="$APP/java/de/privacyguard/adhook/imported/dia/FxDiaFridaActivity.java"
fail(){ echo "FAIL: $*" >&2; exit 1; }

for f in "$GRADLE" "$MANIFEST" "$EDITOR" "$FRIDA"; do
  [ -s "$f" ] || fail "required Dia code-editor migration file missing: $f"
done

grep -Fq "io.github.Rosemoe.sora-editor:editor:0.23.6" "$GRADLE" || fail "Sora editor core dependency missing"
grep -Fq "io.github.Rosemoe.sora-editor:language-java:0.23.6" "$GRADLE" || fail "Sora Java language dependency missing"
grep -Fq '.imported.dia.FxDiaCodeEditorActivity' "$MANIFEST" || fail "CodeEditor Activity is not declared in the unified APK"
grep -Fq 'android:exported="false"' "$MANIFEST" || fail "CodeEditor Activity must not be exported"
grep -Fq 'new CodeEditor(this)' "$EDITOR" || fail "native Sora CodeEditor is not instantiated"
grep -Fq 'new JavaLanguage()' "$EDITOR" || fail "original JavaLanguage support is missing"
grep -Fq 'setEditorLanguage(new JavaLanguage())' "$EDITOR" || fail "Java syntax language is not attached"
grep -Fq 'EXTRA_LANGUAGE = "language"' "$EDITOR" || fail "editor language selector missing"
grep -Fq 'getStringExtra(EXTRA_LANGUAGE)' "$EDITOR" || fail "editor does not restore selected source language"
grep -Fq 'if (!javascriptMode) editor.setEditorLanguage(new JavaLanguage())' "$EDITOR" || fail "Java tokenizer is incorrectly applied to Frida JavaScript"
grep -Fq 'EXTRA_LANGUAGE, "javascript"' "$FRIDA" || fail "Frida caller does not select JavaScript source mode"
grep -Fq '纯文本编辑' "$EDITOR" || fail "JavaScript editor does not disclose its plain-text mode"
grep -Fq 'EXTRA_CODE = "code"' "$EDITOR" || fail "original code input/output extra changed"
grep -Fq 'RESULT_CODE_EDITOR = 0x3039' "$EDITOR" || fail "original 0x3039 result contract changed"
grep -Fq 'result.putExtra(EXTRA_CODE, source)' "$EDITOR" || fail "editor does not return the source text"
grep -Fq 'setResult(RESULT_CODE_EDITOR, result)' "$EDITOR" || fail "editor does not publish the original result code"
grep -Fq 'onSaveInstanceState' "$EDITOR" || fail "editor content is not restored on Activity recreation"
grep -Fq 'MAX_SOURCE_BYTES = 48 * 1024' "$EDITOR" || fail "editor source/Bundle bound missing"
grep -Fq '保存并返回' "$EDITOR" || fail "unsaved changes have no save confirmation"
grep -Fq '放弃修改' "$EDITOR" || fail "unsaved changes have no discard action"
grep -Fq 'REQUEST_CODE_FULL_EDITOR = 0x3039' "$FRIDA" || fail "Frida page did not preserve original editor request code"
grep -Fq '打开全屏代码编辑器' "$FRIDA" || fail "Frida page lacks original full-screen editor entry"
grep -Fq 'FxDiaCodeEditorActivity.RESULT_CODE_EDITOR' "$FRIDA" || fail "Frida page does not receive the original editor result"
grep -Fq 'script.setText(editedSource)' "$FRIDA" || fail "Frida page does not restore returned source"
grep -Fq 'STATE_FULL_EDITOR_PENDING' "$FRIDA" || fail "Frida caller does not persist the pending editor request across recreation"
grep -Fq 'MessageDigest.getInstance("SHA-256")' "$FRIDA" || fail "Frida editor source snapshot fingerprint is missing"
grep -Fq 'pendingFullEditorTargetPackage = targetPackage;' "$FRIDA" || fail "Frida editor request does not capture its target package"
grep -Fq 'pendingFullEditorSourceSha256 = sourceFingerprint;' "$FRIDA" || fail "Frida editor request does not capture the source revision"
grep -Fq '!java.util.Objects.equals(requestedTarget, targetPackage)' "$FRIDA" || fail "Frida editor result is not rejected after target change"
grep -Fq '!requestedFingerprint.equals(currentFingerprint)' "$FRIDA" || fail "Frida editor result can overwrite a newer script revision"
grep -Fq 'outState.putBoolean(STATE_FULL_EDITOR_PENDING, fullEditorPending)' "$FRIDA" || fail "Frida editor pending request is not saved during rotation"

echo "PASS: Dia Sora CodeEditor page, JavaLanguage, 0x3039 result contract, unsaved-change flow, source fingerprint and target ownership"
