import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';
import '../../utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../shared/app_state.dart';
import 'consent_screen.dart';

class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isSubmitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final notifier = ref.read(authStateProvider.notifier);

      await notifier.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        username: _usernameController.text.trim(),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authStateProvider, (previous, next) async {
      if (next.user != null) {
        // ✅ Set user ID globally
        currentUserId = next.user!.id;

        // ✅ Show consent ONCE (signup flow)
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => HealthDataConsentPage(fromSignup: true),
          ),
        );

        // ✅ Continue normal onboarding
        Navigator.pushReplacementNamed(context, AppRoutes.gender);
      }

      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!), backgroundColor: Colors.red),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppTheme.lightPeach,
      appBar: AppBar(backgroundColor: AppTheme.lightPeach),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            CustomTextField(
              controller: _usernameController,
              label: 'Username',
              validator: Validators.validateName,
            ),
            CustomTextField(
              controller: _emailController,
              label: 'Email',
              validator: Validators.validateEmail,
            ),
            CustomTextField(
              controller: _passwordController,
              label: 'Password',
              validator: Validators.validatePassword,
            ),
            CustomTextField(
              controller: _confirmPasswordController,
              label: 'Confirm Password',
              validator:
                  (v) => Validators.validateConfirmPassword(
                    v,
                    _passwordController.text,
                  ),
            ),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _handleSignup,
              child: const Text('SIGN UP'),
            ),
          ],
        ),
      ),
    );
  }
}
