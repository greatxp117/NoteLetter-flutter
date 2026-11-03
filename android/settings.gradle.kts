pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // Flutter 3.47 (the eMudhra-patched Dart, see pubspec.yaml) refuses AGP
    // below 8.11.1 and Gradle below 8.14. The newest 8.x: AGP 9 is its own
    // move, once every plugin here is known to build on it.
    id("com.android.application") version "8.13.2" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.4.4") apply false
    // END: FlutterFire Configuration
    // Flutter 3.47 refuses KGP below 2.2.20, and the Firebase Android SDK the
    // patched FlutterFire set pulls ships Kotlin 2.3 metadata.
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
