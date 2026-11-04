#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GRADLE = (ROOT / "adhook/app/build.gradle").read_text(encoding="utf-8")
MANIFEST = (ROOT / "adhook/app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")
APP = (ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/FxHookApplication.java").read_text(encoding="utf-8")
BRIDGE = (ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/FxLsposedScopeBridge.java").read_text(encoding="utf-8")
MAIN = (ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java").read_text(encoding="utf-8")
MODULE = (ROOT / "adhook/app/src/main/resources/META-INF/xposed/module.prop").read_text(encoding="utf-8")
SCOPE = (ROOT / "adhook/app/src/main/resources/META-INF/xposed/scope.list").read_text(encoding="utf-8")

assert "implementation 'io.github.libxposed:service:102.0.0'" in GRADLE, "libXposed Service implementation dependency missing (published Maven Central version)"
assert 'android:name=".FxHookApplication"' in MANIFEST, "FX Application class is not registered"
assert "FxLsposedScopeBridge.initialize();" in APP, "service listener is not initialized at app startup"
assert "XposedServiceHelper.registerListener(SERVICE_LISTENER)" in BRIDGE, "official Xposed service listener missing"
assert "AtomicBoolean REGISTERED" in BRIDGE, "service listener registration is not process-singleton"
for contract in ("service.getScope()", "service.requestScope(", "service.removeScope("):
    assert contract in BRIDGE, f"modern scope contract missing: {contract}"
assert "onScopeRequestApproved" in BRIDGE, "scope approval callback missing"
assert "onScopeRequestFailed" in BRIDGE, "scope denial/failure callback missing"
assert '"de.privacyguard.adhook".equals(packageName)' in BRIDGE, "FX must not add itself to its own hook scope"
assert 'packageName.matches("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+")' in BRIDGE, "scope package identifier validation missing"
assert "addLsposedScopeControls(selectedPackage" in MAIN, "per-target scope controls are not in the Hook target UI"
assert "向 LSPosed 申请此应用的 Hook 作用域" in MAIN, "target scope request action missing"
assert "LSPosed 模块启用和目标应用作用域必须在 LSPosed Manager 中单独设置" in MAIN, "Hook UI must explain that LSPosed scope remains a separate Manager setting"
assert "移除此应用的 LSPosed 作用域" in MAIN, "target scope revoke action missing"
assert "系统应用作用域" in MAIN, "system-app scope request confirmation missing"
assert "作用域只代表允许模块加载" in MAIN, "UI must distinguish approved scope from injected-process status"
assert "FxLsposedScopeBridge.isConnected()" in MAIN, "Hook hub does not display live service Binder state"
assert "dialog.box" not in BRIDGE, "legacy Dia package identity must not be copied into FX bridge"
assert "staticScope=false" in MODULE, "dynamic user-managed scope must remain enabled"
assert not SCOPE.strip(), "FX must not ship a silent default static package scope"
print("PASS: FX uses official libXposed service APIs for per-target scope requests/removals with explicit approval and status semantics")
