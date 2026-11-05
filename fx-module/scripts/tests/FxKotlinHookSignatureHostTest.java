package de.privacyguard.adhook;

/** JDK-only regression for Kotlin source/Frida signature erasure. */
public final class FxKotlinHookSignatureHostTest {
    private static void expect(String input, String expected) {
        String actual = DeveloperExecutableDescriptor.fromJavaSignature(input, "com.example.app");
        if (!expected.equals(actual)) throw new AssertionError(input + " expected " + expected + " but got " + actual);
    }
    private static void reject(String input) {
        if (DeveloperExecutableDescriptor.fromJavaSignature(input, "com.example.app") != null)
            throw new AssertionError("unexpectedly accepted: " + input);
    }
    public static void main(String[] args) {
        expect("com.example.app.Auth#isReady(kotlin.String): kotlin.Boolean",
                "Lcom/example/app/Auth;->isReady(Ljava/lang/String;)Z");
        expect("com.example.app.Auth#finish(): kotlin.Unit",
                "Lcom/example/app/Auth;->finish()V");
        expect("com.example.app.Auth#copy(kotlin.IntArray): kotlin.ByteArray",
                "Lcom/example/app/Auth;->copy([I)[B");
        expect("com.example.app.Auth#load(kotlin.collections.List): kotlin.collections.Map",
                "Lcom/example/app/Auth;->load(Ljava/util/List;)Ljava/util/Map;");
        expect("com.example.app.Auth.isReady.overload('kotlin.String') -> kotlin.Boolean",
                "Lcom/example/app/Auth;->isReady(Ljava/lang/String;)Z");
        expect("com.example.app.Auth#copy(kotlin.BooleanArray): kotlin.BooleanArray",
                "Lcom/example/app/Auth;->copy([Z)[Z");
        expect("com.example.app.Auth#items(kotlin.collections.MutableList): kotlin.collections.Set",
                "Lcom/example/app/Auth;->items(Ljava/util/List;)Ljava/util/Set;");
        expect("com.example.app.Auth#echo(kotlin.Any): kotlin.Any",
                "Lcom/example/app/Auth;->echo(Ljava/lang/Object;)Ljava/lang/Object;");
        reject("com.example.app.Auth#finish(kotlin.Unit): kotlin.Boolean");
        reject("com.example.app.Auth#load(kotlin.collections.List<kotlin.String>): kotlin.Any");
        System.out.println("PASS: Kotlin source and Frida signatures resolve to exact erased JVM descriptors");
    }
}
