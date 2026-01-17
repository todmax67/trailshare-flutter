import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/cheers_repository.dart';

/// Bottone Cheer (like) riutilizzabile
/// 
/// Uso:
/// ```dart
/// CheerButton(
///   trackId: 'abc123',
///   initialCount: 5,
///   initialHasCheered: false,
/// )
/// ```
class CheerButton extends StatefulWidget {
  final String trackId;
  final int initialCount;
  final bool initialHasCheered;
  final bool showCount;
  final double size;
  final VoidCallback? onAuthRequired;

  const CheerButton({
    super.key,
    required this.trackId,
    this.initialCount = 0,
    this.initialHasCheered = false,
    this.showCount = true,
    this.size = 24,
    this.onAuthRequired,
  });

  @override
  State<CheerButton> createState() => _CheerButtonState();
}

class _CheerButtonState extends State<CheerButton> with SingleTickerProviderStateMixin {
  final CheersRepository _repository = CheersRepository();
  
  late int _count;
  late bool _hasCheered;
  bool _isLoading = false;
  
  // Animazione
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _count = widget.initialCount;
    _hasCheered = widget.initialHasCheered;
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _toggleCheer() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    // Feedback aptico
    HapticFeedback.lightImpact();

    // Animazione ottimistica
    _animationController.forward().then((_) => _animationController.reverse());

    final result = await _repository.toggleCheer(widget.trackId);

    if (result.success) {
      setState(() {
        _hasCheered = result.isNowCheered ?? false;
        _count = _hasCheered ? _count + 1 : _count - 1;
        if (_count < 0) _count = 0;
      });
    } else {
      // Errore - mostra messaggio
      if (mounted) {
        if (result.error?.contains('login') == true) {
          widget.onAuthRequired?.call();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Errore'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : _toggleCheer,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _scaleAnimation,
                child: Icon(
                  _hasCheered ? Icons.favorite : Icons.favorite_border,
                  color: _hasCheered ? Colors.red : AppColors.textMuted,
                  size: widget.size,
                ),
              ),
              if (widget.showCount) ...[
                const SizedBox(width: 4),
                Text(
                  _formatCount(_count),
                  style: TextStyle(
                    color: _hasCheered ? Colors.red : AppColors.textMuted,
                    fontWeight: _hasCheered ? FontWeight.w600 : FontWeight.normal,
                    fontSize: widget.size * 0.6,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}

/// Versione compatta del CheerButton per le liste
class CheerButtonCompact extends StatelessWidget {
  final String trackId;
  final int count;
  final bool hasCheered;
  final VoidCallback? onTap;

  const CheerButtonCompact({
    super.key,
    required this.trackId,
    this.count = 0,
    this.hasCheered = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CheerButton(
      trackId: trackId,
      initialCount: count,
      initialHasCheered: hasCheered,
      size: 20,
    );
  }
}

/// Widget per mostrare solo il conteggio (senza interazione)
class CheerCount extends StatelessWidget {
  final int count;
  final bool highlighted;

  const CheerCount({
    super.key,
    required this.count,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          highlighted ? Icons.favorite : Icons.favorite_border,
          color: highlighted ? Colors.red : AppColors.textMuted,
          size: 16,
        ),
        const SizedBox(width: 4),
        Text(
          count.toString(),
          style: TextStyle(
            color: highlighted ? Colors.red : AppColors.textMuted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
