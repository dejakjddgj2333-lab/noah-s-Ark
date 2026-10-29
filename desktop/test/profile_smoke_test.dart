import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_desktop/pages/profile_page.dart';

void main() {
  testWidgets('ProfilePage builds without layout errors', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(ProfilePage), findsOneWidget);
  });
}
