package com.example.gatecontrol

import android.content.Context

object GatePreferences {
    private const val PREFS_NAME = "gate_control_preferences"
    private const val KEY_PHONE_NUMBER = "gate_phone_number"
    private const val KEY_OPEN_COMMAND = "gate_open_command"
    private const val KEY_CLOSE_COMMAND = "gate_close_command"
    private const val KEY_CONTACT_LOOKUP_KEY = "gate_contact_lookup_key"
    private const val KEY_CONTACT_PHONE_DATA_ID = "gate_contact_phone_data_id"
    private const val KEY_CONTACT_NAME = "gate_contact_name"

    fun getPhoneNumber(context: Context): String = prefs(context)
        .getString(KEY_PHONE_NUMBER, "")?.trim().orEmpty()

    fun setPhoneNumber(context: Context, number: String) {
        prefs(context).edit().putString(KEY_PHONE_NUMBER, number.trim()).apply()
    }

    fun getOpenCommand(context: Context): String = prefs(context)
        .getString(KEY_OPEN_COMMAND, "2011#ON#")?.trim().orEmpty().ifBlank { "2011#ON#" }

    fun setOpenCommand(context: Context, command: String) {
        prefs(context).edit().putString(KEY_OPEN_COMMAND, command.trim()).apply()
    }

    fun getCloseCommand(context: Context): String = prefs(context)
        .getString(KEY_CLOSE_COMMAND, "2011#OFF#")?.trim().orEmpty().ifBlank { "2011#OFF#" }

    fun setCloseCommand(context: Context, command: String) {
        prefs(context).edit().putString(KEY_CLOSE_COMMAND, command.trim()).apply()
    }

    fun setContact(context: Context, lookupKey: String, phoneDataId: Long, displayName: String) {
        prefs(context).edit()
            .putString(KEY_CONTACT_LOOKUP_KEY, lookupKey)
            .putLong(KEY_CONTACT_PHONE_DATA_ID, phoneDataId)
            .putString(KEY_CONTACT_NAME, displayName)
            .apply()
    }

    fun clearContact(context: Context) {
        prefs(context).edit()
            .remove(KEY_CONTACT_LOOKUP_KEY)
            .remove(KEY_CONTACT_PHONE_DATA_ID)
            .remove(KEY_CONTACT_NAME)
            .apply()
    }

    fun getContactLookupKey(context: Context): String = prefs(context)
        .getString(KEY_CONTACT_LOOKUP_KEY, "").orEmpty()

    fun getContactPhoneDataId(context: Context): Long = prefs(context)
        .getLong(KEY_CONTACT_PHONE_DATA_ID, -1L)

    fun getContactName(context: Context): String = prefs(context)
        .getString(KEY_CONTACT_NAME, "").orEmpty()

    fun usesContact(context: Context): Boolean = getContactLookupKey(context).isNotBlank()

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
