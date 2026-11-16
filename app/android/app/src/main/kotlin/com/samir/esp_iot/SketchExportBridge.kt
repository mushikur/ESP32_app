package com.samir.esp_iot

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

internal class SketchExportBridge(
    private val activity: Activity,
    private val channel: MethodChannel,
) {
    private data class Save(val bytes: ByteArray, val result: MethodChannel.Result)

    private var pending: Save? = null
    private var writing = false

    init {
        channel.setMethodCallHandler(::handle)
    }

    @Suppress("DEPRECATION")
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "saveSketch") {
            result.notImplemented()
            return
        }
        if (pending != null) {
            result.error("busy", "A sketch save is already open.", null)
            return
        }
        val arguments = call.arguments as? Map<*, *>
        val name = arguments?.get("name") as? String
        val bytes = arguments?.get("bytes") as? ByteArray
        if (name == null || !sketchName.matches(name) || bytes == null || bytes.size !in 1..32768) {
            result.error("invalidSketch", "The sketch file is invalid.", null)
            return
        }

        val create = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // Arduino sketches have their own extension. A generic MIME type
            // keeps the system picker from appending a text-file extension.
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, name)
        }
        pending = Save(bytes, result)
        try {
            activity.startActivityForResult(create, requestCode)
        } catch (_: RuntimeException) {
            pending = null
            result.error("pickerUnavailable", "The Android save picker could not open.", null)
        }
    }

    fun onActivityResult(code: Int, resultCode: Int, data: Intent?) {
        if (code != requestCode || writing) return
        val save = pending ?: return
        if (resultCode != Activity.RESULT_OK) {
            pending = null
            save.result.success(false)
            return
        }
        val uri = data?.data
        if (uri == null || uri.scheme != ContentResolver.SCHEME_CONTENT) {
            pending = null
            save.result.error("invalidDestination", "Android returned no writable document.", null)
            return
        }

        writing = true
        val resolver = activity.applicationContext.contentResolver
        Thread({
            val written = try {
                val output = resolver.openOutputStream(uri, "wt") ?: throw IOException()
                output.use { it.write(save.bytes) }
                true
            } catch (_: IOException) {
                false
            } catch (_: RuntimeException) {
                false
            }
            activity.runOnUiThread {
                if (pending !== save) return@runOnUiThread
                pending = null
                writing = false
                if (written) {
                    save.result.success(true)
                } else {
                    save.result.error("writeFailed", "The sketch could not be written.", null)
                }
            }
        }, "esp-iot-sketch-export").start()
    }

    fun close() {
        channel.setMethodCallHandler(null)
        val save = pending
        pending = null
        save?.result?.error("saveInterrupted", "The sketch save was interrupted.", null)
    }

    private companion object {
        const val requestCode = 0x4e10
        val sketchName = Regex("[a-z][a-z0-9_]{1,39}\\.ino")
    }
}
