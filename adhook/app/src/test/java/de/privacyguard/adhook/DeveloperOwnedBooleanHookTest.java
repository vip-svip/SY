package de.privacyguard.adhook;

import com.example.owned.AuthRepo;
import org.junit.Test;
import java.lang.reflect.Method;
import static org.junit.Assert.*;

public class DeveloperOwnedBooleanHookTest {
    @Test public void resolvesOnlyExactDebugPackageBooleanMethod() throws Exception {
        Method method = DeveloperOwnedBooleanHook.resolve(AuthRepo.class.getClassLoader(),
                "com.example.owned", "com.example.owned", true, true,
                "com.example.owned.AuthRepo#isVip()Z");
        assertNotNull(method);
        assertEquals("isVip", method.getName());
        assertEquals(boolean.class, method.getReturnType());
    }

    @Test public void releaseOptOutAndPackageMismatchFailClosed() {
        ClassLoader loader = AuthRepo.class.getClassLoader();
        assertNull(DeveloperOwnedBooleanHook.resolve(loader, "com.example.owned",
                "com.example.owned", false, true, "com.example.owned.AuthRepo#isVip()Z"));
        assertNull(DeveloperOwnedBooleanHook.resolve(loader, "com.example.owned",
                "com.example.owned", true, false, "com.example.owned.AuthRepo#isVip()Z"));
        assertNull(DeveloperOwnedBooleanHook.resolve(loader, "com.example.other",
                "com.example.owned", true, true, "com.example.owned.AuthRepo#isVip()Z"));
    }

    @Test public void rejectsMissingMethodAndNonBooleanOrParameterizedMethods() {
        ClassLoader loader = AuthRepo.class.getClassLoader();
        assertNull(DeveloperOwnedBooleanHook.resolve(loader, "com.example.owned",
                "com.example.owned", true, true, "com.example.owned.AuthRepo#missing()Z"));
        assertNull(DeveloperOwnedBooleanHook.resolve(loader, "com.example.owned",
                "com.example.owned", true, true, "com.example.owned.AuthRepo#toString()Ljava/lang/String;"));
        assertNull(DeveloperOwnedBooleanHook.resolve(loader, "com.example.owned",
                "com.example.owned", true, true, "com.example.owned.AuthRepo#isVip(Ljava/lang/String;)Z"));
    }
}
