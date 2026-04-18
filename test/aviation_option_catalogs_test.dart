import 'package:flutter_test/flutter_test.dart';

import 'package:aviation_job_listings/models/aviation_option_catalogs.dart';

void main() {
  test('specialty experience options include Ski-plane', () {
    expect(availableSpecialtyExperienceOptions, contains('Ski-plane'));
  });

  test('specialty experience options keep Ski-plane near Floatplane', () {
    final floatplaneIndex = availableSpecialtyExperienceOptions.indexOf(
      'Floatplane',
    );
    final skiPlaneIndex = availableSpecialtyExperienceOptions.indexOf(
      'Ski-plane',
    );

    expect(floatplaneIndex, isNonNegative);
    expect(skiPlaneIndex, floatplaneIndex + 1);
  });

  test('rating groups flatten to the shared rating option list', () {
    final flattened = groupedRatingSelectionOptions.expand((group) => group);
    expect(flattened.toList(), availableRatingSelectionOptions);
  });

  test('instructor hour option set matches instructor hour list', () {
    expect(instructorHourOptionSet, availableInstructorHourOptions.toSet());
  });

  test('shared option catalogs stay unique', () {
    final optionLists = <List<String>>[
      availableFaaCertificateOptions,
      availableInstructorCertificateOptions,
      availableFaaRuleOptions,
      availableEmployerFlightHourOptions,
      availableInstructorHourOptions,
      availableSpecialtyExperienceOptions,
      availableJobTypeOptions,
      availablePayRateMetricOptions,
      availableRatingSelectionOptions,
    ];

    for (final options in optionLists) {
      expect(options.toSet().length, options.length);
    }
  });
}
