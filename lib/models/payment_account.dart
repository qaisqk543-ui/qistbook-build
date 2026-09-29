/// QistBook ke payment accounts: JazzCash / Easypaisa / Bank.
/// Ye numbers auto-sent SMS aur WhatsApp reminders me share hote hain.

class PaymentAccount {
  String id;
  String type; // JazzCash | Easypaisa | Bank
  String title; // account title / naam
  String number; // account number / mobile number

  PaymentAccount({
    required this.id,
    this.type = 'JazzCash',
    this.title = '',
    this.number = '',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'title': title,
        'number': number,
      };

  factory PaymentAccount.fromMap(Map<String, dynamic> m) =>
      PaymentAccount(
        id: (m['id'] ?? '').toString(),
        type: (m['type'] ?? 'JazzCash').toString(),
        title: (m['title'] ?? '').toString(),
        number: (m['number'] ?? '').toString(),
      );
}
