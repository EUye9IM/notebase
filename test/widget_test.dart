import 'package:flutter_test/flutter_test.dart';

import 'package:notebase/main.dart';

void main() {
  testWidgets('renders home page', (WidgetTester tester) async {
    await tester.pumpWidget(const NotebaseApp());

    expect(find.text('Notebase'), findsOneWidget);
    expect(find.text('空白应用骨架'), findsOneWidget);
  });
}
