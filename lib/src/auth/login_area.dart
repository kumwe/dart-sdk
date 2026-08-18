/// The sign-in area a credential is requested for and bound to.
///
/// Kumwe deployments expose two authenticated areas — the administrative
/// area and the portal — as separate session boundaries on the web. A native
/// credential carries exactly one area binding: the client selects the area
/// before requesting an authentication link, and the issued credential never
/// reaches resources of the other area. The server reports the bound area in
/// its token response; the client never infers it.
enum KumweLoginArea {
  /// The administrative area.
  administrator('administrator'),

  /// The portal area.
  portal('portal');

  const KumweLoginArea(this.wireValue);

  /// Exact lowercase value used on the wire for this area.
  final String wireValue;

  /// Parses a wire value, throwing [FormatException] for unknown areas.
  ///
  /// Unknown areas fail closed: a client never guesses a sign-in target the
  /// server did not name.
  static KumweLoginArea parse(String value) {
    for (final area in values) {
      if (area.wireValue == value) {
        return area;
      }
    }
    throw FormatException('Unknown Kumwe login area.', value);
  }
}
