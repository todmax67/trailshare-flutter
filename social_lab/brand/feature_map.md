# Feature Map TrailShare v1.9.0+52

Riferimento per il social-manager. **Non citare feature non presenti qui**. Per ogni area: cosa c'e, cosa dire (angle social), cosa non dire.

---

## Core tracking

**Cosa c'e**: GPS real-time, **14 sport supportati ufficialmente** (trekking, trail running, MTB, sci, snowshoe, ciclismo, ecc. — il numero comunicato e' 14, anche se il modello dati interno gestisce piu' tipi), bussola integrata con compass-up navigation, mappe interattive, campionamento intelligente dei punti, correzione elevazione da API OpenTopoData, **rilevamento automatico crash/inattivita**, **auto-detect attivita** (l'app riconosce se inizi a correre/camminare), **battery saver** ottimizzato.

**Angle social**: "l'app che si adatta a qualsiasi attivita outdoor", "bussola integrata gratis, niente app separate", "tracce precise anche con GPS impreciso".

**Non dire**: numeri di precisione GPS in metri (dipende dal dispositivo). Non dire "40+ attivita" (vecchio numero) — ufficialmente comunichiamo **14 sport**.

---

## Lifeline (SOS / sicurezza) — **il differenziatore numero 1**

**Cosa c'e** (vedi slide 04):
- **Live tracking** — i tuoi cari vedono in tempo reale dove sei (link pubblico aggiornato live)
- **Auto-alert inattivita** — se durante la registrazione non tocchi lo schermo per X minuti → allarme sonoro + vibrazione + wake-screen forzato anche con telefono in tasca + notifica heads-up Android max priority. Se non confermi "tutto bene" → escalation automatica
- **Pulsante 112** — sempre accessibile in un tap dalla schermata di registrazione. Chiama direttamente il numero unico di emergenza europeo
- **Health Check Live** — usa i dati HR (cardiofrequenzimetro BLE / wearable) per rilevare anomalie durante l'attivita
- **SMS Fallback** — se non c'e dati ma c'e segnale GSM, comunica con i contatti emergenza via SMS
- **Backup & Retry** — sistema multi-canale: la notifica viene re-tentata in piu' modi se il primo fallisce
- Contatti emergenza configurabili (fino a 3)

**Angle social**: "vai in montagna da solo con piu' sicurezza", "nessuno sa dove sei? Lifeline lo dice per te se ti succede qualcosa", "112 in un tap, anche con guanti", "Strava e Komoot non hanno niente di simile".

