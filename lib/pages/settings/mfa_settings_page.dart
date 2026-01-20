import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../config/routes.dart';

/// Minimal MFA settings page (phone/SMS second-factor) compatible with firebase_auth ^5.x
/// Mobile (Android/iOS): full enroll/complete flow implemented.
/// Web: enrollment is NOT supported in this minimal implementation; user is informed.
///
/// Security notes (in-page):
/// - All actions require an authenticated user.
/// - Disabling an enrolled second factor requires reauthentication (password).
/// - No analytics and no persistent local storage beyond Firebase are used.

class MfaSettingsPage extends ConsumerStatefulWidget {
  const MfaSettingsPage({super.key});

  @override
  ConsumerState<MfaSettingsPage> createState() => _MfaSettingsPageState();
}

class _MfaSettingsPageState extends ConsumerState<MfaSettingsPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  final AuthService _authService = AuthService();

  bool _sending = false;
  bool _completing = false;
  String? _verificationId;
  String? _status;
  List<dynamic> _enrolled = []; // MultiFactorInfo objects (use dynamic for flexibility)

  @override
  void initState() {
    super.initState();
    _refreshEnrolled();
  }

  Future<void> _refreshEnrolled() async {
    try {
      final factors = await _authService.getEnrolledSecondFactors();
      setState(() {
        _enrolled = factors;
      });
    } catch (e) {
      setState(() {
        _enrolled = [];
        _status = 'Unable to query enrolled factors';
      });
    }
  }

  Future<void> _sendCode() async {
    if (kIsWeb) {
      setState(() {
        _status = 'Phone MFA enrollment on Web is not supported in this build. Use the mobile app.';
      });
      return;
    }

    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _status = 'Enter phone number (E.164) first');
      return;
    }

    setState(() {
      _sending = true;
      _status = 'Sending verification code...';
    });

    try {
      final verificationId = await _authService.startPhoneEnrollment(phone);
      setState(() {
        _verificationId = verificationId;
        _status = 'Code sent. Enter SMS code to complete enrollment.';
      });
    } catch (e) {
      setState(() => _status = 'Failed to send code: ${e.toString()}');
    } finally {
      setState(() => _sending = false);
    }
  }

  Future<void> _completeEnrollment() async {
    final code = _codeController.text.trim();
    final vid = _verificationId;
    if (vid == null || code.isEmpty) {
      setState(() => _status = 'Please send code and enter the SMS code.');
      return;
    }

    setState(() {
      _completing = true;
      _status = 'Completing enrollment...';
    });

    try {
      final ok = await _authService.completePhoneEnrollment(
        verificationId: vid,
        smsCode: code,
        displayName: 'Phone',
      );
      if (ok) {
        setState(() {
          _status = 'Phone enrolled successfully.';
          _verificationId = null;
          _phoneController.clear();
          _codeController.clear();
        });
        await _refreshEnrolled();
      } else {
        setState(() => _status = 'Enrollment failed.');
      }
    } catch (e) {
      setState(() => _status = 'Enrollment error: ${e.toString()}');
    } finally {
      setState(() => _completing = false);
    }
  }

  Future<void> _disableFactor(String enrollmentId) async {
    // Reauthenticate via password before disenrolling (safety)
    final user = ref.read(authStateProvider).user;
    final email = user?.email;
    if (email == null) {
      setState(() => _status = 'Cannot get email for reauthentication.');
      return;
    }

    final password = await _askPassword();
    if (password == null) return; // cancelled

    final reauthOk = await _authService.reauthenticateWithPassword(email, password);
    if (!reauthOk) {
      setState(() => _status = 'Reauthentication failed. Factor not removed.');
      return;
    }

    try {
      final ok = await _authService.unenrollSecondFactor(enrollmentId);
      if (ok) {
        setState(() => _status = 'Second factor removed.');
        await _refreshEnrolled();
      } else {
        setState(() => _status = 'Failed to remove factor.');
      }
    } catch (e) {
      setState(() => _status = 'Error removing factor: ${e.toString()}');
    }
  }

  Future<String?> _askPassword() async {
    String? pw;
    await showDialog<String?>(
      context: context,
      builder: (ctx) {
        final _c = TextEditingController();
        return AlertDialog(
          title: const Text('Re-enter password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('To disable MFA you must re-enter your password.'),
              TextField(
                controller: _c,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, _c.text), child: const Text('Confirm')),
          ],
        );
      },
    ).then((v) => pw = v);
    return pw;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('MFA Settings')),
        body: const Center(child: Text('You must be signed in to manage MFA.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Multi-Factor Authentication')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'MFA protects your account by requiring a second verification step. '
              'You can enroll a phone to receive SMS verification when required.',
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Enrolled factors:', style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _enrolled.isEmpty
                  ? const Text('No second factors enrolled.')
                  : ListView.builder(
                      itemCount: _enrolled.length,
                      itemBuilder: (ctx, i) {
                        final f = _enrolled[i];
                        final label = (f.displayName ?? (f.uid ?? 'Phone')).toString();
                        final uid = (f.uid ?? '').toString();
                        return Card(
                          child: ListTile(
                            title: Text(label),
                            subtitle: Text('ID: $uid'),
                            trailing: TextButton(
                              onPressed: () async {
                                await _disableFactor(uid);
                              },
                              child: const Text('Disable'),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const Divider(),
            const SizedBox(height: 8),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone (E.164 format, e.g. +1234567890)',
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _sending ? null : _sendCode,
              child: Text(_sending ? 'Sending...' : (kIsWeb ? 'Not available on Web' : 'Send verification code')),
            ),
            if (_verificationId != null) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(labelText: 'SMS code'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _completing ? null : _completeEnrollment,
                child: Text(_completing ? 'Completing...' : 'Complete enrollment'),
              ),
            ],
            const SizedBox(height: 8),
            if (_status != null) Text(_status!),
          ],
        ),
      ),
    );
  }
}
