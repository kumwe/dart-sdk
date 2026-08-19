/// Closed vocabularies of the proposed extension client-surface contract.
///
/// Every vocabulary below is closed by the manifest schema. Parsing returns
/// `null` for a value outside its vocabulary rather than guessing, so the
/// interpreter can fail a surface closed where the value is required and drop
/// only the hint where the value is an optional presentation preference.
library;

/// Who a surface is served to.
enum ClientSurfaceAudience {
  /// Authenticated administrator surface.
  administrator('administrator'),

  /// Authenticated portal surface.
  portal('portal');

  const ClientSurfaceAudience(this.wireName);

  /// Value as it appears on the wire.
  final String wireName;

  /// Returns the audience for [value], or `null` when it is outside the
  /// vocabulary.
  static ClientSurfaceAudience? tryParse(Object? value) =>
      _byWireName(values, value, (item) => item.wireName);
}

/// Whether a surface is a top-level workspace or a module inside one.
enum ClientSurfaceKind {
  /// A top-level navigable workspace.
  workspace('workspace'),

  /// A module grouped inside a workspace.
  module('module');

  const ClientSurfaceKind(this.wireName);

  /// Value as it appears on the wire.
  final String wireName;

  /// Returns the kind for [value], or `null` when it is outside the
  /// vocabulary.
  static ClientSurfaceKind? tryParse(Object? value) =>
      _byWireName(values, value, (item) => item.wireName);
}

/// What a screen presents.
enum ClientScreenKind {
  /// A bounded list over one business definition.
  collection('collection'),

  /// One business record.
  record('record'),

  /// A create or update form over one business definition.
  form('form'),

  /// A header-plus-owned-lines document view.
  document('document'),

  /// A parameterized report.
  report('report');

  const ClientScreenKind(this.wireName);

  /// Value as it appears on the wire.
  final String wireName;

  /// Returns the screen kind for [value], or `null` when it is outside the
  /// vocabulary.
  static ClientScreenKind? tryParse(Object? value) =>
      _byWireName(values, value, (item) => item.wireName);
}

/// What a host does with a surface whose requirements are unmet.
enum ClientUnsupportedBehavior {
  /// Omit the surface entirely.
  hide('hide'),

  /// Show the surface as present but unavailable.
  showUnavailable('show_unavailable');

  const ClientUnsupportedBehavior(this.wireName);

  /// Value as it appears on the wire.
  final String wireName;

  /// Returns the behavior for [value], or `null` when it is outside the
  /// vocabulary.
  static ClientUnsupportedBehavior? tryParse(Object? value) =>
      _byWireName(values, value, (item) => item.wireName);
}

/// Which mutation a form screen performs.
enum ClientFormMode {
  /// The form creates a new record.
  create('create'),

  /// The form updates an existing record.
  update('update');

  const ClientFormMode(this.wireName);

  /// Value as it appears on the wire.
  final String wireName;

  /// Returns the mode for [value], or `null` when it is outside the
  /// vocabulary.
  static ClientFormMode? tryParse(Object? value) =>
      _byWireName(values, value, (item) => item.wireName);
}

/// Semantic icon hint for a navigation item.
///
/// The vocabulary is closed and semantic: it names what an item is for, never
/// an image path, URL or glyph the host would have to fetch.
enum ClientNavigationIcon {
  /// Landing or overview destination.
  home('home'),

  /// A record collection.
  records('records'),

  /// A document.
  document('document'),

  /// A report.
  report('report'),

  /// Configuration.
  settings('settings'),

  /// People or parties.
  people('people'),

  /// Dates and scheduling.
  calendar('calendar'),

  /// Stock or inventory.
  inventory('inventory'),

  /// Monetary information.
  money('money'),

  /// Work items and tasks.
  task('task'),

  /// Search.
  search('search');

  const ClientNavigationIcon(this.wireName);

  /// Value as it appears on the wire.
  final String wireName;

  /// Returns the icon for [value], or `null` when it is outside the
  /// vocabulary.
  static ClientNavigationIcon? tryParse(Object? value) =>
      _byWireName(values, value, (item) => item.wireName);
}

/// Semantic control a field is presented with.
///
/// A widget names the meaning of a value, not a rendering implementation. The
/// host owns every accessible control that realizes it.
enum ClientFieldWidget {
  /// Single-line text.
  text('text'),

