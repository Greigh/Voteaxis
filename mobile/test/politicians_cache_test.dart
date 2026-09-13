import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voteaxis/services/politicians_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PoliticiansCache cache;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('politicians_cache_test');
    cache = PoliticiansCache(directory: () async => tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('an empty cache reads as null on both raw and etag', () async {
    expect(await cache.readRaw(), isNull);
    expect(await cache.readEtag(), isNull);
  });

  test('write then read round-trips the raw JSON and the ETag', () async {
    final raw = jsonEncode([
      {'id': 'jane_example', 'name': 'Jane Example'},
    ]);
    await cache.write(raw, etag: 'W/"123:456"');
    expect(await cache.readRaw(), raw);
    expect(await cache.readEtag(), 'W/"123:456"');
  });

  test('a write without an etag leaves any previous etag alone', () async {
    await cache.write('[]', etag: 'W/"first"');
    await cache.write('[{"id":"a"}]');
    expect(await cache.readRaw(), '[{"id":"a"}]');
    expect(await cache.readEtag(), 'W/"first"');
  });

  test('a second write overwrites the first', () async {
    await cache.write('[{"id":"a"}]', etag: 'W/"a"');
    await cache.write('[{"id":"b"}]', etag: 'W/"b"');
    expect(await cache.readRaw(), '[{"id":"b"}]');
    expect(await cache.readEtag(), 'W/"b"');
  });

  test('a whitespace-only cache file reads as null, not empty content', () async {
    final file = File('${tempDir.path}/politicians_cache.json');
    await file.writeAsString('   \n');
    expect(await cache.readRaw(), isNull);
  });

  test('a directory resolver that throws degrades to null, not a crash', () async {
    final broken = PoliticiansCache(
      directory: () async => throw StateError('no filesystem access'),
    );
    expect(await broken.readRaw(), isNull);
    // write() is equally silent — nothing to assert on beyond "did not throw".
    await broken.write('[]', etag: 'W/"x"');
  });
}
