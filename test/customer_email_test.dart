import 'package:flutter_test/flutter_test.dart';
import 'package:kistbook/models/customer.dart';

void main() {
  test('customer email toMap/fromMap round-trip (v1.0.37)', () {
    final c = Customer(
      accountNo: '003112',
      name: 'M Razaq',
      cell: '03269156127',
      email: 'razaq@example.com',
    );
    final back = Customer.fromMap(c.toMap());
    expect(back.email, 'razaq@example.com');
    expect(back.cell, '03269156127');
  });

  test('purani data file (email key nahi) bhi khulti hai', () {
    final old = Customer(accountNo: '003112', name: 'M Razaq').toMap()
      ..remove('email');
    final back = Customer.fromMap(old);
    expect(back.email, '');
  });
}
