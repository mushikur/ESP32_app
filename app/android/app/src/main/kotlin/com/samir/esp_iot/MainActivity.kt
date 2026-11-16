package com.samir.esp_iot

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var discovery: LocalDiscoveryBridge? = null
    private var sketchExport: SketchExportBridge? = null
    private var appListing: AppListingBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "esp_iot/local_discovery")
        discovery = LocalDiscoveryBridge(applicationContext, channel)
        sketchExport = SketchExportBridge(
            this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "esp_iot/learn_export"),
        )
        appListing = AppListingBridge(
            this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "esp_iot/app_listing"),
        )
    }

    @Deprecated("Receives the Android document picker result for FlutterActivity.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        sketchExport?.onActivityResult(requestCode, resultCode, data)
    }

    override fun onStop() {
        discovery?.cancelAll()
        super.onStop()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        discovery?.close()
        discovery = null
        sketchExport?.close()
        sketchExport = null
        appListing?.close()
        appListing = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
