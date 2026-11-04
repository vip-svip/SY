package de.privacyguard.adhook.imported.ad;

import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.os.Build;

import java.security.MessageDigest;
import java.util.Locale;
import java.util.TreeSet;

/** Current APK signer fingerprint used to pin exported Tasker Root automation senders. */
public final class FxYulongTaskerSigner {
    private FxYulongTaskerSigner() { }

    /**
     * Returns the SHA-256 digest set of the current APK content signers, sorted and
     * comma-separated. Missing signing data or any digest error fails closed.
     *
     * <p>We intentionally pin current signers rather than the historical rotation
     * lineage: a signer change requires the user to re-authorize the automation app.
     */
    public static String currentDigestSet(PackageManager packageManager, String packageName) {
        if (packageManager == null || packageName == null || packageName.trim().isEmpty()
                || Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return "";
        try {
            PackageInfo info = packageManager.getPackageInfo(
                    packageName, PackageManager.GET_SIGNING_CERTIFICATES);
            if (info == null || info.signingInfo == null) return "";
            Signature[] signers = info.signingInfo.getApkContentsSigners();
            if (signers == null || signers.length == 0 || signers.length > 8) return "";
            MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
            TreeSet<String> digests = new TreeSet<>();
            for (Signature signer : signers) {
                if (signer == null) return "";
                sha256.reset();
                byte[] digest = sha256.digest(signer.toByteArray());
                StringBuilder hex = new StringBuilder(64);
                for (byte value : digest) {
                    hex.append(String.format(Locale.ROOT, "%02x", value & 0xff));
                }
                if (!digests.add(hex.toString())) return "";
            }
            return digests.size() == signers.length
                    ? android.text.TextUtils.join(",", digests) : "";
        } catch (Exception | LinkageError unavailable) {
            return "";
        }
    }
}
