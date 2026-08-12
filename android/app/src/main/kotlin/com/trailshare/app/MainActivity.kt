package com.trailshare.app

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private val METHOD_CHANNEL = "com.trailshare.app/garmin"
    private val EVENT_CHANNEL = "com.trailshare.app/garmin_events"
    private val ATTITUDE_METHOD_CHANNEL = "com.trailshare.app/attitude"
    private val ATTITUDE_EVENT_CHANNEL = "com.trailshare.app/attitude_events"

    private var garminService: GarminSyncService? = null
    private var attitudeChannel: DeviceAttitudeChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        garminService = GarminSyncService(this)
        configureAttitude(flutterEngine)

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

    /**
     * Orientamento del telefono per l'AR del Mountain Finder (vedi
     * [DeviceAttitudeChannel]). MethodChannel per comunicare la posizione
     * (serve alla declinazione magnetica) e sapere se il sensore c'è,
     * EventChannel per lo stream dell'assetto.
     */
    private fun configureAttitude(flutterEngine: FlutterEngine) {
        val channel = DeviceAttitudeChannel(this)
        attitudeChannel = channel

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ATTITUDE_METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(channel.isAvailable)
                // Campo visivo reale dell'obiettivo: vive qui e non in un
                // canale a parte perche' e' una sola lettura, e serve alla
                // stessa schermata dell'assetto.
                "getCameraFov" ->
                    result.success(CameraFovProbe.backCameraFieldOfView(this))
                "setLocation" -> {
                    val lat = call.argument<Double>("latitude")
                    val lng = call.argument<Double>("longitude")
                    val alt = call.argument<Double>("altitude") ?: 0.0
                    if (lat == null || lng == null) {
                        result.error("bad_args", "latitude/longitude mancanti", null)
                    } else {
                        // Torna la declinazione applicata: così Dart può
                        // verificarla senza leggere i log nativi.
                        result.success(channel.setLocation(lat, lng, alt))
                    }
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ATTITUDE_EVENT_CHANNEL
        ).setStreamHandler(channel)
    }

    override fun onDestroy() {
        garminService?.shutdown()
        attitudeChannel?.onCancel(null)
        super.onDestroy()
    }
}
