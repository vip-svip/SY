package de.privacyguard.adhook;

import android.app.Activity;
import android.app.AlertDialog;

/**
 * MainActivity's default AlertDialog builder.
 *
 * All direct Builder.show() calls are routed through FxNativeSkin so dialog
 * titles, message text, EditText controls, list rows and action buttons use the
 * active global Skin. Button and selection listeners remain owned by Android's
 * original AlertDialog implementation.
 */
final class FxSkinAlertDialogBuilder extends AlertDialog.Builder {
    private final Activity activity;

    FxSkinAlertDialogBuilder(Activity activity) {
        super(activity);
        if (activity == null) throw new IllegalArgumentException("activity must not be null");
        this.activity = activity;
    }

    @Override
    public AlertDialog show() {
        AlertDialog dialog = create();
        FxNativeSkin.showDialog(activity, dialog);
        return dialog;
    }
}