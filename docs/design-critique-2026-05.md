# Design Critique — TrailShare (maggio 2026)

> Revisione condotta su: codice Flutter in `lib/` (tema, schermate Home/Record/Navigation/Community/Discover/Profile/Dashboard/Onboarding) + materiale marketing `TrailShare — Carousel.pdf`.

---

## Overall Impression

TrailShare ha **una promessa di brand forte** (montagne verdi + arancio "TrailShare", tagline "Il tuo compagno di sentiero", focus su sicurezza con Lifeline) ma il codice rivela una **disconnessione netta fra la qualità del carousel marketing e l'implementazione effettiva**: l'identità visiva premium del materiale promozionale (gradiente verde scuro + tipografia Outfit a 64px + card vetro/scuro) non si traduce nel tema light dell'app, dove l'arancione brand `#E07B4C` su sfondo bianco ha un contrasto di solo **2.95:1 (FAIL WCAG AA)** sui CTA principali. Sotto la superficie c'è anche un **design system molto frammentato**: 15+ valori di `fontSize` hardcoded, 10 raggi di bordo diversi, 91 colori hardcoded fuori da `AppColors`. La più grande opportunità è chiudere il gap fra brand promesso e prodotto reale, partendo dall'accessibilità del colore primario.

---

## 1. Usabilità

| Finding | Severità | Raccomandazione |
|---------|----------|-----------------|
| **AppBar Community con 5 tab + 4 azioni** (Pro, Cerca, Mappa/Lista, Refresh) → cognitive overload e icone non distinguibili sulla stessa riga. | Critico | Riduci a max 2 azioni in AppBar (Cerca + overflow menu). Sposta toggle mappa/lista in un segmented control sotto la tab "Tracce". Il refresh può andare via pull-to-refresh (già presente). |
| **Bottom nav `Registra` ha 3 stati visuali** (idle arancio, recording rosso pulsante, paused ambra) — eccellente. Ma il "ring pulsante" si espande di +14px oltre il SizedBox(64×52) creando un'area che esce dal touch target tracciato e potrebbe sovrapporsi alle label adiacenti. | Moderato | Sposta il `Stack` in un `Positioned.fill` con `Overflow.visible` documentato, oppure riduci il pulse a 26→34px. Verifica che le label "Comunità" e "Tracce" non vengano oscurate durante il pulse. |
| **Profile page** ha 9+ tile spalmati in 3 sezioni più 2 azioni in AppBar (Settings + Logout). Settings dovrebbe essere prominente, Logout è un'azione "distruttiva" troppo accessibile (un tap accidentale ti sbatte fuori). | Moderato | Sposta Logout in fondo alla pagina Settings (pattern standard iOS/Android). Lascia solo Settings nell'AppBar. Considera di accorpare "Profilo" e "Settings" come fanno Strava/Komoot. |
| **Onboarding usa 5 colori brand diversi** (arancio, rosso, blu, verde, arancio scuro). Frammenta il brand: ogni slide sembra un'app diversa. | Moderato | Mantieni l'arancione TrailShare come colore dominante; usa il colore semantico (rosso safety, verde explore) solo per l'icona tonda, non per il CTA in basso. Il CTA dovrebbe restare sempre arancione brand per costruire memoria muscolare. |
| **Record page**: 3.938 linee in un singolo file con HUD compatto/esteso + tutorial overlay + pre-start sheet + lifeline chip + off-trail row + guided turn row + SOS + battery saver + mountain finder. Quasi sicuramente l'utente vede troppe cose simultaneamente in registrazione. | Critico | Audit del HUD: prioritizza distanza/tempo/D+ (già fatti compatti). Tutto il resto (HR, velocità, pace) dovrebbe stare in stati `_statsExpanded`. La "guided turn row" + "lifeline chip" + "off-trail row" sono 3 banner separati: unificali in un singolo "status stack" con priorità (off-trail > svolta > lifeline). |
| **Navigation page** mostra istruzione in alto + stats in basso + bottone "Termina navigazione" full-width con `AppColors.danger` come outlined button. Visivamente è già un'azione distruttiva, ma è grande quanto i CTA primari — può essere toccato per errore. | Moderato | Riduci a icona+testo "✕ Termina" in un chip secondario, oppure metti dietro un tap "long-press 0.5s per confermare" durante la navigazione attiva. |
| **Discover page**: titolo `discoverWithCount(N)` cambia mentre l'utente scrolla la mappa (cluster vs trails) — l'AppBar "lampeggia" con conteggi diversi. | Minore | Mostra il count come chip sottotitolo separato dall'AppBar title, così la title resta stabile ("Scopri sentieri"). |
| **Tab "Seguiti" in Community** ha label hardcoded `'Seguiti'` mentre le altre passano da `context.l10n` — leak di stringhe non localizzate. | Minore | Sposta in `app_it.arb`/`app_en.arb`. |

