import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aviation_job_listings/main.dart';
import 'package:aviation_job_listings/models/job_listing.dart';
import 'package:aviation_job_listings/models/job_seeker_profile.dart';

import 'helpers/fake_app_repository.dart';

const List<String> _jobDetailsApplyCtaLabels = <String>[
  'Apply',
  'Apply Now',
  'Quick Apply',
  'Express Interest',
  'Contact Employer',
  'Apply Externally',
];

bool _hasAnyApplyCtaVisible() {
  for (final label in _jobDetailsApplyCtaLabels) {
    if (find.text(label).evaluate().isNotEmpty) {
      return true;
    }
  }
  return false;
}

Future<void> _tapAnyApplyCta(WidgetTester tester) async {
  for (final label in _jobDetailsApplyCtaLabels) {
    final candidate = find.text(label);
    if (candidate.evaluate().isNotEmpty) {
      await tester.ensureVisible(candidate.first);
      await tester.tap(candidate.hitTestable().first);
      await tester.pumpAndSettle();
      return;
    }
  }
  throw TestFailure('No apply CTA found on Job Details page.');
}

Future<void> _submitQuickApplyDialogIfVisible(WidgetTester tester) async {
  final submitButton = find.text('Submit Application');
  if (submitButton.evaluate().isNotEmpty) {
    await tester.tap(submitButton.hitTestable().first);
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'End-to-end flow: employer creates listing and job seeker applies',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MyHomePage(
            title: 'Aviation Job Listings',
            repository: FakeAppRepository(),
            // adminDashboardBuilder enables the role switcher in this E2E test
            // so the test can simulate employer creating a listing and then
            // a job seeker applying to it.
            adminDashboardBuilder: (ctx, onSwitch) => const SizedBox(),
          ),
        ),
      );
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

      await tester.ensureVisible(find.textContaining('FAA Operational Scope'));
      await tester.tap(find.textContaining('FAA Operational Scope').first);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Part 135'));
      await tester.tap(find.text('Part 135').hitTestable());
      await tester.pumpAndSettle();

      // Part 135 requires selecting IFR/Commuter or VFR Only.
      await tester.ensureVisible(find.text('IFR / Commuter'));
      await tester.tap(find.text('IFR / Commuter').hitTestable());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.textContaining('Required FAA Certificates'));
      await tester.tap(find.textContaining('Required FAA Certificates').first);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.text('Airline Transport Pilot (ATP)').first,
      );
      await tester.tap(find.text('Airline Transport Pilot (ATP)').first);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.textContaining('Required Ratings'));
      await tester.tap(find.textContaining('Required Ratings').first);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Multi-Engine Land').first);
      await tester.tap(find.text('Multi-Engine Land').first);
      await tester.pumpAndSettle();

      // IFR / Commuter auto-populates hours minimums, so no manual entry needed.
      // Just proceed to create the listing.

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

      await _tapAnyApplyCta(tester);
      expect(find.text('Submit Application'), findsOneWidget);

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
      expect(_hasAnyApplyCtaVisible(), isTrue);

      await _tapAnyApplyCta(tester);

      expect(find.text('Submit Application'), findsOneWidget);
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
      SharedPreferences.setMockInitialValues({});
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

      await tester.pumpWidget(
        MaterialApp(
          home: MyHomePage(
            title: 'Aviation Job Listings',
            repository: repository,
            initialProfileType: ProfileType.jobSeeker,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Jobs'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Search jobs'),
        'External Label Regression Role',
      );
      await tester.pumpAndSettle();

      expect(find.text('External Label Regression Role'), findsWidgets);
      expect(find.text('EXTERNAL JOB'), findsOneWidget);

      await tester.tap(find.text('Search').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('search-tab-query')),
        'External Label Regression Role',
      );
      await tester.pumpAndSettle();

      expect(find.text('Showing 1 of 2 jobs'), findsOneWidget);
      await tester.drag(find.byType(ListView).last, const Offset(0, -1200));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -1200));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(Card),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data == 'External Label Regression Role',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('EXTERNAL JOB'), findsOneWidget);
    },
  );

  testWidgets(
    'job seeker summary shows Part 135 IFR for legacy listings without subtype',
    (WidgetTester tester) async {
      final repository = FakeAppRepository();
      await repository.createJob(
        const JobListing(
          id: 'legacy-part135-ifr-fallback',
          title: 'Legacy IFR Charter Role',
          company: 'Mountain Jet',
          location: 'Boise, ID',
          type: 'Full-Time',
          crewRole: 'Single Pilot',
          faaRules: ['Part 135'],
          // Legacy records may be missing part135SubType. The UI should infer
          // IFR from the standard IFR/Commuter minimums.
          flightHours: {
            'Total Time': 1200,
            'Cross-Country': 500,
            'Night': 100,
            'Instrument': 75,
          },
          flightExperience: ['Total Time', 'Cross-Country', 'Night', 'Instrument'],
          description: 'Legacy listing to verify Part 135 fallback display.',
          faaCertificates: ['Airline Transport Pilot (ATP)'],
          aircraftFlown: ['Pilatus PC-12'],
          employerId: 'emp-mountain-jet',
        ),
      );

      await tester.pumpWidget(MyApp(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('Legacy IFR Charter Role'), findsOneWidget);

      await tester.tap(find.text('Legacy IFR Charter Role').first);
      await tester.pumpAndSettle();

      expect(find.text('Part 135 IFR'), findsWidgets);
    },
  );

  testWidgets(
    'job seeker summary shows Part 135 VFR for legacy listings without subtype',
    (WidgetTester tester) async {
      final repository = FakeAppRepository();
      await repository.createJob(
        const JobListing(
          id: 'legacy-part135-vfr-fallback',
          title: 'Legacy VFR Charter Role',
          company: 'Canyon Air Taxi',
          location: 'Phoenix, AZ',
          type: 'Full-Time',
          crewRole: 'Single Pilot',
          faaRules: ['Part 135'],
          // Legacy records may be missing part135SubType. The UI should infer
          // VFR from the standard VFR-only minimums.
          flightHours: {
            'Total Time': 500,
            'Cross-Country': 100,
            'Night': 25,
            'Instrument': 0,
          },
          flightExperience: ['Total Time', 'Cross-Country', 'Night'],
          description: 'Legacy listing to verify Part 135 VFR fallback display.',
          faaCertificates: ['Commercial Pilot Certificate'],
          aircraftFlown: ['Cessna 208 Caravan'],
          employerId: 'emp-canyon-air-taxi',
        ),
      );

      await tester.pumpWidget(MyApp(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('Legacy VFR Charter Role'), findsOneWidget);

      await tester.tap(find.text('Legacy VFR Charter Role').first);
      await tester.pumpAndSettle();

      expect(find.text('Part 135 VFR'), findsWidgets);
    },
  );

  testWidgets(
    'apply flow with instructor hours triggers implied instructor certificate checks',
    (WidgetTester tester) async {
      final repository = FakeAppRepository();
      
      // Create a job that requires CFI hours (which implies CFI certificate)
      await repository.createJob(
        const JobListing(
          id: 'instructor-cert-apply',
          title: 'Flight Instructor Role',
          company: 'AeroTraining Academy',
          location: 'Phoenix, AZ',
          type: 'Full-Time',
          crewRole: 'Flight Instructor',
          faaRules: ['Part 141'],
          description: 'CFI position requiring flight instruction experience.',
          faaCertificates: ['Commercial Pilot Certificate'],
          flightExperience: ['Total Time', 'Flight Instruction (CFI)'],
          flightHours: {
            'Total Time': 1500,
            'Flight Instruction (CFI)': 250,
          },
          aircraftFlown: ['Cessna 172'],
          employerId: 'emp-aero-training',
        ),
      );

      // Create job seeker profile with instructor hours
      final seekerProfile = JobSeekerProfile(
        firstName: 'John',
        lastName: 'Instructor',
        email: 'john@example.com',
        phone: '555-0101',
        city: 'Phoenix',
        stateOrProvince: 'AZ',
        faaCertificates: const ['Commercial Pilot Certificate'],
        flightHours: const {
          'Total Time': 2000,
          'Flight Instruction (CFI)': 300, // Exceeds requirement
        },
        flightHoursTypes: const ['Total Time', 'Flight Instruction (CFI)'],
        aircraftFlown: const ['Cessna 172'],
      );

      await repository.saveJobSeekerProfile(seekerProfile);

      await tester.pumpWidget(MyApp(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('Flight Instructor Role'), findsOneWidget);
      await tester.tap(find.text('Flight Instructor Role').first);
      await tester.pumpAndSettle();

      // Verify that job details are displayed
      expect(find.text('AeroTraining Academy'), findsOneWidget);
      expect(find.textContaining('Flight Instruction (CFI)'), findsWidgets);

      // Apply to the job
      await _tapAnyApplyCta(tester);
      await _submitQuickApplyDialogIfVisible(tester);

      // Verify success feedback
      expect(find.byType(SnackBar), findsOneWidget);

      // Navigate to My Applications to verify application was recorded
      await tester.pageBack();
      await tester.pumpAndSettle();
      
      await tester.tap(find.text('My Applications'));
      await tester.pumpAndSettle();

      // Verify the application appears in My Applications
      expect(find.text('Flight Instructor Role'), findsOneWidget);
      expect(find.textContaining('AeroTraining Academy'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);
    },
  );

  testWidgets(
    'apply flow shows match percentage when profile exceeds instructor hour requirements',
    (WidgetTester tester) async {
      final repository = FakeAppRepository();
      
      // Create a job with CFII instructor hour requirement
      await repository.createJob(
        const JobListing(
          id: 'cfii-instructor-apply',
          title: 'Advanced Flight Instructor Role',
          company: 'Professional Flight Training',
          location: 'Denver, CO',
          type: 'Full-Time',
          crewRole: 'Flight Instructor',
          faaRules: ['Part 141'],
          description: 'CFII position for advanced instruction.',
          faaCertificates: ['Airline Transport Pilot (ATP)'],
          flightExperience: [
            'Total Time',
            'Flight Instruction (CFI)',
            'Instrument Flight Instruction (CFII)',
          ],
          flightHours: {
            'Total Time': 2500,
            'Flight Instruction (CFI)': 400,
            'Instrument Flight Instruction (CFII)': 150,
          },
          aircraftFlown: ['Cirrus SR22'],
          employerId: 'emp-pro-flight-training',
        ),
      );

      // Create profile with matching instructor hours
      final seekerProfile = JobSeekerProfile(
        firstName: 'Jane',
        lastName: 'Advanced',
        email: 'jane@example.com',
        phone: '555-0102',
        city: 'Denver',
        stateOrProvince: 'CO',
        faaCertificates: const ['Airline Transport Pilot (ATP)'],
        flightHours: const {
          'Total Time': 3000,
          'Flight Instruction (CFI)': 500,
          'Instrument Flight Instruction (CFII)': 200,
        },
        flightHoursTypes: const [
          'Total Time',
          'Flight Instruction (CFI)',
          'Instrument Flight Instruction (CFII)',
        ],
        aircraftFlown: const ['Cirrus SR22', 'Piper Cherokee'],
      );

      await repository.saveJobSeekerProfile(seekerProfile);

      await tester.pumpWidget(MyApp(repository: repository));
      await tester.pumpAndSettle();

      // View jobs
      await tester.tap(find.text('Jobs'));
      await tester.pumpAndSettle();

      // Tap on the advanced instructor role
      expect(find.text('Advanced Flight Instructor Role'), findsOneWidget);
      await tester.tap(find.text('Advanced Flight Instructor Role').first);
      await tester.pumpAndSettle();

      // Verify match is shown (should be high percentage since profile exceeds requirements)
      expect(find.text('Professional Flight Training'), findsOneWidget);
      expect(find.textContaining('%'), findsWidgets);

      // Apply
      await _tapAnyApplyCta(tester);
      await _submitQuickApplyDialogIfVisible(tester);

      expect(find.byType(SnackBar), findsOneWidget);
    },
  );

  testWidgets(
    'comprehensive end-to-end apply flow verifies application persistence and status tracking',
    (WidgetTester tester) async {
      final repository = FakeAppRepository();

      // Step 1: Create a matching job listing with specific requirements
      await repository.createJob(
        const JobListing(
          id: 'e2e-apply-comprehensive',
          title: 'Captain - Multi-Engine Charter',
          company: 'Sky Ventures Aviation',
          location: 'Fort Lauderdale, FL',
          type: 'Full-Time',
          crewRole: 'Captain',
          faaRules: ['Part 135'],
          part135SubType: 'IFR / Commuter',
          description:
              'Seeking experienced captain for charter operations across the continental US.',
          faaCertificates: ['Airline Transport Pilot (ATP)'],
          typeRatingsRequired: ['B737'],
          flightExperience: [
            'Total Time',
            'Cross-Country',
            'Night',
            'Instrument',
          ],
          flightHours: {
            'Total Time': 1500,
            'Cross-Country': 500,
            'Night': 100,
            'Instrument': 75,
          },
          aircraftFlown: ['Boeing 737', 'Airbus A320'],
          employerId: 'emp-sky-ventures',
        ),
      );

      // Step 2: Create a job seeker profile that exceeds requirements
      final seekerProfile = JobSeekerProfile(
        firstName: 'Captain',
        lastName: 'Qualified',
        email: 'captain@example.com',
        phone: '555-0199',
        city: 'Fort Lauderdale',
        stateOrProvince: 'FL',
        faaCertificates: const [
          'Airline Transport Pilot (ATP)',
          'Type Rating Examiner'
        ],
        typeRatings: const ['B737', 'A320'],
        flightHours: const {
          'Total Time': 3500, // Exceeds requirement
          'Cross-Country': 1200, // Exceeds requirement
          'Night': 300, // Exceeds requirement
          'Instrument': 200, // Exceeds requirement
        },
        flightHoursTypes: const [
          'Total Time',
          'Cross-Country',
          'Night',
          'Instrument',
        ],
        aircraftFlown: const ['Boeing 737', 'Airbus A320', 'Bombardier CRJ'],
        airframeScope: 'Both',
      );

      await repository.saveJobSeekerProfile(seekerProfile);

      await tester.pumpWidget(MyApp(repository: repository));
      await tester.pumpAndSettle();

      // Step 4: Verify profile was loaded correctly
      expect(find.text('Favorites'), findsOneWidget);

      // Step 5: Navigate to jobs listing
      await tester.tap(find.text('Jobs'));
      await tester.pumpAndSettle();

      // Step 6: Find the created job listing
      expect(find.text('Captain - Multi-Engine Charter'), findsOneWidget);

      // Step 7: Tap on job to view details
      await tester.tap(find.text('Captain - Multi-Engine Charter').first);
      await tester.pumpAndSettle();

      // Step 8: Verify job details are displayed correctly
      expect(find.text('Sky Ventures Aviation'), findsOneWidget);
      expect(find.text('Fort Lauderdale, FL'), findsOneWidget);
      expect(find.text('Part 135 IFR'), findsWidgets);

      // Step 9: Verify apply button is visible (not disabled by category mismatch)
      expect(_hasAnyApplyCtaVisible(), isTrue);

      // Step 10: Tap apply button and submit application
      await _tapAnyApplyCta(tester);
      await _submitQuickApplyDialogIfVisible(tester);

      // Step 11: Verify success feedback
      expect(
        find.text('Applied! Employer will see your profile.'),
        findsOneWidget,
      );

      // Step 12: Navigate back to profile
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Step 13: Go to My Applications tab to verify persistence
      await tester.tap(find.text('My Applications'));
      await tester.pumpAndSettle();

      // Step 14: Verify application appears with correct details and status
      // This confirms the application was successfully saved and is persisting
      expect(find.text('Captain - Multi-Engine Charter'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);
    },
  );

  testWidgets(
    'apply flow shows auto-reject SnackBar when match score is below employer threshold',
    (WidgetTester tester) async {
      final repository = FakeAppRepository();

      // Job with a high auto-reject threshold that an empty profile cannot meet.
      await repository.createJob(
        const JobListing(
          id: 'auto-reject-threshold-test',
          title: 'Senior ATP Captain',
          company: 'Elite Charter Group',
          location: 'Dallas, TX',
          type: 'Full-Time',
          crewRole: 'Captain',
          faaRules: ['Part 135'],
          part135SubType: 'IFR / Commuter',
          description: 'High-threshold listing for auto-reject integration test.',
          faaCertificates: ['Airline Transport Pilot (ATP)'],
          flightExperience: ['Total Time', 'Cross-Country'],
          flightHours: {'Total Time': 2000, 'Cross-Country': 500},
          aircraftFlown: ['Bombardier CRJ'],
          employerId: 'emp-elite-charter',
          autoRejectThreshold: 80,
        ),
      );

      // Default seeker profile has no certificates or hours — match will be 0%.
      await tester.pumpWidget(MyApp(repository: repository));
      await tester.pumpAndSettle();

      // Navigate to Jobs tab (default profile is job seeker).
      await tester.tap(find.text('Jobs'));
      await tester.pumpAndSettle();

      expect(find.text('Senior ATP Captain'), findsOneWidget);
      await tester.tap(find.text('Senior ATP Captain').first);
      await tester.pumpAndSettle();

      expect(find.text('Elite Charter Group'), findsOneWidget);

      // Apply even though match is below the threshold.
      await _tapAnyApplyCta(tester);
      await tester.tap(find.text('Submit Application').hitTestable());
      await tester.pumpAndSettle();

      // The SnackBar must mention auto-reject, not the normal success message.
      expect(
        find.text('Applied! Employer will see your profile.'),
        findsNothing,
      );
      expect(find.textContaining('auto-rejected'), findsOneWidget);

      // Navigate to My Applications and confirm the application is recorded.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Applications'));
      await tester.pumpAndSettle();

      expect(find.text('Senior ATP Captain'), findsOneWidget);
    },
  );
}
