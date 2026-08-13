# Istruzioni per chi lavora su questo repository

Vale per le persone e per gli agenti. Le regole qui sotto non sono consigli:
sono nate ognuna da una cosa andata storta.

## 1. I dati di produzione non si toccano per capire il codice

**In questo repository esiste una chiave che apre il Firebase di produzione**:
`functions/serviceAccountKey.json`. È in `.gitignore` e non è mai finita nella
storia, ma sta sul disco di chi sviluppa, e chi ha accesso alla cartella ha
accesso agli utenti veri.

Da qui una regola secca:

> **Nessuna indagine sul comportamento del codice deve leggere dati di
> produzione.** Non `listUsers()`, non query su Firestore di produzione, non
> lettura di documenti di utenti reali — nemmeno per «capire meglio», nemmeno
> filtrando, nemmeno se il dato serve davvero.

Se per rispondere a una domanda servono dati veri, la strada è **chiederlo a chi
possiede il progetto**, spiegando quale dato serve e perché. Non è una formalità:
i dati sono di altre persone, e la comodità di chi indaga non è un titolo per
guardarli.

**Cosa fare invece**, in ordine di preferenza:

1. leggere il codice e ragionare;
2. riprodurre sul proprio dispositivo con il proprio account;
3. usare gli emulatori Firebase o un progetto di prova;
4. chiedere.

### Perché c'è scritto

Il 2026-08-13, indagando su un logout ricorrente, un agente incaricato di
**leggere il codice** ha trovato la chiave di servizio, si è collegato alla
produzione ed ha eseguito un `listUsers()` in ciclo per verificare se il founder
avesse più account. Nelle trascrizioni sono finiti sessanta UID di utenti reali.
Le trascrizioni sono state cancellate, ma il punto resta: **l'istruzione diceva
"leggi il codice ed esegui comandi", e non vietava la produzione.** L'agente non
ha disobbedito — nessuno gli aveva detto di no.

Chi assegna un compito di indagine ha la responsabilità di scrivere questo
limite. Ora è scritto qui una volta per tutte.

## 2. Le build di test e quelle da Play hanno firme diverse

`android/app/build.gradle` firma anche le build di debug con la chiave di
rilascio, **se `key.properties` esiste**. Nei worktree quel file di solito non
c'è, e allora si ripiega sulla chiave di debug.

Conseguenza da conoscere prima di installare qualcosa sul telefono di qualcuno:
Android identifica un'app dalla coppia *applicationId + firma*. Due firme diverse
non possono sostituirsi: **si disinstalla e si reinstalla**, e la
disinstallazione porta via i dati privati **e revoca tutti i permessi** —
Health Connect compreso.

Il 2026-08-12 è successo: dopo aver passato dalle build locali a quella da Play,
la Dashboard salute è rimasta vuota e l'utente ha creduto di aver perso lo
storico. Non era vero: erano i permessi.

**Per provare una build senza perdere i dati**, caricarla su Play come test
interno: arrivando da Play ha la stessa firma e si installa come aggiornamento.

## 3. «Non lo so» non è «non c'è»

Ricorre in tutto il progetto ed è la regola di scrittura più importante.

Un buco nel modello del terreno non vale zero metri sul livello del mare. Un
permesso mancante non è un archivio vuoto. Una cima che non possiamo dimostrare
nascosta non è una cima visibile. Un rifugio di cui non conosciamo le aperture
non è un rifugio chiuso.

Ogni volta che il codice trasforma un'incertezza in un'affermazione, qualcuno a
valle prende una decisione sbagliata — e non ha modo di accorgersene. Se non si
sa, si dice che non si sa.

## 4. I commenti spiegano il perché, non il cosa

Il codice dice già cosa fa. Un commento che lo ripete invecchia e mente.

Quello che il codice **non** può dire è perché una scelta è stata fatta, quale
alternativa più ovvia è stata scartata e per quale motivo, e quale difetto reale
ha prodotto quella riga. Sono quelle le informazioni che si perdono, e sono le
uniche che valga la pena scrivere.

Stessa cosa per i messaggi di commit: raccontano il problema, non l'elenco dei
file toccati — quello lo dice `git`.
