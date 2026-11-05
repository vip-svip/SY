package de.privacyguard.adhook.imported.dia;

import android.app.AlertDialog;
import android.content.Intent;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import java.nio.charset.StandardCharsets;

import io.github.rosemoe.sora.langs.java.JavaLanguage;
import io.github.rosemoe.sora.widget.CodeEditor;

/**
 * Dia 23.11 full-screen code editor migration.
 *
 * Original intent contract:
 *  - input:  Intent extra "code"
 *  - result: resultCode 0x3039 with Intent extra "code"
 *
 * The editor is local-only. Saving returns text to the caller; it never runs
 * Frida, Java, shell, or DEX code by itself.
 */
public final class FxDiaCodeEditorActivity extends de.privacyguard.adhook.FxNativeTabActivity {
    public static final int RESULT_CODE_EDITOR = 0x3039;
    public static final String EXTRA_CODE = "code";
    public static final String EXTRA_LANGUAGE = "language";
    public static final String EXTRA_SOURCE_FILE = "source_file";
    private static final String STATE_DRAFT_SAVED = "fx_dia_code_editor_draft_saved";
    private static final int EDITOR_VIEW_ID = 0x00f3039;
    private static final String STATE_SOURCE = "fx_dia_code_editor_source";
    private static final String STATE_BASELINE = "fx_dia_code_editor_baseline";

    private CodeEditor editor;
    private String initialCode = "";

    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private TextView text(String value, int size, int color, boolean bold) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        if (bold) view.setTypeface(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD);
        view.setPadding(dp(4), dp(5), dp(4), dp(5));
        return view;
    }

    private Button button(String label, Runnable action) {
        Button button = new Button(this);
        button.setTag("fx-action-row");
        button.setAllCaps(false);
        button.setText(label);
        button.setOnClickListener(view -> action.run());
        return button;
    }

    private static int utf8Length(String value) {
        return value == null ? 0 : value.getBytes(StandardCharsets.UTF_8).length;
    }

    private String currentSource() {
        return editor == null || editor.getText() == null ? "" : editor.getText().toString();
    }

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);

        String intentSource = getIntent() == null ? null : getIntent().getStringExtra(EXTRA_CODE);
        String sourceFile = getIntent() == null ? null : getIntent().getStringExtra(EXTRA_SOURCE_FILE);
        String source;
        try {
            if (sourceFile != null) {
                String draftFile = FxDiaCodeEditorTransfer.sibling(this, sourceFile, ".draft");
                String original = FxDiaCodeEditorTransfer.read(this, sourceFile, ".source");
                source = state != null && state.getBoolean(STATE_DRAFT_SAVED, false)
                        ? FxDiaCodeEditorTransfer.read(this, draftFile, ".draft") : original;
                initialCode = original;
            } else {
                source = intentSource == null ? "" : intentSource;
                if (state != null) source = state.getString(STATE_SOURCE, source);
                initialCode = state == null ? source : state.getString(STATE_BASELINE, source);
            }
        } catch (Exception error) {
            Toast.makeText(this, "读取编辑器源码失败：" + error.getClass().getSimpleName(), Toast.LENGTH_LONG).show();
            setResult(RESULT_CANCELED); finish(); return;
        }
        if (initialCode == null) initialCode = source;

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xfff7f8fa);

        LinearLayout header = new LinearLayout(this);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(8), dp(3), dp(8), dp(3));
        header.addView(button("‹ 返回 Hook", this::onBackPressed));
        boolean javascriptMode = "javascript".equalsIgnoreCase(
                getIntent() == null ? "" : getIntent().getStringExtra(EXTRA_LANGUAGE));
        TextView title = text(javascriptMode ? "Hook · JavaScript 规则编辑器" : "Hook · Java 代码编辑器",
                17, 0xff17212b, true);
        title.setTag("fx-title:18");
        header.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
        header.addView(button("保存并返回", this::saveAndReturn));
        root.addView(header);

        TextView note = text(javascriptMode
                ? "Frida JavaScript 脚本编辑模式。当前 APK 只内置 Java 语法模块，因此脚本使用纯文本编辑；保存只回传，不会自动执行。"
                : "原版 CodeEditorActivity 的 Java 原生编辑页。保存只将代码回传上一页，不会自动执行。",
                12, 0xff617080, false);
        note.setTag("fx-card-detail");
        note.setPadding(dp(12), dp(3), dp(12), dp(7));
        root.addView(note);

        editor = new CodeEditor(this);
        editor.setId(EDITOR_VIEW_ID);
        editor.setSaveEnabled(false);
        editor.setText(source);
        // Sora defaults to EmptyLanguage. Keep Frida JavaScript as source text
        // instead of applying the Java tokenizer to a different language.
        if (!javascriptMode) editor.setEditorLanguage(new JavaLanguage());
        root.addView(editor, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentViewWithNativeTabs(root, 4);

        getWindow().setSoftInputMode(
                android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
    }

    private void saveAndReturn() {
        String source = currentSource();
        Intent result = new Intent();
        String sourceFile = getIntent() == null ? null : getIntent().getStringExtra(EXTRA_SOURCE_FILE);
        try {
            if (sourceFile != null) {
                String resultFile = FxDiaCodeEditorTransfer.sibling(this, sourceFile, ".result");
                FxDiaCodeEditorTransfer.write(this, resultFile, source);
                result.putExtra(EXTRA_SOURCE_FILE, resultFile);
            } else result.putExtra(EXTRA_CODE, source);
            setResult(RESULT_CODE_EDITOR, result); finish();
        } catch (Exception error) {
            Toast.makeText(this, "保存编辑源码失败：" + error.getClass().getSimpleName(), Toast.LENGTH_LONG).show();
        }
    }

    @Override public void onBackPressed() {
        String source = currentSource();
        if (source.equals(initialCode)) {
            setResult(RESULT_CANCELED);
            finish();
            return;
        }
        fxDialogBuilder()
                .setTitle("代码尚未保存")
                .setMessage("是否将当前编辑内容返回 Dia Frida 页面？")
                .setPositiveButton("保存并返回", (dialog, which) -> saveAndReturn())
                .setNegativeButton("放弃修改", (dialog, which) -> {
                    setResult(RESULT_CANCELED);
                    finish();
                })
                .setNeutralButton("继续编辑", null)
                .show();
    }

    @Override protected void onSaveInstanceState(Bundle outState) {
        String source = currentSource();
        String sourceFile = getIntent() == null ? null : getIntent().getStringExtra(EXTRA_SOURCE_FILE);
        if (sourceFile != null) {
            try {
                String draftFile = FxDiaCodeEditorTransfer.sibling(this, sourceFile, ".draft");
                FxDiaCodeEditorTransfer.write(this, draftFile, source);
                outState.putBoolean(STATE_DRAFT_SAVED, true);
            } catch (Exception error) { outState.putBoolean(STATE_DRAFT_SAVED, false); }
        } else {
            outState.putString(STATE_SOURCE, source);
            outState.putString(STATE_BASELINE, initialCode);
        }
        super.onSaveInstanceState(outState);
    }

    @Override protected void onDestroy() {
        String sourceFile = getIntent() == null ? null : getIntent().getStringExtra(EXTRA_SOURCE_FILE);
        if (isFinishing() && !isChangingConfigurations() && sourceFile != null) {
            FxDiaCodeEditorTransfer.delete(this, sourceFile);
            try { FxDiaCodeEditorTransfer.delete(this, FxDiaCodeEditorTransfer.sibling(this, sourceFile, ".draft")); }
            catch (Exception ignored) { }
        }
        super.onDestroy();
    }
}
