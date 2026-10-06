import 'package:url_launcher/url_launcher.dart';

import '../data/us_states.dart';

/// Link-outs to official election information. vote.gov is the federal
/// voter-information site — it carries no ads, no tracking pixel of ours, and
/// the URL we build contains only a state name, never user data.
class CivicLinks {
  CivicLinks._();

  /// `https://vote.gov/register/<hyphenated-state-name>` — e.g.
  /// `vote.gov/register/michigan` or `vote.gov/register/new-hampshire`.
  /// An unknown or unset state falls back to the site root, which opens on a
  /// state picker.
  static Uri voterRegistrationUri(String? stateCode) {
    final name = UsStates.nameFor(stateCode);
    final isReal = UsStates.all.any((s) => s.code == stateCode);
    if (name == null || !isReal) return Uri.parse('https://vote.gov/');
    final slug = name.toLowerCase().replaceAll(' ', '-');
    return Uri.parse('https://vote.gov/register/$slug');
  }

  static Future<bool> openVoterRegistration(
    String? stateCode, {
    Future<bool> Function(Uri uri)? launch,
  }) {
    final opener = launch ?? _launch;
    return opener(voterRegistrationUri(stateCode));
  }

  static Future<bool> _launch(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
