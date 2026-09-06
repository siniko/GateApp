package com.example.gatecontrol

import android.Manifest
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.telephony.SmsManager
import android.widget.RemoteViews
import android.widget.Toast
import androidx.core.content.ContextCompat

class GateWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        updateWidgets(context, appWidgetManager, appWidgetIds)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        when (intent.action) {
            ACTION_OPEN -> sendGateSms(context, GatePreferences.getOpenCommand(context), "Opening gate")
            ACTION_CLOSE -> sendGateSms(context, GatePreferences.getCloseCommand(context), "Closing gate")
        }
    }

    private fun sendGateSms(context: Context, command: String, confirmation: String) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
            Toast.makeText(context, "Open Gate Control and allow SMS permission", Toast.LENGTH_LONG).show()
            return
        }

        if (GatePreferences.usesContact(context) &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED
        ) {
            Toast.makeText(context, "Open Gate Control and allow Contacts permission", Toast.LENGTH_LONG).show()
            return
        }

        val number = try {
            GateContactResolver.resolvePhoneNumber(context)
        } catch (e: SecurityException) {
            null
        }

        if (number.isNullOrBlank()) {
            Toast.makeText(context, "Gate phone number could not be found", Toast.LENGTH_LONG).show()
            return
        }

        try {
            val smsManager = context.getSystemService(SmsManager::class.java)
            smsManager.sendTextMessage(number, null, command, null, null)
            GatePreferences.setPhoneNumber(context, number)
            Toast.makeText(context, "$confirmation ✓", Toast.LENGTH_SHORT).show()
        } catch (e: Exception) {
            Toast.makeText(context, "SMS failed: ${e.message ?: "Unknown error"}", Toast.LENGTH_LONG).show()
        }
    }

    companion object {
        private const val ACTION_OPEN = "com.example.gatecontrol.ACTION_OPEN"
        private const val ACTION_CLOSE = "com.example.gatecontrol.ACTION_CLOSE"

        fun updateWidgets(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetIds: IntArray
        ) {
            appWidgetIds.forEach { widgetId ->
                val views = RemoteViews(context.packageName, R.layout.gate_widget)

                val openIntent = Intent(context, GateWidgetProvider::class.java).apply {
                    action = ACTION_OPEN
                }
                val closeIntent = Intent(context, GateWidgetProvider::class.java).apply {
                    action = ACTION_CLOSE
                }

                val openPendingIntent = PendingIntent.getBroadcast(
                    context,
                    1001,
                    openIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                val closePendingIntent = PendingIntent.getBroadcast(
                    context,
                    1002,
                    closeIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                views.setOnClickPendingIntent(R.id.openButton, openPendingIntent)
                views.setOnClickPendingIntent(R.id.closeButton, closePendingIntent)

                appWidgetManager.updateAppWidget(widgetId, views)
            }
        }
    }
}
