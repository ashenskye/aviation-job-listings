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
  await tester.scrollUntilVisible(
    dropdownFinder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(dropdownFinder);
  await tester.pumpAndSettle();
  final optionFinder = find.text(optionText);
  expect(optionFinder, findsWidgets);
  await tester.tap(optionFinder.first);
  await tester.pumpAndSettle();
}

Future<void> _expandEmployerFilters(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Employer Listing Filters'));
  await tester.tap(find.text('Employer Listing Filters'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('search tab filters by FAA rule from employer options', (
    WidgetTester tester,
  ) async {
    await _pumpSearchTab(tester);
    await _expandEmployerFilters(tester);

    await _selectDropdownOption(
      tester,
      'search-tab-faa-rule-filter',
      'Part 135',
    );

    expect(find.text('Showing 2 of 5 jobs'), findsOneWidget);
  });

  testWidgets('search tab filters by position from employer options', (
    WidgetTester tester,
  ) async {
    await _pumpSearchTab(tester);
    await _expandEmployerFilters(tester);

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

    await tester.ensureVisible(find.text('<70%'));
    await tester.tap(find.text('<70%'));
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
}
