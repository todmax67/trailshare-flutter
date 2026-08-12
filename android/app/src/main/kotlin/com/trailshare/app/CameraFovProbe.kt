package com.trailshare.app

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.util.SizeF
import kotlin.math.atan
import kotlin.math.max

/**
 * Campo visivo reale della fotocamera posteriore, letto dall'hardware.
 *
 * Serve al Mountain Finder: per sovrapporre le etichette alle montagne bisogna
 * sapere quanti gradi di mondo entrano nell'inquadratura, e finora era un
 * valore medio scritto a tavolino (60°×80°) mai verificato su questo
 * dispositivo. Ogni grado di errore sposta le etichette di circa l'1,7% della
 * larghezza dello schermo.
 *
 * Il calcolo è quello della lente sottile: metà sensore diviso la focale dà la
 * tangente del semiangolo. Restituisce il campo del **fotogramma pieno del
 * sensore**, nell'orientamento nativo (orizzontale): il ritaglio della preview
 * lo applica il lato Dart, che è l'unico a sapere come è composta a schermo.
 */
object CameraFovProbe {

    fun backCameraFieldOfView(context: Context): Map<String, Any>? {
        return try {
            val manager =
                context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val id = manager.cameraIdList.firstOrNull { candidate ->
                manager.getCameraCharacteristics(candidate)
                    .get(CameraCharacteristics.LENS_FACING) ==
                    CameraCharacteristics.LENS_FACING_BACK
            } ?: return null

            val chars = manager.getCameraCharacteristics(id)
            val size: SizeF =
                chars.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE) ?: return null
            val focals =
                chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
            // Su un multi-camera la lista contiene più focali: la principale è
            // la più corta, cioè quella con il campo più largo. Le altre sono
            // teleobiettivi che la preview non usa a zoom 1x.
            val focal = focals?.minOrNull() ?: return null
            if (focal <= 0f || size.width <= 0f || size.height <= 0f) return null

            val horizontal = 2.0 * atan((size.width / (2.0 * focal))) * 180.0 / Math.PI
            val vertical = 2.0 * atan((size.height / (2.0 * focal))) * 180.0 / Math.PI
            if (horizontal <= 1 || vertical <= 1) return null

            mapOf(
                // Il fotogramma nativo è orizzontale: il lato lungo del sensore
                // corrisponde al campo maggiore.
                "horizontalDeg" to max(horizontal, vertical),
                "verticalDeg" to minOf(horizontal, vertical),
                "focalMm" to focal.toDouble(),
                "sensorMm" to "${size.width}x${size.height}"
            )
        } catch (e: Exception) {
            null
        }
    }
}
