/// Login: phone-number OTP or email. One account per phone/email is
/// enforced by Firebase Auth itself. On success the AuthGate in main.dart
/// switches to the app automatically.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/firebase_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  // phone
  final _phoneCtrl = TextEditingController(text: '+92');
  final _otpCtrl = TextEditingController();
  String? _verificationId;
  bool _codeSent = false;

  // email
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _signUpMode = false;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _tabs.dispose();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Login failed.');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------- phone tab

  Widget _phoneTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
              'Apne mobile number par OTP hasil karen.\n'
              'Ek number par sirf ek hi account banega.',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            enabled: !_codeSent,
            decoration: const InputDecoration(
              labelText: 'Mobile number',
              hintText: '+923001234567',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (!_codeSent)
            ElevatedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        await FirebaseService.instance.sendOtp(
                          _phoneCtrl.text.trim(),
                          onCodeSent: (vid) => setState(() {
                            _verificationId = vid;
                            _codeSent = true;
                          }),
                          onError: (m) =>
                              setState(() => _error = m),
                        );
                      }),
              child: const Text('Send OTP'),
            ),
          if (_codeSent) ...[
            TextField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'OTP code',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        await FirebaseService.instance.confirmOtp(
                            _verificationId!, _otpCtrl.text.trim());
                      }),
              child: const Text('Verify & Login'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _codeSent = false;
                _verificationId = null;
              }),
              child: const Text('Change number'),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------- email tab

  Widget _emailTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
              'Email se login ya naya account banayen.\n'
              'Ek email par sirf ek hi account banega.',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password (min 6 characters)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                      if (_signUpMode) {
                        await FirebaseService.instance.signUpEmail(
                            _emailCtrl.text, _passCtrl.text);
                      } else {
                        await FirebaseService.instance.signInEmail(
                            _emailCtrl.text, _passCtrl.text);
                      }
                    }),
            child: Text(_signUpMode ? 'Create account' : 'Login'),
          ),
          TextButton(
            onPressed: () =>
                setState(() => _signUpMode = !_signUpMode),
            child: Text(_signUpMode
                ? 'Already have an account? Login'
                : 'New here? Create account'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kist Book — Login'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.phone), text: 'Mobile'),
            Tab(icon: Icon(Icons.email), text: 'Email'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.red.shade50,
              child: Text(_error!,
                  style: const TextStyle(color: Colors.red)),
            ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_phoneTab(), _emailTab()],
            ),
          ),
        ],
      ),
    );
  }
}
