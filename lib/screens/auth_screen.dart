/// Local login / signup / forgot-password — sab kuch is phone par.
/// Roman Urdu labels, bara text, premium look.
library;

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class AuthScreen extends StatefulWidget {
  /// Pehli dafa legacy data mila ho to true → signup par note dikhega.
  final bool legacyDataFound;

  /// Login/signup kamyab hone par call hota hai.
  final VoidCallback onDone;

  const AuthScreen({
    super.key,
    required this.onDone,
    this.legacyDataFound = false,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _Mode { login, signup, forgot }

class _AuthScreenState extends State<AuthScreen> {
  _Mode _mode = _Mode.login;
  bool _busy = false;
  String? _error;

  final _nameCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _showPass = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  AuthService get _auth => AuthScope.of(context).auth;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    AuthResult res;
    try {
      switch (_mode) {
        case _Mode.login:
          res = await _auth.login(_idCtrl.text, _passCtrl.text);
        case _Mode.signup:
          res = await _auth.signup(
            name: _nameCtrl.text,
            email: _idCtrl.text.contains('@') ? _idCtrl.text : '',
            phone: _idCtrl.text.contains('@') ? '' : _idCtrl.text,
            password: _passCtrl.text,
            confirm: _confirmCtrl.text,
          );
          if (res.ok && widget.legacyDataFound) {
            // Purana data is user ke naam kar do.
            await _auth.adoptLegacyDb(res.user!.id);
          }
        case _Mode.forgot:
          res = await _auth.resetPassword(
              _idCtrl.text, _passCtrl.text, _confirmCtrl.text);
          if (res.ok && mounted) {
            showAppSnack(
                context, 'Password badal gaya — ab login karen');
            setState(() {
              _mode = _Mode.login;
              _busy = false;
            });
            return;
          }
      }
    } catch (e) {
      res = AuthResult.fail('Kuch ghalat ho gaya: $e');
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.ok) {
      widget.onDone();
    } else {
      setState(() => _error = res.error);
    }
  }

  String get _title {
    switch (_mode) {
      case _Mode.login:
        return 'Login karen';
      case _Mode.signup:
        return 'Naya account banayen';
      case _Mode.forgot:
        return 'Password bhool gaye?';
    }
  }

  String get _buttonLabel {
    switch (_mode) {
      case _Mode.login:
        return 'Login';
      case _Mode.signup:
        return 'Account banao';
      case _Mode.forgot:
        return 'Naya password set karo';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDeep,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.l),
            child: Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded,
                      size: 52, color: AppColors.primary),
                ),
                const SizedBox(height: AppSpace.m),
                const Text(
                  'QistBook',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: AppSpace.s),
                Text(
                  'Apni dukaan ka hisaab, mehfooz aur asaan',
                  style: AppText.body.copyWith(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpace.l),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.l),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(_title, style: AppText.h2),
                        const SizedBox(height: AppSpace.s),
                        if (widget.legacyDataFound &&
                            _mode == _Mode.signup)
                          Container(
                            padding: const EdgeInsets.all(AppSpace.m),
                            margin: const EdgeInsets.only(
                                bottom: AppSpace.m),
                            decoration: BoxDecoration(
                              color: AppColors.tintAmber,
                              borderRadius: BorderRadius.circular(
                                  AppRadius.button),
                            ),
                            child: Text(
                              'Purana data mil gaya hai — account banao taake wo mehfooz rahe.',
                              style: AppText.body.copyWith(fontSize: 16),
                            ),
                          ),
                        if (_mode == _Mode.signup) ...[
                          TextField(
                            controller: _nameCtrl,
                            textCapitalization:
                                TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Apna naam',
                              prefixIcon:
                                  Icon(Icons.person_rounded),
                            ),
                          ),
                          const SizedBox(height: AppSpace.m),
                        ],
                        TextField(
                          controller: _idCtrl,
                          keyboardType: _mode == _Mode.signup
                              ? TextInputType.text
                              : TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: _mode == _Mode.signup
                                ? 'Email ya phone number'
                                : 'Email ya phone number',
                            hintText: _mode == _Mode.signup
                                ? 'Ek likhna zaroori hai'
                                : null,
                            prefixIcon:
                                const Icon(Icons.contact_mail_rounded),
                          ),
                        ),
                        const SizedBox(height: AppSpace.m),
                        TextField(
                          controller: _passCtrl,
                          obscureText: !_showPass,
                          decoration: InputDecoration(
                            labelText: _mode == _Mode.forgot
                                ? 'Naya password'
                                : 'Password',
                            prefixIcon:
                                const Icon(Icons.lock_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(_showPass
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded),
                              onPressed: () => setState(
                                  () => _showPass = !_showPass),
                            ),
                          ),
                        ),
                        if (_mode != _Mode.login) ...[
                          const SizedBox(height: AppSpace.m),
                          TextField(
                            controller: _confirmCtrl,
                            obscureText: !_showPass,
                            decoration: const InputDecoration(
                              labelText: 'Password dobara likhen',
                              prefixIcon:
                                  Icon(Icons.lock_outline_rounded),
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: AppSpace.m),
                          Container(
                            padding:
                                const EdgeInsets.all(AppSpace.m),
                            decoration: BoxDecoration(
                              color: AppColors.tintRose,
                              borderRadius: BorderRadius.circular(
                                  AppRadius.button),
                            ),
                            child: Text(_error!,
                                style: AppText.body.copyWith(
                                    color: AppColors.dueRed,
                                    fontSize: 16)),
                          ),
                        ],
                        const SizedBox(height: AppSpace.l),
                        ElevatedButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 26,
                                  height: 26,
                                  child:
                                      CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 3,
                                  ),
                                )
                              : Text(_buttonLabel),
                        ),
                        const SizedBox(height: AppSpace.s),
                        if (_mode == _Mode.login) ...[
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _mode = _Mode.forgot;
                                      _error = null;
                                    }),
                            child: const Text(
                                'Password bhool gaye?'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _mode = _Mode.signup;
                                      _error = null;
                                    }),
                            child: const Text(
                                'Naya account banao'),
                          ),
                        ] else
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _mode = _Mode.login;
                                      _error = null;
                                    }),
                            child: const Text(
                                'Pehle se account hai? Login karen'),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.m),
                Text(
                  'Data sirf is phone me mehfooz rehta hai',
                  style:
                      AppText.caption.copyWith(color: Colors.white60),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Provides AuthService down the tree.
class AuthScope extends InheritedWidget {
  final AuthService auth;
  const AuthScope({super.key, required this.auth, required super.child});

  static AuthScope of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(s != null, 'AuthScope not found');
    return s!;
  }

  @override
  bool updateShouldNotify(AuthScope old) => auth != old.auth;
}
