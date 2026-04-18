import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aviation_job_listings/main.dart';
import 'package:aviation_job_listings/models/job_listing.dart';
import 'package:aviation_job_listings/models/job_seeker_profile.dart';

void main() {
  testWidgets('Job details shows unmet comparison details without toggle labels', (
    WidgetTester tester,
  ) async {
    const job = JobListing(
      id: 'job-1',
      title: 'First Officer',
      company: 'Aero Co',
      location: 'USA',
      type: 'Full-Time',
      crewRole: 'Crew',
      crewPosition: 'Co-Pilot',
      faaRules: ['Part 135'],
      description: 'Role',
      faaCertificates: ['Commercial Pilot (CPL)'],
      flightExperience: ['Cross Country'],
      flightHours: {'Cross Country': 100},
      aircraftFlown: ['Cessna 172'],
    );

    const profile = JobSeekerProfile();

    await tester.pumpWidget(
      const MaterialApp(
        home: JobDetailsPage(
          job: job,
          isFavorite: false,
          onFavorite: _noop,
          profile: profile,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Commercial Pilot (CPL) (Not yet met)'), findsNothing);
    expect(find.text('Commercial Pilot (CPL)'), findsWidgets);
    expect(
      find.text('Current: 0 hrs • Required: 100 hrs • Progress: 0%'),
      findsOneWidget,
    );
    expect(find.text('Showing all comparisons'), findsNothing);
    expect(find.text('Showing unmet minimums only'), findsNothing);
  });
}

void _noop() {}
