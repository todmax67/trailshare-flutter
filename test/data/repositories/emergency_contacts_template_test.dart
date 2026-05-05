import 'package:flutter_test/flutter_test.dart';
import 'package:trailshare_flutter/data/repositories/emergency_contacts_repository.dart';

void main() {
  const repo = EmergencyContactsRepository;

  group('EmergencyContactsRepository.renderTemplate', () {
    test('substitutes the basic placeholders {nome} {attività} {link}', () {
      final out = EmergencyContactsRepository.renderTemplate(
        template: 'Ciao {nome}, sto facendo {attività}: {link}',
        contactName: 'Marco',
        activityName: 'trekking',
        link: 'https://trailshare.app/live?id=abc',
      );
      expect(out, 'Ciao Marco, sto facendo trekking: https://trailshare.app/live?id=abc');
    });

    test('tolerates {attivita} (no accent) for compatibility', () {
      final out = EmergencyContactsRepository.renderTemplate(
        template: '{attivita} in corso, link: {link}',
        contactName: 'X',
        activityName: 'cycling',
        link: 'https://x',
      );
      expect(out, 'cycling in corso, link: https://x');
    });

    test('omits the trail clause when referenceName is null', () {
      final out = EmergencyContactsRepository.renderTemplate(
        template: 'Faccio {attività}{nomeTraccia} oggi',
        contactName: 'Marco',
        activityName: 'trekking',
        link: 'https://x',
        referenceName: null,
      );
      expect(out, 'Faccio trekking oggi');
    });

    test('omits the trail clause when referenceName is whitespace-only', () {
      final out = EmergencyContactsRepository.renderTemplate(
        template: '{attività}{nomeTraccia}',
        contactName: 'Marco',
        activityName: 'trekking',
        link: 'https://x',
        referenceName: '   ',
      );
      expect(out, 'trekking');
    });

    test('inserts the trail clause with quotes when referenceName is set', () {
      final out = EmergencyContactsRepository.renderTemplate(
        template: '{attività}{nomeTraccia}',
        contactName: 'Marco',
        activityName: 'trekking',
        link: 'https://x',
        referenceName: 'Sentiero del Resegone',
      );
      expect(out, 'trekking lungo "Sentiero del Resegone"');
    });

    test('replaces ALL occurrences of a placeholder', () {
      final out = EmergencyContactsRepository.renderTemplate(
        template: 'Ciao {nome}! {nome}, ricorda: {link}',
        contactName: 'Anna',
        activityName: '-',
        link: 'L',
      );
      expect(out, 'Ciao Anna! Anna, ricorda: L');
    });

    test('default template renders a complete message', () {
      final out = EmergencyContactsRepository.renderTemplate(
        template: EmergencyContactsRepository.defaultMessageTemplate,
        contactName: 'Luca',
        activityName: 'escursione',
        referenceName: null,
        link: 'https://trailshare.app/live?id=abc&token=xyz',
      );
      expect(out, contains('Ciao Luca'));
      expect(out, contains('escursione'));
      expect(out, contains('https://trailshare.app/live?id=abc&token=xyz'));
      // Senza referenceName, non deve esserci "lungo"
      expect(out, isNot(contains('lungo "')));
    });

    test('does not crash on a template without any placeholders', () {
      final out = EmergencyContactsRepository.renderTemplate(
        template: 'Messaggio statico',
        contactName: 'X',
        activityName: 'Y',
        link: 'Z',
      );
      expect(out, 'Messaggio statico');
    });
  });

  test('EmergencyContactsRepository class is accessible', () {
    // Smoke test che l'import sia corretto e la classe esposta.
    expect(repo, isNotNull);
  });
}
