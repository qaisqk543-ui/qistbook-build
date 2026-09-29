/// QistBook — local login + per-user data, Home-first navigation.
library;

import 'dart:async';

import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/user.dart';
import 'screens/app_lock_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/customer_list_screen.dart';
import 'screens/home_screen.dart';
import 'screens/outstanding_screen.dart';
import 'screens/received_screen.dart';
import 'screens/voucher_screen.dart';
import 'services/access_control.dart';
import 'services/app_lock_service.dart';
import 'services/app_settings.dart';
import 'services/auth_service.dart';
import 'services/call_reminders.dart';
import 'services/customer_store.dart';
import 'services/error_log.dart';
import 'services/firebase_service.dart';
import 'services/subscription_service.dart';
import 'theme/app_theme.dart';

/// True when Firebase was configured and initialized. False = offline mode:
/// the app works fully on the local database (ab local login ke sath).
bool firebaseReady = false;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Diagnostic: never die silently — show the crash reason on screen
  // instead of just closing, so it can be photographed and fixed.
  FlutterError.onError = (FlutterErrorDetails details) {
    _showCrashScreen(details.exception, details.stack);
  };
  runZonedGuarded(() async {
    try {
      // Reads google-services.json (Android) / GoogleService-Info.plist (iOS).
      // See README "Firebase setup".
      await Firebase.initializeApp();
      firebaseReady = true;
      FirebaseService.enabled = true;
    } catch (_) {
      firebaseReady = false; // no Firebase config yet → offline mode
    }
    final settings = AppSettings();
    await settings.init();
    final auth = AuthService();
    await auth.init();
    try {
      await CallReminderService.init();
    } catch (_) {
      // Reminder system must never block app launch.
    }
    runApp(KistBookApp(settings: settings, auth: auth));
    await CallReminderService.handleLaunchFromNotification();
  }, (Object error, StackTrace stack) {
    _showCrashScreen(error, stack);
  });
}

/// Shows the crash reason on screen so it can be photographed/reported
/// instead of the app just closing.
void _showCrashScreen(Object error, StackTrace? stack) {
  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('QistBook — Error')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            'QistBook v$kAppVersion — Error\n\nApp khulne me masla aaya:\n\n$error\n\n$stack',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    ),
  );
}

/// App root (stateful: session check → store open → providers).
///
/// IMPORTANT: CustomerStore + AccessControl providers MaterialApp (aur uske
/// Navigator) se UPAR lagaye gaye hain — taake Navigator.push se khulne wali
/// har screen (CustomerDetail, VoucherDetail waghera) ko store mil sake.
/// Pehle providers Navigator ke neeche the → pushed routes par
/// "Provider<CustomerStore> not found" crash hota tha (v1.0.9 bug).
class KistBookApp extends StatefulWidget {
  final AppSettings settings;
  final AuthService auth;
  const KistBookApp({super.key, required this.settings, required this.auth});

  @override
  State<KistBookApp> createState() => _KistBookAppState();
}

