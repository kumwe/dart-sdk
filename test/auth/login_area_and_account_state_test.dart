import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('login areas round-trip their exact wire values', () {
    expect(KumweLoginArea.administrator.wireValue, 'administrator');
    expect(KumweLoginArea.portal.wireValue, 'portal');
    for (final area in KumweLoginArea.values) {
      expect(KumweLoginArea.parse(area.wireValue), area);
    }
  });

  test('unknown or case-shifted areas fail closed', () {
    expect(() => KumweLoginArea.parse('Administrator'), throwsFormatException);
    expect(() => KumweLoginArea.parse('public'), throwsFormatException);
    expect(() => KumweLoginArea.parse(''), throwsFormatException);
  });

  test('account states round-trip their exact wire values', () {
    expect(KumweAccountState.active.wireValue, 'active');
    expect(KumweAccountState.pending.wireValue, 'pending');
    for (final state in KumweAccountState.values) {
      expect(KumweAccountState.parse(state.wireValue), state);
    }
  });

  test('unknown account states fail closed instead of granting access', () {
    expect(() => KumweAccountState.parse('Active'), throwsFormatException);
    expect(() => KumweAccountState.parse('guest'), throwsFormatException);
    expect(() => KumweAccountState.parse(''), throwsFormatException);
  });
}
