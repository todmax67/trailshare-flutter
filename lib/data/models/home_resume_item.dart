/// Una "cosa da riprendere" mostrata in cima alla Home Feed.
///
/// Per il prototipo l'unico caso gestito è il **recovery di una
/// registrazione interrotta** (crash backup): il
/// [RecordingPersistenceService] mantiene uno stato salvato che,
/// se presente all'avvio, segnala una sessione GPS non chiusa.
///
/// In futuro si potranno aggiungere altri tipi (es. tour multi-giorno
/// in corso) estendendo questa sealed class, una volta che il modello
/// Tour avrà il tracking delle tappe completate (oggi non esiste).
sealed class HomeResumeItem {
  const HomeResumeItem();
  String get title;
  String get subtitle;
}

/// Recovery di una registrazione GPS interrotta (es. crash, kill OS).
class ResumeRecordingBackup extends HomeResumeItem {
  final double partialDistanceKm;
  final Duration partialDuration;

  const ResumeRecordingBackup({
    required this.partialDistanceKm,
    required this.partialDuration,
  });

  @override
  String get title => 'Traccia interrotta';

  @override
  String get subtitle =>
      '${partialDistanceKm.toStringAsFixed(1)} km già registrati';
}
