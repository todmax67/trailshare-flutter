/// Chiede una recensione allo store, ma solo quando ha senso chiederla.
///
/// Al 2026-07-31 TrailShare ha **1 recensione**. Komoot ne ha 30.748, Wikiloc
/// 21.202, PeakVisor 15.497. È il divario più largo che abbiamo con i
/// competitor, ed è anche l'unico che si chiude senza budget: le recensioni
/// alzano il posizionamento negli store, il posizionamento porta download, i
/// download portano recensioni.
///
/// Il prompt nativo esisteva già in Impostazioni, dove però bisogna andarci
/// apposta — e nessuno ci va. Quello che mancava è chiederlo da soli, nel
/// momento giusto.
///
/// ## Quando
///
/// Subito dopo il dialog di fine registrazione: l'utente ha appena visto la
/// sua traccia salvata e i punti guadagnati. È il picco della giornata, e
/// l'unico istante in cui una domanda del genere non è un'interruzione.
///
/// ## Quando NO
///
/// - Prima di [_minSaves] tracce: chi ha salvato una volta sola non ha
///   ancora un'opinione.
/// - Nei primi [_minDaysSinceInstall] giorni: chi prova l'app per un
///   pomeriggio e salva tre giri di test non è un utente, è una prova.
/// - Se il salvataggio non è stato confermato dal server: chiedere una
///   recensione a chi potrebbe aver appena perso un trek è il modo migliore
///   di farsene dare una da una stella.
/// - Più di [_maxAsks] volte in tutta la vita dell'app, e mai due volte a
///   meno di [_daysBetweenAsks] giorni.
///
/// iOS applica un suo limite (3 richieste l'anno) e ignora le altre in
/// silenzio: queste regole servono a non sprecarle, non a sostituirlo.
library;

import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReviewPromptService {
  ReviewPromptService._();
  static final ReviewPromptService instance = ReviewPromptService._();

  static const int _minSaves = 3;
  static const int _minDaysSinceInstall = 7;
  static const int _daysBetweenAsks = 120;
  static const int _maxAsks = 3;

  static const String _kSaves = 'review_saves_count';
  static const String _kAsks = 'review_asks_count';
  static const String _kLastAsk = 'review_last_ask';

  /// Registra un salvataggio andato a buon fine e, se le condizioni ci sono,
  /// mostra il prompt.
  ///
  /// [confirmedByServer] arriva da `SaveTrackResult`: quando è false la
  /// traccia è nella coda locale e sincronizzerà da sola, ma l'utente non ha
  /// ancora la certezza di averla al sicuro. Il salvataggio si conta lo
  /// stesso — è avvenuto — ma non si chiede niente.
  ///
  /// Fire-and-forget: non deve mai rallentare né interrompere il flusso di
  /// fine registrazione.
  Future<void> onTrackSaved({required bool confirmedByServer}) async {
    if (kDebugMode) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saves = (prefs.getInt(_kSaves) ?? 0) + 1;
      await prefs.setInt(_kSaves, saves);

      if (!confirmedByServer) return;
      if (!await _shouldAsk(prefs, saves)) return;

      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;

      // Segna PRIMA di chiedere: se il sistema decide di non mostrare nulla
      // — succede spesso, ed è invisibile all'app — aver consumato il turno è
      // il comportamento giusto. Meglio chiedere una volta in meno che
      // insistere ogni settimana con chi il dialogo non lo vede mai.
      await prefs.setInt(_kAsks, (prefs.getInt(_kAsks) ?? 0) + 1);
      await prefs.setString(_kLastAsk, DateTime.now().toUtc().toIso8601String());

      await review.requestReview();
    } catch (e) {
      debugPrint('[ReviewPrompt] $e');
    }
  }

  Future<bool> _shouldAsk(SharedPreferences prefs, int saves) async {
    if (saves < _minSaves) return false;
    if ((prefs.getInt(_kAsks) ?? 0) >= _maxAsks) return false;

    // Data di prima apertura: la scrive GrowthAnalyticsService. Se manca —
    // utente che c'era prima della 2.9.4 — la condizione si considera
    // soddisfatta: è con noi da più tempo di chiunque altro.
    final firstOpen = prefs.getString('growth_first_open_at');
    if (firstOpen != null) {
      final since = DateTime.now().toUtc().difference(DateTime.parse(firstOpen));
      if (since.inDays < _minDaysSinceInstall) return false;
    }

    final lastAsk = prefs.getString(_kLastAsk);
    if (lastAsk != null) {
      final since = DateTime.now().toUtc().difference(DateTime.parse(lastAsk));
      if (since.inDays < _daysBetweenAsks) return false;
    }

    return true;
  }

  /// Solo per i test manuali: azzera i contatori e permette di rivedere il
  /// prompt senza reinstallare.
  @visibleForTesting
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSaves);
    await prefs.remove(_kAsks);
    await prefs.remove(_kLastAsk);
  }
}
