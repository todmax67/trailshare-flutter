import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Presidio sul tracciamento delle schermate.
///
/// `FirebaseAnalyticsObserver` nomina le schermate leggendo
/// `RouteSettings.name`: **una pagina aperta senza nome non viene registrata
/// affatto**. Non da' errore, non da' warning, non lascia traccia — semplicemente
/// quella schermata non esiste in GA4, e chi legge i report conclude che nessuno
/// ci va.
///
/// E' esattamente la famiglia di guasti contro cui esiste la regola 3 di
/// CLAUDE.md: un dato che manca non e' uno zero. Percio' il controllo sta in un
/// test invece che in una convenzione: aggiungere una pagina e scordare il nome
/// deve far fallire la suite, non sparire in silenzio.
void main() {
  /// Classi che consideriamo "pagine": sono quelle che vale la pena vedere nel
  /// report. Un `AlertDialog` o un `SafeArea` dentro un MaterialPageRoute non
  /// e' una schermata da misurare.
  final pagina = RegExp(r'(Page|Sheet|Viewer|Screen|Editor)$');

  final apertura = RegExp(
    r'(MaterialPageRoute(?:<[^>]*>)?\()'
    r'([\s\S]{0,200}?)'
    r'builder:\s*\(\s*_?[A-Za-z]*\s*\)\s*=>\s*(?:const\s+)?([A-Z]\w*)',
  );

  test('ogni pagina aperta porta un nome, o non finisce in Analytics', () {
    final senzaNome = <String>[];

    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();

      for (final m in apertura.allMatches(src)) {
        final classe = m.group(3)!;
        if (!pagina.hasMatch(classe)) continue;

        // Gli esempi nei commenti di documentazione non sono codice.
        final inizioRiga = src.lastIndexOf('\n', m.start) + 1;
        if (src.substring(inizioRiga, m.start).trimLeft().startsWith('//')) {
          continue;
        }

        if (!m.group(2)!.contains('settings:')) {
          final riga = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          senzaNome.add('${f.path}:$riga  →  $classe');
        }
      }
    }

    expect(
      senzaNome,
      isEmpty,
      reason:
          'Queste pagine si aprono senza RouteSettings(name: ...), quindi non '
          'compariranno mai nel report Schermate di GA4 — silenziosamente.\n'
          'Aggiungi al MaterialPageRoute:\n'
          "  settings: const RouteSettings(name: 'NomeDellaPagina'),\n\n"
          '${senzaNome.join('\n')}',
    );
  });
}
