import 'package:flutter_test/flutter_test.dart';
import 'package:voteaxis/data/us_states.dart';

void main() {
  test('includes 50 states plus DC', () {
    expect(UsStates.all, hasLength(51));
    expect(UsStates.all.map((s) => s.code).toSet(), hasLength(51));
    expect(UsStates.nameFor('MI'), 'Michigan');
    expect(UsStates.nameFor('DC'), 'District of Columbia');
  });

  test('unknown codes pass through; empty is null', () {
    expect(UsStates.nameFor(null), isNull);
    expect(UsStates.nameFor(''), isNull);
    expect(UsStates.nameFor('XX'), 'XX');
  });
}
