# TrailShare — Catalogo Funzionalità

Documento di riferimento per materiale promozionale, brochure e store listing.
Aggiornato a v1.9.0 (in test) · v1.7.0 in produzione.

---

## 🏷️ Posizionamento

**TrailShare** è l'app italiana per chi va in montagna con la testa sulle spalle:
tracciamento GPS evoluto, sicurezza integrata, community attiva, e una serie di
strumenti pensati per **chi cammina davvero sui sentieri**, non solo li sogna.

Sviluppata in Italia, ottimizzata sulle Alpi e sull'Appennino, completamente
in italiano e inglese.

**Tagline brevi disponibili:**
- "Il tuo compagno di sentiero"
- "GPS outdoor con coscienza"
- "Cammina sicuro, condividi davvero"
- "Trekking, sicurezza, community — in un'unica app"

---

## 📍 1. Tracciamento GPS & Attività

### Registrazione live
Il cuore di TrailShare. GPS ad alta precisione con elaborazione del segnale
in tempo reale (filtro mediano sul dislivello, isteresi anti-rumore, smoothing
elevation), per stats accurate anche con copertura imperfetta.

- **14 tipi di attività supportati**: trekking, trail running, camminata,
  ciclismo, corsa, mountain bike, gravel bike, e-bike, e-mountain bike,
  sci alpino, scialpinismo, sci nordico, racchette da neve, snowboard
- **Auto-detect del tipo di attività** in base alla velocità media e allo
  stile di movimento
- **Pausa e ripresa** dalla mappa o da remoto
- **Sblocco automatico al cambio movimento** (la registrazione capisce se
  ti sei fermato per riposare o se hai finito)
- **Ricovero da crash**: se l'app si chiude inaspettatamente, al riavvio
  recuperi la traccia in corso senza perdere un metro

### Statistiche live e finali
- Distanza, dislivello positivo/negativo, tempo totale, tempo di movimento
- Velocità corrente, media e massima
- Quota minima e massima
- Frequenza cardiaca live (con sync Apple Health / Google Health Connect)
- Calorie e passi (sync da Salute)
- Split per chilometro con tempo cumulativo
- Grafico altimetrico interattivo
- Grafico battito cardiaco per zone

### Battery saver
Modalità a basso consumo per uscite lunghe: GPS a intervalli di 10 secondi,
schermo off forzato, sensori secondari disabilitati. Una traccia di 8 ore
consuma circa il 25% di batteria su un dispositivo medio.

---

## 🗺️ 2. Mappe e Navigazione

### Cartografia adattiva
- Mappe base con stili adattati a chiaro/scuro
- Mappe topografiche dettagliate (tile server pubblici)
- Tema coerente con il sistema operativo

### Mappe offline
Scarica zone intere prima di partire. Ideale per rifugi senza copertura,
ferrate, vallate isolate. Gestione spazio occupato e cancellazione selettiva
da Impostazioni.

### Compass-up navigation (v1.9.0)
**La novità che fa la differenza in mano sui sentieri.** La mappa ruota
automaticamente seguendo la tua direzione di marcia grazie alla bussola
del telefono, con sensor fusion GPS + magnetometro e filtro passa-basso
anti-vibrazione.

- Toggle con un tap: "Nord in alto" oppure "Direzione di marcia in alto"
- Icona posizione utente che ruota fluidamente verso la direzione
- Funziona anche da fermi, grazie al magnetometro

### Re-routing automatico
Se ti allontani dal percorso pianificato di oltre 100 metri per più di 30
secondi, l'app calcola un nuovo tracciato per riportarti in pista, oppure
ti chiede se vuoi continuare dove sei.

### Voice guidance
Indicazioni vocali in italiano e inglese con preferenze di tono e velocità
personalizzabili. Annunci automatici a:
- Inizio percorso e ripresa dopo pausa
- Avvicinamento ai POI lungo la via
- Off-trail / re-routing
- Metà percorso, ultimo chilometro, arrivo

### POI / Highlights lungo il percorso
Marca punti di interesse (fontane, rifugi, panorami, sezioni pericolose,
guadi, parcheggi) e ricevi notifica vocale geolocata quando ti avvicini.
I POI sono condivisibili con la community o privati.

### Pianificatore percorso
Disegna manualmente o usa snap-to-trail. Stats pre-partenza con distanza,
dislivello, tempo stimato. Aggiungi waypoint intermedi.

---

