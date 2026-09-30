import 'package:flutter_test/flutter_test.dart';
import 'package:mingce/main.dart';

void main() {
  testWidgets('app shell smoke test', (tester) async {
    await tester.pumpWidget(const MingceApp());
    expect(find.text('Noah’s Ark'), findsOneWidget);
    expect(find.text('首页'), findsWidgets);
  });
}
