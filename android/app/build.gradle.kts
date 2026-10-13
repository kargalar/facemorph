import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.facemorph"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    fun environmentValue(name: String): String? =
        providers.environmentVariable(name).orNull

    val signingProperties = Properties()
    val propertiesFile = rootProject.file("key.properties")
    if (propertiesFile.exists()) {
        propertiesFile.inputStream().use { signingProperties.load(it) }
    }

    fun signingValue(propertyName: String, environmentName: String): String? =
        signingProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }
            ?: environmentValue(environmentName)

    val releaseKeystorePath = signingValue("storeFile", "KARGALAR_KEYSTORE_PATH")
    val releaseKeystorePassword = signingValue(
        "storePassword",
        "KARGALAR_KEYSTORE_PASSWORD",
    )
    val releaseKeyAlias = signingValue("keyAlias", "KARGALAR_KEY_ALIAS")
    val releaseKeyPassword = signingValue("keyPassword", "KARGALAR_KEY_PASSWORD")
    val hasReleaseSigning = listOf(
        releaseKeystorePath,
        releaseKeystorePassword,
        releaseKeyAlias,
        releaseKeyPassword,
    ).all { !it.isNullOrBlank() }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseKeystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.facemorph"
        minSdk = flutter.minSdkVersion
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            check(hasReleaseSigning) {
                "Debug signing is not configured. Provide key.properties or " +
                    "KARGALAR_KEYSTORE_* environment variables."
            }
            signingConfig = signingConfigs.getByName("release")
        }
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }

    val verifyReleaseSigning = tasks.register("verifyReleaseSigning") {
        doLast {
            check(hasReleaseSigning) {
                "Release signing is not configured. Provide key.properties or " +
                    "KARGALAR_KEYSTORE_* environment variables."
            }
            check(file(releaseKeystorePath!!).isFile) {
                "Release keystore was not found: $releaseKeystorePath"
            }
        }
    }
    tasks.configureEach {
        if (
            name == "assembleDebug" ||
            name == "bundleRelease" ||
            name == "assembleRelease"
        ) {
            dependsOn(verifyReleaseSigning)
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
