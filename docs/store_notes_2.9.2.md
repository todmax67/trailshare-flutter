# Note release 2.9.2+111 per gli store — SOLO ANDROID

Correzione di un blocco, niente funzioni nuove. La 2.9.1+110 e' gia' approvata
e pubblicata su entrambi gli store: **l'IPA non va ricaricato**, la SDK Garmin
Connect IQ esiste solo su Android e iOS non e' toccato. Su App Store Connect
resta la 2.9.1+110.

## Cosa succedeva

L'app Garmin Connect manda un broadcast `DEVICE_STATUS` con dentro un oggetto
`IQDevice`. Nel Parcel viaggia il NOME della classe, e chi riceve deve caricare
quel nome per ricostruire l'oggetto: quel nome attraversa il confine fra due
processi, quindi fa parte del protocollo e non si puo' offuscare.

In `proguard-rules.pro` c'erano regole per Flutter, Firebase, Google Sign-In,
geolocator, BLE e Play Core — nessuna per Garmin. R8 rinominava la classe e
cancellava l'enum dello stato:

```
com.garmin.android.connectiq.IQDevice                -> n2.f
com.garmin.android.connectiq.IQDevice$IQDeviceStatus -> R8$$REMOVED$$CLASS$$419
```

Il processo cercava `com.garmin.android.connectiq.IQDevice`, trovava solo
`n2.f`, e finiva in ClassNotFoundException -> BadParcelableException -> crash.

Presente dalla **2.7.0** (SDK aggiunta il 2026-03-28). Invisibile fino alla
2.8.2, la release in cui e' entrato Crashlytics.

## Play Console — "Novità in questa versione" (IT)

```
Risolto un blocco che poteva chiudere l'app da sola quando un orologio Garmin abbinato si connetteva o si disconnetteva.
```

## EN

```
Fixed a crash that could close the app on its own when a paired Garmin watch connected or disconnected.
```

## Perche' non se n'era accorto nessuno

Quattro strati, ognuno sufficiente da solo a nascondere il problema:

1. **In debug non succede.** Non c'e' un blocco `debug` in build.gradle, quindi
   `minifyEnabled` e' false: senza offuscamento la classe conserva il suo nome
   e il crash non puo' avvenire. Tutto il ciclo di sviluppo — `flutter run`,
   le prove sul Motorola collegato via USB — era immune per costruzione.
2. **Il sintomo e' identico al comportamento normale di Android.** Un'app che
   sparisce dal background e' esattamente cio' che i telefoni fanno per
   risparmiare batteria. Il crash aveva una spiegazione innocente gia' pronta,
   e infatti anche l'analisi automatica di Firebase ci e' cascata: proponeva
   ottimizzazione batteria Motorola, Direct Boot e restrizioni Android 16.
3. **Serve una combinazione rara**: app Garmin Connect installata, orologio
   abbinato, SDK inizializzata, e un cambio di stato dell'orologio.
4. **Nessuno lo riportava.** Crashlytics e' arrivato solo con la 2.8.2.

## Il file che ha deciso la questione

`build/app/outputs/mapping/release/mapping.txt`. Quando un crash dice
`ClassNotFoundException` su una classe di libreria in una build offuscata, quello
e' il primo posto dove guardare: o la classe c'e' col suo nome, o non c'e'.
Dopo la correzione: 57 classi `com.garmin` nel mapping, **zero offuscate**.

## Regola da ricordare

Le classi che attraversano un confine fra processi — Parcelable in un Intent,
AIDL, Serializable in un Bundle — vanno tenute per nome in ProGuard. Vale per
qualsiasi SDK di terze parti che riceva broadcast da un'altra app. I receiver
dichiarati nel manifest sono gia' salvi (R8 li tiene da solo): il pericolo sono
quelli registrati a runtime, come questo, che nel manifest unito non compaiono.
