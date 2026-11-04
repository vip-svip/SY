#!/usr/bin/env python3
"""Dia lsp_sync parity: opt-in, official Manager request and safe target boundaries."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
main = (ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java").read_text(encoding="utf-8")
settings = (ROOT / "adhook/app/src/main/java/de/privacyguard/adhook/imported/dia/FxDiaGlobalSettingsActivity.java").read_text(encoding="utf-8")

def section(source, start_sig, end_sig):
    start = source.index(start_sig)
    end = source.index(end_sig, start)
    return source[start:end]

helper = section(main, "private void maybeAutoRequestLsposedScope(", "private void addLsposedScopeControls(")
target = section(main, "private void showTarget(ApplicationInfo ai)", "private void buildNativePrivacyPage(")
assert 'getBoolean("lsp_sync", false)' in helper, "auto scope must remain explicit opt-in"
assert "FxLsposedScopeBridge.isConnected()" in helper
assert "FxLsposedScopeBridge.snapshot(packageName)" in helper, "current scope must be read before requesting"
assert "current.targetInScope" in helper, "already-authorized apps must not get duplicate requests"
assert "FxLsposedScopeBridge.requestScope(packageName" in helper, "request must use official libXposed API"
assert "FLAG_SYSTEM" in helper and "FLAG_UPDATED_SYSTEM_APP" in helper, "system apps must stay explicit-only"
assert "AUTO_SCOPE_REQUESTS_IN_FLIGHT.add(packageName)" in helper
assert "AUTO_SCOPE_REQUESTS_IN_FLIGHT.remove(packageName)" in helper, "pending guard must clear on every result"
assert "AUTO_SCOPE_EXECUTOR.execute(() -> {" in helper and "new Thread(" not in helper, \
    "scope sync must use the shared bounded executor rather than one thread per target"
assert "new ArrayBlockingQueue<>(8)" in main and "new ThreadPoolExecutor.AbortPolicy()" in main, \
    "scope sync executor must have a bounded queue and reject overload"
assert "RejectedExecutionException full" in helper and "AUTO_SCOPE_REQUESTS_IN_FLIGHT.remove(packageName)" in helper, \
    "queue rejection must release the per-package pending guard for retry"
assert "WeakReference<MainActivity>" in helper, "asynchronous Manager callback must not keep a destroyed Activity alive"
assert "maybeAutoRequestLsposedScope(ai)" in target, "automatic request must be wired to explicit target selection"
assert 'addStoredSwitch("自动申请 LSPosed 作用域"' in settings
assert '"lsp_sync", false' in settings
assert 'addUnavailableSwitch("自动同步到 LSPosed 作用域"' not in settings
assert "Manager 仍须批准" in settings
print("PASS: Dia lsp_sync uses official LSPosed API with opt-in, preflight, user-app boundaries and duplicate suppression")