  /// Multi-line plain text.
  multilineText('multiline_text'),

  /// Structured rich text.
  richText('rich_text'),

  /// Whole number.
  integer('integer'),

  /// Exact decimal carried as a canonical string.
  decimal('decimal'),

  /// Exact money carried as a closed amount and currency pair.
  money('money'),

  /// Exact quantity carried as a closed amount and unit pair.
  quantity('quantity'),

  /// Boolean.
  boolean('boolean'),

  /// One value from a bounded choice list.
  choice('choice'),

  /// Calendar date.
  date('date'),

  /// Time of day.
  time('time'),

  /// Absolute instant.
  instant('instant'),

  /// Email address.
  email('email'),

  /// Absolute URL.
  url('url'),

  /// Telephone number.
  phone('phone'),

  /// Reference to a media item.
  mediaReference('media_reference'),

  /// Reference to another business record.
  entityReference('entity_reference'),

  /// Nested composite value.
  object('object'),

  /// Repeated value.
  collection('collection'),

  /// Write-only secret that is never prefilled.
  secret('secret'),

  /// Server-computed read-only output.
  output('output');

  const ClientFieldWidget(this.wireName);

  /// Value as it appears on the wire.
  final String wireName;

  /// Whether the widget is never prefilled from a read.
  bool get isSecret => this == ClientFieldWidget.secret;

  /// Whether the widget is server-owned and not accepted as input.
  bool get isReadOnly => this == ClientFieldWidget.output;

  /// Returns the widget for [value], or `null` when it is outside the
  /// vocabulary.
  static ClientFieldWidget? tryParse(Object? value) =>
      _byWireName(values, value, (item) => item.wireName);
}

/// Relative prominence hint for a presented field.
enum ClientFieldEmphasis {
  /// Default prominence.
  normal('normal'),

  /// Raised prominence.
  primary('primary'),

  /// Reduced prominence.
  secondary('secondary');

  const ClientFieldEmphasis(this.wireName);

  /// Value as it appears on the wire.
  final String wireName;

  /// Returns the emphasis for [value], or `null` when it is outside the
  /// vocabulary.
  static ClientFieldEmphasis? tryParse(Object? value) =>
      _byWireName(values, value, (item) => item.wireName);
}

/// Relative width hint for a presented field.
enum ClientFieldWidth {
  /// Full available width.
  full('full'),

  /// Half the available width.
  half('half'),

  /// A third of the available width.
  third('third');

  const ClientFieldWidth(this.wireName);

  /// Value as it appears on the wire.
  final String wireName;

  /// Returns the width for [value], or `null` when it is outside the
  /// vocabulary.
  static ClientFieldWidth? tryParse(Object? value) =>
      _byWireName(values, value, (item) => item.wireName);
}

/// A generated-business operation a screen depends on.
///
/// The server remains the authority: a listed operation is what the screen
/// needs in order to function, never a grant.
enum ClientBusinessOperation {
  /// Definition discovery.
  discover('discover'),

  /// Bounded collection browse or search.
  browse('browse'),

  /// Single record read.
  read('read'),

  /// Record creation.
  create('create'),

  /// Record update.
  update('update'),

  /// Record deletion.
  delete('delete'),

  /// Lifecycle archive.
  archive('archive'),

  /// Lifecycle restore.
  restore('restore'),

  /// Revision history read.
  history('history'),

  /// Published custom action execution.
  action('action'),

  /// Relation browse or mutation.
  relation('relation'),

  /// Approval request.
  approval('approval'),

  /// Report execution.
  report('report');

  const ClientBusinessOperation(this.wireName);

  /// Value as it appears on the wire.
  final String wireName;

  /// Returns the operation for [value], or `null` when it is outside the
  /// vocabulary.
  static ClientBusinessOperation? tryParse(Object? value) =>
      _byWireName(values, value, (item) => item.wireName);
}

/// Resolves [wire] against [values] by wire name, or `null` when unknown.
T? _byWireName<T>(List<T> values, Object? wire, String Function(T) nameOf) {
  if (wire is! String) {
    return null;
  }
  for (final value in values) {
    if (nameOf(value) == wire) {
      return value;
    }
  }
  return null;
}
