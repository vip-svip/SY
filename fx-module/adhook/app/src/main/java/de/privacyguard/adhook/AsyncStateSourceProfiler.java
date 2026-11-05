package de.privacyguard.adhook;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/** Metadata-only discovery of Java/Kotlin asynchronous state declaration shapes. */
public final class AsyncStateSourceProfiler {
    public enum SourceKind { KOTLIN_FLOW, LIVE_DATA, RX_STREAM, FUTURE, OTHER_ASYNC }
    public static final class Source {
        public final String ownerClass;
        public final String memberName;
        public final String declaredType;
        public final SourceKind kind;
        public final boolean method;
        Source(String owner, String member, String type, SourceKind kind, boolean method) {
            ownerClass=owner; memberName=member; declaredType=type; this.kind=kind; this.method=method;
        }
    }
    private static final int MAX_MEMBERS=128;
    private AsyncStateSourceProfiler() {}

    public static List<Source> inspect(Class<?> type) {
        if(type==null) throw new IllegalArgumentException("type required");
        List<Source> result=new ArrayList<>();
        try {
            Field[] fields=type.getDeclaredFields();
            for(int i=0;i<fields.length && i<MAX_MEMBERS;i++) {
                java.lang.reflect.Field field=fields[i];
                if(Modifier.isStatic(field.getModifiers()) || field.isSynthetic()) continue;
                add(result,type.getName(),field.getName(),field.getType(),false);
            }
        } catch(Throwable ignored) { }
        try {
            Method[] methods=type.getDeclaredMethods();
            for(int i=0;i<methods.length && i<MAX_MEMBERS;i++) {
                Method method=methods[i];
                if(Modifier.isStatic(method.getModifiers()) || method.isSynthetic() || method.isBridge()) continue;
                add(result,type.getName(),method.getName(),method.getReturnType(),true);
                Class<?>[] parameters=method.getParameterTypes();
                for(int p=0;p<parameters.length;p++) {
                    add(result,type.getName(),method.getName()+"#arg"+p,parameters[p],true);
                }
            }
        } catch(Throwable ignored) { }
        return Collections.unmodifiableList(result);
    }

    private static void add(List<Source> out,String owner,String member,Class<?> type,boolean method) {
        if(type==null || MemberCandidateClassifier.kindOf(type)!=MemberCandidateClassifier.Kind.ASYNC_FLOW) return;
        String name=type.getName().toLowerCase(Locale.ROOT);
        SourceKind kind;
        if(name.contains("kotlinx.coroutines") || name.contains("kotlin.coroutines")) kind=SourceKind.KOTLIN_FLOW;
        else if(name.contains("livedata") || name.contains("mutablelive")) kind=SourceKind.LIVE_DATA;
        else if(name.contains("rxjava") || name.contains("observable") || name.contains("flowable")
                || name.contains("publisher") || name.contains("reactor")) kind=SourceKind.RX_STREAM;
        else if(name.contains("future") || name.contains("completionstage") || name.contains("deferred"))
            kind=SourceKind.FUTURE;
        else kind=SourceKind.OTHER_ASYNC;
        out.add(new Source(owner,member,type.getName(),kind,method));
    }
}
