package de.privacyguard.adhook;

/**
 * Explicit adapter for request/response boundaries in OkHttp, Retrofit, Volley,
 * HttpURLConnection, or a custom client. The host app calls begin/complete;
 * this class never intercepts traffic or reads request/response bodies.
 */
public final class AuthorizationRequestTracker {
    public static final class Request {
        private final AuthorizationTrace.Stage stage;
        private final long startedAt;
        private final String source;
        private boolean completed;
        private Request(AuthorizationTrace.Stage stage,long startedAt,String source) {
            this.stage=stage; this.startedAt=startedAt; this.source=source;
        }
    }

    private final AuthorizationTrace trace;
    private final AuthorizationTrace.Clock clock;

    public AuthorizationRequestTracker(AuthorizationTrace trace, AuthorizationTrace.Clock clock) {
        if (trace==null || clock==null) throw new IllegalArgumentException("trace and clock required");
        this.trace=trace; this.clock=clock;
    }

    public Request begin(AuthorizationTrace.Stage stage,String source) {
        requireRequestStage(stage);
        long now=clock.elapsedRealtimeMs();
        trace.record(stage,AuthorizationTrace.Outcome.STARTED,0,-1,source,"request_started");
        return new Request(stage,now,source);
    }

    public synchronized boolean complete(Request request,int httpStatus,Throwable failure) {
        if (request==null) throw new IllegalArgumentException("request required");
        if (request.completed) return false;
        request.completed=true;
        long duration=Math.max(0,clock.elapsedRealtimeMs()-request.startedAt);
        AuthorizationTrace.Outcome outcome;
        String code;
        if (failure!=null) {
            outcome=AuthorizationTrace.Outcome.ERROR;
            code="transport_error";
        } else if (httpStatus>=200 && httpStatus<300) {
            outcome=AuthorizationTrace.Outcome.SUCCESS;
            code="http_success";
        } else if (httpStatus==401 || httpStatus==403) {
            outcome=AuthorizationTrace.Outcome.REJECTED;
            code="http_rejected";
        } else if (httpStatus==0) {
            outcome=AuthorizationTrace.Outcome.ERROR;
            code="no_http_response";
        } else {
            outcome=AuthorizationTrace.Outcome.ERROR;
            code="http_error";
        }
        trace.record(resultStage(request.stage),outcome,httpStatus,duration,request.source,code);
        return true;
    }

    private static AuthorizationTrace.Stage resultStage(AuthorizationTrace.Stage stage) {
        switch(stage) {
            case LOGIN_REQUEST: return AuthorizationTrace.Stage.LOGIN_RESULT;
            case TOKEN_REFRESH: return AuthorizationTrace.Stage.TOKEN_REFRESH_RESULT;
            case ENTITLEMENT_REQUEST: return AuthorizationTrace.Stage.ENTITLEMENT_RESULT;
            case UPDATE_CHECK: return AuthorizationTrace.Stage.UPDATE_RESULT;
            default: throw new IllegalArgumentException("unsupported request stage");
        }
    }

    private static void requireRequestStage(AuthorizationTrace.Stage stage) {
        if (stage!=AuthorizationTrace.Stage.LOGIN_REQUEST && stage!=AuthorizationTrace.Stage.TOKEN_REFRESH
                && stage!=AuthorizationTrace.Stage.ENTITLEMENT_REQUEST && stage!=AuthorizationTrace.Stage.UPDATE_CHECK)
            throw new IllegalArgumentException("stage is not a request stage");
    }
}
