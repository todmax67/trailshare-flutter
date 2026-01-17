import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/live_track_service.dart';

/// Bottone per attivare/disattivare LiveTrack durante la registrazione
/// 
/// Mostra stato con colore e animazione, permette di:
/// - Avviare LiveTrack e condividere link
/// - Ricondividere link
/// - Fermare LiveTrack
class LiveTrackButton extends StatefulWidget {
  final VoidCallback? onStatusChanged;

  const LiveTrackButton({
    super.key,
    this.onStatusChanged,
  });

  @override
  State<LiveTrackButton> createState() => _LiveTrackButtonState();
}

class _LiveTrackButtonState extends State<LiveTrackButton>
    with SingleTickerProviderStateMixin {
  final LiveTrackService _service = LiveTrackService();
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Ascolta stato
    _service.stateStream.listen((state) {
      if (mounted) {
        setState(() {});
        if (state.isActive) {
          _pulseController.repeat(reverse: true);
        } else {
          _pulseController.stop();
          _pulseController.reset();
        }
      }
    });

    // Se già attivo, avvia animazione
    if (_service.isActive) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _toggleLiveTrack() async {
    if (_isLoading) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar('Devi essere loggato per usare LiveTrack', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    if (_service.isActive) {
      // Mostra dialog conferma stop
      final shouldStop = await _showStopDialog();
      if (shouldStop == true) {
        await _service.stop();
        _showSnackBar('LiveTrack terminato');
        widget.onStatusChanged?.call();
      }
    } else {
      // Avvia LiveTrack
      final success = await _service.startAndShare(
        userName: user.displayName ?? user.email ?? 'Escursionista',
      );
      
      if (success) {
        final sessionId = _service.getSessionId();
        _showSnackBar('LiveTrack attivo! ID: $sessionId (copiato) 🎉', isSuccess: true);
        widget.onStatusChanged?.call();
      } else {
        _showSnackBar('Errore avvio LiveTrack', isError: true);
      }
    }

    setState(() => _isLoading = false);
  }

  Future<void> _reshare() async {
    await _service.reshare();
    _showSnackBar('Link condiviso di nuovo!');
  }

  Future<bool?> _showStopDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fermare LiveTrack?'),
        content: const Text(
          'Chi sta seguendo la tua posizione non potrà più vederti.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Ferma'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false, bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError 
            ? AppColors.danger 
            : isSuccess 
                ? AppColors.success 
                : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _service.isActive;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Bottone principale
        ScaleTransition(
          scale: isActive ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
          child: GestureDetector(
            onTap: _isLoading ? null : _toggleLiveTrack,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isActive ? AppColors.danger : Colors.white,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: isActive ? AppColors.danger : AppColors.textMuted,
                  width: 1.5,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: AppColors.danger.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isLoading)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: isActive ? Colors.white : AppColors.primary,
                      ),
                    )
                  else
                    Icon(
                      isActive ? Icons.broadcast_on_personal : Icons.broadcast_on_personal_outlined,
                      size: 18,
                      color: isActive ? Colors.white : AppColors.textMuted,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    isActive ? 'LIVE' : 'LiveTrack',
                    style: TextStyle(
                      color: isActive ? Colors.white : AppColors.textSecondary,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // Bottone ricondividi (solo se attivo)
        if (isActive) ...[
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.share, size: 20),
            onPressed: _reshare,
            tooltip: 'Condividi di nuovo',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Widget compatto per mostrare stato LiveTrack in header
class LiveTrackIndicator extends StatelessWidget {
  const LiveTrackIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final service = LiveTrackService();
    
    if (!service.isActive) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broadcast_on_personal, size: 14, color: Colors.white),
          SizedBox(width: 4),
          Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
