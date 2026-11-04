package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class DeveloperHookRuleTest {
    @Test public void acceptsJavaDescriptorSyntax() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "vip|com.example.vpn.auth.AuthState#isVip()Z|RETURN_TRUE|100",
                "com.example.vpn");
        assertNotNull(rule);
        assertEquals("com.example.vpn.auth.AuthState#isVip()Z", rule.descriptor);
        assertTrue(rule.replacement);
        assertEquals(100, rule.priority);
    }

    @Test public void acceptsJvmArrowSyntax() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "login|Lcom/example/vpn/auth/Session;->isLoggedIn()Z|true|50",
                "com.example.vpn");
        assertNotNull(rule);
        assertEquals("Lcom/example/vpn/auth/Session;->isLoggedIn()Z", rule.descriptor);
    }

    @Test public void acceptsTypedJvmMethodForReadOnlyObservation() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "trace|Lcom/example/vpn/Trace;->dispatch(Ljava/lang/String;[I)Ljava/lang/Object;|OBSERVE|20",
                "com.example.vpn");
        assertNotNull(rule);
        assertEquals(DeveloperHookRule.Action.OBSERVE, rule.action);
        assertEquals("Lcom/example/vpn/Trace;->dispatch(Ljava/lang/String;[I)Ljava/lang/Object;", rule.descriptor);
    }

    @Test public void acceptsConstructorDescriptorForMetadataResolution() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "construct|Lcom/example/vpn/Trace;-><init>(I)V|OBSERVE|1",
                "com.example.vpn");
        assertNotNull(rule);
        assertEquals(DeveloperHookRule.Action.OBSERVE, rule.action);
    }

    @Test public void acceptsJavaSourceSignatureWithTypedArgumentsAndObjectReturn() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "trace|com.example.vpn.Trace#dispatch(java.lang.String,int[])java.lang.Object|OBSERVE|25",
                "com.example.vpn");
        assertNotNull(rule);
        assertEquals("Lcom/example/vpn/Trace;->dispatch(Ljava/lang/String;[I)Ljava/lang/Object;", rule.descriptor);
    }

    @Test public void acceptsJavaSourceSignatureWithPrimitiveAndArrayReturn() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "trace|com.example.vpn.Trace#copy(byte[],boolean)byte[]|OBSERVE|25",
                "com.example.vpn");
        assertNotNull(rule);
        assertEquals("Lcom/example/vpn/Trace;->copy([BZ)[B", rule.descriptor);
    }

    @Test public void sourceParserDoesNotConfuseJvmBooleanCodeWithClassName() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "legacy|com.example.vpn.AuthState#isVip()Z|RETURN_TRUE|1",
                "com.example.vpn");
        assertNotNull(rule);
        assertEquals("com.example.vpn.AuthState#isVip()Z", rule.descriptor);
    }

    @Test public void resolvesCommonJavaLangSimpleNames() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "trace|com.example.vpn.Trace#dispatch(String)Object|OBSERVE|1",
                "com.example.vpn");
        assertNotNull(rule);
        assertEquals("Lcom/example/vpn/Trace;->dispatch(Ljava/lang/String;)Ljava/lang/Object;", rule.descriptor);
    }

    @Test public void rejectsGenericJavaSourceSignatureWithoutErasure() {
        assertNull(DeveloperHookRule.parse(
                "trace|com.example.vpn.Trace#dispatch(java.util.List<java.lang.String>)java.lang.Object|OBSERVE|25",
                "com.example.vpn"));
    }

    @Test public void acceptsFridaOverloadAndColonReturnSyntaxForObserve() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "trace|com.example.vpn.Trace.dispatch.overload('java.lang.String', 'int[]') -> java.lang.Object|OBSERVE|25",
                "com.example.vpn");
        assertNotNull(rule);
        assertEquals("Lcom/example/vpn/Trace;->dispatch(Ljava/lang/String;[I)Ljava/lang/Object;", rule.descriptor);
        assertEquals(DeveloperHookRule.Action.OBSERVE, rule.action);
    }

    @Test public void acceptsJavaColonReturnSyntaxForNoOpVoid() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "stop|com.example.vpn.Worker#refresh(java.lang.String): void|NO_OP_VOID|5",
                "com.example.vpn");
        assertNotNull(rule);
        assertEquals("Lcom/example/vpn/Worker;->refresh(Ljava/lang/String;)V", rule.descriptor);
    }

    @Test public void acceptsDottedSyntaxAndFalseAction() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "update|com.example.vpn.update.UpdatePolicy.shouldShowUpdate()Z|false|10",
                "com.example.vpn");
        assertNotNull(rule);
        assertFalse(rule.replacement);
        assertEquals("com.example.vpn.update.UpdatePolicy#shouldShowUpdate()Z", rule.descriptor);
    }

    @Test public void supportsObserveAndDisabledActions() {
        DeveloperHookRule observe = DeveloperHookRule.parse(
                "trace|com.example.vpn.Trace#isEnabled()Z|OBSERVE_ONLY|0", "com.example.vpn");
        DeveloperHookRule disabled = DeveloperHookRule.parse(
                "off|com.example.vpn.Trace#isEnabled()Z|DISABLED|-1", "com.example.vpn");
        assertNotNull(observe);
        assertEquals(DeveloperHookRule.Action.OBSERVE, observe.action);
        assertNotNull(disabled);
        assertEquals(DeveloperHookRule.Action.DISABLED, disabled.action);
    }

    @Test public void disabledRuleDoesNotShadowLowerPriorityActiveRule() {
        DeveloperHookRule low = DeveloperHookRule.parse(
                "observe|com.example.vpn.Trace#isEnabled()Z|OBSERVE|1", "com.example.vpn");
        DeveloperHookRule off = DeveloperHookRule.parse(
                "off|com.example.vpn.Trace#isEnabled()Z|DISABLED|10", "com.example.vpn");
        java.util.List<DeveloperHookRule> selected =
                DeveloperHookRule.selectEffective(java.util.Arrays.asList(low, off));
        assertEquals(1, selected.size());
        assertEquals("observe", selected.get(0).id);
    }

    @Test public void lowerPriorityRuleDoesNotOverrideHigherPriorityRule() {
        DeveloperHookRule low = DeveloperHookRule.parse(
                "low|com.example.vpn.Trace#isEnabled()Z|OBSERVE|1", "com.example.vpn");
        DeveloperHookRule high = DeveloperHookRule.parse(
                "high|com.example.vpn.Trace#isEnabled()Z|OBSERVE|10", "com.example.vpn");
        java.util.List<DeveloperHookRule> selected =
                DeveloperHookRule.selectEffective(java.util.Arrays.asList(low, high));
        assertEquals(1, selected.size());
        assertEquals("high", selected.get(0).id);
    }

    @Test public void acceptsNoOpOnlyForExactVoidMethods() {
        DeveloperHookRule noArg = DeveloperHookRule.parse(
                "stop|Lcom/example/vpn/Worker;->refresh()V|NO_OP_VOID|25", "com.example.vpn");
        DeveloperHookRule withArgs = DeveloperHookRule.parse(
                "stopArgs|Lcom/example/vpn/Worker;->refresh(Ljava/lang/String;I)V|DO_NOTHING|10", "com.example.vpn");
        DeveloperHookRule javaSource = DeveloperHookRule.parse(
                "stopJava|com.example.vpn.Worker#refresh(java.lang.String)void|NO_OP_VOID|5", "com.example.vpn");
        assertNotNull(noArg);
        assertNotNull(withArgs);
        assertNotNull(javaSource);
        // replacement is a legacy boolean compatibility flag, not the action selector.
        // NO_OP_VOID executes through Action and must never masquerade as RETURN_TRUE.
        assertFalse(noArg.replacement);
        assertFalse(withArgs.replacement);
        assertFalse(javaSource.replacement);
        assertEquals(DeveloperHookRule.Action.NO_OP_VOID, noArg.action);
        assertEquals(DeveloperHookRule.Action.NO_OP_VOID, withArgs.action);
        assertEquals("Lcom/example/vpn/Worker;->refresh(Ljava/lang/String;)V", javaSource.descriptor);
    }

    @Test public void rejectsNoOpForNonVoidConstructorsAndLegacyAmbiguousSignatures() {
        assertNull(DeveloperHookRule.parse("unsafe|Lcom/example/vpn/Worker;->refresh()Z|NO_OP_VOID|1", "com.example.vpn"));
        assertNull(DeveloperHookRule.parse("unsafe|Lcom/example/vpn/Worker;-><init>()V|NO_OP_VOID|1", "com.example.vpn"));
        assertNull(DeveloperHookRule.parse("unsafe|com.example.vpn.Worker#refresh()Z|NO_OP_VOID|1", "com.example.vpn"));
    }

    @Test public void acceptsDottedJavaSourceSignature() {
        DeveloperHookRule rule = DeveloperHookRule.parse(
                "trace|com.example.vpn.Trace.dispatch(String,int[])Object|OBSERVE|5",
                "com.example.vpn");
        assertNotNull(rule);
        assertEquals("Lcom/example/vpn/Trace;->dispatch(Ljava/lang/String;[I)Ljava/lang/Object;", rule.descriptor);
    }

    @Test public void rejectsReplacementForParameterizedMethod() {
        assertNull(DeveloperHookRule.parse(
                "unsafe|Lcom/example/vpn/Trace;->dispatch(I)Z|RETURN_TRUE|1",
                "com.example.vpn"));
    }

    @Test public void rejectsReplacementForConstructor() {
        assertNull(DeveloperHookRule.parse(
                "unsafe|Lcom/example/vpn/Trace;-><init>()V|RETURN_FALSE|1",
                "com.example.vpn"));
    }

    @Test public void keepsParameterizedObservationAvailable() {
        assertNotNull(DeveloperHookRule.parse(
                "trace|Lcom/example/vpn/Trace;->dispatch(I)Z|OBSERVE|1",
                "com.example.vpn"));
    }

    @Test public void rejectsOutOfPackageAndUnsupportedSignature() {
        assertNull(DeveloperHookRule.parse("x|com.other.App#isVip()Z|true|1", "com.example.vpn"));
        assertNull(DeveloperHookRule.parse("x|com.example.vpn.App#isVip(Ljava/lang/String;)Z|true|1", "com.example.vpn"));
        assertNull(DeveloperHookRule.parse("x|com.example.vpn.App#isVip()Z|network_bypass|1", "com.example.vpn"));
        assertNull(DeveloperHookRule.parse("x|com.example.vpn.App#isVip()Z|true|9999", "com.example.vpn"));
    }
    @Test public void rejectsMutationActionsWithAnExplicitReason() {
        assertTrue(DeveloperHookRule.isUnsupportedMutationAction("SET_FIELD"));
        assertTrue(DeveloperHookRule.isUnsupportedMutationAction("WRITE_PROPERTY"));
        assertTrue(DeveloperHookRule.isUnsupportedMutationAction("INVOKE_METHOD"));
        assertTrue(DeveloperHookRule.isUnsupportedMutationAction("MUTATE_STATE"));
        assertFalse(DeveloperHookRule.isUnsupportedMutationAction("OBSERVE"));
        assertFalse(DeveloperHookRule.isUnsupportedMutationAction("RETURN_TRUE"));
        assertFalse(DeveloperHookRule.isUnsupportedMutationAction("NO_OP_VOID"));
        assertTrue(DeveloperHookRule.UNSUPPORTED_MUTATION_ACTION_MESSAGE
                .contains("mutation actions are not supported"));
    }


    @Test public void acceptsReturnFirstArgumentOnlyForExactMatchingTypes() {
        DeveloperHookRule valid = DeveloperHookRule.parse(
                "echo|Lcom/example/vpn/Echo;->echo(Ljava/lang/String;)Ljava/lang/String;|RETURN_ARGUMENT_0|5",
                "com.example.vpn");
        assertNotNull(valid);
        assertEquals(DeveloperHookRule.Action.RETURN_ARGUMENT_0, valid.action);
        assertNull(DeveloperHookRule.parse(
                "bad|Lcom/example/vpn/Echo;->echo(Ljava/lang/Object;)Ljava/lang/String;|RETURN_ARGUMENT_0|5",
                "com.example.vpn"));
        assertNull(DeveloperHookRule.parse(
                "bad|Lcom/example/vpn/Echo;->echo()Ljava/lang/String;|RETURN_ARGUMENT_0|5",
                "com.example.vpn"));
        assertNull(DeveloperHookRule.parse(
                "bad|com.example.vpn.Echo#echo()Z|RETURN_ARGUMENT_0|5",
                "com.example.vpn"));
    }

    @Test public void acceptsReturnThisOnlyForObjectReturningMethods() {
        DeveloperHookRule valid = DeveloperHookRule.parse(
                "self|Lcom/example/vpn/Builder;->self()Lcom/example/vpn/Builder;|RETURN_THIS|5",
                "com.example.vpn");
        assertNotNull(valid);
        assertEquals(DeveloperHookRule.Action.RETURN_THIS, valid.action);
        assertNull(DeveloperHookRule.parse(
                "bad|Lcom/example/vpn/Builder;->count()I|RETURN_THIS|5",
                "com.example.vpn"));
        assertNull(DeveloperHookRule.parse(
                "bad|Lcom/example/vpn/Builder;->items()[Ljava/lang/Object;|RETURN_THIS|5",
                "com.example.vpn"));
    }

    @Test public void acceptsTypedLiteralForSupportedReturnTypes() {
        DeveloperHookRule stringRule = DeveloperHookRule.parse(
                "label|Lcom/example/vpn/DebugState;->label()Ljava/lang/String;|RETURN_LITERAL|10|build-preview",
                "com.example.vpn");
        DeveloperHookRule intRule = DeveloperHookRule.parse(
                "code|Lcom/example/vpn/DebugState;->code()I|RETURN_LITERAL|10|37",
                "com.example.vpn");
        DeveloperHookRule booleanRule = DeveloperHookRule.parse(
                "ready|Lcom/example/vpn/DebugState;->ready()Z|RETURN_LITERAL|10|true",
                "com.example.vpn");
        DeveloperHookRule charRule = DeveloperHookRule.parse(
                "marker|Lcom/example/vpn/DebugState;->marker()C|RETURN_LITERAL|10|65535",
                "com.example.vpn");
        DeveloperHookRule floatRule = DeveloperHookRule.parse(
                "ratio|Lcom/example/vpn/DebugState;->ratio()F|RETURN_LITERAL|10|0.75",
                "com.example.vpn");
        assertNotNull(stringRule);
        assertNotNull(intRule);
        assertNotNull(booleanRule);
        assertNotNull(charRule);
        assertNotNull(floatRule);
        assertEquals("build-preview", stringRule.literalValue);
        assertEquals(Integer.valueOf(37), DeveloperHookRule.parseLiteralValue("I", intRule.literalValue));
        assertEquals(Boolean.TRUE, DeveloperHookRule.parseLiteralValue("Z", booleanRule.literalValue));
        assertEquals(Character.valueOf((char) 65535), DeveloperHookRule.parseLiteralValue("C", charRule.literalValue));
        assertEquals(Float.valueOf(0.75f), DeveloperHookRule.parseLiteralValue("F", floatRule.literalValue));
        assertTrue(stringRule.toEncodedString().endsWith("|build-preview"));
    }

    @Test public void rejectsUnsafeLiteralReturnTypesAndOutOfRangeValues() {
        assertNull(DeveloperHookRule.parse(
                "object|Lcom/example/vpn/DebugState;->object()Ljava/lang/Object;|RETURN_LITERAL|1|anything",
                "com.example.vpn"));
        assertNull(DeveloperHookRule.parse(
                "array|Lcom/example/vpn/DebugState;->items()[I|RETURN_LITERAL|1|1",
                "com.example.vpn"));
        assertNull(DeveloperHookRule.parse(
                "byte|Lcom/example/vpn/DebugState;->small()B|RETURN_LITERAL|1|128",
                "com.example.vpn"));
        assertNull(DeveloperHookRule.parse(
                "char|Lcom/example/vpn/DebugState;->marker()C|RETURN_LITERAL|1|65536",
                "com.example.vpn"));
        assertNull(DeveloperHookRule.parse(
                "bool|Lcom/example/vpn/DebugState;->ready()Z|RETURN_LITERAL|1|yes",
                "com.example.vpn"));
        assertNull(DeveloperHookRule.parse(
                "float|Lcom/example/vpn/DebugState;->ratio()F|RETURN_LITERAL|1|NaN",
                "com.example.vpn"));
        assertNull(DeveloperHookRule.parse(
                "string|Lcom/example/vpn/DebugState;->label()Ljava/lang/String;|RETURN_LITERAL|1|bad\\nvalue",
                "com.example.vpn"));
    }

    @Test public void pausedLiteralRuleKeepsItsValueAndRemainsInert() {
        DeveloperHookRule paused = DeveloperHookRule.parse(
                "literal|Lcom/example/vpn/DebugState;->code()I|OFF|10|42",
                "com.example.vpn");
        assertNotNull(paused);
        assertEquals(DeveloperHookRule.Action.DISABLED, paused.action);
        assertEquals("42", paused.literalValue);
        assertTrue(paused.toEncodedString().endsWith("|42"));
        assertEquals(0, DeveloperHookRule.selectEffective(java.util.Collections.singletonList(paused)).size());
    }

    @Test public void passthroughActionsAreNotClassifiedAsMutationCommands() {
        assertFalse(DeveloperHookRule.isUnsupportedMutationAction("RETURN_ARGUMENT_0"));
        assertFalse(DeveloperHookRule.isUnsupportedMutationAction("RETURN_ARG0"));
        assertFalse(DeveloperHookRule.isUnsupportedMutationAction("RETURN_THIS"));
    }

}
