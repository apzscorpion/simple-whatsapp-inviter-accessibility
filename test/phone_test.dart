import 'package:flutter_test/flutter_test.dart';
import 'package:simple_inviter/phone.dart';

void main() {
  test('normalizePhone', () {
    expect(normalizePhone('98765 43210', '91'), '919876543210');
    expect(normalizePhone('09876543210', '91'), '919876543210');
    expect(normalizePhone('+91 98765-43210', '91'), '919876543210');
    expect(normalizePhone('+971 50 123 4567', '91'), '971501234567');
    expect(normalizePhone('00971501234567', '91'), '971501234567');
    expect(normalizePhone('919876543210', '91'), '919876543210');
    expect(normalizePhone('12345', '91'), null);
    expect(normalizePhone('', '91'), null);
  });

  test('fillMessage', () {
    expect(fillMessage('Hi {name}, come!', ' Uppa '), 'Hi Uppa, come!');
  });
}
