import 'aviation_certificate_utils.dart';

const Set<String> _instructorHourKeys = {
  'Total Instructor Hours',
  'Instrument (CFII)',
  'Multi-Engine (MEI)',
};

class JobListing {
  final String id;
  final String title;
  final String company;
  final String location;
  final String type;
  final String crewRole;
  final String? crewPosition;
  final List<String> faaRules;
  final String description;
  final List<String> faaCertificates;
  final List<String> typeRatingsRequired;
  final List<String> flightExperience;
  final Map<String, int> flightHours;
  final List<String> preferredFlightHours;
  final Map<String, int> instructorHours;
  final List<String> preferredInstructorHours;
  final List<String> specialtyExperience;
  final Map<String, int> specialtyHours;
  final List<String> preferredSpecialtyHours;
  final List<String> aircraftFlown;
  final String? salaryRange;
  final int? minimumHours;
  final List<String> benefits;
  final DateTime? deadlineDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? employerId;
  final int autoRejectThreshold; // 0 = disabled; >0 = auto-reject below this %
  final int reapplyWindowDays; // days a seeker must wait before re-applying

  const JobListing({
    required this.id,
    required this.title,
    required this.company,
    required this.location,
    required this.type,
    required this.crewRole,
    this.crewPosition,
    required this.faaRules,
    required this.description,
    required this.faaCertificates,
    this.typeRatingsRequired = const [],
    required this.flightExperience,
    this.flightHours = const {},
    this.preferredFlightHours = const [],
    this.instructorHours = const {},
    this.preferredInstructorHours = const [],
    this.specialtyExperience = const [],
    this.specialtyHours = const {},
    this.preferredSpecialtyHours = const [],
    required this.aircraftFlown,
    this.salaryRange,
    this.minimumHours,
    this.benefits = const [],
    this.deadlineDate,
    this.createdAt,
    this.updatedAt,
    this.employerId,
    this.autoRejectThreshold = 0,
    this.reapplyWindowDays = 30,
  });

  factory JobListing.fromJson(Map<String, dynamic> json) {
    final rawFlightHours = Map<String, int>.from(
      (json['flightHours'] as Map<String, dynamic>?) ?? {},
    );
    final rawPreferredFlightHours =
        (json['preferredFlightHours'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final parsedInstructorHours = Map<String, int>.from(
      (json['instructorHours'] as Map<String, dynamic>?) ?? {},
    );
    final parsedPreferredInstructorHours =
        (json['preferredInstructorHours'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final instructorHours = parsedInstructorHours.isNotEmpty
        ? parsedInstructorHours
        : {
            for (final entry in rawFlightHours.entries)
              if (_instructorHourKeys.contains(entry.key))
                entry.key: entry.value,
          };

    final preferredInstructorHours = parsedPreferredInstructorHours.isNotEmpty
        ? parsedPreferredInstructorHours
        : rawPreferredFlightHours.where(_instructorHourKeys.contains).toList();

    final flightHours = {
      for (final entry in rawFlightHours.entries)
        if (!_instructorHourKeys.contains(entry.key)) entry.key: entry.value,
    };

    final preferredFlightHours = rawPreferredFlightHours
        .where((name) => !_instructorHourKeys.contains(name))
        .toList();

    return JobListing(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? 'Untitled Job',
      company: json['company'] ?? 'Unknown',
      location: json['location'] ?? 'Remote',
      type: json['type'] ?? 'Unknown',
      crewRole: json['crewRole'] ?? 'Single Pilot',
      crewPosition: json['crewPosition']?.toString(),
      faaRules:
          (json['faaRules'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      description: json['description'] ?? '',
      faaCertificates:
          (json['faaCertificates'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      typeRatingsRequired:
          (json['typeRatingsRequired'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      flightExperience:
          ((json['flightExperience'] as List<dynamic>?) ??
                  (json['flyingStyles'] as List<dynamic>?))
              ?.map((e) => e.toString())
              .where(
                (exp) => normalizeCertificateName(exp) != 'instrument rating',
              )
              .toList() ??
          [],
      flightHours: flightHours,
      preferredFlightHours: preferredFlightHours,
      instructorHours: instructorHours,
      preferredInstructorHours: preferredInstructorHours,
      specialtyExperience:
          (json['specialtyExperience'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      specialtyHours: Map<String, int>.from(
        (json['specialtyHours'] as Map<String, dynamic>?) ?? {},
      ),
      preferredSpecialtyHours:
          (json['preferredSpecialtyHours'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      aircraftFlown:
          (json['aircraftFlown'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      salaryRange: json['salaryRange']?.toString(),
      minimumHours: json['minimumHours'] != null
          ? int.tryParse(json['minimumHours'].toString())
          : null,
      benefits:
          (json['benefits'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      deadlineDate: json['deadlineDate'] != null
          ? DateTime.tryParse(json['deadlineDate'].toString())
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
      employerId: json['employerId']?.toString(),
      autoRejectThreshold:
          (json['autoRejectThreshold'] as num?)?.toInt() ?? 0,
      reapplyWindowDays:
          (json['reapplyWindowDays'] as num?)?.toInt() ?? 30,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'company': company,
    'location': location,
    'type': type,
    'crewRole': crewRole,
    'crewPosition': crewPosition,
    'faaRules': faaRules,
    'description': description,
    'faaCertificates': faaCertificates,
    'typeRatingsRequired': typeRatingsRequired,
    'flyingStyles': flightExperience,
    'flightHours': flightHours,
    'preferredFlightHours': preferredFlightHours,
    'instructorHours': instructorHours,
    'preferredInstructorHours': preferredInstructorHours,
    'specialtyExperience': specialtyExperience,
    'specialtyHours': specialtyHours,
    'preferredSpecialtyHours': preferredSpecialtyHours,
    'aircraftFlown': aircraftFlown,
    'salaryRange': salaryRange,
    'minimumHours': minimumHours,
    'benefits': benefits,
    'deadlineDate': deadlineDate?.toIso8601String(),
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'employerId': employerId,
    'autoRejectThreshold': autoRejectThreshold,
    'reapplyWindowDays': reapplyWindowDays,
  };

  Map<String, int> get flightHoursByType {
    if (flightHours.isNotEmpty) {
      return flightHours;
    }

    return {for (final item in flightExperience) item: 0};
  }

  Map<String, int> get specialtyHoursByType {
    if (specialtyHours.isNotEmpty) {
      return specialtyHours;
    }

    return {for (final item in specialtyExperience) item: 0};
  }

  Map<String, int> get instructorHoursByType {
    if (instructorHours.isNotEmpty) {
      return instructorHours;
    }

    return {
      for (final item in flightExperience)
        if (_instructorHourKeys.contains(item)) item: 0,
    };
  }
}
