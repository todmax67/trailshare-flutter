import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Pagina FAQ
class FaqPage extends StatelessWidget {
  const FaqPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FAQ'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.help_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Come possiamo aiutarti?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Trova risposte alle domande più frequenti',
                  style: TextStyle(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Categorie FAQ
          _buildCategory(
            context,
            title: '📱 Generale',
            faqs: _generalFaqs,
          ),
          _buildCategory(
            context,
            title: '🗺️ Tracking GPS',
            faqs: _trackingFaqs,
          ),
          _buildCategory(
            context,
            title: '👥 Social',
            faqs: _socialFaqs,
          ),
          _buildCategory(
            context,
            title: '🏆 Gamification',
            faqs: _gamificationFaqs,
          ),
          _buildCategory(
            context,
            title: '⚙️ Tecnico',
            faqs: _technicalFaqs,
          ),

          const SizedBox(height: 24),

          // Contatto supporto
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  'Non hai trovato la risposta?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Contattaci e ti risponderemo al più presto',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    // TODO: Aprire email
                  },
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Contatta il supporto'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildCategory(
    BuildContext context, {
    required String title,
    required List<FaqItem> faqs,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...faqs.map((faq) => _FaqTile(faq: faq)),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _FaqTile extends StatelessWidget {
  final FaqItem faq;

  const _FaqTile({required this.faq});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(
          faq.question,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
        ),
        children: [
          Text(
            faq.answer,
            style: TextStyle(
              color: Colors.grey[700],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class FaqItem {
  final String question;
  final String answer;

  const FaqItem({
    required this.question,
    required this.answer,
  });
}

// ============================================
// FAQ DATA
// ============================================

const _generalFaqs = [
  FaqItem(
    question: 'Cos\'è TrailShare?',
    answer: 'TrailShare è un\'app per registrare e condividere le tue escursioni. Puoi tracciare i tuoi percorsi con GPS, scoprire nuovi sentieri, seguire altri escursionisti e partecipare a sfide settimanali.',
  ),
  FaqItem(
    question: 'L\'app è gratuita?',
    answer: 'Sì, TrailShare è completamente gratuita. Tutte le funzionalità sono disponibili senza costi nascosti o abbonamenti.',
  ),
  FaqItem(
    question: 'Devo creare un account?',
    answer: 'Sì, è necessario un account per salvare le tue tracce e accedere alle funzionalità social. Puoi registrarti con email, Google o Apple.',
  ),
  FaqItem(
    question: 'I miei dati sono al sicuro?',
    answer: 'Assolutamente. I tuoi dati sono protetti e criptati. Puoi consultare la nostra Privacy Policy per tutti i dettagli su come gestiamo le informazioni.',
  ),
];

const _trackingFaqs = [
  FaqItem(
    question: 'Come registro una traccia?',
    answer: 'Vai nella sezione "Registra", premi il pulsante verde "Inizia" e cammina! L\'app registrerà automaticamente il tuo percorso. Puoi mettere in pausa e riprendere in qualsiasi momento.',
  ),
  FaqItem(
    question: 'Il GPS funziona in background?',
    answer: 'Sì, puoi bloccare lo schermo o usare altre app mentre registri. Il tracking continua in background con notifica attiva.',
  ),
  FaqItem(
    question: 'Quanto consuma la batteria?',
    answer: 'Il consumo dipende dalla durata dell\'escursione. In media, aspettati un consumo del 5-10% all\'ora. Consigliamo di partire con batteria carica o portare un powerbank.',
  ),
  FaqItem(
    question: 'Funziona senza connessione internet?',
    answer: 'Sì! Il tracking GPS funziona completamente offline. Puoi anche scaricare le mappe in anticipo da Impostazioni > Mappe Offline. La sincronizzazione avverrà quando tornerai online.',
  ),
  FaqItem(
    question: 'Come miglioro la precisione GPS?',
    answer: 'Assicurati di avere una buona visuale del cielo. Evita zone con copertura fitta o canyon stretti. Attendi qualche secondo prima di iniziare per permettere al GPS di calibrarsi.',
  ),
  FaqItem(
    question: 'Posso importare tracce GPX?',
    answer: 'Sì, puoi importare file GPX dalla sezione "Le mie tracce". Tocca il pulsante + e seleziona "Importa GPX".',
  ),
  FaqItem(
    question: 'Posso esportare le mie tracce?',
    answer: 'Certamente! Apri una traccia e tocca l\'icona condividi per esportarla in formato GPX, compatibile con la maggior parte delle app e dispositivi GPS.',
  ),
];

const _socialFaqs = [
  FaqItem(
    question: 'Come seguo altri utenti?',
    answer: 'Cerca un utente o visita il suo profilo da una traccia pubblica, poi tocca "Segui". Vedrai le sue nuove tracce nel tuo feed.',
  ),
  FaqItem(
    question: 'Cos\'è un "Cheers"?',
    answer: 'È il nostro modo di dire "bella traccia!". Puoi lasciare un cheers sulle tracce che ti piacciono. Riceverai anche XP per i cheers ricevuti.',
  ),
  FaqItem(
    question: 'Come pubblico una traccia?',
    answer: 'Dopo aver salvato una traccia, aprila e tocca "Pubblica". La traccia sarà visibile nella sezione Esplora e gli altri potranno vederla.',
  ),
  FaqItem(
    question: 'Posso rendere privata una traccia?',
    answer: 'Le tracce sono private di default. Solo quelle che pubblichi esplicitamente saranno visibili agli altri.',
  ),
  FaqItem(
    question: 'Cos\'è LiveTrack?',
    answer: 'LiveTrack ti permette di condividere la tua posizione in tempo reale durante un\'escursione. Genera un link che puoi inviare a familiari o amici per farti seguire sulla mappa.',
  ),
];

const _gamificationFaqs = [
  FaqItem(
    question: 'Come funzionano gli XP?',
    answer: 'Guadagni XP (punti esperienza) completando tracce, ricevendo cheers, ottenendo follower e completando sfide. Più XP accumuli, più sali di livello!',
  ),
  FaqItem(
    question: 'Quanti livelli ci sono?',
    answer: 'Ci sono 20 livelli, da "Principiante" a "Immortale". Ogni livello richiede più XP del precedente.',
  ),
  FaqItem(
    question: 'Come sblocco i badge?',
    answer: 'I badge si sbloccano automaticamente raggiungendo determinati traguardi: km percorsi, dislivello accumulato, giorni consecutivi di attività e obiettivi social.',
  ),
  FaqItem(
    question: 'Come funziona la classifica?',
    answer: 'La classifica settimanale si basa sui km percorsi e il dislivello accumulato nella settimana. Si resetta ogni lunedì.',
  ),
  FaqItem(
    question: 'Posso vedere i badge degli altri?',
    answer: 'Sì, visitando il profilo di un utente puoi vedere i suoi badge sbloccati e il suo livello.',
  ),
];

const _technicalFaqs = [
  FaqItem(
    question: 'Come collego una fascia cardio?',
    answer: 'Durante la registrazione, tocca l\'icona del cuore in alto. L\'app cercherà automaticamente fasce cardio Bluetooth nelle vicinanze. Seleziona la tua per connetterti.',
  ),
  FaqItem(
    question: 'Quali fasce cardio sono compatibili?',
    answer: 'TrailShare supporta qualsiasi fascia cardio Bluetooth Low Energy (BLE) standard, come Polar H10, Garmin HRM-Dual, Wahoo TICKR e molte altre.',
  ),
  FaqItem(
    question: 'Come scarico le mappe offline?',
    answer: 'Vai in Impostazioni > Mappe Offline > Scarica Area. Seleziona l\'area sulla mappa, scegli il livello di dettaglio e avvia il download.',
  ),
  FaqItem(
    question: 'Quanto spazio occupano le mappe offline?',
    answer: 'Dipende dall\'area e dal livello di zoom. Un\'area di 10km con zoom medio occupa circa 30-50 MB. Puoi vedere lo spazio utilizzato nelle impostazioni.',
  ),
  FaqItem(
    question: 'Come cambio tema chiaro/scuro?',
    answer: 'Vai in Impostazioni > Aspetto > Tema. Puoi scegliere tra Chiaro, Scuro o Automatico (segue le impostazioni del sistema).',
  ),
  FaqItem(
    question: 'Come elimino il mio account?',
    answer: 'Vai in Impostazioni > Zona Pericolosa > Elimina Account. Dovrai confermare con la password. Questa azione è irreversibile e cancellerà tutti i tuoi dati.',
  ),
];
