package com.hentaipark.hentai_park

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

object SubscriptionNotifications {
    fun send(context: Context, args: Map<*, *>): Boolean {
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!manager.areNotificationsEnabled()) return false
        val id = (args["id"] as Number).toInt()
        val channel = "subscriptions"
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(channel, args["channelName"] as? String ?: "订阅更新", NotificationManager.IMPORTANCE_DEFAULT))
            if (manager.getNotificationChannel(channel).importance == NotificationManager.IMPORTANCE_NONE) return false
        }
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_PAYLOAD, "subscriptions")
        }
        val pending = PendingIntent.getActivity(context, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channel) else Notification.Builder(context)
        manager.notify(id, builder.setSmallIcon(R.drawable.ic_launcher_fg)
            .setContentTitle(args["title"] as? String ?: "")
            .setContentText(args["text"] as? String ?: "")
            .setContentIntent(pending).setOnlyAlertOnce(true).setAutoCancel(true).build())
        return true
    }
}
