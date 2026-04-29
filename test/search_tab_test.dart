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
  await repository.createJob(
    const JobListing(
      id: 'search-6-expired',
      title: 'Expired Test Role',
      company: 'Legacy Air',
      location: 'Anchorage, AK',
      type: 'Full-Time',
      crewRole: 'Single Pilot',
      faaRules: ['Part 91'],
      description: 'Expired listing fixture for status filter tests.',
      faaCertificates: [],
      flightExperience: [],
      aircraftFlown: ['Beechcraft 1900'],
      status: 'expired',
    ),
  );

  await tester.pumpWidget(MyApp(repository: repository));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Filter').last);
  await tester.pumpAndSettle();
  expect(find.text('Location Search'), findsOneWidget);
  expect(find.text('Showing 5 of 5 jobs'), findsOneWidget);
}

Future<void> _openFiltersDrawer(WidgetTester tester) async {
  final openFiltersButton = find.text('Open Filters');
  final expandFiltersButton = find.text('Expand Filters');
  if (openFiltersButton.evaluate().isNotEmpty) {
    await tester.tap(openFiltersButton.hitTestable().first);
    await tester.pumpAndSettle();
  } else if (expandFiltersButton.evaluate().isNotEmpty) {
    await tester.tap(expandFiltersButton.hitTestable().first);
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

Future<void> _submitCitySearch(WidgetTester tester, String city) async {
  final cityRow = find.ancestor(
    of: find.byTooltip('Search city'),
    matching: find.byType(Row),
  ).first;
  final cityField = find.descendant(
    of: cityRow,
    matching: find.byType(TextField),
  ).first;
  await tester.enterText(cityField, city);
  final widget = tester.widget<TextField>(cityField);
  widget.onSubmitted?.call(city);
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

    final unitedStatesChip = find.ancestor(
      of: find.text('United States').first,
      matching: find.byType(ChoiceChip),
    );
    await tester.ensureVisible(unitedStatesChip.first);
    await tester.pumpAndSettle();
    await tester.tap(unitedStatesChip.first);
    await tester.pumpAndSettle();

    expect(find.text('Showing 4 of 5 jobs'), findsOneWidget);
  });

  testWidgets('search tab location bucket filters support International', (
    WidgetTester tester,
  ) async {
    await _pumpSearchTab(tester);

    final internationalChip = find.ancestor(
      of: find.text('International').first,
      matching: find.byType(ChoiceChip),
    );
    await tester.ensureVisible(internationalChip.first);
    await tester.pumpAndSettle();
    await tester.tap(internationalChip.first);
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 5 jobs'), findsOneWidget);
  });

  testWidgets('search tab supports city search and match filters', (
    WidgetTester tester,
  ) async {
    await _pumpSearchTab(tester);

    await _submitCitySearch(tester, 'Miami');
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

  testWidgets('search tab can include expired listings and shows expired flag', (
    WidgetTester tester,
  ) async {
    await _pumpSearchTab(tester);

    expect(find.text('Showing 5 of 5 jobs'), findsOneWidget);
    expect(find.text('Expired'), findsNothing);

    final statusChip = find.byKey(
      const ValueKey('search-status-active-or-expired'),
    );
    await tester.dragUntilVisible(
      statusChip,
      find.byKey(const ValueKey('search-tab-scroll')),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    await tester.tap(statusChip);
    await tester.pumpAndSettle();

    expect(find.text('Showing 6 of 6 jobs'), findsOneWidget);
  await _submitCitySearch(tester, 'Anchorage');
    expect(find.text('Showing 1 of 6 jobs'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('search-tab-scroll')),
      const Offset(0, -1800),
    );
    await tester.pumpAndSettle();
    expect(find.text('Expired'), findsWidgets);
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
    await tester.tap(find.text('Filter').last);
    await tester.pumpAndSettle();

    expect(find.text('Showing 2 of 2 jobs'), findsOneWidget);

    await _selectFilterOption(
      tester,
      sectionTitle: 'Instructor',
      optionText: 'Flight Instructor (CFI)',
    );

    expect(find.text('Showing 1 of 2 jobs'), findsOneWidget);

    await _submitCitySearch(tester, 'Dallas');

    expect(find.text('Showing 0 of 2 jobs'), findsOneWidget);
  });

  testWidgets(
    'search tab location search matches state and province full names against abbreviations',
    (WidgetTester tester) async {
      final repository = FakeAppRepository();
      await repository.createJob(
        const JobListing(
          id: 'state-query-1',
          title: 'Mountain Utility Pilot',
          company: 'Northern Lift',
          location: 'Anchorage, AK',
          type: 'Full-Time',
          crewRole: 'Single Pilot',
          faaRules: ['Part 135'],
          description: 'Utility operations in remote regions.',
          faaCertificates: [],
          flightExperience: [],
          aircraftFlown: ['Bell 407'],
        ),
      );
      await repository.createJob(
        const JobListing(
          id: 'state-query-2',
          title: 'Regional Charter Pilot',
          company: 'Prairie Wings',
          location: 'Calgary, AB',
          type: 'Full-Time',
          crewRole: 'Crew',
          crewPosition: 'Captain',
          faaRules: ['Part 91'],
          description: 'Regional charter flights across western Canada.',
          faaCertificates: [],
          flightExperience: [],
          aircraftFlown: ['King Air 200'],
        ),
      );
      await repository.createJob(
        const JobListing(
          id: 'state-query-3',
          title: 'International Coordinator',
          company: 'Global Routes',
          location: 'London, UK',
          type: 'Contract',
          crewRole: 'Crew',
          crewPosition: 'Dispatcher',
          faaRules: ['Part 91'],
          description: 'Cross-border dispatch and scheduling.',
          faaCertificates: [],
          flightExperience: [],
          aircraftFlown: ['Learjet 75'],
        ),
      );

      await tester.pumpWidget(MyApp(repository: repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filter').last);
      await tester.pumpAndSettle();

      expect(find.text('Showing 3 of 3 jobs'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Alaska');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alaska (AK)').last);
      await tester.pumpAndSettle();
      expect(find.text('Showing 1 of 3 jobs'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'AK');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alaska (AK)').last);
      await tester.pumpAndSettle();
      expect(find.text('Showing 1 of 3 jobs'), findsOneWidget);

      final canadaChip = find.ancestor(
        of: find.text('Canada').first,
        matching: find.byType(ChoiceChip),
      );
      await tester.tap(canadaChip.first);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Alberta');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alberta (AB)').last);
      await tester.pumpAndSettle();
      expect(find.text('Showing 1 of 3 jobs'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'AB');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alberta (AB)').last);
      await tester.pumpAndSettle();
      expect(find.text('Showing 1 of 3 jobs'), findsOneWidget);
    },
  );
}
