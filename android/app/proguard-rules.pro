# Jitsi Meet Flutter SDK
-keep class org.webrtc.** { *; }
-dontwarn org.chromium.build.BuildHooksAndroid
-keep class org.jitsi.meet.** { *; }
-keep class org.jitsi.meet.sdk.** { *; }

# React Native (used by Jitsi Android SDK)
-keep,allowobfuscation @interface com.facebook.proguard.annotations.DoNotStrip
-keep,allowobfuscation @interface com.facebook.proguard.annotations.KeepGettersAndSetters
-keep @com.facebook.proguard.annotations.DoNotStrip class *
-keepclassmembers class * {
 @com.facebook.proguard.annotations.DoNotStrip *;
}
-keep class * implements com.facebook.react.bridge.JavaScriptModule { *; }
-keep class * implements com.facebook.react.bridge.NativeModule { *; }
-keepclassmembers,includedescriptorclasses class * { native <methods>; }
-dontwarn com.facebook.react.**
-keep,includedescriptorclasses class com.facebook.react.bridge.** { *; }
-keep class com.facebook.jni.** { *; }
-keep,allowobfuscation @interface com.facebook.yoga.annotations.DoNotStrip
-keep @com.facebook.yoga.annotations.DoNotStrip class *
-keepclassmembers class * {
 @com.facebook.yoga.annotations.DoNotStrip *;
}
-keep public class com.horcrux.svg.** {*;}
-dontwarn okio.**

# flutter_callkit_incoming
-keep class com.hiennv.flutter_callkit_incoming.** { *; }
