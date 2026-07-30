# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Google Sign In
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Geolocator
-keep class com.baseflow.geolocator.** { *; }

# Flutter Blue Plus (BLE)
-keep class com.lib.flutter_blue_plus.** { *; }

# Play Core (deferred components)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Garmin Connect IQ
#
# QUESTE CLASSI ATTRAVERSANO IL CONFINE FRA DUE PROCESSI, quindi il loro NOME
# e' parte del protocollo e non si puo' offuscare.
#
# L'app Garmin Connect ci manda il broadcast DEVICE_STATUS con dentro un
# IQDevice: nel Parcel viaggia il nome originale della classe, e chi riceve
# deve caricare quel nome per ricostruire l'oggetto. Senza queste regole R8
# rinominava com.garmin.android.connectiq.IQDevice in n2.f e cancellava
# l'enum IQDeviceStatus, quindi il nostro processo cercava una classe che
# nel nostro APK non esisteva piu':
#
#   ClassNotFoundException: com.garmin.android.connectiq.IQDevice
#   -> BadParcelableException -> crash in IQMessageReceiver.onReceive
#
# Succedeva dalla 2.7.0 (SDK aggiunta il 2026-03-28) ma nessuno lo vedeva:
# Crashlytics e' arrivato solo con la 2.8.2. Non e' un problema di Motorola
# ne' di ottimizzazione batteria — quelle erano le ipotesi dell'analisi
# automatica, smentite dal file di mappatura della build.
-keep class com.garmin.android.connectiq.** { *; }
-keep class com.garmin.android.apps.connectmobile.connectiq.** { *; }
-keep class com.garmin.monkeybrains.** { *; }
-dontwarn com.garmin.**
