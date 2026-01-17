import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/wishlist_repository.dart';

/// Bottone Wishlist (salva/rimuovi dai preferiti)
/// 
/// Uso:
/// ```dart
/// WishlistButton(
///   trackId: 'abc123',
///   initialIsInWishlist: false,
/// )
/// ```
class WishlistButton extends StatefulWidget {
  final String trackId;
  final bool initialIsInWishlist;
  final double size;
  final bool showLabel;
  final VoidCallback? onAuthRequired;
  final Function(bool isNowInWishlist)? onChanged;

  const WishlistButton({
    super.key,
    required this.trackId,
    this.initialIsInWishlist = false,
    this.size = 24,
    this.showLabel = false,
    this.onAuthRequired,
    this.onChanged,
  });

  @override
  State<WishlistButton> createState() => _WishlistButtonState();
}

class _WishlistButtonState extends State<WishlistButton> with SingleTickerProviderStateMixin {
  final WishlistRepository _repository = WishlistRepository();
  
  late bool _isInWishlist;
  bool _isLoading = false;
  
  // Animazione
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _isInWishlist = widget.initialIsInWishlist;
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
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

  Future<void> _toggleWishlist() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    // Feedback aptico
    HapticFeedback.lightImpact();

    // Animazione
    _animationController.forward().then((_) => _animationController.reverse());

    final result = await _repository.toggleWishlist(widget.trackId);

    if (result.success) {
      setState(() {
        _isInWishlist = result.isNowInWishlist ?? false;
      });
      
      widget.onChanged?.call(_isInWishlist);

      if (mounted && result.message != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message!),
            backgroundColor: _isInWishlist ? AppColors.success : AppColors.textSecondary,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
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
        onTap: _isLoading ? null : _toggleWishlist,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _scaleAnimation,
                child: Icon(
                  _isInWishlist ? Icons.bookmark : Icons.bookmark_border,
                  color: _isInWishlist ? AppColors.warning : AppColors.textMuted,
                  size: widget.size,
                ),
              ),
              if (widget.showLabel) ...[
                const SizedBox(width: 4),
                Text(
                  _isInWishlist ? 'Salvato' : 'Salva',
                  style: TextStyle(
                    color: _isInWishlist ? AppColors.warning : AppColors.textMuted,
                    fontWeight: _isInWishlist ? FontWeight.w600 : FontWeight.normal,
                    fontSize: widget.size * 0.55,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Versione icona semplice per AppBar o liste compatte
class WishlistIconButton extends StatefulWidget {
  final String trackId;
  final bool initialIsInWishlist;
  final Color? color;
  final Color? activeColor;

  const WishlistIconButton({
    super.key,
    required this.trackId,
    this.initialIsInWishlist = false,
    this.color,
    this.activeColor,
  });

  @override
  State<WishlistIconButton> createState() => _WishlistIconButtonState();
}

class _WishlistIconButtonState extends State<WishlistIconButton> {
  final WishlistRepository _repository = WishlistRepository();
  late bool _isInWishlist;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isInWishlist = widget.initialIsInWishlist;
    _checkWishlistStatus();
  }

  Future<void> _checkWishlistStatus() async {
    final isIn = await _repository.isInWishlist(widget.trackId);
    if (mounted) {
      setState(() => _isInWishlist = isIn);
    }
  }

  Future<void> _toggle() async {
    if (_isLoading) return;
    
    setState(() => _isLoading = true);
    HapticFeedback.lightImpact();

    final result = await _repository.toggleWishlist(widget.trackId);
    
    if (result.success && mounted) {
      setState(() => _isInWishlist = result.isNowInWishlist ?? false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? (_isInWishlist ? 'Salvato!' : 'Rimosso')),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _isInWishlist ? Icons.bookmark : Icons.bookmark_border,
        color: _isInWishlist 
            ? (widget.activeColor ?? AppColors.warning) 
            : (widget.color ?? AppColors.textMuted),
      ),
      onPressed: _isLoading ? null : _toggle,
      tooltip: _isInWishlist ? 'Rimuovi dai salvati' : 'Salva percorso',
    );
  }
}
