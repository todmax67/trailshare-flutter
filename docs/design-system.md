# TrailShare — Design System (work in progress)

Pagina di lavoro per costruire un'identità visiva propria, **separata dal codice**.
Nasce da uno spunto onesto ricevuto su FB: _"c'è un abuso di Material 3, prova a fare
componenti più in linea con il design system che vuoi portare"_.

La critica era parzialmente giusta: il tema era curato (brand arancione, font Outfit,
scala radius intenzionale), ma **i microdettagli erano Material "stock"** e le decisioni
di stile erano scavalcate in decine di punti (ogni `Card` con il suo `elevation`).

Questo documento è la **fonte di verità**: dice cosa deve fare il tema e _perché_, così
non si torna a indovinare caso per caso. Si aggiorna a ogni intervento, uno alla volta,
senza grandi rifacimenti.

---

## Principi

Regole stabilite finora. Il tema centrale (`lib/core/constants/app_themes.dart`) le
implementa; i componenti **non devono scavalcarle** se non per i motivi indicati.

### 1. Superfici: piatte di default, ombra solo se "galleggia"
- **Card di contenuto** (sezioni di dettaglio, card-traccia in lista) → **piatte**,
  `elevation: 0`, con **bordo a filo di capello** (`#E8E3DD` light / `#333333` dark).
  Look editoriale alla Komoot/AllTrails, non "tessere Material che galleggiano".
- **UI flottante** (controlli sopra la mappa, FAB, pannelli di navigazione/registrazione,
  bottom sheet, dialog, marker) → **mantiene l'ombra**: lì l'elevazione è _funzionale_,
  serve a separare dal contenuto sottostante. Non appiattire.

> Regola pratica: _l'ombra comunica "sto sopra qualcos'altro", non "sono importante"._
> Se l'elemento non galleggia davvero su altro contenuto, niente ombra.

### 2. Feedback al tocco: ripple brand, non grigio Material
Ripple tinto col brand a bassa opacità (`splashColor`/`highlightColor` sul tema), al
posto dell'onda grigio-nera di default. È il dettaglio percettivamente più "Flutter"
quando lasciato stock.

### 3. Bottoni: piatti e coerenti
`ElevatedButton` ≡ `FilledButton`: stesso aspetto piatto (`elevation: 0`), niente ombrina
"galleggiante" sotto i bottoni (look "Material demo 2021"). Definito un `filledButtonTheme`
allineato così i due tipi convivono senza incoerenza.

### 4. Tipografia
Outfit (Google Fonts) sui titoli (Display/Headline/Title), font di sistema su body/label
per leggibilità. Già in essere — confermato.

---

## Fatto

### 2026-06-04 — De-Materializzazione superfici e bottoni
Tutto nel solo tema + appiattimento delle card di contenuto che lo scavalcavano.

**Tema** (`lib/core/constants/app_themes.dart`, light + dark):
- Ripple brand: `splashFactory: InkRipple.splashFactory` + `splashColor`/`highlightColor`
  tinti arancione.
- `ElevatedButton` → `elevation: 0`; aggiunto `filledButtonTheme` allineato.
- `cardTheme` → `elevation: 0` + bordo a filo di capello.

**Card di contenuto appiattite** (scavalcavano il tema con `elevation` esplicita):
1. `track_segments_section` — _la sezione segmenti notata per prima_
2. `trail_segments_section`
3. `trail_conditions_section`
4. `trail_reviews_section`
5. `trail_photos_section`
6. `weather_forecast_card`
7. `public_track_card`
8. `community_track_card`
9. `segment_detail_page` (card statistiche)

> Nota: i cambi di tema richiedono **full restart** (non hot-reload) per essere visibili.

---

### 2026-06-05 — Scheletro moderno: tipografia + bottoni pillola
Tutto nel solo tema (`app_themes.dart`), zero call-site.
- **Tipografia**: titoli Outfit più grassi con tracking negativo (display/headline
  `w700`, title `w600`, `letterSpacing` da `-1.0` a `-0.2`). Gerarchia premium/editoriale
  al posto dei pesi Material di default. Body/label restano sistema.
