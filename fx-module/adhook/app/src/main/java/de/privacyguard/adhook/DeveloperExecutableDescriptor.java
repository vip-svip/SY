package de.privacyguard.adhook;

import java.lang.reflect.Constructor;
import java.lang.reflect.Executable;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** Exact JVM descriptor parser/resolver for opt-in developer Debug/Test packages. */
public final class DeveloperExecutableDescriptor {
    public final String owner, name, returnDescriptor;
    public final List<String> parameterDescriptors;

    private DeveloperExecutableDescriptor(String owner, String name, List<String> args, String result) {
        this.owner=owner; this.name=name;
        this.parameterDescriptors=Collections.unmodifiableList(args);
        this.returnDescriptor=result;
    }

    /** Example: Lcom/example/app/Foo;->run(Ljava/lang/String;[I)Z */
    public static DeveloperExecutableDescriptor parse(String value, String packageName) {
        if (value==null || packageName==null || value.length()>768 || !value.startsWith("L")) return null;
        int arrow=value.indexOf(";->");
        if (arrow<2) return null;
        String owner=value.substring(1,arrow).replace('/','.');
        if (!owner.matches("[A-Za-z_$][A-Za-z0-9_$.]*") || !owner.startsWith(packageName+".")
                || owner.startsWith("java.") || owner.startsWith("android.")) return null;
        int open=value.indexOf('(',arrow+3), close=value.indexOf(')',open+1);
        if (open<0 || close<0 || close!=value.lastIndexOf(')')) return null;
        String name=value.substring(arrow+3,open);
        if (!("<init>".equals(name) || name.matches("[A-Za-z_$][A-Za-z0-9_$]*"))) return null;
        String args=value.substring(open+1,close);
        List<String> parsed=new ArrayList<>();
        for (int p=0;p<args.length();) {
            int end=typeEnd(args,p,false);
            if (end<0 || parsed.size()>=64) return null;
            parsed.add(args.substring(p,end)); p=end;
        }
        String result=value.substring(close+1);
        if (typeEnd(result,0,true)!=result.length()) return null;
        if ("<init>".equals(name) && !"V".equals(result)) return null;
        return new DeveloperExecutableDescriptor(owner,name,parsed,result);
    }

    /**
     * Converts a Java source-style exact signature to a JVM descriptor.
     * Accepted form: com.example.Foo#run(java.lang.String,int[])java.lang.Object
     * Generic type arguments are intentionally rejected: runtime erasure must be explicit.
     */
    public static String fromJavaSignature(String value, String packageName) {
        if (value == null || packageName == null || value.length() > 768) return null;
        // Kotlin declaration form: fun com.example.Foo.run(value: kotlin.String, count: Int): Boolean
        // Parameter names are presentation-only; runtime matching remains based on exact erased JVM types.
        String source = value.trim();
        boolean kotlinSyntax = source.startsWith("fun ");
        if (kotlinSyntax) source = source.substring(4).trim();
        String frida = fromFridaOverloadSignature(source, packageName);
        if (frida != null) return frida;
        int open = source.indexOf('(');
        int close = source.indexOf(')', open + 1);
        if (open <= 0 || close < open || close != source.lastIndexOf(')')) return null;
        int hash = source.lastIndexOf('#', open);
        int dot = source.lastIndexOf('.', open);
        int split = Math.max(hash, dot);
        if (split <= 0) return null;
        String owner = source.substring(0, split);
        String name = source.substring(split + 1, open);
        if (!owner.startsWith(packageName + ".") || !name.matches("[A-Za-z_$][A-Za-z0-9_$]*|<init>")) return null;
        String argsText = source.substring(open + 1, close).trim();
        List<String> args = new ArrayList<>();
        if (!argsText.isEmpty()) {
            for (String part : argsText.split(",", -1)) {
                String argument = part.trim();
                // Kotlin named parameters use "name: Type". Reject defaults,
                // destructuring, and malformed names rather than guessing an ABI.
                if (argument.indexOf('=') >= 0) return null;
                int typeSeparator = argument.indexOf(':');
                if (typeSeparator >= 0) {
                    kotlinSyntax = true;
                    String parameterName = argument.substring(0, typeSeparator).trim();
                    if (!parameterName.matches("[A-Za-z_$][A-Za-z0-9_$]*")) return null;
                    argument = argument.substring(typeSeparator + 1).trim();
                }
                String descriptor = kotlinSyntax
                        ? kotlinTypeDescriptor(argument, false) : javaTypeDescriptor(argument, false);
                if (descriptor == null || args.size() >= 64) return null;
                args.add(descriptor);
            }
        }
        String returnText = source.substring(close + 1).trim();
        if (returnText.startsWith(":")) returnText = returnText.substring(1).trim();
        else if (returnText.startsWith("->")) returnText = returnText.substring(2).trim();
        else if (returnText.regionMatches(true, 0, "returns ", 0, 8))
            returnText = returnText.substring(8).trim();
        String result = kotlinSyntax
                ? kotlinTypeDescriptor(returnText, true) : javaTypeDescriptor(returnText, true);
        if (result == null || ("<init>".equals(name) && !"V".equals(result))) return null;
        StringBuilder out = new StringBuilder("L").append(owner.replace('.', '/')).append(";->")
                .append(name).append('(');
        for (String arg : args) out.append(arg);
        out.append(')').append(result);
        String descriptor = out.toString();
        return parse(descriptor, packageName) == null ? null : descriptor;
    }

