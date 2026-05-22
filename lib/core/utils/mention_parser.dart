/// Utility per gestire le menzioni `@username` nel testo dei commenti
/// (Epic 3.6).
///
/// Le menzioni nel testo seguono la convenzione `@username` con username
/// composto da 2-30 caratteri alfanumerici / underscore / punto / trattino.
/// Lo stesso regex viene usato sia per estrarre le menzioni quando un
/// commento viene salvato (per costruire la mappa `mentions: username→uid`
/// e mandare le notifiche FCM) sia per renderizzare i pezzi di testo
/// tappabili nella UI.
class MentionParser {
  /// Regex: cattura @ seguito da uno username valido. Username:
  /// - inizia con lettera o underscore
  /// - può contenere lettere, numeri, `_`, `.`, `-`
  /// - lunghezza 2..30
  /// - non greedy: si ferma al primo carattere non valido
  static final RegExp pattern = RegExp(r'@([A-Za-z_][A-Za-z0-9_.\-]{1,29})');

  /// Estrae l'insieme degli username menzionati (senza `@`), normalizzati
  /// in minuscolo. Es. "Ciao @Mario e @luca!" → {"mario", "luca"}.
  /// Usato lato repo per risolvere gli uid prima di salvare il commento.
  static Set<String> extractUsernames(String text) {
    return pattern
        .allMatches(text)
        .map((m) => m.group(1)!.toLowerCase())
        .toSet();
  }

  /// Spezza il testo in segmenti alternati testo/menzione, mantenendo
  /// l'ordine originale. Usato dal renderer UI per costruire i TextSpan
  /// alternati (testo normale vs span tappabile colorato).
  ///
  /// Ogni segmento ha un `username` non-null se è una menzione.
  static List<MentionSegment> split(String text) {
    final List<MentionSegment> out = [];
    int cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        out.add(MentionSegment(text: text.substring(cursor, match.start)));
      }
      out.add(MentionSegment(
        text: match.group(0)!, // include la @
        username: match.group(1)!.toLowerCase(),
      ));
      cursor = match.end;
    }
    if (cursor < text.length) {
      out.add(MentionSegment(text: text.substring(cursor)));
    }
    return out;
  }

  /// Trova l'eventuale "@partial" che l'utente sta digitando alla
  /// posizione corrente del cursore. Ritorna lo username parziale (senza
  /// `@`, lowercase) e l'intervallo da rimpiazzare quando si seleziona
  /// un suggerimento. Ritorna null se il cursore non è dentro un token
  /// di menzione in corso di digitazione.
  ///
  /// Es. testo = "Ciao @lu", cursore = 8 → ("lu", start: 5, end: 8)
  static MentionInProgress? findInProgress(String text, int cursor) {
    if (cursor <= 0 || cursor > text.length) return null;
    // Scorri all'indietro dal cursore finché trovi @ (o un separatore).
    int start = cursor - 1;
    while (start >= 0) {
      final ch = text[start];
      if (ch == '@') break;
      // Caratteri ammessi dentro lo username
      if (!RegExp(r'[A-Za-z0-9_.\-]').hasMatch(ch)) return null;
      start -= 1;
    }
    if (start < 0 || text[start] != '@') return null;
    // Il carattere immediatamente prima della @ deve essere inizio testo
    // o uno spazio (evita @ in mezzo a una parola, es. "email@host").
    if (start > 0 && !RegExp(r'\s').hasMatch(text[start - 1])) return null;
    final partial = text.substring(start + 1, cursor).toLowerCase();
    return MentionInProgress(
      partial: partial,
      start: start,
      end: cursor,
    );
  }
}

class MentionSegment {
  final String text;
  /// Se non null, questo segmento è una menzione `@username` (lowercase).
  final String? username;
  const MentionSegment({required this.text, this.username});
  bool get isMention => username != null;
}

class MentionInProgress {
  final String partial;
  final int start; // index inclusivo della @
  final int end; // index esclusivo del cursore
  const MentionInProgress({
    required this.partial,
    required this.start,
    required this.end,
  });
}
