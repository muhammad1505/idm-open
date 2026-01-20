package com.idmopen

import android.app.Activity
import android.content.Intent
import android.os.Bundle

class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
        finish()
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        if (intent != null) {
            handleIntent(intent)
        }
        finish()
    }

    private fun handleIntent(intent: Intent) {
        val url = extractUrl(intent) ?: return
        val serviceIntent = Intent(this, DownloadForegroundService::class.java)
        serviceIntent.putExtra(DownloadForegroundService.EXTRA_URL, url)
        startForegroundService(serviceIntent)
    }

    private fun extractUrl(intent: Intent): String? {
        return when (intent.action) {
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
            Intent.ACTION_VIEW -> intent.dataString
            else -> null
        }
    }
}
