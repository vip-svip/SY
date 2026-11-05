package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class MemberUiTestProfileTest {
    @Test public void testProfileChangesOnlyUiStateWhenGateIsEnabled() {
        assertEquals(MemberUiTestProfile.State.VIP,
                MemberUiTestProfile.resolveUiState(MemberUiTestProfile.State.FREE,
                        MemberUiTestProfile.State.VIP, true));
        assertEquals(MemberUiTestProfile.State.FREE,
                MemberUiTestProfile.resolveUiState(MemberUiTestProfile.State.FREE,
                        MemberUiTestProfile.State.VIP, false));
    }

    @Test public void entitlementStateAlwaysRemainsServerAuthoritative() {
        assertEquals(MemberUiTestProfile.State.FREE,
                MemberUiTestProfile.resolveEntitlementState(MemberUiTestProfile.State.FREE));
        assertEquals(MemberUiTestProfile.State.FREE,
                MemberUiTestProfile.resolveEntitlementState(null));
    }

    @Test public void supportsExpiredRevokedAndPendingUiScenarios() {
        for (MemberUiTestProfile.State state : new MemberUiTestProfile.State[]{
                MemberUiTestProfile.State.EXPIRED, MemberUiTestProfile.State.REVOKED,
                MemberUiTestProfile.State.PENDING}) {
            assertEquals(state, MemberUiTestProfile.resolveUiState(
                    MemberUiTestProfile.State.FREE, state, true));
        }
    }
}
