import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';

/// Pagina Onboarding
/// 
/// Mostra un tutorial introduttivo ai nuovi utenti.
class OnboardingPage extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingPage({
    super.key,
    required this.onComplete,
  });

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingSlide> _slides = [
    OnboardingSlide(
      icon: Icons.terrain,
      title: 'Benvenuto in TrailShare',
      description: 'La tua app per registrare e condividere avventure outdoor. Traccia i tuoi percorsi, scopri nuovi sentieri e connettiti con altri escursionisti.',
      color: AppColors.primary,
    ),
    OnboardingSlide(
      icon: Icons.gps_fixed,
      title: 'Traccia i tuoi percorsi',
      description: 'Registra le tue escursioni con GPS preciso. Visualizza distanza, dislivello, velocità e tempo in tempo reale anche in background.',
      color: const Color(0xFF1976D2),
    ),
    OnboardingSlide(
      icon: Icons.explore,
      title: 'Scopri nuovi sentieri',
      description: 'Esplora percorsi pubblicati dalla community. Salva i tuoi preferiti nella wishlist e pianifica la tua prossima avventura.',
      color: const Color(0xFF388E3C),
    ),
    OnboardingSlide(
      icon: Icons.people,
      title: 'Connettiti con altri',
      description: 'Segui amici ed escursionisti, condividi i tuoi percorsi e scala la classifica settimanale. Guadagna XP e sblocca badge!',
      color: const Color(0xFFE64A19),
    ),
    OnboardingSlide(
      icon: Icons.offline_bolt,
      title: 'Funziona anche offline',
      description: 'Scarica le mappe per usarle senza connessione. Il tracking GPS funziona sempre, anche in modalità aereo.',
      color: const Color(0xFF7B1FA2),
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _skipOnboarding() {
    _completeOnboarding();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _skipOnboarding,
                child: Text(
                  'Salta',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 16,
                  ),
                ),
              ),
            ),

            // Page view
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  return _buildSlide(_slides[index]);
                },
              ),
            ),

            // Dots indicator
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (index) => _buildDot(index),
                ),
              ),
            ),

            // Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _nextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _slides[_currentPage].color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _currentPage == _slides.length - 1 ? 'Inizia!' : 'Avanti',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide(OnboardingSlide slide) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon container
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              color: slide.color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              slide.icon,
              size: 80,
              color: slide.color,
            ),
          ),
          const SizedBox(height: 48),

          // Title
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),

          // Description
          Text(
            slide.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    final isActive = index == _currentPage;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive ? _slides[_currentPage].color : Colors.grey[300],
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// Modello per una slide dell'onboarding
class OnboardingSlide {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const OnboardingSlide({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
}

/// Service per gestire lo stato dell'onboarding
class OnboardingService {
  static const String _key = 'onboarding_completed';

  static Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> setCompleted(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
