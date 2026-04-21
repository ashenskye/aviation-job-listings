import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aviation_job_listings/main.dart';
import 'package:aviation_job_listings/models/job_listing.dart';

import 'helpers/fake_app_repository.dart';

Future<void> _pumpSearchTab(WidgetTester tester) async {
  final repository = FakeAppRepository();
  await repository.createJob(
    const JobListing(
      id: 'search-1',
      title: 'Rescue Pilot',
      company: 'Sky Rescue',
      location: 'Dallas, TX',
      type: 'Full-Time',
      crewRole: 'Single Pilot',
      faaRules: ['Part 135'],
      part135SubType: 'ifr',
      description: 'Rescue and medevac operations.',
      faaCertificates: ['Airline Transport Pilot (ATP)'],
      flightExperience: [],
      aircraftFlown: ['Cessna 208'],
    ),
  );
  await repository.createJob(
    const JobListing(
      id: 'search-2',
      title: 'Ramp Coordinator',
      company: 'Ground Ops',
      location: 'Dallas, TX',
      type: 'Part-Time',
      crewRole: 'Crew',
      crewPosition: 'Ground',
      faaRules: ['Part 91'],
      description: 'Coordinate ground and ramp activity.',
      faaCertificates: [],
      flightExperience: [],
      aircraftFlown: ['Tug'],
    ),
  );
  await repository.createJob(
    const JobListing(
      id: 'search-3',
      title: 'Charter Dispatcher',
      company: 'Southwind Charter',
      location: 'Miami, FL',
      type: 'Contract',
      crewRole: 'Crew',
      crewPosition: 'Dispatcher',
      faaRules: ['Part 135'],
      part135SubType: 'vfr',
      description: 'Dispatch and flight planning support.',
      faaCertificates: [],
      flightExperience: [],
      aircraftFlown: ['Piper Navajo'],
    ),
  );
  await repository.createJob(
    const JobListing(
      id: 'search-4',
      title: 'International Liaison Pilot',
      company: 'Global Wings',
      location: 'London, UK',
      type: 'Seasonal',
      crewRole: 'Crew',
      crewPosition: 'Captain',
      faaRules: ['Part 91'],
      description: 'Coordinate cross-border operations.',
      faaCertificates: [],
      flightExperience: [],
      aircraftFlown: ['Learjet 45'],
    ),
  );
  await repository.createJob(
    const JobListing(
      id: 'search-5',
      title: 'Regional First Officer',
      company: 'Metro Air',
      location: 'Phoenix, AZ',
      type: 'Full-Time',
      crewRole: 'Crew',
      crewPosition: 'Co-Pilot',
      faaRules: ['Part 91'],
      description: 'First officer support on regional routes.',
      faaCertificates: [],
      requiredRatings: ['Multi-Engine Land'],
      flightExperience: [],
      aircraftFlown: ['Embraer E-175'],
    ),
  );

  await tester.pumpWidget(MyApp(repository: repository));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Search').last);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('search-tab-query')), findsOneWidget);
  expect(find.text('Showing 5 of 5 jobs'), findsOneWidget);
}

Future<void> _selectDropdownOption(
  WidgetTester tester,
  String dropdownKey,
  String optionText,
) async {
  final dropdownFinder = find.byKey(ValueKey(dropdownKey));
  await tester.ensureVisible(dropdownFinder);
  await tester.pumpAndSettle();
  await tester.tap(dropdownFinder.hitTestable().first);
  await tester.pumpAndSettle();
  final optionFinder = find.descendant(
    of: find.byType(Overlay),
    matching: find.text(optionText),
  );
  expect(optionFinder, findsWidgets);
  await tester.tap(optionFinder.hitTestable().first);
  await tester.pumpAndSettle();
}

Future<void> _expandFilterSection(WidgetTester tester, String title) async {
  final titleFinder = find.text(title);
  final tileFinder = find.ancestor(of: titleFinder, matching: find.byType(ListTile));
  final tile = tester.widget<ListTile>(tileFinder.first);
  tile.onTap?.call();
  await tester.pumpAndSettle();
}

Future<void> _expandEmployerFilters(WidgetTester tester) async {
  await _expandFilterSection(tester, 'Advanced Filters');
}

