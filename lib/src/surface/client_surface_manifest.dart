import 'client_surface_vocabulary.dart';

/// Length of [value] in Unicode code points.
///
/// JSON Schema counts string length in code points, while Dart's
/// `String.length` counts UTF-16 code units. Using the latter would refuse a
/// perfectly valid label written in a non-BMP script at roughly half its
/// declared bound.
int textLength(String value) => value.runes.length;

/// Plain display text with bounded translations and a required default.
///
/// Manifest text is always plain text. It is never markup, never a template
/// and never an expression, so a host renders it as a string without
/// interpreting anything inside it.
final class LocalizedText {
  /// Creates validated localized text.
  factory LocalizedText({
    required String defaultText,
    Map<String, String> translations = const {},
  }) {
    if (defaultText.isEmpty || textLength(defaultText) > 500) {
      throw ArgumentError.value(
        defaultText,
        'defaultText',
        'Localized text carries 1 to 500 characters.',
      );
    }
    if (translations.length > 16 ||
        translations.entries.any(
          (entry) =>
              textLength(entry.key) > 35 ||
              !_localePattern.hasMatch(entry.key) ||
              entry.value.isEmpty ||
              textLength(entry.value) > 500,
        )) {
      throw ArgumentError.value(
        translations,
        'translations',
        'Translations are up to 16 language tags of at most 35 characters '
            'mapped to 1 to 500 characters.',
      );
    }
    return LocalizedText._(defaultText, Map.unmodifiable(translations));
  }

  const LocalizedText._(this.defaultText, this.translations);

  /// Text used when no translation matches.
  final String defaultText;

  /// Bounded language-tag to text map.
  final Map<String, String> translations;

  /// Returns the best text for [locale], falling back to less specific tags
  /// and finally to [defaultText].
  ///
  /// Matching is case-insensitive and truncates one subtag at a time, so
  /// `en-NA` resolves against `en-NA`, then `en`, then the default.
  String resolve(String? locale) {
    if (locale == null || translations.isEmpty) {
      return defaultText;
    }
    final lowered = {
      for (final entry in translations.entries)
        entry.key.toLowerCase(): entry.value,
    };
    var candidate = locale.toLowerCase();
    while (candidate.isNotEmpty) {
      final match = lowered[candidate];
      if (match != null) {
        return match;
      }
      final separator = candidate.lastIndexOf('-');
      if (separator < 0) {
        break;
      }
      candidate = candidate.substring(0, separator);
    }
    return defaultText;
  }

  @override
  String toString() => 'LocalizedText($defaultText)';

  static final RegExp _localePattern = RegExp(
    r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$',
  );
}

/// The extension package that owns a manifest.
final class ClientSurfaceOwner {
  /// Creates an owner descriptor from validated wire data.
  const ClientSurfaceOwner({
    required this.extension,
    required this.version,
    required this.checksum,
  });

  /// Owning package in `vendor/name` form.
  final String extension;

  /// Owning package semantic version.
  final String version;

  /// `sha256:` digest of the owning package release.
  final String checksum;

  @override
  String toString() => 'ClientSurfaceOwner($extension@$version)';
}

/// The trusted runtime generation a manifest is bound to.
///
/// A cached manifest is only valid while the server reports this generation
/// and checksum; either changing invalidates it.
final class ClientSurfaceRuntime {
  /// Creates a runtime binding from validated wire data.
  const ClientSurfaceRuntime({
    required this.generation,
    required this.checksum,
  });

  /// Monotonic trusted-runtime generation.
  final int generation;

  /// `sha256:` digest of the effective runtime contribution set.
  final String checksum;

  @override
  String toString() => 'ClientSurfaceRuntime(generation: $generation)';
}

/// A contract the manifest requires the host to support.
final class ClientSurfaceContractRequirement {
  /// Creates a contract requirement from validated wire data.
  const ClientSurfaceContractRequirement({
    required this.id,
    required this.versionRange,
  });

  /// Stable contract identifier.
  final String id;

  /// Version range expression the host must satisfy.
  final String versionRange;

  @override
  String toString() => 'ClientSurfaceContractRequirement($id $versionRange)';
}

/// How one field is presented on a screen.
final class ClientFieldPresentation {
  /// Creates a field presentation from validated wire data.
  const ClientFieldPresentation({
    required this.widget,
    this.emphasis,
    this.width,
  });

  /// Semantic control the value is presented with.
  final ClientFieldWidget widget;

  /// Optional prominence hint; `null` when absent or not understood.
  final ClientFieldEmphasis? emphasis;

  /// Optional width hint; `null` when absent or not understood.
  final ClientFieldWidth? width;

  @override
  String toString() => 'ClientFieldPresentation(${widget.wireName})';
}

/// One navigation entry inside a surface.
final class ClientSurfaceNavigationItem {
  /// Creates a navigation item from validated wire data.
  ClientSurfaceNavigationItem({
    required this.id,
    required this.label,
    required this.screen,
    required this.order,
    required Set<String> requiredCapabilities,
    this.icon,
  }) : requiredCapabilities = Set.unmodifiable(requiredCapabilities);

  /// Namespaced navigation item identifier.
  final String id;

  /// Plain display label.
  final LocalizedText label;

  /// Identifier of a screen declared by the same surface.
  final String screen;

