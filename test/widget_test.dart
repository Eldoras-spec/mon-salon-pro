import 'package:flutter_test/flutter_test.dart';
import 'package:mon_salon/main.dart';

void main() {
  testWidgets('Login screen smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MonSalonProApp());

    // Verify that the app title "Mon Salon" is displayed.
    expect(find.text('Mon Salon'), findsOneWidget);
    expect(find.text("Découvrez l'excellence de la coiffure"), findsOneWidget);

    // Verify that social buttons are present
    expect(find.text('Continuer avec Google'), findsOneWidget);
    expect(find.text('Continuer avec Apple'), findsOneWidget);
  });
}
