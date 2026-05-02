# TrailShare Business — Pricing & Tier

Documento di prodotto, decisioni del 2026-05-02.

I gruppi Business sono **a pagamento dal primo livello** (no free tier per
i business). Gli utenti finali che entrano nei gruppi Business **restano
sempre gratis** — il modello commerciale colpisce solo chi vuole
"apparire" come servizio/pubblicità sulla piattaforma.

Pagamenti gestiti via **Stripe**, **fuori dagli store** Apple/Google,
per evitare la commissione 15-30% e massimizzare il margine.
L'integrazione Stripe è in attesa di consulto commercialista — finché
non parte, il flag `isBusinessGroup` viene attivato manualmente dal
super admin per clienti seed e demo.

---

## Tier

### Verified — €19.99/mese o €199/anno (-17%)

Per: rifugi, guide alpine, B&B outdoor, piccoli MTB club, organizzatori
di eventi locali, piccole pro loco.

Funzioni incluse:

- Logo personalizzato + badge "verificato"
- Cover image 16:9 sul tab Info del gruppo
- Colore brand custom (palette guidata, 12 colori)
- Card invito brandizzata: PNG 9:16 con QR del codice invito,
  condivisibile su social/WhatsApp/stampa
- Hero card differenziata nelle liste (cover banner + bordo accent +
  pill BUSINESS)
- Statistiche aggregate **base**:
  - membri totali del gruppo
  - quante volte ogni traccia condivisa è stata seguita (cumulativo)
  - quanti utenti sono entrati via QR brandizzato
- **Cap**: 10 tracce condivise nel gruppo, 4 eventi attivi insieme
- **Trial 14 giorni** senza carta richiesta. Allo scadere, se Stripe
  non è configurato, il gruppo perde i privilegi Business e torna
  visualizzato come gruppo standard (asset preservati, riattivabili
  con subscription).
- **1 gruppo per subscription**.

### Pro — €49.99/mese o €499/anno (-17%)

Per: tour operator, consorzi turistici, brand outdoor, sezioni CAI
grandi, organizzatori di gare, federazioni sportive locali.

Tutto Verified +:

- Tracce condivise e eventi **illimitati**
- **Featured placement** nella discovery (priorità nel sort dei gruppi
  pubblici)
- **Pinned post** nel chat del gruppo (annuncio fisso modificabile
  dall'admin)
- Notifiche **push + email** ai membri per nuove tracce/eventi
- Statistiche **avanzate**:
  - timeline mensile (delta nuovi membri, follow, eventi)
  - breakdown geografico utenti (per provincia/regione)
  - funnel di acquisizione: "QR visto → join → traccia seguita"
- **Team admin**: fino a 5 admin oltre al founder
- Esportazione lista membri in CSV per CRM proprio
- 1 gruppo per subscription. Upgrade pro-rata da Verified.
- **Niente trial**.

### Enterprise — custom

Per: brand grandi (Salewa, La Sportiva), consorzi multi-rifugio,
federazioni nazionali, eventi con sponsor.

- Multi-gruppo sotto un solo account commerciale
- White label: il QR può puntare a un sottodominio del cliente
- API per export programmatico dati e integrazione CRM
- Onboarding dedicato + priority support
- Co-branding negli eventi pubblicati

Pricing su preventivo, contatto commerciale.

---

## Promo lancio

**Early Adopter — -30% lifetime**

I primi 20 clienti Verified che firmano un piano **annuale** entro i
primi 6 mesi dal lancio Stripe ottengono uno sconto del 30%
**permanente** sul rinnovo.

- Verified annuale Early Adopter: **€139/anno** (≈€11.50/mese)
- Comunicato chiaramente come "primi 20 posti", crea urgenza
- Tracking via campo `earlyAdopter: true` su account Stripe customer

---

## Razionale prezzi

- **€19.99 Verified**: stesso ordine di grandezza × 10 del Pro
  consumer (€19.99/anno). Marketing istantaneo: "come 10 abbonamenti
  consumer regalati al cliente". Sotto la barriera psicologica dei €20
  mensili, sweet spot per outdoor B2B italiano.
- **€49.99 Pro**: 2.5× il Verified annuale. Justifica upsell
  (illimitato + featured + analytics + team admin), sotto i €500 anche
  qui psicologicamente.
- **Promo lifetime invece di prezzo basso permanente**: più facile
  alzare dopo via promo che alzare il listino (alzare il listino =
  churn quasi garantito).
- Riferimenti consumer (AllTrails Pro €36/anno, Komoot Premium
  €60/anno) **non si applicano** al B2B: mercati diversi, value driver
  diversi (visibilità/canale vs. ricreazione personale).

---

## Da definire con commercialista

- IVA inclusa o esclusa nel listino mostrato in app/sito?
- Fattura elettronica automatica dopo pagamento Stripe (richiesta in
  Italia per B2B): integrazione con quale provider (Fatture in Cloud,
  Aruba, FattureGB)?
- Tassazione abbonamenti ricorrenti SaaS B2B
- Gestione reverse charge UE per clienti esteri (es. rifugi austriaci)
- Termini contrattuali e condizioni di recesso
- Gestione churn / mancato pagamento (grace period? freeze?)

---

## Roadmap implementazione (post-decisione)

1. Statistiche aggregate base (in arrivo, indipendente da Stripe)
2. Cap su Verified (tracce, eventi) — gating client + Cloud Function
3. Stripe Checkout + Customer Portal + webhook subscription events
4. Trial 14 giorni Verified (stato gruppo `business_trial_until`)
5. Featured placement + pinned post (Pro)
6. Statistiche avanzate (Pro)
7. Team admin + CSV export (Pro)
8. Enterprise: white label e API (su richiesta cliente)
