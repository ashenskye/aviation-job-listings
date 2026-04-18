import 'package:flutter_test/flutter_test.dart';

import 'package:aviation_job_listings/models/aviation_location_catalogs.dart';

void main() {
  test('formatCityStateLocation stores city with state abbreviation', () {
    expect(
      formatCityStateLocation(city: 'Anchorage', stateOrProvince: 'Alaska'),
      'Anchorage, AK',
    );
  });

  test('parseCityStateLocation infers country from abbreviation', () {
    final parsed = parseCityStateLocation('Calgary, AB');

    expect(parsed.city, 'Calgary');
    expect(parsed.stateOrProvince, 'AB');
    expect(parsed.country, 'Canada');
  });

  test('parseCityStateLocation clears legacy placeholder values', () {
    final parsed = parseCityStateLocation('Location not specified');

    expect(parsed.city, isEmpty);
    expect(parsed.stateOrProvince, isEmpty);
    expect(parsed.country, 'USA');
  });

  test('stateProvinceOptionsForCountry scopes by selected country', () {
    expect(stateProvinceOptionsForCountry('USA'), contains('Alaska'));
    expect(stateProvinceOptionsForCountry('USA'), isNot(contains('Alberta')));
    expect(stateProvinceOptionsForCountry('Canada'), contains('Alberta'));
    expect(stateProvinceOptionsForCountry('Canada'), isNot(contains('Alaska')));
  });
}