---

## 2. Gerarchia Visiva

**Cosa cattura l'occhio per primo**: nel carousel marketing, è giustamente il titolo bold `Outfit 48pt` ("GPS & Attività") seguito dal mockup iPhone con dati live. **Nell'app vera**, sulla Home con tab "Community" default, l'occhio non sa dove andare: l'AppBar ha 4 azioni icona + 5 tab con icona+label, nessuna gerarchia evidente.

**Flusso di lettura**: il carousel funziona da sinistra (testi+features) a destra (mockup) — schema editoriale solido. Nell'app, schermate come Profile e Dashboard usano lo stesso pattern (hero stat in alto, satelliti sotto, sezioni con headers) — questo è il pattern che funziona meglio e dovrebbe essere il template per le altre pagine.

**Enfasi**: il Record button al centro della nav bar è l'azione più importante e correttamente è l'elemento più prominente — ottima decisione. Su Community/Discover invece **tutto compete**: 5 tab equipollenti, 4 azioni equipollenti, e il contenuto principale (lista tracce o mappa) arriva visivamente terzo.

**Whitespace**: padding generalmente buono (12-16px standard), ma le card stats compatte sotto `_buildStatsCompact` mescolano padding interni 4-6-8-10-12px che non rispondono a una scala chiara — l'occhio percepisce "compressione".

---

## 3. Consistenza (Design System)

