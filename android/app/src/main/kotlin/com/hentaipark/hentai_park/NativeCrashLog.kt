package com.hentaipark.hentai_park

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.os.Process
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors
import kotlin.system.exitProcess

/** Collect before Flutter starts, and always delegate to Android's fatal handler. */
object NativeCrashLog {
    private const val LIMIT = 256 * 1024
    private val worker = Executors.newSingleThreadExecutor()
    private val reasons = setOf(
        "JAVA_CRASH", "NATIVE_CRASH", "ANR", "LOW_MEMORY", "SIGNALED", "EXIT_SELF",
        "EXCESSIVE_RESOURCE", "USER_REQUESTED", "USER_STOPPED", "DEPENDENCY_DIED",
        "INITIALIZATION_FAILURE", "PERMISSION_CHANGE", "PACKAGE_STATE_CHANGE",
        "PACKAGE_UPDATED", "FREEZER", "OTHER", "UNKNOWN",
    )

    private fun fields(input: JSONObject): JSONObject = JSONObject().apply {
        val event = input.optString("event")
        put("event", if (event in setOf("native_crash", "process_exit", "native_diagnostics")) event else "native_diagnostics")
        put("library", "android")
        input.optString("reason").takeIf { it in reasons }?.let { put("reason", it) }
        input.optString("type").takeIf { it.matches(Regex("[A-Za-z][A-Za-z0-9_]{0,63}")) }?.let { put("type", it) }
        input.optString("exitStatus").toIntOrNull()?.takeIf { it in 0..255 }?.let { put("exitStatus", it.toString()) }
    }

    fun install(context: Context) {
        val app = context.applicationContext
        // Remove dynamic text from existing local diagnostics before recording.
        runCatching { readStored(app) }
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                append(app, entry(
                    System.currentTimeMillis(),
                    JSONObject().put("event", "native_crash").put("reason", "JAVA_CRASH")
                        .put("type", error.javaClass.simpleName).put("library", "android"),
                ))
            } catch (_: Throwable) {
                // OOM, storage errors and logging failures must not replace the original crash.
            } finally {
                if (previous != null) previous.uncaughtException(thread, error)
                else {
                    Process.killProcess(Process.myPid())
                    exitProcess(10)
                }
            }
        }
        worker.execute {
            try { collectExits(app) } catch (_: Throwable) {
                // The read method retries and reports collection errors to Dart.
            }
        }
    }

    fun read(context: Context, done: (List<Map<String, Any?>>?, Throwable?) -> Unit) {
        worker.execute {
            try {
                val collectionError = runCatching { collectExits(context) }.exceptionOrNull()
                val records = readStored(context).toMutableList()
                if (collectionError != null) {
                    records.add(entry(System.currentTimeMillis(),
                        JSONObject().put("event", "native_diagnostics").put("library", "android")
                            .put("type", collectionError.javaClass.simpleName),
                    ))
                }
                done(records.map { value ->
                    mapOf(
                        "time" to value.getString("time"),
                        "fields" to value.getJSONObject("fields").let { fields ->
                            fields.keys().asSequence().associateWith { fields.getString(it) }
                        },
                        "frames" to value.getJSONArray("frames").let { frames ->
                            (0 until frames.length()).map { frames.getString(it) }
                        },
                    )
                }, null)
            } catch (error: Throwable) { done(null, error) }
        }
    }

    private fun entry(time: Long, metadata: JSONObject): JSONObject {
        val timestamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.ROOT).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date(time))
        return JSONObject().put("time", timestamp).put("fields", fields(metadata))
            .put("frames", JSONArray())
    }

    private fun file(context: Context) = File(context.filesDir, "logs/native_crash.log")

    @Synchronized
    private fun append(context: Context, entry: JSONObject) {
        val target = file(context)
        check(target.parentFile!!.isDirectory || target.parentFile!!.mkdirs())
        val bytes = (entry.toString() + "\n").toByteArray(Charsets.UTF_8)
        if (target.exists() && target.length() + bytes.size > LIMIT) {
            val rotated = File(target.path + ".1")
            check(!rotated.exists() || rotated.delete())
            check(target.renameTo(rotated))
        }
        FileOutputStream(target, true).use { stream ->
            stream.write(bytes)
            stream.fd.sync()
        }
    }

    @Synchronized
    private fun readStored(context: Context): List<JSONObject> =
        listOf(File(file(context).path + ".1"), file(context)).flatMap { target ->
            runCatching {
                if (!target.exists()) emptyList() else {
                    val entries = target.useLines { lines ->
                        lines.mapNotNull { line -> runCatching {
                            val value = JSONObject(line)
                            val time = value.optString("time")
                            if (!time.matches(Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z"))) null
                            else JSONObject().put("time", time)
                                .put("fields", fields(value.getJSONObject("fields")))
                                .put("frames", JSONArray())
                        }.getOrNull() }.toList()
                    }
                    FileOutputStream(target).use { stream ->
                        for (entry in entries) stream.write((entry.toString() + "\n").toByteArray(Charsets.UTF_8))
                        stream.fd.sync()
                    }
                    entries
                }
            }.getOrDefault(emptyList())
        }

    private fun collectExits(context: Context) {
        if (Build.VERSION.SDK_INT < 30) return
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val preferences = context.getSharedPreferences("crash_diagnostics", Context.MODE_PRIVATE)
        val importedThrough = preferences.getLong("imported_through", 0)
        val known = readStored(context).map { it.optString("time") + it.optJSONObject("fields")?.optString("reason") }.toMutableSet()
        // Oldest first on disk, so rotation keeps the latest incidents.
        for (exit in manager.getHistoricalProcessExitReasons(context.packageName, 0, 20).sortedBy { it.timestamp }) {
            // Rotation must not cause discarded old exits to be re-imported over newer ones.
            if (exit.timestamp < importedThrough) continue
            val reason = when (exit.reason) {
                ApplicationExitInfo.REASON_CRASH -> "JAVA_CRASH"
                ApplicationExitInfo.REASON_CRASH_NATIVE -> "NATIVE_CRASH"
                ApplicationExitInfo.REASON_ANR -> "ANR"
                ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
                ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED"
                ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF"
                ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "EXCESSIVE_RESOURCE"
                ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED"
                ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
                ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
                ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
                ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
                ApplicationExitInfo.REASON_PACKAGE_STATE_CHANGE -> "PACKAGE_STATE_CHANGE"
                ApplicationExitInfo.REASON_PACKAGE_UPDATED -> "PACKAGE_UPDATED"
                ApplicationExitInfo.REASON_FREEZER -> "FREEZER"
                ApplicationExitInfo.REASON_OTHER -> "OTHER"
                else -> "UNKNOWN"
            }
            val record = entry(exit.timestamp,
                JSONObject().put("event", "process_exit").put("library", "android")
                    .put("reason", reason).put("exitStatus", exit.status.toString()),
            )
            if (!known.add(record.getString("time") + reason)) continue
            // Exit descriptions, ANR traces and tombstones may contain user
            // content or paths. Only the structured reason/status are collected.
            append(context, record)
            check(preferences.edit().putLong("imported_through", exit.timestamp).commit())
        }
    }
}
