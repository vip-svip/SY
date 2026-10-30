package de.privacyguard.adhook;

/**
 * A bounded, package-scoped Debug fixture rule for a developer-owned application.
 * Supported descriptor syntaxes normalize to an exact no-argument boolean getter.
 * The parser caps each package at 16 rules and constrains actions to local boolean fixtures.
 */
public final class DeveloperHookRule {
    public final String id;
    public final String descriptor;
    public final boolean replacement;
    public final int priority;

    private DeveloperHookRule(String id, String descriptor, boolean replacement, int priority) {
        this.id = id;
        this.descriptor = descriptor;
        this.replacement = replacement;
        this.priority = priority;
    }

    public static DeveloperHookRule parse(String encoded, String packageName) {
        if (encoded == null || packageName == null || encoded.length() > 768) return null;
        String[] fields = encoded.split("\\|", -1);
        if (fields.length != 4) return null;
        String id = fields[0].trim();
        if (!id.matches("[A-Za-z][A-Za-z0-9_-]{0,31}")) return null;
        String descriptor = normalizeDescriptor(fields[1].trim());
        if (descriptor == null || !isInPackage(descriptor, packageName)) return null;
        String action = fields[2].trim().toUpperCase(java.util.Locale.ROOT);
        final boolean replacement;
        if ("TRUE".equals(action) || "RETURN_TRUE".equals(action)) replacement = true;
        else if ("FALSE".equals(action) || "RETURN_FALSE".equals(action)) replacement = false;
        else return null;
        final int priority;
        try { priority = Integer.parseInt(fields[3].trim()); }
        catch (NumberFormatException e) { return null; }
        if (priority < -1000 || priority > 1000) return null;
        return new DeveloperHookRule(id, descriptor, replacement, priority);
    }

    static String normalizeDescriptor(String value) {
        if (value == null || value.length() > 512) return null;
        String d = value;
        if (d.startsWith("L") && d.contains(";->")) {
            int arrow = d.indexOf(";->");
            d = d.substring(1, arrow).replace('/', '.') + "#" + d.substring(arrow + 3);
        } else if (!d.contains("#")) {
            int paren = d.indexOf('(');
            int dot = paren < 0 ? -1 : d.lastIndexOf('.', paren);
            if (dot > 0) d = d.substring(0, dot) + "#" + d.substring(dot + 1);
        }
        if (!d.matches("[A-Za-z_$][A-Za-z0-9_$.]*#[A-Za-z_$][A-Za-z0-9_$]*\\(\\)Z")) return null;
        return d;
    }

    private static boolean isInPackage(String descriptor, String packageName) {
        int split = descriptor.indexOf('#');
        String owner = descriptor.substring(0, split);
        return owner.startsWith(packageName + ".")
                && !owner.startsWith("java.") && !owner.startsWith("android.");
    }
}