    /**
     * Frida Java bridge overload form with an explicit return type:
     * com.example.app.Auth.isReady.overload('java.lang.String', 'int[]') -> boolean
     *
     * Frida .overload() does not report the method return type. FX therefore
     * requires ':'/'->'/'returns' plus a result type to keep the final method
     * descriptor exact and fully verifiable.
     */
    private static String fromFridaOverloadSignature(String value, String packageName) {
        final String marker = ".overload(";
        int markerAt = value.indexOf(marker);
        if (markerAt <= 0 || markerAt != value.lastIndexOf(marker)) return null;
        int open = markerAt + marker.length() - 1;
        int close = value.indexOf(')', open + 1);
        if (close < 0 || close != value.lastIndexOf(')')) return null;

        String ownerAndMethod = value.substring(0, markerAt).trim();
        int split = ownerAndMethod.lastIndexOf('.');
        if (split <= 0 || split == ownerAndMethod.length() - 1) return null;
        String owner = ownerAndMethod.substring(0, split).trim();
        String method = ownerAndMethod.substring(split + 1).trim();
        if (!method.matches("[A-Za-z_$][A-Za-z0-9_$]*|<init>")) return null;

        String returnText = value.substring(close + 1).trim();
        if (returnText.startsWith("->")) returnText = returnText.substring(2).trim();
        else if (returnText.startsWith(":")) returnText = returnText.substring(1).trim();
        else if (returnText.regionMatches(true, 0, "returns ", 0, 8))
            returnText = returnText.substring(8).trim();
        else return null;
        if (returnText.isEmpty()) return null;

        String argsText = value.substring(open + 1, close).trim();
        List<String> args = new ArrayList<>();
        if (!argsText.isEmpty()) {
            for (String raw : argsText.split(",", -1)) {
                String arg = raw.trim();
                if ((arg.startsWith("'") && arg.endsWith("'"))
                        || (arg.startsWith("\"") && arg.endsWith("\""))) {
                    if (arg.length() < 2) return null;
                    arg = arg.substring(1, arg.length() - 1).trim();
                }
                if (arg.isEmpty() || arg.contains("'") || arg.contains("\"")
                        || arg.contains("<") || arg.contains(">")) return null;
                args.add(arg);
            }
        }
        StringBuilder javaSignature = new StringBuilder(owner).append('#').append(method).append('(');
        for (int i = 0; i < args.size(); i++) {
            if (i > 0) javaSignature.append(',');
            javaSignature.append(args.get(i));
        }
        javaSignature.append(")->").append(returnText);
        return fromJavaSignature(javaSignature.toString(), packageName);
    }

