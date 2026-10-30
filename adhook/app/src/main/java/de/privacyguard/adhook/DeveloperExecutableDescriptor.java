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
        int open = value.indexOf('(');
        int close = value.indexOf(')', open + 1);
        if (open <= 0 || close < open || close != value.lastIndexOf(')')) return null;
        int hash = value.lastIndexOf('#', open);
        int dot = value.lastIndexOf('.', open);
        int split = Math.max(hash, dot);
        if (split <= 0) return null;
        String owner = value.substring(0, split);
        String name = value.substring(split + 1, open);
        if (!owner.startsWith(packageName + ".") || !name.matches("[A-Za-z_$][A-Za-z0-9_$]*|<init>")) return null;
        String argsText = value.substring(open + 1, close).trim();
        List<String> args = new ArrayList<>();
        if (!argsText.isEmpty()) {
            for (String part : argsText.split(",", -1)) {
                String descriptor = javaTypeDescriptor(part.trim(), false);
                if (descriptor == null || args.size() >= 64) return null;
                args.add(descriptor);
            }
        }
        String result = javaTypeDescriptor(value.substring(close + 1).trim(), true);
        if (result == null || ("<init>".equals(name) && !"V".equals(result))) return null;
        StringBuilder out = new StringBuilder("L").append(owner.replace('.', '/')).append(";->")
                .append(name).append('(');
        for (String arg : args) out.append(arg);
        out.append(')').append(result);
        String descriptor = out.toString();
        return parse(descriptor, packageName) == null ? null : descriptor;
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