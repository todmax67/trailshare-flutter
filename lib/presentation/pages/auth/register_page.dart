import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/auth_service.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();
  
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isAppleLoading = false;
  bool _isPasswordVisible = false;
  bool _appleSignInAvailable = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkAppleSignIn();
  }

  Future<void> _checkAppleSignIn() async {
    if (Platform.isIOS) {
      final available = await _authService.isAppleSignInAvailable();
      setState(() => _appleSignInAvailable = available);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _authService.registerWithEmail(
      _emailController.text,
      _passwordController.text,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      
      if (result.success) {
        // Registrazione riuscita, torna indietro
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Account creato con successo!'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        setState(() => _errorMessage = result.errorMessage);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
      _errorMessage = null;
    });

    final result = await _authService.signInWithGoogle();

    if (mounted) {
      setState(() => _isGoogleLoading = false);
      
      if (result.success) {
        Navigator.pop(context);
      } else if (result.errorMessage != 'Accesso annullato') {
        setState(() => _errorMessage = result.errorMessage);
      }
    }
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _isAppleLoading = true;
      _errorMessage = null;
    });

    final result = await _authService.signInWithApple();

    if (mounted) {
      setState(() => _isAppleLoading = false);
      
      if (result.success) {
        Navigator.pop(context);
      } else if (result.errorMessage != 'Accesso annullato') {
        setState(() => _errorMessage = result.errorMessage);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool anyLoading = _isLoading || _isGoogleLoading || _isAppleLoading;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crea account'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                const Text(
                  'Unisciti a TrailShare',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Crea un account per salvare le tue tracce',
                  style: TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 32),

                // Bottoni Social
                if (_appleSignInAvailable) ...[
                  _SocialButton(
                    onPressed: anyLoading ? null : _signInWithApple,
                    isLoading: _isAppleLoading,
                    icon: Icons.apple,
                    label: 'Continua con Apple',
                    backgroundColor: Colors.black,
                    textColor: Colors.white,
                  ),
                  const SizedBox(height: 12),
                ],

                _SocialButton(
                  onPressed: anyLoading ? null : _signInWithGoogle,
                  isLoading: _isGoogleLoading,
                  icon: null,
                  customIcon: const Text('G', style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  )),
                  label: 'Continua con Google',
                  backgroundColor: Colors.white,
                  textColor: AppColors.textPrimary,
                  borderColor: AppColors.border,
                ),

                const SizedBox(height: 24),

                // Divider
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'oppure registrati con email',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),

                const SizedBox(height: 24),

                // Campo Email
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  enabled: !anyLoading,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Inserisci la tua email';
                    }
                    if (!value.contains('@') || !value.contains('.')) {
                      return 'Email non valida';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 16),

                // Campo Password
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_isPasswordVisible,
                  textInputAction: TextInputAction.next,
                  enabled: !anyLoading,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    border: const OutlineInputBorder(),
                    helperText: 'Minimo 6 caratteri',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() => _isPasswordVisible = !_isPasswordVisible);
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Inserisci una password';
                    }
                    if (value.length < 6) {
                      return 'La password deve avere almeno 6 caratteri';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Conferma Password
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: !_isPasswordVisible,
                  textInputAction: TextInputAction.done,
                  enabled: !anyLoading,
                  onFieldSubmitted: (_) => _register(),
                  decoration: const InputDecoration(
                    labelText: 'Conferma password',
                    prefixIcon: Icon(Icons.lock_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Conferma la password';
                    }
                    if (value != _passwordController.text) {
                      return 'Le password non coincidono';
                    }
                    return null;
                  },
                ),

                // Messaggio errore
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: AppColors.danger),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Bottone Registrazione
                ElevatedButton(
                  onPressed: anyLoading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Crea account', style: TextStyle(fontSize: 16)),
                ),

                const SizedBox(height: 16),

                // Info privacy
                Text(
                  'Creando un account accetti i nostri Termini di servizio e la Privacy Policy',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 24),

                // Link login
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Hai già un account?'),
                    TextButton(
                      onPressed: anyLoading ? null : () => Navigator.pop(context),
                      child: const Text('Accedi'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottone social personalizzato
class _SocialButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final Widget? customIcon;
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final Color? borderColor;

  const _SocialButton({
    required this.onPressed,
    required this.isLoading,
    this.icon,
    this.customIcon,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: borderColor != null 
                ? BorderSide(color: borderColor!) 
                : BorderSide.none,
          ),
        ),
        child: isLoading
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: textColor,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null)
                    Icon(icon, size: 24)
                  else if (customIcon != null)
                    customIcon!,
                  const SizedBox(width: 12),
                  Text(label, style: const TextStyle(fontSize: 16)),
                ],
              ),
      ),
    );
  }
}
