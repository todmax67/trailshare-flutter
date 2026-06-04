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

## Backlog (ordinato per ROI)

### Zona grigia — da verificare una a una
Card con `elevation` esplicita che **potrebbero** essere contenuto travestito da flottante.
Controllare il contesto prima di appiattire:
- `discover_page.dart:1466`
- `planner_tab.dart:776`, `:786`
- `community_page.dart:1307`
- `group_tracks_tab.dart:185`

### Elemento-firma (il vero margine d'identità)
Le **tracce colorate per velocità/pendenza** (gradienti già in `AppColors`) sono l'unico
elemento davvero distintivo vs Strava/Komoot. Da valorizzare come segno ricorrente del
brand, non solo come dettaglio funzionale sulla mappa.

### Densità delle superfici
313 `Card` in totale: il pattern "tutto è una card" resta. Valutare liste con separatori
sottili al posto di card singole dove ha senso (feed, elenchi).

### Movimento
Una transizione di pagina "firmata" (anche una sola): il movimento è ciò che il cervello
registra come marchio. Oggi sono le transizioni M3 di default.

### UI flottante — mappare le BoxShadow custom
~30 file usano `BoxShadow` proprie. Censire quali sono legittime (flottanti) e quali
andrebbero unificate in un token d'ombra condiviso, per coerenza dell'elevazione.
