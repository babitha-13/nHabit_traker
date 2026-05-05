package com.example.untitled

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AlarmVibrationPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "alarm_notification_dismiss")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "patchDeleteIntent") {
            val notificationId = call.argument<Int>("notificationId")
            if (notificationId == null) {
                result.error("INVALID_ARG", "notificationId required", null)
                return
            }
            result.success(patchNotificationDeleteIntent(notificationId))
        } else {
            result.notImplemented()
        }
    }

    private fun patchNotificationDeleteIntent(notificationId: Int): Boolean {
        // recoverBuilder requires API 24+; older devices fall back to finite vibration pattern
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        return try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val sbn = nm.activeNotifications.find { it.id == notificationId } ?: return false

            val intent = Intent(context, DismissAlarmReceiver::class.java)
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            else
                PendingIntent.FLAG_UPDATE_CURRENT

            val deleteIntent = PendingIntent.getBroadcast(context, notificationId, intent, flags)

            @Suppress("DEPRECATION")
            val notification = Notification.Builder.recoverBuilder(context, sbn.notification)
                .setDeleteIntent(deleteIntent)
                .build()

            nm.notify(sbn.tag, notificationId, notification)
            true
        } catch (_: Exception) {
            false
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
