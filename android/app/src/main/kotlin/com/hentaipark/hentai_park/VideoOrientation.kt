package com.hentaipark.hentai_park

import android.app.Activity
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.view.OrientationEventListener
import android.view.Surface

/** Fullscreen keeps its selected axis, including reverse portrait on phones. */
class VideoOrientation(private val activity: Activity) {
    private var landscape: Boolean? = null
    private var foreground = true
    private var naturalLandscape = false
    private var preferred = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    private var lastAngle = OrientationEventListener.ORIENTATION_UNKNOWN
    private val sensor = object : OrientationEventListener(activity) {
        override fun onOrientationChanged(angle: Int) {
            lastAngle = angle
            val horizontal = landscape ?: return
            if (!foreground || angle == ORIENTATION_UNKNOWN) return
            val normal = if (horizontal) {
                if (naturalLandscape) 0 else 270
            } else {
                if (naturalLandscape) 270 else 0
            }
            val delta = (angle - normal + 360) % 360
            val reverse = when {
                delta <= 60 || delta >= 300 -> false
                delta in 120..240 -> true
                else -> return // Keep the current side near axis boundaries.
            }
            preferred = if (horizontal) {
                if (reverse) ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
                else ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            } else {
                if (reverse) ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT
                else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            }
            apply()
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
            // Sensor fallback for devices without a working orientation listener.
            preferred = if (horizontal) ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            else ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
        }
        if (foreground) {
            apply()
            sensor.enable()
            sensor.onOrientationChanged(lastAngle)
        }
    }

    private fun apply() {
        if (activity.requestedOrientation != preferred) activity.requestedOrientation = preferred
    }

    fun resume() {
        foreground = true
        if (landscape != null) {
            apply()
            sensor.enable()
        }
    }

    fun pause() {
        foreground = false
        sensor.disable()
    }

    fun stop() {
        sensor.disable()
        landscape = null
        preferred = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        apply()
    }
}
