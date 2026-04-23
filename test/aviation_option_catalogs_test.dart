import 'package:flutter_test/flutter_test.dart';

import 'package:aviation_job_listings/models/aviation_option_catalogs.dart';

void main() {
  test('specialty experience options include Alaska Time', () {
    expect(availableSpecialtyExperienceOptions, contains('Alaska Time'));
  });

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

  test('instructor hour option set includes UI options and legacy alias', () {
    expect(instructorHourOptionSet, containsAll(availableInstructorHourOptions));
    expect(instructorHourOptionSet, contains(legacyTotalInstructorHoursLabel));
  });

  test('flight hour options keep Instrument below Multi-engine, Cross-Country and Night below Instrument', () {
    final opts = availableEmployerFlightHourOptions;
    final multiEngineIndex = opts.indexOf('Multi-engine');
    final instrumentIndex = opts.indexOf('Instrument');
    final crossCountryIndex = opts.indexOf('Cross-Country');
    final nightIndex = opts.indexOf('Night');

    expect(multiEngineIndex, isNonNegative);
    expect(instrumentIndex, multiEngineIndex + 2);
    expect(crossCountryIndex, instrumentIndex + 1);
    expect(nightIndex, crossCountryIndex + 1);
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
