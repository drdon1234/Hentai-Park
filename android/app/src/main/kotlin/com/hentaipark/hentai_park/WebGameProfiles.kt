package com.hentaipark.hentai_park

import android.view.ViewGroup
import android.view.KeyEvent
import android.os.SystemClock
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.pichillilorenzo.flutter_inappwebview_android.InAppWebViewFlutterPlugin
import io.flutter.embedding.engine.FlutterEngine

/** 独立且持久的游戏浏览器配置；关闭页面不清除存档或缓存。 */
class WebGameProfiles(private val engine: FlutterEngine) {
    private val active = mutableSetOf<String>()
    private fun plugin() = engine.plugins.get(InAppWebViewFlutterPlugin::class.java)
        as? InAppWebViewFlutterPlugin

    fun challengeView(id: String): android.webkit.WebView? =
        if (active.contains(id)) plugin()?.inAppWebViewManager?.keepAliveWebViews?.get(id)?.webView
        else null

    fun attach(id: String, key: String): Boolean {
        if (!Regex("^[a-f0-9]{64}$").matches(key)) return false
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) return false
        val view = plugin()?.inAppWebViewManager?.keepAliveWebViews?.get(id)?.webView ?: return false
        if (active.contains(id)) return true
        return try {
            // The plugin binds the profile immediately after constructing the WebView.
            if (WebViewCompat.getProfile(view).name != "park_game_$key") return false
            active.add(id)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun release(id: String) {
        if (!active.remove(id)) return
        val flutterView = plugin()?.inAppWebViewManager?.keepAliveWebViews?.remove(id) ?: return
        val view = flutterView.webView
        try {
            (flutterView.view?.parent as? ViewGroup)?.removeView(flutterView.view)
            flutterView.keepAliveId = null
            flutterView.dispose()
        } finally {
            runCatching { view?.destroy() }
        }
    }

    fun sendKey(id: String, code: String, down: Boolean, ctrl: Boolean): Boolean {
        if (!active.contains(id)) return false
        val view = plugin()?.inAppWebViewManager?.keepAliveWebViews?.get(id)?.webView ?: return false
        val keyCode = when (code) {
            "ArrowUp" -> KeyEvent.KEYCODE_DPAD_UP
            "ArrowDown" -> KeyEvent.KEYCODE_DPAD_DOWN
            "ArrowLeft" -> KeyEvent.KEYCODE_DPAD_LEFT
            "ArrowRight" -> KeyEvent.KEYCODE_DPAD_RIGHT
            "KeyZ" -> KeyEvent.KEYCODE_Z
            "KeyX" -> KeyEvent.KEYCODE_X
            "Enter" -> KeyEvent.KEYCODE_ENTER
            "Space" -> KeyEvent.KEYCODE_SPACE
            "Escape" -> KeyEvent.KEYCODE_ESCAPE
            "ControlLeft" -> KeyEvent.KEYCODE_CTRL_LEFT
            else -> return false
        }
        val now = SystemClock.uptimeMillis()
        val modifiers = if (ctrl) KeyEvent.META_CTRL_ON or KeyEvent.META_CTRL_LEFT_ON else 0
        val event = KeyEvent(now, now, if (down) KeyEvent.ACTION_DOWN else KeyEvent.ACTION_UP, keyCode, 0, modifiers)
        view.requestFocus()
        view.dispatchKeyEvent(event)
        return true
    }
}
