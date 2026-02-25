import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/extensions/l10n_extension.dart';
import '../../../core/services/auth_service.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
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
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _authService.signInWithEmail(
      _emailController.text,
      _passwordController.text,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      
      if (!result.success) {
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
      
      if (!result.success && result.errorMessage != 'Accesso annullato') {
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
      
      if (!result.success && result.errorMessage != 'Accesso annullato') {
        setState(() => _errorMessage = result.errorMessage);
      }
    }
  }

  void _showResetPasswordDialog() {
    final emailController = TextEditingController(text: _emailController.text);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.resetPassword),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.enterEmailForReset),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: context.l10n.emailLabel,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final result = await _authService.resetPassword(emailController.text);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      result.success 
                          ? context.l10n.resetEmailSent 
                          : result.errorMessage ?? context.l10n.genericError,
                    ),
                    backgroundColor: result.success ? AppColors.success : AppColors.danger,
                  ),
                );
              }
            },
            child: Text(context.l10n.sendAction),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool anyLoading = _isLoading || _isGoogleLoading || _isAppleLoading;
    
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                
                // Logo e titolo
                Icon(Icons.terrain, size: 80, color: AppColors.primary),
                const SizedBox(height: 16),
                Text(
                  'TrailShare',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.trackYourAdventures,
                  style: const TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 40),

                // Bottoni Social
                if (_appleSignInAvailable) ...[
                  _SocialButton(
                    onPressed: anyLoading ? null : _signInWithApple,
                    isLoading: _isAppleLoading,
                    icon: Icons.apple,
                    label: context.l10n.continueWithApple,
                    backgroundColor: Colors.black,
                    textColor: Colors.white,
                  ),
                  const SizedBox(height: 12),
                ],

                _SocialButton(
                  onPressed: anyLoading ? null : _signInWithGoogle,
                  isLoading: _isGoogleLoading,
                  icon: null,
                  customIcon: _buildGoogleIcon(),
                  label: context.l10n.continueWithGoogle,
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
                        context.l10n.orDivider,
                        style: TextStyle(color: AppColors.textMuted),
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
                  decoration: InputDecoration(
                    labelText: context.l10n.emailLabel,
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return context.l10n.enterYourEmail;
                    }
                    if (!value.contains('@')) {
                      return context.l10n.invalidEmail;
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 16),

                // Campo Password
                TextFormField(
                  controller: _passwordController,
                  obscureText: !_isPasswordVisible,
                  textInputAction: TextInputAction.done,
                  enabled: !anyLoading,
                  onFieldSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    labelText: context.l10n.passwordLabel,
                    prefixIcon: const Icon(Icons.lock_outlined),
                    border: const OutlineInputBorder(),
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
                      return context.l10n.enterPassword;
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 8),

                // Link recupero password
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: anyLoading ? null : _showResetPasswordDialog,
                    child: Text(context.l10n.forgotPassword),
                  ),
                ),

                // Messaggio errore
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
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

                // Bottone Login
                ElevatedButton(
                  onPressed: anyLoading ? null : _login,
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
                      : Text(context.l10n.loginAction, style: const TextStyle(fontSize: 16)),
                ),

                const SizedBox(height: 24),

                // Link registrazione
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(context.l10n.noAccountQuestion),
                    TextButton(
                      onPressed: anyLoading 
                          ? null 
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const RegisterPage()),
                              );
                            },
                      child: Text(context.l10n.registerAction),
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

  Widget _buildGoogleIcon() {
    return Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: NetworkImage(
            'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
          ),
        ),
      ),
      child: const Text('G', style: TextStyle(
        color: Colors.red,
        fontWeight: FontWeight.bold,
        fontSize: 16,
      )),
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