  /// Sort order within the surface.
  final int order;

  /// Optional semantic icon; `null` when absent or not understood.
  final ClientNavigationIcon? icon;

  /// Capabilities the item needs; never a grant, only a requirement.
  final Set<String> requiredCapabilities;

  @override
  String toString() => 'ClientSurfaceNavigationItem($id -> $screen)';
}

/// One screen declared by a surface.
final class ClientSurfaceScreen {
  /// Creates a screen from validated wire data.
  ClientSurfaceScreen({
    required this.id,
    required this.kind,
    required this.label,
    required this.order,
    required Set<String> requiredCapabilities,
    required Set<ClientBusinessOperation> requiredOperations,
    required Map<String, ClientFieldPresentation> fieldPresentations,
    this.description,
    this.definition,
    this.view,
    this.mode,
    this.report,
  }) : requiredCapabilities = Set.unmodifiable(requiredCapabilities),
       requiredOperations = Set.unmodifiable(requiredOperations),
       fieldPresentations = Map.unmodifiable(fieldPresentations);

  /// Namespaced screen identifier.
  final String id;

  /// What the screen presents.
  final ClientScreenKind kind;

  /// Plain display label.
  final LocalizedText label;

  /// Optional plain description.
  final LocalizedText? description;

  /// Sort order within the surface.
  final int order;

  /// Capabilities the screen needs; never a grant, only a requirement.
  final Set<String> requiredCapabilities;

  /// Generated-business operations the screen depends on.
  final Set<ClientBusinessOperation> requiredOperations;

  /// Business definition handle, for every kind except `report`.
  final String? definition;

  /// Custom view handle, for `document` screens.
  final String? view;

  /// Mutation performed, for `form` screens.
  final ClientFormMode? mode;

  /// Report handle, for `report` screens.
  final String? report;

  /// Field presentation hints keyed by field handle.
  final Map<String, ClientFieldPresentation> fieldPresentations;

  @override
  String toString() => 'ClientSurfaceScreen($id, ${kind.wireName})';
}

/// One policy-filtered extension-owned surface.
final class ClientSurface {
  /// Creates a surface from validated wire data.
  ClientSurface({
    required this.id,
    required this.audience,
    required this.kind,
    required this.label,
    required this.order,
    required Set<String> requiredCapabilities,
    required this.unsupportedBehavior,
    required List<ClientSurfaceNavigationItem> navigation,
    required List<ClientSurfaceScreen> screens,
    this.description,
  }) : requiredCapabilities = Set.unmodifiable(requiredCapabilities),
       navigation = List.unmodifiable(navigation),
       screens = List.unmodifiable(screens);

  /// Namespaced surface identifier.
  final String id;

  /// Who the surface is served to.
  final ClientSurfaceAudience audience;

  /// Whether the surface is a workspace or a module.
  final ClientSurfaceKind kind;

  /// Plain display label.
  final LocalizedText label;

  /// Optional plain description.
  final LocalizedText? description;

  /// Sort order among surfaces.
  final int order;

  /// Capabilities the surface needs; never a grant, only a requirement.
  final Set<String> requiredCapabilities;

  /// What a host does when the surface's requirements are unmet.
  final ClientUnsupportedBehavior unsupportedBehavior;

  /// Navigation entries, each pointing at a screen of this surface.
  final List<ClientSurfaceNavigationItem> navigation;

  /// Screens this surface declares.
  final List<ClientSurfaceScreen> screens;

  /// Returns the screen with [screenId], or `null` when absent.
  ClientSurfaceScreen? screen(String screenId) {
    for (final candidate in screens) {
      if (candidate.id == screenId) {
        return candidate;
      }
    }
    return null;
  }

  @override
  String toString() => 'ClientSurface($id, ${audience.wireName})';
}

/// An interpreted extension client-surface manifest.
///
/// Only surfaces that were fully understood appear in [surfaces]. A manifest
/// whose surfaces were all rejected is still returned, with an empty list, so
/// a caller can distinguish "nothing admitted" from "nothing declared".
final class ClientSurfaceManifest {
  /// Creates a manifest from validated wire data.
  ClientSurfaceManifest({
    required this.schemaVersion,
    required this.manifestId,
    required this.owner,
    required this.runtime,
    required List<ClientSurfaceContractRequirement> requiredContracts,
    required List<ClientSurface> surfaces,
  }) : requiredContracts = List.unmodifiable(requiredContracts),
       surfaces = List.unmodifiable(surfaces);

  /// Manifest schema version.
  final int schemaVersion;

  /// Namespaced manifest identifier.
  final String manifestId;

  /// Owning extension package.
  final ClientSurfaceOwner owner;

  /// Trusted runtime binding this manifest is valid for.
  final ClientSurfaceRuntime runtime;

  /// Contracts the host must support.
  final List<ClientSurfaceContractRequirement> requiredContracts;

  /// Surfaces that were fully understood and admitted.
  final List<ClientSurface> surfaces;

  /// Surfaces for [audience], in declared order.
  List<ClientSurface> surfacesFor(ClientSurfaceAudience audience) => [
    for (final surface in surfaces)
      if (surface.audience == audience) surface,
  ];

  @override
  String toString() =>
      'ClientSurfaceManifest($manifestId, ${surfaces.length} surfaces)';
}
