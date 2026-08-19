import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/main.dart';

void main() {
  testWidgets('App inicializa na tela de login (Tiago IA)',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(find.text('TIAGO IA'), findsOneWidget);
    expect(find.text('ENTRAR'), findsOneWidget);
    expect(find.byType(Form), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(Form), matching: find.byType(TextFormField)),
        findsNWidgets(2));
  });
}