## 🛡️ 3. Sicurezza in Montagna — Lifeline

**La feature che ci differenzia da tutte le concorrenti.** Pensata per chi
va da solo o in zone isolate.

### Lifeline live tracking
- Definisci 1-3 contatti di emergenza dalla rubrica
- Avvii Lifeline e i tuoi contatti ricevono via SMS o link un URL
  pubblico con la tua posizione live aggiornata ogni 30 secondi
- Token sicuro: il link è univoco per uscita e si auto-invalida al termine

### Auto-alert inattività (2-step)
Se non ti muovi per il tempo che hai impostato (15-60 min):
1. Conferma locale: l'app suona, vibra, mostra un countdown visuale
   con anti-tap accidentale (richiede swipe o long-press per annullare)
2. Se non rispondi, viene inviato automaticamente un alert ai contatti
   con la tua ultima posizione e il messaggio personalizzabile

### Pulsante SOS sempre accessibile
Durante la registrazione, il pulsante 112 è sempre raggiungibile in un tap.
Apre direttamente il dialer con il numero di emergenza europeo, senza
passaggi intermedi.

### Health-check 30 secondi
Durante Lifeline, banner con stato del sistema sempre visibile:
- 🟢 Tutto OK: rete dati attiva, Firestore raggiungibile, GPS preciso
- 🟡 Degradato: una delle componenti ha problemi
- 🔴 Critico: stai trasmettendo solo localmente, i contatti non vedono la
  posizione aggiornata

### SMS fallback nativo
Se la rete dati cade ma c'è ancora segnale GSM, gli alert vengono inviati
via SMS direttamente al contatto, senza passare da internet.

### Backup locale + retry automatico
Tutte le posizioni Lifeline sono prima salvate localmente in SQLite. Quando
la rete torna, vengono inviate in batch. Nessuna posizione persa anche
con copertura intermittente.

### Disclaimer e formazione
Al primo uso Lifeline mostriamo un disclaimer chiaro sui limiti dell'app
(non sostituisce GeoResQ, soccorso alpino o satellitari). Link diretto a
GeoResQ nelle impostazioni Sicurezza.

---

## 👥 4. Community & Social

### Pubblicazione tracce
Rendi pubblica una tua traccia con un tap. Verrà aggiunta al feed
community con nome, foto, statistiche, mappa e descrizione opzionale.

### Esplora trail della community
- Mappa con cluster intelligenti
- Filtri per regione, attività, distanza, dislivello
- Schede percorso con anteprima dell'altimetria

### Cheers, foto e recensioni
- **Cheers**: like rapidi sulle tracce che ti piacciono
- **Foto multiple** per traccia con upload in alta qualità
- **Recensioni con stelle** + testo libero per dare un feedback dettagliato
- **Condizioni trail crowdsourced**: gli utenti segnalano fango, ghiaccio,
  alberi caduti, frane recenti

### Commenti sulle tracce (v1.9.0)
Discussioni in tempo reale sotto ogni traccia community. Parla del percorso,
chiedi consigli, condividi info aggiornate. Moderazione lato proprietario
della traccia per mantenere la conversazione pulita.

### Follow / Followers
Segui altri escursionisti, ricevi le loro nuove tracce nel feed personale,
visita il loro profilo pubblico con stats e wishlist.

### Profilo pubblico
- Avatar, username, bio
- Livello + XP totali
- Distanza e dislivello cumulati
- Tracce pubbliche
- Badge sbloccati
- Tour pubblici

### Gruppi
Crea o entra in gruppi tematici (CAI, sezioni locali, gruppi di amici).
Feed dedicato, eventi condivisi, chat di gruppo light.

### Wishlist
Salva i percorsi che vuoi fare un giorno. Sincronizzata con cloud, accessibile
da tutti i tuoi dispositivi.

### Sharing link web
Ogni traccia pubblica ha un URL condivisibile su `trailshare.app/track/{id}`
con anteprima Open Graph completa: nome, mappa thumbnail, stats. Idem per
i tour: `trailshare.app/tour/{id}`. Funziona su Whatsapp, Facebook, email,
ovunque.

---

## 🏔️ 5. Tour Multi-giorno

Aggregatore post-hoc per "viaggi" composti da più tracce singole. Pensato
per trekking di più giorni come l'Alta Via, il Sentiero Italia o il
Cammino di Santiago.

