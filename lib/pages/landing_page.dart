import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../state/auth_notifier.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Nav bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.edit_note, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'NoteLetter',
                          style: GoogleFonts.libreBaskerville(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => _showAuthDialog(context, isSignUp: false),
                          child: Text(
                            'Log In',
                            style: TextStyle(color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => _showAuthDialog(context, isSignUp: true),
                          style: FilledButton.styleFrom(backgroundColor: primary),
                          child: const Text('Get Started'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Hero section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: primary.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        'AI-Powered Knowledge Management',
                        style: TextStyle(
                          color: primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Your Knowledge Base,\nAutomatically Curated',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.libreBaskerville(
                        fontSize: 48,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Upload documents, connect cloud storage, and let AI transform your research into personalized newsletters delivered straight to your inbox.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 36),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _showAuthDialog(context, isSignUp: true),
                          style: FilledButton.styleFrom(
                            backgroundColor: primary,
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                          ),
                          icon: const Icon(Icons.rocket_launch_outlined, size: 18),
                          label: const Text('Start for Free', style: TextStyle(fontSize: 16)),
                        ),
                        const SizedBox(width: 16),
                        OutlinedButton.icon(
                          onPressed: () => _showAuthDialog(context, isSignUp: false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                          ),
                          icon: const Icon(Icons.login, size: 18),
                          label: const Text('Log In', style: TextStyle(fontSize: 16)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Features section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
                child: Column(
                  children: [
                    Text(
                      'Everything you need to manage your knowledge',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.libreBaskerville(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      alignment: WrapAlignment.center,
                      children: [
                        _FeatureCard(
                          icon: Icons.upload_file_outlined,
                          title: 'Smart Upload',
                          description: 'Upload PDFs, Word docs, images, and YouTube videos. Our AI processes and indexes everything automatically.',
                          color: primary,
                        ),
                        _FeatureCard(
                          icon: Icons.search_outlined,
                          title: 'Semantic Search',
                          description: 'Find exactly what you\'re looking for with AI-powered vector search across all your documents.',
                          color: primary,
                        ),
                        _FeatureCard(
                          icon: Icons.mail_outline,
                          title: 'Auto Newsletters',
                          description: 'Receive curated digests of your knowledge base, personalized to your interests and schedule.',
                          color: primary,
                        ),
                        _FeatureCard(
                          icon: Icons.cloud_outlined,
                          title: 'Cloud Sync',
                          description: 'Connect Google Drive, OneDrive, Dropbox, and Notion to automatically sync your documents.',
                          color: primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Footer
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
                child: Text(
                  '© 2025 NoteLetter. All rights reserved.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAuthDialog(BuildContext context, {required bool isSignUp}) {
    showDialog(
      context: context,
      builder: (ctx) => _AuthDialog(initialIsSignUp: isSignUp),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: 280,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.libreBaskerville(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthDialog extends StatefulWidget {
  final bool initialIsSignUp;

  const _AuthDialog({required this.initialIsSignUp});

  @override
  State<_AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<_AuthDialog> {
  late bool _isSignUp;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _isSignUp = widget.initialIsSignUp;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? AppColors.primaryDark : AppColors.primary;
    final authNotifier = context.watch<AuthNotifier>();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(32),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              Text(
                _isSignUp ? 'Create your account' : 'Welcome back',
                style: GoogleFonts.libreBaskerville(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isSignUp
                    ? 'Start building your knowledge base today.'
                    : 'Sign in to access your knowledge base.',
                style: TextStyle(
                  color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 28),

              // Email field
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: const Icon(Icons.mail_outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Email is required';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
                onFieldSubmitted: (_) => _submit(context),
              ),
              const SizedBox(height: 16),

              // Password field
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password is required';
                  if (_isSignUp && v.length < 6) return 'Password must be at least 6 characters';
                  return null;
                },
                onFieldSubmitted: (_) => _submit(context),
              ),
              const SizedBox(height: 24),

              // Submit button
              FilledButton(
                onPressed: authNotifier.isLoading ? null : () => _submit(context),
                style: FilledButton.styleFrom(
                  backgroundColor: primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: authNotifier.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_isSignUp ? 'Create Account' : 'Sign In'),
              ),
              const SizedBox(height: 16),

              // Toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isSignUp ? 'Already have an account?' : "Don't have an account?",
                    style: TextStyle(
                      color: isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground,
                      fontSize: 14,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _isSignUp = !_isSignUp),
                    child: Text(
                      _isSignUp ? 'Log In' : 'Sign Up',
                      style: TextStyle(color: primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

    final authNotifier = context.read<AuthNotifier>();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (_isSignUp) {
      await authNotifier.signUp(email, password);
    } else {
      await authNotifier.signIn(email, password);
    }

    if (!mounted) return;

    if (authNotifier.error != null) {
      AppToast.show(context, authNotifier.error!, type: ToastType.error);
      authNotifier.clearError();
    } else {
      Navigator.of(context).pop();
      // GoRouter's refreshListenable will redirect to '/' automatically
    }
  }
}
