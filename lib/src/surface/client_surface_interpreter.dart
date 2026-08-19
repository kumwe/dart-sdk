import 'dart:convert';

import '../json/kumwe_json.dart';
import 'client_surface_manifest.dart';
import 'client_surface_vocabulary.dart';

/// Why a manifest or one of its surfaces was not admitted.
enum ClientSurfaceRejectionReason {
  /// The document declares a schema identity this interpreter cannot read.
  unsupportedSchema,

  /// A member was missing, of the wrong type, out of bounds, or undeclared.
  structuralViolation,

  /// A required value fell outside its closed vocabulary.
  unknownRequiredVocabulary,

  /// A declared reference did not resolve inside its own surface.
  unresolvedReference,

  /// An identifier was declared more than once in the same scope.
  duplicateIdentifier,

  /// An identifier fell outside the namespace of the owning extension.
  ownerNamespaceEscape,
}

/// One manifest or surface that was refused, with the reason it failed.
final class ClientSurfaceRejection {
  /// Creates a rejection record.
  const ClientSurfaceRejection({
    required this.reason,
    required this.path,
    required this.message,
    this.surfaceId,
  });

  /// Identifier of the refused surface, or `null` when the whole manifest
  /// was refused.
  final String? surfaceId;

  /// Why the subject was refused.
  final ClientSurfaceRejectionReason reason;

  /// Location of the offending value.
  final String path;

  /// Operator-readable explanation carrying no manifest payload.
  final String message;

  @override
  String toString() => 'ClientSurfaceRejection($path: $message)';
}

/// One optional contribution that was understood well enough to omit.
///
/// Notices never carry a security decision. They exist so a host can report
/// that an optional presentation hint was newer than the client, without
/// failing a surface that is otherwise complete.
final class ClientSurfaceNotice {
  /// Creates a notice record.
  const ClientSurfaceNotice({
    required this.surfaceId,
    required this.path,
    required this.message,
  });

  /// Surface the omitted contribution belonged to.
  final String surfaceId;

  /// Location of the omitted value.
  final String path;

  /// Operator-readable explanation carrying no manifest payload.
  final String message;

  @override
  String toString() => 'ClientSurfaceNotice($path: $message)';
}

/// The outcome of interpreting one client-surface manifest.
final class ClientSurfaceInterpretation {
  /// Creates an interpretation result.
  ClientSurfaceInterpretation({
    required this.manifest,
    required List<ClientSurfaceRejection> rejections,
    required List<ClientSurfaceNotice> notices,
  }) : rejections = List.unmodifiable(rejections),
       notices = List.unmodifiable(notices);

  /// The manifest when its envelope was understood, otherwise `null`.
  ///
  /// A non-null manifest may still carry no surfaces when every surface was
  /// refused; check [isUsable] before presenting anything.
  final ClientSurfaceManifest? manifest;

  /// Manifests and surfaces that were refused.
  final List<ClientSurfaceRejection> rejections;

  /// Optional contributions that were omitted rather than refused.
  final List<ClientSurfaceNotice> notices;

  /// Whether at least one surface was admitted.
  bool get isUsable => manifest != null && manifest!.surfaces.isNotEmpty;

  /// Whether anything at all was refused.
  bool get hasRejections => rejections.isNotEmpty;

  @override
  String toString() =>
      'ClientSurfaceInterpretation(surfaces: ${manifest?.surfaces.length ?? 0},'
      ' rejections: ${rejections.length}, notices: ${notices.length})';
}

/// Reads a bounded declarative client-surface manifest into immutable models.
///
/// The interpreter is defense in depth, not the authorization boundary: the
/// server admits, policy-filters and lifecycle-binds a manifest before a
/// client ever sees it, and this type validates the closed grammar again
/// before exposing any model.
///
/// Failure is scoped deliberately. A malformed envelope refuses the whole
/// manifest, while a surface that cannot be fully understood is refused on
/// its own so the remaining surfaces stay usable. Required vocabulary outside
/// its closed set fails its surface closed; an optional presentation hint
/// outside its set is omitted with a notice, because dropping a width hint
/// cannot mislead a user the way guessing a widget could.
///
/// Nothing here executes, fetches, or resolves anything: the grammar has no
/// route, URL, template, expression, handler or credential to act on.
///
/// Two rules go beyond the manifest JSON Schema read in isolation, because
/// the contract is that schema together with the repository's semantic rules:
/// identifiers must be unique within their scope, and every identifier must
/// sit inside the owning package's namespace. `uniqueItems` alone would admit
/// two screens that share an identifier while differing elsewhere, which
/// would make navigation resolution ambiguous.
final class ClientSurfaceInterpreter {
  /// Creates the stateless interpreter.
  const ClientSurfaceInterpreter();

