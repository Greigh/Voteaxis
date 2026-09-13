class Pillar {
  const Pillar({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;

  factory Pillar.fromJson(Map<String, dynamic> json) {
    return Pillar(
      id: json['id'] as String,
      label: json['label'] as String,
      description: json['description'] as String,
    );
  }
}
