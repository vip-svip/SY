import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("org.jetbrains.kotlin.multiplatform")
}

val upstreamSelector = rootProject.file("../vendor/GKD-XA/gkd-selector")

kotlin {
    explicitApi()
    jvm {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }
    sourceSets {
        commonMain {
            kotlin.srcDir(upstreamSelector.resolve("src/commonMain/kotlin"))
            dependencies { implementation(kotlin("stdlib")) }
        }
        jvmMain {
            kotlin.srcDir(upstreamSelector.resolve("src/jvmMain/kotlin"))
        }
        jvmTest {
            dependencies { implementation(kotlin("test")) }
        }
    }
}