  /// Schema identity this interpreter understands.
  static const String schemaId =
      'urn:kumwe:proposal:schema:client-surface-manifest:0.1.0';

  /// Manifest schema version this interpreter understands.
  static const int supportedSchemaVersion = 1;

  /// Largest encoded manifest the proposed contract permits, in bytes.
  static const int maxEncodedBytes = 1048576;

  /// Interprets manifest [source] text, bounding it before it is parsed.
  ///
  /// The encoded-byte limit has to be applied to the bytes, not to a parsed
  /// document: by the time a multi-megabyte manifest has been decoded the
  /// memory has already been spent. Callers that receive an already-parsed
  /// document should bound it at the transport instead.
  ClientSurfaceInterpretation interpretJson(
    String source, {
    int maxBytes = maxEncodedBytes,
  }) {
    if (utf8.encode(source).length > maxBytes) {
      return ClientSurfaceInterpretation(
        manifest: null,
        rejections: const [
          ClientSurfaceRejection(
            reason: ClientSurfaceRejectionReason.structuralViolation,
            path: r'$',
            message: 'The encoded manifest exceeds its declared byte bound.',
          ),
        ],
        notices: const [],
      );
    }
    final KumweJsonObject document;
    try {
      document = KumweJsonObject.parse(source);
    } on FormatException {
      return ClientSurfaceInterpretation(
        manifest: null,
        rejections: const [
          ClientSurfaceRejection(
            reason: ClientSurfaceRejectionReason.structuralViolation,
            path: r'$',
            message: 'The manifest is not a well-formed JSON object.',
          ),
        ],
        notices: const [],
      );
    }
    return interpret(document);
  }

  /// Interprets [document] into admitted surfaces, rejections and notices.
  ClientSurfaceInterpretation interpret(KumweJsonObject document) {
    final rejections = <ClientSurfaceRejection>[];
    final notices = <ClientSurfaceNotice>[];
    final root = document.value;

    final ClientSurfaceOwner owner;
    final ClientSurfaceRuntime runtime;
    final List<ClientSurfaceContractRequirement> contracts;
    final String manifestId;
    final List<Object?> surfaceEntries;
    try {
      _requireClosed(root, _rootMembers, r'$');
      _requireSchemaIdentity(root);
      manifestId = _requireString(
        root,
        'manifest_id',
        r'$.manifest_id',
        pattern: _namespacedId,
        maxLength: 191,
      );
      owner = _readOwner(root);
      _requireOwnedNamespace(manifestId, owner, r'$.manifest_id', null);
      runtime = _readRuntime(root);
      contracts = _readContracts(root);
      surfaceEntries = _requireArray(
        root,
        'surfaces',
        r'$.surfaces',
        minItems: 1,
        maxItems: 64,
      );
    } on _Violation catch (violation) {
      return ClientSurfaceInterpretation(
        manifest: null,
        rejections: [violation.toRejection()],
        notices: notices,
      );
    }

    final surfaces = <ClientSurface>[];
    final seenSurfaceIds = <String>{};
    for (var index = 0; index < surfaceEntries.length; index++) {
      final path = '\$.surfaces[$index]';
      final entry = surfaceEntries[index];
      final declaredId = entry is Map<String, Object?> ? entry['id'] : null;
      final surfaceId = declaredId is String ? declaredId : null;
      // Notices this attempt appends are withdrawn positionally if it fails.
      // Matching on the surface identifier instead would withdraw an admitted
      // surface's notices when a later surface declares the same identifier.
      final noticeMark = notices.length;
      try {
        final surface = _readSurface(entry, path, owner, notices);
        if (!seenSurfaceIds.add(surface.id)) {
          throw _Violation(
            ClientSurfaceRejectionReason.duplicateIdentifier,
            '$path.id',
            'Surface identifier is declared more than once.',
            surfaceId: surface.id,
          );
        }
        surfaces.add(surface);
      } on _Violation catch (violation) {
        rejections.add(violation.toRejection(fallbackSurfaceId: surfaceId));
        notices.removeRange(noticeMark, notices.length);
      }
    }

    return ClientSurfaceInterpretation(
      manifest: ClientSurfaceManifest(
        schemaVersion: supportedSchemaVersion,
        manifestId: manifestId,
        owner: owner,
        runtime: runtime,
        requiredContracts: contracts,
        surfaces: surfaces,
      ),
      rejections: rejections,
      notices: notices,
    );
  }

