package com.hentaipark.hentai_park

import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.MethodChannel

object WebViewProxy {
    fun apply(raw: Any?, result: MethodChannel.Result) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
            result.success(false)
            return
        }
        val args = raw as? Map<*, *>
        val host = (args?.get("host") as? String)?.trim() ?: ""
        val controller = ProxyController.getInstance()
        try {
            if (host.isEmpty()) {
                controller.clearProxyOverride(Runnable::run) { result.success(true) }
                return
            }
            val port = (args?.get("port") as? Number)?.toInt() ?: 0
            if (port !in 1..65535) {
                result.success(false)
                return
            }
            val formattedHost = if (host.contains(':') && !host.startsWith("[")) "[$host]" else host
            val config = ProxyConfig.Builder()
                .addProxyRule("http://$formattedHost:$port")
                .build()
            controller.setProxyOverride(config, Runnable::run) { result.success(true) }
        } catch (_: Exception) {
            result.success(false)
        }
    }
}
