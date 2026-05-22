import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/monthly_report.dart';
import '../../data/models/track.dart';
import '../../data/repositories/monthly_reports_repository.dart';
import '../../data/repositories/tracks_repository.dart';

/// Orchestrator dei [MonthlyReport] automatici.
///
/// Responsabilità:
/// 1. **Generator**: dato un mese, legge le tracce dell'utente in quel
///    range e produce aggregati (distanza, D+, tempo, count, breakdown per
///    tipo, record mensili).
/// 2. **Comparison**: appoggia la generazione del mese N al report del
///    mese N-1 (fetchato o generato on-demand) per calcolare le delta %.
/// 3. **Badge / XP mensili**: legge da `users/{uid}/badges` e
///    `users/{uid}/xp_history` i record con timestamp nel mese.
/// 4. **"Nuovo report pronto"**: il primo giorno del mese N+1 l'utente
///    dovrebbe vedere la card di Discovery del mese appena chiuso. Il
///    servizio espone [hasNewReportForPreviousMonth] (bool cached) e
///    [markPreviousReportViewed] per persistere il flag.
class MonthlyReportService {
  MonthlyReportService._();
  static final MonthlyReportService _instance = MonthlyReportService._();
  factory MonthlyReportService() => _instance;

  final _repo = MonthlyReportsRepository();
  final _tracksRepo = TracksRepository();
  final _firestore = FirebaseFirestore.instance;

  /// Cache in-memory: mese id -> report.
  final Map<String, MonthlyReport> _cache = {};

  /// Flag cached sul fatto che ci sia un report del mese scorso "nuovo" da
  /// mostrare nel Discovery Carousel. Ricomputato da
  /// [refreshHasNewReportFlag] (chiamato dal carousel prima del collect).
  bool _cachedHasNewReport = false;
  bool get hasNewReportCached => _cachedHasNewReport;

  static const _prefsKeyLastViewedPrevious =
      'monthly_report_last_viewed_previous_id';

  /// Genera (o rigenera) il report del mese corrente e lo salva.
  ///
  /// Thin wrapper su [generateForMonth] che usa [MonthBoundaries.forNow].
  Future<MonthlyReport?> ensureCurrent() async {
    final id = MonthBoundaries.forNow().yearMonthId;
    return generateForMonth(id);
  }

  /// Genera (o rigenera) il report del mese PRECEDENTE.
  Future<MonthlyReport?> ensurePrevious() async {
    final id = MonthBoundaries.forNow().previous().yearMonthId;
    return generateForMonth(id);
  }

  /// Carica il report dalla cache / da Firestore senza rigenerarlo.
  /// Usato dalla pagina "Il mio mese" quando l'utente naviga nei mesi passati
  /// e il report è storico (non più mutabile).
  Future<MonthlyReport?> getForMonth(String yearMonthId) async {
    if (_cache.containsKey(yearMonthId)) return _cache[yearMonthId];
    final doc = await _repo.getById(yearMonthId);
    if (doc != null) {
      _cache[yearMonthId] = doc;
    }
    return doc;
  }

  /// Genera il report per un mese specifico dato il suo `yyyy-MM`.
  ///
  /// Strategia:
  /// - legge tutte le tracce utente (paginate lato repository),
  /// - filtra per `recordedAt ?? createdAt` nel range [monthStart, monthEnd],
  /// - aggrega stats, record, breakdown, giorni attivi,
  /// - fetcha badge sbloccati e XP guadagnati nel range,
  /// - carica il report del mese precedente per le delta %,
  /// - upsert su Firestore.
  Future<MonthlyReport?> generateForMonth(String yearMonthId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final parts = yearMonthId.split('-');
    if (parts.length != 2) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) return null;

    final boundaries = MonthBoundaries.forYearMonth(year, month);

    // Report mensile: serve solo stats aggregate (distanza, dislivello,
    // count, durata). getMyTracks() scarica anche i GPS points che
    // saturano l'heap. Lightweight ritorna fino a 1000 tracce senza
    // points → niente OOM e copre tutto lo storico, non solo gli
    // ultimi 20.
    final allTracks = await _tracksRepo.getMyTracksLightweight();
    final monthTracks = allTracks.where((t) {
      final d = t.recordedAt ?? t.createdAt;
      return !d.isBefore(boundaries.start) && !d.isAfter(boundaries.end);
    }).toList();

    // ─── Totali ──────────────────────────────────────────────────────
    double distance = 0;
    double elevationGain = 0;
    double elevationLoss = 0;
    int duration = 0;
    int movingTime = 0;
    final activityTypes = <String, int>{};
    final activeDayKeys = <String>{};

    Track? bestDistanceTrack;
    Track? bestElevationTrack;

    for (final t in monthTracks) {
      distance += t.stats.distance;
      elevationGain += t.stats.elevationGain;
      elevationLoss += t.stats.elevationLoss;
      duration += t.stats.duration.inSeconds;
      movingTime += t.stats.movingTime.inSeconds > 0
          ? t.stats.movingTime.inSeconds
          : t.stats.duration.inSeconds;

      final activityKey = t.activityType.name;
      activityTypes[activityKey] = (activityTypes[activityKey] ?? 0) + 1;

      final d = t.recordedAt ?? t.createdAt;
      activeDayKeys
          .add('${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');

      if (bestDistanceTrack == null ||
          t.stats.distance > bestDistanceTrack.stats.distance) {
        bestDistanceTrack = t;
      }
      if (bestElevationTrack == null ||
          t.stats.elevationGain > bestElevationTrack.stats.elevationGain) {
        bestElevationTrack = t;
      }
    }