- Crea un Tour, dai un titolo (es. "Alta Via 1 Dolomiti")
- Aggiungi le tracce delle tappe in ordine
- Statistiche cumulative: distanza totale, dislivello totale, giorni, durata
- Versione privata per uso personale + versione pubblica per la community
- Mappa con tutte le tappe sovrapposte
- Sharing link web dedicato `trailshare.app/tour/{id}`

---

## 🎯 6. Engagement & Gamification

### Sistema XP + livelli
Guadagna esperienza con ogni attività. 20 livelli con titoli evocativi:
Principiante → Escursionista → Esploratore → ... → Mito → Immortale.

- 50 XP per traccia completata
- 10 XP per ogni km percorso
- 15 XP per ogni 100m di dislivello
- Bonus per first-track, traccia pubblicata, sfida completata, follower nuovo

### 13 Badge da sbloccare
Categorie: milestone, distanza, dislivello, social, streak.

- Primi Passi 👟 (prima traccia)
- Camminatore 🚶 (10 km)
- Escursionista 🥾 (50 km)
- Maratoneta 🏃 (100 km)
- Ultra Runner 🦅 (500 km)
- Scalatore ⛰️ (1000 m D+)
- Alpinista 🏔️ (5000 m D+)
- Conquistatore 🗻 (10000 m D+)
- Influencer 👥 (5 follower)
- Popolare 🎉 (50 cheers ricevuti)
- Costante 🔥 (3 giorni consecutivi)
- Dedito 💪 (7 giorni consecutivi)
- Inarrestabile 🌟 (30 giorni consecutivi)

### Sfide settimanali personalizzate (v1.9.0)
Ogni lunedì una sfida nuova generata sulla **tua** storia delle ultime 8
settimane. Nessuna sfida copia-incollata uguale per tutti.

- 4 tipi a rotazione: distanza, dislivello, tracce, durata
- Target = +15% sopra la tua media settimanale (stretch realistico)
- Bonus XP scalato sull'impegno (30-200 XP)
- Card dedicata in Dashboard con barra progresso e tempo rimanente
- Celebrazione al completamento

### Classifiche
- **Classifica settimanale tra amici**: tu vs i tuoi follower, settimana corrente
- **Classifica regionale (v1.9.0)**: top 50 della tua regione
  - Tab "Totale" (per XP cumulati)
  - Tab "Questo mese" (per distanza del mese in corso)
  - Avatar, badge "TU" sulla tua riga, medaglie oro/argento/bronzo top 3
  - Scegli la tua regione tra le 20 italiane + sentinella "Internazionale"

### Report mensile automatico "Il mio mese" (v1.9.0)
Il primo del mese trovi pronto il report del mese appena chiuso, con
notifica Discovery in-app nei primi 7 giorni:

- Hero: distanza totale del mese
- 3 stat card: dislivello, tempo, tracce
- Confronto percentuale vs mese precedente (frecce up/down con %)
- Giorni attivi (giorni distinti con tracce)
- Record del mese: traccia più lunga + dislivello maggiore
- Breakdown per tipo di attività con barre proporzionali
- Badge sbloccati nel mese
- XP guadagnati nel mese
- Navigazione tra mesi con frecce per rivedere lo storico

### Discovery Carousel
Carosello di card promozionali contestuali che appaiono sulla tab Discover
in base alla tua attività: nuova sfida, lifeline da configurare, primo
tour, classifica regionale, report mensile pronto. Auto-rotate, dismiss
individuale, indicatori dot.

### Streak
Conteggio dei giorni consecutivi con almeno una traccia. Mostrato nel
profilo, contribuisce ai badge.

---

## 🏁 7. Segmenti Cronometrati

Sezioni famose di sentieri (es. la salita al Rifugio Locatelli) con
classifica dedicata.

- Definisci segmenti dalla mappa o usa quelli della community
- **Matching automatico**: ogni volta che salvi una traccia, l'app rileva
  se hai percorso un segmento conosciuto e lo cronometra
- **Personal Best**: il tuo miglior tempo viene salvato e confrontato
- **Leaderboard segmento**: top 100 con avatar, tempo, data, velocità media
- **KOM/QOM**: il primo posto assoluto (King/Queen of the Mountain)
- Dialog risultati post-traccia con notifica nuovo PB o nuovo record

---

## 📊 8. Statistiche & Analisi

