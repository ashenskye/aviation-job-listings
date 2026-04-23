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

Future<void> _openFiltersDrawer(WidgetTester tester) async {
  final openFiltersButton = find.text('Open Filters');
  if (openFiltersButton.evaluate().isNotEmpty) {
    await tester.tap(openFiltersButton.hitTestable().first);
    await tester.pumpAndSettle();
  }
  expect(find.byKey(const ValueKey('search-primary-filters-open')), findsOneWidget);
}

void _invokeTapCallback(WidgetTester tester, Finder target) {
  if (target.evaluate().isEmpty) {
    throw TestFailure('Expected tappable target was not found.');
  }
  final widget = tester.widget(target.first);
  if (widget is InkWell) {
    widget.onTap?.call();
    return;
  }
  if (widget is FilledButton) {
    widget.onPressed?.call();
    return;
  }
  if (widget is OutlinedButton) {
    widget.onPressed?.call();
    return;
  }
  if (widget is TextButton) {
    widget.onPressed?.call();
    return;
  }
  throw TestFailure('Found target does not expose a tap callback.');
}

Future<void> _expandFilterSection(WidgetTester tester, String title) async {
  await _openFiltersDrawer(tester);
  final filtersCard = find.byKey(const ValueKey('search-primary-filters-open'));
  final titleFinder = find.descendant(of: filtersCard, matching: find.text(title));
  expect(titleFinder, findsWidgets);
  final tapTarget = find.ancestor(
    of: titleFinder.first,
    matching: find.byType(InkWell),
  );
  if (tapTarget.evaluate().isNotEmpty) {
    _invokeTapCallback(tester, tapTarget);
  } else {
    _invokeTapCallback(tester, titleFinder);
  }
  await tester.pumpAndSettle();
}

Future<void> _selectFilterOption(
  WidgetTester tester, {
  required String sectionTitle,
  required String optionText,
}) async {
  await _openFiltersDrawer(tester);
  final filtersCard = find.byKey(const ValueKey('search-primary-filters-open'));
  var optionFinder = find.descendant(
    of: filtersCard,
    matching: find.text(optionText),
  );
  if (optionFinder.evaluate().isEmpty) {
    await _expandFilterSection(tester, sectionTitle);
    optionFinder = find.descendant(
      of: filtersCard,
      matching: find.text(optionText),
    );
  }
  expect(optionFinder, findsWidgets);
  await tester.ensureVisible(optionFinder.first);
  final optionTapTarget = find.ancestor(
    of: optionFinder.first,
    matching: find.byType(InkWell),
  );
  if (optionTapTarget.evaluate().isNotEmpty) {
    _invokeTapCallback(tester, optionTapTarget);
  } else {
    _invokeTapCallback(tester, optionFinder);
  }
  await tester.pumpAndSettle();

  final applyButtonText = find.descendant(
    of: filtersCard,
    matching: find.text('Apply'),
  );
  expect(applyButtonText, findsOneWidget);
  final applyTapTarget = find.ancestor(
    of: applyButtonText,
    matching: find.byType(FilledButton),
  );
  _invokeTapCallback(tester, applyTapTarget);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('search tab FAA rule filter shows Part 135 IFR and VFR options', (
    WidgetTester tester,
  ) async {
    await _pumpSearchTab(tester);

    await _expandFilterSection(tester, 'FAA Rule');
    final filtersCard = find.byKey(const ValueKey('search-primary-filters-open'));
    expect(
      find.descendant(of: filtersCard, matching: find.text('Part 135 IFR')),
      findsWidgets,
    );
    expect(
      find.descendant(of: filtersCard, matching: find.text('Part 135 VFR')),
      findsWidgets,
    );

    await _selectFilterOption(
      tester,
      sectionTitle: 'FAA Rule',
      optionText: 'Part 135 VFR',
    );
    expect(find.text('Showing 1 of 5 jobs'), findsOneWidget);
  });

  testWidgets('search tab filters by position from primary filters', (
    WidgetTester tester,
  ) async {
    await _pumpSearchTab(tester);

    await _selectFilterOption(
      tester,
      sectionTitle: 'Position',
      optionText: 'Crew Member: Co-Pilot',
    );

    expect(find.text('Showing 1 of 5 jobs'), findsOneWidget);
  });

  testWidgets('search tab location bucket filters support USA and International', (
    WidgetTester tester,
  ) async {
    await _pumpSearchTab(tester);

    await _selectFilterOption(
      tester,
      sectionTitle: 'Location',
      optionText: 'USA',
    );
    expect(find.text('Showing 4 of 5 jobs'), findsOneWidget);
  });

  testWidgets('search tab location bucket filters support International', (
    WidgetTester tester,
  ) async {
    await _pumpSearchTab(tester);

    await _selectFilterOption(
      tester,
      sectionTitle: 'Location',
      optionText: 'International',
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

    final matchField = find.byKey(const ValueKey('search-tab-match-percent'));
    await tester.ensureVisible(matchField);
    await tester.pumpAndSettle();

    await tester.enterText(matchField, '70');
    await tester.pumpAndSettle();
    expect(find.text('Qualifications Match: 70%+'), findsOneWidget);

    await tester.enterText(matchField, '0');
    await tester.pumpAndSettle();
    expect(find.text('Qualifications Match: 70%+'), findsNothing);
    expect(find.text('Showing 5 of 5 jobs'), findsOneWidget);
  });

  testWidgets('search tab supports certificate filter category', (
    WidgetTester tester,
  ) async {
    await _pumpSearchTab(tester);

    await _selectFilterOption(
      tester,
      sectionTitle: 'Certificate',
      optionText: 'Airline Transport Pilot (ATP)',
    );
    expect(find.text('Showing 1 of 5 jobs'), findsOneWidget);
  });

  testWidgets('search tab supports rating filter category', (
    WidgetTester tester,
  ) async {
    await _pumpSearchTab(tester);

    await _selectFilterOption(
      tester,
      sectionTitle: 'Rating',
      optionText: 'Multi-Engine Land',
    );
    expect(find.text('Showing 1 of 5 jobs'), findsOneWidget);
  });

  testWidgets('search tab supports flight instruction filter', (
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
        instructorHours: {'Flight Instruction (CFI)': 300},
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

    await _selectFilterOption(
      tester,
      sectionTitle: 'Flight Instruction',
      optionText: 'Flight Instructor (CFI)',
    );

    expect(find.text('Showing 1 of 2 jobs'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('search-tab-query')),
      'Ramp Agent',
    );
    await tester.pumpAndSettle();

    expect(find.text('Showing 0 of 2 jobs'), findsOneWidget);
  });
}
