import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/customer_list_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/import_screen.dart';
import 'screens/login_screen.dart';
import 'screens/outstanding_screen.dart';
import 'screens/received_screen.dart';
import 'services/call_reminders.dart';
import 'services/customer_store.dart';
import 'services/firebase_service.dart';

/// True when Firebase was configured and initialized. False = offline mode:
/// login is skipped and the app works fully on the local database.
/// (Set up Firebase later per README "Firebase setup" to enable login+sync.)
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
    final store = CustomerStore();
    await store.init();
    try {
      await CallReminderService.init();
    } catch (_) {
      // Reminder system must never block app launch.
    }
    CallReminderService.lookupCustomer = store.findByAccountNo;
    runApp(KistBookApp(store: store));
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
            'App khulne me masla aaya:\n\n$error\n\n$stack',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    ),
  );
}

class KistBookApp extends StatelessWidget {
  final CustomerStore store;
  const KistBookApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        title: 'QistBook',
        navigatorKey: appNavigatorKey,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          useMaterial3: true,
        ),
        home: AuthGate(store: store),
      ),
    );
  }
}

/// Routes to Login or the app based on auth state. On sign-in, binds the
/// store to the user's uid and pulls their private cloud data.
class AuthGate extends StatelessWidget {
  final CustomerStore store;
  const AuthGate({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    if (!firebaseReady) {
      // Offline mode: no login, straight into the app.
      return const HomeShell();
    }
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        if (user == null) return const LoginScreen();
        return _SyncedHome(store: store, uid: user.uid);
      },
    );
  }
}

class _SyncedHome extends StatefulWidget {
  final CustomerStore store;
  final String uid;
  const _SyncedHome({required this.store, required this.uid});

  @override
  State<_SyncedHome> createState() => _SyncedHomeState();
}

class _SyncedHomeState extends State<_SyncedHome> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    widget.store.bindUser(widget.uid).whenComplete(() {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Syncing your data…'),
            ],
          ),
        ),
      );
    }
    return const HomeShell();
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = [
    OutstandingScreen(),
    ReceivedScreen(),
    CustomerListScreen(),
    ImportScreen(),
    DashboardScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (!firebaseReady)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  vertical: 6, horizontal: 12),
              color: Colors.orange.shade100,
              child: const Text(
                'Offline mode — Firebase setup baqi hai. Data sirf is phone me save hoga.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ),
          Expanded(child: _pages[_index]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.warning_amber), label: 'Outstanding'),
          NavigationDestination(
              icon: Icon(Icons.task_alt), label: 'Received'),
          NavigationDestination(
              icon: Icon(Icons.people), label: 'Customers'),
          NavigationDestination(
              icon: Icon(Icons.document_scanner), label: 'Import'),
          NavigationDestination(
              icon: Icon(Icons.dashboard), label: 'Dashboard'),
        ],
      ),
    );
  }
}
