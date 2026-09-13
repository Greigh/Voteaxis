import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voteaxis/models/issue.dart';
import 'package:voteaxis/models/pillar.dart';

void main() {
  test('Issue.fromJson keeps the quiz explainer', () {
    final issue = Issue.fromJson({
      'id': 'taxes',
      'label': 'Taxes',
      'pillarId': 'economy',
      'context': 'Who pays, and how much.',
    });
    expect(issue.pillarId, 'economy');
    expect(issue.context, contains('Who pays'));
  });

  test('bundled issues map onto the five pillars', () {
    final pillars =
        (jsonDecode(File('assets/data/pillars.json').readAsStringSync())
                as List)
            .map((e) => Pillar.fromJson(e as Map<String, dynamic>))
            .toList();
    final issues =
        (jsonDecode(File('assets/data/issues.json').readAsStringSync()) as List)
            .map((e) => Issue.fromJson(e as Map<String, dynamic>))
            .toList();
    expect(pillars, hasLength(5));
    expect(issues, hasLength(22));
    final pillarIds = {for (final p in pillars) p.id};
    for (final issue in issues) {
      expect(pillarIds, contains(issue.pillarId));
    }
  });
}
