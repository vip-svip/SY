package de.privacyguard.adhook;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.math.BigDecimal;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;

/**
 * A bounded, package-scoped Debug fixture rule for a developer-owned application.
 * Exact JVM descriptors support method observation with overloads and typed parameters.
 * Legacy owner#method()Z descriptors remain accepted for boolean Debug fixtures.
 */
public final class DeveloperHookRule {
    public enum Action { RETURN_TRUE, RETURN_FALSE, RETURN_NULL, RETURN_ZERO, RETURN_EMPTY_STRING, RETURN_LITERAL, RETURN_ARGUMENT_0, RETURN_THIS, NO_OP_VOID, OBSERVE, DISABLED }

    public static final String UNSUPPORTED_MUTATION_ACTION_MESSAGE =
            "自定义 Hook 写入型动作不支持（mutation actions are not supported）。除 OBSERVE、RETURN_*、NO_OP_VOID 外，RETURN_ARGUMENT_0（首参数与返回类型必须完全相同）和 RETURN_THIS（仅非静态且返回类型可接收当前对象）也仅用于 debuggable 本地测试；不支持字段写入或任意方法调用。";

    /** Identify common state-changing action names so the UI and config parser can fail closed with a precise reason. */
    public static boolean isUnsupportedMutationAction(String rawAction) {
        if (rawAction == null) return false;
        String action = rawAction.trim().toUpperCase(java.util.Locale.ROOT);
        if (action.isEmpty() || action.length() > 64) return false;
        if (action.contains("MUTAT") || action.contains("WRITE")
                || action.contains("INVOKE") || action.contains("EXECUTE")) return true;
        for (String prefix : new String[]{
                "SET_", "PUT_", "DELETE_", "CREATE_", "REMOVE_", "MODIFY_",
                "PATCH_", "CALL_", "FIELD_SET", "PROPERTY_SET", "REPLACE_FIELD",
                "REPLACE_ARGUMENT", "ASSIGN_"
        }) {
            if (action.startsWith(prefix)) return true;
        }
        return "SET".equals(action) || "PUT".equals(action) || "DELETE".equals(action)
                || "CREATE".equals(action) || "REMOVE".equals(action) || "PATCH".equals(action)
                || "CALL".equals(action) || "MODIFY".equals(action);
    }
    public final String id;
    public final String descriptor;
    public final boolean replacement;
    public final Action action;
    public final int priority;
    /** Optional exact immutable constant, present only for RETURN_LITERAL and paused copies. */
    public final String literalValue;

    private DeveloperHookRule(String id, String descriptor, Action action, int priority, String literalValue) {
        this.id = id;
        this.descriptor = descriptor;
        this.action = action;
        this.literalValue = literalValue;
        // Legacy boolean compatibility flag: true means RETURN_TRUE.
        // The Action enum remains authoritative for every other return/no-op action.
        this.replacement = action == Action.RETURN_TRUE;
        this.priority = priority;
    }

