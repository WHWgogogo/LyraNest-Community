plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath = providers.environmentVariable("HARMONY_ANDROID_KEYSTORE_PATH").orNull
val releaseStorePassword = providers.environmentVariable("HARMONY_ANDROID_KEYSTORE_PASSWORD").orNull
val releaseKeyAlias = providers.environmentVariable("HARMONY_ANDROID_KEY_ALIAS").orNull
val releaseKeyPassword = providers.environmentVariable("HARMONY_ANDROID_KEY_PASSWORD").orNull
val releaseSigningValues = listOf(
    releaseKeystorePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
)
val releaseSigningConfigured = releaseSigningValues.all { !it.isNullOrBlank() }

require(releaseSigningConfigured || releaseSigningValues.all { it.isNullOrBlank() }) {
    "Configure all HARMONY_ANDROID_KEYSTORE_PATH, HARMONY_ANDROID_KEYSTORE_PASSWORD, " +
        "HARMONY_ANDROID_KEY_ALIAS, and HARMONY_ANDROID_KEY_PASSWORD, or configure none for test signing."
}

configurations.configureEach {
    exclude(group = "io.flutter", module = "armeabi_v7a_release")
    exclude(group = "io.flutter", module = "x86_release")
    exclude(group = "io.flutter", module = "x86_64_release")
}

android {
    namespace = "com.lyranest.community.player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.lyranest.community.player"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = 101
        versionName = flutter.versionName
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    packaging {
        jniLibs {
            excludes += setOf(
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                "lib/x86_64/**",
            )
        }
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("externalRelease") {
                storeFile = file(requireNotNull(releaseKeystorePath))
                storePassword = requireNotNull(releaseStorePassword)
                keyAlias = requireNotNull(releaseKeyAlias)
                keyPassword = requireNotNull(releaseKeyPassword)
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseSigningConfigured) {
                signingConfigs.getByName("externalRelease")
            } else {
                signingConfigs.getByName("debug")
            }
        }
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

dependencies {
    testImplementation("junit:junit:4.13.2")
}
