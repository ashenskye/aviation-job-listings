import 'package:flutter_test/flutter_test.dart';

import 'package:aviation_job_listings/models/job_seeker_profile.dart';

void main() {
  test('fromJson splits legacy fullName into first and last name', () {
    final profile = JobSeekerProfile.fromJson(const {
      'fullName': 'Amelia Earhart',
      'email': 'amelia@example.com',
    });

    expect(profile.firstName, 'Amelia');
    expect(profile.lastName, 'Earhart');
    expect(profile.fullName, 'Amelia Earhart');
  });

  test('copyWith keeps fullName aligned when first and last name change', () {
    const profile = JobSeekerProfile(
      firstName: 'Bessie',
      lastName: 'Coleman',
      fullName: 'Bessie Coleman',
    );

    final updated = profile.copyWith(firstName: 'Katherine', lastName: 'Johnson');

    expect(updated.firstName, 'Katherine');
    expect(updated.lastName, 'Johnson');
    expect(updated.fullName, 'Katherine Johnson');
  });
}