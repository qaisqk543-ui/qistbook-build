/// Local app user (login / signup, on-device).
/// Har user ka data alag database file me hota hai: qistbook_<uid>.db
library;

class AppUser {
  final String id; // uuid
  final String name;
  final String email;
  final String phone;
  final String passwordHash; // SHA-256
  final String photoPath; // local file path, empty = none
  final String createdAt; // ISO

  AppUser({
    required this.id,
    this.name = '',
    this.email = '',
    this.phone = '',
    this.passwordHash = '',
    this.photoPath = '',
    this.createdAt = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'passwordHash': passwordHash,
        'photoPath': photoPath,
        'createdAt': createdAt,
      };

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        email: (m['email'] ?? '').toString(),
        phone: (m['phone'] ?? '').toString(),
        passwordHash: (m['passwordHash'] ?? '').toString(),
        photoPath: (m['photoPath'] ?? '').toString(),
        createdAt: (m['createdAt'] ?? '').toString(),
      );

  AppUser copyWith({
    String? name,
    String? email,
    String? phone,
    String? passwordHash,
    String? photoPath,
  }) =>
      AppUser(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        passwordHash: passwordHash ?? this.passwordHash,
        photoPath: photoPath ?? this.photoPath,
        createdAt: createdAt,
      );

  /// Login identifier: email ya phone (jo bhi diya ho).
  String get identifier => email.isNotEmpty ? email : phone;
}