- **Bottoni a pillola**: `ElevatedButton`/`FilledButton`/`OutlinedButton` → `StadiumBorder`
  (era radius 12). Segnale "moderno" più riconoscibile su un CTA.

> Principio aggiunto: **titoli grassi + tracking stretto** = firma tipografica del brand.

### 2026-06-05 — Superfici tonali calde (addio bianco piatto)
L'app era "interamente bianca": sfondo `#FAF9F7` + card bianche → tutto piatto.
Introdotto un **sistema tonale caldo a livelli** nel `ColorScheme` (`app_themes.dart`),
che alimenta anche `theme_colors_extension.dart` (prima ereditava i default lavanda di M3).

Scala superfici **chiaro** (sabbia → bianco caldo):
- sfondo pagina (scaffold / `surfaceContainer`): `#E7E9D9` (sabbia-salvia, undertone verde)
- card / dialog / sheet (`surface`): `#FBF9F5` (bianco caldo)
- input well (`surfaceContainerHigh`): `#ECE6DD`
- bubble/placeholder (`surfaceContainerHighest`): `#E6DFD4`
- hairline (`outlineVariant`): `#E8E3DD` · testo secondario (`onSurfaceVariant`): `#6E665C`

Le card "galleggiano" per **contrasto di tono** (bianco caldo su sabbia), non per ombra.
**Scuro**: definiti gli stessi ruoli `surfaceContainer*` con grigi neutri (no lavanda M3).
`AppColors.background`/`surface` allineati per i consumer hardcoded.

> Tunabile: per più caldo/profondo basta scurire il sabbia; per più freddo, ridurre la
> componente gialla. Tutto centralizzato nel `ColorScheme`.

### 2026-06-05 — Sezioni "a lista" minimaliste (PROVA, reversibile)
Nella pagina dettaglio trail (`trail_detail_page.dart`) **tutte** le sezioni contenuto sono
sullo stesso salvia, **senza cornice**, separate da una **linea leggera** — look editoriale
/ settings-app invece della colonna di card.

Tecnica:
- helper `_onSage(child)` = `Theme` locale con `cardTheme.color: transparent` + shape senza
  bordo. Avvolge l'**intera** colonna di sezioni → tutte le card interne spariscono.
- helper `_sectionDivider()` = `Divider` 1px colore `#D6D9C5` (salvia più scuro) tra le sezioni.
- **Zero modifiche ai widget di sezione** (riusati altrove intatti, conservano la card).

Esteso poi a **tutta** la pagina: `_onSage` ora neutralizza anche `colorScheme.surface` e
`outlineVariant` (per i `Container` basati sui ruoli tema, es. POI), ed è applicato anche a
**info card**, **stat tiles**, **grafico**. La **mappa** è full-bleed via `_fullBleedMap`
(card senza margine/bordo, angoli vivi) → edge-to-edge nell'header.

**Titolo** spostato dall'overlay sulla mappa a **headline grande** nella prima area sotto
(valorizza la tipografia bold). Tradeoff: la app-bar collassata non mostra più il nome
(da rivalutare con un titolo collapse-aware se serve). Scheda "Informazioni" in fondo
(`_buildDetails`) anch'essa unificata a salvia.

> ⚠️ In prova: `_onSage` rende trasparenti **tutte** le card/`surface` annidate e azzera
> `outlineVariant` (spariscono anche separatori interni, es. tra item POI). Se qualcosa
> perde troppa leggibilità → revert facile. Non ancora replicato su `track_detail_page.dart`.

---

### 2026-06-05 — Helper condivisi + estensione a track_detail_page
Estratti gli helper in `lib/presentation/widgets/flat_section.dart` (riutilizzabili in
tutte le pagine): `SageSurface` (sezione frameless su sfondo), `SectionDivider` (linea
leggera), `FullBleedCard` (mappa edge-to-edge).

