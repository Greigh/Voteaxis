import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voteaxis/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('App shell loads', (tester) async {
    await tester.pumpWidget(const VoteaxisApp());
    await tester.pump();
    expect(find.byType(VoteaxisApp), findsOneWidget);
  });
}
