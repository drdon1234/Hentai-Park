package com.hentaipark.hentai_park

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.Display
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Native hooks used by lib/ui/platform.dart: FLAG_SECURE, volume-key paging in the reader and
 * plain system notifications (library updates) without an extra plugin, and the preferred
 * display refresh rate (many 90/120/144 Hz phones keep apps at 60 Hz unless they ask).
 */
class MainActivity : FlutterFragmentActivity() {
    private var channel: MethodChannel? = null
    private var interceptVolume = false
    private var launchPayload: String? = null

    /** Requested refresh rate in Hz; 0 = the highest the display offers at the current resolution. */
    private var refreshRate = 0.0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        applyRefreshRate()
    }

    @Suppress("DEPRECATION")
    private fun currentDisplay(): Display? = if (Build.VERSION.SDK_INT >= 30) display else windowManager.defaultDisplay

    /** Modes with the current resolution (switching resolution would recreate surfaces). */
    private fun sameSizeModes(): List<Display.Mode> {
        if (Build.VERSION.SDK_INT < 23) return emptyList()
        val d = currentDisplay() ?: return emptyList()
        val cur = d.mode
        return d.supportedModes.filter { it.physicalWidth == cur.physicalWidth && it.physicalHeight == cur.physicalHeight }
    }

    private fun applyRefreshRate() {
        if (Build.VERSION.SDK_INT < 23) return
        val modes = sameSizeModes()
        if (modes.isEmpty()) return
        val target = if (refreshRate <= 0) modes.maxByOrNull { it.refreshRate }
        else modes.minByOrNull { Math.abs(it.refreshRate - refreshRate) }
        target ?: return
        val attrs = window.attributes
        if (attrs.preferredDisplayModeId == target.modeId && attrs.preferredRefreshRate == target.refreshRate) return
        attrs.preferredDisplayModeId = target.modeId
        attrs.preferredRefreshRate = target.refreshRate
        window.attributes = attrs
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launchPayload = intent?.getStringExtra(EXTRA_PAYLOAD)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hentai_park/platform").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        if (call.arguments == true) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "interceptVolume" -> {
                        interceptVolume = call.arguments == true
                        result.success(null)
                    }
                    "notify" -> {
                        notify(call.arguments as Map<*, *>)
                        result.success(null)
                    }
                    "cancelNotification" -> {
                        manager().cancel((call.arguments as Number).toInt())
                        result.success(null)
                    }
                    "requestNotificationPermission" -> result.success(requestNotificationPermission())
                    "refreshRates" -> result.success(
                        sameSizeModes().map { Math.round(it.refreshRate).toInt() }.distinct().sorted()
                    )
                    "currentRefreshRate" -> result.success(currentDisplay()?.refreshRate?.toDouble() ?: 60.0)
                    "setRefreshRate" -> {
                        refreshRate = (call.arguments as? Number)?.toDouble() ?: 0.0
                        applyRefreshRate()
                        result.success(null)
                    }
                    "takeLaunchPayload" -> {
                        result.success(launchPayload)
                        launchPayload = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra(EXTRA_PAYLOAD)?.let { channel?.invokeMethod("notificationTap", it) }
    }

    private fun manager() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun requestNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) return true
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7001)
        return false
    }

    private fun notify(args: Map<*, *>) {
        val id = (args["id"] as Number).toInt()
        val channelId = args["channel"] as? String ?: "library"
        if (Build.VERSION.SDK_INT >= 26) {
            val name = args["channelName"] as? String ?: "书库更新"
            val importance = if (args["ongoing"] == true) NotificationManager.IMPORTANCE_LOW else NotificationManager.IMPORTANCE_DEFAULT
            manager().createNotificationChannel(NotificationChannel(channelId, name, importance))
        }
        val open = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            (args["payload"] as? String)?.let { putExtra(EXTRA_PAYLOAD, it) }
        }
        val pending = PendingIntent.getActivity(this, id, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channelId) else Notification.Builder(this)
        builder
            .setSmallIcon(R.drawable.ic_launcher_fg)
            .setContentTitle(args["title"] as? String ?: "")
            .setContentText(args["text"] as? String ?: "")
            .setContentIntent(pending)
            .setOngoing(args["ongoing"] == true)
            .setOnlyAlertOnce(true)
            .setAutoCancel(args["ongoing"] != true)
        val max = (args["max"] as? Number)?.toInt() ?: 0
        if (max > 0) builder.setProgress(max, (args["progress"] as? Number)?.toInt() ?: 0, false)
        (args["text"] as? String)?.let { builder.setStyle(Notification.BigTextStyle().bigText(it)) }
        manager().notify(id, builder.build())
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (interceptVolume && (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP)) {
            channel?.invokeMethod("volumeKey", if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) 1 else -1)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (interceptVolume && (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP)) return true
        return super.onKeyUp(keyCode, event)
    }

    companion object {
        const val EXTRA_PAYLOAD = "park_payload"
    }
}
