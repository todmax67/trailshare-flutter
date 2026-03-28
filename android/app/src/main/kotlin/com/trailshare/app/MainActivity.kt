package com.trailshare.app

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private val METHOD_CHANNEL = "com.trailshare.app/garmin"
    private val EVENT_CHANNEL = "com.trailshare.app/garmin_events"

    private var garminService: GarminSyncService? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        garminService = GarminSyncService(this)

        // MethodChannel per comandi (init, status, shutdown)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    garminService?.initialize()
                    result.success(true)
                }
                "getStatus" -> {
                    result.success(garminService?.getStatus())
                }
                "shutdown" -> {
                    garminService?.shutdown()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // EventChannel per eventi in arrivo dall'orologio
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    garminService?.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    garminService?.setEventSink(null)
                }
            }
        )
    }

    override fun onDestroy() {
        garminService?.shutdown()
        super.onDestroy()
    }
}
