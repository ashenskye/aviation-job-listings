import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aviation_job_listings/main.dart';

import 'helpers/fake_app_repository.dart';

void main() {
  testWidgets('state picker supports arrow key navigation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyApp(repository: FakeAppRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit Personal Information').last);
    await tester.pumpAndSettle();

    final stateField = find.widgetWithText(TextField, 'State / Province');
    expect(stateField, findsOneWidget);

    await tester.tap(stateField);
    await tester.pumpAndSettle();

    await tester.enterText(stateField, 'a');
    await tester.pumpAndSettle();

    expect(find.text('Alabama (AL)'), findsWidgets);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alabama (AL)').first);
    await tester.pumpAndSettle();

    final selectedStateController = tester.widget<TextField>(stateField).controller;
    expect(selectedStateController?.text, 'Alabama');

    final saveChangesButton = find.widgetWithText(ElevatedButton, 'Save Changes');
    await tester.ensureVisible(saveChangesButton);
    await tester.pumpAndSettle();
    await tester.tap(saveChangesButton);
    await tester.pumpAndSettle();

    expect(find.text('Alabama'), findsOneWidget);
  });

  testWidgets('employer state picker supports arrow key navigation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MyHomePage(
          title: 'Aviation Job Listings',
          repository: FakeAppRepository(),
          initialProfileType: ProfileType.employer,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Employer Profile').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit').first);
    await tester.pumpAndSettle();

    final stateField = find.widgetWithText(TextField, 'State / Province');
    expect(stateField, findsOneWidget);

    await tester.tap(stateField);
    await tester.pumpAndSettle();

    await tester.enterText(stateField, 'a');
    await tester.pumpAndSettle();

    expect(find.text('Alabama (AL)'), findsWidgets);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alabama (AL)').first);
    await tester.pumpAndSettle();

    final selectedStateController =
        tester.widget<TextField>(stateField).controller;
    expect(selectedStateController?.text, 'Alabama');

    final saveChangesButton = find.widgetWithText(
      OutlinedButton,
      'Save Changes',
    );
    await tester.ensureVisible(saveChangesButton);
    await tester.pumpAndSettle();
    await tester.tap(saveChangesButton.first);
    await tester.pumpAndSettle();

    expect(find.text('Alabama'), findsOneWidget);
  });
}
