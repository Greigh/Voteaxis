class Question {
  const Question({
    required this.id,
    required this.issueId,
    required this.text,
    required this.polarity,
    this.era = 'modern',
    this.steelManArgument,
  });

  final String id;
  final String issueId;
  final String text;

  /// -1 = agreeing leans liberal; +1 = agreeing leans conservative.
  final int polarity;

  /// `modern` (default) or `historical` (Progressive Era / 1912-style).
  final String era;

  /// Strongest case against agreeing with [text]. Shown after a hard lean.
  final String? steelManArgument;

  bool get isHistorical => era == 'historical';

  bool get hasSteelMan =>
      steelManArgument != null && steelManArgument!.trim().isNotEmpty;

  factory Question.fromJson(Map<String, dynamic> json) {
    final raw = json['steel_man_argument'] as String?;
    return Question(
      id: json['id'] as String,
      issueId: json['issueId'] as String,
      text: json['text'] as String,
      polarity: json['polarity'] as int,
      era: (json['era'] as String?) ?? 'modern',
      steelManArgument: raw == null || raw.trim().isEmpty ? null : raw.trim(),
    );
  }
}
