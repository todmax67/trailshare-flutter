import 'package:flutter/widgets.dart';

/// Utility per costruire avatar da URL utente in modo sicuro.
///
/// Molti profili Firestore espongono `avatarUrl`/`photoURL` come stringa
/// vuota (es. `data['avatarUrl'] ?? data['photoURL']`) invece che `null`.
/// Passare `""` a [NetworkImage] solleva l'eccezione (catturata da Flutter)
/// "ArgumentError: No host specified in URI file:///", che sporca i log e
/// mostra un'icona rotta. Queste helper scartano gli URL non validi, così che
/// il chiamante mostri l'iniziale/placeholder al loro posto.

/// `true` se [url] è un URL remoto valido (http/https) usabile come avatar.
bool hasRemoteAvatar(String? url) {
  final trimmed = url?.trim();
  return trimmed != null && trimmed.startsWith('http');
}

/// Restituisce un [ImageProvider] solo se [url] è un URL http(s) valido,
/// altrimenti `null` (così il `CircleAvatar` mostra il `child` placeholder
/// invece di costruire `NetworkImage("")`).
ImageProvider? avatarImageProvider(String? url) =>
    hasRemoteAvatar(url) ? NetworkImage(url!.trim()) : null;
