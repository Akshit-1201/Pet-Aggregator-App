# R8 keep rules for the release build. Firebase, Google Play services and
# AndroidX ship their own consumer rules; these cover what they don't.

# --- Razorpay (from Razorpay's Android integration guide) -------------------
# Checkout runs in a WebView that calls back into Java through
# @JavascriptInterface methods and reflection; stripping or renaming them
# breaks payment callbacks in release builds only.
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keepattributes JavascriptInterface
-keepattributes *Annotation*
-dontwarn com.razorpay.**
-keep class com.razorpay.** { *; }
-optimizations !method/inlining/*
-keepclasseswithmembers class * {
    public void onPayment*(...);
}

# --- Google Sign-In via Credential Manager ----------------------------------
# The Play-services credential provider is found by reflection.
-if class androidx.credentials.CredentialManager
-keep class androidx.credentials.playservices.** { *; }

# --- Flutter ------------------------------------------------------------------
# Flutter's embedding references Play Core (deferred components) optionally;
# the app doesn't use it, so the missing classes are expected.
-dontwarn com.google.android.play.core.**
