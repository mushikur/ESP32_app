import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is read from android/key.properties when present, otherwise from
// ESP_IOT_RELEASE_* environment variables. Both sources stay outside version control.
// All four values must be supplied together or the release stays unsigned.
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties().apply {
    if (keyPropertiesFile.isFile) keyPropertiesFile.inputStream().use { load(it) }
}

fun signingValue(propertyName: String, environmentName: String): String? =
    (keyProperties.getProperty(propertyName) ?: providers.environmentVariable(environmentName).orNull)
        ?.takeIf { it.isNotBlank() }

val releaseKeystore = signingValue("storeFile", "ESP_IOT_RELEASE_KEYSTORE")
val releaseStorePassword = signingValue("storePassword", "ESP_IOT_RELEASE_STORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "ESP_IOT_RELEASE_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "ESP_IOT_RELEASE_KEY_PASSWORD")
val releaseSigningValues =
    listOf(releaseKeystore, releaseStorePassword, releaseKeyAlias, releaseKeyPassword)
val releaseSigningConfigured = releaseSigningValues.any { it != null }
if (releaseSigningConfigured) {
    require(releaseSigningValues.all { it != null }) {
        "Set all four release signing values in android/key.properties or the ESP_IOT_RELEASE_* environment variables."
    }
}

android {
    namespace = "com.samir.esp_iot"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Public package identifier. Android upgrades also require a matching signer.
        applicationId = "com.samir.esp_iot"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Keep every density and locale the bundled assets and launcher icons need.
        resourceConfigurations += listOf("en", "bn")
    }

    if (releaseSigningConfigured) {
        signingConfigs.create("distribution") {
            storeFile = file(releaseKeystore!!)
            require(storeFile?.isFile == true) {
                "The release keystore was not found at the configured path."
            }
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
        }
    }

    buildTypes {
        getByName("debug") {
            applicationIdSuffix = ".debug"
        }
        getByName("release") {
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("distribution")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        resources.excludes += setOf(
            "META-INF/*.kotlin_module",
            "META-INF/DEPENDENCIES",
            "META-INF/LICENSE*",
            "META-INF/NOTICE*",
            "**/kotlin/**",
            "DebugProbesKt.bin",
        )
    }

    dependenciesInfo {
        // Keep the dependency blob out of the shared APK; Play still receives it in the bundle.
        includeInApk = false
        includeInBundle = true
    }

    lint {
        checkReleaseBuilds = true
        abortOnError = true
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