void main() {
  testWidgets('search tab FAA rule filter shows Part 135 IFR and VFR options', (
    WidgetTester tester,
  ) async {
    await _pumpSearchTab(tester);

    final dropdownFinder = find.byKey(const ValueKey('search-tab-faa-rule-filter'));
    await tester.ensureVisible(dropdownFinder);
    await tester.pumpAndSettle();
    await tester.tap(dropdownFinder.hitTestable().first);
    await tester.pumpAndSettle();

    final ifrOption = find.descendant(
      of: find.byType(Overlay),
      matching: find.text('Part 135 IFR'),
    );
    final vfrOption = find.descendant(
      of: find.byType(Overlay),
      matching: find.text('Part 135 VFR'),
    );
    expect(ifrOption, findsWidgets);
    expect(vfrOption, findsWidgets);

    await tester.tap(vfrOption.hitTestable().first);
    await tester.pumpAndSettle();
  });

  testWidgets('search tab filters by position from primary filters', (
    WidgetTester tester,
  ) async {
    await _pumpSearchTab(tester);

    await _selectDropdownOption(
      tester,
      'search-tab-position-filter',
      'Crew Member: Co-Pilot',
    );

    expect(find.text('Showing 1 of 5 jobs'), findsOneWidget);
  });

  testWidgets('search tab location bucket filters support USA and International', (
    WidgetTester tester,
  ) async {
    await _pumpSearchTab(tester);

    await _selectDropdownOption(tester, 'search-tab-location-filter', 'USA');
    expect(find.text('Showing 4 of 5 jobs'), findsOneWidget);
  });

  testWidgets('search tab location bucket filters support International', (
    WidgetTester tester,
  ) async {
    await _pumpSearchTab(tester);

    await _selectDropdownOption(
      tester,
      'search-tab-location-filter',
      'International',
    );
    expect(find.text('Showing 1 of 5 jobs'), findsOneWidget);
  });

  testWidgets('search tab supports query and match filters', (
    WidgetTester tester,
  ) async {
    await _pumpSearchTab(tester);

    await tester.enterText(
      find.byKey(const ValueKey('search-tab-query')),
      'Rescue',
    );
    await tester.pumpAndSettle();
    expect(find.text('Showing 1 of 5 jobs'), findsOneWidget);
  });

  testWidgets('search tab supports match filters', (
    WidgetTester tester,
  ) async {
    await _pumpSearchTab(tester);

    final stretchChip = find.widgetWithText(ChoiceChip, '<70%');
    await tester.ensureVisible(stretchChip);
    await tester.pumpAndSettle();
    await tester.tap(stretchChip.hitTestable().first);
    await tester.pumpAndSettle();

    expect(find.text('Showing 2 of 5 jobs'), findsOneWidget);
  });

  testWidgets('search tab supports certificate filter category', (
    WidgetTester tester,
  ) async {
    await _pumpSearchTab(tester);
    await _expandEmployerFilters(tester);

    await _selectDropdownOption(
      tester,
      'search-tab-certificate-filter',
      'Airline Transport Pilot (ATP)',
    );
    expect(find.text('Showing 1 of 5 jobs'), findsOneWidget);
  });

  testWidgets('search tab supports rating filter category', (
    WidgetTester tester,
  ) async {
    await _pumpSearchTab(tester);
    await _expandEmployerFilters(tester);

    await _selectDropdownOption(
      tester,
      'search-tab-rating-filter',
      'Multi-Engine Land',
    );
    expect(find.text('Showing 1 of 5 jobs'), findsOneWidget);
  });

  testWidgets('search tab supports instructor-only toggle', (
    WidgetTester tester,
  ) async {
    final repository = FakeAppRepository();
    await repository.createJob(
      const JobListing(
        id: 'instructor-role-1',
        title: 'Flight Instructor',
        company: 'Lift Academy',
        location: 'Mesa, AZ',
        type: 'Full-Time',
        crewRole: 'Single Pilot',
        faaRules: ['Part 91'],
        description: 'Train student pilots and run CFI checkout flights.',
        faaCertificates: ['Flight Instructor (CFI)'],
        flightExperience: [],
        instructorHours: {'Total Instructor Hours': 300},
        aircraftFlown: ['Cessna 172'],
      ),
    );
    await repository.createJob(
      const JobListing(
        id: 'non-instructor-role-1',
        title: 'Ramp Agent',
        company: 'Regional Ops',
        location: 'Mesa, AZ',
        type: 'Full-Time',
        crewRole: 'Crew',
        crewPosition: 'Ground',
        faaRules: ['Part 91'],
        description: 'Support ramp and turn operations.',
        faaCertificates: [],
        flightExperience: [],
        aircraftFlown: ['Tug'],
      ),
    );

    await tester.pumpWidget(MyApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search').last);
    await tester.pumpAndSettle();

    expect(find.text('Showing 2 of 2 jobs'), findsOneWidget);

    final instructorOnlyChip = find.byKey(
      const ValueKey('search-tab-instructor-only'),
    );
    await tester.ensureVisible(instructorOnlyChip);
    await tester.tap(instructorOnlyChip.first);
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 2 jobs'), findsOneWidget);
    expect(find.text('Instructor Filters'), findsOneWidget);
    expect(find.text('Instructor Hours Category'), findsOneWidget);

    await _expandFilterSection(tester, 'Instructor Filters');
    await _expandFilterSection(tester, 'Instructor Filters');

    await tester.enterText(
      find.byKey(const ValueKey('search-tab-query')),
      'Ramp Agent',
    );
    await tester.pumpAndSettle();

    expect(find.text('Showing 0 of 2 jobs'), findsOneWidget);
  });
}
