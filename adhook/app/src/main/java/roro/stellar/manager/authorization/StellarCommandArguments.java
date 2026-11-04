package roro.stellar.manager.authorization;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * Parses the narrow Stellar UI command protocol before any text reaches su -c.
 * The module script still applies its own authorization and operation allowlists;
 * this layer prevents shell syntax from being interpreted at the outer su boundary.
 */
final class StellarCommandArguments {
    private static final int MAX_INPUT_LENGTH = 8192;
    private static final Pattern PACKAGE =
            Pattern.compile("[A-Za-z0-9_]+([.][A-Za-z0-9_-]+)+");
    private static final Set<String> SCOPES = Collections.unmodifiableSet(new HashSet<>(Arrays.asList(
            "SHELL_ID_COMMAND", "PACKAGE_LIST_COMMAND", "PROCESS_LIST_COMMAND",
            "PROPERTY_READ_COMMAND", "SETTINGS_READ_COMMAND", "SELINUX_STATUS_COMMAND",
            "FILESYSTEM_READ_COMMAND", "SERVICE_LIST_COMMAND", "SECURE_SETTINGS_WRITE",
            "APPOPS_MANAGE", "RUNTIME_PERMISSION_MANAGE", "TERMINAL_COMMAND")));
    private static final Set<String> READ_ONLY_SCOPES = Collections.unmodifiableSet(new HashSet<>(Arrays.asList(
            "SHELL_ID_COMMAND", "PACKAGE_LIST_COMMAND", "PROCESS_LIST_COMMAND",
            "PROPERTY_READ_COMMAND", "SETTINGS_READ_COMMAND", "SELINUX_STATUS_COMMAND",
            "FILESYSTEM_READ_COMMAND", "SERVICE_LIST_COMMAND")));

    private StellarCommandArguments() { }

    static String buildScriptCommand(String raw) {
        List<String> args = tokenize(raw);
        validate(args);
        StringBuilder command = new StringBuilder()
                .append("MP=''; for d in /data/adb/modules/privacyguard ")
                .append("/data/adb/modules_update/privacyguard /data/adb/modules/privacy_guard ")
                .append("/data/adb/modules/pg; do ")
                .append("if [ -s \"$d/module.prop\" ] && grep -q '^id=privacyguard$' \"$d/module.prop\"; ")
                .append("then MP=\"$d\"; break; fi; done; ")
                .append("[ -n \"$MP\" ] || exit 20; ")
                .append("sh \"$MP/scripts/yulong-stellar-control.sh\"");
        for (String arg : args) command.append(' ').append(shellQuote(arg));
        return command.toString();
    }

    private static List<String> tokenize(String raw) {
        if (raw == null || raw.isEmpty() || raw.length() > MAX_INPUT_LENGTH)
            throw new IllegalArgumentException("empty or oversized request");
        List<String> args = new ArrayList<>(4);
        int i = 0;
        while (i < raw.length()) {
            while (i < raw.length() && raw.charAt(i) == ' ') i++;
            if (i == raw.length()) break;
            StringBuilder token = new StringBuilder();
            boolean quoted = raw.charAt(i) == '\'';
            if (quoted) {
                i++;
                while (i < raw.length() && raw.charAt(i) != '\'') {
                    char ch = raw.charAt(i++);
                    if (!isSafeQuotedCharacter(ch))
                        throw new IllegalArgumentException("quoted argument contains shell syntax or control data");
                    token.append(ch);
                }
                if (i >= raw.length() || raw.charAt(i) != '\'')
                    throw new IllegalArgumentException("unterminated quoted argument");
                i++;
                if (i < raw.length() && raw.charAt(i) != ' ')
                    throw new IllegalArgumentException("quoted argument is not token-delimited");
            } else {
                while (i < raw.length() && raw.charAt(i) != ' ') {
                    char ch = raw.charAt(i++);
                    if (!isSafeUnquotedCharacter(ch))
                        throw new IllegalArgumentException("unquoted argument contains unsafe data");
                    token.append(ch);
                }
            }
            if (token.length() == 0) throw new IllegalArgumentException("empty argument");
            args.add(token.toString());
            if (args.size() > 4) throw new IllegalArgumentException("too many arguments");
        }
        if (args.isEmpty()) throw new IllegalArgumentException("empty request");
        return args;
    }

    private static boolean isSafeQuotedCharacter(char ch) {
        return (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z')
                || (ch >= '0' && ch <= '9') || ch == '_' || ch == '.'
                || ch == ':' || ch == '/' || ch == '-' || ch == ' ';
    }

    private static boolean isSafeUnquotedCharacter(char ch) {
        return (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z')
                || (ch >= '0' && ch <= '9') || ch == '_' || ch == '-';
    }

    private static void validate(List<String> args) {
        String action = args.get(0);
        switch (action) {
            case "list": case "logs": case "clear-logs":
                requireSize(args, 1);
                return;
            case "pkg-set":
                requireSize(args, 3);
                requirePackage(args.get(1));
                requireBit(args.get(2));
                return;
            case "scope-set":
                requireSize(args, 4);
                requirePackage(args.get(1));
                requireScope(args.get(2));
                requireBit(args.get(3));
                if ("TERMINAL_COMMAND".equals(args.get(2)) && "1".equals(args.get(3)))
                    throw new IllegalArgumentException("terminal command scope cannot be enabled");
                return;
            case "always-set":
                requireSize(args, 4);
                requirePackage(args.get(1));
                requireText(args.get(2), 512);
                requireBit(args.get(3));
                return;
            case "permission":
                requireSize(args, 4);
                requirePackage(args.get(1));
                if (!("grant".equals(args.get(2)) || "revoke".equals(args.get(2))))
                    throw new IllegalArgumentException("invalid permission action");
                requireText(args.get(3), 255);
                return;
            case "appops":
                requireSize(args, 4);
                requirePackage(args.get(1));
                requireText(args.get(2), 64);
                requireText(args.get(3), 32);
                return;
            case "secure-setting":
                requireSize(args, 4);
                requirePackage(args.get(1));
                requireText(args.get(2), 64);
                requireText(args.get(3), 32);
                return;
            case "run":
                requireSize(args, 4);
                requirePackage(args.get(1));
                if (!READ_ONLY_SCOPES.contains(args.get(2)))
                    throw new IllegalArgumentException("run only accepts read-only scopes");
                requireText(args.get(3), 512);
                return;
            default:
                throw new IllegalArgumentException("unsupported Stellar operation");
        }
    }

    private static void requireSize(List<String> args, int expected) {
        if (args.size() != expected) throw new IllegalArgumentException("wrong argument count");
    }

    private static void requirePackage(String value) {
        if (!PACKAGE.matcher(value).matches()) throw new IllegalArgumentException("invalid package name");
    }

    private static void requireScope(String value) {
        if (!SCOPES.contains(value)) throw new IllegalArgumentException("unknown Stellar scope");
    }

    private static void requireBit(String value) {
        if (!("0".equals(value) || "1".equals(value)))
            throw new IllegalArgumentException("invalid boolean flag");
    }

    private static void requireText(String value, int maxLength) {
        if (value == null || value.isEmpty() || value.length() > maxLength)
            throw new IllegalArgumentException("argument length is outside the allowed range");
        for (int i = 0; i < value.length(); i++) {
            if (!isSafeQuotedCharacter(value.charAt(i)))
                throw new IllegalArgumentException("argument contains unsafe characters");
        }
    }

    private static String shellQuote(String value) {
        return "'" + value.replace("'", "'\\''") + "'";
    }
}
