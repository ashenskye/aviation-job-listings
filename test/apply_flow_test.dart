import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aviation_job_listings/main.dart';

import 'helpers/fake_app_repository.dart';

void main() {
  testWidgets(
    'End-to-end flow: employer creates listing and job seeker applies',
    (WidgetTester tester) async {
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
        'E2E Apply Role',
      );
      await tester.enterText(
        find.byKey(const ValueKey('create-starting-pay')),
        '80000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('create-description')),
        'E2E role description',
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

      await tester.ensureVisible(find.text('Create Job Listing'));

      await tester.ensureVisible(find.text('Part 135'));
      await tester.tap(find.text('Part 135').hitTestable());
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.text('Airline Transport Pilot (ATP)').first,
      );
      await tester.tap(find.text('Airline Transport Pilot (ATP)').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Multi-Engine Land').first);
      await tester.tap(find.text('Multi-Engine Land').first);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Hours Requirements *'));
      await tester.tap(find.text('Hours Requirements *').hitTestable());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Total Time'));
      await tester.tap(find.text('Total Time').hitTestable());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('create-hours-Flight Hours-Total Time')),
        '1000',
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Create Job Listing'));
      await tester.tap(find.text('Create Job Listing').hitTestable());
      await tester.pumpAndSettle();

      expect(find.text('Job Listing Created'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.person));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Job Seeker').last);
      await tester.pumpAndSettle();
      expect(find.text('Favorites'), findsOneWidget);

      await tester.tap(find.text('Jobs'));
      await tester.pumpAndSettle();

      expect(find.text('E2E Apply Role'), findsOneWidget);

      // For an empty profile, the match is <70% (stretch), so tapping Apply
      // opens the "Apply Anyway" quick-apply dialog.
      await tester.tap(find.byTooltip('Apply').hitTestable().first);
      await tester.pumpAndSettle();

      // The quick apply dialog should now be visible.
      expect(find.text('Apply Anyway'), findsWidgets);

      // Submit the dialog.
      await tester.tap(find.text('Submit Application').hitTestable());
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    },
  );
}
