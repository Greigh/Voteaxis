import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/scoring.dart';
import 'device_token.dart';
import 'result_envelope.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class PublishedCode {
  const PublishedCode({
    required this.code,
    required this.token,
    required this.expiresAt,
  });

  final String code;
  final String token;
  final DateTime expiresAt;
}

class RemoteProfile {
  const RemoteProfile({
    required this.code,
    required this.displayName,
    required this.axisScore,
    required this.issueScores,
    required this.issueWeights,
    required this.pillarScores,
    required this.dealbreakerIssueIds,
  });

  final String code;
  final String displayName;
  final double axisScore;
  final Map<String, double> issueScores;
  final Map<String, double> issueWeights;
  final Map<String, double> pillarScores;
  final List<String> dealbreakerIssueIds;

  factory RemoteProfile.fromJson(Map<String, dynamic> json) {
    Map<String, double> scores(String key) {
      final raw = json[key];
      if (raw is! Map) return const {};
      return raw.map((k, v) => MapEntry(k as String, (v as num).toDouble()));
    }

    return RemoteProfile(
      code: json['code'] as String,
      displayName: (json['displayName'] as String?) ?? '',
      axisScore: (json['axisScore'] as num).toDouble(),
      issueScores: scores('issueScores'),
      issueWeights: scores('issueWeights'),
      pillarScores: scores('pillarScores'),
      dealbreakerIssueIds:
          (json['dealbreakerIssueIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }

  SpectrumProfile toProfile() => SpectrumProfile(
    issueScores: issueScores,
    pillarScores: pillarScores,
    axisScore: axisScore,
    issueWeights: issueWeights,
    dealbreakerIssueIds: dealbreakerIssueIds,
  );

  String get label => displayName.isEmpty ? 'Friend' : displayName;
}

/// A result published to `voteaxis.org/result/<id>`.
class SharedResultLink {
  const SharedResultLink({
    required this.id,
    required this.token,
    required this.url,
    required this.encrypted,
    required this.expiresAt,
  });

  final String id;

  /// Server-minted write token. Holding it lets this device replace or revoke
  /// the link later, so re-sharing after a retake reuses the same URL.
  final String token;
  final String url;

  /// Sealed on this device — the server holds ciphertext it cannot read.
  final bool encrypted;
  final DateTime expiresAt;

  factory SharedResultLink.fromJson(Map<String, dynamic> json) {
    return SharedResultLink(
      id: json['id'] as String,
      token: json['token'] as String,
      url: json['url'] as String,
      encrypted: json['encrypted'] as bool? ?? false,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (json['expiresAt'] as num).toInt(),
      ),
    );
  }
}

/// A result fetched back from a shared link.
class SharedResult {
  const SharedResult({
    required this.id,
    required this.encrypted,
    this.envelope,
    this.transferCode,
    this.homeState,
    this.label = '',
    this.axisScore = 0,
    this.issueScores = const {},
    this.issueWeights = const {},
    this.pillarScores = const {},
    this.dealbreakerIssueIds = const [],
  });

  final String id;

  /// Sealed. [envelope] is all that came back; open it with the password.
  final bool encrypted;
  final ResultEnvelope? envelope;
  final String? transferCode;
  final String? homeState;
  final String label;
  final double axisScore;
  final Map<String, double> issueScores;
  final Map<String, double> issueWeights;
  final Map<String, double> pillarScores;
  final List<String> dealbreakerIssueIds;

  /// Rebuilds a result from a decrypted envelope body, which carries the same
  /// fields an open link would have returned inline.
  factory SharedResult.opened(String id, Map<String, dynamic> body) {
    return SharedResult.fromJson({...body, 'id': id, 'encrypted': false});
  }

  factory SharedResult.fromJson(Map<String, dynamic> json) {
    Map<String, double> scores(String key) {
      final raw = json[key];
      if (raw is! Map) return const {};
      return raw.map((k, v) => MapEntry(k as String, (v as num).toDouble()));
    }

    final encrypted = json['encrypted'] as bool? ?? false;
    return SharedResult(
      id: json['id'] as String,
      encrypted: encrypted,
      envelope: encrypted
          ? ResultEnvelope.fromJson(
              (json['envelope'] as Map?)?.cast<String, dynamic>() ?? const {},
            )
          : null,
      transferCode: json['transferCode'] as String?,
      homeState: json['homeState'] as String?,
      label: (json['label'] as String?) ?? '',
      axisScore: (json['axisScore'] as num?)?.toDouble() ?? 0,
      issueScores: scores('issueScores'),
      issueWeights: scores('issueWeights'),
      pillarScores: scores('pillarScores'),
      dealbreakerIssueIds:
          (json['dealbreakerIssueIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
  }
}

class CongressBill {
  const CongressBill({
    required this.kind,
    required this.congress,
    required this.type,
    required this.number,
    required this.title,
    required this.url,
    this.introducedDate,
    this.latestAction,
    this.summary,
    this.enrichedFrom,
  });

  final String kind;
  final int congress;
  final String type;
  final String number;
  final String title;
  final String url;
  final String? introducedDate;
  final String? latestAction;
  final String? summary;
  final String? enrichedFrom;

  factory CongressBill.fromJson(Map<String, dynamic> json) {
    final intro = json['introducedDate'] as String?;
    final summary = json['summary'] as String?;
    return CongressBill(
      kind: json['kind'] as String? ?? 'sponsored',
      congress: (json['congress'] as num).toInt(),
      type: json['type'] as String,
      number: '${json['number']}',
      title: json['title'] as String,
      url: json['url'] as String,
      introducedDate: intro == null || intro.isEmpty ? null : intro,
      latestAction: json['latestAction'] as String?,
      summary: summary == null || summary.isEmpty ? null : summary,
      enrichedFrom: json['enrichedFrom'] as String?,
    );
  }

  String get citation {
    final prefix = switch (type.toUpperCase()) {
      'HR' => 'H.R.',
      'HRES' => 'H.Res.',
      'HJRES' => 'H.J.Res.',
      'HCONRES' => 'H.Con.Res.',
      'SRES' => 'S.Res.',
      'SJRES' => 'S.J.Res.',
      'SCONRES' => 'S.Con.Res.',
      _ => type.toUpperCase(),
    };
    return '$prefix $number · ${_ordinal(congress)}';
  }
}

String _ordinal(int n) {
  final v = n % 100;
  if (v >= 11 && v <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

class CongressReceipts {
  const CongressReceipts({
    required this.bioguideId,
    required this.memberUrl,
    required this.sponsored,
    required this.cosponsored,
    this.name,
  });

  final String bioguideId;
  final String memberUrl;
  final String? name;
  final List<CongressBill> sponsored;
  final List<CongressBill> cosponsored;

  factory CongressReceipts.fromJson(Map<String, dynamic> json) {
    List<CongressBill> bills(String key) {
      final raw = json[key];
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          if (item is Map)
            CongressBill.fromJson(Map<String, dynamic>.from(item)),
      ];
    }

    return CongressReceipts(
      bioguideId: json['bioguideId'] as String,
      memberUrl: json['memberUrl'] as String? ?? '',
      name: json['name'] as String?,
      sponsored: bills('sponsored'),
      cosponsored: bills('cosponsored'),
    );
  }

  bool get isEmpty => sponsored.isEmpty && cosponsored.isEmpty;
}

/// A roster fetch that changed. [raw] is the bare JSON array — the same
/// shape as the bundled `assets/data/politicians.json` — ready to hand to
/// [PoliticiansCache.write] or decode straight into [Politician]s.
class PoliticiansSnapshot {
  const PoliticiansSnapshot({required this.raw, this.etag});

  final String raw;
  final String? etag;
}

class IssueOfTheWeek {
  const IssueOfTheWeek({
    required this.weekOf,
    required this.issueId,
    required this.headline,
    required this.question,
    this.context,
  });

  final String weekOf;
  final String issueId;
  final String headline;
  final String question;
  final String? context;

  factory IssueOfTheWeek.fromJson(Map<String, dynamic> json) {
    return IssueOfTheWeek(
      weekOf: json['weekOf'] as String? ?? '',
      issueId: json['issueId'] as String? ?? '',
      headline: json['headline'] as String? ?? '',
      question: json['question'] as String? ?? '',
      context: json['context'] as String?,
    );
  }
}

class VoteaxisApi {
  VoteaxisApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _base = (baseUrl ?? AppConfig.apiBase).replaceAll(RegExp(r'/$'), '');

  final http.Client _client;
  final bool _ownsClient;
  final String _base;
  static const _timeout = Duration(seconds: 12);

  Uri _uri(String path) => Uri.parse('$_base$path');

  /// Closes the underlying HTTP client and its idle-connection pool. Call this
  /// from the owning widget's dispose(). A no-op when the client was injected —
  /// whoever passed it in owns its lifecycle.
  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<PublishedCode> publish({
    required SpectrumProfile profile,
    String? token,
    String? displayName,
  }) async {
    final res = await _client
        .post(
          _uri('/v1/codes'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            if (token != null && token.isNotEmpty) 'token': token,
            if (displayName != null && displayName.isNotEmpty)
              'displayName': displayName,
            'axisScore': profile.axisScore,
            'issueScores': profile.issueScores,
            'issueWeights': profile.issueWeights,
            'pillarScores': profile.pillarScores,
            'dealbreakerIssueIds': profile.dealbreakerIssueIds,
          }),
        )
        .timeout(_timeout);
    final body = _decode(res);
    if (res.statusCode != 200) {
      throw ApiException(
        body['error'] as String? ?? 'Could not publish your code.',
        statusCode: res.statusCode,
      );
    }
    return PublishedCode(
      code: body['code'] as String,
      token: body['token'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (body['expiresAt'] as num).toInt(),
      ),
    );
  }

  Future<RemoteProfile> lookup(String code) async {
    final res = await _client
        .get(_uri('/v1/codes/${Uri.encodeComponent(code)}'))
        .timeout(_timeout);
    final body = _decode(res);
    if (res.statusCode == 404) {
      throw ApiException('Code expired or not found.', statusCode: 404);
    }
    if (res.statusCode != 200) {
      throw ApiException(
        body['error'] as String? ?? 'Could not look up that code.',
        statusCode: res.statusCode,
      );
    }
    return RemoteProfile.fromJson(body);
  }

  /// Publishes a shareable result page. Passing [token] replaces the link
  /// this device published before instead of minting a new URL.
  ///
  /// With a [password] the payload is sealed on this device, so the server
  /// only ever receives ciphertext — it has no key and no way to read it.
  /// Without one the scores go up in the clear, which is what lets an open
  /// link render a page at all.
  Future<SharedResultLink> shareResult({
    required SpectrumProfile profile,
    String? token,
    String? password,
    String? transferCode,
    String? homeState,
    String? label,
    DateTime? takenAt,
  }) async {
    final payload = <String, dynamic>{
      'axisScore': profile.axisScore,
      'issueScores': profile.issueScores,
      'issueWeights': profile.issueWeights,
      'pillarScores': profile.pillarScores,
      'dealbreakerIssueIds': profile.dealbreakerIssueIds,
      'transferCode': ?transferCode,
      'homeState': ?homeState,
      'label': ?label,
      if (takenAt != null) 'takenAt': takenAt.millisecondsSinceEpoch,
    };
    final sealed = password == null || password.isEmpty
        ? null
        : await ResultEnvelope.seal(payload: payload, password: password);

    final res = await _client
        .post(
          _uri('/v1/results'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            if (token != null && token.isNotEmpty) 'token': token,
            if (sealed != null)
              'envelope': sealed.toJson()
            else
              'payload': payload,
          }),
        )
        .timeout(_timeout);
    final body = _decode(res);
    if (res.statusCode != 200) {
      throw ApiException(
        body['error'] as String? ?? 'Could not create your link.',
        statusCode: res.statusCode,
      );
    }
    return SharedResultLink.fromJson(body);
  }

  /// Reads a shared result. An encrypted one comes back sealed — hand it to
  /// [openResult] with the password.
  Future<SharedResult> fetchResult(String id) async {
    final res = await _client
        .get(_uri('/v1/results/${Uri.encodeComponent(id)}'))
        .timeout(_timeout);
    final body = _decode(res);
    if (res.statusCode == 404) {
      throw ApiException('This link expired or was removed.', statusCode: 404);
    }
    if (res.statusCode != 200) {
      throw ApiException(
        body['error'] as String? ?? 'Could not open that link.',
        statusCode: res.statusCode,
      );
    }
    return SharedResult.fromJson(body);
  }

  /// Decrypts locally. Returns null when the password is wrong — no request
  /// leaves the device, so there is nothing for the server to observe or for
  /// an attacker to rate-limit their way around on our side.
  static Future<SharedResult?> openResult(
    SharedResult sealed,
    String password,
  ) async {
    final envelope = sealed.envelope;
    if (envelope == null) return sealed;
    final body = await envelope.open(password);
    if (body == null) return null;
    return SharedResult.opened(sealed.id, body);
  }

  /// Takes a shared link down before its expiry.
  Future<void> revokeResult(String id, String token) async {
    final res = await _client
        .delete(
          _uri('/v1/results/${Uri.encodeComponent(id)}'),
          headers: {'x-voteaxis-token': token},
        )
        .timeout(_timeout);
    if (res.statusCode == 200 || res.statusCode == 404) return;
    final body = _decode(res);
    throw ApiException(
      body['error'] as String? ?? 'Could not remove that link.',
      statusCode: res.statusCode,
    );
  }

  Future<CongressReceipts> receipts(String bioguideId) async {
    final res = await _client
        .get(_uri('/v1/receipts/${Uri.encodeComponent(bioguideId)}'))
        .timeout(_timeout);
    final body = _decode(res);
    if (res.statusCode != 200) {
      throw ApiException(
        body['error'] as String? ?? 'Could not load Congress receipts.',
        statusCode: res.statusCode,
      );
    }
    return CongressReceipts.fromJson(body);
  }

  Future<IssueOfTheWeek?> week() async {
    final res = await _client.get(_uri('/v1/week')).timeout(_timeout);
    if (res.statusCode == 404) return null;
    final body = _decode(res);
    if (res.statusCode != 200) return null;
    return IssueOfTheWeek.fromJson(body);
  }

  /// Best-effort like [week]: never throws, and returns null both on a
  /// network failure and on a 304 (server-confirmed no change since [etag]).
  /// Either way the caller keeps using whatever roster it already has —
  /// bundled asset, prior cache, or the current in-memory list.
  ///
  /// [key] and [deviceAuth] are the server's two independent credentials for
  /// this route (see server/README.md) — send whichever this build and this
  /// install have. Either alone is enough; sending both is harmless.
  Future<PoliticiansSnapshot?> fetchPoliticians({
    String? etag,
    String key = AppConfig.politiciansKey,
    DeviceAuthHeaders? deviceAuth,
  }) async {
    try {
      final res = await _client
          .get(
            _uri('/v1/politicians'),
            headers: {
              if (key.isNotEmpty) 'x-voteaxis-key': key,
              ...?deviceAuth?.toHeaders(),
              if (etag != null && etag.isNotEmpty) 'if-none-match': etag,
            },
          )
          .timeout(_timeout);
      // Locked-down-for-now (see server/README.md): neither credential was
      // accepted, or this build/install has neither to offer. Either way,
      // best-effort — the caller keeps whatever roster it already has.
      if (res.statusCode == 401) return null;
      if (res.statusCode == 304) return null;
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['politicians'] is! List) return null;
      return PoliticiansSnapshot(
        raw: jsonEncode(decoded['politicians']),
        etag: res.headers['etag'],
      );
    } catch (_) {
      return null;
    }
  }

  /// Registers this install's public key with `POST /v1/device-tokens` and
  /// returns the deviceId the server assigned. [publicKeyHex] is the raw
  /// 32-byte Ed25519 public key from [DeviceIdentity] — the matching private
  /// key never reaches this method or the server. Best effort like
  /// [fetchPoliticians]: null on any failure, so the caller just tries again
  /// on the next refresh rather than surfacing an error for an endpoint the
  /// user never directly interacts with.
  Future<String?> registerDevice(String publicKeyHex) async {
    try {
      final res = await _client
          .post(
            _uri('/v1/device-tokens'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'publicKey': publicKeyHex}),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      final deviceId = decoded is Map ? decoded['deviceId'] : null;
      return deviceId is String && deviceId.isNotEmpty ? deviceId : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _decode(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      throw ApiException(
        res.statusCode >= 500
            ? 'The Voteaxis server is unavailable.'
            : 'Unexpected response from the server.',
        statusCode: res.statusCode,
      );
    }
  }
}
