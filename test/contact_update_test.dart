import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kistbook/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('qb_contact_test');
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

  test('Profile se number badlo — login naye format se bhi, purane se nahi',
      () async {
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
    final uid = auth.currentUser!.id;

    // Number change (03 -> doosra number, +92 format me likha).
    final err = await auth.updateContact(uid, phone: '+92 300 1234567');
    expect(err, isNull);
    await auth.logout();

    // Purana number ab nahi chalega, naya chalega (dono formats me).
    final oldLogin = await auth.login('03144668065', 'pass1234');
    expect(oldLogin.ok, isFalse);
    final newLogin = await auth.login('03001234567', 'pass1234');
    expect(newLogin.ok, isTrue, reason: newLogin.error ?? '');
  });

  test('Email add karo — phir email se login; doosre account ka email mana',
      () async {
    final auth = AuthService();
    await auth.init();
    final s1 = await auth.signup(
      name: 'Ek',
      email: '',
      phone: '03111111111',
      password: 'pass1234',
      confirm: 'pass1234',
    );
    expect(s1.ok, isTrue, reason: s1.error ?? '');
    final uid1 = auth.currentUser!.id;
    final err = await auth.updateContact(uid1, email: 'Qais@Example.com');
    expect(err, isNull);
    await auth.logout();
    final byEmail = await auth.login('qais@example.com', 'pass1234');
    expect(byEmail.ok, isTrue, reason: byEmail.error ?? '');
    await auth.logout();

    // Doosra account wahi email lene ki koshish kare to roka jaye.
    final s2 = await auth.signup(
      name: 'Do',
      email: '',
      phone: '03222222222',
      password: 'pass1234',
      confirm: 'pass1234',
    );
    expect(s2.ok, isTrue, reason: s2.error ?? '');
    final clash =
        await auth.updateContact(auth.currentUser!.id, email: 'qais@example.com');
    expect(clash, isNotNull);
  });
}
