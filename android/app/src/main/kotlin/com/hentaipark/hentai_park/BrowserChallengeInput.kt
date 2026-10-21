package com.hentaipark.hentai_park

import android.net.Uri
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.webkit.WebView
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** 只在指定后台 WebView 的当前文档内分发触摸，不使用系统级输入或调试端口。 */
internal class BrowserChallengeInput(private val resolve: (String) -> WebView?) {
    fun click(args: Map<*, *>?, result: MethodChannel.Result) {
        val id = args?.get("id") as? String
        val url = args?.get("url") as? String
        val token = args?.get("token") as? String
        val view = id?.let(resolve)
        if (view == null || url == null || token.isNullOrEmpty() || token.length > 160 ||
            !secureUrl(url) || view.url != url || !view.isAttachedToWindow) {
            result.success(false)
            return
        }
        val width = view.width
        val height = view.height
        val started = SystemClock.uptimeMillis()
        // JS 同时检查每文档随机标识、唯一可信框、遮挡和可视范围，并消耗该次输入机会。
        val script = "window.__parkChallengeInput?.snapshot(${JSONObject.quote(token)}, true) ?? null"
        try {
            view.evaluateJavascript(script) { raw ->
                var down = false
                var downTime = 0L
                var x = 0f
                var y = 0f
                try {
                    if (resolve(id) !== view || view.url != url || !view.isAttachedToWindow ||
                        view.width != width || view.height != height ||
                        SystemClock.uptimeMillis() - started > 1500) {
                        result.success(false)
                        return@evaluateJavascript
                    }
                    val data = JSONObject(raw)
                    val frame = data.getString("frame")
                    val viewportWidth = data.getDouble("width")
                    val viewportHeight = data.getDouble("height")
                    val cssX = data.getDouble("x")
                    val cssY = data.getDouble("y")
                    val scale = width / viewportWidth
                    val scaleY = height / viewportHeight
                    if (data.getString("token") != token || data.getString("url") != url ||
                        !secureUrl(frame, "challenges.cloudflare.com") ||
                        !listOf(viewportWidth, viewportHeight, cssX, cssY, scale, scaleY).all { it.isFinite() } ||
                        scale !in 0.1..10.0 || kotlin.math.abs(scaleY / scale - 1) > 0.02 ||
                        cssX <= 0 || cssX >= viewportWidth || cssY <= 0 || cssY >= viewportHeight) {
                        result.success(false)
                        return@evaluateJavascript
                    }
                    x = (cssX * scale).toFloat()
                    y = (cssY * scale).toFloat()
                    downTime = SystemClock.uptimeMillis()
                    down = touch(view, downTime, MotionEvent.ACTION_DOWN, x, y)
                    val acceptedDown = down
                    val up = touch(view, downTime, MotionEvent.ACTION_UP, x, y)
                    down = false
                    result.success(acceptedDown && up)
                } catch (_: Exception) {
                    if (down) runCatching { touch(view, downTime, MotionEvent.ACTION_CANCEL, x, y) }
                    result.success(false)
                }
            }
        } catch (_: Exception) {
            result.success(false)
        }
    }

    private fun secureUrl(value: String, host: String? = null): Boolean = runCatching {
        val uri = Uri.parse(value)
        uri.scheme == "https" && !uri.host.isNullOrEmpty() &&
            (host == null || uri.host == host) && (uri.port == -1 || uri.port == 443) &&
            uri.userInfo.isNullOrEmpty()
    }.getOrDefault(false)

    private fun touch(view: WebView, start: Long, action: Int, x: Float, y: Float): Boolean {
        val event = MotionEvent.obtain(start, SystemClock.uptimeMillis(), action, x, y, 0)
        event.source = InputDevice.SOURCE_TOUCHSCREEN
        return try { view.dispatchTouchEvent(event) } finally { event.recycle() }
    }
}