  void _requireSchemaIdentity(Map<String, Object?> root) {
    if (root[r'$schema'] != schemaId) {
      throw _Violation(
        ClientSurfaceRejectionReason.unsupportedSchema,
        r'$.$schema',
        'The manifest declares a schema identity this client does not read.',
      );
    }
    if (root['schema_version'] != supportedSchemaVersion) {
      throw _Violation(
        ClientSurfaceRejectionReason.unsupportedSchema,
        r'$.schema_version',
        'The manifest declares an unsupported schema version.',
      );
    }
  }

  /// Requires [id] to sit inside the namespace its owning package owns.
  ///
  /// Core admission proves owner namespacing before serving a manifest; the
  /// client proves it again so a contribution can never present itself under
  /// another extension's identity if that admission is ever bypassed. The
  /// namespace is the `vendor/name` package with its separator normalized,
  /// so `acme/orders` owns `acme.orders.*`.
  void _requireOwnedNamespace(
    String id,
    ClientSurfaceOwner owner,
    String path,
    String? surfaceId,
  ) {
    final namespace = owner.extension.replaceAll('/', '.');
    if (!id.startsWith('$namespace.')) {
      throw _Violation(
        ClientSurfaceRejectionReason.ownerNamespaceEscape,
        path,
        'An identifier is declared outside the namespace of its owning '
        'extension.',
        surfaceId: surfaceId,
      );
    }
  }

  ClientSurfaceOwner _readOwner(Map<String, Object?> root) {
    const path = r'$.owner';
    final owner = _requireObject(root, 'owner', path);
    _requireClosed(owner, _ownerMembers, path);
    return ClientSurfaceOwner(
      extension: _requireString(
        owner,
        'extension',
        '$path.extension',
        pattern: _extensionName,
        maxLength: 127,
      ),
      version: _requireString(
        owner,
        'version',
        '$path.version',
        pattern: _semanticVersion,
        maxLength: 80,
      ),
      checksum: _requireString(
        owner,
        'checksum',
        '$path.checksum',
        pattern: _checksum,
        maxLength: 71,
      ),
    );
  }

  ClientSurfaceRuntime _readRuntime(Map<String, Object?> root) {
    const path = r'$.runtime';
    final runtime = _requireObject(root, 'runtime', path);
    _requireClosed(runtime, _runtimeMembers, path);
    return ClientSurfaceRuntime(
      generation: _requireInt(
        runtime,
        'generation',
        '$path.generation',
        minimum: 0,
        maximum: 2147483647,
      ),
      checksum: _requireString(
        runtime,
        'checksum',
        '$path.checksum',
        pattern: _checksum,
        maxLength: 71,
      ),
    );
  }

  List<ClientSurfaceContractRequirement> _readContracts(
    Map<String, Object?> root,
  ) {
    const path = r'$.required_contracts';
    final entries = _requireArray(
      root,
      'required_contracts',
      path,
      minItems: 1,
      maxItems: 16,
    );
    final contracts = <ClientSurfaceContractRequirement>[];
    final seen = <String>{};
    for (var index = 0; index < entries.length; index++) {
      final entryPath = '$path[$index]';
      final entry = entries[index];
      if (entry is! Map<String, Object?>) {
        throw _Violation(
          ClientSurfaceRejectionReason.structuralViolation,
          entryPath,
          'A contract requirement must be an object.',
        );
      }
      _requireClosed(entry, _contractMembers, entryPath);
      final id = _requireString(
        entry,
        'id',
        '$entryPath.id',
        pattern: _handle,
        maxLength: 191,
      );
      if (!seen.add(id)) {
        throw _Violation(
          ClientSurfaceRejectionReason.duplicateIdentifier,
          '$entryPath.id',
          'A contract requirement is declared more than once.',
        );
      }
      contracts.add(
        ClientSurfaceContractRequirement(
          id: id,
          versionRange: _requireString(
            entry,
            'version_range',
            '$entryPath.version_range',
            pattern: _versionRange,
            maxLength: 80,
          ),
        ),
      );
    }
    return contracts;
  }

  ClientSurface _readSurface(
    Object? entry,
    String path,
    ClientSurfaceOwner owner,
    List<ClientSurfaceNotice> notices,
  ) {
    if (entry is! Map<String, Object?>) {
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        path,
        'A surface must be an object.',
      );
    }
    _requireClosed(entry, _surfaceMembers, path);
    final id = _requireString(
      entry,
      'id',
      '$path.id',
      pattern: _namespacedId,
      maxLength: 191,
    );
    _requireOwnedNamespace(id, owner, '$path.id', id);
    final audience = _requireVocabulary(
      ClientSurfaceAudience.tryParse(entry['audience']),
      '$path.audience',
      'audience',
      id,
    );
    final kind = _requireVocabulary(
      ClientSurfaceKind.tryParse(entry['kind']),
      '$path.kind',
      'surface kind',
      id,
    );
    final unsupported = _requireVocabulary(
      ClientUnsupportedBehavior.tryParse(entry['unsupported_behavior']),
      '$path.unsupported_behavior',
      'unsupported behavior',
      id,
    );

