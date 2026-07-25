# Note release 2.8.1+107 per gli store

Rilascio breve, subito dopo la 2.8.0. Una sola novità visibile all'utente.

## Play Console / App Store Connect — "Novità in questa versione" (IT)

```
Pubblichi un cammino a tappe? Ora puoi scegliere "Pubblica solo nel tour": le tappe si aprono dal tour senza comparire una per una nel feed di chi ti segue.

La scelta è reversibile quando vuoi, dal menu della traccia.

Correzioni e migliorie minori.
```

## EN

```
Publishing a multi-stage route? You can now choose "Publish for the tour only": stages open from the tour without filling your followers' feed one by one.

You can change your mind anytime from the track menu.

Minor fixes and improvements.
```

## Contenuto tecnico incluso (non citato nelle note utente)

- `hiddenFromFeed` filtrato in feed, Home "Dalla community", seguiti e "I sentieri più amati"
- Feed che pagina finché non ha abbastanza tracce visibili (senza, un blocco di tappe nascoste svuotava la prima pagina)
- Pin "Tour del mese" per admin (`isEditorial` su `community_tours`) — regole Firestore già deployate il 25/07
- `hiddenFromFeed` denormalizzato sulla traccia privata per lo stato del menu

## Nota per le tracce pubblicate prima di questa versione

Le tappe pubblicate con la vecchia checkbox hanno il flag solo sulla copia
pubblica: nel menu appariranno come "Togli dal feed" finché non le si tocca
una volta. Nessun effetto sul comportamento reale, solo sull'etichetta.