Applicati a **`track_detail_page.dart`** (la traccia personale): contenuto avvolto in
`SageSurface` (tutto frameless su salvia), mappa header `FullBleedCard` (rimossi overlay
titolo + gradient), titolo come headline grande sotto la mappa. **Spaziatura via SizedBox
esistenti** (non ancora i `SectionDivider` — da aggiungere se si vuole parità piena con
trail_detail; rinviato per via delle molte sezioni condizionali).

### 2026-06-05 — Estensione completata a tutte le pagine dettaglio
- **`community_track_detail_page`**: ricetta piena (uguale a track) — `SageSurface` su tutto
  il contenuto, mappa `FullBleedCard` (rimossi overlay titolo + gradient), titolo headline sotto.
- **`tour_detail_page`** e **`community_tour_detail_page`** (struttura diversa: `ListView` +
  `AppBar` classica + `TourHero`): titolo già OK nell'AppBar, header `TourHero` lasciato com'è.
  Trattamento mirato: le **tappe** (`_StageTile`) ora sono lista pulita su salvia
  (`SageSurface` + `SectionDivider` tra una tappa e l'altra).

> Da rifinire: trail_detail usa ancora gli helper locali `_onSage`/`_sectionDivider`/
> `_fullBleedMap` (identici a `flat_section.dart`) — migrabili per pulizia.
> Da verificare nelle pagine tour: `TourRichHeaderSections` (widget esterno) potrebbe avere
> card/superfici proprie che restano bianche su salvia → eventuale follow-up.

---

## Backlog (ordinato per ROI)

### ⚠️ Sweep `Colors.white` hardcoded (follow-up diretto del tonale)
~415 `color: Colors.white` + 19 `backgroundColor: Colors.white` + ~396 `0xFFFFFFFF` nei
widget. Molti sono **testo/icone bianchi su sfondo colorato** (vanno lasciati!), ma quelli
usati come **sfondo di Container/BoxDecoration** ora stoneranno come isole bianche sul
sabbia. Serve uno sweep **discernente** (sfondo vs primo piano), non un replace cieco.


### Zona grigia — da verificare una a una
Card con `elevation` esplicita che **potrebbero** essere contenuto travestito da flottante.
Controllare il contesto prima di appiattire:
- `discover_page.dart:1466`
- `planner_tab.dart:776`, `:786`
- `community_page.dart:1307`
- `group_tracks_tab.dart:185`

### Elemento-firma (tracce colorate per pendenza) — FATTO inline ✅
Logica estratta in `lib/core/utils/track_gradient_colors.dart` (`slopeBetween`, `slopeColor`,
`slopeGradientPolylines`, `trackHasElevation`, widget `SlopeLegend`). Il fullscreen
(`track_map_page`) ora delega al condiviso (single source). La **mappa inline**
`InteractiveTrackMap` colora la traccia per pendenza di **default** (`colorBySlope = true`)
con **mini-legenda** in basso-centro (solo se la traccia ha quota; fallback `AppColors.primary`).
Ora la firma colorata è visibile a tutti senza aprire il fullscreen.

Rimanenti (secondari):
- **Velocità**: `speedGradient` definito ma mai usato (mancano timestamp per-punto).
- Gradiente a fasce discrete, non continuo (Color.lerp) → rifinitura.

### Densità delle superfici
313 `Card` in totale: il pattern "tutto è una card" resta. Valutare liste con separatori
sottili al posto di card singole dove ha senso (feed, elenchi).

### Movimento
Una transizione di pagina "firmata" (anche una sola): il movimento è ciò che il cervello
registra come marchio. Oggi sono le transizioni M3 di default.

### UI flottante — mappare le BoxShadow custom
~30 file usano `BoxShadow` proprie. Censire quali sono legittime (flottanti) e quali
andrebbero unificate in un token d'ombra condiviso, per coerenza dell'elevazione.
