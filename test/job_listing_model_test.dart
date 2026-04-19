import 'package:flutter_test/flutter_test.dart';

import 'package:aviation_job_listings/models/job_listing.dart';

void main() {
  test('JobListing preserves external fields through JSON round-trip', () {
    final source = JobListing.fromJson({
      'id': 'external-json-roundtrip',
      'title': 'External Roundtrip Role',
      'company': 'Mountain Air Charter',
      'location': 'Boise, ID',
      'type': 'Full-Time',
      'crewRole': 'Single Pilot',
      'faaRules': const <String>['Part 91'],
      'description': 'Validates external field persistence.',
      'faaCertificates': const <String>[],
      'flightExperience': const <String>[],
      'aircraftFlown': const <String>[],
      'isExternal': true,
      'externalApplyUrl': 'https://example.com/apply',
      'contactName': 'Hiring Team',
      'companyPhone': '+1-208-555-0100',
      'contactEmail': 'hiring@mountainaircharter.com',
      'companyUrl': 'https://mountainaircharter.com',
    });

    final encoded = source.toJson();
    final decoded = JobListing.fromJson(encoded);

    expect(decoded.isExternal, isTrue);
    expect(decoded.externalApplyUrl, 'https://example.com/apply');
    expect(decoded.contactName, 'Hiring Team');
    expect(decoded.companyPhone, '+1-208-555-0100');
    expect(decoded.contactEmail, 'hiring@mountainaircharter.com');
    expect(decoded.companyUrl, 'https://mountainaircharter.com');
  });

  test('JobListing.copyWith keeps external fields unless explicitly changed', () {
    const source = JobListing(
      id: 'external-copywith-source',
      title: 'External CopyWith Source',
      company: 'Mountain Air Charter',
      location: 'Boise, ID',
      type: 'Full-Time',
      crewRole: 'Single Pilot',
      faaRules: ['Part 91'],
      description: 'Validates copyWith behavior for external fields.',
      faaCertificates: [],
      flightExperience: [],
      aircraftFlown: [],
      isExternal: true,
      externalApplyUrl: 'https://example.com/apply',
      contactName: 'Hiring Team',
      companyPhone: '+1-208-555-0100',
      contactEmail: 'hiring@mountainaircharter.com',
      companyUrl: 'https://mountainaircharter.com',
    );

    final unchanged = source.copyWith(title: 'Updated Title');
    expect(unchanged.isExternal, isTrue);
    expect(unchanged.externalApplyUrl, 'https://example.com/apply');
    expect(unchanged.contactName, 'Hiring Team');
    expect(unchanged.companyPhone, '+1-208-555-0100');
    expect(unchanged.contactEmail, 'hiring@mountainaircharter.com');
    expect(unchanged.companyUrl, 'https://mountainaircharter.com');

    final changed = source.copyWith(
      isExternal: false,
      externalApplyUrl: null,
      contactName: null,
      companyPhone: null,
      contactEmail: null,
      companyUrl: null,
    );
    expect(changed.isExternal, isFalse);
    expect(changed.externalApplyUrl, isNull);
    expect(changed.contactName, isNull);
    expect(changed.companyPhone, isNull);
    expect(changed.contactEmail, isNull);
    expect(changed.companyUrl, isNull);
  });
}
