import 'package:flutter_test/flutter_test.dart';
import 'package:foo/main.dart' as app;

void main() {
  testWidgets('debug_main', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await app.main();
    });
  }, timeout: Timeout.none);
}
