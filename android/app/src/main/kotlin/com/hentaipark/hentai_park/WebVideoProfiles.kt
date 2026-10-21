package com.hentaipark.hentai_park

import android.view.ViewGroup
import android.os.Handler
import android.os.Looper
import androidx.webkit.ProfileStore
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import androidx.webkit.WebStorageCompat
import com.pichillilorenzo.flutter_inappwebview_android.InAppWebViewFlutterPlugin
import io.flutter.embedding.engine.FlutterEngine
import java.util.UUID

/** 播放器不读写应用默认 WebView 的 Cookie，也不把上游 Cookie 导入源分区。 */
class WebVideoProfiles(private val engine: FlutterEngine) {
    private val profiles = mutableMapOf<String, String>()
    private val prefix = "park_web_video_"

    private fun plugin() = engine.plugins.get(InAppWebViewFlutterPlugin::class.java)
        as? InAppWebViewFlutterPlugin

    fun challengeView(id: String): android.webkit.WebView? =
        if (profiles.containsKey(id)) plugin()?.inAppWebViewManager?.keepAliveWebViews?.get(id)?.webView
        else null

    fun isolate(id: String): Boolean {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) return false
        val view = plugin()?.inAppWebViewManager?.keepAliveWebViews?.get(id)?.webView
            ?: return false
        if (profiles.containsKey(id)) return true
        val store = ProfileStore.getInstance()
        // 上次异常退出遗留的临时数据，只删除本播放器创建且当前未使用的 Profile。
        for (name in store.allProfileNames) {
            if (name.startsWith(prefix) && !profiles.containsValue(name)) {
                runCatching { store.deleteProfile(name) }
            }
        }
        val name = prefix + UUID.randomUUID().toString()
        return try {
            WebViewCompat.setProfile(view, name)
            profiles[id] = name
            true
        } catch (_: Exception) {
            runCatching { store.deleteProfile(name) }
            false
        }
    }

    fun release(id: String) {
        val manager = plugin()?.inAppWebViewManager
        val flutterView = manager?.keepAliveWebViews?.remove(id)
        val view = flutterView?.webView
        val name = profiles.remove(id)
        try {
            if (flutterView != null) {
                // 部分 WebView 在本进程内不允许删除已载入的 Profile。
                // 只清当前独立 Profile，绝不调用全局 CookieManager/WebStorage。
                name?.let {
                    val profile = ProfileStore.getInstance().getProfile(it)
                    profile?.cookieManager?.removeAllCookies(null)
                    profile?.webStorage?.deleteAllData()
                    profile?.geolocationPermissions?.clearAll()
                    if (profile != null && WebViewFeature.isFeatureSupported(WebViewFeature.DELETE_BROWSING_DATA)) {
                        WebStorageCompat.deleteBrowsingData(profile.webStorage) {}
                    }
                }
                (flutterView.view?.parent as? ViewGroup)?.removeView(flutterView.view)
                flutterView.keepAliveId = null
                flutterView.dispose()
            }
        } finally {
            // 插件通常等空白页完成才 destroy；先销毁才能可靠删除 Profile。
            runCatching { view?.destroy() }
            name?.let { profileName ->
                // Chromium 的销毁会排队释放 Profile；下一轮主线程再删除。
                Handler(Looper.getMainLooper()).post {
                    // 若当前实现仍认为 Profile 在使用，下次进程启动时 isolate 会删除。
                    runCatching { ProfileStore.getInstance().deleteProfile(profileName) }
                }
            }
        }
    }
}
