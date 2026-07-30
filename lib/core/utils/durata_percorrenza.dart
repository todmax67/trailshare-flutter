/// Come si scrive un tempo di percorrenza, in un posto solo.
///
/// Nasce perché la stessa informazione veniva formattata in cinque punti
/// diversi e in due modi incompatibili: la card di Scopri diceva "~2 giorni"
/// (via `PublicTrail.tempoLeggibile`) mentre la scheda dello stesso sentiero
/// diceva "10h 36m", e i totali dei tour arrivavano a "64h 6m". Sopra una certa
/// soglia le ore smettono di dire qualcosa: nessuno pianifica un cammino
/// contando 64 ore.
library;

/// Oltre questa durata il tempo in ore non è più un'informazione utile:
/// l'itinerario non si fa in giornata e quello che conta sono i giorni.
const Duration kSogliaGiornata = Duration(hours: 8);

/// Ore e minuti di un tempo che sta in giornata, `null` se non ci sta.
///
/// Serve dove i giorni sono GIA' mostrati per altra via — nei tour il conteggio
/// tappe è già in testata — e ripetere lo sforzo in giorni creerebbe due numeri
/// simili ma diversi accanto ("10 giorni" di tappe contro "~11 giorni" di
/// cammino). Sopra soglia si tace invece di confondere.
String? durataInGiornata(Duration d) {
  if (d <= Duration.zero || d >= kSogliaGiornata) return null;
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

/// Tempo leggibile completo: ore quando sta in giornata, giorni quando no.
///
/// Da usare dove NON c'è già un conteggio di giorni a fianco — la scheda di un
/// sentiero del catalogo, per esempio. I giorni sono una CONVENZIONE
/// (ore/[orePerGiorno] arrotondate per eccesso), da presentare col "circa".
String? durataLeggibile(Duration d, {int orePerGiorno = 6}) {
  if (d <= Duration.zero) return null;
  if (d < kSogliaGiornata) return durataInGiornata(d);
  final giorni = (d.inMinutes / (orePerGiorno * 60)).ceil();
  return '~$giorni giorni';
}