    public static DeveloperHookRule parse(String encoded, String packageName) {
        if (encoded == null || packageName == null || encoded.length() > 1024) return null;
        String[] fields = encoded.split("\\|", -1);
        if (fields.length != 4 && fields.length != 5) return null;
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
        else if ("RETURN_LITERAL".equals(actionText)) action = Action.RETURN_LITERAL;
        else if ("RETURN_ARGUMENT_0".equals(actionText) || "RETURN_ARG0".equals(actionText)) action = Action.RETURN_ARGUMENT_0;
        else if ("RETURN_THIS".equals(actionText)) action = Action.RETURN_THIS;
        else if ("NO_OP_VOID".equals(actionText) || "DO_NOTHING".equals(actionText)) action = Action.NO_OP_VOID;
        else if ("OBSERVE".equals(actionText) || "OBSERVE_ONLY".equals(actionText)) action = Action.OBSERVE;
        else if ("OFF".equals(actionText) || "DISABLED".equals(actionText)) action = Action.DISABLED;
        else return null;

        final String literalValue = fields.length == 5 ? fields[4] : null;
        if (action == Action.RETURN_LITERAL || (action == Action.DISABLED && literalValue != null)) {
            if (literalValue == null) return null;
            DeveloperExecutableDescriptor parsed = DeveloperExecutableDescriptor.parse(descriptor, packageName);
            if (parsed == null || "<init>".equals(parsed.name)
                    || parseLiteralValue(parsed.returnDescriptor, literalValue) == null) return null;
        } else if (literalValue != null) {
            return null;
        }

        if (action == Action.NO_OP_VOID) {
            if (!descriptor.startsWith("L")) return null;
            DeveloperExecutableDescriptor parsed = DeveloperExecutableDescriptor.parse(descriptor, packageName);
            if (parsed == null || "<init>".equals(parsed.name) || !"V".equals(parsed.returnDescriptor)) return null;
        }
        if (action == Action.RETURN_ARGUMENT_0 || action == Action.RETURN_THIS) {
            // Passthrough actions require a complete JVM descriptor.
            if (!descriptor.startsWith("L")) return null;
            DeveloperExecutableDescriptor parsed =
                    DeveloperExecutableDescriptor.parse(descriptor, packageName);
            if (parsed == null || "<init>".equals(parsed.name)) return null;
            String result = parsed.returnDescriptor;
            if (action == Action.RETURN_ARGUMENT_0) {
                if (parsed.parameterDescriptors.isEmpty()
                        || !result.equals(parsed.parameterDescriptors.get(0)) || "V".equals(result)) return null;
            } else if (!result.startsWith("L") || !result.endsWith(";")) {
                return null;
            }
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
        return new DeveloperHookRule(id, descriptor, action, priority, literalValue);
    }

    /** Exact immutable JVM value parser: primitive wrappers or String only. */
    public static Object parseLiteralValue(String returnDescriptor, String value) {
        if (returnDescriptor == null || value == null || value.length() > 256) return null;
        if ("Ljava/lang/String;".equals(returnDescriptor)) {
            if (value.indexOf('|') >= 0 || value.getBytes(StandardCharsets.UTF_8).length > 256) return null;
            for (int i = 0; i < value.length(); i++) {
                if (Character.isISOControl(value.charAt(i))) return null;
            }
            return value;
        }
        String numeric = value.trim();
        if (numeric.isEmpty() || numeric.length() > 64) return null;
        try {
            switch (returnDescriptor) {
                case "Z":
                    if ("true".equalsIgnoreCase(numeric)) return Boolean.TRUE;
                    if ("false".equalsIgnoreCase(numeric)) return Boolean.FALSE;
                    return null;
                case "B": {
                    BigInteger n = new BigInteger(numeric);
                    if (n.compareTo(BigInteger.valueOf(Byte.MIN_VALUE)) < 0
                            || n.compareTo(BigInteger.valueOf(Byte.MAX_VALUE)) > 0) return null;
                    return Byte.valueOf(n.byteValue());
                }
                case "C": {
                    BigInteger n = new BigInteger(numeric);
                    if (n.signum() < 0 || n.compareTo(BigInteger.valueOf(Character.MAX_VALUE)) > 0) return null;
                    return Character.valueOf((char) n.intValue());
                }
                case "S": {
                    BigInteger n = new BigInteger(numeric);
                    if (n.compareTo(BigInteger.valueOf(Short.MIN_VALUE)) < 0
                            || n.compareTo(BigInteger.valueOf(Short.MAX_VALUE)) > 0) return null;
                    return Short.valueOf(n.shortValue());
                }
                case "I": return Integer.valueOf(new BigInteger(numeric).intValueExact());
                case "J": return Long.valueOf(new BigInteger(numeric).longValueExact());
                case "F": {
                    float n = new BigDecimal(numeric).floatValue();
                    return Float.isNaN(n) || Float.isInfinite(n) ? null : Float.valueOf(n);
                }
                case "D": {
                    double n = new BigDecimal(numeric).doubleValue();
                    return Double.isNaN(n) || Double.isInfinite(n) ? null : Double.valueOf(n);
                }
                default:
                    return null; // No arbitrary object/array values, expressions or method calls.
            }
        } catch (ArithmeticException | NumberFormatException invalid) {
            return null;
        }
    }

    public String toEncodedString() {
        String value = id + "|" + descriptor + "|" + action.name() + "|" + priority;
        return literalValue == null ? value : value + "|" + literalValue;
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
