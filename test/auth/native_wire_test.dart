import 'dart:convert';
import 'dart:io';

import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  Map<String, Object?> fixture(String name) {
    final source = File('contracts/examples/$name').readAsStringSync();
    return (jsonDecode(source) as Map).cast<String, Object?>();
  }

  group('contract versions', () {
    test('parses bounded semantic versions and orders them', () {
      final low = KumweContractVersion('1.0.0');
      final high = KumweContractVersion('1.2.0');
      expect(low.compareTo(high), isNegative);
      expect(low, KumweContractVersion('1.0.0'));
      expect(low.hashCode, KumweContractVersion('1.0.0').hashCode);
      expect(KumweContractVersion('2.0.0').major, 2);
    });

    test('compares prerelease versions by their numeric triple', () {
      final prerelease = KumweContractVersion('1.0.0-rc.1');
      expect(prerelease.compareTo(KumweContractVersion('1.0.0')), 0);
      expect(prerelease.value, '1.0.0-rc.1');
    });

    test('refuses drifting or unbounded version strings', () {
      expect(() => KumweContractVersion('1.0'), throwsFormatException);
      expect(() => KumweContractVersion('v1.0.0'), throwsFormatException);
      expect(() => KumweContractVersion('1000000.0.0'), throwsFormatException);
    });
  });

  group('discovery documents', () {
    test('the shipped example parses into a usable document', () {
      final document = KumweNativeDiscoveryDocument.fromJson(
        fixture('minimal.native-discovery.json'),
      );
      expect(document.installationReference, 'installation-example-0001');
      expect(document.installationDisplayName, 'Example Kumwe Installation');
      expect(document.coreVersion, '2.0.0');
      expect(document.allowedOrigins, hasLength(1));
      expect(
        document.allowsOrigin(Uri.parse('https://cms.example.invalid')),
        isTrue,
      );
      expect(
        document.allowsOrigin(Uri.parse('https://CMS.EXAMPLE.INVALID')),
        isTrue,
        reason: 'origin comparison is case-normalized',
      );
      expect(
        document.allowsOrigin(Uri.parse('https://evil.example.invalid')),
        isFalse,
      );
      expect(document.supportsProfile('authentication_link'), isTrue);
      expect(document.supportsProfile('device_code'), isFalse);
      expect(document.advertisedAreas, [
        KumweLoginArea.administrator,
        KumweLoginArea.portal,
      ]);
      expect(document.maxRequestBytes, 10485760);
      expect(document.maxPageSize, 200);
    });

    test('the client-contract window is inclusive on both ends', () {
      final document = KumweNativeDiscoveryDocument.fromJson(
        fixture('minimal.native-discovery.json'),
      );
      expect(
        document.supportsClientContract(KumweContractVersion('1.0.0')),
        isTrue,
      );
      expect(
        document.supportsClientContract(KumweContractVersion('0.9.9')),
        isFalse,
      );
      expect(
        document.supportsClientContract(KumweContractVersion('1.0.1')),
        isFalse,
      );
    });

    test('refuses a drifted base path or unpinned site-context rule', () {
      final drifted = fixture('minimal.native-discovery.json');
      (drifted['api']! as Map<String, Object?>)['base_path'] = '/api/v2';
      expect(
        () => KumweNativeDiscoveryDocument.fromJson(drifted),
        throwsFormatException,
      );
      final unpinned = fixture('minimal.native-discovery.json');
      (unpinned['context']! as Map<String, Object?>)['site_required'] = false;
      expect(
        () => KumweNativeDiscoveryDocument.fromJson(unpinned),
        throwsFormatException,
      );
    });

    test('refuses an inverted contract window', () {
      final inverted = fixture('minimal.native-discovery.json');
      (inverted['compatibility']!
              as Map<String, Object?>)['min_client_contract'] =
          '2.0.0';
      expect(
        () => KumweNativeDiscoveryDocument.fromJson(inverted),
        throwsFormatException,
      );
    });

    test('refuses non-HTTPS, oversized and repeated origins', () {
      final insecure = fixture('minimal.native-discovery.json');
      (insecure['api']! as Map<String, Object?>)['allowed_origins'] = [
        'http://cms.example.invalid',
      ];
      expect(
        () => KumweNativeDiscoveryDocument.fromJson(insecure),
        throwsA(anything),
      );
      final oversized = fixture('minimal.native-discovery.json');
      (oversized['api']!
          as Map<String, Object?>)['allowed_origins'] = List<Object?>.generate(
        9,
        (index) => 'https://origin-$index.example.invalid',
      );
      expect(
        () => KumweNativeDiscoveryDocument.fromJson(oversized),
        throwsFormatException,
      );
    });

    test('refuses repeated or overflowing authorization declarations', () {
      final repeated = fixture('minimal.native-discovery.json');
      (repeated['authorization']! as Map<String, Object?>)['profiles'] = [
        'preissued_bearer',
        'preissued_bearer',
      ];
      expect(
        () => KumweNativeDiscoveryDocument.fromJson(repeated),
        throwsFormatException,
      );
      final areas = fixture('minimal.native-discovery.json');
      (areas['authorization']! as Map<String, Object?>)['areas'] = [
        'administrator',
        'administrator',
      ];
      expect(
        () => KumweNativeDiscoveryDocument.fromJson(areas),
        throwsFormatException,
      );
    });

    test('a document without areas offers no chooser', () {
      final bare = fixture('minimal.native-discovery.json');
      (bare['authorization']! as Map<String, Object?>).remove('areas');
      final document = KumweNativeDiscoveryDocument.fromJson(bare);
      expect(document.advertisedAreas, isEmpty);
    });

    test('diagnostics stay to reference and origin count', () {
      final document = KumweNativeDiscoveryDocument.fromJson(
        fixture('minimal.native-discovery.json'),
      );
      expect(document.toString(), contains('installation-example-0001'));
      expect(document.toString(), contains('1 origin(s)'));
    });
  });

  group('token responses', () {
    test('the shipped active-account example parses fully', () {
      final response = KumweNativeTokenResponse.fromJson(
        fixture('token-response.native-authorization.json'),
      );
      expect(response.expiresIn, const Duration(days: 30));
      expect(response.refreshEligible, isTrue);
      expect(response.credentialReference.value, 'credential-example-0001');
      expect(response.area, KumweLoginArea.portal);
      expect(response.accountState, KumweAccountState.active);
      expect(response.site, 'corporate');
      expect(response.organization, 'org-example-0001');
      expect(response.workspace, 'workspace-example-0001');
      expect(response.authorityGenerations['policy_generation'], '7');
      expect(
        () => response.authorityGenerations['x'] = 'y',
        throwsUnsupportedError,
      );
    });

    test('the pending-guest example lands in the pending state', () {
      final response = KumweNativeTokenResponse.fromJson(
        fixture('token-response.pending-guest.native-authorization.json'),
      );
      expect(response.accountState, KumweAccountState.pending);
      expect(response.organization, isNull);
      expect(response.workspace, isNull);
      expect(response.scope, 'account.self');
    });

    test('builds an access token anchored to the injected clock', () {
      final issuedAt = DateTime.utc(2026, 8, 25, 12);
      final token = KumweNativeTokenResponse.fromJson(
        fixture('token-response.native-authorization.json'),
      ).toAccessToken(issuedAt: issuedAt);
      expect(token.expiresAt, issuedAt.add(const Duration(days: 30)));
      expect(token.boundSite, 'corporate');
      expect(token.refreshEligible, isTrue);
      expect(token.area, KumweLoginArea.portal);
      expect(token.accountState, KumweAccountState.active);
      expect(token.authorityGenerations['security_epoch'], '1');
    });

    test('refuses non-Bearer, unbounded and lifeless responses', () {
      final wrongType = fixture('token-response.native-authorization.json');
      wrongType['token_type'] = 'MAC';
      expect(
        () => KumweNativeTokenResponse.fromJson(wrongType),
        throwsFormatException,
      );
      final shortToken = fixture('token-response.native-authorization.json');
      shortToken['access_token'] = 'too-short';
      expect(
        () => KumweNativeTokenResponse.fromJson(shortToken),
        throwsFormatException,
      );
      final shortLife = fixture('token-response.native-authorization.json');
      shortLife['expires_in'] = 60;
      expect(
        () => KumweNativeTokenResponse.fromJson(shortLife),
        throwsFormatException,
      );
      final longLife = fixture('token-response.native-authorization.json');
      longLife['expires_in'] = 7776001;
      expect(
        () => KumweNativeTokenResponse.fromJson(longLife),
        throwsFormatException,
      );
    });

    test('refuses a credential without its reference', () {
      final anonymous = fixture('token-response.native-authorization.json');
      (anonymous['credential']! as Map<String, Object?>).remove('reference');
      expect(
        () => KumweNativeTokenResponse.fromJson(anonymous),
        throwsFormatException,
      );
    });

    test('refuses out-of-grammar scopes and oversized generation maps', () {
      final badScope = fixture('token-response.native-authorization.json');
      badScope['scope'] = 'has  double-space';
      expect(
        () => KumweNativeTokenResponse.fromJson(badScope),
        throwsFormatException,
      );
      final generations = fixture('token-response.native-authorization.json');
      generations['authority_generations'] = {
        for (var index = 0; index < 17; index++) 'authority$index': '1',
      };
      expect(
        () => KumweNativeTokenResponse.fromJson(generations),
        throwsFormatException,
      );
    });

    test('diagnostics never include token material', () {
      final response = KumweNativeTokenResponse.fromJson(
        fixture('token-response.native-authorization.json'),
      );
      expect(response.toString(), isNot(contains('example-access-token')));
      expect(response.toString(), isNot(contains('example-refresh-token')));
      expect(response.toString(), contains('credential-example-0001'));
      expect(response.toString(), contains('<redacted>'));
    });
  });

  group('web-session responses', () {
    test('the shipped example parses and binds to its origin', () {
      final response = KumweNativeWebSessionResponse.fromJson(
        fixture('web-session.native-authorization.json'),
      );
      expect(response.expiresIn, 60);
      final handoff = response.toHandoff(
        expectedOrigin: Uri.parse('https://cms.example.invalid'),
      );
      expect(handoff.handoffUrl.host, 'cms.example.invalid');
    });

    test('a handoff for the wrong origin is refused at conversion', () {
      final response = KumweNativeWebSessionResponse.fromJson(
        fixture('web-session.native-authorization.json'),
      );
      expect(
        () => response.toHandoff(
          expectedOrigin: Uri.parse('https://other.example.invalid'),
        ),
        throwsArgumentError,
      );
    });

    test('refuses plain-HTTP, oversized and out-of-window responses', () {
      expect(
        () => KumweNativeWebSessionResponse.fromJson({
          'handoff_url': 'http://cms.example.invalid/native/x',
          'expires_in': 60,
        }),
        throwsFormatException,
      );
      expect(
        () => KumweNativeWebSessionResponse.fromJson({
          'handoff_url': 'https://cms.example.invalid/${'a' * 320}',
          'expires_in': 60,
        }),
        throwsFormatException,
      );
      expect(
        () => KumweNativeWebSessionResponse.fromJson({
          'handoff_url': 'https://cms.example.invalid/native/x',
          'expires_in': 5,
        }),
        throwsFormatException,
      );
      expect(
        () => KumweNativeWebSessionResponse.fromJson({
          'handoff_url': 'https://cms.example.invalid/native/x',
          'expires_in': 301,
        }),
        throwsFormatException,
      );
    });

    test('diagnostics never include the handoff URL', () {
      final response = KumweNativeWebSessionResponse.fromJson(
        fixture('web-session.native-authorization.json'),
      );
      expect(response.toString(), isNot(contains('redeem')));
      expect(response.toString(), contains('<url redacted>'));
    });
  });
}
