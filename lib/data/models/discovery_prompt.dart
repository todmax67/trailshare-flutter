import 'package:flutter/material.dart';

/// Funzione asincrona che valuta se un [DiscoveryPrompt] deve essere mostrato.
/// Riceve lo snapshot dell'attività utente; ritorna `true` per "mostra".
typedef PromptCondition = bool Function(UserActivitySnapshot snapshot);

/// Snapshot leggero dello stato utente, calcolato una volta e passato a tutte
/// le condizioni dei prompt per evitare N round-trip verso repository.
class UserActivitySnapshot {
  final int trackCount;
  final bool hasLifelineContacts;
  final bool hasPublishedTrack;
  final int tourCount;
  final bool hasExportedFit;
  final bool hasUsedPlanner;

  const UserActivitySnapshot({
    required this.trackCount,
    required this.hasLifelineContacts,
    required this.hasPublishedTrack,
    required this.tourCount,
    required this.hasExportedFit,
    required this.hasUsedPlanner,
  });
}

/// Card promozionale / di scoperta mostrata in cima alla Community tab.
///
/// Due fonti possibili:
/// - **Local**: condizioni hard-coded nel registry (valutate ogni volta).
/// - **Remote**: documenti in `discovery_prompts/{id}` di Firestore
///   (modificabili senza aggiornare l'app).
class DiscoveryPrompt {
  /// Chiave univoca usata anche per la dismiss persistente.
  final String id;

  final String title;
  final String description;
  final IconData icon;
  final Color accentColor;
  final String ctaLabel;

  /// Callback al tap sul CTA. Riceve il BuildContext della card.
  final void Function(BuildContext context) onCta;

  /// Priorità 0-100: viene ordinata DESC, più alta = più in alto.
  final int priority;

  /// Condizione di visibilità (solo per prompt locali). Se null, sempre mostrato.
  final PromptCondition? condition;

  const DiscoveryPrompt({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.ctaLabel,
    required this.onCta,
    this.priority = 50,
    this.condition,
  });
}
