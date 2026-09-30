/// Local login / signup / forgot-password, fully on-device.
/// Users live in a JSON file (app_users.json). Har user ka apna data
/// alag file me hota hai: qistbook_<uid>.json
/// SQLite se hata diya — kuch phones par openDatabase atak jata tha.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import 'subscription_service.dart';

class AuthResult {
  final AppUser? user;
  final String? error; // Roman Urdu message
  const AuthResult.ok(this.user) : error = null;
  const AuthResult.fail(this.error) : user = null;
  bool get ok => user != null;
}

class AuthService {
  static const _sessionKey = 'session_uid';

  final List<AppUser> _users = [];
  String? _sessionUid;
  AppUser? _currentUser;

  AppUser? get currentUser => _currentUser;

  /// Pehla user (auto-login ke liye).
  AppUser? get firstUser => _users.isEmpty ? null : _users.first;

  Future<File> _usersFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'app_users.json'));
  }

  Future<void> _loadUsers() async {
    _users.clear();
    try {
      final file = await _usersFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content) as List;
        for (final m in data) {
          try {
            _users.add(AppUser.fromMap(m as Map<String, dynamic>));
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> _saveUsers() async {
    try {
      final file = await _usersFile();
      final data = _users.map((u) => u.toMap()).toList();
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<void> init() async {
    await _loadUsers();
    final prefs = await SharedPreferences.getInstance();
    _sessionUid = prefs.getString(_sessionKey);
    if (_sessionUid != null) {
      _currentUser = _findById(_sessionUid!);
      if (_currentUser == null) {
        _sessionUid = null;
        await prefs.remove(_sessionKey);
      }
    }
  }

  String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt::$password')).toString();

  String _uuid() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final h =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<void> _save(AppUser u) async {
    final i = _users.indexWhere((e) => e.id == u.id);
    if (i >= 0) {
      _users[i] = u;
    } else {
      _users.add(u);
    }
    await _saveUsers();
  }

  AppUser? _findById(String id) {
    for (final u in _users) {
      if (u.id == id) return u;
    }
    return null;
  }

  Future<AppUser?> findByIdentifier(String identifier) async {
    final key = identifier.trim().toLowerCase();
    for (final u in _users) {
      if (u.email.trim().toLowerCase() == key ||
          u.phone.replaceAll(RegExp(r'\D'), '') ==
              key.replaceAll(RegExp(r'\D'), '')) {
        return u;
      }
    }
    return null;
  }

  bool get hasAnyUser => _hasAnyUserCached;
  bool _hasAnyUserCached = false;

  Future<bool> checkHasAnyUser() async {
    _hasAnyUserCached = _users.isNotEmpty;
    return _hasAnyUserCached;
  }

  /// Legacy (v1.0.7 tak) — ab JSON hai, purana SQLite data migrate nahi hota.
  Future<bool> legacyDbHasData() async {
    return false;
  }

  /// Legacy — ab kuch nahi karna.
  Future<void> adoptLegacyDb(String uid) async {}

  static String userDbName(String uid) => 'qistbook_$uid.db';

  // ------------------------------------------------------------ validation

  static bool validEmail(String e) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e.trim());

  static bool validPhone(String ph) {
    final d = ph.replaceAll(RegExp(r'\D'), '');
    return d.length >= 10 && d.length <= 13;
  }

  // ---------------------------------------------------------------- signup

  Future<AuthResult> signup({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String confirm,
  }) async {
    name = name.trim();
    email = email.trim();
    phone = phone.trim();
    if (name.isEmpty) {
      return const AuthResult.fail('Apna naam likhen');
    }
    if (email.isEmpty && phone.isEmpty) {
      return const AuthResult.fail(
          'Email ya phone number — ek zaroor likhen');
    }
    if (email.isNotEmpty && !validEmail(email)) {
      return const AuthResult.fail('Email sahi nahi lag rahi');
    }
    if (phone.isNotEmpty && !validPhone(phone)) {
      return const AuthResult.fail('Phone number sahi nahi lag raha');
    }
    if (password.length < 4) {
      return const AuthResult.fail(
          'Password kam se kam 4 harf ka ho');
    }
    if (password != confirm) {
      return const AuthResult.fail(
          'Dono password ek jaise nahi hain');
    }
    if (email.isNotEmpty &&
        await findByIdentifier(email) != null) {
      return const AuthResult.fail(
          'Ye email pehle se istemal ho rahi hai');
    }
    if (phone.isNotEmpty &&
        await findByIdentifier(phone) != null) {
      return const AuthResult.fail(
          'Ye number pehle se istemal ho raha hai');
    }
    final id = _uuid();
    final user = AppUser(
      id: id,
      name: name,
      email: email,
      phone: phone,
      passwordHash: _hash(password, id),
      createdAt: DateTime.now().toIso8601String(),
    );
    await _save(user);
    _hasAnyUserCached = true;
    await _setSession(user);
    // Naye user ko 30 din ka free trial (full access).
    await SubscriptionService.startTrial(id);
    return AuthResult.ok(user);
  }

  // ----------------------------------------------------------------- login

  Future<AuthResult> login(String identifier, String password) async {
    final user = await findByIdentifier(identifier);
    if (user == null) {
      return const AuthResult.fail(
          'Ye email/number registered nahi hai');
    }
    if (user.passwordHash != _hash(password, user.id)) {
      return const AuthResult.fail('Password ghalat hai');
    }
    await _setSession(user);
    return AuthResult.ok(user);
  }

  // -------------------------------------------------------- forgot password

  Future<AuthResult> resetPassword(
      String identifier, String password, String confirm) async {
    final user = await findByIdentifier(identifier);
    if (user == null) {
      return const AuthResult.fail(
          'Ye email/number registered nahi hai');
    }
    if (password.length < 4) {
      return const AuthResult.fail(
          'Password kam se kam 4 harf ka ho');
    }
    if (password != confirm) {
      return const AuthResult.fail(
          'Dono password ek jaise nahi hain');
    }
    final updated =
        user.copyWith(passwordHash: _hash(password, user.id));
    await _save(updated);
    if (_currentUser?.id == updated.id) _currentUser = updated;
    return AuthResult.ok(updated);
  }

  Future<void> updateProfile(AppUser updated) async {
    await _save(updated);
    if (_currentUser?.id == updated.id) _currentUser = updated;
  }

  Future<void> _setSession(AppUser user) async {
    _sessionUid = user.id;
    _currentUser = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, user.id);
  }

  Future<void> logout() async {
    _sessionUid = null;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  /// Refresh current user (e.g. after profile edit elsewhere).
  Future<void> reloadCurrent() async {
    if (_sessionUid != null) {
      _currentUser = _findById(_sessionUid!);
    }
  }
}
