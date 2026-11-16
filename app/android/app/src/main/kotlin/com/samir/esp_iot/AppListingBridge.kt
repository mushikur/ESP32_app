package com.samir.esp_iot

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Opens a Google Play listing for a named application.
 *
 * Dart supplies only an application id, never a URL, so this channel cannot be
 * used to open an arbitrary address. The id is checked against the Android
 * package grammar before any intent is built.
 */
internal class AppListingBridge(
    private val activity: Activity,
    private val channel: MethodChannel,
) {
    init {
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "openListing") {
            result.notImplemented()
            return
        }
        val id = (call.arguments as? Map<*, *>)?.get("applicationId") as? String
        if (id == null || id.length > 255 || !applicationId.matches(id)) {
            result.error("invalidApplicationId", "The application id is invalid.", null)
            return
        }

        // The Play Store app handles market:// directly. Where it is absent or
        // disabled, the web listing opens in a browser instead.
        val targets = listOf(
            Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$id"))
                .setPackage("com.android.vending"),
            Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://play.google.com/store/apps/details?id=$id"),
            ),
        )
        for (intent in targets) {
            try {
                activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(null)
                return
            } catch (_: ActivityNotFoundException) {
                // Try the next way of reaching the listing.
            } catch (_: SecurityException) {
                // A restricted profile can refuse the store; fall through.
            }
        }
        result.error("storeUnavailable", "Google Play could not be opened.", null)
    }

    fun close() = channel.setMethodCallHandler(null)

    private companion object {
        val applicationId = Regex("^[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z][a-zA-Z0-9_]*)+$")
    }
}
