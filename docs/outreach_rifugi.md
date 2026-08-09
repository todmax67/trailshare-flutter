# Mail ai gestori di rifugio

Testo per i contatti estratti da `scripts/build_hut_outreach.py` e classificati
da `scripts/hut_outreach_crossref.cjs`.

## Quando mandarla

**Non in agosto.** Un gestore in piena stagione ha la casa piena e legge la
posta a mezzanotte, se la legge. La finestra e' **fine settembre / ottobre**:
chiudono, si mettono a fare le carte, e hanno in testa sia le date della
stagione appena finita sia quelle della prossima — che e' esattamente cio' che
gli stiamo chiedendo.

Seconda finestra utile: **fine aprile**, quando programmano l'apertura.

## A chi

Dal CSV incrociato, in quest'ordine:

| Chi | Quanti | Variante |
|---|---|---|
| scheda esistente non rivendicata, con email | 496 | **A** |
| nessuna scheda, con email | ~5 | **B** |
| solo telefono o sito | 515 | nessuna: telefonata o modulo del sito |
| bivacchi | 253 | **non scrivere** — non hanno un gestore |

I 999 con una scheda gia' online sono il grosso, e sono anche la
conversazione piu' facile: non bisogna convincerli a esistere, ci sono gia'.

Il campo `gestore_e_organizzazione` segnala CAI, SAT, AVS e parchi: 34 rifugi
della sola SAT, 25 del CAI nazionale. Quelli **non** si contattano uno per uno —
una mail alla sezione ne sblocca decine, e scriverne trenta separate al CAI fa
sembrare che non si sappia con chi si sta parlando.

## Variante A — la scheda esiste gia'

Per i 999 con una pagina non rivendicata. Il gancio non e' l'offerta, e' il
fatto che esista gia' qualcosa su di loro che non hanno scritto loro.

**Oggetto:** `La pagina del {{nome}} su TrailShare — la puo' correggere lei`

```
Buongiorno,

su TrailShare — un'app italiana di sentieri e rifugi — esiste una pagina
del {{nome}}:

{{link_scheda}}

L'abbiamo generata da dati pubblici di OpenStreetMap, quindi e' parziale e
in qualche punto probabilmente sbagliata. Non l'ha scritta lei, e ci sembra
giusto che possa metterci mano.

La cosa che ci manca di piu' sono i **periodi di apertura**: li abbiamo per
meno di un rifugio su venti, ed e' la domanda che gli escursionisti fanno
piu' spesso.

Due modi, scelga il piu' comodo:

- prende il controllo della pagina e la aggiorna quando vuole — foto,
  descrizione, contatti, aperture: {{link_rivendica}}
- oppure risponde a questa mail con le date di apertura di quest'anno, e
  le inserisco io.

Al momento non c'e' niente da pagare. Piu' avanti ci saranno piani a
pagamento per chi vorra' funzioni in piu', e chi c'e' da adesso terra' uno
sconto permanente.

Buona chiusura di stagione,
{{firma}}
TrailShare — trailshare.app
```

## Variante B — nessuna scheda

Per i ~269 senza pagina. Manca il gancio della variante A, quindi si punta
sull'essere trovati.

**Oggetto:** `{{nome}} su TrailShare`

```
Buongiorno,

TrailShare e' un'app italiana di sentieri e rifugi. Stiamo completando la
mappa dei rifugi delle Alpi e dell'Appennino, e del {{nome}} non abbiamo
ancora una pagina.

Se le interessa esserci, bastano poche cose: due righe di descrizione, una
foto e i periodi di apertura. La pagina resta sua e la aggiorna quando
vuole: {{link_crea}}

Se preferisce, mi risponda con quelle informazioni e la preparo io.

Al momento non c'e' niente da pagare.

Buona chiusura di stagione,
{{firma}}
TrailShare — trailshare.app
```

## Il piede della mail, obbligatorio

Va in fondo a entrambe. Senza, il contatto commerciale a freddo non sta in
piedi: e' quello che rende legittimo l'invio, non un formalismo.

```
—
Le scrivo a questo indirizzo perche' e' pubblicato su OpenStreetMap fra i
contatti del rifugio. Dati © contributori OpenStreetMap.
Se non vuole altre mail da noi, risponda con "no" e la togliamo subito:
nessuna altra comunicazione, e l'indirizzo resta nella lista di esclusione.
{{ragione_sociale}} — {{indirizzo}} — privacy: trailshare.app/privacy
```

Chi risponde "no" va in una lista di esclusione **permanente**, e va
controllata prima di ogni invio successivo. Non e' facoltativo.

## Campi da unire

Dal CSV `rifugi_contatti_AAAA-MM-GG_incrociato.csv`:

| Campo | Colonna |
|---|---|
| `{{nome}}` | `nome` |
| `{{link_scheda}}` | costruito da `scheda_id` |
| `{{link_rivendica}}` | scheda + azione di rivendicazione |
| `{{link_crea}}` | modulo di creazione |
| `{{firma}}`, `{{ragione_sociale}}`, `{{indirizzo}}` | fissi |

## Cose da sistemare prima del primo invio

1. **La pagina di atterraggio.** Il gestore clicca `{{link_scheda}}` e deve
   capire in tre secondi che quella pagina parla di lui e che puo' correggerla.
   Se atterra su una scheda muta, la mail e' sprecata.
2. **Il percorso di rivendicazione** dev'essere percorribile da chi non ha
   l'app installata e non vuole installarla per rispondere a una mail.
3. **Alto Adige in tedesco.** 214 contatti stanno in Trentino-Alto Adige, e
   buona parte dei rifugi altoatesini hanno gestione di lingua tedesca. Una
   mail in italiano li' e' un piccolo insulto, non un dettaglio.
4. **Un indirizzo di risposta vero**, presidiato: la variante A invita
   esplicitamente a rispondere, e non rispondere alle risposte e' peggio che
   non aver scritto.
5. **Mandarne venti prima**, non cinquecento. Si legge cosa rispondono, si
   corregge il testo, e solo allora si apre il rubinetto.

## Cosa NON scrivere

- Numeri di utenti. Non ne abbiamo abbastanza perche' impressionino, e un
  gestore che verifica e scopre che erano gonfiati non torna piu'.
- "Gratis per sempre". Non e' vero: i piani a pagamento sono previsti.
- Nessuna scadenza inventata per creare fretta.
