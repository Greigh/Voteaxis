class RollcallMove {
  const RollcallMove({
    required this.issueId,
    required this.cast,
    required this.contribution,
    this.date,
    this.congress,
    this.chamber,
    this.rollnumber,
    this.bill,
    this.question,
    this.desc,
    this.url,
  });

  final String issueId;
  final String cast;
  final double contribution;
  final String? date;
  final int? congress;
  final String? chamber;
  final String? rollnumber;
  final String? bill;
  final String? question;
  final String? desc;
  final String? url;

  factory RollcallMove.fromJson(Map<String, dynamic> json) {
    final date = json['date'] as String?;
    final bill = json['bill'] as String?;
    final question = json['question'] as String?;
    final desc = json['desc'] as String?;
    final url = json['url'] as String?;
    final chamber = json['chamber'] as String?;
    final rollnumber = json['rollnumber'] == null
        ? null
        : '${json['rollnumber']}';
    return RollcallMove(
      issueId: json['issueId'] as String? ?? '',
      cast: json['cast'] as String? ?? '',
      contribution: (json['contribution'] as num?)?.toDouble() ?? 0,
      date: date == null || date.isEmpty ? null : date,
      congress: (json['congress'] as num?)?.toInt(),
      chamber: chamber == null || chamber.isEmpty ? null : chamber,
      rollnumber: rollnumber == null || rollnumber.isEmpty ? null : rollnumber,
      bill: bill == null || bill.isEmpty ? null : bill,
      question: question == null || question.isEmpty ? null : question,
      desc: desc == null || desc.isEmpty ? null : desc,
      url: url == null || url.isEmpty ? null : url,
    );
  }

  bool get pulledConservative => contribution > 0;
}

class RollcallSession {
  const RollcallSession({
    required this.congress,
    required this.year,
    required this.label,
    required this.axisScore,
    this.issues = const {},
    this.counts = const {},
    this.moves = const [],
  });

  final int congress;
  final int year;
  final String label;
  final double axisScore;
  final Map<String, double> issues;
  final Map<String, int> counts;
  final List<RollcallMove> moves;

  String get yearSpan => '$year–${year + 1}';

  factory RollcallSession.fromJson(Map<String, dynamic> json) {
    Map<String, double> issues() {
      final raw = json['issues'];
      if (raw is! Map) return const {};
      return raw.map((k, v) => MapEntry('$k', (v as num).toDouble()));
    }

    Map<String, int> counts() {
      final raw = json['counts'];
      if (raw is! Map) return const {};
      return raw.map((k, v) => MapEntry('$k', (v as num).toInt()));
    }

    List<RollcallMove> moves() {
      final raw = json['moves'];
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          if (item is Map)
            RollcallMove.fromJson(Map<String, dynamic>.from(item)),
      ];
    }

    return RollcallSession(
      congress: (json['congress'] as num).toInt(),
      year: (json['year'] as num).toInt(),
      label: json['label'] as String? ?? '',
      axisScore: (json['axisScore'] as num).toDouble(),
      issues: issues(),
      counts: counts(),
      moves: moves(),
    );
  }

  static List<RollcallSession> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          RollcallSession.fromJson(Map<String, dynamic>.from(item)),
    ];
  }
}
