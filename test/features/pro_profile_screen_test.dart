import 'package:flutter_test/flutter_test.dart';
import 'package:pet_aggregator_app/data/models/pro.dart';
import 'package:pet_aggregator_app/features/services/pro_profile_screen.dart';
import '../support/pump.dart';

void main() {
  testWidgets('renders the pro and shows New rating; Book hints coming soon', (tester) async {
    const pro = Pro(uid: 'pro1', name: 'Aarav Sharma', area: 'Bandra West',
        bio: 'Friendly reliable walker.', serviceType: ServiceType.walker,
        rate: 250, experienceYears: 4);
    await pumpPg(tester, const ProProfileScreen(pro: pro));
    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.text('Friendly reliable walker.'), findsOneWidget);
    expect(find.textContaining('New'), findsWidgets); // no reviews yet
    await tester.tap(find.text('💬')); // chat button still shows coming-soon
    await tester.pump();
    expect(find.text('Chat is coming soon 🐾'), findsOneWidget);
  });
}
