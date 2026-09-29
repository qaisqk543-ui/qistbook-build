// Basic smoke test for QistBook: verifies the reminder message builder
// and WhatsApp number normalization work as expected.

import 'package:flutter_test/flutter_test.dart';
import 'package:kistbook/models/customer.dart';
import 'package:kistbook/services/reminders.dart';

void main() {
  test('toWhatsAppNumber converts 03XXXXXXXXX to 92XXXXXXXXX', () {
    expect(toWhatsAppNumber('03216512528'), '923216512528');
    expect(toWhatsAppNumber('923216512528'), '923216512528');
    expect(toWhatsAppNumber(''), '');
  });

  test('dueReminderMessage mentions the customer name', () {
    final c = Customer(
      accountNo: '003077',
      name: 'Naeem Akhtar',
      monthlyInstallment: 46250,
      currentDue: 92500,
    );
    expect(dueReminderMessage(c), contains('Naeem Akhtar'));
  });
}
