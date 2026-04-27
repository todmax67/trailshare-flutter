/// Utility per la ricerca testuale accent-insensitive nelle liste di
/// PublicTrail / Track / community items (4.4).
///
/// La normalizzazione:
/// - converte tutto in lowercase
/// - rimuove accenti / diacritici comuni in italiano e inglese
///   (à → a, è/é → e, ì/í → i, ò/ó → o, ù/ú → u, ñ → n, ç → c)
///
/// Esempio:
/// ```dart
/// TextSearch.normalize('Sentiero Italià') == 'sentiero italia';
/// TextSearch.matches('Cammino di Santiago', 'santiágo') == true;
/// ```
class TextSearch {
  TextSearch._();

  static const Map<String, String> _accentMap = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'æ': 'ae',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ý': 'y', 'ÿ': 'y',
    'ñ': 'n',
    'ç': 'c',
    'ß': 'ss',
  };

  /// Normalizza una stringa per la ricerca: lowercase + accenti rimossi.
  static String normalize(String input) {
    final lower = input.toLowerCase();
    final buf = StringBuffer();
    for (final ch in lower.split('')) {
      buf.write(_accentMap[ch] ?? ch);
    }
    return buf.toString();
  }

  /// True se [haystack] contiene [needle] (entrambi normalizzati).
  /// Ritorna true anche per [needle] vuoto (nessun filtro).
  static bool matches(String haystack, String needle) {
    if (needle.isEmpty) return true;
    return normalize(haystack).contains(normalize(needle));
  }

  /// Versione che accetta più campi opzionali. Se uno qualsiasi matcha,
  /// ritorna true. Utile per query "full-text" multi-campo.
  ///
  /// ```dart
  /// final found = TextSearch.matchesAny(query, [
  ///   trail.name,
  ///   trail.ref,
  ///   trail.region,
  /// ]);
  /// ```
  static bool matchesAny(String needle, Iterable<String?> fields) {
    if (needle.isEmpty) return true;
    final n = normalize(needle);
    for (final f in fields) {
      if (f == null || f.isEmpty) continue;
      if (normalize(f).contains(n)) return true;
    }
    return false;
  }
}
