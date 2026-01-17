// ═══════════════════════════════════════════════════════════════════════════
// FIX MEMORIA: TracksPage con Paginazione (Lazy Load)
// File: lib/presentation/pages/tracks/tracks_page.dart
// ═══════════════════════════════════════════════════════════════════════════
//
// ISTRUZIONI: Queste sono le MODIFICHE da fare al file esistente
//

// ═══════════════════════════════════════════════════════════════════════════
// STEP 1: Aggiungi queste variabili allo State (dopo _error)
// ═══════════════════════════════════════════════════════════════════════════

  // Paginazione
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();


// ═══════════════════════════════════════════════════════════════════════════
// STEP 2: Modifica initState per aggiungere il listener scroll
// ═══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _scrollController.addListener(_onScroll); // AGGIUNGI QUESTA RIGA
    _loadTracks();
  }


// ═══════════════════════════════════════════════════════════════════════════
// STEP 3: Modifica dispose per rimuovere il controller
// ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose(); // AGGIUNGI QUESTA RIGA
    super.dispose();
  }


// ═══════════════════════════════════════════════════════════════════════════
// STEP 4: Aggiungi il metodo _onScroll per il lazy loading
// ═══════════════════════════════════════════════════════════════════════════

  /// Listener per caricare più tracce quando si raggiunge il fondo
  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreTracks();
    }
  }


// ═══════════════════════════════════════════════════════════════════════════
// STEP 5: Modifica _loadTracks per usare la paginazione
// ═══════════════════════════════════════════════════════════════════════════

  Future<void> _loadTracks() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
        _error = 'Effettua il login per vedere le tue tracce';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _tracks = null;
      _lastDocument = null; // Reset paginazione
      _hasMore = true;
    });

    try {
      // Usa il metodo paginato
      final result = await _repository.getUserTracksPaginated(
        user.uid,
        limit: 10, // Carica solo 10 alla volta
      );
      
      setState(() {
        _tracks = result.tracks;
        _lastDocument = result.lastDocument;
        _hasMore = result.hasMore;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Errore caricamento: $e';
        _isLoading = false;
      });
    }
  }


// ═══════════════════════════════════════════════════════════════════════════
// STEP 6: Aggiungi il metodo _loadMoreTracks per caricare altre pagine
// ═══════════════════════════════════════════════════════════════════════════

  /// Carica altre tracce (paginazione)
  Future<void> _loadMoreTracks() async {
    // Non caricare se già in corso, non ci sono più dati, o non c'è un cursore
    if (_isLoadingMore || !_hasMore || _lastDocument == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoadingMore = true);

    try {
      final result = await _repository.getUserTracksPaginated(
        user.uid,
        limit: 10,
        lastDocument: _lastDocument,
      );

      setState(() {
        _tracks = [...?_tracks, ...result.tracks];
        _lastDocument = result.lastDocument;
        _hasMore = result.hasMore;
        _isLoadingMore = false;
      });
    } catch (e) {
      print('[TracksPage] Errore caricamento altre tracce: $e');
      setState(() => _isLoadingMore = false);
    }
  }


// ═══════════════════════════════════════════════════════════════════════════
// STEP 7: Modifica il ListView.builder nel metodo _buildTracksListTab
// ═══════════════════════════════════════════════════════════════════════════

// Trova questo codice:
//   return RefreshIndicator(
//     onRefresh: _loadTracks,
//     child: ListView.builder(
//       padding: const EdgeInsets.all(16),
//       itemCount: _tracks!.length,

// Sostituisci con:
    return RefreshIndicator(
      onRefresh: _loadTracks,
      child: ListView.builder(
        controller: _scrollController, // AGGIUNGI QUESTO
        padding: const EdgeInsets.all(16),
        itemCount: _tracks!.length + (_hasMore ? 1 : 0), // +1 per il loader
        itemBuilder: (context, index) {
          // Se siamo all'ultimo item e ci sono altre pagine, mostra loader
          if (index >= _tracks!.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          
          final track = _tracks![index];
          // ... resto del codice esistente per la card
        },
      ),
    );
