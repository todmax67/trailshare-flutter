import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Epic 7.H12 — Tracker eventi del funnel claim per Spazi Pro
/// `unclaimed`.
///
/// Eventi tracciati:
/// - `unclaimed_view` → visualizzazione scheda unclaimed
/// - `claim_started` → click su "Rivendica" (form aperto)
/// - `claim_completed` → form submittato con successo
///
/// `claim_approved` / `claim_rejected` sono tracciati lato server
/// dalle Cloud Function `approveClaimRequest` / `rejectClaimRequest`.
///
/// Tutte le chiamate sono best-effort: errori (rete, function down,
/// rate limit) NON propagano. Una telemetria mancata non deve mai
/// bloccare il flow utente.
///
/// Dedup view-per-sessione: ogni `unclaimed_view` viene mandato al
/// massimo una volta per (businessId, lifetime app session). Niente
/// inflazione contatori se l'utente naviga avanti-indietro.
class BusinessFunnelTracker {
  static final BusinessFunnelTracker _instance =
      BusinessFunnelTracker._internal();
  factory BusinessFunnelTracker() => _instance;
  BusinessFunnelTracker._internal();

  final Set<String> _viewedThisSession = <String>{};

  Future<void> trackUnclaimedView(String businessId) async {
    if (_viewedThisSession.contains(businessId)) return;
    _viewedThisSession.add(businessId);
    await _track(businessId, 'unclaimed_view');
  }

  Future<void> trackClaimStarted(String businessId) =>
      _track(businessId, 'claim_started');

  Future<void> trackClaimCompleted(String businessId) =>
      _track(businessId, 'claim_completed');

  Future<void> _track(String businessId, String event) async {
    try {
      await FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('trackFunnelEvent')
          .call({
        'businessId': businessId,
        'event': event,
      });
    } catch (e) {
      // Best effort: non bloccare nulla, log soft.
      debugPrint('[FunnelTracker] $event($businessId) failed: $e');
    }
  }
}
