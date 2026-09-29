import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/customer_list_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/import_screen.dart';
import 'screens/login_screen.dart';
import 'screens/outstanding_screen.dart';
import 'services/customer_store.dart';
import 'services/firebase_service.dart';

/// True when Firebase was configured and initialized. False = offline mode:
/// login is skipped and the app works fully on the local database.
/// (Set up Firebase later per README "Firebase setup" to enable login+sync.)
bool firebaseReady = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  runApp(KistBookApp(store: store));
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
