import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../data/repositories/groups_repository.dart';
import '../../presentation/pages/groups/group_detail_page.dart';

/// Singleton che gestisce i deep link in ingresso.
///
/// Scheme custom supportato:
/// - `trailshare://g/{code}` — join al gruppo via codice invito
///
/// Per il momento gestiamo solo il flusso "join gruppo" (Card invito
/// brandizzata Business). Quando aggiungeremo Universal Links su
/// `https://trailshare.app/...` l'handler riconoscerà anche quei
/// pattern senza modifiche al sito (la parte web è già pronta come
/// pagina ponte).
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService _instance = DeepLinkService._();
  factory DeepLinkService() => _instance;

  final AppLinks _appLinks = AppLinks();
  final GroupsRepository _repo = GroupsRepository();
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
    final code = _extractGroupCode(uri);
    if (code != null && code.isNotEmpty) {
      await _handleGroupCode(code);
    }
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
