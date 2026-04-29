import 'aviation_location_catalogs.dart';

class JobSeekerProfile {
  final String firstName;
  final String lastName;
  final String fullName;
  final String email;
  final String phone;
  final String city;
  final String stateOrProvince;
  final String country;
  final String airframeScope;
  final List<String> faaCertificates;
  final List<String> typeRatings;
  final Map<String, int> flightHours;
  final List<String> flightHoursTypes;
  final List<String> specialtyFlightHours;
  final Map<String, int> specialtyFlightHoursMap;
  final List<String> aircraftFlown;
  final int totalFlightHours;
  final bool notifyOnApplicationStatusChange;
  final String resumeUrl;
  final String resumeFileName;

  // Job alert preferences
  final bool newJobAlertEnabled;
  final bool newJobAlertStateOnly;
  final bool newJobAlertAirframeMatch;
  final int newJobAlertMinimumMatchPercent;
  final bool newJobAlertCertificateMatch;

  const JobSeekerProfile({
    this.firstName = '',
    this.lastName = '',
    this.fullName = '',
    this.email = '',
    this.phone = '',
    this.city = '',
    this.stateOrProvince = '',
    this.country = '',
    this.airframeScope = 'Fixed Wing',
    this.faaCertificates = const [],
    this.typeRatings = const [],
    this.flightHours = const {},
    this.flightHoursTypes = const [],
    this.specialtyFlightHours = const [],
    this.specialtyFlightHoursMap = const {},
    this.aircraftFlown = const [],
    this.totalFlightHours = 0,
    this.notifyOnApplicationStatusChange = true,
    this.resumeUrl = '',
    this.resumeFileName = '',
    this.newJobAlertEnabled = false,
    this.newJobAlertStateOnly = false,
    this.newJobAlertAirframeMatch = true,
    this.newJobAlertMinimumMatchPercent = 100,
    this.newJobAlertCertificateMatch = false,
  });

  static List<String> _splitFullName(String fullName) {
    final normalized = fullName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      return const ['', ''];
    }

    final parts = normalized.split(' ');
    if (parts.length == 1) {
      return [parts.first, ''];
    }