    final screens = <ClientSurfaceScreen>[];
    final screenIds = <String>{};
    final screenEntries = _requireArray(
      entry,
      'screens',
      '$path.screens',
      minItems: 1,
      maxItems: 256,
      surfaceId: id,
    );
    for (var index = 0; index < screenEntries.length; index++) {
      final screen = _readScreen(
        screenEntries[index],
        '$path.screens[$index]',
        id,
        owner,
        notices,
      );
      if (!screenIds.add(screen.id)) {
        throw _Violation(
          ClientSurfaceRejectionReason.duplicateIdentifier,
          '$path.screens[$index].id',
          'A screen identifier is declared more than once in this surface.',
          surfaceId: id,
        );
      }
      screens.add(screen);
    }

    final navigation = <ClientSurfaceNavigationItem>[];
    final navigationIds = <String>{};
    final navigationEntries = _requireArray(
      entry,
      'navigation',
      '$path.navigation',
      minItems: 1,
      maxItems: 128,
      surfaceId: id,
    );
    for (var index = 0; index < navigationEntries.length; index++) {
      final item = _readNavigationItem(
        navigationEntries[index],
        '$path.navigation[$index]',
        id,
        owner,
        notices,
      );
      if (!navigationIds.add(item.id)) {
        throw _Violation(
          ClientSurfaceRejectionReason.duplicateIdentifier,
          '$path.navigation[$index].id',
          'A navigation identifier is declared more than once in this '
              'surface.',
          surfaceId: id,
        );
      }
      if (!screenIds.contains(item.screen)) {
        throw _Violation(
          ClientSurfaceRejectionReason.unresolvedReference,
          '$path.navigation[$index].screen',
          'A navigation item points at a screen this surface does not '
              'declare.',
          surfaceId: id,
        );
      }
      navigation.add(item);
    }

