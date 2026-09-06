package com.example.gatecontrol

import android.content.Context
import android.provider.ContactsContract

object GateContactResolver {

    /**
     * Resolves the phone number from the Contacts database each time a widget action is used.
     * This means editing the saved gate contact's phone number is enough; the app does not
     * need to be reconfigured in the common case.
     */
    fun resolvePhoneNumber(context: Context): String? {
        if (!GatePreferences.usesContact(context)) return GatePreferences.getPhoneNumber(context).ifBlank { null }

        val resolver = context.contentResolver
        val lookupKey = GatePreferences.getContactLookupKey(context)
        val preferredDataId = GatePreferences.getContactPhoneDataId(context)

        // First try the exact phone row originally chosen. If the number was edited in-place,
        // this returns the new value while preserving which phone entry was selected.
        if (preferredDataId >= 0) {
            resolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.NUMBER,
                    ContactsContract.CommonDataKinds.Phone.LOOKUP_KEY
                ),
                "${ContactsContract.CommonDataKinds.Phone._ID}=?",
                arrayOf(preferredDataId.toString()),
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val rowLookup = cursor.getString(1).orEmpty()
                    if (rowLookup == lookupKey) {
                        return cursor.getString(0)?.trim()?.takeIf { it.isNotBlank() }
                    }
                }
            }
        }

        // Fallback: the phone row may have been deleted/recreated while editing the contact.
        // Resolve the contact using its stable lookup key and use its first current phone number.
        resolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Phone._ID,
                ContactsContract.CommonDataKinds.Phone.NUMBER
            ),
            "${ContactsContract.CommonDataKinds.Phone.LOOKUP_KEY}=?",
            arrayOf(lookupKey),
            "${ContactsContract.CommonDataKinds.Phone.IS_SUPER_PRIMARY} DESC, " +
                "${ContactsContract.CommonDataKinds.Phone.IS_PRIMARY} DESC"
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val newDataId = cursor.getLong(0)
                val number = cursor.getString(1)?.trim()?.takeIf { it.isNotBlank() }
                if (number != null) {
                    GatePreferences.setContact(
                        context,
                        lookupKey,
                        newDataId,
                        GatePreferences.getContactName(context)
                    )
                    return number
                }
            }
        }

        return null
    }
}