    /**
     * Kotlin source types retain nullability in the JVM ABI: nullable primitive
     * values are boxed, while nullable reference values keep their reference descriptor.
     * Array<T> is accepted only when T is a concrete, exactly representable type.
     */
    private static String kotlinTypeDescriptor(String type, boolean allowVoid) {
        if (type == null) return null;
        String value = type.trim();
        boolean nullable = value.endsWith("?");
        if (nullable) value = value.substring(0, value.length() - 1).trim();
        if (value.startsWith("Array<") && value.endsWith(">")) {
            if (nullable && value.length() <= 7) return null;
            String component = kotlinTypeDescriptor(value.substring(6, value.length() - 1), false);
            if (component == null || "V".equals(component)) return null;
            if (component.length() == 1 && "ZBCSIJFD".contains(component)) {
                switch (component) {
                    case "Z": component = "Ljava/lang/Boolean;"; break;
                    case "B": component = "Ljava/lang/Byte;"; break;
                    case "C": component = "Ljava/lang/Character;"; break;
                    case "S": component = "Ljava/lang/Short;"; break;
                    case "I": component = "Ljava/lang/Integer;"; break;
                    case "J": component = "Ljava/lang/Long;"; break;
                    case "F": component = "Ljava/lang/Float;"; break;
                    case "D": component = "Ljava/lang/Double;"; break;
                    default: return null;
                }
            }
            return "[" + component;
        }
        String primitive = null;
        String boxed = null;
        switch (value) {
            case "Boolean": case "kotlin.Boolean": primitive = "Z"; boxed = "Ljava/lang/Boolean;"; break;
            case "Byte": case "kotlin.Byte": primitive = "B"; boxed = "Ljava/lang/Byte;"; break;
            case "Char": case "kotlin.Char": primitive = "C"; boxed = "Ljava/lang/Character;"; break;
            case "Short": case "kotlin.Short": primitive = "S"; boxed = "Ljava/lang/Short;"; break;
            case "Int": case "kotlin.Int": primitive = "I"; boxed = "Ljava/lang/Integer;"; break;
            case "Long": case "kotlin.Long": primitive = "J"; boxed = "Ljava/lang/Long;"; break;
            case "Float": case "kotlin.Float": primitive = "F"; boxed = "Ljava/lang/Float;"; break;
            case "Double": case "kotlin.Double": primitive = "D"; boxed = "Ljava/lang/Double;"; break;
            case "Unit": case "kotlin.Unit":
                if (!allowVoid || nullable) return null;
                return "V";
            default: break;
        }
        if (primitive != null) return nullable ? boxed : primitive;
        if ("String".equals(value) || "kotlin.String".equals(value)) return "Ljava/lang/String;";
        if ("Any".equals(value) || "kotlin.Any".equals(value)) return "Ljava/lang/Object;";
        if ("Nothing".equals(value) || "kotlin.Nothing".equals(value)) return null;
        if (value.endsWith("Array") && value.startsWith("kotlin.")) {
            String array = javaTypeDescriptor(value, false);
            return array != null && array.startsWith("[") ? array : null;
        }
        if (value.indexOf('<') >= 0 || value.indexOf('>') >= 0) return null;
        String reference = javaTypeDescriptor(value, false);
        if (reference == null || reference.length() == 1 || "V".equals(reference)) return null;
        return reference;
    }

