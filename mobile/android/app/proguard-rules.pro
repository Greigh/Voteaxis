# R8 keeps for this app's release build.
#
# The Flutter Gradle plugin contributes its own engine rules; these cover the
# plugins that reach Dart through reflection or a platform channel R8 cannot
# see being used.

# home_widget's background receiver is named in AndroidManifest.xml and
# instantiated by the system, never referenced from Kotlin.
-keep class es.antonborri.home_widget.** { *; }

# The widget provider is named in the manifest and in widget_bridge.dart.
-keep class com.greighstudios.voteaxis.IssueWidgetProvider { *; }

# mobile_scanner binds ML Kit's barcode models dynamically. The library ships
# its own consumer rules; this is the documented extra keep for the optional
# model classes R8 otherwise strips.
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# flutter_secure_storage. This version wraps values with its own RSA/AES keys
# in the Android Keystore rather than EncryptedSharedPreferences, so the keep
# is on the plugin package itself — androidx.security.crypto is not in the APK
# at all, and a keep rule naming it would only look like coverage.
-keep class com.it_nomads.fluttersecurestorage.** { *; }
