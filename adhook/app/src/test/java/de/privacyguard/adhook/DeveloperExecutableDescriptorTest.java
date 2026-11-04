package de.privacyguard.adhook;

import org.junit.Test;
import static org.junit.Assert.*;

public class DeveloperExecutableDescriptorTest {
    @Test public void parsesMethodWithObjectAndArrayArguments() {
        DeveloperExecutableDescriptor d=DeveloperExecutableDescriptor.parse(
            "Lcom/example/app/Foo;->run(Ljava/lang/String;[I)Ljava/lang/Object;","com.example.app");
        assertNotNull(d); assertEquals("run",d.name); assertEquals(2,d.parameterDescriptors.size());
    }
    @Test public void parsesConstructor() {
        DeveloperExecutableDescriptor d=DeveloperExecutableDescriptor.parse(
            "Lcom/example/app/Foo;-><init>(I)V","com.example.app");
        assertNotNull(d); assertEquals("<init>",d.name);
    }
    @Test public void parsesJavaSignatureWithColonReturnSeparator() {
        String descriptor = DeveloperExecutableDescriptor.fromJavaSignature(
            "com.example.app.Foo#run(java.lang.String, int[]): java.lang.Object", "com.example.app");
        assertEquals("Lcom/example/app/Foo;->run(Ljava/lang/String;[I)Ljava/lang/Object;", descriptor);
    }
    @Test public void parsesFridaOverloadWithQuotedTypesAndExplicitReturn() {
        String descriptor = DeveloperExecutableDescriptor.fromJavaSignature(
            "com.example.app.Auth.isReady.overload('java.lang.String', 'int[]') -> boolean",
            "com.example.app");
        assertEquals("Lcom/example/app/Auth;->isReady(Ljava/lang/String;[I)Z", descriptor);
    }
    @Test public void parsesFridaNoArgOverloadWithReturnsKeyword() {
        String descriptor = DeveloperExecutableDescriptor.fromJavaSignature(
            "com.example.app.Auth.isReady.overload() returns boolean", "com.example.app");
        assertEquals("Lcom/example/app/Auth;->isReady()Z", descriptor);
    }
    @Test public void rejectsFridaOverloadWithoutExplicitReturnType() {
        assertNull(DeveloperExecutableDescriptor.fromJavaSignature(
            "com.example.app.Auth.isReady.overload('java.lang.String')", "com.example.app"));
    }
    @Test public void rejectsFridaOverloadOutsideSelectedPackage() {
        assertNull(DeveloperExecutableDescriptor.fromJavaSignature(
            "com.other.Auth.isReady.overload() -> boolean", "com.example.app"));
    }
    @Test public void rejectsFridaOverloadWithMalformedQuotedType() {
        assertNull(DeveloperExecutableDescriptor.fromJavaSignature(
            "com.example.app.Auth.isReady.overload('java.lang.String, int') -> boolean",
            "com.example.app"));
    }

    @Test public void rejectsInvalidAndOutOfScopeDescriptors() {
        assertNull(DeveloperExecutableDescriptor.parse("Lcom/other/Foo;->x()V","com.example.app"));
        assertNull(DeveloperExecutableDescriptor.parse("Lcom/example/app/Foo;->x(V)V","com.example.app"));
        assertNull(DeveloperExecutableDescriptor.parse("Lcom/example/app/Foo;-><init>()I","com.example.app"));
        assertNull(DeveloperExecutableDescriptor.parse("Lcom/example/app/Foo;->x(Ljava/lang/String)V","com.example.app"));
    }
    @Test public void supportsPrimitiveAndVoidReturns() {
        assertNotNull(DeveloperExecutableDescriptor.parse("Lcom/example/app/Foo;->enabled()Z","com.example.app"));
        assertNotNull(DeveloperExecutableDescriptor.parse("Lcom/example/app/Foo;->refresh()V","com.example.app"));
    }
}