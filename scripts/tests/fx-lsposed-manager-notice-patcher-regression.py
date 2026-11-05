#!/usr/bin/env python3
"""Exercise the LSPosed Manager notice patcher against isolated source fixtures."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PATCHER = ROOT / "fx-patches/ensure_lsposed_manager_notice.py"

HUB_NOTICE = "LSPosed 模块启用和目标应用作用域必须在 LSPosed Manager 中单独设置"
PUBLISH_NOTICE = (
    "保存并发布 Hook 配置只更新 FX 设备端配置和 Remote Files 发布状态，"
    "不会自动授予或修改 LSPosed 作用域。目标应用作用域由 LSPosed Manager 单独管理；"
    "上方的作用域申请仍须经过 Manager 审查和批准。"
)
BASE = """class MainActivity {
    private void showHookHub() {
        section("LSPosed");
        TextView ls = new TextView(this);
        content.addView(ls);
    }
    private void addModeOption() {}
    private void showHookTarget() {
        Button save=new Button(this); save.setText("保存并发布 Hook 配置");
        content.addView(save);
    }
}
"""


def invoke(root: Path, expect_success: bool) -> subprocess.CompletedProcess:
    result = subprocess.run(
        [sys.executable, str(PATCHER), str(root)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if expect_success and result.returncode != 0:
        raise AssertionError(f"patcher failed unexpectedly: {result.stdout}\n{result.stderr}")
    if not expect_success and result.returncode == 0:
        raise AssertionError("patcher unexpectedly accepted a broken source anchor")
    return result


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fx-lsposed-notice-") as tmp:
        root = Path(tmp)
        main_java = root / "adhook/app/src/main/java/de/privacyguard/adhook/MainActivity.java"
        main_java.parent.mkdir(parents=True)
        main_java.write_text(BASE, encoding="utf-8")

        first = invoke(root, True)
        patched = main_java.read_text(encoding="utf-8")
        assert HUB_NOTICE in patched, "Hub must explain LSPosed Manager retains scope authority"
        assert PUBLISH_NOTICE in patched, "Publish action must explain it does not grant LSPosed scope"
        assert patched.index(HUB_NOTICE) < patched.index('TextView ls = new TextView(this);')
        assert patched.index(PUBLISH_NOTICE) < patched.index('Button save=new Button(this);')
        assert "PASS:" in first.stdout

        invoke(root, True)
        repeated = main_java.read_text(encoding="utf-8")
        assert repeated == patched, "patcher must be idempotent"
        assert repeated.count(HUB_NOTICE) == 1, "Hub notice must be inserted exactly once"
        assert repeated.count(PUBLISH_NOTICE) == 1, "Publish notice must be inserted exactly once"

        # Missing unique publish control must fail before writing the partially
        # modified Hub text back to disk.
        broken = BASE.replace(
            '        Button save=new Button(this); save.setText("保存并发布 Hook 配置");\n', ""
        )
        main_java.write_text(broken, encoding="utf-8")
        before = main_java.read_text(encoding="utf-8")
        result = invoke(root, False)
        assert main_java.read_text(encoding="utf-8") == before, (
            "failed patch must not partially persist the Hub notice"
        )
        assert "unique Hook config publish control" in result.stderr

    print("PASS: LSPosed Manager notice patcher inserts both notices, remains idempotent, and fails closed without partial writes")


if __name__ == "__main__":
    main()
