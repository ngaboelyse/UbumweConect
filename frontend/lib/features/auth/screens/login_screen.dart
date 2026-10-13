import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../app/theme/app_colors.dart';
import '../../../firebase_options.dart' as fb_opts;
import '../providers/auth_provider.dart';

const Color _brand = Color(0xFF0F766E); // deep teal
const Color _brandLight = Color(0xFF14B8A6);
const Color _brandDark = Color(0xFF0B4F4A);
const Color _fieldFill = Color(0xFFF4F7FA);
const Color _fieldBorder = Color(0xFFE2E8F0);

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ───────────────────────── Auth logic (unchanged) ─────────────────────────

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).login(
            _emailController.text.trim(),
            _passwordController.text,
          );
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    if (!fb_opts.isFirebaseWebConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google sign-in is not configured yet. Fill in lib/firebase_options.dart with your Firebase web config.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final googleSignIn = GoogleSignIn(
        clientId: fb_opts.googleWebClientId.isNotEmpty &&
                !fb_opts.googleWebClientId.startsWith('PASTE_')
            ? fb_opts.googleWebClientId
            : null,
      );
      final account = await googleSignIn.signIn();
      if (account == null) return;

      final auth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final firebaseToken = await userCredential.user?.getIdToken() ?? '';

      await ref
          .read(authNotifierProvider.notifier)
          .loginWithFirebase(firebaseToken);
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google sign-in failed: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ───────────────────────────── Decoration helpers ─────────────────────────

  Widget _circle(double size, Color color,
      {double? top, double? left, double? right, double? bottom}) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
          color: AppColors.textSecondary, fontFamily: 'Poppins', fontSize: 14),
      floatingLabelStyle: const TextStyle(
          color: _brand, fontFamily: 'Poppins', fontWeight: FontWeight.w600),
      prefixIcon: Icon(icon, color: AppColors.textSecondary),
      suffixIcon: suffix,
      filled: true,
      fillColor: _fieldFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: _border(_fieldBorder),
      enabledBorder: _border(_fieldBorder),
      focusedBorder: _border(_brand, width: 1.6),
      errorBorder: _border(AppColors.error),
      focusedErrorBorder: _border(AppColors.error, width: 1.6),
    );
  }

  Widget _logo() {
    return Container(
      width: 160,
      height: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Image.asset(
        'assets/images/ubumwe.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
      ),
    );
  }

  // ───────────────────────────── Left brand panel (wide) ────────────────────

  Widget _featureRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0x26FFFFFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _langChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x26FFFFFF),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0x40FFFFFF)),
      ),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontFamily: 'Poppins', fontSize: 12)),
    );
  }

  Widget _brandPanel() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_brandDark, _brand, _brandLight],
        ),
      ),
      child: Stack(
        children: [
          _circle(320, const Color(0x14FFFFFF), top: -100, right: -100),
          _circle(220, const Color(0x14FFFFFF), bottom: -60, left: -60),
          _circle(90, const Color(0x1AFFFFFF), bottom: 140, right: 60),
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(48),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _logo(),
                        const SizedBox(height: 36),
                        const Text(
                          'Speak your language.\nConnect with everyone.',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 32,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Ubumwe Connect helps people understand each other, '
                          'wherever they are.',
                          style: TextStyle(
                            color: Color(0xDDFFFFFF),
                            fontFamily: 'Poppins',
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 32),
                        _featureRow(Icons.translate, 'Instant translation',
                            'Understand messages in your own language.'),
                        _featureRow(Icons.chat_bubble_outline,
                            'Easy conversations', 'Chat naturally, no barriers.'),
                        _featureRow(Icons.groups_outlined, 'One community',
                            'Bring people together across languages.'),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _langChip('Kinyarwanda'),
                            _langChip('English'),
                            _langChip('Français'),
                            _langChip('Kiswahili'),
                            _langChip('Español'),
                            _langChip('العربية'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────── Form side ──────────────────────────────────

  Widget _formCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _fieldBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: _fieldDecoration(
                  label: 'Email Address', icon: Icons.email_outlined),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Email is required';
                if (!v.contains('@')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _login(),
              decoration: _fieldDecoration(
                label: 'Password',
                icon: Icons.lock_outline,
                suffix: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Password is required';
                if (v.length < 8) return 'Password must be at least 8 characters';
                return null;
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: _brand),
                onPressed: () => context.push('/forgot-password'),
                child: const Text('Forgot Password?',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontFamily: 'Poppins')),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins'),
                ),
                onPressed: _isLoading ? null : _login,
                child: _isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Text('Sign In'),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: const [
                Expanded(child: Divider(color: _fieldBorder, height: 1)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Text('OR',
                      style: TextStyle(
                          color: AppColors.textHint,
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                ),
                Expanded(child: Divider(color: _fieldBorder, height: 1)),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: _fieldBorder),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Poppins'),
                ),
                onPressed: _isLoading ? null : _loginWithGoogle,
                icon: const Text('G',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDB4437))),
                label: const Text('Continue with Google'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formSide({required bool showLogo}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFDDF4F0), Color(0xFFF3FAF9), Color(0xFFF8FAFF)],
        ),
      ),
      child: Stack(
        children: [
          _circle(260, const Color(0x1A14B8A6), top: -90, right: -80),
          _circle(180, const Color(0x140F766E), bottom: -50, left: -60),
          _circle(70, const Color(0x1A14B8A6), top: 220, left: 24),
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showLogo) ...[
                          Center(child: _logo()),
                          const SizedBox(height: 28),
                        ],
                        const Text(
                          'Welcome Back! 👋',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Sign in to continue translating and connecting',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        const SizedBox(height: 28),
                        _formCard(),
                        const SizedBox(height: 24),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text("Don't have an account? ",
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontFamily: 'Poppins')),
                            TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: _brand,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                minimumSize: const Size(0, 36),
                              ),
                              onPressed: () => context.push('/register'),
                              child: const Text('Register',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'Poppins')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────── Build ──────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: isWide
          ? Row(
              children: [
                Expanded(flex: 5, child: _brandPanel()),
                Expanded(flex: 4, child: _formSide(showLogo: false)),
              ],
            )
          : _formSide(showLogo: true),
    );
  }
}