import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailshare_flutter/core/services/onboarding_checklist_service.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

void main() {
  const uid = 'u1';
  late FakeFirebaseFirestore fs;
  late MockFirebaseAuth auth;
  late OnboardingChecklistService svc;

  Future<void> addTracks(int n) async {
    for (var i = 0; i < n; i++) {
      await fs.collection('users').doc(uid).collection('tracks').add({
        'name': 'T$i',
        'hasGeometryDoc': true,
      });
    }
  }

  Future<void> setProfile(Map<String, dynamic> data) =>
      fs.collection('user_profiles').doc(uid).set(data);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fs = FakeFirebaseFirestore();
    auth = MockFirebaseAuth();
    final user = MockUser();
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.uid).thenReturn(uid);
    svc = OnboardingChecklistService(firestore: fs, auth: auth);
  });

  test('utente nuovo: tutti i task incompleti, card mostrata', () async {
    final s = await svc.load();
    expect(s, isNotNull);
    expect(s!.recorded, isFalse);
    expect(s.explored, isFalse);
    expect(s.favorited, isFalse);
    expect(s.profileDone, isFalse);
    expect(s.doneCount, 0);
    expect(s.allDone, isFalse);
  });

  test('una traccia → task "registra" completato', () async {
    await addTracks(1);
    final s = await svc.load();
    expect(s!.recorded, isTrue);
    expect(s.doneCount, 1);
  });

  test('wishlist non vuota → task "preferito"; avatar/bio → "profilo"',
      () async {
    await setProfile({
      'wishlist': ['trail_1'],
      'avatarUrl': 'https://x/a.jpg',
    });
    final s = await svc.load();
    expect(s!.favorited, isTrue);
    expect(s.profileDone, isTrue);
  });

  test('markExplored → task "esplora" completato', () async {
    await svc.markExplored();
    final s = await svc.load();
    expect(s!.explored, isTrue);
  });

  test('tutti i task fatti → card nascosta (null)', () async {
    await addTracks(1);
    await svc.markExplored();
    await setProfile({
      'wishlist': ['t'],
      'bio': 'ciao',
    });
    final s = await svc.load();
    expect(s, isNull, reason: 'allDone deve nascondere la checklist');
  });

  test('utente già attivo (>=5 tracce) → card nascosta', () async {
    await addTracks(5);
    final s = await svc.load();
    expect(s, isNull, reason: 'gli utenti attivi non vedono l’onboarding');
  });

  test('dismiss → card nascosta anche se non completata', () async {
    await svc.dismiss();
    final s = await svc.load();
    expect(s, isNull);
  });
}