    // ─── Badge sbloccati nel mese ───────────────────────────────────
    final badgesUnlocked = <String>[];
    try {
      final snap = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('badges')
          .where('unlockedAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(boundaries.start))
          .where('unlockedAt',
              isLessThanOrEqualTo: Timestamp.fromDate(boundaries.end))
          .get();
      for (final d in snap.docs) {
        badgesUnlocked.add(d.id);
      }
    } catch (e) {
      debugPrint('[MonthlyReport] badge query error: $e');
    }

    // ─── XP guadagnati nel mese ─────────────────────────────────────
    int xpEarned = 0;
    try {
      final snap = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('xp_history')
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(boundaries.start))
          .where('timestamp',
              isLessThanOrEqualTo: Timestamp.fromDate(boundaries.end))
          .get();
      for (final d in snap.docs) {
        xpEarned += (d.data()['amount'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      debugPrint('[MonthlyReport] xp query error: $e');
    }

    // ─── Confronto col mese precedente ─────────────────────────────
    final previousId = boundaries.previous().yearMonthId;
    final previous = await _repo.getById(previousId);

    double? pct(double curr, double prev) {
      if (prev <= 0) return null;
      return ((curr - prev) / prev) * 100;
    }

    final distanceDelta =
        previous == null ? null : pct(distance, previous.distance);
    final elevationDelta = previous == null
        ? null
        : pct(elevationGain, previous.elevationGain);
    final durationDelta = previous == null
        ? null
        : pct(duration.toDouble(), previous.duration.toDouble());
    final tracksDelta = previous == null
        ? null
        : pct(monthTracks.length.toDouble(), previous.trackCount.toDouble());

    final report = MonthlyReport(
      id: yearMonthId,
      userId: user.uid,
      monthStart: boundaries.start,
      monthEnd: boundaries.end,
      distance: distance,
      elevationGain: elevationGain,
      elevationLoss: elevationLoss,
      duration: duration,
      movingTime: movingTime,
      trackCount: monthTracks.length,
      activeDays: activeDayKeys.length,
      activityTypes: activityTypes,
      bestDistance: bestDistanceTrack?.stats.distance ?? 0,
      bestDistanceName: bestDistanceTrack?.name,
      bestElevation: bestElevationTrack?.stats.elevationGain ?? 0,
      bestElevationName: bestElevationTrack?.name,
      distanceDeltaPercent: distanceDelta,
      elevationDeltaPercent: elevationDelta,
      durationDeltaPercent: durationDelta,
      tracksDeltaPercent: tracksDelta,
      badgesUnlocked: badgesUnlocked,
      xpEarned: xpEarned,
      generatedAt: DateTime.now(),
    );

    // Non salviamo report vuoti di mesi vecchi: se l'utente non esisteva
    // ancora e quel mese non ha nulla, non ha senso creare documenti vuoti
    // (solo rumore). Per il mese corrente invece salviamo sempre, così la
    // pagina può mostrare "inizia a registrare".
    if (report.isEmpty && !report.isCurrentMonth) {
      debugPrint('[MonthlyReport] $yearMonthId vuoto e non corrente: skip save');
      _cache[yearMonthId] = report;
      return report;
    }

    await _repo.save(report);
    _cache[yearMonthId] = report;
    return report;
  }

  // ─── Flag "Nuovo report pronto" (Discovery) ─────────────────────

  /// Vero se siamo entro i primi 7 giorni del mese AND il report del mese
  /// precedente esiste AND l'utente non lo ha ancora visualizzato.
  ///
  /// Pre-genera il report del mese scorso se non esiste — così la Discovery
  /// card appare al primo accesso del mese nuovo anche se l'utente non ha
  /// mai aperto la pagina "Il mio mese".
  Future<bool> hasNewReportForPreviousMonth() async {
    final now = DateTime.now();
    if (now.day > 7) {
      _cachedHasNewReport = false;
      return false;
    }

    final previousId = MonthBoundaries.forNow().previous().yearMonthId;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastViewed = prefs.getString(_prefsKeyLastViewedPrevious);
      if (lastViewed == previousId) {
        _cachedHasNewReport = false;
        return false;
      }

      // Se non esiste ancora (primo accesso del mese nuovo) lo generiamo
      // al volo così la Discovery card può apparire.
      final prev = await _repo.getById(previousId) ??
          await generateForMonth(previousId);
      final result = prev != null && !prev.isEmpty;
      _cachedHasNewReport = result;
      return result;
    } catch (e) {
      debugPrint('[MonthlyReport] hasNewReport error: $e');
      _cachedHasNewReport = false;
      return false;
    }
  }

  /// Alias public usato dal [DiscoveryCarousel] per pre-caricare il flag
  /// prima di valutare le condizioni dei prompt (che sono sync).
  Future<void> refreshHasNewReportFlag() async {
    await hasNewReportForPreviousMonth();
  }

  /// Marca il report del mese precedente come "già visto" così il prompt
  /// Discovery scompare.
  Future<void> markPreviousReportViewed() async {
    final previousId = MonthBoundaries.forNow().previous().yearMonthId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyLastViewedPrevious, previousId);
      _cachedHasNewReport = false;
    } catch (e) {
      debugPrint('[MonthlyReport] markViewed error: $e');
    }
  }
}
