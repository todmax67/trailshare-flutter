# Note release 2.8.0+106 per gli store

## Play Console / App Store Connect — "Novità in questa versione" (IT, ≤500 char)

```
Nuova Home! Si apre con una foto della community, i bottoni Registra e Scopri, e il Tour del mese in evidenza. Le tracce senza foto mostrano il profilo altimetrico.

• Mappa Scopri: sentieri raggruppati in cluster + vista Lista
• Mappa 3D a richiesta su sentieri e zona, con stile Satellite/Topografica
• Le notifiche aprono direttamente chat, traccia o profilo giusti
• Import GPX/TCX/FIT: distanza fedele e tempo "In movimento"
• Fix e prestazioni migliorate
```

(≈480 caratteri, verificare il contatore in console)

## EN (≤500 char)

```
New Home! It opens with a photo from the community, Record and Discover buttons, and the Tour of the month front and center. Tracks without photos now show their elevation profile.

• Discover map: trails grouped in clusters + List view
• On-demand 3D map for trails and areas, with Satellite/Topo styles
• Notifications now open the right chat, track or profile
• GPX/TCX/FIT import: accurate distance and new "Moving time"
• Fixes and performance improvements
```

## Contenuto tecnico incluso (non citato nelle note utente)

- Google Play Billing Library 8.0.0 (richiesta Google, deadline 31/8/2026)
- Fix distanza import: stats sui punti completi, non decimati (bug utente Pro)
- movingTime calcolato su GPX/TCX/FIT (soglia 0,5 m/s)
- Routing tap notifiche: group_message/event/challenge/join_request/join_approved/kudos/mention/new_follower
- Home Feed redesign "Editoriale 2b" + rimozione _MiniMapCard
- flutter_map_marker_cluster su Scopri (client-side, disableClusteringAtZoom: 15)
