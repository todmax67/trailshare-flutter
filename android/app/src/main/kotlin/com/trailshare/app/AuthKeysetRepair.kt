package com.trailshare.app

import android.content.Context
import android.util.Log
import java.io.File
import java.security.KeyStore

/**
 * Ripara la sessione di Firebase Auth quando il suo lucchetto è rimasto orfano.
 *
 * ## Il guasto
 *
 * Su Android la sessione non è salvata in chiaro: è cifrata. La chiave che la
 * cifra vive in `shared_prefs/com.google.firebase.auth.api.crypto.<pk>.xml`, ed
 * è a sua volta protetta da una chiave dell'Android Keystore **legata al
 * dispositivo** — non esportabile, e distrutta dalla disinstallazione dell'app.
 *
 * Il backup automatico di Android salva e ripristina le SharedPreferences, ma
 * non può salvare la chiave del Keystore. Chi disinstalla e reinstalla si
 * ritrova quindi il file cifrato **senza più la chiave che lo apre**.
 *
 * E qui sta la parte cattiva: Firebase, quando non riesce ad aprirlo, non
 * solleva nessun errore. Restituisce `null` e prosegue — sia in lettura sia in
 * scrittura. L'utente resta slogato **a ogni apertura dell'app, per sempre**,
 * senza un messaggio, senza un crash, senza niente in Crashlytics. E lo stato
 * non si ripara da solo, perché Tink rigenera quel file solo quando **non
 * esiste**: quello rotto resta lì.
 *
 * Misurato sul campo il 2026-08-13, con l'unica traccia che il sistema lascia:
 * ```
 * E FirebearStorageCryptoHelper: Keystore cannot load the key with ID:
 *     firebear_main_key_id_for_storage_crypto.W0RFRkFVTFRd+MTo3NjA5...
 * E FirebearStorageCryptoHelper: KeysetManager failed to initialize
 *     - unable to decrypt data
 * ```
 *
 * ## La cura
 *
 * Togliere il lucchetto orfano prima che Firebase ci provi. Al primo accesso
 * successivo ne viene creato uno nuovo, con una chiave del Keystore nuova, e la
 * sessione torna a durare.
 *
 * ## Perché è prudente
 *
 * Si cancella **solo** se la chiave del Keystore corrispondente manca o non è
 * utilizzabile, cioè solo nello stato già rotto. Se la chiave c'è, non si tocca
 * niente: nel caso normale questo codice non fa nulla se non una lettura.
 *
 * Il costo di sbagliare è comunque limitato a un accesso da rifare, che è
 * esattamente ciò che l'utente sta già subendo a ogni avvio.
 *
 * Va chiamata **prima** che Firebase Auth venga usato per la prima volta, cioè
 * prima che il codice Dart parta: da `MainActivity.onCreate`, dove le
 * SharedPreferences non sono ancora state aperte da nessuno e cancellare il
 * file ha davvero effetto.
 *
 * La regola alla radice sta in `res/xml/backup_rules.xml` e
 * `res/xml/data_extraction_rules.xml`, che escludono quei file dal backup: da
 * lì in avanti il lucchetto orfano non si crea più. Questa classe serve a chi
 * ci è già finito dentro, e potrà essere tolta quando non ci sarà più nessuno
 * in quello stato.
 */
object AuthKeysetRepair {

    private const val TAG = "AuthKeysetRepair"
    private const val CRYPTO_PREFIX = "com.google.firebase.auth.api.crypto."
    private const val STORE_PREFIX = "com.google.firebase.auth.api.Store."
    private const val KEY_ALIAS_PREFIX = "firebear_main_key_id_for_storage_crypto."

    @JvmStatic
    fun repairIfOrphaned(context: Context) {
        try {
            val prefsDir = File(context.applicationInfo.dataDir, "shared_prefs")
            if (!prefsDir.isDirectory) return

            val cryptoFiles = prefsDir.listFiles { f ->
                f.isFile && f.name.startsWith(CRYPTO_PREFIX) && f.name.endsWith(".xml")
            } ?: return
            if (cryptoFiles.isEmpty()) return

            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

            for (cryptoFile in cryptoFiles) {
                val persistenceKey = cryptoFile.name
                    .removePrefix(CRYPTO_PREFIX)
                    .removeSuffix(".xml")
                val alias = KEY_ALIAS_PREFIX + persistenceKey

                // Non basta che l'alias esista: può esserci ed essere inservibile
                // (Keystore che rifiuta l'operazione, chiave invalidata dal
                // sistema). Il criterio è "riesco davvero a prenderla".
                val keyIsUsable = try {
                    keyStore.containsAlias(alias) && keyStore.getKey(alias, null) != null
                } catch (e: Exception) {
                    Log.w(TAG, "chiave presente ma inservibile per $persistenceKey: ${e.message}")
                    false
                }

                if (keyIsUsable) continue

                // Lucchetto senza chiave: si toglie, insieme alla sessione che
                // nessuno può più decifrare.
                val cryptoDeleted = cryptoFile.delete()
                val storeDeleted =
                    File(prefsDir, "$STORE_PREFIX$persistenceKey.xml").delete()
                Log.w(
                    TAG,
                    "keyset orfano rimosso (crypto=$cryptoDeleted store=$storeDeleted): " +
                        "la sessione non era più decifrabile, al prossimo accesso ne nasce una nuova"
                )
            }
        } catch (e: Exception) {
            // Non deve mai impedire l'avvio dell'app: nel peggiore dei casi si
            // resta nello stato di prima, che è quello che c'era comunque.
            Log.w(TAG, "verifica non riuscita: ${e.message}")
        }
    }
}