    return ClientSurface(
      id: id,
      audience: audience,
      kind: kind,
      label: _requireLocalizedText(entry, 'label', '$path.label', id),
      description: _optionalLocalizedText(
        entry,
        'description',
        '$path.description',
        id,
      ),
      order: _requireInt(
        entry,
        'order',
        '$path.order',
        minimum: 0,
        maximum: 100000,
        surfaceId: id,
      ),
      requiredCapabilities: _readCapabilities(
        entry,
        '$path.required_capabilities',
        id,
      ),
      unsupportedBehavior: unsupported,
      navigation: navigation,
      screens: screens,
    );
  }

  ClientSurfaceScreen _readScreen(
    Object? entry,
    String path,
    String surfaceId,
    ClientSurfaceOwner owner,
    List<ClientSurfaceNotice> notices,
  ) {
    if (entry is! Map<String, Object?>) {
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        path,
        'A screen must be an object.',
        surfaceId: surfaceId,
      );
    }
    _requireClosed(entry, _screenMembers, path, surfaceId: surfaceId);
    final id = _requireString(
      entry,
      'id',
      '$path.id',
      pattern: _namespacedId,
      maxLength: 191,
      surfaceId: surfaceId,
    );
    _requireOwnedNamespace(id, owner, '$path.id', surfaceId);
    final kind = _requireVocabulary(
      ClientScreenKind.tryParse(entry['kind']),
      '$path.kind',
      'screen kind',
      surfaceId,
    );

    final definition = _optionalString(
      entry,
      'definition',
      '$path.definition',
      pattern: _handle,
      maxLength: 191,
      surfaceId: surfaceId,
    );
    final view = _optionalString(
      entry,
      'view',
      '$path.view',
      pattern: _localHandle,
      maxLength: 120,
      surfaceId: surfaceId,
    );
    final report = _optionalString(
      entry,
      'report',
      '$path.report',
      pattern: _handle,
      maxLength: 191,
      surfaceId: surfaceId,
    );
    final ClientFormMode? mode;
    if (entry.containsKey('mode')) {
      if (entry['mode'] == null) {
        throw _Violation(
          ClientSurfaceRejectionReason.structuralViolation,
          '$path.mode',
          'A member is present carrying no value; the grammar declares no '
              'nullable member.',
          surfaceId: surfaceId,
        );
      }
      mode = _requireVocabulary(
        ClientFormMode.tryParse(entry['mode']),
        '$path.mode',
        'form mode',
        surfaceId,
      );
    } else {
      mode = null;
    }

    _requireScreenShape(
      entry: entry,
      kind: kind,
      path: path,
      surfaceId: surfaceId,
      definition: definition,
      view: view,
      mode: mode,
      report: report,
    );

    return ClientSurfaceScreen(
      id: id,
      kind: kind,
      label: _requireLocalizedText(entry, 'label', '$path.label', surfaceId),
      description: _optionalLocalizedText(
        entry,
        'description',
        '$path.description',
        surfaceId,
      ),
      order: _requireInt(
        entry,
        'order',
        '$path.order',
        minimum: 0,
        maximum: 100000,
        surfaceId: surfaceId,
      ),
      requiredCapabilities: _readCapabilities(
        entry,
        '$path.required_capabilities',
        surfaceId,
      ),
      requiredOperations: _readOperations(
        entry,
        '$path.required_operations',
        surfaceId,
      ),
      definition: definition,
      view: view,
      mode: mode,
      report: report,
      fieldPresentations: _readFieldPresentations(
        entry,
        '$path.field_presentations',
        surfaceId,
        notices,
      ),
    );
  }

  /// Enforces the per-kind screen shape the manifest schema declares.
  ///
  /// A `false` subschema forbids a member outright, so presence is the
  /// violation whatever the value carries. Forbidding is therefore decided
  /// on the raw entry rather than on a parsed value.
  void _requireScreenShape({
    required Map<String, Object?> entry,
    required ClientScreenKind kind,
    required String path,
    required String surfaceId,
    required String? definition,
    required String? view,
    required ClientFormMode? mode,
    required String? report,
  }) {
    void require(Object? value, String member) {
      if (value == null) {
        throw _Violation(
          ClientSurfaceRejectionReason.structuralViolation,
          '$path.$member',
          'A ${kind.wireName} screen must declare $member.',
          surfaceId: surfaceId,
        );
      }
    }

    void forbid(String member) {
      if (entry.containsKey(member)) {
        throw _Violation(
          ClientSurfaceRejectionReason.structuralViolation,
          '$path.$member',
          'A ${kind.wireName} screen cannot declare $member.',
          surfaceId: surfaceId,
        );
      }
    }

    switch (kind) {
      case ClientScreenKind.collection:
        require(definition, 'definition');
        forbid('mode');
        forbid('report');
      case ClientScreenKind.record:
        require(definition, 'definition');
        forbid('view');
        forbid('mode');
        forbid('report');
      case ClientScreenKind.form:
        require(definition, 'definition');
        require(mode, 'mode');
        forbid('view');
        forbid('report');
      case ClientScreenKind.document:
        require(definition, 'definition');
        require(view, 'view');
        forbid('mode');
        forbid('report');
      case ClientScreenKind.report:
        require(report, 'report');
        forbid('definition');
        forbid('view');
        forbid('mode');
        forbid('field_presentations');
    }
  }

  ClientSurfaceNavigationItem _readNavigationItem(
    Object? entry,
    String path,
    String surfaceId,
    ClientSurfaceOwner owner,
    List<ClientSurfaceNotice> notices,
  ) {
    if (entry is! Map<String, Object?>) {
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        path,
        'A navigation item must be an object.',
        surfaceId: surfaceId,
      );
    }
    _requireClosed(entry, _navigationMembers, path, surfaceId: surfaceId);
    ClientNavigationIcon? icon;
    if (entry.containsKey('icon')) {
      final rawIcon = entry['icon'];
      if (rawIcon is! String) {
        throw _Violation(
          ClientSurfaceRejectionReason.structuralViolation,
          '$path.icon',
          'An optional icon hint must be one of its declared text values.',
          surfaceId: surfaceId,
        );
      }
      icon = ClientNavigationIcon.tryParse(rawIcon);
      if (icon == null) {
        notices.add(
          ClientSurfaceNotice(
            surfaceId: surfaceId,
            path: '$path.icon',
            message: 'An unsupported navigation icon was omitted.',
          ),
        );
      }
    }
    final id = _requireString(
      entry,
      'id',
      '$path.id',
      pattern: _namespacedId,
      maxLength: 191,
      surfaceId: surfaceId,
    );
    _requireOwnedNamespace(id, owner, '$path.id', surfaceId);
    return ClientSurfaceNavigationItem(
      id: id,
      label: _requireLocalizedText(entry, 'label', '$path.label', surfaceId),
      screen: _requireString(
        entry,
        'screen',
        '$path.screen',
        pattern: _namespacedId,
        maxLength: 191,
        surfaceId: surfaceId,
      ),
      order: _requireInt(
        entry,
        'order',
        '$path.order',
        minimum: 0,
        maximum: 100000,
        surfaceId: surfaceId,
      ),
      icon: icon,
      requiredCapabilities: _readCapabilities(
        entry,
        '$path.required_capabilities',
        surfaceId,
      ),
    );
  }

  Map<String, ClientFieldPresentation> _readFieldPresentations(
    Map<String, Object?> entry,
    String path,
    String surfaceId,
    List<ClientSurfaceNotice> notices,
  ) {
    final raw = entry['field_presentations'];
    if (raw == null) {
      _rejectExplicitNull(
        entry,
        'field_presentations',
        path,
        surfaceId: surfaceId,
      );
      return const {};
    }
    if (raw is! Map<String, Object?>) {
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        path,
        'Field presentations must be an object.',
        surfaceId: surfaceId,
      );
    }
    if (raw.length > 64) {
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        path,
        'Field presentations are bounded to 64 entries.',
        surfaceId: surfaceId,
      );
    }
    final presentations = <String, ClientFieldPresentation>{};
    for (final field in raw.entries) {
      final fieldPath = '$path.${field.key}';
      if (!_localHandle.hasMatch(field.key) || textLength(field.key) > 120) {
        throw _Violation(
          ClientSurfaceRejectionReason.structuralViolation,
          fieldPath,
          'A field presentation key must be a bounded local handle.',
          surfaceId: surfaceId,
        );
      }
      final value = field.value;
      if (value is! Map<String, Object?>) {
        throw _Violation(
          ClientSurfaceRejectionReason.structuralViolation,
          fieldPath,
          'A field presentation must be an object.',
          surfaceId: surfaceId,
        );
      }
      _requireClosed(
        value,
        _fieldPresentationMembers,
        fieldPath,
        surfaceId: surfaceId,
      );
      final widget = ClientFieldWidget.tryParse(value['widget']);
      if (widget == null) {
        throw _Violation(
          ClientSurfaceRejectionReason.unknownRequiredVocabulary,
          '$fieldPath.widget',
          'A field declares a widget this client cannot present.',
          surfaceId: surfaceId,
        );
      }
      presentations[field.key] = ClientFieldPresentation(
        widget: widget,
        emphasis: _optionalHint(
          value,
          'emphasis',
          '$fieldPath.emphasis',
          surfaceId,
          notices,
          ClientFieldEmphasis.tryParse,
          'emphasis',
        ),
        width: _optionalHint(
          value,
          'width',
          '$fieldPath.width',
          surfaceId,
          notices,
          ClientFieldWidth.tryParse,
          'width',
        ),
      );
    }
    return presentations;
  }

  T? _optionalHint<T>(
    Map<String, Object?> object,
    String key,
    String path,
    String surfaceId,
    List<ClientSurfaceNotice> notices,
    T? Function(Object?) parse,
    String label,
  ) {
    if (!object.containsKey(key)) {
      return null;
    }
    final raw = object[key];
    if (raw is! String) {
      // Forgiveness extends to a newer vocabulary word, never to a malformed
      // value: arbitrary JSON here is a broken document, not a hint from a
      // later contract revision.
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        path,
        'An optional $label hint must be one of its declared text values.',
        surfaceId: surfaceId,
      );
    }
    final parsed = parse(raw);
    if (parsed == null) {
      notices.add(
        ClientSurfaceNotice(
          surfaceId: surfaceId,
          path: path,
          message: 'An unsupported $label hint was omitted.',
        ),
      );
    }
    return parsed;
  }

  Set<String> _readCapabilities(
    Map<String, Object?> entry,
    String path,
    String surfaceId,
  ) {
    final raw = entry['required_capabilities'];
    if (raw is! List<Object?>) {
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        path,
        'Required capabilities must be an array.',
        surfaceId: surfaceId,
      );
    }
    if (raw.length > 32) {
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        path,
        'Required capabilities are bounded to 32 entries.',
        surfaceId: surfaceId,
      );
    }
    final capabilities = <String>{};
    for (var index = 0; index < raw.length; index++) {
      final value = raw[index];
      if (value is! String ||
          textLength(value) > 191 ||
          !_capability.hasMatch(value)) {
        throw _Violation(
          ClientSurfaceRejectionReason.structuralViolation,
          '$path[$index]',
          'A required capability must be a bounded capability identifier.',
          surfaceId: surfaceId,
        );
      }
      if (!capabilities.add(value)) {
        throw _Violation(
          ClientSurfaceRejectionReason.duplicateIdentifier,
          '$path[$index]',
          'A required capability is declared more than once.',
          surfaceId: surfaceId,
        );
      }
    }
    return capabilities;
  }

  Set<ClientBusinessOperation> _readOperations(
    Map<String, Object?> entry,
    String path,
    String surfaceId,
  ) {
    final raw = entry['required_operations'];
    if (raw is! List<Object?>) {
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        path,
        'Required operations must be an array.',
        surfaceId: surfaceId,
      );
    }
    if (raw.length > 16) {
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        path,
        'Required operations are bounded to 16 entries.',
        surfaceId: surfaceId,
      );
    }
    final operations = <ClientBusinessOperation>{};
    for (var index = 0; index < raw.length; index++) {
      final operation = ClientBusinessOperation.tryParse(raw[index]);
      if (operation == null) {
        throw _Violation(
          ClientSurfaceRejectionReason.unknownRequiredVocabulary,
          '$path[$index]',
          'A screen requires an operation this client does not understand.',
          surfaceId: surfaceId,
        );
      }
      if (!operations.add(operation)) {
        throw _Violation(
          ClientSurfaceRejectionReason.duplicateIdentifier,
          '$path[$index]',
          'A required operation is declared more than once.',
          surfaceId: surfaceId,
        );
      }
    }
    return operations;
  }

  LocalizedText _requireLocalizedText(
    Map<String, Object?> object,
    String key,
    String path,
    String? surfaceId,
  ) {
    final value = _optionalLocalizedText(object, key, path, surfaceId);
    if (value == null) {
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        path,
        'Localized text is required here.',
        surfaceId: surfaceId,
      );
    }
    return value;
  }

  LocalizedText? _optionalLocalizedText(
    Map<String, Object?> object,
    String key,
    String path,
    String? surfaceId,
  ) {
    final raw = object[key];
    if (raw == null) {
      _rejectExplicitNull(object, key, path, surfaceId: surfaceId);
      return null;
    }
    if (raw is! Map<String, Object?>) {
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        path,
        'Localized text must be an object.',
        surfaceId: surfaceId,
      );
    }
    _requireClosed(raw, _localizedTextMembers, path, surfaceId: surfaceId);
    final translations = <String, String>{};
    final rawTranslations = raw['translations'];
    if (rawTranslations == null) {
      _rejectExplicitNull(
        raw,
        'translations',
        '$path.translations',
        surfaceId: surfaceId,
      );
    } else {
      if (rawTranslations is! Map<String, Object?>) {
        throw _Violation(
          ClientSurfaceRejectionReason.structuralViolation,
          '$path.translations',
          'Translations must be an object.',
          surfaceId: surfaceId,
        );
      }
      for (final entry in rawTranslations.entries) {
        final value = entry.value;
        if (value is! String) {
          throw _Violation(
            ClientSurfaceRejectionReason.structuralViolation,
            '$path.translations.${entry.key}',
            'A translation must be text.',
            surfaceId: surfaceId,
          );
        }
        translations[entry.key] = value;
      }
    }
    final defaultText = raw['default'];
    if (defaultText is! String) {
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        '$path.default',
        'Localized text must carry default text.',
        surfaceId: surfaceId,
      );
    }
    try {
      return LocalizedText(
        defaultText: defaultText,
        translations: translations,
      );
    } on ArgumentError {
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        path,
        'Localized text exceeds its declared bounds.',
        surfaceId: surfaceId,
      );
    }
  }

  T _requireVocabulary<T>(
    T? parsed,
    String path,
    String label,
    String? surfaceId,
  ) {
    if (parsed == null) {
      throw _Violation(
        ClientSurfaceRejectionReason.unknownRequiredVocabulary,
        path,
        'The declared $label is outside the vocabulary this client reads.',
        surfaceId: surfaceId,
      );
    }
    return parsed;
  }

  void _requireClosed(
    Map<String, Object?> object,
    Set<String> allowed,
    String path, {
    String? surfaceId,
  }) {
    for (final key in object.keys) {
      if (!allowed.contains(key)) {
        throw _Violation(
          ClientSurfaceRejectionReason.structuralViolation,
          '$path.$key',
          'The manifest declares a member this closed object does not allow.',
          surfaceId: surfaceId,
        );
      }
    }
  }

  Map<String, Object?> _requireObject(
    Map<String, Object?> object,
    String key,
    String path, {
    String? surfaceId,
  }) {
    final value = object[key];
    if (value is! Map<String, Object?>) {
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        path,
        'A required object is missing or malformed.',
        surfaceId: surfaceId,
      );
    }
    return value;
  }

  List<Object?> _requireArray(
    Map<String, Object?> object,
    String key,
    String path, {
    required int minItems,
    required int maxItems,
    String? surfaceId,
  }) {
    final value = object[key];
    if (value is! List<Object?>) {
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        path,
        'A required array is missing or malformed.',
        surfaceId: surfaceId,
      );
    }
    if (value.length < minItems || value.length > maxItems) {
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        path,
        'An array carries $minItems to $maxItems entries.',
        surfaceId: surfaceId,
      );
    }
    return value;
  }

  String _requireString(
    Map<String, Object?> object,
    String key,
    String path, {
    required RegExp pattern,
    required int maxLength,
    String? surfaceId,
  }) {
    final value = _optionalString(
      object,
      key,
      path,
      pattern: pattern,
      maxLength: maxLength,
      surfaceId: surfaceId,
    );
    if (value == null) {
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        path,
        'A required value is missing.',
        surfaceId: surfaceId,
      );
    }
    return value;
  }

  /// Refuses a member that is present carrying no value.
  ///
  /// The grammar is closed and declares no nullable member, so an explicit
  /// null is a malformed document rather than an omission. Reading it as
  /// absent would let a screen smuggle past the members its kind forbids.
  void _rejectExplicitNull(
    Map<String, Object?> object,
    String key,
    String path, {
    String? surfaceId,
  }) {
    if (object.containsKey(key)) {
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        path,
        'A member is present carrying no value; the grammar declares no '
        'nullable member.',
        surfaceId: surfaceId,
      );
    }
  }

  String? _optionalString(
    Map<String, Object?> object,
    String key,
    String path, {
    required RegExp pattern,
    required int maxLength,
    String? surfaceId,
  }) {
    final value = object[key];
    if (value == null) {
      _rejectExplicitNull(object, key, path, surfaceId: surfaceId);
      return null;
    }
    if (value is! String ||
        textLength(value) > maxLength ||
        !pattern.hasMatch(value)) {
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        path,
        'A value does not match its declared bounded form.',
        surfaceId: surfaceId,
      );
    }
    return value;
  }

  /// Reads an integer member.
  ///
  /// JSON Schema calls any number with no fractional part an integer, so a
  /// wire value of `10.0` is accepted exactly as `10` is. The range is
  /// checked before conversion, which also rejects the non-finite values.
  int _requireInt(
    Map<String, Object?> object,
    String key,
    String path, {
    required int minimum,
    required int maximum,
    String? surfaceId,
  }) {
    final value = object[key];
    if (value is! num ||
        !(value >= minimum) ||
        !(value <= maximum) ||
        value != value.roundToDouble()) {
      throw _Violation(
        ClientSurfaceRejectionReason.structuralViolation,
        path,
        'An integer is missing or outside $minimum to $maximum.',
        surfaceId: surfaceId,
      );
    }
    return value.toInt();
  }

  static const Set<String> _rootMembers = {
    r'$schema',
    'schema_version',
    'manifest_id',
    'owner',
    'runtime',
    'required_contracts',
    'surfaces',
  };
  static const Set<String> _ownerMembers = {'extension', 'version', 'checksum'};
  static const Set<String> _runtimeMembers = {'generation', 'checksum'};
  static const Set<String> _contractMembers = {'id', 'version_range'};
  static const Set<String> _localizedTextMembers = {'default', 'translations'};
  static const Set<String> _fieldPresentationMembers = {
    'widget',
    'emphasis',
    'width',
  };
  static const Set<String> _navigationMembers = {
    'id',
    'label',
    'screen',
    'order',
    'icon',
    'required_capabilities',
  };
  static const Set<String> _screenMembers = {
    'id',
    'kind',
    'label',
    'description',
    'order',
    'required_capabilities',
    'required_operations',
    'definition',
    'view',
    'mode',
    'report',
    'field_presentations',
  };
  static const Set<String> _surfaceMembers = {
    'id',
    'audience',
    'kind',
    'label',
    'description',
    'order',
    'required_capabilities',
    'unsupported_behavior',
    'navigation',
    'screens',
  };
}

final class _Violation implements Exception {
  _Violation(this.reason, this.path, this.message, {this.surfaceId});

  final ClientSurfaceRejectionReason reason;
  final String path;
  final String message;
  final String? surfaceId;

  ClientSurfaceRejection toRejection({String? fallbackSurfaceId}) {
    return ClientSurfaceRejection(
      reason: reason,
      path: path,
      message: message,
      surfaceId: surfaceId ?? fallbackSurfaceId,
    );
  }
}

final RegExp _namespacedId = RegExp(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+){2,}$');
final RegExp _handle = RegExp(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)+$');
final RegExp _localHandle = RegExp(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$');
final RegExp _capability = RegExp(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)+$');
final RegExp _checksum = RegExp(r'^sha256:[0-9a-f]{64}$');
final RegExp _semanticVersion = RegExp(
  r'^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
);
final RegExp _extensionName = RegExp(
  r'^[a-z][a-z0-9-]{0,62}/[a-z][a-z0-9-]{0,62}$',
);
final RegExp _versionRange = RegExp(r'^[0-9A-Za-z^~<>=.*+| ,_-]{1,80}$');
