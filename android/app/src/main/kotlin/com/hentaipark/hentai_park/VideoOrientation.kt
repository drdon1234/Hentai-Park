package com.hentaipark.hentai_park

import android.app.Activity
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.view.OrientationEventListener
import android.view.Surface
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

/** Fullscreen keeps its selected axis, including reverse portrait on phones. */
class VideoOrientation(private val activity: Activity) {
    private var landscape: Boolean? = null
    private var foreground = true
    private var naturalLandscape = false
    private var preferred = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    private val handler = Handler(Looper.getMainLooper())
    private var armedAt = 0L
    private var candidate: Int? = null
    private var pending: Runnable? = null
    private fun clearCandidate() {
        pending?.let { handler.removeCallbacks(it) }
        pending = null
        candidate = null
    }
    private val sensor = object : OrientationEventListener(activity) {
        override fun onOrientationChanged(angle: Int) {
            val horizontal = landscape ?: return
            if (!foreground || angle == ORIENTATION_UNKNOWN || SystemClock.uptimeMillis() < armedAt) {
                clearCandidate()
                return
            }
            val normal = if (horizontal) {
                if (naturalLandscape) 0 else 270
            } else {
                if (naturalLandscape) 270 else 0
            }
            val delta = (angle - normal + 360) % 360
            val reverse = when {
                delta <= 30 || delta >= 330 -> false
                delta in 150..210 -> true
                else -> { clearCandidate(); return }
            }
            val target = if (horizontal) {
                if (reverse) ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
                else ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            } else {
                if (reverse) ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT
                else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            }
            if (target == preferred) { clearCandidate(); return }
            if (candidate == target) return
            clearCandidate()
            candidate = target
            pending = Runnable {
                if (foreground && landscape != null && candidate == target) {
                    preferred = target
                    clearCandidate()
                    apply()
                }
            }.also { handler.postDelayed(it, 700) }
        }
    }

    @Suppress("DEPRECATION")
    fun start(horizontal: Boolean) {
        if (landscape != horizontal) {
            val rotation = activity.windowManager.defaultDisplay.rotation
            val currentLandscape = activity.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
            naturalLandscape = if (rotation == Surface.ROTATION_0 || rotation == Surface.ROTATION_180) {
                currentLandscape
            } else !currentLandscape
            landscape = horizontal
            val reverse = rotation == Surface.ROTATION_180 || rotation == Surface.ROTATION_270
            preferred = if (horizontal) {
                if (reverse) ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            } else {
                if (reverse) ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            }
            clearCandidate()
            armedAt = SystemClock.uptimeMillis() + 1500
        }
        if (foreground) {
            apply()
            sensor.enable()
        }
    }

    private fun apply() {
        if (activity.requestedOrientation != preferred) activity.requestedOrientation = preferred
    }

    fun resume() {
        foreground = true
        clearCandidate()
        armedAt = SystemClock.uptimeMillis() + 1500
        if (landscape != null) {
            apply()
            sensor.enable()
        }
    }

    fun pause() {
        foreground = false
        clearCandidate()
        sensor.disable()
    }

    fun stop() {
        clearCandidate()
        sensor.disable()
        landscape = null
        preferred = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        apply()
    }
}
