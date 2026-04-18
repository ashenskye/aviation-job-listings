class ParsedCityStateLocation {
  const ParsedCityStateLocation({
    required this.city,
    required this.stateOrProvince,
    required this.country,
  });

  final String city;
  final String stateOrProvince;
  final String country;
}

const List<String> usStateOptions = [
  'Alabama',
  'Alaska',
  'Arizona',
  'Arkansas',
  'California',
  'Colorado',
  'Connecticut',
  'Delaware',
  'District of Columbia',
  'Florida',
  'Georgia',
  'Hawaii',
  'Idaho',
  'Illinois',
  'Indiana',
  'Iowa',
  'Kansas',
  'Kentucky',
  'Louisiana',
  'Maine',
  'Maryland',
  'Massachusetts',
  'Michigan',
  'Minnesota',
  'Mississippi',
  'Missouri',
  'Montana',
  'Nebraska',
  'Nevada',
  'New Hampshire',
  'New Jersey',
  'New Mexico',
  'New York',
  'North Carolina',
  'North Dakota',
  'Ohio',
  'Oklahoma',
  'Oregon',
  'Pennsylvania',
  'Rhode Island',
  'South Carolina',
  'South Dakota',
  'Tennessee',
  'Texas',
  'Utah',
  'Vermont',
  'Virginia',
  'Washington',
  'West Virginia',
  'Wisconsin',
  'Wyoming',
];

const List<String> canadaProvinceOptions = [
  'Alberta',
  'British Columbia',
  'Manitoba',
  'New Brunswick',
  'Newfoundland and Labrador',
  'Northwest Territories',
  'Nova Scotia',
  'Nunavut',
  'Ontario',
  'Prince Edward Island',
  'Quebec',
  'Saskatchewan',
  'Yukon',
];

const List<String> countryOptions = ['USA', 'Canada'];

const List<String> stateProvinceOptions = [
  ...usStateOptions,
  ...canadaProvinceOptions,
];

const Map<String, String> stateProvinceAbbreviations = {
  'Alabama': 'AL',
  'Alaska': 'AK',
  'Arizona': 'AZ',
  'Arkansas': 'AR',
  'California': 'CA',
  'Colorado': 'CO',
  'Connecticut': 'CT',
  'Delaware': 'DE',
  'District of Columbia': 'DC',
  'Florida': 'FL',
  'Georgia': 'GA',
  'Hawaii': 'HI',
  'Idaho': 'ID',
  'Illinois': 'IL',
  'Indiana': 'IN',
  'Iowa': 'IA',
  'Kansas': 'KS',
  'Kentucky': 'KY',
  'Louisiana': 'LA',
  'Maine': 'ME',
  'Maryland': 'MD',
  'Massachusetts': 'MA',
  'Michigan': 'MI',
  'Minnesota': 'MN',
  'Mississippi': 'MS',
  'Missouri': 'MO',
  'Montana': 'MT',
  'Nebraska': 'NE',
  'Nevada': 'NV',
  'New Hampshire': 'NH',
  'New Jersey': 'NJ',
  'New Mexico': 'NM',
  'New York': 'NY',
  'North Carolina': 'NC',
  'North Dakota': 'ND',
  'Ohio': 'OH',
  'Oklahoma': 'OK',
  'Oregon': 'OR',
  'Pennsylvania': 'PA',
  'Rhode Island': 'RI',
  'South Carolina': 'SC',
  'South Dakota': 'SD',
  'Tennessee': 'TN',
  'Texas': 'TX',
  'Utah': 'UT',
  'Vermont': 'VT',
  'Virginia': 'VA',
  'Washington': 'WA',
  'West Virginia': 'WV',
  'Wisconsin': 'WI',
  'Wyoming': 'WY',
  'Alberta': 'AB',
  'British Columbia': 'BC',
  'Manitoba': 'MB',
  'New Brunswick': 'NB',
  'Newfoundland and Labrador': 'NL',
  'Northwest Territories': 'NT',
  'Nova Scotia': 'NS',
  'Nunavut': 'NU',
  'Ontario': 'ON',
  'Prince Edward Island': 'PE',
  'Quebec': 'QC',
  'Saskatchewan': 'SK',
  'Yukon': 'YT',
};

final Map<String, String> _stateProvinceValueToName = {
  for (final option in stateProvinceOptions) option.toLowerCase(): option,
  for (final entry in stateProvinceAbbreviations.entries)
    entry.value.toLowerCase(): entry.key,
};

String stateProvinceLabel(String name) {
  final abbreviation = stateProvinceAbbreviations[name];
  if (abbreviation == null) {
    return name;
  }
  return '$name ($abbreviation)';
}

String? normalizeCountryValue(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }
  if (normalized == 'usa' ||
      normalized == 'us' ||
      normalized == 'united states' ||
      normalized == 'united states of america') {
    return 'USA';
  }
  if (normalized == 'canada' || normalized == 'ca') {
    return 'Canada';
  }
  return null;
}

List<String> stateProvinceOptionsForCountry(String rawCountry) {
  switch (normalizeCountryValue(rawCountry)) {
    case 'USA':
      return usStateOptions;
    case 'Canada':
      return canadaProvinceOptions;
    default:
      return stateProvinceOptions;
  }
}

String? inferCountryFromStateProvince(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }

  final canonicalName = _stateProvinceValueToName[normalized];
  if (canonicalName == null) {
    return null;
  }
  if (canadaProvinceOptions.contains(canonicalName)) {
    return 'Canada';
  }
  if (usStateOptions.contains(canonicalName)) {
    return 'USA';
  }
  return null;
}

bool isValidStateProvinceForCountry(String rawCountry, String value) {
  final normalizedValue = value.trim().toLowerCase();
  if (normalizedValue.isEmpty) {
    return false;
  }

  final scopedOptions = stateProvinceOptionsForCountry(rawCountry);
  return scopedOptions.any((option) {
    final abbreviation =
        stateProvinceAbbreviations[option]?.toLowerCase() ?? '';
    return option.toLowerCase() == normalizedValue ||
        abbreviation == normalizedValue;
  });
}

String formatCityStateLocation({
  required String city,
  required String stateOrProvince,
}) {
  final trimmedCity = city.trim().replaceAll(RegExp(r'\s+'), ' ');
  final trimmedState = stateOrProvince.trim();
  final canonicalName = _stateProvinceValueToName[trimmedState.toLowerCase()];
  final displayState = canonicalName == null
      ? trimmedState
      : (stateProvinceAbbreviations[canonicalName] ?? canonicalName);

  if (trimmedCity.isEmpty) {
    return displayState;
  }
  if (displayState.isEmpty) {
    return trimmedCity;
  }
  return '$trimmedCity, $displayState';
}

ParsedCityStateLocation parseCityStateLocation(String location) {
  final trimmed = location.trim();
  if (trimmed.isEmpty || trimmed.toLowerCase() == 'location not specified') {
    return const ParsedCityStateLocation(
      city: '',
      stateOrProvince: '',
      country: 'USA',
    );
  }

  final parts = trimmed
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);

  if (parts.isEmpty) {
    return const ParsedCityStateLocation(
      city: '',
      stateOrProvince: '',
      country: 'USA',
    );
  }

  final city = parts.first;
  final state = parts.length > 1 ? parts[1] : '';
  final explicitCountry = parts.length > 2
      ? normalizeCountryValue(parts[2])
      : null;
  final inferredCountry = inferCountryFromStateProvince(state);

  return ParsedCityStateLocation(
    city: city,
    stateOrProvince: state,
    country: explicitCountry ?? inferredCountry ?? 'USA',
  );
}
