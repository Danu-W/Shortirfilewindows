import 'package:flutter_test/flutter_test.dart';

import 'package:shortir_file/main.dart';

void main() {
  testWidgets('App renders sign-in gate', (WidgetTester tester) async {
    await tester.pumpWidget(const ShortirApp());

    expect(find.text('Shortir File'), findsOneWidget);
    expect(find.text('Masuk'), findsOneWidget);
    expect(find.text('Buat akun baru'), findsOneWidget);
  });
}
