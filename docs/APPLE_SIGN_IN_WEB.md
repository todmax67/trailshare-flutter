# Apple Sign-in Web — Procedura di setup

Lato Flutter il codice è già pronto (`lib/web/pages/web_login_page.dart`,
metodo `_signInWithApple`). Per attivarlo serve configurare un
**Service ID + key** su Apple Developer e collegarli al provider
Apple di Firebase Auth.

Richiede:
- Account Apple Developer attivo (€99/anno)
- Bundle ID iOS dell'app TrailShare (App ID già esistente, es.
  `com.trailshare.app`)
- ~30 minuti di lavoro su due console

---

## 1. Apple Developer Console — Service ID

1. Vai su https://developer.apple.com/account → **Certificates,
   Identifiers & Profiles**.
2. **Identifiers** → tasto `+` → seleziona **Services IDs** → Continua.
3. Compila:
   - **Description**: `TrailShare Web Sign In`
   - **Identifier** (reverse-DNS, deve essere unico globalmente):
     `app.trailshare.signin` (esempio — adatta al tuo schema)
4. Continua → Register.
5. Apri il Service ID appena creato → spunta **Sign in with Apple**
   → click "Configure" accanto.
6. **Primary App ID**: seleziona l'App ID dell'app iOS di TrailShare
   (es. `com.trailshare.app`).
7. **Domains and Subdomains**: aggiungi
   ```
   trailshare-5334b.firebaseapp.com
   ```
   (è l'auth handler di Firebase: `<projectId>.firebaseapp.com`)
8. **Return URLs**: aggiungi
   ```
   https://trailshare-5334b.firebaseapp.com/__/auth/handler
   ```
9. Save → Continue → Save.

---

## 2. Apple Developer Console — Sign in with Apple Key

1. **Keys** → tasto `+`.
2. **Key Name**: `TrailShare Sign In Key`.
3. Spunta **Sign in with Apple** → "Configure".
4. **Choose a Primary App ID**: stesso App ID iOS del passo 1.6.
5. Save → Continue → Register.
6. **Scarica il file `.p8`** — viene mostrato **una sola volta**, non
   è recuperabile dopo. Salvalo in posto sicuro
   (es. password manager / cassaforte locale).
7. Annota il **Key ID** (10 caratteri, mostrato nella schermata) e il
   **Team ID** (visibile in alto a destra di Apple Developer → click
   sul nome del team → Membership Details).

---

## 3. Firebase Console — Provider Apple

1. https://console.firebase.google.com/project/trailshare-5334b →
   **Authentication** → **Sign-in method**.
2. Click su **Apple** (se è in stato Disabled) → **Enable**.
3. Compila:
   - **Service ID**: `app.trailshare.signin` (quello del passo 1.3)
   - **Apple Team ID**: il team ID del passo 2.7
   - **Key ID**: dal passo 2.7
   - **Private key**: apri il file `.p8` con un editor di testo,
     copia **tutto** il contenuto incluse le righe
     `-----BEGIN PRIVATE KEY-----` e `-----END PRIVATE KEY-----`,
     incolla nel campo.
4. (Opzionale ma consigliato) **Configure Email Relay Service**:
   permette ad Apple di mostrare l'opzione "Hide my email" agli
   utenti. Apple genera un alias `xxx@privaterelay.appleid.com` che
   inoltra le email a quella reale dell'utente. Per attivarlo serve
   verificare il dominio mittente delle email transazionali su
   Apple Developer (servizio ECRS). **Non bloccante**.
5. Save.

---

## 4. Verifica

1. Build + deploy:
   ```bash
   flutter build web --target=lib/main_web.dart --release
   firebase deploy --only hosting:webapp
   ```
2. Apri https://trailshare.web.app → click "Continua con Apple"
   → si apre popup Apple ID → login.
3. Al successo torni sulla pagina loggato come l'utente Apple.

Se il login fallisce con `auth/operation-not-allowed`: il provider
Apple non è abilitato in Firebase (passo 3).
Se fallisce con redirect URI mismatch: Return URL nel Service ID non
combacia con il Firebase auth handler (passo 1.8).
Se il popup si chiude subito senza errore: probabile blocco popup
del browser o `localhost`/dominio non in **Authorized domains** di
Firebase Auth (Settings → Authorized domains).

---

## Note

- L'utente Apple a volte arriva con email `xxx@privaterelay.appleid.com`
  (Hide my email): vale come email valida lato Firebase, ma se vuoi
  inviargli newsletter hai una deliverability ridotta.
- Il nome dell'utente è mostrato **solo al primo login**. Salvarlo
  subito su Firestore (campo `displayName`) per non perderlo.
- Apple richiede di mostrare un button conforme alle linee guida
  di Human Interface (sfondo nero, logo Apple bianco, testo
  "Continua con Apple"). Il bottone Flutter attuale rispetta queste
  guidelines.
