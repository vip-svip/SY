package de.privacyguard.adhook;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** Read-only lifecycle trace for an application's own auth and entitlement integration. */
public final class AuthorizationTrace {
    public enum Stage { LOGIN_REQUEST, LOGIN_RESULT, SESSION_RESTORE, TOKEN_REFRESH,
        TOKEN_REFRESH_RESULT, LOGOUT, ENTITLEMENT_REQUEST, ENTITLEMENT_RESULT,
        BILLING_RESULT, UPDATE_CHECK, UPDATE_RESULT }
    public enum Outcome { STARTED, SUCCESS, REJECTED, EXPIRED, REVOKED, PENDING, ERROR, SKIPPED, UNKNOWN }

    public interface Clock { long elapsedRealtimeMs(); }

    public static final class Event {
        public final long elapsedRealtimeMs;
        public final Stage stage;
        public final Outcome outcome;
        public final int httpStatus;
        public final long durationMs;
        public final String source;
        public final String detailCode;
        private Event(long time, Stage stage, Outcome outcome, int status, long duration,
                      String source, String detail) {
            this.elapsedRealtimeMs=time; this.stage=stage; this.outcome=outcome;
            this.httpStatus=status; this.durationMs=duration; this.source=source; this.detailCode=detail;
        }
    }

    private static final int DEFAULT_CAPACITY=256;
    private final int capacity;
    private final Clock clock;
    private final ArrayDeque<Event> events=new ArrayDeque<>();

    public AuthorizationTrace() { this(DEFAULT_CAPACITY, new Clock() {
        @Override public long elapsedRealtimeMs() { return System.nanoTime()/1000000L; }
    }); }
    public AuthorizationTrace(int capacity) { this(capacity, new Clock() {
        @Override public long elapsedRealtimeMs() { return System.nanoTime()/1000000L; }
    }); }
    public AuthorizationTrace(int capacity, Clock clock) {
        if (capacity<1 || capacity>4096) throw new IllegalArgumentException("capacity out of range");
        if (clock==null) throw new IllegalArgumentException("clock required");
        this.capacity=capacity; this.clock=clock;
    }

    /** Never pass passwords, tokens, cookies, raw response bodies, account IDs or full URLs. */
    public synchronized void record(Stage stage, Outcome outcome, int httpStatus,
                                    long durationMs, String source, String detailCode) {
        if (stage==null || outcome==null) throw new IllegalArgumentException("stage/outcome required");
        if (httpStatus<0 || httpStatus>599) throw new IllegalArgumentException("invalid HTTP status");
        if (durationMs < -1) throw new IllegalArgumentException("invalid duration");
        Event event=new Event(clock.elapsedRealtimeMs(),stage,outcome,httpStatus,durationMs,
                safeLabel(source),safeLabel(detailCode));
        if (events.size()==capacity) events.removeFirst();
        events.addLast(event);
    }

    public synchronized List<Event> snapshot() {
        return Collections.unmodifiableList(new ArrayList<>(events));
    }
    public synchronized void clear() { events.clear(); }

    private static String safeLabel(String value) {
        if (value==null || value.isEmpty()) return "";
        StringBuilder out=new StringBuilder(Math.min(value.length(),48));
        for (int i=0;i<value.length() && out.length()<48;i++) {
            char c=value.charAt(i);
            if ((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='_'||c=='-'||c=='.') out.append(c);
            else out.append('_');
        }
        return out.toString();
    }
}
