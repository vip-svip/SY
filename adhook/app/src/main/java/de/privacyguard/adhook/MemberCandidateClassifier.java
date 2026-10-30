package de.privacyguard.adhook;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.Locale;

/**
 * Conservative, metadata-only member API candidate classifier.
 *
 * It never invokes a candidate method, reads a field value, or changes an app result.
 * Results are hints for diagnostics and explicit developer-authored adapters only.
 */
public final class MemberCandidateClassifier {
    public enum Kind {
        BOOLEAN, INTEGER, LONG, STRING, ENUM, OBJECT, ASYNC_FLOW, UNKNOWN
    }

    public static final class Candidate {
        public final Kind kind;
        public final int score;
        public final String reason;

        Candidate(Kind kind, int score, String reason) {
            this.kind = kind;
            this.score = score;
            this.reason = reason;
        }

        public boolean isWorthInspecting() {
            return score >= 2 && kind != Kind.UNKNOWN;
        }
    }

    private MemberCandidateClassifier() {}

    public static Candidate inspect(Method method) {
        if (method == null) return unknown("null method");
        int score = nameScore(method.getName());
        Class<?> result = method.getReturnType();
        Kind kind = kindOf(result);
        if (kind != Kind.UNKNOWN) score += 1;
        for (Class<?> parameter : method.getParameterTypes()) {
            String name = parameter.getName().toLowerCase(Locale.ROOT);
            if (name.contains("continuation")) {
                kind = Kind.ASYNC_FLOW;
                score += 2;
            }
        }
        if (Modifier.isStatic(method.getModifiers())) score += 0;
        return new Candidate(kind, score, "method metadata only");
    }

    public static Candidate inspect(Field field) {
        if (field == null) return unknown("null field");
        int score = nameScore(field.getName());
        Kind kind = kindOf(field.getType());
        if (kind != Kind.UNKNOWN) score += 1;
        return new Candidate(kind, score, "field metadata only");
    }

    static int nameScore(String rawName) {
        if (rawName == null) return 0;
        String name = rawName.toLowerCase(Locale.ROOT);
        int score = 0;
        String[] terms = {"vip", "premium", "member", "membership", "subscription",
                "entitlement", "prouser", "ispro", "paiduser", "validuntil",
                "expire", "renew", "planlevel", "tier"};
        for (String term : terms) if (name.contains(term)) score += 2;
        return Math.min(score, 6);
    }

    static Kind kindOf(Class<?> type) {
        if (type == null) return Kind.UNKNOWN;
        if (type == boolean.class || type == Boolean.class) return Kind.BOOLEAN;
        if (type == int.class || type == Integer.class || type == short.class
                || type == Short.class) return Kind.INTEGER;
        if (type == long.class || type == Long.class) return Kind.LONG;
        if (type == String.class || CharSequence.class.isAssignableFrom(type)) return Kind.STRING;
        if (type.isEnum()) return Kind.ENUM;
        String name = type.getName().toLowerCase(Locale.ROOT);
        if (name.contains("kotlinx.coroutines.flow")
                || name.contains("livedata") || name.contains("observable")
                || name.contains("publisher") || name.contains("flowable")) {
            return Kind.ASYNC_FLOW;
        }
        if (!type.isPrimitive() && !type.isArray() && type != Void.class) return Kind.OBJECT;
        return Kind.UNKNOWN;
    }

    private static Candidate unknown(String reason) {
        return new Candidate(Kind.UNKNOWN, 0, reason);
    }
}
