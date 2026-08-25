import 'dart:collection';

import '../auth/credential_reference.dart';
import '../context/execution_context.dart';
import '../json/canonical_json.dart';
import '../json/kumwe_json.dart';

/// One authority partition of the runtime cache.
///
/// A partition binds a cache entry to everything that decides what a
/// caller may see: deployment origin, site, credential and the full set of
/// authority generations the server stamped on the credential's token.
/// When any generation moves — policy, membership, security epoch — the
/// partition digest changes and every entry cached under the old digest
/// becomes unreachable, so stale disclosure can never leak across an
/// authority change.
final class KumweAuthorityPartition {
  /// Derives a partition from its authority inputs.
  ///
  /// Organization and workspace are part of the scope: one credential
  /// browsing two organizations holds two partitions, so their disclosed
  /// views can never collide in the cache.
  factory KumweAuthorityPartition({
    required Uri origin,
    required String site,
    required KumweCredentialReference credential,
    String? organization,
    String? workspace,
    Map<String, String> generations = const {},
  }) {
    if (generations.length > 16) {
      throw ArgumentError.value(
        generations.length,
        'generations',
        'Authority generations are a bounded map.',
      );
    }
    if (workspace != null && organization == null) {
      throw ArgumentError.value(
        workspace,
        'workspace',
        'A workspace is scoped inside an organization.',
      );
    }
    final normalizedOrigin = KumweContextIdentifiers.normalizeOrigin(
      origin,
      'origin',
    );
    final normalizedSite = KumweContextIdentifiers.normalizeSite(site);
    final normalizedOrganization = organization == null
        ? null
        : KumweContextIdentifiers.normalizeSelection(
            organization,
            'organization',
          );
    final normalizedWorkspace = workspace == null
        ? null
        : KumweContextIdentifiers.normalizeSelection(workspace, 'workspace');
    final digest = KumweCanonicalJson.sha256Hex(
      KumweJsonValue.from({
        'origin': normalizedOrigin.toString(),
        'site': normalizedSite,
        'credential': credential.value,
        'organization': normalizedOrganization,
        'workspace': normalizedWorkspace,
        'generations': generations,
      }),
    );
    return KumweAuthorityPartition._(
      scope:
          '${normalizedOrigin.toString()}|$normalizedSite'
          '|${normalizedOrganization ?? '-'}|${normalizedWorkspace ?? '-'}'
          '|${credential.value}',
      digest: digest,
    );
  }

  const KumweAuthorityPartition._({required this.scope, required this.digest});

  /// Which credential context the partition belongs to; two partitions of
  /// one scope are the same caller under different authority states.
  final String scope;

  /// Canonical digest over every authority input.
  final String digest;

  @override
  bool operator ==(Object other) =>
      other is KumweAuthorityPartition &&
      other.scope == scope &&
      other.digest == digest;

  @override
  int get hashCode => Object.hash(scope, digest);

  @override
  String toString() => 'KumweAuthorityPartition(${digest.substring(0, 12)}…)';
}

/// A bounded, authority-partitioned, online-first runtime cache.
///
/// The cache is disposable by design: it accelerates repeat reads of
/// policy-disclosed documents and is never a source of truth. Entries are
/// readable only under the exact partition that wrote them; adopting a new
/// partition for a scope drops everything the scope cached under any older
/// partition, and [clear] releases everything at once.
final class KumweRuntimeCache<V> {
  /// Creates a cache holding at most [maxEntries] values.
  factory KumweRuntimeCache({int maxEntries = 256}) {
    if (maxEntries < 1 || maxEntries > 65536) {
      throw ArgumentError.value(
        maxEntries,
        'maxEntries',
        'Cache capacities run from 1 to 65536 entries.',
      );
    }
    return KumweRuntimeCache._(maxEntries);
  }

  KumweRuntimeCache._(this._maxEntries);

