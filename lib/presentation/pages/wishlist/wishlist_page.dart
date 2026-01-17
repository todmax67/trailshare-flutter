import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/wishlist_repository.dart';
import '../../../data/repositories/community_tracks_repository.dart';
import '../../widgets/community_track_card.dart';
import '../discover/community_track_detail_page.dart';
import '../../../data/models/track.dart';

/// Pagina che mostra i percorsi salvati nella wishlist
class WishlistPage extends StatefulWidget {
  const WishlistPage({super.key});

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  final WishlistRepository _wishlistRepository = WishlistRepository();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<CommunityTrack> _tracks = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadWishlistTracks();
  }

  Future<void> _loadWishlistTracks() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
        _error = 'login_required';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 1. Ottieni gli ID dalla wishlist
      final trackIds = await _wishlistRepository.getWishlistIds();

      if (trackIds.isEmpty) {
        setState(() {
          _tracks = [];
          _isLoading = false;
        });
        return;
      }

      // 2. Carica le tracce da published_tracks
      // Firestore limita "whereIn" a 30 elementi
      final List<CommunityTrack> loadedTracks = [];
      
      // Dividi in batch da 30
      for (int i = 0; i < trackIds.length; i += 30) {
        final batchIds = trackIds.skip(i).take(30).toList();
        
        final snapshot = await _firestore
            .collection('published_tracks')
            .where(FieldPath.documentId, whereIn: batchIds)
            .get();

        for (final doc in snapshot.docs) {
          final track = _parseCommunityTrack(doc);
          if (track != null) {
            loadedTracks.add(track);
          }
        }
      }

      setState(() {
        _tracks = loadedTracks;
        _isLoading = false;
      });
    } catch (e) {
      print('[WishlistPage] Errore: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  CommunityTrack? _parseCommunityTrack(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return null;

      return CommunityTrack(
        id: doc.id,
        name: data['name'] ?? 'Senza nome',
        ownerUsername: data['ownerUsername'] ?? 'Utente',
        ownerId: data['originalOwnerId'] ?? '',
        activityType: data['activityType'] ?? 'trekking',
        distance: (data['distance'] as num?)?.toDouble() ?? 0,
        elevationGain: (data['elevationGain'] as num?)?.toDouble() ?? 0,
        duration: (data['duration'] as num?)?.toInt() ?? 0,
        cheerCount: (data['cheerCount'] as num?)?.toInt() ?? 0,
        points: _parsePoints(data['points']),
        sharedAt: (data['sharedAt'] as Timestamp?)?.toDate(),
      );
    } catch (e) {
      print('[WishlistPage] Errore parsing track: $e');
      return null;
    }
  }

  List<TrackPoint> _parsePoints(dynamic pointsData) {
    if (pointsData == null) return [];
    if (pointsData is! List) return [];

    return pointsData.map<TrackPoint>((p) {
      if (p is Map) {
        return TrackPoint(
          latitude: (p['latitude'] ?? p['y'] ?? 0).toDouble(),
          longitude: (p['longitude'] ?? p['x'] ?? 0).toDouble(),
          elevation: (p['elevation'] ?? p['z'] ?? 0).toDouble(),
          timestamp: DateTime.now(),
        );
      }
      return TrackPoint(latitude: 0, longitude: 0, timestamp: DateTime.now());
    }).toList();
  }

  Future<void> _removeFromWishlist(String trackId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rimuovi dai salvati'),
        content: const Text('Vuoi rimuovere questo percorso dalla tua lista?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _wishlistRepository.removeFromWishlist(trackId);
      if (success && mounted) {
        setState(() {
          _tracks.removeWhere((t) => t.id == trackId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Percorso rimosso dai salvati'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  void _openTrackDetail(CommunityTrack track) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityTrackDetailPage(track: track),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Percorsi Salvati'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error == 'login_required') {
      return _buildLoginRequired();
    }

    if (_error != null) {
      return _buildError();
    }

    if (_tracks.isEmpty) {
      return _buildEmpty();
    }

    return _buildList();
  }

  Widget _buildLoginRequired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_border, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 24),
            const Text(
              'Accedi per vedere i tuoi percorsi salvati',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Salva i percorsi che ti interessano per ritrovarli facilmente!',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.danger),
            const SizedBox(height: 16),
            const Text(
              'Errore nel caricamento',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Errore sconosciuto',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadWishlistTracks,
              icon: const Icon(Icons.refresh),
              label: const Text('Riprova'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bookmark_border, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 24),
            const Text(
              'Nessun percorso salvato',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Esplora la sezione "Scopri" e salva i percorsi che ti interessano!',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.explore),
              label: const Text('Vai a Scopri'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      onRefresh: _loadWishlistTracks,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _tracks.length,
        itemBuilder: (context, index) {
          final track = _tracks[index];
          return Dismissible(
            key: Key(track.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: AppColors.danger,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) async {
              await _removeFromWishlist(track.id);
              return false; // Gestiamo noi la rimozione
            },
            child: CommunityTrackCard(
              trackId: track.id,
              name: track.name,
              ownerUsername: track.ownerUsername,
              activityIcon: track.activityIcon,
              distanceKm: track.distanceKm,
              elevationGain: track.elevationGain,
              durationFormatted: track.durationFormatted,
              cheerCount: track.cheerCount,
              sharedAt: track.sharedAt,
              onTap: () => _openTrackDetail(track),
            ),
          );
        },
      ),
    );
  }
}