### Dashboard personale
- Hero: distanza totale all-time
- Stat card: dislivello totale, ore totali, numero tracce
- Sfida settimanale corrente
- Entry point Report Mensile
- Record personali (più lunga / più alta / più lunga durata)
- Grafico a torta per tipo di attività
- Grafico time series con filtri (settimana / mese / anno)

### Track detail completo
- Mappa con polyline colorata per velocità o quota
- Grafico altimetrico con interazione (touch sulla curva → punto sulla mappa)
- Grafico HR per zone (riposo / leggera / aerobica / soglia / massima)
- Stats per chilometro
- Foto allegate con thumbnail
- Pulsanti share, esporta, modifica

### Storico tracce
- Lista paginata con thumbnail mappa
- Stats inline (distanza, durata, dislivello)
- Filtri per attività, periodo, lunghezza
- Ricerca testuale (in roadmap)

---

## 📦 9. Esportazione & Integrazione

### Formati di export
- **GPX** (sempre, standard universale)
- **TCX** (Garmin, TrainingPeaks)
- **FIT** (Garmin Connect, Wahoo, Bryton — formato nativo dei dispositivi)
- **KML** (Google Earth, visualizzazione 3D)

### Health & Fitness sync
- **Apple Health** (iOS): import HR + steps + calories, export workout
- **Google Health Connect** (Android): stessa logica
- Configurazione frequenza cardiaca massima personalizzata

### Web sharing (Open Graph)
Link pubblici con preview ricche su Whatsapp, Facebook, Twitter, email.
Server-side rendering della scheda traccia/tour con thumbnail mappa,
stats, foto principale.

---

## 🎨 10. Personalizzazione & UX

### Tema visivo
- **Light mode** classico
- **Dark mode** completo, app-wide, con sistema `ThemeColorsExtension`
  che adatta automaticamente tutti i testi e i bordi al tema corrente
- **System** segue le preferenze del telefono

### Tipografia premium
- Display: **Outfit** (geometrico moderno)
- Body: **DM Sans** (alta leggibilità)
- Tabular figures sulle statistiche per evitare il "ballo" delle cifre
  durante il tracking live

### Empty states topografici
Quando non ci sono ancora tracce/dati, illustriamo lo stato vuoto con
linee di livello topografiche custom-painted, coerenti col mood outdoor
dell'app. Tre varianti diverse a seconda del contesto.

### Lingua
- 🇮🇹 Italiano completo
- 🇬🇧 English completo
- Localizzazione testi via ARB con plurali ICU

### Onboarding
4 schermate al primo avvio focalizzate su: cosa fa l'app, sicurezza
(Lifeline), pubblicazione community, prima registrazione. Tutorial REC
specifico al primo tap del pulsante di registrazione.

### Discovery prompts
Card contestuali in cima alla Discover che suggeriscono cosa fare dopo:
configura Lifeline (se hai 2+ tracce e non hai contatti), crea il primo
tour (se hai 5+ tracce e nessun tour), prova lo sharing web, esporta in
FIT, prova il planner, ecc. Dismissibili individualmente con persistenza.

---

## 🔒 11. Privacy & Conformità

- **Privacy Policy** dedicata e aggiornata
- **Terms of Service** con sezione specifica sulle limitazioni di Lifeline
- **GDPR-ready**: eliminazione completa account dall'app con cancellazione
  a cascata di tracce, profilo, badge, follower
- **Permission minime**: la migrazione del manifest Android per essere
  conforme alle policy Google Play sui permessi foto/video è completata
- **Dati locali first**: tracce salvate prima localmente, poi sincronizzate.
  Se vuoi, lavori offline e sincronizzi solo quando rientri in Wi-Fi.
- **Token di condivisione** per Lifeline che si auto-invalidano al termine
  della sessione

---

## 🌐 12. Backend & Affidabilità

- Firebase Firestore per data layer real-time
- Firebase Auth per identità (email, Apple, Google)
- Firebase Cloud Functions per operazioni server-side critiche
- Firebase Cloud Messaging (FCM) per notifiche push
- Firebase Hosting per il sito `trailshare.app` e le pagine di sharing
- Architettura ottimizzata per offline-first

---

## 🚀 13. Roadmap Premium (v2.0+) — In arrivo

In sviluppo per la prossima major release. Modello **freemium**: tutto
quello che c'è oggi resta gratis, queste sono **funzioni "wow" extra**.

### TrailShare Pro

