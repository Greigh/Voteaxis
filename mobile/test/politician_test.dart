import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voteaxis/models/politician.dart';

void main() {
  test('generic ingest blurbs are hidden from stance cards', () {
    const generic = SignatureStance(
      issueId: 'taxes',
      blurb: 'Core fiscal and tax posture in the Senate.',
    );
    const real = SignatureStance(
      issueId: 'healthcare',
      blurb: 'Signed the Affordable Care Act.',
      sourceUrl: 'https://www.congress.gov/bill/111th-congress/house-bill/3590',
    );
    expect(generic.isGenericPlaceholder, isTrue);
    expect(real.isGenericPlaceholder, isFalse);
  });

  test('bioguide ids parse for Congress receipts', () {
    final person = Politician.fromJson({
      'id': 'sanders',
      'name': 'Bernie Sanders',
      'role': 'U.S. Senator (VT)',
      'party': 'Independent',
      'state': 'VT',
      'officeType': 'senator',
      'current': true,
      'bio': '',
      'officeHistory': <String>[],
      'issues': <String, int>{},
      'confidence': <String, String>{},
      'signatureStances': <Map<String, String>>[],
      'bioguideId': 'S000033',
    });
    expect(person.bioguideId, 'S000033');
  });

  test('office history years drive era filters', () {
    const reagan = Politician(
      id: 'reagan',
      name: 'Ronald Reagan',
      role: '40th President',
      party: 'Republican',
      state: '',
      officeType: 'president',
      current: false,
      bio: '',
      officeHistory: [
        'Governor of California (1967–1975)',
        'President of the United States (1981–1989)',
      ],
      issues: {},
      confidence: {},
      signatureStances: [],
    );
    expect(reagan.servedDuring(1980, 1989), isTrue);
    expect(reagan.servedDuring(1960, 1969), isTrue);
    expect(reagan.servedDuring(2000, 2009), isFalse);
    expect(reagan.servedSince(FigureFloor.year1980), isTrue);
    expect(reagan.servedSince(FigureFloor.year2000), isFalse);
    expect(reagan.servedSince(FigureFloor.year1960), isTrue);
  });

  test('Kennedy is only on the 1960s plus floor', () {
    const kennedy = Politician(
      id: 'jfk',
      name: 'John F. Kennedy',
      role: '35th President',
      party: 'Democratic',
      state: '',
      officeType: 'president',
      current: false,
      bio: '',
      officeHistory: ['President of the United States (1961–1963)'],
      issues: {},
      confidence: {},
      signatureStances: [],
    );
    expect(kennedy.servedSince(FigureFloor.year1960), isTrue);
    expect(kennedy.servedSince(FigureFloor.year1980), isFalse);
    expect(kennedy.servedSince(FigureFloor.year2000), isFalse);
  });

  test('sitting members always pass every floor', () {
    final person = Politician.fromJson({
      'id': 'sanders',
      'name': 'Bernie Sanders',
      'role': 'U.S. Senator (VT)',
      'party': 'Independent',
      'state': 'VT',
      'officeType': 'senator',
      'current': true,
      'bio': '',
      'officeHistory': <String>[],
      'issues': <String, int>{},
      'confidence': <String, String>{},
      'signatureStances': <Map<String, String>>[],
    });
    expect(person.servedSince(FigureFloor.year2000), isTrue);
    expect(person.servedSince(FigureFloor.year1960), isTrue);
  });

  test('figure floor coerces unknown years to 2000s plus', () {
    expect(FigureFloor.coerce(2000), FigureFloor.year2000);
    expect(FigureFloor.coerce(1980), FigureFloor.year1980);
    expect(FigureFloor.coerce(1960), FigureFloor.year1960);
    expect(FigureFloor.coerce(1999), FigureFloor.year2000);
    expect(FigureFloor.showsPastUi(FigureFloor.year2000), isFalse);
    expect(FigureFloor.showsPastUi(FigureFloor.year1980), isTrue);
    expect(FigureFloor.showsHistoricalQuiz(FigureFloor.year1960), isTrue);
    expect(FigureFloor.showsHistoricalQuiz(FigureFloor.year1980), isFalse);
  });

  test('time-blind role strips years and ordinals', () {
    const person = Politician(
      id: 'reagan',
      name: 'Ronald Reagan',
      role: '40th President (1981–1989)',
      party: 'Republican',
      state: '',
      officeType: 'president',
      current: false,
      bio: '',
      officeHistory: [],
      issues: {},
      confidence: {},
      signatureStances: [],
    );
    expect(person.eraBlindRole.contains('1981'), isFalse);
    expect(person.eraBlindRole.contains('40th'), isFalse);
    expect(person.eraBlindRole, contains('President'));
  });

  test('profileConfidence rolls up the per-issue confidence map', () {
    Politician withConf(Map<String, String> conf) => Politician.fromJson({
      'id': 'x',
      'name': 'X',
      'role': 'r',
      'party': 'p',
      'state': 'CA',
      'officeType': 'other',
      'current': true,
      'bio': '',
      'officeHistory': <String>[],
      'issues': {for (final k in conf.keys) k: 0},
      'confidence': conf,
      'signatureStances': <Map<String, String>>[],
    });

    final allDoc = {for (var i = 0; i < 22; i++) 'i$i': 'documented'};
    expect(withConf(allDoc).profileConfidence, 'documented');

    final allInf = {for (var i = 0; i < 22; i++) 'i$i': 'inferred'};
    expect(withConf(allInf).profileConfidence, 'inferred');

    final mixed = {
      for (var i = 0; i < 22; i++) 'i$i': i < 19 ? 'documented' : 'inferred',
    };
    expect(withConf(mixed).profileConfidence, 'mixed');

    // rollcall counts as grounded, like documented.
    final rollcall = {for (var i = 0; i < 22; i++) 'i$i': 'rollcall'};
    expect(withConf(rollcall).profileConfidence, 'documented');

    expect(withConf(const {}).profileConfidence, 'inferred');

    // A short documented "lane" still reads as an inferred profile overall,
    // but the note acknowledges the grounded issues.
    final lane = {
      for (var i = 0; i < 22; i++) 'i$i': i < 4 ? 'documented' : 'inferred',
    };
    expect(withConf(lane).profileConfidence, 'inferred');
    expect(withConf(lane).profileConfidenceNote, contains('few issues'));
    expect(withConf(allInf).profileConfidenceNote, contains('not itemized'));
  });

  test('bundled roster keeps stance sourcing aligned with issue confidence', () {
    final raw = File('assets/data/politicians.json').readAsStringSync();
    for (final row in jsonDecode(raw) as List<dynamic>) {
      final person = Politician.fromJson(row as Map<String, dynamic>);
      // A profile that is documented or mixed must have at least one issue
      // that is not inferred.
      if (person.profileConfidence != 'inferred') {
        expect(
          person.confidence.values.any((v) => v != 'inferred'),
          isTrue,
          reason: person.id,
        );
      }
    }
  });

  test('documented signature stances carry a quote and public sourceUrl', () {
    final raw = File('assets/data/politicians.json').readAsStringSync();
    final list = jsonDecode(raw) as List<dynamic>;
    final sourced = <String>[];
    for (final row in list) {
      final person = Politician.fromJson(row as Map<String, dynamic>);
      for (final stance in person.displayStances) {
        if (stance.sourceUrl != null && stance.quote != null) {
          sourced.add('${person.id}:${stance.issueId}');
          expect(stance.sourceUrl, startsWith('http'));
          expect(stance.quote, isNotEmpty);
        }
      }
    }
    expect(sourced, contains('donald_trump:taxes'));
    expect(sourced, contains('ron_desantis:education'));
    expect(sourced, contains('jfk:civil_rights'));
    expect(sourced, contains('mitt_romney:healthcare'));
    expect(sourced.length, greaterThanOrEqualTo(40));
  });
}
