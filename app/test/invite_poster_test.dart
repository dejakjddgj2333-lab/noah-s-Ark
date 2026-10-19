import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mingce/core/invite_poster.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('share action opens poster preview dialog', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => InvitePoster.previewAndShare(
                  context: context,
                  inviteCode: 'MC8K2Q',
                  inviteLink: 'https://mingce.example/?invite=MC8K2Q',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('分享海报预览'), findsOneWidget);
    expect(find.text('MC8K2Q'), findsOneWidget);
    expect(find.text('分享海报'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('取消'));
    await tester.pumpAndSettle();
    expect(find.text('分享海报预览'), findsNothing);
  });

  testWidgets('invite poster preview renders and captures as PNG', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 360,
                height: 680,
                child: InvitePoster.preview(
                  inviteCode: 'MC8K2Q',
                  inviteLink: 'https://mingce.example/?invite=MC8K2Q',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('明策 MINGCE'), findsOneWidget);
    expect(find.text('MC8K2Q'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(tester.takeException(), isNull);

    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    expect(image.width, 360);
    expect(image.height, 680);
  });
}
