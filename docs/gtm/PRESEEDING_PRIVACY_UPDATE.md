# Privacy Policy & Terms — update per Spazi Pro pre-seeded

Documento operativo: sezioni **drop-in** da aggiungere a
`trailshare.app/privacy` (HTML) e `trailshare.app/terms` (HTML)
PRIMA di mettere in produzione il primo batch di Spazi Pro
generati automaticamente (Epic 7.H).

Senza questi aggiornamenti, il pre-seeding espone TrailShare a
reclami GDPR (Garante Privacy IT, autorità EU).

---

## 🛡️ Base legale

Il trattamento dei dati pubblici di attività commerciali per
creare schede informative TrailShare è basato su:

- **Art. 6.1.f Regolamento UE 2016/679 (GDPR)**: interesse
  legittimo del titolare del trattamento (TrailShare) a fornire
  un servizio di discovery outdoor utile alla collettività,
  bilanciato dai diritti dei soggetti coinvolti (attività
  commerciali registrate, dati già pubblicamente disponibili).
- Riferimento a directory commerciali simili: Google My Business,
  Tripadvisor, AllTrails — pattern consolidato e accettato dalle
  autorità privacy EU per dati di natura business-public.

---

## 📄 Sezione da AGGIUNGERE alla Privacy Policy

Inserire come nuova sezione subito dopo "Dati che raccogliamo
direttamente dall'utente", PRIMA della sezione "Diritti
dell'interessato":

---

### Schede informative pre-generate ("Spazi Pro non rivendicati")

TrailShare può creare automaticamente schede informative
relative ad **attività commerciali outdoor pubbliche** —
rifugi alpini, bivacchi, scuole di alpinismo, guide alpine
professionali, negozi di attrezzatura, noleggi e-bike,
consorzi turistici — operanti sul territorio italiano.

**Cosa pubblichiamo**:

- Denominazione dell'attività (come registrata pubblicamente)
- Indirizzo e coordinate geografiche
- Numero di telefono e sito web, **solo se già pubblicati
  liberamente** dall'attività su:
  - OpenStreetMap (licenza ODbL)
  - Sito web ufficiale dell'attività
  - Registro Imprese / Camera di Commercio
  - Sito CAI per i rifugi del Club Alpino Italiano

**Cosa NON pubblichiamo** nelle schede non rivendicate:

- Foto del locale o degli interni
- Listino prezzi e servizi
- Orari di apertura dettagliati
- Email o numeri di cellulare personali del gestore
- Recensioni o valutazioni
- Qualsiasi contenuto non verificabile da fonti pubbliche

**Base legale**: art. 6.1.f GDPR (interesse legittimo) — fornire
un servizio di scoperta sentieri integrato con i punti di appoggio
del territorio è funzionale al nostro scopo di sicurezza in
montagna e supporto all'outdoor italiano.

**Indicazione visiva chiara**: ogni scheda non rivendicata mostra
in alto un banner permanente "_Questa scheda è stata generata
automaticamente da fonti pubbliche. Sei tu il gestore?_" con
link al flusso di rivendicazione e al modulo di rimozione.

**Diritto di rimozione (opt-out immediato)**: il legale
rappresentante dell'attività può richiedere la rimozione della
propria scheda inviando una email a
`info@trailshare.app` con oggetto "Rimuovi scheda {nome
attività}". La rimozione avviene **entro 48 ore lavorative** dal
ricevimento della richiesta, senza necessità di motivazione.
Resta facoltativa la verifica dell'identità del richiedente
(scansione documento o PEC) nei soli casi dubbi.

**Diritto di rettifica**: il gestore può segnalare informazioni
errate cliccando "Segnala errore" sulla scheda pubblica. La
correzione avviene entro 7 giorni lavorativi previa verifica
con la fonte pubblica originale.

**Diritto di rivendicazione**: il gestore può rivendicare la
scheda compilando il form `Claim this space`. La verifica avviene
tramite:
- Email PEC dell'attività, OPPURE
- Codice univoco inviato al numero di telefono pubblico
  dell'attività, OPPURE
- Documentazione P.IVA + visura camerale aggiornata

Una volta rivendicata, la scheda passa al pieno controllo del
gestore (modifica testi, foto, listino, orari) e il banner di
disclaimer viene rimosso.

---

## 📄 Sezione da AGGIUNGERE ai Terms of Service

Inserire come nuovo paragrafo subito dopo "Account utente",
PRIMA di "Limitazione di responsabilità":

---

### Schede attività commerciali outdoor