#### Mountain Recognition (parzialmente gratis)
**Free:** Riconoscimento cime in tempo reale tramite la fotocamera. Punta
il telefono verso la montagna e vedi sovrapposti il nome, l'altitudine e
la distanza delle cime davanti a te (top 5 cime visibili). Realtà aumentata
basata su GPS + bussola + giroscopio. Database OpenStreetMap di tutte le
cime italiane (~12.000 vette).

**Pro:** Scatta una foto del panorama e ricevi tutte le cime identificate
(non solo 5), salvataggio in galleria, immagine annotata condivisibile sui
social, archivio personale di "cime conquistate".

#### 3D Fly-through replay (Pro)
Rivedi le tue tracce in 3D con vista terreno reale. Vola lungo il percorso
con animazione cinematografica, perfetto per condividere video sui social.

#### Mappe topografiche premium offline (Pro)
- IGM Italia (Istituto Geografico Militare)
- Swisstopo (Svizzera)
- Tirol Atlas (Austria)
Layer ad alta risoluzione con curve di livello a 10m, ideale per ferrate,
escursioni alpine impegnative, fuori sentiero.

#### Allenamento HR personalizzato (Pro)
Genera piani di allenamento mirati basati sul tuo storico tracce,
frequenza cardiaca, obiettivi (es. "preparati per il giro del Cervino").
Sessioni programmate con notifiche.

#### Trail conditions AI (Pro)
Riassunto AI delle condizioni recenti di un percorso analizzando i
commenti e le segnalazioni della community degli ultimi 30 giorni.
"Negli ultimi 7 giorni: 3 utenti hanno segnalato fango pesante nella prima
metà, una traccia chiusa al guado del torrente."

#### Pianificatore IA "trova un percorso simile a..." (Pro)
Inserisci distanza, dislivello, zona o un percorso già fatto. L'AI ti
propone 3 alternative dalla community simili per profilo e difficoltà.

#### Time-lapse video automatico (Pro)
Genera un video time-lapse della tua giornata mescolando GPS animato +
foto + statistiche, pronto per Instagram/TikTok/Reels.

#### Pricing previsto
- **€2,99/mese** o **€19,99/anno** (sconto -44%)
- **Trial 14 giorni gratis** dal Discovery prompt
- **Lifetime discount -30%** per utenti attivi (>50 tracce) al lancio
- **Family sharing** nativo Apple/Google: un abbonamento per 6 membri

---

## 🌟 Differenziatori chiave (per messaggio brochure)

Quando devi spiegare in 3 punti perché TrailShare:

1. **Sicurezza vera**: Lifeline con auto-alert, SMS fallback, health-check
   real-time. Nessun'altra app italiana ha questo livello di copertura.
2. **Made in Italy, per l'Italia**: 14 tipi di attività incluse quelle
   alpine (scialpinismo, racchette), 20 regioni nelle classifiche,
   integrazione con la community italiana che cresce ogni settimana.
3. **Qualità dei dati**: tracce stat-accurate grazie a elaboration GPS
   evoluta (filtro mediano, smoothing, isteresi), formato di export
   completo (GPX/TCX/FIT/KML), sharing web con preview ricche.

E poi ci aggiungi:
- Gratis al 100% per il core, premium solo per le wow non indispensabili
- Italiano + Inglese
- Dark mode completa
- iOS + Android nativi (Flutter)

---

## 📝 Asset disponibili per la brochure

- Logo TrailShare (PNG nel root)
- Screenshot recenti (da fare al momento della finalizzazione)
- Sito web vetrina su `trailshare.app`
- Icona app vettoriale
- Palette colori: primary `AppColors.primary` (verde outdoor), success
  `AppColors.success`, accenti per le diverse feature

---

## 🎯 Target audience suggerito

- **Primario**: escursionisti italiani 25-55 anni, da occasionali a esperti,
  che cercano sicurezza + community vera (non finta come Strava per i
  professionisti)
- **Secondario**: trail runner amatoriali, mountain biker, sci-alpinisti,
  appassionati di outdoor in genere
- **Lungo termine**: turisti stranieri che fanno trekking in Italia
  (versione EN già completa)

---

## 📞 Contatti progetto

- Sito: `trailshare.app`
- Email contatto: `info@trailshare.app`
- Repository: github.com/todmax67/trailshare-flutter
- Versione corrente in produzione: 1.7.0
- In test: 1.9.0

---

*Documento mantenuto in `docs/FEATURES.md` — aggiornare ad ogni release
maggiore o introduzione di feature significativa.*
