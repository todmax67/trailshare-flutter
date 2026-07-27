# Foto dei rifugi — coda di revisione

Come dare una copertina ai rifugi che ne sono privi, senza rischiare di
metterne una sbagliata.

## Perché non è automatico

`scripts/business_commons_photos.cjs` prende le foto dai tag OSM
(`wikidata` → P18, `wikimedia_commons`, `image`). Quella via è affidabile —
il tag dice esplicitamente «questa immagine è questo rifugio» — ma è esaurita:
copre circa il 30% dei rifugi e sull'ultimo giro completo ha prodotto **una**
foto nuova su 3.046 rifugi rimasti.

Le fonti alternative sono molto più ampie ma non si possono verificare da
programma:

- **Foto geolocalizzate vicine.** Commons sa quali immagini sono state scattate
  entro X metri, ma «vicino al rifugio» non vuol dire «è il rifugio»: accanto al
  Rifugio Vittorio Sella ci sono foto di cince e di panorami.
- **Categorie omonime.** Una `Category:Blahbergalm` è quasi sempre giusta, ma i
  rifugi omonimi esistono: il nostro Refuge Cezanne è negli Écrins, quello di
  Commons sta sulla Montagne Sainte-Victoire, 180 km più a sud.

Una copertina sbagliata l'utente la vede subito, quindi la sceglie una persona.
Da qui la coda: lo script propone, tu decidi, un secondo script applica.

## I tre passi

```bash
node scripts/business_photo_candidates.cjs
```

Interroga Commons per ogni rifugio senza foto e scrive
`.photo_review/candidates.json` (cartella ignorata da git). Circa 35 minuti sui
3.000 rifugi. Opzioni utili: `--country FR`, `--bbox s,w,n,e`, `--limit 50`,
`--radius 1500`, `--type noleggio`.

Salva un checkpoint ogni 50 rifugi: se si interrompe, `--resume` riparte da dove
era. I rifugi falliti per rate limit **non** vengono segnati come fatti, così al
giro dopo si riprovano da soli.

```bash
node scripts/business_photo_review_page.cjs && open .photo_review/index.html
```

Genera la pagina di revisione. Una scheda per rifugio, le proposte in fila:
clic sulla miniatura per approvarla, «nessuna» per archiviare il rifugio senza
foto. Tastiera: `1`–`6` sceglie, `0` nessuna, `j`/`k` scorre. Le scelte restano
in `localStorage`, si può chiudere e riprendere. Alla fine **scarica
approvals.json**.

Ogni proposta porta le sue etichette:

| etichetta | significato |
|---|---|
| `foto geolocalizzata` | scattata entro il raggio, e il titolo o le categorie contengono il nome |
| `categoria omonima` | viene da una categoria Commons con lo stesso nome |
| `posizione non verificata` | né i file né la categoria hanno coordinate: **potrebbe essere un omonimo** |
| `forse un cartello/dettaglio` | il titolo suggerisce un segnavia, una mappa, un interno |

Sotto ogni miniatura ci sono le categorie del file: è il modo più rapido per
smascherare un omonimo, «Montagne Sainte-Victoire» sotto un rifugio degli Écrins
salta all'occhio.

```bash
node scripts/business_photo_apply.cjs --dry   # controllo
node scripts/business_photo_apply.cjs         # scrive
```

Copia le immagini approvate nel nostro Storage
(`business_covers/{id}/wikimedia.jpg`) e scrive `branding.heroPhotoUrl` +
`photoAttribution` con autore e licenza. Non tocca mai un rifugio che nel
frattempo ha già una foto: se il gestore ne ha caricata una dopo la
rivendicazione, la sua vince.

Per tornare indietro: `node scripts/business_photo_apply.cjs --undo` — rimuove
le foto dell'ultimo giro e cancella i file da Storage.

## Come si affina

L'elenco delle parole generiche (`GENERIC` in `business_photo_candidates.cjs`)
è quello che regge la precisione: finché «casa» resta nel confronto, «Casa
Bastone» fa match con «casa semiutilizzata» di un paese qualsiasi. Ogni lingua
nuova che si aggiunge vuole le sue (`koča`, `menedékház`, `alpengasthof`…).

L'elenco delle foto deboli (`WEAK`) sta invece in
`business_photo_review_page.cjs`, non nella scansione: è una lista che si affina
guardando i risultati, e rigenerare la pagina costa un secondo mentre rifare la
scansione costa un'ora.
