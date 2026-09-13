import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/issue.dart';
import '../models/pillar.dart';
import '../models/politician.dart';
import '../models/question.dart';
import '../models/scoring.dart';
import '../services/device_token.dart';
import '../services/politicians_cache.dart';
import '../services/voteaxis_api.dart';

class AppData {
  AppData({
    required this.pillars,
    required this.issues,
    required this.questions,
    required this.politicians,
  });

  final List<Pillar> pillars;
  final List<Issue> issues;
  final List<Question> questions;
  final List<Politician> politicians;

  Map<String, Issue> get issuesById => {for (final i in issues) i.id: i};

  Map<String, Pillar> get pillarsById => {for (final p in pillars) p.id: p};

  SpectrumProfile profileFor(Politician politician) {
    return Scoring.profileFromPolitician(
      politician: politician,
      issues: issues,
    );
  }

  /// A copy with [politicians] swapped — everything else (issues, pillars,
  /// the quiz bank) is unaffected by a roster refresh.
  AppData withPoliticians(List<Politician> politicians) => AppData(
    pillars: pillars,
    issues: issues,
    questions: questions,
    politicians: politicians,
  );

  static Future<Map<String, dynamic>> _loadRollcallOverlay() async {
    try {
      final rollcallRaw = await rootBundle.loadString(
        'assets/data/rollcall_scores.json',
      );
      final decoded = jsonDecode(rollcallRaw);
      if (decoded is Map) {
        final members = decoded['members'];
        if (members is Map) return Map<String, dynamic>.from(members);
      }
    } catch (_) {
      // Overlay is optional until scripts/score_rollcalls.py has been run.
    }
    return const {};
  }

  static List<Politician> _decodePoliticians(
    String raw,
    Map<String, dynamic> overlay,
  ) {
    return (jsonDecode(raw) as List<dynamic>).map((e) {
      final person = Politician.fromJson(e as Map<String, dynamic>);
      final bio = person.bioguideId;
      if (bio == null) return person;
      final member = overlay[bio] ?? overlay[bio.toUpperCase()];
      if (member is! Map) return person;
      return Scoring.applyRollcall(person, Map<String, dynamic>.from(member));
    }).toList();
  }

  static Future<AppData> load({PoliticiansCache? cache}) async {
    final pillarsRaw = await rootBundle.loadString('assets/data/pillars.json');
    final issuesRaw = await rootBundle.loadString('assets/data/issues.json');
    final questionsRaw = await rootBundle.loadString(
      'assets/data/questions.json',
    );
    final overlay = await _loadRollcallOverlay();

    // A previously network-refreshed roster (see [refreshPoliticians]) beats
    // the bundled asset — it can only be newer, since it's only ever written
    // after a successful fetch. First launch, a cleared cache, or every
    // refresh since install failing all fall back to what shipped in the
    // app, so this never blocks startup on the network.
    final cached = await (cache ?? PoliticiansCache()).readRaw();
    final politiciansRaw =
        cached ??
        await rootBundle.loadString('assets/data/politicians.json');

    final pillars = (jsonDecode(pillarsRaw) as List<dynamic>)
        .map((e) => Pillar.fromJson(e as Map<String, dynamic>))
        .toList();
    final issues = (jsonDecode(issuesRaw) as List<dynamic>)
        .map((e) => Issue.fromJson(e as Map<String, dynamic>))
        .toList();
    final questions = (jsonDecode(questionsRaw) as List<dynamic>)
        .map((e) => Question.fromJson(e as Map<String, dynamic>))
        .toList();
    final politicians = _decodePoliticians(politiciansRaw, overlay);

    return AppData(
      pillars: pillars,
      issues: issues,
      questions: questions,
      politicians: politicians,
    );
  }

  /// Checks `/v1/politicians` for a newer roster than whatever is already
  /// cached, caching and returning the decoded list on a change.
  ///
  /// Best-effort and silent by design, same as the Issue of the Week fetch
  /// this mirrors: no network, a timeout, a 304 (nothing changed), or a
  /// malformed response all just return null, and the caller keeps showing
  /// whatever roster [load] already produced. Never throws.
  ///
  /// Also makes sure this install has registered a device keypair (once per
  /// install — see [DeviceIdentity]) and signs the request with it, sent
  /// alongside whatever build-time [VoteaxisApi.fetchPoliticians]'s `key`
  /// default carries — the two credentials the server accepts are
  /// independent, so this works whether this build ships a personal key,
  /// relies on signed devices, both, or (for now, on a build with neither and
  /// a server not yet accepting device auth) neither.
  static Future<List<Politician>?> refreshPoliticians({
    VoteaxisApi? api,
    PoliticiansCache? cache,
    DeviceIdentity? deviceIdentity,
  }) async {
    final ownedApi = api == null;
    final client = api ?? VoteaxisApi();
    final store = cache ?? PoliticiansCache();
    final identity = deviceIdentity ?? DeviceIdentity();
    try {
      final etag = await store.readEtag();
      await identity.ensureRegistered(client.registerDevice);
      final deviceAuth = await identity.sign(
        method: 'GET',
        path: '/v1/politicians',
      );
      final snapshot = await client.fetchPoliticians(
        etag: etag,
        deviceAuth: deviceAuth,
      );
      if (snapshot == null) return null;
      final overlay = await _loadRollcallOverlay();
      final politicians = _decodePoliticians(snapshot.raw, overlay);
      await store.write(snapshot.raw, etag: snapshot.etag);
      return politicians;
    } catch (_) {
      return null;
    } finally {
      if (ownedApi) client.dispose();
    }
  }
}
