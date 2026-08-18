/// The server-reported lifecycle state of the authenticated account.
///
/// An authentication link signs in unknown addresses too: they arrive as
/// pending guests with the minimum capability set, the client shows its
/// arrival page, and an authorized administrator positions the account in
/// core's own UI. The state is server truth from the token response; the
/// client renders it and never asserts a transition itself.
enum KumweAccountState {
  /// The account is positioned and holds its granted capabilities.
  active('active'),

  /// The account arrived as a guest and awaits positioning; only the
  /// arrival experience is available until the server reports otherwise.
  pending('pending');

  const KumweAccountState(this.wireValue);

  /// Exact lowercase value used on the wire for this state.
  final String wireValue;

  /// Parses a wire value, throwing [FormatException] for unknown states.
  ///
  /// Unknown states fail closed rather than defaulting to broader access.
  static KumweAccountState parse(String value) {
    for (final state in values) {
      if (state.wireValue == value) {
        return state;
      }
    }
    throw FormatException('Unknown Kumwe account state.', value);
  }
}
