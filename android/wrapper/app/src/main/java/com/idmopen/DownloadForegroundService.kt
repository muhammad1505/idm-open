package com.idmopen

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log

class DownloadForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val url = intent?.getStringExtra(EXTRA_URL)
        if (url.isNullOrBlank()) {
            stopSelf()
            return START_NOT_STICKY
        }

        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("IDM-Open")
            .setContentText("Queued: $url")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .build()

        startForeground(NOTIFICATION_ID, notification)

        // TODO: call Rust core via JNI/FFI to enqueue the task.
        Log.i(TAG, "Received URL: $url")

        stopForeground(STOP_FOREGROUND_DETACH)
        stopSelf()
        return START_NOT_STICKY
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                CHANNEL_ID,
                "IDM-Open",
                NotificationManager.IMPORTANCE_LOW
            )
            manager.createNotificationChannel(channel)
        }
    }

    companion object {
        const val EXTRA_URL = "extra_url"
        private const val CHANNEL_ID = "idm_open"
        private const val NOTIFICATION_ID = 1001
        private const val TAG = "IDM-Open"
    }
}