    private static String javaTypeDescriptor(String type, boolean allowVoid) {
        if (type == null || type.isEmpty() || type.indexOf('<') >= 0 || type.indexOf('>') >= 0) return null;
        int dimensions = 0;
        while (type.endsWith("[]")) { dimensions++; type = type.substring(0, type.length() - 2).trim(); }
        if (dimensions > 255 || type.isEmpty()) return null;
        String base;
        switch (type) {
            case "boolean": base = "Z"; break; case "byte": base = "B"; break;
            case "char": base = "C"; break; case "short": base = "S"; break;
            case "int": base = "I"; break; case "long": base = "J"; break;
            case "float": base = "F"; break; case "double": base = "D"; break;
            case "void": if (!allowVoid || dimensions != 0) return null; base = "V"; break;
            // Kotlin source aliases map to their exact erased JVM representation.
            case "kotlin.Boolean": base = "Z"; break;
            case "kotlin.Byte": base = "B"; break;
            case "kotlin.Char": base = "C"; break;
            case "kotlin.Short": base = "S"; break;
            case "kotlin.Int": base = "I"; break;
            case "kotlin.Long": base = "J"; break;
            case "kotlin.Float": base = "F"; break;
            case "kotlin.Double": base = "D"; break;
            case "kotlin.Unit":
                if (!allowVoid || dimensions != 0) return null;
                base = "V"; break;
            case "kotlin.String": base = "Ljava/lang/String;"; break;
            case "kotlin.Any": base = "Ljava/lang/Object;"; break;
            case "kotlin.IntArray": base = "[I"; break;
            case "kotlin.BooleanArray": base = "[Z"; break;
            case "kotlin.ByteArray": base = "[B"; break;
            case "kotlin.CharArray": base = "[C"; break;
            case "kotlin.ShortArray": base = "[S"; break;
            case "kotlin.LongArray": base = "[J"; break;
            case "kotlin.FloatArray": base = "[F"; break;
            case "kotlin.DoubleArray": base = "[D"; break;
            case "kotlin.collections.Iterable": base = "Ljava/lang/Iterable;"; break;
            case "kotlin.collections.Collection":
            case "kotlin.collections.MutableCollection": base = "Ljava/util/Collection;"; break;
            case "kotlin.collections.List":
            case "kotlin.collections.MutableList": base = "Ljava/util/List;"; break;
            case "kotlin.collections.Set":
            case "kotlin.collections.MutableSet": base = "Ljava/util/Set;"; break;
            case "kotlin.collections.Map":
            case "kotlin.collections.MutableMap": base = "Ljava/util/Map;"; break;
            // A bare JVM type code is not a Java source type; do not reinterpret legacy ()Z rules as class Z.
            case "V": case "Z": case "B": case "C": case "S": case "I":
            case "J": case "F": case "D": return null;
            case "String": case "Object": case "Boolean": case "Byte": case "Character":
            case "Short": case "Integer": case "Long": case "Float": case "Double":
                base = "Ljava/lang/" + type + ";"; break;
            default:
                if (!type.matches("[A-Za-z_$][A-Za-z0-9_$.]*")) return null;
                base = "L" + type.replace('.', '/') + ";";
        }
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < dimensions; i++) out.append('[');
        return out.append(base).toString();
    }

    public Executable resolve(ClassLoader loader) throws ReflectiveOperationException {
        if (loader==null) return null;
        Class<?> c=Class.forName(owner,false,loader);
        Class<?>[] args=new Class<?>[parameterDescriptors.size()];
        for(int i=0;i<args.length;i++) args[i]=resolveType(parameterDescriptors.get(i),loader);
        if ("<init>".equals(name)) return c.getDeclaredConstructor(args);
        Method m=c.getDeclaredMethod(name,args);
        return returnDescriptor.equals(descriptorOf(m.getReturnType())) ? m : null;
    }

    private static Class<?> resolveType(String d,ClassLoader l) throws ClassNotFoundException {
        switch(d) {
            case "Z": return boolean.class; case "B": return byte.class; case "C": return char.class;
            case "S": return short.class; case "I": return int.class; case "J": return long.class;
            case "F": return float.class; case "D": return double.class;
            default:
                if(d.startsWith("L")) return Class.forName(d.substring(1,d.length()-1).replace('/','.'),false,l);
                if(d.startsWith("[")) return Class.forName(d.replace('/','.'),false,l);
                throw new ClassNotFoundException("invalid descriptor");
        }
    }

    private static String descriptorOf(Class<?> c) {
        if(c.isArray()) return c.getName().replace('.','/');
        if(!c.isPrimitive()) return "L"+c.getName().replace('.','/')+";";
        if(c==void.class)return "V"; if(c==boolean.class)return "Z"; if(c==byte.class)return "B";
        if(c==char.class)return "C"; if(c==short.class)return "S"; if(c==int.class)return "I";
        if(c==long.class)return "J"; if(c==float.class)return "F"; if(c==double.class)return "D";
        throw new IllegalArgumentException("unknown primitive");
    }

    private static int typeEnd(String s,int start,boolean allowVoid) {
        if(s==null || start>=s.length()) return -1;
        int p=start; while(p<s.length() && s.charAt(p)=='[') p++;
        if(p>=s.length() || p-start>255) return -1;
        char k=s.charAt(p);
        if("ZBCSIJFD".indexOf(k)>=0) return p+1;
        if(k=='V') return allowVoid && p==start ? p+1 : -1;
        if(k!='L') return -1;
        int semi=s.indexOf(';',p+1);
        if(semi<=p+1) return -1;
        String n=s.substring(p+1,semi);
        if(!n.matches("[A-Za-z_$][A-Za-z0-9_$]*(/[A-Za-z_$][A-Za-z0-9_$]*)*")) return -1;
        return semi+1;
    }
}