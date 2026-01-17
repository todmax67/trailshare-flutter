// ═══════════════════════════════════════════════════════════════════════════
// FIX MEMORIA: DiscoverPage con caricamento su viewport
// File: lib/presentation/pages/discover/discover_page.dart
// ═══════════════════════════════════════════════════════════════════════════
//
// ISTRUZIONI: Queste sono le MODIFICHE da fare al file esistente
//

// ═══════════════════════════════════════════════════════════════════════════
// STEP 1: Aggiungi queste variabili allo State
// ═══════════════════════════════════════════════════════════════════════════

  // Viewport-based loading
  LatLngBounds? _currentBounds;
  bool _isLoadingViewport = false;
  Timer? _debounceTimer;


// ═══════════════════════════════════════════════════════════════════════════
// STEP 2: Aggiungi import per Timer (in cima al file)
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';


// ═══════════════════════════════════════════════════════════════════════════
// STEP 3: Modifica le MapOptions nel FlutterMap per aggiungere onMapEvent
// ═══════════════════════════════════════════════════════════════════════════

// Trova dove crei FlutterMap e aggiungi onMapEvent:

  FlutterMap(
    mapController: _mapController,
    options: MapOptions(
      initialCenter: ...,
      initialZoom: 12,
      minZoom: 8,
      maxZoom: 18,
      // AGGIUNGI QUESTO:
      onMapEvent: _onMapEvent,
    ),
    children: [
      // ...
    ],
  )


// ═══════════════════════════════════════════════════════════════════════════
// STEP 4: Aggiungi il metodo _onMapEvent per rilevare spostamenti mappa
// ═══════════════════════════════════════════════════════════════════════════

  /// Chiamato quando la mappa si muove
  void _onMapEvent(MapEvent event) {
    // Carica solo quando l'utente smette di muovere la mappa
    if (event is MapEventMoveEnd || event is MapEventFlingEnd) {
      _loadTracksInViewport();
    }
  }

  /// Carica le tracce visibili nel viewport corrente (con debounce)
  void _loadTracksInViewport() {
    // Cancella il timer precedente
    _debounceTimer?.cancel();
    
    // Aspetta 300ms prima di caricare (evita troppe chiamate)
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _doLoadTracksInViewport();
    });
  }

  /// Effettua il caricamento delle tracce nel viewport
  Future<void> _doLoadTracksInViewport() async {
    if (_isLoadingViewport) return;

    // Ottieni i bounds attuali della mappa
    final bounds = _mapController.camera.visibleBounds;
    
    // Se i bounds sono gli stessi, non ricaricare
    if (_currentBounds != null && 
        _boundsAreSimilar(_currentBounds!, bounds)) {
      return;
    }

    setState(() => _isLoadingViewport = true);
    _currentBounds = bounds;

    try {
      // Carica solo i sentieri nel bounding box visibile
      final trails = await _trailsRepository.getTrailsInBounds(
        minLat: bounds.south,
        maxLat: bounds.north,
        minLng: bounds.west,
        maxLng: bounds.east,
        limit: 50, // Massimo 50 per viewport
      );

      setState(() {
        _trails = trails;
        _isLoadingViewport = false;
      });

      print('[DiscoverPage] Caricate ${trails.length} tracce nel viewport');
    } catch (e) {
      print('[DiscoverPage] Errore caricamento viewport: $e');
      setState(() => _isLoadingViewport = false);
    }
  }

  /// Verifica se due bounds sono simili (evita ricaricamenti inutili)
  bool _boundsAreSimilar(LatLngBounds a, LatLngBounds b) {
    const threshold = 0.01; // ~1km
    return (a.north - b.north).abs() < threshold &&
           (a.south - b.south).abs() < threshold &&
           (a.east - b.east).abs() < threshold &&
           (a.west - b.west).abs() < threshold;
  }


// ═══════════════════════════════════════════════════════════════════════════
// STEP 5: Modifica dispose per cancellare il timer
// ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _debounceTimer?.cancel(); // AGGIUNGI QUESTA RIGA
    // ... resto del dispose esistente
    super.dispose();
  }


// ═══════════════════════════════════════════════════════════════════════════
// STEP 6: Modifica _loadTrailsNearby per caricare meno dati iniziali
// ═══════════════════════════════════════════════════════════════════════════

// Nel metodo esistente, riduci il limite:

  Future<void> _loadTrailsNearby() async {
    if (_userPosition == null) {
      await _loadTrailsWithoutLocation();
      return;
    }

    setState(() => _isLoadingTrails = true);

    try {
      final trails = await _trailsRepository.getTrailsNearby(
        center: _userPosition!,
        radiusKm: _searchRadiusKm,
        limit: 30, // RIDOTTO da 100 a 30
      );

      // ... resto del codice
    } catch (e) {
      // ... gestione errore
    }
  }


// ═══════════════════════════════════════════════════════════════════════════
// STEP 7 (OPZIONALE): Mostra indicatore di caricamento sulla mappa
// ═══════════════════════════════════════════════════════════════════════════

// Aggiungi questo widget sopra la mappa:

  if (_isLoadingViewport)
    Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Caricamento...', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    ),
