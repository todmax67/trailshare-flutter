import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../data/repositories/business_repository.dart';
import '../../data/repositories/groups_repository.dart';
import '../../presentation/pages/business/business_profile_page.dart';
import '../../presentation/pages/challenges/challenges_page.dart';
import '../../presentation/pages/groups/group_detail_page.dart';

/// Singleton che gestisce i deep link in ingresso.
///
/// Scheme custom supportati:
/// - `trailshare://g/{code}` — join al gruppo via codice invito
/// - `trailshare://b/{businessId}` — apre profilo Spazio Pro (7.C9)
/// - `https://trailshare.app/g/{code}` — universal link gruppo
/// - `https://trailshare.app/b/{slug}` — universal link Spazio Pro (slug)
///
/// L'Universal Link/App Link richiede file ben noti su trailshare.app
/// (`.well-known/apple-app-site-association` + `assetlinks.json`) —
/// quando saranno pubblicati, il routing è già pronto qui.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService _instance = DeepLinkService._();
  factory DeepLinkService() => _instance;

  final AppLinks _appLinks = AppLinks();
  final GroupsRepository _repo = GroupsRepository();
  final BusinessRepository _businessRepo = BusinessRepository();
  StreamSubscription<Uri>? _sub;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        // Posticipa di un frame: navigatorKey può non essere ancora
        // pronto al cold start.
        WidgetsBinding.instance.addPostFrameCallback((_) => _handle(initial));
      }
    } catch (e) {
      debugPrint('[DeepLink] getInitialLink errore: $e');
    }
    _sub = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (e) => debugPrint('[DeepLink] stream errore: $e'),
    );
  }

  Future<void> _handle(Uri uri) async {
    debugPrint('[DeepLink] ricevuto: $uri');

    // trailshare://strava/connected | trailshare://strava/error?msg=...
    if (uri.scheme == 'trailshare' && uri.host == 'strava') {
      _handleStravaCallback(uri);
      return;
    }

    // 7.C9 — link Spazio Pro: trailshare://b/{id} oppure
    // https://trailshare.app/b/{slug}. L'id custom-scheme è il doc id,
    // lo slug universal-link è quello human-readable.
    final businessRef = _extractBusinessRef(uri);
    if (businessRef != null) {
      await _handleBusinessRef(businessRef);
      return;
    }

    final code = _extractGroupCode(uri);
    if (code != null && code.isNotEmpty) {
      await _handleGroupCode(code);
      return;
    }

    // Universal Link per Apple In-App Events e link da PR/social:
    // https://trailshare.app/sfide → apre ChallengesPage.
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == 'trailshare.app' &&
        uri.pathSegments.isNotEmpty &&
        (uri.pathSegments.first == 'sfide' ||
            uri.pathSegments.first == 'challenges')) {
      _handleChallenges();
      return;
    }
  }

  void _handleChallenges() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const ChallengesPage()),
    );
  }

  void _handleStravaCallback(Uri uri) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final connected = uri.pathSegments.contains('connected');
    final msg = connected
        ? 'Strava collegato ✓'
        : 'Errore Strava: ${uri.queryParameters['msg'] ?? 'sconosciuto'}';
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 7.C9 — Estrae il riferimento a uno Spazio Pro dall'URI.
  /// Ritorna `(isSlug, value)` dove isSlug=true se proviene da Universal
  /// Link (serve risolvere via slug), false se proviene dallo scheme
  /// custom (è già un doc id).
  ({bool isSlug, String value})? _extractBusinessRef(Uri uri) {
    if (uri.scheme == 'trailshare' && uri.host == 'b') {
      if (uri.pathSegments.isNotEmpty) {
        return (isSlug: false, value: uri.pathSegments.first);
      }
    }
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == 'trailshare.app' &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments.first == 'b') {
      return (isSlug: true, value: uri.pathSegments[1]);
    }
    return null;
  }

  Future<void> _handleBusinessRef(({bool isSlug, String value}) ref) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    String? businessId;
    try {
      if (ref.isSlug) {
        final business = await _businessRepo.getBusinessBySlug(ref.value);
        businessId = business?.id;
      } else {
        businessId = ref.value;
      }
    } catch (e) {
      debugPrint('[DeepLink] business lookup error: $e');
    }
    final freshCtx = navigatorKey.currentContext;
    if (freshCtx == null || !freshCtx.mounted) return;
    if (businessId == null) {
      ScaffoldMessenger.of(freshCtx).showSnackBar(
        const SnackBar(content: Text('Spazio Pro non trovato')),
      );
      return;
    }
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => BusinessProfilePage(businessId: businessId!),
      ),
    );
  }

  /// Riconosce sia il custom scheme che l'URL https (per quando
  /// aggiungeremo gli Universal Links).
  ///
  /// Pattern accettati:
  /// - `trailshare://g/CODE`        → host=g, segments=[CODE]
  /// - `https://trailshare.app/g/CODE` → segments=[g, CODE]
  String? _extractGroupCode(Uri uri) {
    if (uri.scheme == 'trailshare' && (uri.host == 'g' || uri.host == 'group')) {
      if (uri.pathSegments.isNotEmpty) return uri.pathSegments.first;
    }
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == 'trailshare.app' &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments.first == 'g') {
      return uri.pathSegments[1];
    }
    return null;
  }

  Future<void> _handleGroupCode(String rawCode) async {
    final code = rawCode.toUpperCase().trim();
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      debugPrint('[DeepLink] navigator non pronto, link perso: $code');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('Accedi a TrailShare per usare il codice invito'),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text('Codice invito ricevuto: $code')),
    );

    final result = await _repo.joinByInviteCode(code);
    final freshCtx = navigatorKey.currentContext;
    if (freshCtx == null || !freshCtx.mounted) return;

    if (result['success'] == true) {
      final groupId = result['groupId'] as String?;
      final groupName = result['groupName'] as String? ?? 'Gruppo';
      if (groupId != null) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) =>
                GroupDetailPage(groupId: groupId, groupName: groupName),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(freshCtx).showSnackBar(
        SnackBar(
          content: Text(result['error']?.toString() ?? 'Errore'),
        ),
      );
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _initialized = false;
  }
}
