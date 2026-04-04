class JobSeekerProfile {
  final String fullName;
  final String email;
  final String phone;
  final String city;
  final String stateOrProvince;
  final String country;
  final List<String> faaCertificates;
  final List<String> typeRatings;
  final Map<String, int> flightHours;
  final List<String> flightHoursTypes;
  final List<String> specialtyFlightHours;
  final Map<String, int> specialtyFlightHoursMap;
  final List<String> aircraftFlown;
  final int totalFlightHours;

  const JobSeekerProfile({
    this.fullName = '',
    this.email = '',
    this.phone = '',
    this.city = '',
    this.stateOrProvince = '',
    this.country = '',
    this.faaCertificates = const [],
    this.typeRatings = const [],
    this.flightHours = const {},
    this.flightHoursTypes = const [],
    this.specialtyFlightHours = const [],
    this.specialtyFlightHoursMap = const {},
    this.aircraftFlown = const [],
    this.totalFlightHours = 0,
  });

  factory JobSeekerProfile.fromJson(Map<String, dynamic> json) {
    return JobSeekerProfile(
      fullName: json['fullName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      stateOrProvince: json['stateOrProvince']?.toString() ?? '',
      country: json['country']?.toString() ?? '',
      faaCertificates:
          (json['faaCertificates'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      typeRatings:
          (json['typeRatings'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      flightHours: Map<String, int>.from(
        (json['flightHours'] as Map<String, dynamic>?) ??
            (json['flightExperienceHours'] as Map<String, dynamic>?) ??
            (json['certificateHours'] as Map<String, dynamic>?) ??
            {},
      ),
      flightHoursTypes:
          ((json['flightHoursTypes'] as List<dynamic>?) ??
                  (json['flightExperience'] as List<dynamic>?))
              ?.map((e) => e.toString())
              .toList() ??
          [],
      specialtyFlightHours:
          ((json['specialtyFlightHours'] as List<dynamic>?) ??
                  (json['specialtyExperience'] as List<dynamic>?))
              ?.map((e) => e.toString())
              .toList() ??
          [],
      specialtyFlightHoursMap: Map<String, int>.from(
        (json['specialtyFlightHoursMap'] as Map<String, dynamic>?) ??
            (json['specialtyHours'] as Map<String, dynamic>?) ??
            {},
      ),
      aircraftFlown:
          (json['aircraftFlown'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      totalFlightHours: json['totalFlightHours'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'fullName': fullName,
    'email': email,
    'phone': phone,
    'city': city,
    'stateOrProvince': stateOrProvince,
    'country': country,
    'faaCertificates': faaCertificates,
    'typeRatings': typeRatings,
    'flightHours': flightHours,
    'flightHoursTypes': flightHoursTypes,
    'specialtyFlightHours': specialtyFlightHours,
    'specialtyFlightHoursMap': specialtyFlightHoursMap,
    'aircraftFlown': aircraftFlown,
    'totalFlightHours': totalFlightHours,
  };

  JobSeekerProfile copyWith({
    String? fullName,
    String? email,
    String? phone,
    String? city,
    String? stateOrProvince,
    String? country,
    List<String>? faaCertificates,
    List<String>? typeRatings,
    Map<String, int>? flightHours,
    List<String>? flightHoursTypes,
    List<String>? specialtyFlightHours,
    Map<String, int>? specialtyFlightHoursMap,
    List<String>? aircraftFlown,
    int? totalFlightHours,
  }) {
    return JobSeekerProfile(
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      city: city ?? this.city,
      stateOrProvince: stateOrProvince ?? this.stateOrProvince,
      country: country ?? this.country,
      faaCertificates: faaCertificates ?? this.faaCertificates,
      typeRatings: typeRatings ?? this.typeRatings,
      flightHours: flightHours ?? this.flightHours,
      flightHoursTypes: flightHoursTypes ?? this.flightHoursTypes,
      specialtyFlightHours:
          specialtyFlightHours ?? this.specialtyFlightHours,
      specialtyFlightHoursMap:
          specialtyFlightHoursMap ?? this.specialtyFlightHoursMap,
      aircraftFlown: aircraftFlown ?? this.aircraftFlown,
      totalFlightHours: totalFlightHours ?? this.totalFlightHours,
    );
  }
}
