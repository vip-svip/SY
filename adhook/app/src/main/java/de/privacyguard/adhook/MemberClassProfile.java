package de.privacyguard.adhook;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** Metadata-only profiler for membership-related state-holder classes. */
public final class MemberClassProfile {
    public static final class Result {
        public final String className;
        public final int score;
        public final boolean namedCandidate;
        public final boolean obfuscatedStateShape;
        public final List<MemberCandidateClassifier.Candidate> fields;
        public final List<MemberCandidateClassifier.Candidate> methods;
        Result(String name, int score, boolean named, boolean obfuscated,
               List<MemberCandidateClassifier.Candidate> fields,
               List<MemberCandidateClassifier.Candidate> methods) {
            this.className=name; this.score=score; this.namedCandidate=named;
            this.obfuscatedStateShape=obfuscated;
            this.fields=Collections.unmodifiableList(fields);
            this.methods=Collections.unmodifiableList(methods);
        }
        public boolean isCandidate() { return namedCandidate || obfuscatedStateShape || score >= 3; }
    }
    private MemberClassProfile() {}
    public static Result inspect(Class<?> type) {
        if (type == null) throw new IllegalArgumentException("type required");
        String name=type.getName();
        int score=MemberCandidateClassifier.nameScore(name);
        boolean named=score>=2;
        List<MemberCandidateClassifier.Candidate> fields=new ArrayList<>();
        List<MemberCandidateClassifier.Candidate> methods=new ArrayList<>();
        try {
            Field[] declared=type.getDeclaredFields();
            for(int i=0;i<declared.length && i<128;i++) {
                Field f=declared[i];
                if(Modifier.isStatic(f.getModifiers()) || f.isSynthetic()) continue;
                MemberCandidateClassifier.Candidate c=MemberCandidateClassifier.inspect(f);
                if(c.isWorthInspecting()) { fields.add(c); score+=Math.min(c.score,3); }
            }
        } catch(Throwable ignored) {}
        try {
            Method[] declared=type.getDeclaredMethods();
            for(int i=0;i<declared.length && i<128;i++) {
                Method m=declared[i];
                if(!MemberCandidateClassifier.shouldObserveMethod(m,named,false)) continue;
                methods.add(MemberCandidateClassifier.inspect(m));
                score+=Math.min(MemberCandidateClassifier.inspect(m).score,3);
            }
        } catch(Throwable ignored) {}
        boolean obfuscated=!named && MemberCandidateClassifier.hasObfuscatedStateShape(type);
        if(obfuscated) score+=2;
        return new Result(name,Math.min(score,100),named,obfuscated,fields,methods);
    }
    /** Safe summary contains declaration metadata only, never field/method values. */
    public static String summarize(Result result) {
        if(result==null) return "member_profile=none";
        String name=result.className;
        int dot=name.lastIndexOf('.');
        if(dot>=0) name=name.substring(dot+1);
        StringBuilder safe=new StringBuilder(64);
        for(int i=0;i<name.length() && safe.length()<64;i++) {
            char ch=name.charAt(i);
            safe.append(Character.isLetterOrDigit(ch)||ch=='_'||ch=='$'?ch:'_');
        }
        return "class="+safe+";score="+result.score+";named="+result.namedCandidate
                +";obfuscatedShape="+result.obfuscatedStateShape
                +";fields="+result.fields.size()+";methods="+result.methods.size();
    }
}
