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