import 'package:flutter_test/flutter_test.dart';
import 'package:voteaxis/models/scoring.dart';
import 'package:voteaxis/services/voteaxis_api.dart';

void main() {
  test('remote profile maps onto SpectrumProfile', () {
    final remote = RemoteProfile.fromJson({
      'code': 'A2B3C4',
      'displayName': 'Alex',
      'axisScore': -40,
      'issueScores': {'taxes': -50, 'abortion': -10},
      'issueWeights': {'taxes': 2.5},
      'pillarScores': {'economy': -50},
      'dealbreakerIssueIds': ['abortion'],
    });
    expect(remote.label, 'Alex');
    final profile = remote.toProfile();
    expect(profile.axisScore, -40);
    expect(profile.issueWeights['taxes'], 2.5);
    expect(remote.dealbreakerIssueIds, ['abortion']);
  });

  test('congress receipts parse sponsored bills', () {
    final receipts = CongressReceipts.fromJson({
      'bioguideId': 'S000033',
      'memberUrl': 'https://bioguide.congress.gov/search/bio/S000033',
      'sponsored': [
        {
          'kind': 'sponsored',
          'congress': 118,
          'type': 'S',
          'number': '1655',
          'title': 'Medicare for All Act',
          'url':
              'https://www.congress.gov/bill/118th-congress/senate-bill/1655',
        },
      ],
      'cosponsored': [],
    });
    expect(receipts.sponsored.single.citation, 'S 1655 · 118th');
    expect(receipts.sponsored.single.summary, isNull);
    expect(receipts.isEmpty, isFalse);

    final numeric = CongressBill.fromJson({
      'kind': 'sponsored',
      'congress': 118,
      'type': 'HR',
      'number': 3392,
      'title': 'AREA Act',
      'url': 'https://www.congress.gov/bill/118th-congress/house-bill/3392',
      'introducedDate': '',
    });
    expect(numeric.citation, 'H.R. 3392 · 118th');
    expect(numeric.introducedDate, isNull);
  });

  test('compareProfiles reports closeness and a story', () {
    const self = SpectrumProfile(
      issueScores: {'taxes': -50, 'abortion': -80},
      pillarScores: {},
      axisScore: -60,
    );
    const other = SpectrumProfile(
      issueScores: {'taxes': -40, 'abortion': 70},
      pillarScores: {},
      axisScore: 20,
    );
    final compared = Scoring.compareProfiles(
      self: self,
      other: other,
      issueLabels: const {'taxes': 'Taxes', 'abortion': 'Abortion'},
    );
    expect(compared.closeness < 100, isTrue);
    expect(compared.story.toLowerCase(), contains('abortion'));
  });
}
