#!/usr/bin/env python3
from pathlib import Path
import hashlib

path = Path("adhook/app/src/main/java/de/privacyguard/adhook/AdVisibilityHook.java")
source = path.read_text()
base_hash = "658b49b63159e7071ca3e22e158435b5833e5c1d82fe64543c2ac88266f0a02f"
actual = hashlib.sha256(path.read_bytes()).hexdigest()
if actual != base_hash:
    raise SystemExit(f"unexpected API101 base source: {actual}")

def replace_once(old, new):
    global source
    if source.count(old) != 1:
        raise SystemExit("expected exactly one patch anchor: " + old[:100])
    source = source.replace(old, new, 1)

replace_once(
    "    private static final int MAX_REWARDED_AD_EVIDENCE = 32;\n",
    "    private static final int MAX_REWARDED_AD_EVIDENCE = 32;\n"
    "    private static final int MAX_REWARDED_AD_SUBTREE_NODES = 64;\n"
)
replace_once(
    "        boolean strong = hasAny(evidence, STRONG_AD_MARKERS);\n"
    "        boolean sdkNamespace = hasAny(cls, AD_CLASS_MARKERS);\n"
    "        // A SDK namespace alone is not proof that every custom View is an ad:\n",
    "        boolean strong = hasAny(evidence, STRONG_AD_MARKERS);\n"
    "        boolean sdkNamespace = hasAny(cls, AD_CLASS_MARKERS);\n"
    "        // Preserve a real rewarded flow for the provider's completion and server-validation path.\n"
    "        // Never fabricate or invoke its reward callback.\n"
    "        if ((strong || sdkNamespace) && (isRewardedFlowEvidence(evidence) ||\n"
    "                containsRewardedText(view, 3, new int[]{MAX_REWARDED_AD_SUBTREE_NODES}))) {\n"
    "            return false;\n"
    "        }\n"
    "        // A SDK namespace alone is not proof that every custom View is an ad:\n"
)
helper = """    /** Bounded descendant scan prevents a generic ad container from swallowing a
     * rewarded CTA nested inside it. The 64-node budget keeps hot UI paths bounded. */
    private boolean containsRewardedText(View view, int depth, int[] remaining) {
        if (view == null || depth > 3 || remaining[0]-- <= 0) return false;
        if (view instanceof TextView) {
            TextView textView = (TextView) view;
            try {
                String evidence = String.valueOf(textView.getText()) + " " +
                        String.valueOf(textView.getContentDescription());
                if (isRewardedFlowEvidence(evidence)) {
                    recordRewardedAdEvidence(textView, textView.getContext().getPackageName());
                    return true;
                }
            } catch (Throwable ignored) {}
        }
        if (!(view instanceof ViewGroup)) return false;
        ViewGroup group = (ViewGroup) view;
        int count;
        try { count = Math.min(group.getChildCount(), remaining[0]); }
        catch (Throwable ignored) { return false; }
        for (int i = 0; i < count && remaining[0] > 0; i++) {
            View child;
            try { child = group.getChildAt(i); } catch (Throwable ignored) { continue; }
            if (containsRewardedText(child, depth + 1, remaining)) return true;
        }
        return false;
    }

"""
replace_once("    private ParentEvidence findStrongAdParent(View view) {\n", helper + "    private ParentEvidence findStrongAdParent(View view) {\n")
path.write_text(source)
expected = "45ece5042197c8e7418e120a76b54250413b922a5f01412d1a17ceb9ed3c1fe5"
actual = hashlib.sha256(path.read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit(f"rewarded-flow patch hash mismatch: {actual}")
print("API101 rewarded-ad preservation patch: PASS", actual)
