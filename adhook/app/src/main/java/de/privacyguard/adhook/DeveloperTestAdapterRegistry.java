package de.privacyguard.adhook;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Explicit registry for developer-owned test/preview adapters.
 * Adapters can provide scenario data to test UI only; they are not hooks and
 * cannot replace server authorization, billing results, tokens, or update policy.
 */
public final class DeveloperTestAdapterRegistry {
    public interface TestScenarioProvider {
        AuthorizationSimulationProfile scenarioForTestUi();
    }
    public static final class Registration {
        public final String packageName;
        public final String adapterId;
        public final TestScenarioProvider provider;
        Registration(String packageName,String adapterId,TestScenarioProvider provider) {
            this.packageName=packageName; this.adapterId=adapterId; this.provider=provider;
        }
    }
    private final boolean enabled;
    private final String allowedPackage;
    private final Map<String,Registration> registrations=new LinkedHashMap<>();

    public DeveloperTestAdapterRegistry(boolean debuggableBuild,boolean explicitOptIn,
                                        String processPackage,String configuredTestPackage) {
        enabled=MemberTestGate.isEnabled(debuggableBuild,explicitOptIn,processPackage,configuredTestPackage);
        allowedPackage=enabled?processPackage.trim():"";
    }

    public synchronized boolean register(String packageName,String adapterId,TestScenarioProvider provider) {
        if(!enabled || packageName==null || adapterId==null || provider==null) return false;
        String pkg=packageName.trim(), id=adapterId.trim();
        if(pkg.isEmpty() || id.isEmpty() || !allowedPackage.equals(pkg) || id.length()>64) return false;
        if(!id.matches("[A-Za-z0-9_.-]+")) return false;
        registrations.put(id,new Registration(pkg,id,provider));
        return true;
    }

    public synchronized AuthorizationSimulationProfile scenarioForTestUi(String adapterId) {
        if(!enabled || adapterId==null) return AuthorizationSimulationProfile.defaults();
        Registration registration=registrations.get(adapterId);
        if(registration==null || !allowedPackage.equals(registration.packageName))
            return AuthorizationSimulationProfile.defaults();
        AuthorizationSimulationProfile profile=registration.provider.scenarioForTestUi();
        return profile==null?AuthorizationSimulationProfile.defaults():profile;
    }

    public synchronized Map<String,Registration> registrations() {
        if(!enabled) return Collections.emptyMap();
        return Collections.unmodifiableMap(new LinkedHashMap<>(registrations));
    }

    public synchronized void clear() {
        registrations.clear();
    }
}