    return [parts.first, parts.sublist(1).join(' ')];
  }

  static String combineName(String firstName, String lastName) {
    final parts = [firstName.trim(), lastName.trim()]
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return parts.join(' ');
  }

  factory JobSeekerProfile.fromJson(Map<String, dynamic> json) {
    final firstName = json['firstName']?.toString().trim() ?? '';
    final lastName = json['lastName']?.toString().trim() ?? '';
    final legacyFullName = json['fullName']?.toString() ?? '';
    final splitLegacyName = _splitFullName(legacyFullName);
    final resolvedFirstName = firstName.isNotEmpty
        ? firstName
        : splitLegacyName[0];
    final resolvedLastName = lastName.isNotEmpty ? lastName : splitLegacyName[1];
    final resolvedFullName = combineName(resolvedFirstName, resolvedLastName);

    return JobSeekerProfile(
      firstName: resolvedFirstName,
      lastName: resolvedLastName,
      fullName: resolvedFullName.isNotEmpty
          ? resolvedFullName
          : legacyFullName.trim(),
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      stateOrProvince: normalizeStateProvinceValue(json['stateOrProvince']?.toString() ?? '') ?? json['stateOrProvince']?.toString() ?? '',
      country: normalizeCountryValue(json['country']?.toString() ?? '') ?? json['country']?.toString() ?? '',
      airframeScope: (() {
        final normalized = json['airframeScope']?.toString().trim().toLowerCase();
        switch (normalized) {
          case 'fixed wing':
            return 'Fixed Wing';
          case 'helicopter':
          case 'rotorcraft':
            return 'Helicopter';
          case 'both':
            return 'Both';
          default:
            return 'Fixed Wing';
        }
      })(),
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
      notifyOnApplicationStatusChange:
          (json['notifyOnApplicationStatusChange'] as bool?) ??
          (json['notify_on_application_status_change'] as bool?) ??
          true,
      newJobAlertEnabled:
          (json['newJobAlertEnabled'] as bool?) ??
          (json['new_job_alert_enabled'] as bool?) ??
          false,
      newJobAlertStateOnly:
          (json['newJobAlertStateOnly'] as bool?) ??
          (json['new_job_alert_state_only'] as bool?) ??
          false,
      newJobAlertAirframeMatch:
          (json['newJobAlertAirframeMatch'] as bool?) ??
          (json['new_job_alert_airframe_match'] as bool?) ??
          true,
        newJobAlertMinimumMatchPercent:
          (json['newJobAlertMinimumMatchPercent'] as num?)?.toInt() ??
          (json['new_job_alert_minimum_match_percent'] as num?)?.toInt() ??
          100,
      newJobAlertCertificateMatch:
          (json['newJobAlertCertificateMatch'] as bool?) ??
          (json['new_job_alert_certificate_match'] as bool?) ??
          false,
      resumeUrl: json['resumeUrl']?.toString() ?? json['resume_url']?.toString() ?? '',
      resumeFileName: json['resumeFileName']?.toString() ?? json['resume_file_name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'firstName': firstName,
    'lastName': lastName,
    'fullName': () {
      final combined = combineName(firstName, lastName);
      return combined.isNotEmpty ? combined : fullName;
    }(),
    'email': email,
    'phone': phone,
    'city': city,
    'stateOrProvince': stateOrProvince,
    'country': country,
    'airframeScope': airframeScope,
    'faaCertificates': faaCertificates,
    'typeRatings': typeRatings,
    'flightHours': flightHours,
    'flightHoursTypes': flightHoursTypes,
    'specialtyFlightHours': specialtyFlightHours,
    'specialtyFlightHoursMap': specialtyFlightHoursMap,
    'aircraftFlown': aircraftFlown,
    'totalFlightHours': totalFlightHours,
    'notifyOnApplicationStatusChange': notifyOnApplicationStatusChange,
    'newJobAlertEnabled': newJobAlertEnabled,
    'newJobAlertStateOnly': newJobAlertStateOnly,
    'newJobAlertAirframeMatch': newJobAlertAirframeMatch,
    'newJobAlertMinimumMatchPercent': newJobAlertMinimumMatchPercent,
    'newJobAlertCertificateMatch': newJobAlertCertificateMatch,
    'resumeUrl': resumeUrl,
    'resumeFileName': resumeFileName,
  };

  JobSeekerProfile copyWith({
    String? firstName,
    String? lastName,
    String? fullName,
    String? email,
    String? phone,
    String? city,
    String? stateOrProvince,
    String? country,
    String? airframeScope,
    List<String>? faaCertificates,
    List<String>? typeRatings,
    Map<String, int>? flightHours,
    List<String>? flightHoursTypes,
    List<String>? specialtyFlightHours,
    Map<String, int>? specialtyFlightHoursMap,
    List<String>? aircraftFlown,
    int? totalFlightHours,
    bool? notifyOnApplicationStatusChange,
    bool? newJobAlertEnabled,
    bool? newJobAlertStateOnly,
    bool? newJobAlertAirframeMatch,
    int? newJobAlertMinimumMatchPercent,
    bool? newJobAlertCertificateMatch,
    String? resumeUrl,
    String? resumeFileName,
  }) {
    final splitFullName = fullName == null ? null : _splitFullName(fullName);
    final nextFirstName = firstName ?? splitFullName?[0] ?? this.firstName;
    final nextLastName = lastName ?? splitFullName?[1] ?? this.lastName;
    final combinedName = combineName(nextFirstName, nextLastName);

    return JobSeekerProfile(
      firstName: nextFirstName,
      lastName: nextLastName,
      fullName: combinedName.isNotEmpty
          ? combinedName
          : (fullName ?? this.fullName).trim(),
      email: email ?? this.email,
      phone: phone ?? this.phone,
      city: city ?? this.city,
      stateOrProvince: stateOrProvince ?? this.stateOrProvince,
      country: country ?? this.country,
      airframeScope: airframeScope ?? this.airframeScope,
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
      notifyOnApplicationStatusChange:
          notifyOnApplicationStatusChange ??
          this.notifyOnApplicationStatusChange,
      newJobAlertEnabled: newJobAlertEnabled ?? this.newJobAlertEnabled,
      newJobAlertStateOnly: newJobAlertStateOnly ?? this.newJobAlertStateOnly,
      newJobAlertAirframeMatch:
          newJobAlertAirframeMatch ?? this.newJobAlertAirframeMatch,
      newJobAlertMinimumMatchPercent:
          (newJobAlertMinimumMatchPercent ?? this.newJobAlertMinimumMatchPercent)
              .clamp(0, 100),
      newJobAlertCertificateMatch:
          newJobAlertCertificateMatch ?? this.newJobAlertCertificateMatch,
      resumeUrl: resumeUrl ?? this.resumeUrl,
      resumeFileName: resumeFileName ?? this.resumeFileName,
    );
  }
}
