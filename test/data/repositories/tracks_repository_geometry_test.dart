import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:trailshare_flutter/data/models/track.dart';
import 'package:trailshare_flutter/data/repositories/tracks_repository.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

/// Test del refactor "punti GPS in sub-collezione geometria" (fix OOM).
/// Inchioda: scrittura split metadati/geometria, lazy-load in lettura,
/// retrocompatibilità con le tracce legacy (points inline), lightweight
/// senza geometria, delete a cascata, round-trip del battito.
void main() {
  const uid = 'testuid';

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late TracksRepository repo;

  CollectionReference<Map<String, dynamic>> tracksCol() =>
      firestore.collection('users').doc(uid).collection('tracks');

  DocumentReference<Map<String, dynamic>> geometryDoc(String trackId) =>
      tracksCol().doc(trackId).collection('geometry').doc('data');

  /// Track di test con [n] punti reali (distanza > 0). DEM disattivata
  /// (`elevationCorrectedFromDem: true`) per non innescare chiamate di rete.
  Track makeTrack({int n = 50, Map<DateTime, int>? hr}) {
    final base = DateTime(2026, 6, 1, 8);
    final points = List.generate(
      n,
      (i) => TrackPoint(
        latitude: 45.0 + i * 0.0005,
        longitude: 9.0 + i * 0.0003,
        elevation: 100.0 + i,
        timestamp: base.add(Duration(seconds: i * 10)),
        speed: 1.5,
        accuracy: 5,
      ),
    );
    return Track(
      name: 'Giro test',
      points: points,
      createdAt: base,
      recordedAt: base,
      elevationCorrectedFromDem: true,
      heartRateData: hr,
    );
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth();
    final user = MockUser();
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.uid).thenReturn(uid);
    repo = TracksRepository(firestore: firestore, auth: auth);
  });

  group('Scrittura: split metadati / geometria', () {
    test('il doc principale NON contiene i punti inline', () async {
      final id = await repo.saveTrack(makeTrack(n: 30));
      final doc = await tracksCol().doc(id).get();
      final data = doc.data()!;

      expect(data.containsKey('points'), isFalse,
          reason: 'i punti non devono più stare nel doc principale');
      expect(data['hasGeometryDoc'], isTrue);
      expect(data['pointsCount'], 30);
      // Le stats restano sul doc principale.
      expect((data['distance'] as num) > 0, isTrue);
    });

    test('il doc geometria contiene i punti (pointsJson)', () async {
      final id = await repo.saveTrack(makeTrack(n: 30));
      final geo = await geometryDoc(id).get();
      expect(geo.exists, isTrue);
      final pj = geo.data()!['pointsJson'] as String;
      final decoded = jsonDecode(pj) as List;
      expect(decoded.length, 30);
      expect(geo.data()!['pointsCount'], 30);
    });
  });

  group('Lettura lazy + round-trip', () {
    test('getTrackById ricarica i punti dalla geometria', () async {
      final original = makeTrack(n: 40);
      final id = await repo.saveTrack(original);

      final loaded = await repo.getTrackById(id);
      expect(loaded, isNotNull);
      expect(loaded!.points.length, 40);
      // Coordinate preservate (primo e ultimo punto).
      expect(loaded.points.first.latitude, closeTo(45.0, 1e-6));
      expect(loaded.points.last.latitude,
          closeTo(original.points.last.latitude, 1e-6));
      expect(loaded.points.last.longitude,
          closeTo(original.points.last.longitude, 1e-6));
    });

    test('il battito fa round-trip attraverso la geometria', () async {
      final hr = {
        DateTime(2026, 6, 1, 8, 0, 5): 120,
        DateTime(2026, 6, 1, 8, 0, 15): 135,
      };
      final id = await repo.saveTrack(makeTrack(n: 20, hr: hr));

      // Il battito NON è nel doc principale.
      final main = await tracksCol().doc(id).get();
      expect(main.data()!.containsKey('heartRateData'), isFalse);

      final loaded = await repo.getTrackById(id);
      expect(loaded!.heartRateData, isNotNull);
      expect(loaded.heartRateData!.values, containsAll([120, 135]));
    });
  });

  group('Retrocompatibilità: tracce legacy con points inline', () {
    test('getTrackById legge i punti inline (nessun doc geometria)', () async {
      // Seed manuale di una traccia "vecchio formato": points inline,
      // niente hasGeometryDoc, niente sub-collezione.
      final ref = await tracksCol().add({
        'name': 'Legacy',
        'userId': uid,
        'createdAt': Timestamp.fromDate(DateTime(2025, 1, 1)),
        'distance': 1234.0,
        'points': [
          {
            'longitude': 9.0,
            'latitude': 45.0,
            'altitude': 100,
            'timestamp': DateTime(2025, 1, 1).millisecondsSinceEpoch,
          },
          {
            'longitude': 9.001,
            'latitude': 45.001,
            'altitude': 110,
            'timestamp':
                DateTime(2025, 1, 1, 0, 1).millisecondsSinceEpoch,
          },
        ],
      });

      final loaded = await repo.getTrackById(ref.id);
      expect(loaded, isNotNull);
      expect(loaded!.points.length, 2,
          reason: 'le tracce legacy devono continuare a funzionare');
      expect(loaded.points.first.latitude, closeTo(45.0, 1e-6));
    });
  });

  group('Lightweight: nessuna lettura della geometria', () {
    test('getMyTracksLightweight torna senza punti ma con le stats', () async {
      final id = await repo.saveTrack(makeTrack(n: 60));
      final list = await repo.getMyTracksLightweight();
      expect(list, hasLength(1));
      expect(list.first.id, id);
      expect(list.first.points, isEmpty,
          reason: 'la lista non deve caricare i punti (perf)');
      expect(list.first.stats.distance > 0, isTrue,
          reason: 'le stats restano disponibili dai metadati');
    });
  });

  group('Delete a cascata', () {
    test('deleteTrack rimuove sia i metadati sia la geometria', () async {
      final id = await repo.saveTrack(makeTrack(n: 25));
      expect((await geometryDoc(id).get()).exists, isTrue);

      await repo.deleteTrack(id);

      expect((await tracksCol().doc(id).get()).exists, isFalse);
      expect((await geometryDoc(id).get()).exists, isFalse,
          reason: 'il doc geometria non deve restare orfano');
    });
  });

  group('Lettura cross-utente (gruppi / percorsi consigliati)', () {
    test('getTrackByOwnerAndId aggancia la geometria', () async {
      final id = await repo.saveTrack(makeTrack(n: 35));
      final loaded = await repo.getTrackByOwnerAndId(uid, id);
      expect(loaded, isNotNull);
      expect(loaded!.points.length, 35,
          reason: 'anche il percorso cross-utente deve avere i punti');
    });
  });

  group('Split: guard anti-perdita-dati', () {
    test('splitTrack idrata una traccia "leggera" e NON perde dati', () async {
      final id = await repo.saveTrack(makeTrack(n: 40));

      // Simula l'ingresso dalla lista: traccia con punti VUOTI.
      final light = (await repo.getMyTracksLightweight()).first;
      expect(light.points, isEmpty);

      final res = await repo.splitTrack(light, 20);
      expect(res, isNotNull, reason: 'deve idratare e riuscire');
      // I due nuovi pezzi hanno punti reali (non vuoti).
      final p1 = await repo.getTrackById(res!.firstId);
      final p2 = await repo.getTrackById(res.secondId);
      expect(p1!.points.length, 20);
      expect(p2!.points.length, 20);
      // L'originale è stato cancellato SOLO dopo il successo.
      expect((await tracksCol().doc(id).get()).exists, isFalse);
    });
  });

  group('updateTrackHeartRate scrive nella geometria', () {
    test('il battito aggiornato non ri-gonfia il doc principale', () async {
      final id = await repo.saveTrack(makeTrack(n: 20));
      await repo.updateTrackHeartRate(id, {
        DateTime(2026, 6, 1, 8, 0, 30): 142,
      });

      // Niente HR inline sul doc principale.
      final main = await tracksCol().doc(id).get();
      expect(main.data()!.containsKey('heartRateData'), isFalse);
      // Il lettore lo recupera dalla geometria.
      final loaded = await repo.getTrackById(id);
      expect(loaded!.heartRateData, isNotNull);
      expect(loaded.heartRateData!.values, contains(142));
    });
  });
}