TrailShare può pubblicare automaticamente schede informative
relative ad attività commerciali outdoor (rifugi, guide, noleggi,
scuole alpinismo, consorzi turistici) operanti sul territorio
italiano, sulla base di dati raccolti da fonti pubbliche
verificabili (OpenStreetMap, siti ufficiali, Registro Imprese,
Club Alpino Italiano).

Queste schede sono identificate come **"Spazi Pro non
rivendicati"** tramite un banner visibile e contengono solo
informazioni di natura strettamente pubblica.

Il legale rappresentante dell'attività ha diritto in qualunque
momento di:

1. **Rivendicare la scheda** prendendone il pieno controllo
   gratuitamente (tier `Verified` o successivi a pagamento
   secondo il listino vigente)
2. **Richiedere la rimozione** della scheda entro 48 ore
   lavorative scrivendo a `info@trailshare.app`
3. **Segnalare informazioni errate** per correzione entro 7
   giorni lavorativi

TrailShare non è responsabile di eventuali informazioni datate
sulle schede non rivendicate, ferma restando l'attività di
auto-refresh mensile dei dati da OpenStreetMap. Si invitano i
gestori a rivendicare le proprie schede per garantire
informazioni sempre aggiornate ai visitatori.

L'esistenza di una scheda non rivendicata **non implica alcun
rapporto commerciale** tra TrailShare e l'attività, né alcuna
relazione di partnership o endorsement. TrailShare agisce come
directory informativa di pubblica utilità.

---

## 🇮🇹 Note specifiche per il contesto italiano

### Garante Privacy
Il pattern "directory di attività commerciali pubbliche con base
legale interesse legittimo" è accettato dal Garante italiano per
servizi di pubblica utilità. Riferimenti:

- Provvedimento Garante n. 161/2014 — directory aziendali su dati pubblici
- FAQ Garante "Trattamento dati di natura pubblica per finalità di interesse legittimo"

### CAI (Club Alpino Italiano)
I dati dei rifugi del CAI sono pubblicati sul sito ufficiale
`cai.it` con licenza implicita d'uso pubblico (vedi sezione
"Strutture ricettive del Club Alpino Italiano"). Citare la fonte
nelle schede pre-popolate è raccomandato ma non strettamente
obbligatorio (i dati sono di pubblica utilità).

### OpenStreetMap (ODbL)
I dati OSM sono sotto licenza Open Database License (ODbL). La
licenza richiede attribuzione: ogni scheda pre-popolata da OSM
deve mostrare nel footer "_Dati cartografici e di base © OpenStreetMap contributors,
licenza ODbL_" (già presente nei TileLayer dell'app, da
aggiungere anche alle pagine /b/{slug} statiche).

### Registro Imprese
Visura camerale base (denominazione + indirizzo + P.IVA) è
gratuita e di pubblica consultazione. Non ci sono limitazioni
all'uso per directory di pubblica utilità.

---

## ⚖️ Checklist pre-go-live

Prima di abilitare il primo batch di Spazi Pro `unclaimed` in
produzione:

- [ ] Sezione "Schede informative pre-generate" aggiunta a
      `trailshare-website/privacy.html`
- [ ] Sezione "Schede attività commerciali outdoor" aggiunta a
      `trailshare-website/terms.html`
- [ ] Email `info@trailshare.app` monitorata 7gg/7 (auto-reply
      "richiesta ricevuta, risposta entro 48h")
- [ ] Procedura interna scritta per processare opt-out (chi
      verifica? quale doc richiediamo? tempo SLA?)
- [ ] Banner disclaimer testato visivamente su mobile + desktop
- [ ] Footer attribuzione OSM presente su `/b/{slug}` pubbliche
- [ ] Form "Segnala errore" funzionante con email destinazione
- [ ] Test claim flow end-to-end con un rifugio reale consenziente
      (es. Rifugio Curò già seed client)

## 📞 In caso di reclamo formale

Se ricevete email/PEC da legale rappresentante che contesta la
scheda:

1. **Risposta entro 24h** con conferma ricezione
2. **Rimozione immediata** della scheda se richiesta esplicita
3. **Non chiedere prove** di rappresentanza se la richiesta è
   coerente (nome + email aziendale OK) — sotto soglia di rischio
4. **Conservare la corrispondenza** per 5 anni come prova di
   compliance (storage Firebase + backup locale)

In caso di richieste avvocato/Garante, escalare immediatamente a
consulente legale di fiducia. NON rispondere autonomamente.