class _KistBookAppState extends State<KistBookApp> {
  bool _loading = true;
  bool _legacyFound = false;
  CustomerStore? _store;
  AccessControl? _access;
  String? _openError;
  AppUser? _pendingPinUser;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final hasAny = await widget.auth.checkHasAnyUser();
    var legacy = false;
    if (!hasAny) {
      // Pehli dafa: purana (v1.0.7) single-DB data hai to adopt karenge.
      legacy = await widget.auth.legacyDbHasData();
    }
    final user = widget.auth.currentUser;
    if (user != null) {
      await _openStore(user);
    } else if (mounted) {
      setState(() {
        _loading = false;
        _legacyFound = legacy;
      });
    }
  }

  Future<void> _openStore(AppUser user) async {
    try {
      final store = CustomerStore();
      await store.init(user.id);
      CallReminderService.lookupCustomer = store.findByAccountNo;
      if (firebaseReady) {
        await store.bindUser(user.id);
      }
      // App Lock: PIN laga ho to pehle PIN mango (login ke baad).
      final locked = await AppLockService.isEnabled(user.id);
      // Subscription read-only state (owner kabhi read-only nahi).
      final access = AccessControl();
      await access.init(user.id);
      await SubscriptionService.ensureExpiryReminder(user.id);
      if (mounted) {
        setState(() {
          _store = store;
          _access = access;
          _pendingPinUser = locked ? user : null;
          _loading = false;
          _openError = null;
        });
      }
    } catch (e) {
      ErrorLog.log('Startup', e);
      if (mounted) {
        setState(() {
          _loading = false;
          _openError =
              'Data khulne me masla aaya. Koi baat nahi — dobara try karein.';
        });
      }
    }
  }

  void _onAuthDone() {
    final user = widget.auth.currentUser;
    if (user == null) return;
    setState(() {
      _loading = true;
      _store = null;
    });
    _openStore(user);
  }

  void _onLogout() {
    // Providers hatane se pehle pushed routes saaf karo (wo store ko
    // watch karti hain) — warna rebuild par ProviderNotFound.
    appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    setState(() {
      _store = null;
      _access = null;
      _pendingPinUser = null;
      _loading = false;
      _openError = null;
    });
  }

  /// PIN bhool gaye → logout karke password se dobara login (yehi reset hai).
  Future<void> _onPinForgot() async {
    await widget.auth.logout();
    _onLogout();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.settings,
      child: AuthScope(
        auth: widget.auth,
        child: Builder(
          builder: (context) {
            final s = context.watch<AppSettings>();

            // Kaunsi home screen dikhani hai.
            final Widget home;
            if (_loading) {
              home = const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            } else if (_openError != null) {
              home = _errorHome();
            } else if (_pendingPinUser != null) {
              // App Lock gate: sahi PIN par hi andar.
              final pinUser = _pendingPinUser!;
              home = AppLockScreen(
                uid: pinUser.id,
                mode: PinMode.verify,
                onDone: (ok) {
                  if (ok && mounted) {
                    setState(() => _pendingPinUser = null);
                  }
                },
                onForgot: _onPinForgot,
              );
            } else {
              final store = _store;
              final access = _access;
              home = (store != null && access != null)
                  ? HomeShell(store: store, onLogout: _onLogout)
                  : AuthScreen(
                      onDone: _onAuthDone, legacyDataFound: _legacyFound);
            }

            Widget app = MaterialApp(
              title: 'QistBook',
              navigatorKey: appNavigatorKey,
              theme: appTheme(),
              // Elderly-friendly text scaling (Normal / Bara).
              builder: (context, child) {
                final mq = MediaQuery.of(context);
                return MediaQuery(
                  data:
                      mq.copyWith(textScaler: TextScaler.linear(s.textScale)),
                  child: child!,
                );
              },
              home: home,
            );

            // Store ready + PIN gate clear → providers Navigator se UPAR,
            // taake har pushed route ko CustomerStore/AccessControl mile.
            final store = _store;
            final access = _access;
            if (store != null &&
                access != null &&
                _pendingPinUser == null) {
              app = MultiProvider(
                providers: [
                  ChangeNotifierProvider.value(value: store),
                  ChangeNotifierProvider.value(value: access),
                ],
                child: app,
              );
            }
            return app;
          },
        ),
      ),
    );
  }

  /// Startup error screen (dobara try ka button).
  Widget _errorHome() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 72, color: AppColors.dueRed),
              const SizedBox(height: 16),
              const Text('Kuch garbar hui',
                  style: AppText.h1, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(_openError!,
                  style: AppText.body, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Dobara try karein'),
                onPressed: () {
                  final user = widget.auth.currentUser;
                  setState(() {
                    _loading = true;
                    _openError = null;
                  });
                  if (user != null) {
                    _openStore(user);
                  } else {
                    _boot();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 5 tabs: Home, Outstanding, Voucher, Received, Customers.
/// Import/Dashboard/Profile sirf Home cards se khulte hain.
class HomeShell extends StatefulWidget {
  final CustomerStore store;
  final VoidCallback onLogout;
  const HomeShell({super.key, required this.store, required this.onLogout});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  void _navigate(int i) {
    if (i == -1) {
      // Logout: pushed screens hatao, phir auth screen dikhao.
      Navigator.of(context).popUntil((r) => r.isFirst);
      widget.onLogout();
      return;
    }
    if (i >= 0 && i < 5) setState(() => _index = i);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Har login par monthly rollover check (1st ko dues refresh).
    Future.microtask(() async {
      try {
        final n = await widget.store.maybeRollover();
        // 1st ko rollover chale to local notification bhi bhejo.
        await CallReminderService.notifyRollover(n);
        if (n > 0 && mounted) {
          showAppSnack(
              context, 'Naya mahina: $n customers ki due update ho gayi.');
        }
      } catch (e) {
        ErrorLog.log('Rollover', e);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// App resume par subscription check — expired ho to read-only lag jaye.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      try {
        final access = Provider.of<AccessControl>(context, listen: false);
        access.refresh();
        final uid = access.uid;
        if (uid != null) {
          SubscriptionService.ensureExpiryReminder(uid);
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (!firebaseReady)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              color: Colors.orange.shade100,
              child: const Text(
                'Offline mode — Firebase setup baqi hai. Data sirf is phone me save hoga.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14),
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                HomeScreen(onNavigate: _navigate),
                const OutstandingScreen(),
                const VoucherScreen(),
                const ReceivedScreen(),
                const CustomerListScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.warning_amber_rounded), label: 'Outstanding'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_rounded), label: 'Voucher'),
          NavigationDestination(
              icon: Icon(Icons.task_alt_rounded), label: 'Received'),
          NavigationDestination(
              icon: Icon(Icons.people_rounded), label: 'Customers'),
        ],
      ),
    );
  }
}
