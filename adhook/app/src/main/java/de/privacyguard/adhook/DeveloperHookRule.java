package de.privacyguard.adhook;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * A bounded, package-scoped Debug fixture rule for a developer-owned application.
 * Exact JVM descriptors support method observation with overloads and typed parameters.
 * Legacy owner#method()Z descriptors remain accepted for boolean Debug fixtures.
 */
public final class DeveloperHookRule {
    public enum Action { RETURN_TRUE, RETURN_FALSE, RETURN_NULL, RETURN_ZERO, RETURN_EMPTY_STRING, NO_OP_VOID, OBSERVE, DISABLED }
    public final String id;
    public final String descriptor;
    public final boolean replacement;
    public final Action action;
    public final int priority;

    private DeveloperHookRule(String id, String descriptor, Action action, int priority) {
        this.id = id;
        this.descriptor = descriptor;
        this.action = action;
        this.replacement = action == Action.RETURN_TRUE || action == Action.RETURN_FALSE
                || action == Action.RETURN_NULL || action == Action.RETURN_ZERO
                || action == Action.RETURN_EMPTY_STRING || action == Action.NO_OP_VOID;
        this.priority = priority;
    }

    public static DeveloperHookRule parse(String encoded, String packageName) {
        if (encoded == null || packageName == null || encoded.length() > 768) return null;
        String[] fields = encoded.split("\\|", -1);
        if (fields.length != 4) return null;
        String id = fields[0].trim();
        if (!id.matches("[A-Za-z][A-Za-z0-9_-]{0,31}")) return null;
        String descriptor = normalizeDescriptor(fields[1].trim(), packageName);
        if (descriptor == null || !isInPackage(descriptor, packageName)) return null;
        String actionText = fields[2].trim().toUpperCase(java.util.Locale.ROOT);
        final Action action;
        if ("TRUE".equals(actionText) || "RETURN_TRUE".equals(actionText)) action = Action.RETURN_TRUE;
        else if ("FALSE".equals(actionText) || "RETURN_FALSE".equals(actionText)) action = Action.RETURN_FALSE;
        else if ("NULL".equals(actionText) || "RETURN_NULL".equals(actionText)) action = Action.RETURN_NULL;
        else if ("ZERO".equals(actionText) || "RETURN_ZERO".equals(actionText)) action = Action.RETURN_ZERO;
        else if ("EMPTY_STRING".equals(actionText) || "RETURN_EMPTY_STRING".equals(actionText)) action = Action.RETURN_EMPTY_STRING;
        else if ("NO_OP_VOID".equals(actionText) || "DO_NOTHING".equals(actionText)) action = Action.NO_OP_VOID;
        else if ("OBSERVE".equals(actionText) || "OBSERVE_ONLY".equals(actionText)) action = Action.OBSERVE;
        else if ("OFF".equals(actionText) || "DISABLED".equals(actionText)) action = Action.DISABLED;
        else return null;
        if (action == Action.NO_OP_VOID) {
            // The old method_empty behavior could corrupt non-void call sites.
            if (!descriptor.startsWith("L")) return null;
            DeveloperExecutableDescriptor parsed = DeveloperExecutableDescriptor.parse(descriptor, packageName);
            if (parsed == null || "<init>".equals(parsed.name) || !"V".equals(parsed.returnDescriptor)) return null;
        }
        if (action == Action.RETURN_TRUE || action == Action.RETURN_FALSE
                || action == Action.RETURN_NULL || action == Action.RETURN_ZERO
                || action == Action.RETURN_EMPTY_STRING) {
            if (descriptor.startsWith("L")) {
                DeveloperExecutableDescriptor parsed = DeveloperExecutableDescriptor.parse(descriptor, packageName);
                if (parsed == null || "<init>".equals(parsed.name)) return null;
                String result = parsed.returnDescriptor;
                if ((action == Action.RETURN_TRUE || action == Action.RETURN_FALSE)
                        && (!parsed.parameterDescriptors.isEmpty() || !"Z".equals(result))) return null;
                if (action == Action.RETURN_NULL && !(result.startsWith("L") || result.startsWith("["))) return null;
                if (action == Action.RETURN_ZERO && !"BCSIJFD".contains(result)) return null;
                if (action == Action.RETURN_EMPTY_STRING && !"Ljava/lang/String;".equals(result)) return null;
            } else if (!descriptor.matches("[A-Za-z_$][A-Za-z0-9_$.]*#[A-Za-z_$][A-Za-z0-9_$]*\\(\\)Z")) {
                return null;
            }
        }
        final int priority;
        try { priority = Integer.parseInt(fields[3].trim()); }
        catch (NumberFormatException e) { return null; }
        if (priority < -1000 || priority > 1000) return null;
        return new DeveloperHookRule(id, descriptor, action, priority);
    }

    /** Highest-priority active rule wins for each exact method descriptor. */
    public static List<DeveloperHookRule> selectEffective(List<DeveloperHookRule> rules) {
        if (rules == null || rules.isEmpty()) return Collections.emptyList();
        List<DeveloperHookRule> ordered = new ArrayList<>();
        for (DeveloperHookRule rule : rules) if (rule != null) ordered.add(rule);
        // Stable sort preserves config order for equal-priority rules.
        ordered.sort((left, right) -> Integer.compare(right.priority, left.priority));
        Set<String> claimed = new HashSet<>();
        List<DeveloperHookRule> selected = new ArrayList<>();
        for (DeveloperHookRule rule : ordered) {
            // DISABLED is an inert entry: it does not claim the descriptor or shadow an active rule.
            if (rule.action == Action.DISABLED) continue;
            if (claimed.add(rule.descriptor)) selected.add(rule);
        }
        return Collections.unmodifiableList(selected);
    }

    static String normalizeDescriptor(String value, String packageName) {
        if (value == null || value.length() > 512) return null;
        String d = value;
        if (!d.startsWith("L") && d.contains("(") && d.contains(")")) {
            String sourceSignature = DeveloperExecutableDescriptor.fromJavaSignature(d, packageName);
            if (sourceSignature != null) return sourceSignature;
        }
        if (d.startsWith("L") && d.contains(";->")) {
            if (!d.matches("L[A-Za-z_$][A-Za-z0-9_$]*(/[A-Za-z_$][A-Za-z0-9_$]*)*;->[A-Za-z_$<>][A-Za-z0-9_$<>]*\\(.*\\).+")) return null;
            return d;
        } else if (!d.contains("#")) {
            int paren = d.indexOf('(');
            int dot = paren < 0 ? -1 : d.lastIndexOf('.', paren);
            if (dot > 0) d = d.substring(0, dot) + "#" + d.substring(dot + 1);
        }
        if (!d.matches("[A-Za-z_$][A-Za-z0-9_$.]*#[A-Za-z_$][A-Za-z0-9_$]*\\(\\)Z")) return null;
        return d;
    }

    private static boolean isInPackage(String descriptor, String packageName) {
        if (descriptor.startsWith("L") && descriptor.contains(";->")) {
            return DeveloperExecutableDescriptor.parse(descriptor, packageName) != null;
        }
        int split = descriptor.indexOf('#');
        if (split <= 0) return false;
        String owner = descriptor.substring(0, split);
        return owner.startsWith(packageName + ".")
                && !owner.startsWith("java.") && !owner.startsWith("android.");
    }
}
