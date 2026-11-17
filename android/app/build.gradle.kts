plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "org.vifast.visdroid"
    compileSdk = flutter.compileSdkVersion
    // Pin NDK 27 — engine libvis_ffi.so đã biên dịch sẵn (native/build-so.sh).
    ndkVersion = "27.0.12077973"
    // NDK 27 dùng để cross-compile libvis_ffi.so (native/build-so.sh).

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "org.vifast.visdroid"
        // VisDroid hỗ trợ Android 7.1.1 trở lên (API 25).
        minSdk = 25
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs {
            // libvis_ffi.so đã strip sẵn lúc build engine (native/build-so.sh) —
            // không cần AGP strip/extract lại (NDK trên máy chỉ là stub).
            keepDebugSymbols.add("**/*.so")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
