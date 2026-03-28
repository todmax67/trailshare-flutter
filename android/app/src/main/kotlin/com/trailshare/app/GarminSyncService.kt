package com.trailshare.app

import android.content.Context
import android.util.Log
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class GarminSyncService(private val context: Context) {

    companion object {
        private const val TAG = "GarminSync"
        // L'ID della tua app TrailShare sull'orologio (dal manifest.xml)
        private const val WATCH_APP_ID = "b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2"
    }

    private var connectIQ: ConnectIQ? = null
    private var connectedDevice: IQDevice? = null
    private var isInitialized = false
    private var eventSink: EventChannel.EventSink? = null

    // Buffer per ricostruire la traccia dai chunk
    private var trackHeader: Map<String, Any>? = null
    private var trackPoints: MutableList<Map<String, Any>> = mutableListOf()
    private var expectedChunks = 0
    private var receivedChunks = 0

    fun initialize() {
        try {
            connectIQ = ConnectIQ.getInstance(context, ConnectIQ.IQConnectType.WIRELESS)
            connectIQ?.initialize(context, true, object : ConnectIQ.ConnectIQListener {
                override fun onSdkReady() {
                    Log.d(TAG, "ConnectIQ SDK pronto")
                    isInitialized = true
                    findDevices()
                }

                override fun onInitializeError(status: ConnectIQ.IQSdkErrorStatus?) {
                    Log.e(TAG, "Errore init ConnectIQ: $status")
                    isInitialized = false
                }

                override fun onSdkShutDown() {
                    Log.d(TAG, "ConnectIQ SDK chiuso")
                    isInitialized = false
                }
            })
        } catch (e: Exception) {
            Log.e(TAG, "Errore inizializzazione: ${e.message}")
        }
    }

    private fun findDevices() {
        try {
            val devices = connectIQ?.knownDevices ?: return

            for (device in devices) {
                val status = connectIQ?.getDeviceStatus(device)
                Log.d(TAG, "Device: ${device.friendlyName}, Status: $status")

                if (status == IQDevice.IQDeviceStatus.CONNECTED) {
                    connectedDevice = device
                    Log.d(TAG, "Dispositivo connesso: ${device.friendlyName}")
                    registerForMessages(device)
                    break
                }
            }

            if (connectedDevice == null) {
                Log.d(TAG, "Nessun dispositivo Garmin connesso")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Errore ricerca dispositivi: ${e.message}")
        }
    }

    private fun registerForMessages(device: IQDevice) {
        try {
            val app = IQApp(WATCH_APP_ID)

            connectIQ?.registerForAppEvents(device, app) { _, _, data, _ ->
                if (data != null && data.isNotEmpty()) {
                    handleIncomingData(data[0])
                }
            }

            Log.d(TAG, "Registrato per messaggi dall'app $WATCH_APP_ID")
        } catch (e: Exception) {
            Log.e(TAG, "Errore registrazione messaggi: ${e.message}")
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun handleIncomingData(data: Any?) {
        if (data !is Map<*, *>) {
            Log.w(TAG, "Dati ricevuti non validi: $data")
            return
        }

        val dataMap = data as Map<String, Any>
        val type = dataMap["type"] as? String ?: return

        Log.d(TAG, "Ricevuto messaggio tipo: $type")

        when (type) {
            "trailshare_track" -> {
                // Header della traccia
                trackHeader = dataMap
                trackPoints.clear()
                expectedChunks = (dataMap["chunks"] as? Number)?.toInt() ?: 0
                receivedChunks = 0
                Log.d(TAG, "Header traccia ricevuto: ${dataMap["totalPoints"]} punti, $expectedChunks chunks")
                notifyFlutter("sync_started", dataMap)
            }

            "trailshare_chunk" -> {
                // Chunk di punti GPS
                val points = dataMap["points"] as? List<Map<String, Any>> ?: return
                trackPoints.addAll(points)
                receivedChunks++
                Log.d(TAG, "Chunk $receivedChunks/$expectedChunks ricevuto (${points.size} punti)")
                notifyFlutter("sync_progress", mapOf(
                    "received" to receivedChunks,
                    "total" to expectedChunks,
                    "pointsReceived" to trackPoints.size
                ))
            }

            "trailshare_end" -> {
                // Fine trasmissione - assembla la traccia completa
                Log.d(TAG, "Traccia completa: ${trackPoints.size} punti GPS")
                
                val completeTrack = mutableMapOf<String, Any>()
                trackHeader?.let { completeTrack.putAll(it) }
                
                // Converti punti da formato compatto a coordinate
                val decodedPoints = trackPoints.map { point ->
                    mapOf(
                        "latitude" to ((point["la"] as? Number)?.toDouble() ?: 0.0) / 100000.0,
                        "longitude" to ((point["lo"] as? Number)?.toDouble() ?: 0.0) / 100000.0,
                        "altitude" to ((point["al"] as? Number)?.toDouble() ?: 0.0)
                    )
                }
                
                completeTrack["points"] = decodedPoints
                completeTrack["type"] = "trailshare_complete"

                notifyFlutter("sync_complete", completeTrack)

                // Reset
                trackHeader = null
                trackPoints.clear()
                expectedChunks = 0
                receivedChunks = 0
            }
        }
    }

    private fun notifyFlutter(event: String, data: Map<String, Any>) {
        try {
            val payload = HashMap<String, Any>()
            payload["event"] = event
            payload.putAll(data)

            // Invia tramite EventChannel al main thread
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                eventSink?.success(payload)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Errore notifica Flutter: ${e.message}")
        }
    }

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    fun getStatus(): Map<String, Any> {
        return mapOf(
            "initialized" to isInitialized,
            "deviceConnected" to (connectedDevice != null),
            "deviceName" to (connectedDevice?.friendlyName ?: ""),
            "pointsBuffered" to trackPoints.size
        )
    }

    fun shutdown() {
        try {
            connectIQ?.shutdown(context)
        } catch (e: Exception) {
            Log.e(TAG, "Errore shutdown: ${e.message}")
        }
    }
}