**Non dire**: "salva vite" (legale complicato), "sostituisce il soccorso alpino" (non e' vero — affianca), "garantito" (dipende da segnale).

---

## Post-tracciata

**Cosa c'e**: statistiche automatiche (distanza, D+/D-, tempo totale/movimento, velocita media, cadenza, HR se connesso), foto geolocalizzate lungo la traccia, trail conditions crowdsource (segnala fango/neve/asfalto).

**Angle social**: "i tuoi dati, chiari", "foto ancorate al punto della traccia", "dai una mano alla community segnalando condizioni reali".

---

## Export multi-formato — **differenziatore tecnico**

**Cosa c'e**: export in **GPX, KML, TCX, FIT**.

**Angle social**: "porti le tue tracce su Garmin, Wahoo, Suunto senza compromessi", "Strava ti da solo GPX, e solo se sei Premium. Noi 4 formati gratis."

---

## POI e Navigation

**Cosa c'e**:
- 10 tipi di POI marcabili: fontana, rifugio, panorama, pericolo, parcheggio, ristoro, bagno, campeggio, storico, natura
- **Guida vocale italiana**: mentre cammini, annunci audio ("Fontana tra 100 metri")
- Turn-by-turn su tracce con steps di navigazione
- Import sentieri CAI via Waymarked Trails
- Import da GPX, KML, FIT, TCX di altre app

**Angle social**: "mentre cammini, TrailShare parla per te", "scopri un sentiero CAI vicino a casa", "i tuoi POI preferiti, sempre dove li hai messi".

---

## Social / Community

**Cosa c'e**:
- Pubblicazione tracce pubbliche con cheers (like)
- Commenti sulle tracce (novita v1.9.0)
- Followers / Following + feed
- **Gruppi locali** con chat, eventi RSVP, sfide private
- Tour multi-giorno (aggrega 2+ tracce in un itinerario tipo "cammino in 3 tappe")
- Recensioni sentieri con voto 1-5 stelle

**Angle social**: "crea un gruppo con i tuoi compagni di escursione", "commenta direttamente sotto la traccia, non sul feed", "organizza un'uscita di gruppo con RSVP".

---

## Gamification

**Cosa c'e**:
- **13 badge**: distanza (Primi Passi 1 traccia, Camminatore 10 km, Escursionista 50 km, Maratoneta 100 km, Ultra Runner 500 km), elevazione (Scalatore 1000m D+, Alpinista 5000m, Conquistatore 10000m), social (Influencer 5 followers, Popolare 50 cheers), streak (Costante 3 gg, Fedele 7 gg, Campione 30 gg)
- Sistema XP con livelli
- **Sfide settimanali personali** (v1.9.0): ogni lunedi una sfida generata su misura sulla base delle tue medie (distanza, dislivello, numero tracce, durata)
- Sfide mensili
- Segmenti/KOM su sentieri CAI

**Angle social**: "13 badge da sbloccare", "ogni lunedi una sfida pensata per te", "quanto ci metti a fare i primi 100 km?".

---

## Classifiche — **differenziatore italianita**

**Cosa c'e**:
- Leaderboard globale all-time per XP totali
- **Classifiche regionali** (v1.9.0) per tutte le 20 regioni italiane, con tab "All-time" e "Mese in corso" (distanza)

**Angle social**: "sei nella top 10 della tua regione?", "classifica mensile che si resetta — puoi sempre risalire", "ogni regione ha la sua top".

---

## Reporting

**Cosa c'e**:
- **Report mensile "Il mio mese"** (v1.9.0): automatico il primo giorno del mese successivo. Contiene totali (km, D+/D-, durata, moving time, tracce, giorni attivi), breakdown per attivita, personal best, confronto % YoY, badge sbloccati nel mese, XP guadagnati
- Dashboard con pie chart attivita
- Discovery carousel che notifica quando il report e' pronto

**Angle social**: "a fine mese TrailShare ti regala il tuo report", "wrapped stile Spotify ma per le tue escursioni".

---

## Integrazioni wearable / health

**Cosa c'e**:
- **Cardiofrequenzimetro BLE**: connette fasce cardio standard (Heart Rate Service) per HR real-time
- **Health Connect** (Android) e **HealthKit** (iOS): legge HR, respiration rate, calorie da wearable
- **Sync bidirezionale Garmin** tramite Health Connect bridge

**Angle social**: "connetti la tua fascia cardio e vedi il HR durante la traccia", "Garmin sync automatico, senza passare per Strava".

---

## Mappe offline

**Cosa c'e**: scarica tile per area geografica, disponibili offline durante la traccia, fallback automatico a rete.

**Angle social**: "niente rete? La traccia continua", "scarica la zona prima di partire".

---

## Personalizzazione / profilo

**Cosa c'e**: tema scuro/chiaro, italiano completo, profilo utente (username, avatar, bio, regione), impostazioni POI vocali, preferenze notifiche (novita + aggiornamenti).

---

## TrailShare PRO — **in arrivo**, comunicazione cauta

**Cosa esiste**: piano premium annunciato come **"Coming Soon"** sul materiale promozionale (slide 11 carousel intro). Prezzo annunciato: **da €2,90/mese**.

**Feature in roadmap PRO** (citate sulla slide):
- Mountain Recognition AI (riconoscimento vette dall'inquadratura camera)
- 3D fly-through replay delle tracce
- Mappe topografiche premium (IGM, Geoplan)
- Allenamenti HR personalizzati
- Trail conditions con AI a meta etá

**Come comunicare**:
- OK: "TrailShare PRO sta arrivando con feature avanzate", "stay tuned per il PRO"
- OK: "tutto il core resta gratuito per sempre, il PRO aggiunge feature premium opzionali"
- **NO**: dare date precise di rilascio
- **NO**: promettere singole feature PRO ("a giugno avremo Mountain Recognition") finche non sono confermate
- **NO**: usare il PRO come hook principale dei post di acquisizione (l'hook resta "100% gratuita")
- **NO**: confondere utenti facendogli pensare che il free verra' depotenziato — chiarire sempre che il PRO e' **aggiuntivo**, non sostitutivo

**Quando usarlo nei contenuti**:
- Slide finale carousel intro (gia' c'e)
- Pinned comment sotto i reel "PS: e' arrivata anche la PRO con feature avanzate, scopri di piu' sul profilo"
- Stories teaser puntuali (1 ogni 2-3 settimane, non di piu')

---

## Feature che **NON** esistono (evita di comunicarle)

- Web dashboard pubblico (non deployato — l'HTML carousel e' interno/asset, non e' un dashboard utente)
- Social login via Facebook (solo Google + Apple)
- Meteo predittivo oltre 3 giorni (solo previsioni base)
- Analytics biomeccanica tipo Stryd power (non ce l'abbiamo)
- Pianificazione itinerari tipo Komoot avanzata (import sentieri CAI si, planning turn-by-turn da zero no)
- Live tracking di altri utenti in real-time (solo link pubblico della propria traccia)
- Mountain Recognition AI, 3D fly-through, mappe IGM (sono **PRO Coming Soon**, vedi sezione sopra — non descrivere come disponibili)

Se un draft tocca queste aree, il social-manager deve **segnalarlo al founder** invece di scriverle.
