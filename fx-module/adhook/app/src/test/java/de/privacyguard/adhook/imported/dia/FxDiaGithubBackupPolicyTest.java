package de.privacyguard.adhook.imported.dia;

import org.junit.Test;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public class FxDiaGithubBackupPolicyTest {
    @Test public void acceptsOnlyCanonicalHttpsRawHost() {
        assertTrue(FxDiaGithubBackupPolicy.isTrustedDownloadUrl(
                "https://raw.githubusercontent.com/vip-svip/SY/main/backups/fx.json"));
        assertTrue(FxDiaGithubBackupPolicy.isTrustedDownloadUrl(
                "https://raw.githubusercontent.com:443/vip-svip/SY/main/backups/fx.json"));
    }

    @Test public void rejectsTokenExfiltrationAndRedirectTargets() {
        assertFalse(FxDiaGithubBackupPolicy.isTrustedDownloadUrl(
                "http://raw.githubusercontent.com/vip-svip/SY/main/backup.json"));
        assertFalse(FxDiaGithubBackupPolicy.isTrustedDownloadUrl(
                "https://raw.githubusercontent.com.attacker.invalid/vip-svip/SY/main/backup.json"));
        assertFalse(FxDiaGithubBackupPolicy.isTrustedDownloadUrl(
                "https://attacker.invalid/raw.githubusercontent.com/backup.json"));
        assertFalse(FxDiaGithubBackupPolicy.isTrustedDownloadUrl(
                "https://user:token@raw.githubusercontent.com/vip-svip/SY/main/backup.json"));
        assertFalse(FxDiaGithubBackupPolicy.isTrustedDownloadUrl(
                "https://raw.githubusercontent.com:8443/vip-svip/SY/main/backup.json"));
        assertFalse(FxDiaGithubBackupPolicy.isTrustedDownloadUrl(
                "https://raw.githubusercontent.com/vip-svip/SY/main/backup.json#fragment"));
        assertFalse(FxDiaGithubBackupPolicy.isTrustedDownloadUrl("not a URL"));
    }
}
