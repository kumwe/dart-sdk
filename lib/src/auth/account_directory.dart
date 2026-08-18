import '../context/execution_context.dart';
import 'account_state.dart';
import 'credential_reference.dart';
import 'login_area.dart';

/// Identity of one signed-in account: the exact deployment origin, the
/// sign-in area and the credential that belongs to it.
///
/// A client may hold accounts on several Kumwe deployments and both areas of
/// one deployment at once, and switch between them. Keying by origin, area
/// and credential reference — never by address alone — keeps every account's
/// material and caches apart.
final class KumweAccountKey {
  /// Creates a validated account key.
  factory KumweAccountKey({
    required Uri origin,
    required KumweLoginArea area,
    required KumweCredentialReference credential,
  }) {
    return KumweAccountKey._(
      origin: KumweContextIdentifiers.normalizeOrigin(origin, 'origin'),
      area: area,
      credential: credential,
    );
  }

  const KumweAccountKey._({
    required this.origin,
    required this.area,
    required this.credential,
  });

  /// Exact HTTPS deployment origin the account belongs to.
  final Uri origin;

  /// Sign-in area the account's credential is bound to.
  final KumweLoginArea area;

  /// Non-secret reference naming the account's credential.
  final KumweCredentialReference credential;

  /// Canonical identity used by directory implementations.
  String get identity =>
      '${origin.scheme}://${origin.authority}'
      '|${area.wireValue}|${credential.value}';

  @override
  bool operator ==(Object other) =>
      other is KumweAccountKey && other.identity == identity;

  @override
  int get hashCode => identity.hashCode;

  @override
  String toString() => 'KumweAccountKey($identity)';
}

/// The non-secret roster entry for one signed-in account.
///
/// Records carry only what an account switcher needs to render and select an
/// account; token material stays in the credential store under its own key.
final class KumweAccountRecord {
  /// Creates a validated roster entry.
  factory KumweAccountRecord({
    required KumweAccountKey key,
    required KumweAccountState state,
    String? emailAddress,
    String? installationDisplayName,
  }) {
    if (emailAddress != null &&
        (emailAddress.isEmpty ||
            emailAddress.length > 254 ||
            emailAddress.contains(RegExp(r'[\s\x00-\x1f\x7f]')))) {
      throw ArgumentError.value(
        '<redacted>',
        'emailAddress',
        'Displayed addresses are bounded and free of control characters.',
      );
    }
    if (installationDisplayName != null &&
        (installationDisplayName.trim().isEmpty ||
            installationDisplayName.length > 120)) {
      throw ArgumentError.value(
        installationDisplayName,
        'installationDisplayName',
        'Installation display names need 1 to 120 characters.',
      );
    }
    return KumweAccountRecord._(
      key: key,
      state: state,
      emailAddress: emailAddress,
      installationDisplayName: installationDisplayName?.trim(),
    );
  }

  const KumweAccountRecord._({
    required this.key,
    required this.state,
    required this.emailAddress,
    required this.installationDisplayName,
  });

  /// Identity of the account this record describes.
  final KumweAccountKey key;

  /// Last server-reported account state; pending renders the arrival page.
  final KumweAccountState state;

  /// Optional address shown in the switcher; personal data, so it stays out
  /// of diagnostics.
  final String? emailAddress;

  /// Optional installation display name from the discovery document.
  final String? installationDisplayName;

  /// Returns this record with a newly reported [state].
  KumweAccountRecord withState(KumweAccountState state) => KumweAccountRecord._(
    key: key,
    state: state,
    emailAddress: emailAddress,
    installationDisplayName: installationDisplayName,
  );

  @override
  String toString() =>
      'KumweAccountRecord(${key.identity}, state: ${state.wireValue}, '
      '<address redacted>)';
}

/// The application seam that persists the non-secret account roster.
///
/// The roster is what an account switcher lists; it holds no token material.
/// Removing an account removes only the roster entry — the application also
/// removes the credential-store entry and authority-bound caches under the
/// same key, and attempts server-side revocation first.
abstract interface class KumweAccountDirectory {
  /// Lists every stored account record.
  Future<List<KumweAccountRecord>> list();

  /// Stores [record], replacing any previous record with the same key.
  Future<void> save(KumweAccountRecord record);

  /// Removes the record for [key]; removing an absent entry is not an error.
  Future<void> remove(KumweAccountKey key);
}

/// A volatile in-memory directory for tests and development hosts.
final class InMemoryAccountDirectory implements KumweAccountDirectory {
  /// Creates an empty volatile directory.
  InMemoryAccountDirectory();

  final Map<String, KumweAccountRecord> _records = {};

  @override
  Future<List<KumweAccountRecord>> list() async =>
      List.unmodifiable(_records.values);

  @override
  Future<void> save(KumweAccountRecord record) async {
    _records[record.key.identity] = record;
  }

  @override
  Future<void> remove(KumweAccountKey key) async {
    _records.remove(key.identity);
  }

  @override
  String toString() => 'InMemoryAccountDirectory(${_records.length} entries)';
}
