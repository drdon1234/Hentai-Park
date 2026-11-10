package com.hentaipark.hentai_park

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.media.session.MediaSession
import android.media.session.PlaybackState
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel

/** 前台服务仅维持已打开的音声播放会话，不保存媒体地址或作品信息。 */
class VoicePlaybackService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var mediaSession: MediaSession? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == CONTROL) {
            val id = intent.getStringExtra("id")
            val action = intent.getStringExtra("command")
            if (id != null && action != null && available.contains(id)) controls[id]?.invoke(action)
            return START_NOT_STICKY
        }
        launching = false
        if (leases.isEmpty()) {
            stopping = true
            stopSelf()
            finishWaiting(false)
            return START_NOT_STICKY
        }
        try {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(NotificationChannel(CHANNEL, notificationText, NotificationManager.IMPORTANCE_LOW))
            }
            if (mediaSession == null) {
                mediaSession = MediaSession(this, "HentaiParkVoice").apply {
                    @Suppress("DEPRECATION")
                    setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
                    setCallback(object : MediaSession.Callback() {
                        override fun onPlay() = dispatch("play")
                        override fun onPause() = dispatch("pause")
                        override fun onStop() = dispatch("stop")
                    })
                    setSessionActivity(PendingIntent.getActivity(this@VoicePlaybackService, NOTIFICATION_ID,
                        Intent(this@VoicePlaybackService, MainActivity::class.java),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                }
            }
            updateMediaState()
            startForeground(NOTIFICATION_ID, notification())
            current = this
            updateWakeLock()
            finishWaiting(true)
        } catch (_: Exception) {
            leases.clear()
            playing.clear()
            available.clear()
            controls.clear()
            finishWaiting(false)
            stopping = true
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (current === this) current = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        mediaSession?.release()
        mediaSession = null
        if (stopping) {
            stopping = false
            if (leases.isNotEmpty()) launch(applicationContext) else finishWaiting(false)
        } else {
            leases.clear()
            playing.clear()
            available.clear()
            controls.clear()
            finishWaiting(false)
        }
        super.onDestroy()
    }

    private fun selectedLease(): String? = available.lastOrNull { playing.contains(it) } ?: available.lastOrNull()

    private fun dispatch(action: String) {
        selectedLease()?.let { controls[it]?.invoke(action) }
    }

    private fun updateMediaState() {
        val id = selectedLease()
        val active = id != null
        val isPlaying = id != null && playing.contains(id)
        mediaSession?.setPlaybackState(PlaybackState.Builder()
            .setActions(if (active) PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_STOP else 0L)
            .setState(if (!active) PlaybackState.STATE_NONE else if (isPlaying) PlaybackState.STATE_PLAYING
                else PlaybackState.STATE_PAUSED, PlaybackState.PLAYBACK_POSITION_UNKNOWN, if (isPlaying) 1f else 0f)
            .build())
        mediaSession?.isActive = active
    }

    @Suppress("DEPRECATION")
    private fun notification(): Notification {
        val open = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pending = PendingIntent.getActivity(this, NOTIFICATION_ID, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = (if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this))
            .setSmallIcon(R.drawable.ic_launcher_fg)
            .setContentTitle("HentaiPark")
            .setContentText(notificationText)
            .setContentIntent(pending)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
        val style = Notification.MediaStyle().setMediaSession(mediaSession?.sessionToken)
        selectedLease()?.let { id ->
            val isPlaying = playing.contains(id)
            val action = if (isPlaying) "pause" else "play"
            val intent = Intent(this, VoicePlaybackService::class.java).setAction(CONTROL)
                .putExtra("id", id).putExtra("command", action)
            val control = PendingIntent.getService(this, NOTIFICATION_ID, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            builder.addAction(if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (isPlaying) pauseLabel else playLabel, control)
            style.setShowActionsInCompactView(0)
        }
        return builder.setStyle(style).build()
    }

    private fun updatePlayback() {
        updateWakeLock()
        updateMediaState()
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIFICATION_ID, notification())
    }

    private fun updateWakeLock() {
        if (playing.isEmpty()) {
            wakeLock?.let { if (it.isHeld) it.release() }
            wakeLock = null
        } else if (wakeLock == null) {
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "HentaiPark:voice").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    companion object {
        private const val CHANNEL = "voice_playback"
        private const val NOTIFICATION_ID = 3002
        private const val CONTROL = "com.hentaipark.hentai_park.VOICE_CONTROL"
        private val leases = mutableSetOf<String>()
        private val playing = mutableSetOf<String>()
        private val available = mutableSetOf<String>()
        private val controls = mutableMapOf<String, (String) -> Unit>()
        private val waiting = mutableListOf<MethodChannel.Result>()
        private var current: VoicePlaybackService? = null
        private var launching = false
        private var stopping = false
        private var notificationText = "HentaiPark"
        private var playLabel = ""
        private var pauseLabel = ""

        private fun finishWaiting(started: Boolean) {
            val results = waiting.toList()
            waiting.clear()
            results.forEach { it.success(started) }
        }

        fun start(context: Context, id: String, text: String, play: String, pause: String,
            result: MethodChannel.Result, control: (String) -> Unit) {
            leases.add(id)
            controls[id] = control
            notificationText = text
            playLabel = play
            pauseLabel = pause
            if (current != null && !stopping) {
                result.success(true)
                return
            }
            waiting.add(result)
            if (!stopping) launch(context)
        }

        private fun launch(context: Context) {
            if (launching) return
            launching = true
            try {
                ContextCompat.startForegroundService(context, Intent(context, VoicePlaybackService::class.java).putExtra("text", notificationText))
            } catch (_: Exception) {
                launching = false
                leases.clear()
                playing.clear()
                available.clear()
                controls.clear()
                finishWaiting(false)
            }
        }

        fun stop(context: Context, id: String) {
            leases.remove(id)
            playing.remove(id)
            available.remove(id)
            controls.remove(id)
            current?.updatePlayback()
            if (leases.isEmpty() && current != null && !stopping) {
                stopping = true
                if (!context.stopService(Intent(context, VoicePlaybackService::class.java))) {
                    stopping = false
                    current = null
                    finishWaiting(false)
                }
            }
        }

        fun stopAll(context: Context) {
            leases.toList().forEach { stop(context, it) }
        }

        fun setPlaying(id: String, value: Boolean, canControl: Boolean) {
            if (!leases.contains(id)) return
            if (canControl) available.add(id) else available.remove(id)
            if (value && canControl) playing.add(id) else playing.remove(id)
            current?.updatePlayback()
        }
    }
}
