import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/core/widgets/pg_image_slot.dart';
import '../support/pump.dart';

void main() {
  testWidgets('renders a network image, decoded at display size', (tester) async {
    await pumpPg(tester, const PgImageSlot(size: 60, emoji: '🐾', imageUrl: 'https://x/img.jpg'));

    final img = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(img.imageUrl, 'https://x/img.jpg');
    // Decoded at display size: without the hint a 60px avatar decodes the full
    // upload into memory, which is the whole point of PgNetworkImage. In
    // physical pixels, so it scales with the device pixel ratio rather than
    // decoding a blurry 60px bitmap on a 3x screen.
    final dpr = tester.view.devicePixelRatio;
    expect(img.memCacheWidth, (60 * dpr).ceil());
    expect(img.memCacheHeight, (60 * dpr).ceil());
  });

  testWidgets('renders the emoji placeholder when imageUrl is null or empty', (tester) async {
    await pumpPg(tester, const PgImageSlot(size: 60, emoji: '🐾'));
    expect(find.text('🐾'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);

    await pumpPg(tester, const PgImageSlot(size: 60, emoji: '🐾', imageUrl: ''));
    expect(find.text('🐾'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });

  testWidgets('fills its bounded parent when size is null', (tester) async {
    await pumpPg(
      tester,
      const SizedBox(
        width: 200,
        height: 300,
        child: PgImageSlot(imageUrl: 'https://x/img.jpg'),
      ),
    );
    // PgImageSlot always draws a 1px `Border.all` around its content; Container
    // auto-applies a border's `dimensions` as padding to its child so the
    // border isn't painted over the image. So the fully-filled Image is the
    // 200x300 parent box minus that 1px inset on every side (198x298), not
    // exactly 200x300 — this proves the image fills 100% of the *available*
    // content area rather than collapsing to its intrinsic (zero) size.
    final img = tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(Size(img.width!, img.height!), const Size(198, 298));
  });
}
