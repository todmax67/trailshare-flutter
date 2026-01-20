// ============================================================
// ISTRUZIONI per aggiungere la sezione Admin in settings_page.dart
// ============================================================
//
// 1. Aggiungi l'import in cima al file:
// ------------------------------------------------------------
import '../admin/geohash_migration_page.dart';
// ------------------------------------------------------------
//
// 2. Trova la sezione "Zona Pericolosa" (circa in fondo al metodo build)
//    e PRIMA di quella sezione, aggiungi la sezione Admin:
// ------------------------------------------------------------

          // Sezione Admin (solo per admin/sviluppatori)
          // TODO: In produzione, controllare se l'utente è admin
          if (_isAdmin(user)) ...[
            const Divider(height: 32),
            _buildSectionHeader('Amministrazione', danger: false),
            _buildListTile(
              icon: Icons.location_on,
              title: 'Migrazione GeoHash',
              subtitle: 'Gestisci indici geospaziali per i sentieri',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GeohashMigrationPage()),
                );
              },
            ),
            _buildListTile(
              icon: Icons.analytics_outlined,
              title: 'Statistiche Database',
              subtitle: 'Visualizza metriche e utilizzo',
              onTap: () {
                // TODO: Implementare pagina statistiche
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Coming soon!')),
                );
              },
            ),
          ],

          // Zona pericolosa (solo se loggato)
          // ... resto del codice esistente ...

// ------------------------------------------------------------
//
// 3. Aggiungi il metodo _isAdmin nella classe _SettingsPageState:
// ------------------------------------------------------------

  /// Verifica se l'utente è admin
  /// In produzione: controllare un campo 'isAdmin' nel documento utente su Firestore
  bool _isAdmin(User? user) {
    if (user == null) return false;
    
    // Lista di email admin (per sviluppo)
    // In produzione: usare un campo su Firestore o Firebase Custom Claims
    const adminEmails = [
      'admin@trailshare.app',
      'developer@trailshare.app',
      // Aggiungi qui le tue email di sviluppo
    ];
    
    return adminEmails.contains(user.email?.toLowerCase());
  }

// ============================================================
// ALTERNATIVA: Mostra sempre sezione Admin (per sviluppo)
// ============================================================
// Se vuoi vedere la sezione Admin durante lo sviluppo senza controlli,
// sostituisci la condizione con:
//
//   if (true) ...[  // Sempre visibile (solo per sviluppo!)
//
// Ricorda di rimuoverla prima di rilasciare in produzione!
// ============================================================
