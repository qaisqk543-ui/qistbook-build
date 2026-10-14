import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kistbook/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('qb_auth_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('signup +92 format, login 03 format — purana contradiction bug',
      () async {
    final auth = AuthService();
    await auth.init();
    final s = await auth.signup(
      name: 'Qais',
      email: '',
      phone: '+92 314 4668065',
      password: 'pass1234',
      confirm: 'pass1234',
    );
    expect(s.ok, isTrue, reason: s.error ?? '');
    await auth.logout();

    // Login dusre format me — v1.0.35 me "registered nahi hai" aata tha.
    final l = await auth.login('03144668065', 'pass1234');
    expect(l.ok, isTrue, reason: l.error ?? '');

    // Aur ulta: 03 se signup wala +92 se login.
    await auth.logout();
    final l2 = await auth.login('923144668065', 'pass1234');
    expect(l2.ok, isTrue, reason: l2.error ?? '');
  });

  test('signup duplicate dusre phone format me bhi pakra jaye', () async {
    final auth = AuthService();
    await auth.init();
    final s = await auth.signup(
      name: 'Qais',
      email: '',
      phone: '03144668065',
      password: 'pass1234',
      confirm: 'pass1234',
    );
    expect(s.ok, isTrue, reason: s.error ?? '');
    final dup = await auth.signup(
      name: 'Dosra',
      email: '',
      phone: '+923144668065',
      password: 'pass1234',
      confirm: 'pass1234',
    );
    expect(dup.ok, isFalse);
    expect(dup.error, contains('istemal'));
  });

  test('email case-insensitive login + ghalat email par hint', () async {
    final auth = AuthService();
    await auth.init();
    final s = await auth.signup(
      name: 'Qais',
      email: 'QaisQK543@Gmail.com',
      phone: '',
      password: 'pass1234',
      confirm: 'pass1234',
    );
    expect(s.ok, isTrue, reason: s.error ?? '');
    await auth.logout();
    final l = await auth.login('qaisqk543@gmail.com', 'pass1234');
    expect(l.ok, isTrue, reason: l.error ?? '');
    await auth.logout();
    // Ghalat email: digits-wala email kisi phone-less user se galat
    // match nahi hona chahiye, aur error me masked hint aana chahiye.
    final bad = await auth.login('unknown999@mail.com', 'pass1234');
    expect(bad.ok, isFalse);
    expect(bad.error, contains('registered nahi'));
    expect(bad.error, contains('***'));
  });
}
