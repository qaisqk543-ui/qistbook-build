/// Firebase for Kist Book:
///  * Auth — phone-number OTP login OR email login. Firebase enforces one
///    account per phone number / email automatically.
///  * Firestore — each user's data lives under /users/{uid}/ and is visible
///    ONLY to that user (see firestore.rules). Local sqflite stays as the
///    offline cache; Firestore is the source of truth and syncs across the
///    user's devices.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseService {
  FirebaseService._();
  static final instance = FirebaseService._();

  /// Set true in main() after Firebase.initializeApp() succeeds.
  /// False = offline demo mode: all cloud calls become no-ops and the app
  /// works fully on the local database.
  static bool enabled = false;

  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore db = FirebaseFirestore.instance;

  String? get uid => auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> _customers(String uid) =>
      db.collection('users').doc(uid).collection('customers');

  // ---------------------------------------------------------- phone login

  /// Starts OTP verification. [onCodeSent] receives the verificationId that
  /// [confirmOtp] needs. Phone numbers must be in E.164 format, e.g. +923001234567.
  Future<void> sendOtp(
    String phone, {
    required void Function(String verificationId) onCodeSent,
    required void Function(String message) onError,
    void Function()? onAutoVerified,
  }) async {
    await auth.verifyPhoneNumber(
      phoneNumber: phone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential cred) async {
        await auth.signInWithCredential(cred);
        onAutoVerified?.call();
      },
      verificationFailed: (FirebaseAuthException e) =>
          onError(e.message ?? 'Phone verification failed.'),
      codeSent: (String verificationId, int? _) =>
          onCodeSent(verificationId),
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<UserCredential> confirmOtp(
      String verificationId, String smsCode) {
    final cred = PhoneAuthProvider.credential(
        verificationId: verificationId, smsCode: smsCode);
    return auth.signInWithCredential(cred);
  }

  // ---------------------------------------------------------- email login

  Future<UserCredential> signInEmail(String email, String password) =>
      auth.signInWithEmailAndPassword(
          email: email.trim(), password: password);

  Future<UserCredential> signUpEmail(String email, String password) =>
      auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);

  Future<void> signOut() => auth.signOut();

  // ---------------------------------------------------------- cloud sync

  Future<void> pushCustomer(
      String uid, String accountNo, Map<String, dynamic> data) {
    return _customers(uid).doc(accountNo).set(data);
  }

  Future<List<Map<String, dynamic>>> pullCustomers(String uid) async {
    final snap = await _customers(uid).get();
    return snap.docs.map((d) => d.data()).toList();
  }

  Future<void> logImport(String uid, Map<String, dynamic> info) {
    return db
        .collection('users')
        .doc(uid)
        .collection('imports')
        .add({...info, 'at': FieldValue.serverTimestamp()});
  }
}
