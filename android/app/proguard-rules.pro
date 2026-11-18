# flutter_local_notifications stores scheduled notifications with Gson and restores them on boot.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-dontwarn com.google.errorprone.annotations.**
# Flutter deferred components (not used) reference Play Core classes.
-dontwarn com.google.android.play.core.**
