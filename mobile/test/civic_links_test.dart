import 'package:flutter_test/flutter_test.dart';
import 'package:voteaxis/data/us_states.dart';
import 'package:voteaxis/services/civic_links.dart';

void main() {
  group('voterRegistrationUri', () {
    test('state pages are the hyphenated lowercase name', () {
      expect(
        CivicLinks.voterRegistrationUri('MI').toString(),
        'https://vote.gov/register/michigan',
      );
      expect(
        CivicLinks.voterRegistrationUri('NY').toString(),
        'https://vote.gov/register/new-york',
      );
      expect(
        CivicLinks.voterRegistrationUri('DC').toString(),
        'https://vote.gov/register/district-of-columbia',
      );
    });

    test('every covered state code produces a https vote.gov URL', () {
      for (final s in UsStates.all) {
        final uri = CivicLinks.voterRegistrationUri(s.code);
        expect(uri.scheme, 'https');
        expect(uri.host, 'vote.gov');
        expect(uri.pathSegments.first, 'register');
        expect(uri.pathSegments.last, isNotEmpty);
      }
    });

    test('unknown or unset codes fall back to the site root', () {
      expect(
        CivicLinks.voterRegistrationUri(null).toString(),
        'https://vote.gov/',
      );
      expect(
        CivicLinks.voterRegistrationUri('XX').toString(),
        'https://vote.gov/',
      );
    });

    test('the URL carries no user data — only a state name', () {
      final uri = CivicLinks.voterRegistrationUri('MI');
      expect(uri.queryParameters, isEmpty);
      expect(uri.fragment, isEmpty);
      expect(uri.path.contains('register'), isTrue);
    });
  });

  test('openVoterRegistration launches the state URL', () async {
    Uri? opened;
    await CivicLinks.openVoterRegistration(
      'MI',
      launch: (uri) async {
        opened = uri;
        return true;
      },
    );
    expect(opened.toString(), 'https://vote.gov/register/michigan');
  });
}
