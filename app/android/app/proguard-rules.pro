# ESP IoT release shrinking rules.
#
# Most dependencies ship their own consumer rules inside their AAR, so this file
# only covers the cases R8 cannot infer: entry points reached from the Android
# manifest, code reached over Flutter platform channels, and classes resolved
# reflectively from native code.

# Keep line numbers so a release stack trace stays readable, but drop the
# original source file names.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Flutter embedding entry points and the platform-channel bridges this app
# installs on them. MainActivity is reached from the manifest; the bridges are
# constructed by it and must keep their channel-handler methods.
-keep class com.samir.esp_iot.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Flutter's deferred-components manager compiles against Play Core, which this
# app does not bundle because it ships no deferred components. The class is
# never loaded, so the dangling references are safe to ignore.
-dontwarn com.google.android.play.core.**

# dart:ffi / package:jni resolve these from native code, so reflection-based
# lookups must survive shrinking. Used here through flutter_secure_storage.
-keep class com.github.dart_lang.jni.** { *; }
-keepclasseswithmembers class * {
    native <methods>;
}

# ML Kit barcode scanning, used by mobile_scanner. The bundled model classes are
# loaded dynamically and the optional unbundled path may be absent.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# CameraX configuration providers are named in the merged manifest as strings.
-keep class androidx.camera.camera2.Camera2Config { *; }
-keep class androidx.camera.core.impl.MetadataHolderService { *; }

# sqflite opens the database through reflection-free JNI but its result objects
# cross the channel boundary as plain maps; keep the plugin surface intact.
-keep class com.tekartik.sqflite.** { *; }

# androidx.security.crypto and the Tink backend behind flutter_secure_storage.
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# Kotlin coroutines internals referenced only from the service loader.
-dontwarn kotlinx.coroutines.**
-keep class kotlinx.coroutines.android.AndroidDispatcherFactory { *; }

# Strip Android log calls that could echo endpoint addresses or tokens into
# logcat on a release build.
-assumenosideeffects class android.util.Log {
    public static *** v(...);
    public static *** d(...);
    public static *** i(...);
}
