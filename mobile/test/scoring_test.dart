import 'package:flutter_test/flutter_test.dart';
import 'package:voteaxis/models/issue.dart';
import 'package:voteaxis/models/politician.dart';
import 'package:voteaxis/models/question.dart';
import 'package:voteaxis/models/scoring.dart';

void main() {
  final issues = [
    const Issue(id: 'taxes', label: 'Taxes', pillarId: 'economy'),
    const Issue(id: 'jobs', label: 'Jobs', pillarId: 'economy'),
    const Issue(id: 'abortion', label: 'Abortion', pillarId: 'society'),
    const Issue(id: 'healthcare', label: 'Health', pillarId: 'health'),
    const Issue(id: 'immigration', label: 'Immigration', pillarId: 'justice'),
    const Issue(id: 'climate', label: 'Climate', pillarId: 'world'),
  ];

  test('issue scores average shared issues from answers', () {
    final questions = [
      const Question(
        id: 'a',
        issueId: 'immigration',
        text: 'path',
        polarity: -1,
      ),
      const Question(
        id: 'b',
        issueId: 'immigration',
        text: 'border',
        polarity: 1,
      ),
    ];
    final scores = Scoring.issueScoresFromAnswers(
      questions: questions,
      likertIndexes: [3, 3],
    );
    expect(scores['immigration'], 0);
  });

  test('importance pulls the axis toward the weighted issue', () {
    final questions = [
      const Question(id: 'a', issueId: 'taxes', text: 't', polarity: 1),
      const Question(id: 'b', issueId: 'abortion', text: 'a', polarity: -1),
    ];
    // Agree on both: taxes +50, abortion -50. Equal weight → ~0.
    final equal = Scoring.profileFromAnswers(
      questions: questions,
      likertIndexes: const [3, 3],
      issues: issues,
      importanceIndexes: const [2, 2],
    );
    // Abortion marked Essential, taxes Low → axis should go liberal.
    final weighted = Scoring.profileFromAnswers(
      questions: questions,
      likertIndexes: const [3, 3],
      issues: issues,
      importanceIndexes: const [0, 4],
    );
    expect(equal.axisScore.abs() < 8, isTrue);
    expect(weighted.axisScore < equal.axisScore, isTrue);
  });

  test('pillars and equal-weight axis', () {
    final profile = Scoring.profileFromIssueScores(
      issueScores: {
        'taxes': -50,
        'jobs': -50,
        'abortion': -100,
        'healthcare': -50,
        'immigration': 0,
        'climate': -50,
      },
      issues: issues,
    );
    expect(profile.pillarScores['economy'], -50);
    expect(profile.pillarScores['society'], -100);
    expect(profile.axisScore < 0, isTrue);
  });

  test('importance label maps weights back', () {
    expect(Scoring.importanceLabelForWeight(2.5), 'Essential');
    expect(Scoring.importanceLabelForWeight(1.0), 'Average');
    expect(Scoring.importanceLabelForWeight(0.25), 'Low');
  });

  test('civic Venn splits align from who is more liberal', () {
    final self = Scoring.profileFromIssueScores(
      issueScores: const {'taxes': -40, 'abortion': -80, 'healthcare': 10},
      issues: issues,
    );
    final other = Scoring.profileFromIssueScores(
      issueScores: const {'taxes': -30, 'abortion': 20, 'healthcare': -80},
      issues: issues,
    );
    final venn = Scoring.civicVenn(self: self, other: other);
    expect(venn.aligned.map((o) => o.issueId), ['taxes']);
    expect(venn.youMoreLiberal.map((o) => o.issueId), ['abortion']);
    expect(venn.theyMoreLiberal.map((o) => o.issueId), ['healthcare']);
  });

  test('civic Venn treats a hard unique lean as a diverge', () {
    final self = Scoring.profileFromIssueScores(
      issueScores: const {'taxes': -40, 'climate': -80},
      issues: issues,
    );
    final other = Scoring.profileFromIssueScores(
      issueScores: const {'taxes': -30, 'healthcare': -80},
      issues: issues,
    );
    final venn = Scoring.civicVenn(self: self, other: other);
    expect(venn.aligned.map((o) => o.issueId), ['taxes']);
    expect(venn.youMoreLiberal.map((o) => o.issueId), ['climate']);
    expect(venn.theyMoreLiberal.map((o) => o.issueId), ['healthcare']);
  });

  test('compareProfiles story does not invent a diverge', () {
    const self = SpectrumProfile(
      issueScores: {'taxes': -40, 'abortion': -38},
      pillarScores: {},
      axisScore: -40,
    );
    const other = SpectrumProfile(
      issueScores: {'taxes': -30, 'abortion': -20},
      pillarScores: {},
      axisScore: -25,
    );
    final compared = Scoring.compareProfiles(
      self: self,
      other: other,
      issueLabels: const {'taxes': 'Taxes', 'abortion': 'Abortion'},
    );
    expect(compared.agreements.map((o) => o.issueId), ['taxes', 'abortion']);
    expect(compared.disagreements, isEmpty);
    expect(compared.story.toLowerCase(), isNot(contains('diverged')));
  });

  test('closeness is 100 at zero distance', () {
    expect(Scoring.closenessFromDistance(0), 100);
    expect(Scoring.closenessFromDistance(200), 0);
    expect(Scoring.closenessFromDistance(50), 75);
  });

  test('dealbreakers flag large issue gaps', () {
    final hits = Scoring.dealbreakerHits(
      user: const {'abortion': -80},
      politician: const {'abortion': 80},
      dealbreakerIssueIds: const ['abortion'],
    );
    expect(hits, ['abortion']);
  });

  test('rank uses issue weights and reports closeness', () {
    const close = Politician(
      id: 'close',
      name: 'Close',
      role: 'Test',
      party: 'Democratic',
      state: 'MI',
      officeType: 'senator',
      current: true,
      bio: '',
      officeHistory: [],
      issues: {'taxes': -50, 'abortion': -50},
      confidence: {},
      signatureStances: [],
    );
    const far = Politician(
      id: 'far',
      name: 'Far',
      role: 'Test',
      party: 'Republican',
      state: 'TX',
      officeType: 'senator',
      current: true,
      bio: '',
      officeHistory: [],
      issues: {'taxes': 80, 'abortion': 80},
      confidence: {},
      signatureStances: [],
    );
    final user = Scoring.profileFromIssueScores(
      issueScores: const {'taxes': -50, 'abortion': -40},
      issues: issues,
    );
    final ranked = Scoring.rankPoliticians(
      user: user,
      politicians: const [far, close],
      issues: issues,
    );
    expect(ranked.first.politician.id, 'close');
    expect(ranked.first.closeness > ranked.last.closeness, isTrue);
  });

  test('dealbreaker hits sort after other matches', () {
    const closeClash = Politician(
      id: 'clash',
      name: 'Clash',
      role: 'Test',
      party: 'Democratic',
      state: 'MI',
      officeType: 'senator',
      current: true,
      bio: '',
      officeHistory: [],
      issues: {'taxes': -50, 'abortion': 90},
      confidence: {},
      signatureStances: [],
    );
    const farther = Politician(
      id: 'farther',
      name: 'Farther',
      role: 'Test',
      party: 'Republican',
      state: 'TX',
      officeType: 'senator',
      current: true,
      bio: '',
      officeHistory: [],
      issues: {'taxes': 20, 'abortion': -40},
      confidence: {},
      signatureStances: [],
    );
    final user = Scoring.profileFromIssueScores(
      issueScores: const {'taxes': -50, 'abortion': -80},
      issues: issues,
      dealbreakerIssueIds: const ['abortion'],
    );
    final ranked = Scoring.rankPoliticians(
      user: user,
      politicians: const [closeClash, farther],
      issues: issues,
    );
    expect(ranked.first.politician.id, 'farther');
    expect(ranked.last.politician.id, 'clash');
    expect(ranked.last.hasDealbreaker, isTrue);
  });

  test('vector distance and format', () {
    expect(Scoring.vectorDistance({'a': -50, 'b': 0}, {'a': -40, 'b': 20}), 15);
    expect(Scoring.formatScore(-62), 'Liberal 62');
    expect(Scoring.formatScore(40), 'Conservative 40');
    expect(Scoring.formatScore(0), 'Center 0');
    expect(Scoring.labelForScore(-62), 'Strongly liberal');
  });

  test('roll-call blend pulls curated scores with more votes', () {
    expect(Scoring.blendRollcall(curated: -40, rollcall: -100, n: 2), -40);
    final blended = Scoring.blendRollcall(curated: -40, rollcall: -100, n: 6);
    expect(blended < -40, isTrue);
    expect(blended > -100, isTrue);

    const person = Politician(
      id: 'sanders',
      name: 'Bernie Sanders',
      role: 'U.S. Senator (VT)',
      party: 'Independent',
      state: 'VT',
      officeType: 'senator',
      current: true,
      bio: '',
      officeHistory: [],
      issues: {'healthcare': -80, 'taxes': -90},
      confidence: {'healthcare': 'documented'},
      signatureStances: [],
      bioguideId: 'S000033',
    );
    final scored = Scoring.applyRollcall(person, {
      'issues': {'healthcare': -100.0},
      'counts': {'healthcare': 12},
    });
    expect(scored.issues['healthcare']! < -80, isTrue);
    expect(scored.confidence['healthcare'], 'rollcall');
    expect(scored.rollcallCounts['healthcare'], 12);
    expect(scored.issues['taxes'], -90);
    expect(scored.rollcallSessions, isEmpty);
  });

  test(
    'applyRollcall attaches session coordinates without replacing lifetime taxes',
    () {
      const person = Politician(
        id: 's',
        name: 'Bernie Sanders',
        role: 'Senator',
        party: 'Independent',
        state: 'VT',
        officeType: 'senator',
        current: true,
        bio: '',
        officeHistory: [],
        issues: {'healthcare': -80, 'taxes': -90},
        confidence: {'healthcare': 'documented'},
        signatureStances: [],
        bioguideId: 'S000033',
      );
      final scored = Scoring.applyRollcall(person, {
        'issues': {'healthcare': -100.0},
        'counts': {'healthcare': 12},
        'sessions': [
          {
            'congress': 117,
            'year': 2021,
            'label': '117th Congress',
            'axisScore': 40,
            'issues': {'taxes': 40},
            'counts': {'taxes': 3},
            'moves': [
              {
                'issueId': 'taxes',
                'cast': 'Yea',
                'contribution': 100,
                'bill': 'S123',
                'desc': 'Corporate tax cut',
                'url': 'https://voteview.com/rollcall/RS1170001',
              },
            ],
          },
          {
            'congress': 118,
            'year': 2023,
            'label': '118th Congress',
            'axisScore': -80,
            'issues': {'healthcare': -80},
            'counts': {'healthcare': 4},
            'moves': [],
          },
        ],
      });
      expect(scored.hasVoteRecord, isTrue);
      expect(scored.rollcallSessions.first.axisScore, 40);
      expect(scored.rollcallSessions.first.moves.single.bill, 'S123');
      expect(scored.issues['taxes'], -90);
    },
  );

  test(
    'formatScore and labelForScore use Liberal 100 ← 0 → Conservative 100',
    () {
      expect(Scoring.formatScore(0), 'Center 0');
      expect(Scoring.formatScore(-42), 'Liberal 42');
      expect(Scoring.formatScore(52), 'Conservative 52');
      expect(Scoring.labelForScore(0), 'Centrist');
      expect(Scoring.labelForScore(-12), 'Slightly liberal');
      expect(Scoring.labelForScore(40), 'Moderately conservative');
      expect(Scoring.labelForScore(-60), 'Strongly liberal');
      expect(Scoring.labelForScore(90), 'Very conservative');
    },
  );

  test('matchStory names aligned and diverged issues', () {
    const aligned = IssueOverlap(
      issueId: 'taxes',
      diff: 5,
      userScore: -50,
      politicianScore: -45,
    );
    const split = IssueOverlap(
      issueId: 'abortion',
      diff: 90,
      userScore: -80,
      politicianScore: 10,
    );
    expect(
      Scoring.matchStory(
        agreements: const [aligned],
        disagreements: const [split],
        issueLabels: const {'taxes': 'Taxes', 'abortion': 'Abortion'},
      ),
      'You aligned on Taxes, but diverged on Abortion.',
    );
  });

  test('roll-call blend ignores issues with fewer than 3 votes', () {
    const person = Politician(
      id: 'x',
      name: 'X',
      role: 'Test',
      party: 'Democratic',
      state: 'MI',
      officeType: 'senator',
      current: true,
      bio: '',
      officeHistory: [],
      issues: {'taxes': -20},
      confidence: {'taxes': 'documented'},
      signatureStances: [],
    );
    final skipped = Scoring.applyRollcall(person, {
      'issues': {'taxes': 80.0},
      'counts': {'taxes': 2},
    });
    expect(skipped.issues['taxes'], -20);
    expect(skipped.confidence['taxes'], 'documented');
  });

  test('ancestry picks the closest figure below the floor', () {
    const nowPerson = Politician(
      id: 'obama',
      name: 'Barack Obama',
      role: '44th President',
      party: 'Democratic',
      state: '',
      officeType: 'president',
      current: false,
      bio: '',
      officeHistory: ['President of the United States (2009–2017)'],
      issues: {'taxes': -40, 'abortion': -50},
      confidence: {},
      signatureStances: [],
    );
    const reagan = Politician(
      id: 'reagan',
      name: 'Ronald Reagan',
      role: '40th President',
      party: 'Republican',
      state: '',
      officeType: 'president',
      current: false,
      bio: '',
      officeHistory: ['President of the United States (1981–1989)'],
      issues: {'taxes': 80, 'abortion': 80},
      confidence: {},
      signatureStances: [],
    );
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
      issues: {'taxes': -50, 'abortion': -40},
      confidence: {},
      signatureStances: [],
    );
    final roster = [nowPerson, reagan, kennedy];
    expect(
      Scoring.politicalAncestry(
        person: nowPerson,
        roster: roster,
        issues: issues,
        floorYear: FigureFloor.year2000,
      )?.id,
      'jfk',
    );
    expect(
      Scoring.politicalAncestry(
        person: nowPerson,
        roster: roster,
        issues: issues,
        floorYear: FigureFloor.year1980,
      )?.id,
      'jfk',
    );
    expect(
      Scoring.politicalAncestry(
        person: nowPerson,
        roster: roster,
        issues: issues,
        floorYear: FigureFloor.year1960,
      ),
      isNull,
    );
  });

  test(
    'micro-calibration blends a tap into one issue and recalculates the axis',
    () {
      final profile = Scoring.profileFromIssueScores(
        issueScores: const {'taxes': 0, 'jobs': 0},
        issues: issues,
      );
      final agreed = Scoring.applyMicroCalibration(
        profile: profile,
        issues: issues,
        issueId: 'taxes',
        polarity: -1,
        agree: true,
      );
      expect(agreed.issueScores['taxes'], -20);
      expect(agreed.issueScores['jobs'], 0);
      expect(agreed.axisScore, -10);
      expect(agreed.pillarScores['economy'], -10);

      final fresh = Scoring.applyMicroCalibration(
        profile: Scoring.profileFromIssueScores(
          issueScores: const {'jobs': 40},
          issues: issues,
        ),
        issues: issues,
        issueId: 'taxes',
        polarity: -1,
        agree: true,
      );
      expect(fresh.issueScores['taxes'], -45);
    },
  );

  test('steel man appears only for a hard lean on the question\'s side', () {
    const bank = [
      Question(
        id: 'taxes_a',
        issueId: 'taxes',
        text: 't',
        polarity: -1,
        steelManArgument: 'Incentives and incidence.',
      ),
      Question(
        id: 'deficit_a',
        issueId: 'deficit',
        text: 'd',
        polarity: 1,
        steelManArgument: 'Public investment can raise future income.',
      ),
    ];
    expect(
      Scoring.steelManQuestion(
        issueId: 'taxes',
        userScore: -50,
        questions: bank,
      )?.steelManArgument,
      'Incentives and incidence.',
    );
    expect(
      Scoring.steelManQuestion(
        issueId: 'taxes',
        userScore: -40,
        questions: bank,
      ),
      isNull,
    );
    expect(
      Scoring.steelManQuestion(
        issueId: 'taxes',
        userScore: 80,
        questions: bank,
      ),
      isNull,
    );
    expect(
      Scoring.steelManQuestion(
        issueId: 'deficit',
        userScore: 60,
        questions: bank,
      )?.id,
      'deficit_a',
    );
  });

  test('micro-calibration disagree is the opposite Likert pole', () {
    final profile = Scoring.profileFromIssueScores(
      issueScores: const {'taxes': 0},
      issues: issues,
    );
    final disagreed = Scoring.applyMicroCalibration(
      profile: profile,
      issues: issues,
      issueId: 'taxes',
      polarity: -1,
      agree: false,
    );
    expect(disagreed.issueScores['taxes'], 20);
  });

  test('hand-set pillars fan out to every issue in that pillar', () {
    final profile = Scoring.profileFromPillarScores(
      pillarScores: const {
        'economy': 60,
        'society': -40,
        'health': 0,
        'justice': 0,
        'world': 0,
      },
      issues: issues,
    );
    expect(profile.issueScores['taxes'], 60);
    expect(profile.issueScores['jobs'], 60);
    expect(profile.issueScores['abortion'], -40);
    expect(profile.pillarScores['economy'], 60);
    expect(profile.pillarScores['society'], -40);
    // Six issues: two at +60, one at -40, three at 0.
    expect(profile.axisScore, closeTo(80 / 6, 0.001));
  });

  test('hand-set profile ranks politicians like a quiz run', () {
    const left = Politician(
      id: 'left',
      name: 'Left',
      role: 'Senator',
      party: 'Democratic',
      state: 'MI',
      officeType: 'senator',
      current: true,
      bio: '',
      officeHistory: [],
      issues: {'taxes': -70, 'abortion': -70},
      confidence: {},
      signatureStances: [],
    );
    const right = Politician(
      id: 'right',
      name: 'Right',
      role: 'Senator',
      party: 'Republican',
      state: 'MI',
      officeType: 'senator',
      current: true,
      bio: '',
      officeHistory: [],
      issues: {'taxes': 70, 'abortion': 70},
      confidence: {},
      signatureStances: [],
    );
    final ranked = Scoring.rankPoliticians(
      user: Scoring.profileFromPillarScores(
        pillarScores: const {'economy': -80, 'society': -80},
        issues: issues,
      ),
      politicians: const [right, left],
      issues: issues,
    );
    expect(ranked.first.politician.id, 'left');
  });

  test('pillar scores past the ends are clamped to the axis', () {
    final profile = Scoring.profileFromPillarScores(
      pillarScores: const {'economy': 400},
      issues: issues,
    );
    expect(profile.issueScores['taxes'], 100);
    expect(profile.issueScores.containsKey('abortion'), isFalse);
  });
}
