import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  final origin = Uri.parse('https://cms.example.invalid');
  final url = Uri.parse(
    'https://cms.example.invalid/native/web-session/redeem/example-0001',
  );

  test('accepts a bounded same-origin HTTPS handoff', () {
    final handoff = KumweWebSessionHandoff(
      handoffUrl: url,
      expiresIn: 60,
      expectedOrigin: origin,
    );
    expect(handoff.handoffUrl, url);
    expect(handoff.expiresIn, 60);
    expect(handoff.origin, origin);
  });

  test('refuses a handoff pointing anywhere but the deployment origin', () {
    for (final wrong in [
      'http://cms.example.invalid/native/web-session/redeem/example-0001',
      'https://evil.example.invalid/native/web-session/redeem/example-0001',
      'https://cms.example.invalid:8443/native/web-session/redeem/e-0001',
      'https://user:secret@cms.example.invalid/native/web-session/e-0001',
    ]) {
      expect(
        () => KumweWebSessionHandoff(
          handoffUrl: Uri.parse(wrong),
          expiresIn: 60,
          expectedOrigin: origin,
        ),
        throwsArgumentError,
        reason: wrong,
      );
    }
  });

  test('honors an explicit port when both sides declare it', () {
    final portOrigin = Uri.parse('https://cms.example.invalid:8443');
    final portUrl = Uri.parse(
      'https://cms.example.invalid:8443/native/web-session/redeem/e-0001',
    );
    final handoff = KumweWebSessionHandoff(
      handoffUrl: portUrl,
      expiresIn: 30,
      expectedOrigin: portOrigin,
    );
    expect(handoff.handoffUrl, portUrl);
  });

  test('bounds the lifetime to the wire contract', () {
    for (final ttl in [0, 9, 301]) {
      expect(
        () => KumweWebSessionHandoff(
          handoffUrl: url,
          expiresIn: ttl,
          expectedOrigin: origin,
        ),
        throwsArgumentError,
        reason: '$ttl',
      );
    }
  });

  test('bounds the URL length', () {
    expect(
      () => KumweWebSessionHandoff(
        handoffUrl: Uri.parse(
          'https://cms.example.invalid/native/${'a' * 320}',
        ),
        expiresIn: 60,
        expectedOrigin: origin,
      ),
      throwsArgumentError,
    );
  });

  test('the secret URL never appears in diagnostics', () {
    final handoff = KumweWebSessionHandoff(
      handoffUrl: url,
      expiresIn: 60,
      expectedOrigin: origin,
    );
    expect(handoff.toString(), isNot(contains('redeem')));
    expect(handoff.toString(), contains('expiresIn: 60'));
  });
}
