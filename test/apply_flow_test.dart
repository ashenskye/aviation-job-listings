import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aviation_job_listings/main.dart';
import 'package:aviation_job_listings/models/job_listing.dart';
import 'package:aviation_job_listings/models/job_seeker_profile.dart';

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
      await tester.tap(find.text('Apply').hitTestable().first);
      await tester.pumpAndSettle();

      // The quick apply dialog should now be visible.
      expect(find.text('Apply Anyway'), findsWidgets);

      // Submit the dialog.
      await tester.tap(find.text('Submit Application').hitTestable());
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    },
  );

  testWidgets(
    'job details apply flow adds item to My Applications with Submitted status',
    (WidgetTester tester) async {
      final repository = FakeAppRepository();
      await repository.createJob(
        const JobListing(
          id: 'job-details-apply',
          title: 'Details Apply Role',
          company: 'SkyBridge Air',
          location: 'Denver, CO',
          type: 'Full-Time',
          crewRole: 'Single Pilot',
          faaRules: ['Part 91'],
          description: 'Open role used to verify job details apply flow.',
          faaCertificates: ['Airline Transport Pilot (ATP)'],
          flightExperience: ['Total Time'],
          flightHours: {'Total Time': 1500},
          aircraftFlown: ['Pilatus PC-12'],
          employerId: 'emp-skybridge',
        ),
      );

      await tester.pumpWidget(MyApp(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('Details Apply Role'), findsOneWidget);

      await tester.tap(find.text('Details Apply Role').first);
      await tester.pumpAndSettle();

      expect(find.text('Share Listing'), findsOneWidget);
      expect(find.text('Apply Anyway'), findsOneWidget);

      await tester.tap(find.text('Apply Anyway').hitTestable());
      await tester.pumpAndSettle();

      expect(find.text('Apply Anyway'), findsWidgets);
      await tester.tap(find.text('Submit Application').hitTestable());
      await tester.pumpAndSettle();

      expect(
        find.text('Applied! Employer will see your profile.'),
        findsOneWidget,
      );

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('My Applications'));
      await tester.pumpAndSettle();

      expect(find.text('Details Apply Role'), findsOneWidget);
      expect(find.text('SkyBridge Air • Denver, CO'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);
    },
  );

  testWidgets(
    'external listing still triggers apply callback from details page',
    (WidgetTester tester) async {
      var applyTapped = false;
      final externalJob = JobListing.fromJson({
        'id': 'external-apply-role',
        'title': 'External Captain Opportunity',
        'company': 'Mountain Air Charter',
        'location': 'Boise, ID',
        'type': 'External',
        'crewRole': 'Single Pilot',
        'faaRules': const <String>[],
        'description': 'Externally sourced posting for apply gating test.',
        'faaCertificates': const <String>[],
        'flightExperience': const <String>[],
        'aircraftFlown': const <String>[],
        'isExternal': true,
        'externalApplyUrl': 'https://example.com/apply',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: JobDetailsPage(
            job: externalJob,
            isFavorite: false,
            onFavorite: () {},
            onApply: () => applyTapped = true,
            profile: const JobSeekerProfile(),
            hasApplied: false,
            matchPercentage: 95,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Apply Externally'), findsOneWidget);
      expect(find.text('Apply Anyway'), findsNothing);
      expect(find.text('Quick Apply'), findsNothing);
      expect(find.text('Apply Now'), findsNothing);

      await tester.tap(find.text('Apply Externally'));
      await tester.pumpAndSettle();
      expect(applyTapped, isTrue);
    },
  );

  testWidgets(
    'external listing shows EXTERNAL JOB label on jobs and search cards',
    (WidgetTester tester) async {
      final repository = FakeAppRepository();
      await repository.createJob(
        JobListing.fromJson({
          'id': 'external-label-regression',
          'title': 'External Label Regression Role',
          'company': 'Mountain Air Charter',
          'location': 'Boise, ID',
          'type': 'Full-Time',
          'crewRole': 'Single Pilot',
          'faaRules': const <String>['Part 91'],
          'description':
              'Regression test listing to verify external badge text rendering.',
          'faaCertificates': const <String>[],
          'flightExperience': const <String>[],
          'aircraftFlown': const <String>[],
          'isExternal': true,
          'externalApplyUrl': 'https://example.com/apply',
        }),
      );

      await repository.createJob(
        const JobListing(
          id: 'internal-label-control',
          title: 'Internal Control Role',
          company: 'SkyBridge Air',
          location: 'Denver, CO',
          type: 'Full-Time',
          crewRole: 'Single Pilot',
          faaRules: ['Part 91'],
          description: 'Control listing without external marker.',
          faaCertificates: ['Airline Transport Pilot (ATP)'],
          flightExperience: ['Total Time'],
          flightHours: {'Total Time': 1500},
          aircraftFlown: ['Pilatus PC-12'],
          employerId: 'emp-skybridge',
        ),
      );

      await tester.pumpWidget(MyApp(repository: repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Jobs'));
      await tester.pumpAndSettle();

      expect(find.text('External Label Regression Role'), findsOneWidget);
      expect(find.text('EXTERNAL JOB'), findsOneWidget);

      await tester.tap(find.text('Search').last);
      await tester.pumpAndSettle();

      expect(find.text('External Label Regression Role'), findsOneWidget);
      expect(find.text('EXTERNAL JOB'), findsOneWidget);
    },
  );
}
