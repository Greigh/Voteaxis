/// Compile-time API and site roots. Override per device:
/// `flutter run --dart-define=VOTEAXIS_API_URL=http://127.0.0.1:8787`
/// `flutter run --dart-define=VOTEAXIS_SITE_URL=http://127.0.0.1:3000`
class AppConfig {
  AppConfig._();

  static const apiBase = String.fromEnvironment(
    'VOTEAXIS_API_URL',
    defaultValue: 'https://api.voteaxis.org',
  );

  static const siteBase = String.fromEnvironment(
    'VOTEAXIS_SITE_URL',
    defaultValue: 'https://voteaxis.org',
  );

  /// `/v1/politicians` is personal-only for now — see server/README.md.
  /// Empty by default, so a build with no dart-define just gets 401s from
  /// that one endpoint (and keeps using its bundled/cached roster) rather
  /// than failing to build. Set it to the same value as the server's
  /// `POLITICIANS_API_KEY`:
  /// `flutter run --dart-define=VOTEAXIS_POLITICIANS_KEY=<value>`
  ///
  /// A value compiled in here is not a secret once the app ships — it can be
  /// pulled back out of the binary. Fine while this is your own device only;
  /// opening the roster to every install needs a different mechanism (an
  /// authenticated proxy, a per-install token, ...), not a wider audience for
  /// this same dart-define.
  static const politiciansKey = String.fromEnvironment(
    'VOTEAXIS_POLITICIANS_KEY',
  );

  static String get contributeUrl => '$siteBase/contribute';
}
