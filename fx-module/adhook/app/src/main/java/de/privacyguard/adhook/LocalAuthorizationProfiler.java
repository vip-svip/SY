package de.privacyguard.adhook;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/**
 * Metadata-only profiler for locally persisted authorization state in developer-owned apps.
 * It never reads preference values, files, databases, keystore entries, or invokes app methods.
 */
public final class LocalAuthorizationProfiler {
    public enum StorageKind { SHARED_PREFERENCES, DATASTORE, ROOM_OR_SQLITE, FILE_BACKED, ENCRYPTED_PREFERENCES, KEYSTORE, UNKNOWN }
    public static final class Evidence {
        public final String owner;
        public final String member;
        public final String type;
        public final StorageKind storageKind;
        public final int score;
        Evidence(String owner,String member,String type,StorageKind storageKind,int score) {
            this.owner=owner; this.member=member; this.type=type; this.storageKind=storageKind; this.score=score;
        }
    }
    public static final class Result {
        public final String className;
        public final List<Evidence> evidence;
        Result(String className,List<Evidence> evidence) {
            this.className=className;
            this.evidence=Collections.unmodifiableList(new ArrayList<>(evidence));
        }
        public boolean isCandidate() { return !evidence.isEmpty(); }
    }
    private static final int MAX_FIELDS=128, MAX_METHODS=128, MAX_EVIDENCE=64;
    private LocalAuthorizationProfiler() {}

    public static Result inspect(Class<?> type) {
        if(type==null) return new Result("",Collections.emptyList());
        List<Evidence> out=new ArrayList<>();
        Field[] fields;
        Method[] methods;
        try { fields=type.getDeclaredFields(); } catch(Throwable ignored) { fields=new Field[0]; }
        try { methods=type.getDeclaredMethods(); } catch(Throwable ignored) { methods=new Method[0]; }
        for(int i=0;i<Math.min(fields.length,MAX_FIELDS)&&out.size()<MAX_EVIDENCE;i++) {
            Field f=fields[i];
            if(Modifier.isStatic(f.getModifiers())||f.isSynthetic()) continue;
            StorageKind kind=storageKind(f.getType().getName());
            int score=score(f.getName(),f.getType().getName(),kind);
            if(score>=2) out.add(new Evidence(type.getName(),f.getName(),f.getType().getName(),kind,score));
        }
        for(int i=0;i<Math.min(methods.length,MAX_METHODS)&&out.size()<MAX_EVIDENCE;i++) {
            Method m=methods[i];
            if(Modifier.isStatic(m.getModifiers())||m.isSynthetic()||m.isBridge()) continue;
            StorageKind kind=storageKind(m.getReturnType().getName());
            int score=score(m.getName(),m.getReturnType().getName(),kind);
            if(score>=3) out.add(new Evidence(type.getName(),m.getName(),m.getReturnType().getName(),kind,score));
        }
        return new Result(type.getName(),out);
    }
    static StorageKind storageKind(String typeName) {
        String n=typeName==null?"":typeName.toLowerCase(Locale.ROOT);
        if(n.contains("encryptedsharedpreferences")||n.contains("encryptedpreferences")) return StorageKind.ENCRYPTED_PREFERENCES;
        if(n.contains("sharedpreferences")) return StorageKind.SHARED_PREFERENCES;
        if(n.contains("datastore")||n.contains("preferences.data")) return StorageKind.DATASTORE;
        if(n.contains("room")||n.contains("sqlite")||n.contains("dao")) return StorageKind.ROOM_OR_SQLITE;
        if(n.contains("keystore")||n.contains("secretkey")||n.contains("privatekey")) return StorageKind.KEYSTORE;
        if(n.contains("file")||n.contains("path")||n.contains("randomaccess")) return StorageKind.FILE_BACKED;
        return StorageKind.UNKNOWN;
    }
    private static int score(String name,String type,StorageKind kind) {
        String n=(name==null?"":name).toLowerCase(Locale.ROOT);
        String t=(type==null?"":type).toLowerCase(Locale.ROOT);
        int score=0;
        String[] markers={"vip","premium","member","membership","entitlement","license","licence",
                "subscription","expire","expiry","validuntil","paid","prostatus","accesslevel","plan"};
        for(String marker:markers) if(n.contains(marker)) { score+=2; break; }
        if(kind!=StorageKind.UNKNOWN) score+=2;
        if(t.contains("boolean")||t.equals("int")||t.contains("integer")||t.contains("enum")) score++;
        return score;
    }
}
