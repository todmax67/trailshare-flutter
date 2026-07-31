# Note release 2.9.5+114 per gli store

Una riga sola: i font dell'app non si scaricano più.

Fino alla 2.9.4 la tipografia arrivava da `fonts.gstatic.com` alla prima
apertura, tramite il pacchetto `google_fonts`. Su un'app da montagna è un
difetto che si vede subito: nei report Crashlytics della 2.9.4, pubblicata
poche ore prima, il fallimento è comparso il giorno stesso.

Chi installa a casa e apre l'app in rifugio senza rete vedeva l'interfaccia
con il font di sistema invece del nostro. Non era un crash — un non-fatal — ma
è esattamente il caso d'uso che l'app pubblicizza.

## Play Console / App Store Connect — "Novità in questa versione" (IT)

```
I caratteri dell'app ora sono inclusi nell'installazione invece di essere scaricati alla prima apertura.

Se apri TrailShare senza rete — in rifugio, in quota, in aereo — l'interfaccia si vede come deve, non con i caratteri di sistema.
```

## EN

```
The app's fonts now ship with the install instead of being downloaded on first launch.

If you open TrailShare with no connection — in a mountain hut, at altitude, on a plane — the interface looks the way it should, not like a system fallback.
```

## Cosa contiene, per chi rilegge fra sei mesi

- Outfit impacchettato in `assets/fonts/` come **istanze statiche** a 400, 600
  e 700, estratte dal font variabile con `fonttools varLib.instancer`. Col solo
  variabile Flutter avrebbe simulato il grassetto invece di usare l'asse dei
  pesi, e su un font da display si nota.
- `GoogleFonts.outfit(...)` sostituito da `TextStyle(fontFamily: 'Outfit')` in
  `app_themes.dart` (con l'helper `_outfit`) e `stat_number.dart`.
- **Dipendenza `google_fonts` rimossa.** Non serviva più a nessuno: il
  generatore PDF usa `PdfGoogleFonts` di `printing`, che è un'altra cosa.
- Licenza SIL Open Font impacchettata e registrata in `LicenseRegistry`:
  compare in Impostazioni → Licenze open source.

## L'effetto collaterale che conta

Non è solo un fix estetico. Era **una connessione a Google che nessuna
informativa dichiarava**: senza cache, ogni avvio mandava l'IP dell'utente al
CDN dei font. Non era nell'informativa, non era fra i servizi di terze parti,
non era nei due questionari privacy compilati lo stesso giorno.

Impacchettando i font il buco si chiude alla radice, e non c'è niente da
aggiungere alle dichiarazioni.

È il tipo di cosa che sfugge a un audit perché non la scrive nessuno nel
codice: la porta dentro un pacchetto.

## Verifica

Emulatore Android, installazione pulita, **modalità aereo attiva**: titoli in
Outfit, zero errori di caricamento font nel log del processo. Le uniche
eccezioni sono di Firebase Installations, attese senza rete.
