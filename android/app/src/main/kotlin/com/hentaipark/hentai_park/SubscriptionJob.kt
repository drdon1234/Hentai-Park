package com.hentaipark.hentai_park

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.pichillilorenzo.flutter_inappwebview_android.InAppWebViewFlutterPlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.MethodChannel

/** 系统周期任务；不启动窗口，前后台只允许一个源运行环境写入配置。 */
class SubscriptionJob : JobService() {
    private var engine: FlutterEngine? = null
    private var background: MethodChannel? = null
    private var params: JobParameters? = null
    private val handler = Handler(Looper.getMainLooper())
    private val cleanup = Runnable { finish(true) }
    private val timeout = Runnable { cancelAndFinish() }
    private var stopped = false

    override fun onStartJob(parameters: JobParameters): Boolean {
        if (engine != null) return false
        if (foreground != null) {
            foreground?.invokeMethod("subscriptionWake", null)
            return false
        }
        active = this
        params = parameters
        stopped = false
        try {
        val loader = FlutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)
        val runtime = FlutterEngine(applicationContext)
        engine = runtime
        val browserChallengeInput = BrowserChallengeInput { id ->
            val plugin = runtime.plugins.get(InAppWebViewFlutterPlugin::class.java) as? InAppWebViewFlutterPlugin
            plugin?.headlessInAppWebViewManager?.webViews?.get(id)?.flutterWebView?.webView
        }
        MethodChannel(runtime.dartExecutor.binaryMessenger, "hentai_park/platform").setMethodCallHandler { call, result ->
            when (call.method) {
                "notifyChecked" -> {
                    try { result.success(SubscriptionNotifications.send(this, call.arguments as Map<*, *>)) }
                    catch (_: Exception) { result.success(false) }
                }
                "clickBrowserChallenge" -> browserChallengeInput.click(call.arguments as? Map<*, *>, result)
                "setWebViewProxy" -> WebViewProxy.apply(call.arguments, result)
                "terminateSourceRenderer" -> {
                    val id = call.arguments as? String
                    val plugin = runtime.plugins.get(InAppWebViewFlutterPlugin::class.java) as? InAppWebViewFlutterPlugin
                    val view = plugin?.headlessInAppWebViewManager?.webViews?.get(id)?.flutterWebView?.webView
                    val terminated = view != null &&
                        WebViewFeature.isFeatureSupported(WebViewFeature.WEB_VIEW_RENDERER_TERMINATE) &&
                        WebViewCompat.getWebViewRenderProcess(view)?.terminate() == true
                    result.success(terminated)
                }
                else -> result.notImplemented()
            }
        }
        background = MethodChannel(runtime.dartExecutor.binaryMessenger, "hentai_park/subscription_background").also {
            it.setMethodCallHandler { call, result ->
                if (call.method == "finished") {
                    result.success(null)
                    handler.post { finish(false) }
                } else result.notImplemented()
            }
        }
        runtime.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "subscriptionBackgroundMain"))
        handler.postDelayed(timeout, 240000)
        } catch (_: Exception) {
            // 初始化失败仍交还系统重试，不输出含路径或凭据的异常。
            handler.post { finish(true) }
        }
        return true
    }

    private fun cancelAndFinish() {
        handler.removeCallbacks(timeout)
        background?.invokeMethod("cancel", null)
        handler.removeCallbacks(cleanup)
        handler.postDelayed(cleanup, 10000)
    }

    private fun finish(reschedule: Boolean) {
        handler.removeCallbacks(timeout)
        handler.removeCallbacks(cleanup)
        background?.setMethodCallHandler(null)
        background = null
        engine?.destroy()
        engine = null
        if (active === this) active = null
        if (!stopped) params?.let { jobFinished(it, reschedule) }
        params = null
        val waiting = claims.toList()
        claims.clear()
        waiting.forEach { it.success(null) }
    }

    override fun onStopJob(parameters: JobParameters): Boolean {
        stopped = true
        // 给取消与原子写入一个短暂的收尾窗口；进程被杀后 SQLite 租约自动过期。
        cancelAndFinish()
        return true
    }

    override fun onDestroy() {
        stopped = true
        finish(false)
        super.onDestroy()
    }

    companion object {
        private const val ID = 17003
        private var active: SubscriptionJob? = null
        private val claims = mutableListOf<MethodChannel.Result>()
        var foreground: MethodChannel? = null
        fun claim(result: MethodChannel.Result) {
            val job = active
            if (job == null) result.success(null)
            else {
                claims.add(result)
                job.cancelAndFinish()
            }
        }
        fun schedule(context: Context, hours: Int) {
            val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
            if (hours == 0) { scheduler.cancel(ID); return }
            require(hours in listOf(1, 3, 6, 12, 24))
            val current = scheduler.getPendingJob(ID)
            val period = hours * 3600000L
            if (current?.intervalMillis == period) return
            val job = JobInfo.Builder(ID, ComponentName(context, SubscriptionJob::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPersisted(true).setPeriodic(period).build()
            check(scheduler.schedule(job) == JobScheduler.RESULT_SUCCESS)
        }
    }
}
