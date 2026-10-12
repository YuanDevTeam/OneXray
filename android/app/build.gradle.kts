import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("org.jetbrains.kotlin.plugin.serialization")
}

// Optional upload-signing config. The keystore directory is gitignored, so
// fresh clones won't have this file — in that case we fall back to the default
// debug keystore so `./gradlew assembleDebug` / `flutter run` works out of the
// box without any signing setup.
val keystoreFile = rootProject.file("keystore/keystore.properties")
val keystoreProperties: Properties? = if (keystoreFile.exists()) {
    Properties().apply { keystoreFile.inputStream().use { load(it) } }
} else {
    null
}
val splitPerAbi = providers.gradleProperty("split-per-abi").orNull?.toBoolean() == true

android {
    namespace = "net.yuandev.onexray"
    compileSdk = 37
    ndkVersion = "30.0.16248370"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "net.yuandev.onexray"
        minSdk = 29
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        if (!splitPerAbi) {
            ndk {
                abiFilters.clear()
                abiFilters += listOf("arm64-v8a", "x86_64")
            }
        }
    }

    if (splitPerAbi) {
        splits {
            abi {
                reset()
                isEnable = true
                isUniversalApk = false
                include("arm64-v8a", "x86_64")
            }
        }
    }

    signingConfigs {
        keystoreProperties?.let { props ->
            create("upload") {
                keyAlias = props["keyAlias"] as String
                keyPassword = props["keyPassword"] as String
                storeFile = file(props["storeFile"] as String)
                storePassword = props["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Real releases use the upload key when keystore/keystore.properties is
            // present. Without it, fall back to the debug keystore so a contributor
            // can still run `./gradlew assembleRelease` locally — the resulting APK
            // is debug-signed and can be installed on a test device but cannot be
            // published to Play Store.
            signingConfig = signingConfigs.findByName("upload")
                ?: signingConfigs.getByName("debug")
        }
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Resource-backed JVM tests also package the assets written by Flutter.
tasks.matching { it.name.startsWith("package") && it.name.endsWith("UnitTestForUnitTest") }
    .configureEach {
        val variant = name.removePrefix("package").removeSuffix("UnitTestForUnitTest")
        dependsOn("copyFlutterAssets$variant")
    }

dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.17")
    val coreVersion = "1.19.0"
    implementation("androidx.core:core-ktx:$coreVersion")
    implementation("androidx.core:core-splashscreen:1.2.0")

    implementation("androidx.fragment:fragment-ktx:1.9.0")
    implementation("androidx.activity:activity-ktx:1.13.0")

    val kotlinxCoroutinesVersion = "1.11.0"
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:$kotlinxCoroutinesVersion")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:$kotlinxCoroutinesVersion")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:$kotlinxCoroutinesVersion")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:$kotlinxCoroutinesVersion")

    implementation("com.github.getActivity:XXPermissions:21.3")
    implementation("com.elvishew:xlog:1.11.1")

    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.jar", "*.aar"))))
}
