package com.fallguardian.caregiver_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createFallAlertChannel()
    }

    private fun createFallAlertChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            "fall_alerts",
            "Fall alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Urgent fall alerts from protected persons"
        }

        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
