import 'package:flutter_test/flutter_test.dart';
import 'package:necaramba/main.dart';

void main() {
  testWidgets('disconnected bootstrap displays unavailable runtime', (
    tester,
  ) async {
    await tester.pumpWidget(const NecarambaApp());
    await tester.pumpAndSettle();
    expect(find.text('Native runtime unavailable'), findsOneWidget);
  });
}
