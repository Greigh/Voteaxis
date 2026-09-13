class Issue {
  const Issue({
    required this.id,
    required this.label,
    required this.pillarId,
    this.context,
  });

  final String id;
  final String label;
  final String pillarId;

  /// Two-sentence, nonpartisan explainer shown from the quiz "?" control.
  final String? context;

  factory Issue.fromJson(Map<String, dynamic> json) {
    return Issue(
      id: json['id'] as String,
      label: json['label'] as String,
      pillarId: json['pillarId'] as String,
      context: json['context'] as String?,
    );
  }
}
