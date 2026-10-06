import 'package:voteaxis/data/app_data.dart';
import 'package:voteaxis/models/issue.dart';
import 'package:voteaxis/models/pillar.dart';
import 'package:voteaxis/models/politician.dart';
import 'package:voteaxis/models/question.dart';
import 'package:voteaxis/models/scoring.dart';

const testIssues = [
  Issue(
    id: 'taxes',
    label: 'Taxes',
    pillarId: 'economy',
    context: 'Who pays, and how much.',
  ),
  Issue(id: 'abortion', label: 'Abortion', pillarId: 'society'),
];

const testPillars = [
  Pillar(id: 'economy', label: 'Economy', description: 'Fiscal policy.'),
  Pillar(id: 'society', label: 'Society', description: 'Rights and culture.'),
];

const testQuestions = [
  Question(
    id: 'taxes_a',
    issueId: 'taxes',
    text: 'Taxes on high earners should go up.',
    polarity: -1,
    steelManArgument:
        'High rates can change the form of income more than the amount collected.',
  ),
  Question(
    id: 'abortion_a',
    issueId: 'abortion',
    text: 'Abortion should remain legal.',
    polarity: -1,
    steelManArgument:
        'If a fetus is a rights-bearing human, the frame is equal protection, not who decides.',
  ),
];

Politician testPolitician({
  String id = 'obama',
  String name = 'Barack Obama',
  String role = '44th President (2009–2017)',
  String party = 'Democratic',
  String state = '',
  String officeType = 'president',
  bool current = false,
  String bio = '44th president.',
  List<String> officeHistory = const [
    'President of the United States (2009–2017)',
  ],
  Map<String, double> issues = const {'taxes': -40, 'abortion': -50},
  Map<String, String> confidence = const {
    'taxes': 'documented',
    'abortion': 'documented',
  },
  List<SignatureStance> signatureStances = const [
    SignatureStance(
      issueId: 'taxes',
      blurb: 'Signed the Affordable Care Act.',
      quote: 'Patient Protection and Affordable Care Act.',
      sourceUrl: 'https://www.congress.gov/bill/111th-congress/house-bill/3590',
    ),
  ],
  String? bioguideId,
  int? district,
  List<RollcallSession> rollcallSessions = const [],
}) {
  return Politician(
    id: id,
    name: name,
    role: role,
    party: party,
    state: state,
    officeType: officeType,
    current: current,
    bio: bio,
    officeHistory: officeHistory,
    issues: issues,
    confidence: confidence,
    signatureStances: signatureStances,
    bioguideId: bioguideId,
    district: district,
    rollcallSessions: rollcallSessions,
  );
}

Politician testSenator({
  String id = 'sanders',
  String name = 'Bernie Sanders',
  String state = 'VT',
}) {
  return testPolitician(
    id: id,
    name: name,
    role: 'U.S. Senator ($state)',
    party: 'Independent',
    state: state,
    officeType: 'senator',
    current: true,
    officeHistory: ['U.S. Senator, $state (2007–present)'],
    issues: const {'taxes': -90, 'abortion': -80},
  );
}

AppData testAppData({List<Politician>? politicians}) {
  return AppData(
    pillars: testPillars,
    issues: testIssues,
    questions: testQuestions,
    politicians: politicians ?? [testPolitician(), testSenator()],
  );
}

SpectrumProfile testProfile({
  Map<String, double> issueScores = const {'taxes': -40, 'abortion': -50},
}) {
  return Scoring.profileFromIssueScores(
    issueScores: issueScores,
    issues: testIssues,
  );
}
