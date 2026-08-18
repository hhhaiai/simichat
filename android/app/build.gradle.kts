plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "top.simitalk.aichat"
    compileSdk = flutter.compileSdkVersion
    // NDK r28 defaults to 16 KB ELF segment alignment for newly linked
    // native libraries. Keep this explicit so the Android bridge is built
    // with the same toolchain on every developer and release machine.
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "top.simitalk.aichat"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // The checked-in nodejs-mobile runtime currently has one verified ABI.
        // Do not add an ABI here until its libnode.so, bridge, libc++_shared.so,
        // page-size audit, and device smoke have all passed.
        ndk {
            abiFilters += "arm64-v8a"
        }

        externalNativeBuild {
            cmake {
                arguments += "-DANDROID_STL=c++_shared"
                cppFlags += listOf("-std=c++17", "-fexceptions", "-frtti")
            }
        }
    }

    // 真机 integration runner 不得替换已安装的正式应用。
    // 所有 Android 真机 smoke 都使用显式 flavor，避免依赖无 flavor variant。
    flavorDimensions += "smoke"
    productFlavors {
        create("production") {
            dimension = "smoke"
            applicationId = "top.simitalk.aichat"
            providers.gradleProperty("simichatApplicationId").orNull?.let {
                applicationId = it
            }
        }
        create("modelswitch") {
            dimension = "smoke"
            applicationId = "top.simitalk.aichat.modelswitch"
        }
        create("realtimepcm") {
            dimension = "smoke"
            applicationId = "top.simitalk.aichat.realtimepcm"
        }
    }

    applicationVariants.all {
        if (flavorName == "production" && buildType.name == "release") {
            check(applicationId == "top.simitalk.aichat") {
                "productionRelease must keep applicationId=top.simitalk.aichat"
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            // The production APK must carry release application flags even while
            // this repository still uses the debug keystore for local installs.
            isDebuggable = false
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
