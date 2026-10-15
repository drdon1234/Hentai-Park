package com.hentaipark.hentai_park

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.Display
import android.view.KeyEvent
import android.view.WindowManager
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.pichillilorenzo.flutter_inappwebview_android.InAppWebViewFlutterPlugin
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
    private var mediaRemuxer: MediaRemuxer? = null
    private var interceptVolume = false
    private var launchPayload: String? = null
    private var videoBrightness: Float? = null
    private var videoFullscreen = false
    private var videoSystemUi: VideoSystemUi? = null

    private data class VideoSystemUi(val visibleTypes: Int, val behavior: Int)

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

    override fun onPostResume() {
        super.onPostResume()
        if (videoFullscreen) hideVideoSystemBars()
    }

    override fun onPause() {
        // Keep the fullscreen preference, but release the window while backgrounded.
        restoreVideoSystemBars(clear = false)
        resetVideoBrightness()
        super.onPause()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && videoFullscreen) hideVideoSystemBars()
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
        mediaRemuxer?.shutdown()
        mediaRemuxer = MediaRemuxer(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        launchPayload = intent?.getStringExtra(EXTRA_PAYLOAD)
        val webVideoProfiles = WebVideoProfiles(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hentai_park/platform").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isolateWebVideo" -> {
                        try { result.success(webVideoProfiles.isolate(call.arguments as String)) }
                        catch (_: Exception) { result.success(false) }
                    }
                    "releaseWebVideo" -> {
                        try {
                            webVideoProfiles.release(call.arguments as String)
                            result.success(null)
                        } catch (_: Exception) { result.error("WEB_VIDEO", "WEB_VIDEO", null) }
                    }
                    "claimSourceEngine" -> SubscriptionJob.claim(result)
                    "scheduleSubscriptions" -> {
                        try {
                            SubscriptionJob.schedule(this, (call.arguments as Number).toInt())
                            result.success(null)
                        } catch (_: Exception) { result.error("SCHEDULE", "SCHEDULE", null) }
                    }
                    "notifyChecked" -> {
                        try { result.success(SubscriptionNotifications.send(this, call.arguments as Map<*, *>)) }
                        catch (_: Exception) { result.success(false) }
                    }
                    "appUpdateAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                    "appUpdatePermission" -> {
                        try {
                            AppInstaller(this).openPermission()
                            result.success(null)
                        } catch (_: Exception) { result.error("UPDATE_PERMISSION", "UPDATE_PERMISSION", null) }
                    }
                    "appUpdateInstall" -> {
                        try {
                            val args = call.arguments as Map<*, *>
                            result.success(AppInstaller(this).install(args["path"] as String, args["version"] as String))
                        } catch (_: Exception) { result.error("UPDATE_INSTALL", "UPDATE_INSTALL", null) }
                    }
                    "terminateSourceRenderer" -> {
                        val id = call.arguments as? String
                        val plugin = flutterEngine.plugins.get(InAppWebViewFlutterPlugin::class.java) as? InAppWebViewFlutterPlugin
                        val view = plugin?.headlessInAppWebViewManager?.webViews?.get(id)?.flutterWebView?.webView
                        val terminated = view != null &&
                            WebViewFeature.isFeatureSupported(WebViewFeature.WEB_VIEW_RENDERER_TERMINATE) &&
                            WebViewCompat.getWebViewRenderProcess(view)?.terminate() == true
                        result.success(terminated)
                    }
                    "setSecure" -> {
                        if (call.arguments == true) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "interceptVolume" -> {
                        interceptVolume = call.arguments == true
                        result.success(null)
                    }
                    "videoLevels" -> {
                        val override = window.attributes.screenBrightness
                        val brightness = if (override >= 0) override.toDouble() else
                            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128) / 255.0
                        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
                        result.success(mapOf(
                            "brightness" to brightness.coerceIn(0.0, 1.0),
                            "volume" to audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max
                        ))
                    }
                    "setVideoBrightness" -> {
                        val attrs = window.attributes
                        if (videoBrightness == null) videoBrightness = attrs.screenBrightness
                        attrs.screenBrightness = (call.arguments as Number).toFloat().coerceIn(0f, 1f)
                        window.attributes = attrs
                        result.success(null)
                    }
                    "setVideoVolume" -> {
                        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val level = (call.arguments as Number).toDouble().coerceIn(0.0, 1.0)
                        val target = Math.round(level * audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)).toInt()
                        audio.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
                        result.success(null)
                    }
                    "resetVideoBrightness" -> {
                        resetVideoBrightness()
                        result.success(null)
                    }
                    "setVideoFullscreen" -> {
                        try {
                            videoFullscreen = call.arguments == true
                            if (videoFullscreen) hideVideoSystemBars()
                            else restoreVideoSystemBars(clear = true)
                            result.success(null)
                        } catch (error: Exception) {
                            videoFullscreen = false
                            runCatching { restoreVideoSystemBars(clear = true) }
                            result.error("SYSTEM_UI", error.message, null)
                        }
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
        SubscriptionJob.foreground = channel
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (SubscriptionJob.foreground === channel) SubscriptionJob.foreground = null
        mediaRemuxer?.shutdown()
        mediaRemuxer = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra(EXTRA_PAYLOAD)?.let { channel?.invokeMethod("notificationTap", it) }
    }

    private fun resetVideoBrightness() {
        val original = videoBrightness ?: return
        val attrs = window.attributes
        attrs.screenBrightness = original
        window.attributes = attrs
        videoBrightness = null
    }

    private fun hideVideoSystemBars() {
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        if (videoSystemUi == null) {
            val insets = ViewCompat.getRootWindowInsets(window.decorView)
            var visibleTypes = 0
            if (insets?.isVisible(WindowInsetsCompat.Type.statusBars()) != false) visibleTypes = visibleTypes or WindowInsetsCompat.Type.statusBars()
            if (insets?.isVisible(WindowInsetsCompat.Type.navigationBars()) != false) visibleTypes = visibleTypes or WindowInsetsCompat.Type.navigationBars()
            if (insets?.isVisible(WindowInsetsCompat.Type.captionBar()) == true) visibleTypes = visibleTypes or WindowInsetsCompat.Type.captionBar()
            videoSystemUi = VideoSystemUi(visibleTypes, controller.systemBarsBehavior)
        }
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller.hide(WindowInsetsCompat.Type.systemBars())
    }

    private fun restoreVideoSystemBars(clear: Boolean) {
        val original = videoSystemUi ?: return
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        val hiddenTypes = WindowInsetsCompat.Type.systemBars() and original.visibleTypes.inv()
        controller.systemBarsBehavior = original.behavior
        if (original.visibleTypes != 0) controller.show(original.visibleTypes)
        if (hiddenTypes != 0) controller.hide(hiddenTypes)
        if (clear) videoSystemUi = null
    }

    override fun onDestroy() {
        videoFullscreen = false
        restoreVideoSystemBars(clear = true)
        resetVideoBrightness()
        super.onDestroy()
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
        val handled = super.onKeyUp(keyCode, event)
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
            channel?.invokeMethod("mediaVolume", audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max)
        }
        return handled
    }

    companion object {
        const val EXTRA_PAYLOAD = "park_payload"
    }
}
