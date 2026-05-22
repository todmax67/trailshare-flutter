import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Risultato della Cloud Function `summarizeTrailConditions`.
class TrailConditionsSummary {
  /// Testo del riassunto AI. `null` se nessun report disponibile.
  final String? summary;

  /// Numero di report community usati per il summary.
  final int reportsCount;

  /// True se almeno uno dei report ha status critico (closed/rockfall/ice).
  final bool hasCriticalReports;

  /// Timestamp del report più recente incluso nel summary.
  final DateTime? newestReportAt;

  /// Quando è stato generato il summary (per mostrare freshness).
  final DateTime? generatedAt;

  /// True se il summary arriva dalla cache Firestore.
  final bool cached;

  const TrailConditionsSummary({
    required this.summary,
    required this.reportsCount,
    required this.hasCriticalReports,
    this.newestReportAt,
    this.generatedAt,
    required this.cached,
  });

  /// Convenience: true se c'è effettivamente un summary da mostrare.
  bool get hasContent => summary != null && summary!.trim().isNotEmpty;

  factory TrailConditionsSummary.fromMap(Map<String, dynamic> data) {
    return TrailConditionsSummary(
      summary: data['summary'] as String?,
      reportsCount: (data['reportsCount'] as num?)?.toInt() ?? 0,
      hasCriticalReports: data['hasCriticalReports'] == true,
      newestReportAt: _parseTs(data['newestReportAt']),
      generatedAt: _parseTs(data['generatedAt']),
      cached: data['cached'] == true,
    );
  }

  static DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    return null;
  }
}

/// Wrapper sulla Cloud Function `summarizeTrailConditions`.
///
/// Killer feature Pro 6.6: AI summary delle condizioni sentiero
/// community. Cache 24h server-side + invalidazione automatica su
/// nuovo report (vedi `invalidateTrailConditionsSummaryOnNewReport`).
///
/// Pattern singleton — la function è stateless, riusa stessa istanza
/// di FirebaseFunctions.
class TrailConditionsAiService {
  TrailConditionsAiService._();
  static final TrailConditionsAiService _instance =
      TrailConditionsAiService._();
  factory TrailConditionsAiService() => _instance;

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'europe-west3');

  /// Chiede il summary AI per [trailId]. Se [forceRefresh] = true,
  /// bypassa la cache 24h server-side (utile per pull-to-refresh).
  ///
  /// Lancia [TrailConditionsAiException] su errori.
  Future<TrailConditionsSummary> summarize({
    required String trailId,
    required String trailName,
    String locale = 'it',
    bool forceRefresh = false,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('summarizeTrailConditions')
          .call<Map<String, dynamic>>({
        'trailId': trailId,
        'trailName': trailName,
        'locale': locale,
        'forceRefresh': forceRefresh,
      });
      return TrailConditionsSummary.fromMap(result.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[TrailConditionsAi] FunctionsException: ${e.code} ${e.message}');
      throw TrailConditionsAiException(
        e.message ?? 'Errore generazione riassunto',
      );
    } catch (e) {
      debugPrint('[TrailConditionsAi] Error: $e');
      throw TrailConditionsAiException('Errore di rete');
    }
  }
}

class TrailConditionsAiException implements Exception {
  final String message;
  TrailConditionsAiException(this.message);
  @override
  String toString() => message;
}