| Elemento | Issue | Raccomandazione |
|----------|-------|-----------------|
| **fontSize hardcoded** | 222 occorrenze di `fontSize:12`, 143 di `fontSize:11`, 121 di `fontSize:13`, 100 di `fontSize:16`, 93 di `fontSize:14`, 59 di `fontSize:18`, **57 di `fontSize:10`**, 33 di `fontSize:15`. Sono ~15 scale diverse. | Definisci una scala tipografica in `AppThemes` (es. Material 3: `bodySmall` 12, `bodyMedium` 14, `bodyLarge` 16, `titleSmall` 14, `titleMedium` 16, `titleLarge` 22, `headlineSmall` 24, `headlineMedium` 28, `headlineLarge` 32). Vieta `fontSize` hardcoded via lint — usa `Theme.of(context).textTheme.X`. |
| **BorderRadius hardcoded** | 107×12 + 92×8 + 36×10 + 33×20 + 31×16 + 25×4 + 21×2 + 18×14 + 14×999 + 9×6. **10 valori diversi.** | Definisci `AppRadii.sm = 8, md = 12, lg = 16, pill = 999`. Tutto il resto va eliminato. I valori `2` e `4` sono indistinguibili a occhio e creano disordine. |
| **Color hardcoded** | **91 occorrenze** di `Color(0xFF...)` in `presentation/pages` fuori da `AppColors`. Esempi: `#1565C0`, `#2E7D32`, `#5E35B1`, `#D32F2F`, `#FFEB3B`, `#B71C1C`, `#E64A19`, `#388E3C`, `#1976D2`. | Sposta tutti in `AppColors` come token semantici (`difficultyEasy/Medium/Hard`, `activityHiking/Bike/Ski`). Ogni colore "magic number" è una decisione presa una sola volta che diventa inconsistente la seconda volta. |
| **Light theme vs Marketing** | Il carousel comunica un'estetica **dark, outdoor, premium** (verde scurissimo + arancio). Il light theme dell'app è cream `#FAF9F7` + arancio: caldo ma non riconoscibile come "TrailShare" dal carousel. | Considera due strade: **(a)** rendi il dark theme il default (i tracker outdoor — Komoot, Gaia, Strava — partono dark perché l'utente li usa fuori); oppure **(b)** rifai il light theme con un accento verde montagna che riprenda l'identità del carousel. |
| **AppBar background trasparente** | Sia light che dark hanno `appBarTheme.backgroundColor: Colors.transparent`. Su schermate scrollabili senza hero image questo crea AppBar "fluttuanti" non delimitate dal contenuto. | Su schermate non-immersive (Profile, Dashboard, Tracks) usa `colorScheme.surface` per delimitare la barra. Mantieni trasparente solo su Record/Navigation/Discover (mappa). |
| **Navigation page hardcoded `Colors.white`** | I pannelli istruzione e stats sono `Material(color: Colors.white)` — in dark mode l'utente vede schermate bianche accecanti sopra una mappa scura. | Usa `colorScheme.surface` o `Theme.of(context).cardColor`. Stesso problema su molti widget che fanno `Container(color: Colors.white)`. |
| **Snackbar** | `AppSnackBar` è coerente (icona + colore semantico + radius 12 + floating) — **buon esempio di design system**. Replica questo livello di rigore sugli altri componenti riutilizzabili. | Mantieni come reference pattern. |

---

## 4. Accessibilità (WCAG 2.1 AA)

### Contrasto colore — 9 FAILURE critici su 16 coppie testate

| Coppia | Ratio | AA normale | Severità |
|---|---|---|---|
| **WHITE su `#E07B4C` (TUTTI i CTA filled in light)** | **2.95** | FAIL | 🔴 Critico |
| `#E07B4C` arancione su white (link/outline btn) | 2.95 | FAIL | 🔴 Critico |
| **`#B2BEC3` textMuted su `#FAF9F7`** | **1.81** | FAIL | 🔴 Critico |
| `#9E9E9E` nav inactive su white | 2.68 | FAIL | 🟡 Moderato |
| `#757575` nav inactive su `#1E1E1E` dark | 3.62 | FAIL (large PASS) | 🟡 Moderato |
| Snackbar bianco su `#4CAF50` success | 2.78 | FAIL | 🟡 Moderato |
| Snackbar bianco su `#FFA726` warning | 1.94 | FAIL | 🔴 Critico |
| Snackbar bianco su `#29B6F6` info | 2.30 | FAIL | 🔴 Critico |
| Snackbar bianco su `#E53935` danger | 4.23 | FAIL (large PASS) | 🟡 Moderato |

**Cosa funziona**: il dark theme è quasi tutto a posto. `primaryLight #F5A67E` su scaffold scuro ha ratio 8.45-9.49 — pass AAA. Il textPrimary su light passa AAA. Il textSecondary `#636E72` passa AA.

**Cosa è urgente**:
1. **Scurire il primary o arrendersi al fatto che l'arancione `#E07B4C` non può portare testo bianco.** Opzioni:
   - Scuro: nuovo `primary #B85A2C` → ratio 4.6:1 con white (PASS AA). Mantieni `#E07B4C` come `primaryAccent` per icone e bordi su sfondo chiaro (1.5+ ratio basta per UI components non-text).
   - Mantieni il colore brand ma forza il testo dei CTA al `colorScheme.onSurface` (nero) invece di white — testato: nero `#1A1A1A` su `#E07B4C` ha ratio 7.4:1 PASS AAA. *Strava ha fatto questo cambio nel 2019.*
2. **Sostituisci `textMuted #B2BEC3` con `#7A8388`** (ratio 4.51:1 PASS AA su `#FAF9F7`).
3. **Snackbar warning/info** devono avere testo nero, non white: `#000` su `#FFA726` = 9.6:1 PASS AAA.

### Touch target size

- `_NavItem.SizedBox(width: 64)` con `Icon size: 24` → totale ~44×44 con padding label. **Al limite minimo (44dp iOS, 48dp Android)** — ok ma stretto.
- Le icone in AppBar Community (4 azioni + tab icons) sono `IconButton` standard (48dp), ok.
- I chip stat 10-12px (`_miniStat`, `_buildStat small:true`) **non sono tap target ma il testo è ai limiti della leggibilità** (raccomandato 12pt min, qui usi 10pt per labels).

### Tipografia

- **143 occorrenze di `fontSize:11` + 57 di `fontSize:10`** in schermata. Per un'app outdoor usata in movimento, con guanti, sotto pioggia, con sole forte sullo schermo, **niente sotto 14pt nel corpo del testo**. Le label sottili a 10pt sotto i numeri stats sono accettabili solo perché il numero principale è 22-36pt.
- Outfit (titoli) + system font (body) è una scelta solida. Ma assicurati di passare via `Theme.textTheme` ovunque — molte `Text` ignorano il theme e applicano fontSize esplicito.

### Altri punti

- Mai visto `Semantics(label: ...)` esplicito sulle icone — gli `IconButton` ereditano tooltip ma molti `Icon` puri (es. nelle stats card) sono "muti" per screen reader.
- Recording dot pulsante non ha label semantica → un utente VoiceOver/TalkBack non sa che la registrazione è attiva.

---

## 5. Cosa Funziona Bene

- **Identità marketing forte e differenziata** (Lifeline = USP chiara, 14 sport, claim "compagno di sentiero" — il carousel comunica bene chi è TrailShare contro Strava/Komoot).
- **Pulsante REC al centro della nav bar con 3 stati visuali** (idle/recording/paused) e ring pulsante in registrazione — pattern moderno e leggibile a colpo d'occhio.
- **Tipografia Outfit per i titoli** — distintiva e leggibile, scelta editoriale di alta qualità.
- **AppSnackBar** centralizza icona+colore+forma con 4 varianti semantiche — è il modello da estendere ad altri componenti.
- **Dashboard hero stat + 3 satelliti** è un pattern di gerarchia molto chiaro che andrebbe replicato.
- **Naming feature in italiano marketing** (Lifeline, Battery Saver, Auto-detect, Cronometro automatico, KOM/QOM) — terminologia adulta e specifica del dominio outdoor, non infantilizzata.
- **Service centralizzato per recording status** (`RecordingStatusService`) che alimenta UI nav bar — buona architettura che riflette in UI consistente.
- **Onboarding 5 slide con dot indicator + skip + animation** — pattern industria standard, fa il suo lavoro.

---

## 6. Priorità Raccomandazioni

1. **🔴 Fix critico contrasto del primary brand**. Tutti i CTA filled in light mode sono sotto WCAG AA. Decidi se:
   - (a) Scurire `primary` a `#B85A2C` (PASS AA con white) — soluzione fast.
   - (b) Cambiare il foreground dei CTA primary a `#1A1A1A` (PASS AAA, mantiene il colore brand). **Raccomandato** — preserva l'identità.
   - In ogni caso, aggiorna anche `textMuted`, `warning` (testo nero), `info` (testo nero), e i `9E9E9E` della nav.

2. **🔴 Token system + lint rule**. Crea `AppRadii`, `AppSpacing`, `AppTypography` e introduci una regola `analysis_options.yaml` (custom_lint o just-grep CI) che fallisce su `fontSize:` hardcoded e `Color(0xFF` fuori da `core/constants/`. Senza questo, ogni nuova schermata aumenta la frammentazione. Hai **91 colori e 15 fontSize** da ricondurre — non si fa in un giorno ma serve un freeze.

3. **🟡 Allinea l'identità app al carousel marketing**. Il dark mode dell'app è già coerente col carousel; rendilo il default per nuovi utenti (impostazione modificabile) e ribattezza light mode come "Tema diurno" non default. Oppure rifai il light usando il verde montagna `#0F3A2E` come `secondary` invece del verde Material `#2E7D32` — riprende l'identità del carousel hero.

4. **🟡 Audit della densità informativa di Record page e Community**. Su Record: unifica i 3 banner di stato (turn row + lifeline + off-trail) in un singolo "status stack" prioritizzato. Su Community: 5 tab + 4 actions è troppo. Sposta "Spazi Pro" e "Cerca utenti" in overflow menu, "mappa/lista" in segmented control sotto la tab.

5. **🟡 Logout out of reach**. Sposta il bottone logout dall'AppBar Profile a fondo Settings page. Un tap accidentale dall'AppBar è un evento traumatico per un utente in mezzo a un'attività.

6. **🟢 Estendi il pattern `AppSnackBar`**. Crea componenti riutilizzabili `AppCard`, `AppStatTile`, `AppSectionHeader`, `AppEmptyState` (ne hai già uno con `TopoEmptyState`) — riduci il copy-paste di `Container + BoxDecoration` che vedo ovunque.

7. **🟢 Onboarding monocromatico brand**. Tutti i CTA arancione, l'icona tonda usa il colore semantico della slide. Costruisce memoria muscolare del CTA primario.

8. **🟢 Aggiungi Semantics labels** ai widget di stato dinamico (recording dot, HR widget, battery saver toggle) — un utente con assistive tech deve sapere che la registrazione è attiva.

---

## Allegato: dati grezzi del lint informale

```
fontSize hardcoded (top 8):    222×12  143×11  121×13  100×16  93×14  59×18  57×10  33×15
BorderRadius hardcoded (top): 107×12  92×8   36×10  33×20  31×16  25×4   21×2   18×14
Color(0xFF...) fuori AppColors: 91 occorrenze
File più lunghi (lib/presentation):
  3.938  record_page.dart
  2.628  community_page.dart
  1.899  discover_page.dart
  1.847  trail_follow_page.dart
    910  dashboard_page.dart
    927  profile_page.dart
```

---

*Revisione effettuata su snapshot codice del 27-28 maggio 2026. Non include test su dispositivo fisico né analisi dei flussi di errore (network down, GPS lost, recovery da crash). Raccomandato follow-up con user testing su 5 utenti reali in ambiente outdoor per validare ipotesi su densità informativa di Record page.*