  final int _maxEntries;
  final LinkedHashMap<String, _CacheEntry<V>> _entries =
      LinkedHashMap<String, _CacheEntry<V>>();
  final LinkedHashMap<String, String> _livePartitions =
      LinkedHashMap<String, String>();

  /// Most scopes held live at once; beyond it the least recently adopted
  /// scope is retired whole, so forgotten credentials cannot accumulate.
  static const int _maxScopes = 64;

  /// Declares [partition] live for its scope, dropping every entry the
  /// scope cached under a different partition digest.
  ///
  /// Call this whenever a session adopts a token: an unchanged digest
  /// only refreshes the scope's recency, a changed digest is a full
  /// invalidation of that caller's view. When the *credential itself*
  /// rotated, also [retire] the superseded partition's scope — rotation
  /// changes the scope, so adopt alone cannot see the old entries.
  void adopt(KumweAuthorityPartition partition) {
    final current = _livePartitions.remove(partition.scope);
    _livePartitions[partition.scope] = partition.digest;
    if (current != null && current != partition.digest) {
      _entries.removeWhere(
        (_, entry) =>
            entry.partition.scope == partition.scope &&
            entry.partition.digest != partition.digest,
      );
    }
    while (_livePartitions.length > _maxScopes) {
      final oldest = _livePartitions.keys.first;
      retire(oldest);
    }
  }

  /// Retires a whole scope: its live-partition record and every entry it
  /// cached, under any digest.
  ///
  /// Credential *rotation* mints a new credential reference and with it a
  /// new scope, so [adopt] alone would leave the superseded credential's
  /// entries and live record behind forever. Whoever rotates a credential
  /// retires the old partition's [KumweAuthorityPartition.scope] when
  /// adopting the new one.
  void retire(String scope) {
    _livePartitions.remove(scope);
    _entries.removeWhere((_, entry) => entry.partition.scope == scope);
  }

  /// Reads the cached value, or `null` when nothing usable is cached.
  ///
  /// A read under a partition that is not the scope's live partition
  /// returns `null` and drops whatever the stale partition had written.
  V? read(KumweAuthorityPartition partition, String key) {
    _requireKey(key);
    if (_livePartitions[partition.scope] != partition.digest) {
      return null;
    }
    final entry = _entries.remove(_entryKey(partition, key));
    if (entry == null) {
      return null;
    }
    // Reinsert to refresh recency.
    _entries[_entryKey(partition, key)] = entry;
    return entry.value;
  }

  /// Caches [value] under [partition], evicting the least recently used
  /// entry when full.
  ///
  /// A write under a stale partition is silently dropped: online-first
  /// means the fresh response was already delivered to the caller, and a
  /// disposable cache never preserves a superseded authority view.
  void write(KumweAuthorityPartition partition, String key, V value) {
    _requireKey(key);
    if (_livePartitions[partition.scope] != partition.digest) {
      return;
    }
    _entries.remove(_entryKey(partition, key));
    _entries[_entryKey(partition, key)] = _CacheEntry(partition, value);
    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Removes one cached value.
  void evict(KumweAuthorityPartition partition, String key) {
    _requireKey(key);
    _entries.remove(_entryKey(partition, key));
  }

  /// Drops every entry and every live-partition declaration.
  void clear() {
    _entries.clear();
    _livePartitions.clear();
  }

  /// Number of cached entries.
  int get length => _entries.length;

  static String _entryKey(KumweAuthorityPartition partition, String key) =>
      '${partition.digest}#$key';

  static void _requireKey(String key) {
    if (key.isEmpty || key.length > 512) {
      throw ArgumentError.value(
        '<key>',
        'key',
        'Cache keys need 1 to 512 characters.',
      );
    }
  }

  @override
  String toString() => 'KumweRuntimeCache(${_entries.length} entry(ies))';
}

final class _CacheEntry<V> {
  const _CacheEntry(this.partition, this.value);

  final KumweAuthorityPartition partition;
  final V value;
}
