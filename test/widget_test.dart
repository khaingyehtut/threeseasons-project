import 'package:flutter_test/flutter_test.dart';
import 'package:three_seasons_project/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ThreeSeasonsApp());
    expect(find.byType(ThreeSeasonsApp), findsOneWidget);
  });
}
