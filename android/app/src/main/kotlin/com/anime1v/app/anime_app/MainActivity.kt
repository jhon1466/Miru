package com.anime1v.app.anime_app

import android.app.UiModeManager
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.anime1v.app/foreground_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    startForegroundDownloadService()
                    result.success(null)
                }
                "stopService" -> {
                    stopForegroundDownloadService()
                    result.success(null)
                }
                "isAndroidTV" -> {
                    val uiModeManager = getSystemService(UI_MODE_SERVICE) as UiModeManager
                    result.success(uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION)
                }
                "keepScreenOn" -> {
                    window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(null)
                }
                "releaseScreenOn" -> {
                    window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun startForegroundDownloadService() {
        val intent = Intent(this, DownloadForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopForegroundDownloadService() {
        val intent = Intent(this, DownloadForegroundService::class.java)
        stopService(intent)
    }
}
