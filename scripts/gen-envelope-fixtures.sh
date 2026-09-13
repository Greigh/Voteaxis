#!/usr/bin/env bash
# Regenerates shared/fixtures/envelope-interop.json.
#
# Only needed when the share-link envelope format itself changes — and if it
# does, every link already shared stops opening, so bump the version and keep
# the old branch alive rather than regenerating and moving on.
set -euo pipefail
cd "$(dirname "$0")/.."

bun run shared/fixtures/seal-webcrypto.ts

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat > "mobile/test/gen_envelope_fixture_test.dart" <<'DART'
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voteaxis/services/result_envelope.dart';

void main() {
  test('seal the interop fixture with the app implementation', () async {
    final file = File('../shared/fixtures/envelope-interop.json');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final envelope = await ResultEnvelope.seal(
      payload: (json['payload'] as Map).cast<String, dynamic>(),
      password: json['password'] as String,
      iterations: (json['iterations'] as num).toInt(),
    );
    json['sealedByDart'] = envelope.toJson();
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(json)}\n',
    );
  });
}
DART
(cd mobile && flutter test test/gen_envelope_fixture_test.dart)
rm mobile/test/gen_envelope_fixture_test.dart
echo "Regenerated shared/fixtures/envelope-interop.json"
