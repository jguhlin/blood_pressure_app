package com.example.blood_pressure_app

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Extends FlutterFragmentActivity for Health Connect permission flows
class MainActivity : FlutterFragmentActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.healthconnect").setMethodCallHandler { call, result ->
      when (call.method) {
        "openSettings" -> {
          try {
            val action = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
              // Android 14+
              "android.health.connect.action.HEALTH_HOME_SETTINGS"
            } else {
              // Android 13 and below (Health Connect app)
              "androidx.health.ACTION_HEALTH_CONNECT_SETTINGS"
            }
            val intent = Intent(action)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            result.success(true)
          } catch (e: Exception) {
            try {
              val launch = packageManager.getLaunchIntentForPackage("com.google.android.apps.healthdata")
              if (launch != null) {
                startActivity(launch)
                result.success(true)
              } else {
                result.error("NO_APP", "Health Connect app not found", null)
              }
            } catch (ex: Exception) {
              result.error("ERROR", ex.localizedMessage, null)
            }
          }
        }
        else -> result.notImplemented()
      }
    }
  }
}
