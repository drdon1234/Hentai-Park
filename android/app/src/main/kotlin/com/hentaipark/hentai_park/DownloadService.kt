package com.hentaipark.hentai_park

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** 只保护当前引擎内正在执行的下载，不自动重建任务或启动第二个源引擎。 */
class DownloadService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null
    private var count = 0
    private val idleStop = Runnable { if (count == 0) stopDownloads() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        current = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            val title = intent?.getStringExtra("title") ?: "HentaiPark"
            val text = intent?.getStringExtra("text") ?: ""
            count = intent?.getIntExtra("count", 0) ?: 0
            val notification = notification(title, text)
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            if (wakeLock == null) {
                val power = getSystemService(Context.POWER_SERVICE) as PowerManager
                wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "HentaiPark:downloads").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
            ready(null)
            if (count == 0) stopDownloads()
        } catch (_: Exception) {
            count = 0
            ready("START_FAILED")
            stopDownloads()
        }
        return START_NOT_STICKY
    }

    private fun update(count: Int, title: String, text: String) {
        handler.removeCallbacks(idleStop)
        this.count = count
        if (count == 0) {
            // 队列交接和并发任务收尾期间不反复从后台重新启动前台服务。
            handler.postDelayed(idleStop, 1500)
        } else {
            manager().notify(NOTIFICATION_ID, notification(title, text))
        }
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Android 15 的 dataSync 时间额度耗尽后必须及时退出前台服务。
        interrupt()
        stopDownloads()
    }

    private fun interrupt() {
        if (count > 0) events?.invokeMethod("interrupted", null)
        count = 0
    }

    private fun stopDownloads() {
        handler.removeCallbacks(idleStop)
        if (current === this) current = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        interrupt()
        stopDownloads()
        ready("STOPPED")
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        events?.invokeMethod("taskRemoved", null)
        super.onTaskRemoved(rootIntent)
    }

    private fun manager() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun notification(title: String, text: String): Notification {
        if (Build.VERSION.SDK_INT >= 26) {
            manager().createNotificationChannel(NotificationChannel(CHANNEL, title, NotificationManager.IMPORTANCE_LOW))
        }
        val open = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(this, NOTIFICATION_ID, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        return builder.setSmallIcon(R.drawable.ic_launcher_fg)
            .setContentTitle(title).setContentText(text).setContentIntent(pending)
            .setOngoing(true).setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setProgress(0, 0, true).build()
    }

    companion object {
        private const val CHANNEL = "downloads"
        private const val NOTIFICATION_ID = 3001
        private var current: DownloadService? = null
        private var events: MethodChannel? = null
        private val waiting = mutableListOf<MethodChannel.Result>()

        private fun ready(error: String?) {
            val results = waiting.toList()
            waiting.clear()
            results.forEach {
                if (error == null) it.success(null) else it.error(error, null, null)
            }
        }

        fun attach(context: Context, messenger: BinaryMessenger): MethodChannel {
            val channel = MethodChannel(messenger, "hentai_park/downloads")
            events = channel
            channel.setMethodCallHandler { call, result ->
                if (call.method != "update") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val count = call.argument<Int>("count")
                val title = call.argument<String>("title")
                val text = call.argument<String>("text")
                if (count == null || count < 0 || title == null || text == null) {
                    result.error("ARGUMENT", null, null)
                    return@setMethodCallHandler
                }
                try {
                    val service = current
                    if (service != null) {
                        service.update(count, title, text)
                        result.success(null)
                    } else if (count == 0) {
                        result.success(null)
                    } else {
                        waiting.add(result)
                        ContextCompat.startForegroundService(context, Intent(context, DownloadService::class.java).apply {
                            putExtra("count", count)
                            putExtra("title", title)
                            putExtra("text", text)
                        })
                    }
                } catch (_: Exception) {
                    if (waiting.remove(result)) ready("START_FAILED")
                    result.error("START_FAILED", null, null)
                }
            }
            return channel
        }

        fun detach(channel: MethodChannel?) {
            if (events !== channel) return
            events = null
            channel?.setMethodCallHandler(null)
            current?.stopDownloads()
            ready("STOPPED")
        }
    }
}
