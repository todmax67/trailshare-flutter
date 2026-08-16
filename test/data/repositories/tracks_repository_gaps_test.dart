import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:trailshare_flutter/data/models/track.dart';
import 'package:trailshare_flutter/data/repositories/tracks_repository.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

/// I buchi di registrazione attraverso il repository: il salvataggio li
/// scrive, la lettura li restituisce, la dichiarazione del proprietario li
/// aggiunge senza toccare nient'altro, e la rimozione toglie SOLO le
/// dichiarazioni — mai le misure del watchdog.
///
/// Il primo test esiste per un difetto reale: _trackToFirestore costruisce la
/// mappa a mano, non via toMap(), e i gaps del watchdog venivano persi in
/// silenzio al salvataggio. I test sul modello non potevano vederlo, perche'
/// provavano toMap() — che era corretta. Si inchioda il percorso VERO.
void main() {
  const uid = 'testuid';

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late TracksRepository repo;

  CollectionReference<Map<String, dynamic>> tracksCol() =>
      firestore.collection('users').doc(uid).collection('tracks');

  final base = DateTime.utc(2026, 8, 16, 10);

  /// Punti che curvano (zigzag oltre la tolleranza di Douglas-Peucker), come
  /// nel test della geometria: su una retta la semplificazione ne terrebbe due.
  List<TrackPoint> makePoints(int n) => List.generate(
        n,
        (i) => TrackPoint(
          latitude: 45.0 + i * 0.0005,
          longitude: 9.0 + i * 0.0003 + (i.isEven ? 0.0006 : -0.0006),
          elevation: 100.0 + i,
          timestamp: base.add(Duration(seconds: i * 10)),
          speed: 1.5,
          accuracy: 5,
        ),
      );

  Track makeTrack({int n = 30, List<TrackGap> gaps = const []}) => Track(
        name: 'Giro con buchi',
        points: makePoints(n),
        createdAt: base,
        recordedAt: base,
        elevationCorrectedFromDem: true,
        gaps: gaps,
      );

  TrackGap watchdogGap() => TrackGap(
        startedAt: base.add(const Duration(seconds: 100)),
        endedAt: base.add(const Duration(seconds: 110)),
        cause: TrackGap.causeAppFrozen,
      );

  TrackGap declaredGap({int startSec = 200, int endSec = 210}) => TrackGap(
        startedAt: base.add(Duration(seconds: startSec)),
        endedAt: base.add(Duration(seconds: endSec)),
        cause: TrackGap.causeOwnerDeclared,
      );

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth();
    final user = MockUser();
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.uid).thenReturn(uid);
    repo = TracksRepository(firestore: firestore, auth: auth);
  });

  group('il salvataggio non perde i buchi del watchdog', () {
    test('saveTrack scrive gaps sul documento', () async {
      final id = await repo.saveTrack(makeTrack(gaps: [watchdogGap()]));
      final doc = await tracksCol().doc(id).get();
      final raw = doc.data()!['gaps'];
      expect(raw, isA<List>(), reason: 'il campo deve esistere sul doc');
      expect((raw as List), hasLength(1));
    });

    test('getTrackById li restituisce identici', () async {
      final g = watchdogGap();
      final id = await repo.saveTrack(makeTrack(gaps: [g]));
      final loaded = await repo.getTrackById(id);
      expect(loaded!.gaps, hasLength(1));
      expect(loaded.gaps.single.cause, TrackGap.causeAppFrozen);
      expect(loaded.gaps.single.startedAt, g.startedAt);
      expect(loaded.gaps.single.endedAt, g.endedAt);
    });

    test('una traccia senza buchi non ha il campo', () async {
      final id = await repo.saveTrack(makeTrack());
      final doc = await tracksCol().doc(id).get();
      expect(doc.data()!.containsKey('gaps'), isFalse,
          reason: 'assente = "non sappiamo", e non va scritto un [] vuoto');
    });
  });

  group('declareGaps', () {
    test('aggiunge la dichiarazione e la rilegge', () async {
      final id = await repo.saveTrack(makeTrack());
      final merged = await repo.declareGaps(id, [declaredGap()]);
      expect(merged, hasLength(1));
      expect(merged.single.isOwnerDeclared, isTrue);

      final loaded = await repo.getTrackById(id);
      expect(loaded!.gaps, hasLength(1));
      expect(loaded.gaps.single.isOwnerDeclared, isTrue);
    });

    test('convive con i buchi del watchdog, in ordine cronologico', () async {
      final id = await repo.saveTrack(makeTrack(gaps: [watchdogGap()]));
      final merged = await repo.declareGaps(id, [declaredGap(startSec: 50, endSec: 60)]);
      expect(merged, hasLength(2));
      // La dichiarazione (50s) precede il buco del watchdog (100s).
      expect(merged.first.isOwnerDeclared, isTrue);
      expect(merged.last.cause, TrackGap.causeAppFrozen);
      expect(merged.first.startedAt.isBefore(merged.last.startedAt), isTrue);
    });

    test('rifiuta una dichiarazione che si sovrappone a un buco esistente', () async {
      final id = await repo.saveTrack(makeTrack(gaps: [watchdogGap()]));
      // Il watchdog copre 100-110s: questa lo interseca.
      final merged = await repo.declareGaps(id, [declaredGap(startSec: 105, endSec: 130)]);
      expect(merged, hasLength(1), reason: 'niente sovrapposizioni');
      expect(merged.single.cause, TrackGap.causeAppFrozen);
    });

    test('non tocca punti, statistiche, geometria', () async {
      final id = await repo.saveTrack(makeTrack());
      final before = (await tracksCol().doc(id).get()).data()!;
      final geoBefore = (await tracksCol()
              .doc(id)
              .collection('geometry')
              .doc('data')
              .get())
          .data()!['pointsJson'];

      await repo.declareGaps(id, [declaredGap()]);

      final after = (await tracksCol().doc(id).get()).data()!;
      final geoAfter = (await tracksCol()
              .doc(id)
              .collection('geometry')
              .doc('data')
              .get())
          .data()!['pointsJson'];

      // La distanza — il numero che alimenta classifica e XP — non si muove.
      expect(after['distance'], before['distance']);
      expect(after['elevationGain'], before['elevationGain']);
      expect(after['movingTime'], before['movingTime']);
      expect(after['pointsCount'], before['pointsCount']);
      expect(geoAfter, geoBefore, reason: 'i punti sono intoccabili');
    });
  });

  group('removeDeclaredGaps', () {
    test('toglie solo le dichiarazioni, mai le misure del watchdog', () async {
      final id = await repo.saveTrack(makeTrack(gaps: [watchdogGap()]));
      await repo.declareGaps(id, [declaredGap()]);

      final remaining = await repo.removeDeclaredGaps(id);
      expect(remaining, hasLength(1));
      expect(remaining.single.cause, TrackGap.causeAppFrozen,
          reason: 'il buco misurato resta: non e\' ritirabile');
    });

    test('senza piu' ' buchi il campo sparisce: si torna a "non sappiamo"', () async {
      final id = await repo.saveTrack(makeTrack());
      await repo.declareGaps(id, [declaredGap()]);
      final remaining = await repo.removeDeclaredGaps(id);

      expect(remaining, isEmpty);
      final doc = await tracksCol().doc(id).get();
      expect(doc.data()!.containsKey('gaps'), isFalse,
          reason: 'il campo assente e\' lo stato di prima della dichiarazione');
    });
  });

  group('i fallimenti lanciano invece di fingere successo', () {
    // Prima ritornavano la lista come se fosse stata scritta: la UI mostrava
    // "Interruzioni dichiarate" e alla riapertura spariva tutto.
    test('declareGaps su una traccia inesistente lancia', () async {
      expect(
        () => repo.declareGaps('non-esiste', [declaredGap()]),
        throwsStateError,
      );
    });

    test('removeDeclaredGaps su una traccia inesistente lancia', () async {
      expect(
        () => repo.removeDeclaredGaps('non-esiste'),
        throwsStateError,
      );
    });

    test('declareGaps con lista vuota ritorna lo stato attuale, senza scrivere', () async {
      final id = await repo.saveTrack(makeTrack(gaps: [watchdogGap()]));
      final result = await repo.declareGaps(id, const []);
      expect(result, hasLength(1));
      expect(result.single.cause, TrackGap.causeAppFrozen);
    });
  });

  group('split e merge non corrompono i buchi', () {
    test('lo split assegna ogni buco alla meta\' in cui cade', () async {
      // 30 punti, 10 s l'uno. Il buco del watchdog sta a 100-110 s: nella
      // prima meta' se si taglia all'indice 20 (200 s).
      final id = await repo.saveTrack(makeTrack(gaps: [watchdogGap()]));
      final loaded = await repo.getTrackById(id);

      final ids = await repo.splitTrack(loaded!, 20);
      expect(ids, isNotNull);

      final part1 = await repo.getTrackById(ids!.firstId);
      final part2 = await repo.getTrackById(ids.secondId);

      expect(part1!.gaps, hasLength(1),
          reason: 'il buco cade nell\'intervallo della prima meta\'');
      expect(part2!.gaps, isEmpty,
          reason: 'la seconda meta\' non deve ereditare un buco altrui');
    });

    test('il merge conserva i buchi di ENTRAMBE le tracce', () async {
      // Due tracce distinte nel tempo; solo la seconda ha un buco.
      final idA = await repo.saveTrack(makeTrack());
      final laterBase = base.add(const Duration(hours: 2));
      final trackB = Track(
        name: 'Giro pomeriggio',
        points: List.generate(
          30,
          (i) => TrackPoint(
            latitude: 46.0 + i * 0.0005,
            longitude: 9.0 + i * 0.0003 + (i.isEven ? 0.0006 : -0.0006),
            elevation: 100.0 + i,
            timestamp: laterBase.add(Duration(seconds: i * 10)),
            speed: 1.5,
            accuracy: 5,
          ),
        ),
        createdAt: laterBase,
        recordedAt: laterBase,
        elevationCorrectedFromDem: true,
        gaps: [
          TrackGap(
            startedAt: laterBase.add(const Duration(seconds: 100)),
            endedAt: laterBase.add(const Duration(seconds: 110)),
            cause: TrackGap.causeAppFrozen,
          ),
        ],
      );
      final idB = await repo.saveTrack(trackB);

      final a = await repo.getTrackById(idA);
      final b = await repo.getTrackById(idB);
      final mergedId = await repo.mergeTracks(a!, b!);
      expect(mergedId, isNotNull);

      final merged = await repo.getTrackById(mergedId!);
      expect(merged!.gaps, hasLength(1),
          reason: 'il buco del pomeriggio non deve sparire nell\'unione');
      expect(merged.gaps.single.cause, TrackGap.causeAppFrozen);
    });
  });
}
