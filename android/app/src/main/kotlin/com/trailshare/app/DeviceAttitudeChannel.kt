package com.trailshare.app

import android.app.Activity
import android.content.Context
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.SystemClock
import android.view.Surface
import android.view.WindowManager
import io.flutter.plugin.common.EventChannel
import kotlin.math.cos
import kotlin.math.sin

/**
 * Orientamento completo del telefono per l'AR del Mountain Finder.
 *
 * Perché non basta una bussola: per sovrapporre le etichette alle montagne
 * serve sapere dove punta **l'obiettivo posteriore** e come è ruotato il
 * telefono attorno all'asse ottico. Una bussola dà un solo angolo — quello del
 * bordo alto del telefono — e l'accelerometro da solo dà un pitch che sbanda
 * appena ci si muove. Qui usiamo TYPE_ROTATION_VECTOR, cioè la sensor fusion
 * del sistema (giroscopio + accelerometro + magnetometro), che restituisce
 * l'assetto completo.
 *
 * Verso Dart mandiamo la matrice di rotazione **device → ENU** (Est, Nord, Su)
 * row-major, già corretta al **nord geografico**: la conversione in
 * azimut/pitch/roll e la proiezione stanno in Dart, dove si possono testare.
 *
 * Nota sul nord: TYPE_ROTATION_VECTOR è riferito al nord **magnetico**, che
 * nelle Alpi dista 3,5-4,5° da quello geografico — con FOV 60° sono circa 70 px
 * di sfasamento costante di tutte le etichette. La correzione la calcola
 * [GeomagneticField] (modello WMM di sistema), e richiede la posizione: il lato
 * Dart la comunica con `setLocation` a ogni fix GPS significativo.
 */
class DeviceAttitudeChannel(private val activity: Activity) :
    EventChannel.StreamHandler, SensorEventListener {

    private val sensorManager =
        activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val rotationSensor: Sensor? =
        sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)

    private var eventSink: EventChannel.EventSink? = null

    private val rotationMatrix = FloatArray(9)
    private val rotationVector = FloatArray(4)
    private val enuMatrix = DoubleArray(9)

    /** Declinazione magnetica in gradi (positiva a est). Null finché non arriva un fix. */
    private var declinationDeg: Double? = null

    /** Incertezza stimata sulla bussola, in gradi. Null = inaffidabile. */
    private var accuracyDeg: Double? = null

    /** ~30 Hz: oltre non si guadagna nulla e si spreca banda sul channel. */
    private var nextEmitAtMs = 0L

    /** True se il sensore di fusione esiste su questo dispositivo. */
    val isAvailable: Boolean get() = rotationSensor != null

    /**
     * Posizione corrente, per il calcolo della declinazione magnetica.
     * Va richiamata quando l'utente si sposta in modo significativo: la
     * declinazione varia di circa 1° ogni 100-150 km, quindi qualche chilometro
     * non cambia nulla.
     */
    /// Restituisce la declinazione applicata, così il lato Dart può
    /// verificarla senza dover leggere i log nativi.
    fun setLocation(latitude: Double, longitude: Double, altitude: Double): Double {
        val declination = GeomagneticField(
            latitude.toFloat(),
            longitude.toFloat(),
            altitude.toFloat(),
            System.currentTimeMillis()
        ).declination.toDouble()
        declinationDeg = declination
        return declination
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        val sensor = rotationSensor
        if (sensor == null) {
            events?.error("no_sensor", "TYPE_ROTATION_VECTOR non disponibile", null)
            return
        }
        sensorManager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)
    }

    override fun onCancel(arguments: Any?) {
        sensorManager.unregisterListener(this)
        eventSink = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_ROTATION_VECTOR) return

        val now = SystemClock.elapsedRealtime()
        if (now < nextEmitAtMs) return
        nextEmitAtMs = now + 33

        // Alcuni dispositivi riportano 5 valori invece di 4 e
        // getRotationMatrixFromVector va in errore: copiamo solo i primi 4.
        val size = if (event.values.size > 4) 4 else event.values.size
        System.arraycopy(event.values, 0, rotationVector, 0, size)
        SensorManager.getRotationMatrixFromVector(
            rotationMatrix,
            if (event.values.size > 4) rotationVector else event.values
        )

        // getRotationMatrixFromVector restituisce una matrice device → mondo con
        // X = est, Y = nord MAGNETICO, Z = su, applicata come v_mondo = R · v_device.
        // Ruotiamo attorno alla verticale per portarla al nord geografico.
        val decl = declinationDeg
        if (decl == null) {
            for (i in 0..8) enuMatrix[i] = rotationMatrix[i].toDouble()
        } else {
            val d = Math.toRadians(decl)
            val c = cos(d)
            val s = sin(d)
            // Un vettore di componenti magnetiche (E,N) ha bearing geografico
            // maggiore di `decl`: E' = E·cos + N·sin, N' = -E·sin + N·cos.
            for (col in 0..2) {
                val e = rotationMatrix[col].toDouble()          // riga 0 = Est
                val n = rotationMatrix[3 + col].toDouble()      // riga 1 = Nord
                enuMatrix[col] = c * e + s * n
                enuMatrix[3 + col] = -s * e + c * n
                enuMatrix[6 + col] = rotationMatrix[6 + col].toDouble() // Su invariato
            }
        }

        eventSink?.success(
            hashMapOf(
                "m" to enuMatrix.toList(),
                "screenRotation" to screenRotationDeg(),
                "accuracy" to accuracyDeg,
                "trueNorth" to (decl != null)
            )
        )
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Android non espone un'incertezza in gradi: traduciamo i quattro
        // livelli in valori indicativi, che servono solo a decidere quando
        // suggerire all'utente di calibrare la bussola.
        accuracyDeg = when (accuracy) {
            SensorManager.SENSOR_STATUS_ACCURACY_HIGH -> 5.0
            SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM -> 15.0
            SensorManager.SENSOR_STATUS_ACCURACY_LOW -> 30.0
            else -> null // UNRELIABLE / NO_CONTACT
        }
    }

    /**
     * Rotazione della UI rispetto all'orientamento naturale del dispositivo.
     * Serve a Dart per sapere quale asse del device è "destra dello schermo":
     * in landscape non è più l'asse X, e i due landscape sono opposti fra loro.
     */
    private fun screenRotationDeg(): Int {
        val rotation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display?.rotation ?: Surface.ROTATION_0
        } else {
            @Suppress("DEPRECATION")
            (activity.getSystemService(Context.WINDOW_SERVICE) as WindowManager)
                .defaultDisplay.rotation
        }
        return when (rotation) {
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
    }
}
