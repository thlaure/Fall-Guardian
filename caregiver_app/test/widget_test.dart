import 'package:flutter_test/flutter_test.dart';

import 'package:caregiver_app/main.dart';

void main() {
  testWidgets('renders caregiver scaffold home', (tester) async {
    await tester.pumpWidget(const CaregiverApp());

    expect(find.text('Fall Guardian Caregiver'), findsOneWidget);
    expect(find.text('Caregiver app scaffolded'), findsOneWidget);
    expect(find.textContaining('separate caregiver client'), findsOneWidget);
  });
}
