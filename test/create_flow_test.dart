import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aviation_job_listings/main.dart';

import 'helpers/fake_app_repository.dart';

void main() {
  testWidgets('Employer create flow advances to qualifications step', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyApp(repository: FakeAppRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Employer').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create New Listing'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Title *'),
      'Test Job',
    );
    await tester.enterText(
      find.byKey(const ValueKey('create-starting-pay')),
      '65000',
    );
    await tester.enterText(
      find.byKey(const ValueKey('create-description')),
      'Test role description',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('create-employment-type')),
    );
    await tester.tap(
      find.byKey(const ValueKey('create-employment-type')).hitTestable(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contract').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('create-position-selection')),
    );
    await tester.tap(
      find.byKey(const ValueKey('create-position-selection')).hitTestable(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Single Pilot').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('create-pay-rate-metric')),
    );
    await tester.tap(
      find.byKey(const ValueKey('create-pay-rate-metric')).hitTestable(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flight Hour').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Next: Qualifications'));
    await tester.tap(find.text('Next: Qualifications'));
    await tester.pumpAndSettle();

    expect(
      find.text('Step 2 of 2: Define requirements and qualifications'),
      findsOneWidget,
    );
  });

  testWidgets('Selecting ATP hides lower pilot certificates in create flow', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyApp(repository: FakeAppRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Employer').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create New Listing'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Title *'),
      'ATP Role',
    );
    await tester.enterText(
      find.byKey(const ValueKey('create-starting-pay')),
      '70000',
    );
    await tester.enterText(
      find.byKey(const ValueKey('create-description')),
      'ATP role description',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('create-employment-type')),
    );
    await tester.tap(
      find.byKey(const ValueKey('create-employment-type')).hitTestable(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contract').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('create-position-selection')),
    );
    await tester.tap(
      find.byKey(const ValueKey('create-position-selection')).hitTestable(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Single Pilot').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('create-pay-rate-metric')),
    );
    await tester.tap(
      find.byKey(const ValueKey('create-pay-rate-metric')).hitTestable(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flight Hour').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Next: Qualifications'));
    await tester.tap(find.text('Next: Qualifications'));
    await tester.pumpAndSettle();

    // Expand the Required FAA Certificates section before checking contents.
    await tester.ensureVisible(find.text('Required FAA Certificates *'));
    await tester.tap(find.text('Required FAA Certificates *'));
    await tester.pumpAndSettle();

    expect(find.text('Commercial Pilot (CPL)'), findsOneWidget);
    expect(find.text('Instrument Rating (IFR)'), findsOneWidget);
    expect(find.text('Private Pilot (PPL)'), findsOneWidget);

    await tester.ensureVisible(
      find.text('Airline Transport Pilot (ATP)').first,
    );
    await tester.tap(
      find.text('Airline Transport Pilot (ATP)').hitTestable().first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Commercial Pilot (CPL)'), findsNothing);
    expect(find.text('Instrument Rating (IFR)'), findsNothing);
    expect(find.text('Private Pilot (PPL)'), findsNothing);
  });
}
