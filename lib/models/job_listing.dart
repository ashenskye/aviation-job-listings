import 'aviation_certificate_utils.dart';
import 'aviation_option_catalogs.dart';

String _normalizeRequiredRatingLabel(String rating) {
  final normalized = rating.trim().toLowerCase();
  return normalized == 'rotorcraft' ? 'Helicopter' : rating;
}

class JobListing {
  final String id;
  final String title;
  final String company;
  final String location;
  final String type;
  final String crewRole;
  final String? crewPosition;
  final List<String> faaRules;
  final String? part135SubType; // 'ifr' or 'vfr' when faaRules contains 'Part 135'
  final String description;
  final List<String> faaCertificates;
  final List<String> requiredRatings;
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
  final bool isExternal; // true when listing is sourced externally
  final String? externalApplyUrl; // optional external application URL
  final String? contactName; // optional listing contact name
  final String? contactEmail; // optional listing contact email
  final String? companyPhone; // optional company contact phone
  final String? companyUrl; // optional company website URL
  final bool isActive; // false = archived by employer
  final DateTime? archivedAt; // set when archived

  const JobListing({
    required this.id,
    required this.title,
    required this.company,
    required this.location,
    required this.type,
    required this.crewRole,
    this.crewPosition,
    required this.faaRules,
    this.part135SubType,
    required this.description,
    required this.faaCertificates,
    this.requiredRatings = const [],
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
    this.isExternal = false,
    this.externalApplyUrl,
    this.contactName,
    this.contactEmail,
    this.companyPhone,
    this.companyUrl,
    this.isActive = true,
    this.archivedAt,
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

    final parsedInstructorHours = <String, int>{
      for (final entry
          in ((json['instructorHours'] as Map<String, dynamic>?) ?? {})
              .entries)
        normalizeInstructorHourLabel(entry.key):
            int.tryParse(entry.value.toString()) ?? 0,
    };
    final parsedPreferredInstructorHours =
        (json['preferredInstructorHours'] as List<dynamic>?)
            ?.map((e) => normalizeInstructorHourLabel(e.toString()))
            .toList() ??
        [];

    final instructorHours = parsedInstructorHours.isNotEmpty
        ? parsedInstructorHours
        : {
            for (final entry in rawFlightHours.entries)
              if (instructorHourOptionSet.contains(
                normalizeInstructorHourLabel(entry.key),
              ))
                normalizeInstructorHourLabel(entry.key): entry.value,
          };

    final preferredInstructorHours = parsedPreferredInstructorHours.isNotEmpty
        ? parsedPreferredInstructorHours
        : rawPreferredFlightHours
              .map(normalizeInstructorHourLabel)
              .where(instructorHourOptionSet.contains)
              .toList();

    final flightHours = {
      for (final entry in rawFlightHours.entries)
        if (!instructorHourOptionSet.contains(
          normalizeInstructorHourLabel(entry.key),
        ))
          entry.key: entry.value,
    };

    final preferredFlightHours = rawPreferredFlightHours
        .where(
          (name) => !instructorHourOptionSet.contains(
            normalizeInstructorHourLabel(name),
          ),
        )
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
      part135SubType: json['part135SubType']?.toString(),
      description: json['description'] ?? '',
      faaCertificates:
          (json['faaCertificates'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      requiredRatings:
          (json['requiredRatings'] as List<dynamic>?)
              ?.map((e) => _normalizeRequiredRatingLabel(e.toString()))
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
      autoRejectThreshold: (json['autoRejectThreshold'] as num?)?.toInt() ?? 0,
      reapplyWindowDays: (json['reapplyWindowDays'] as num?)?.toInt() ?? 30,
      isExternal: (json['isExternal'] as bool?) ?? false,
      externalApplyUrl: json['externalApplyUrl']?.toString(),
      contactName: json['contactName']?.toString(),
      contactEmail: json['contactEmail']?.toString(),
      companyPhone: json['companyPhone']?.toString(),
      companyUrl: json['companyUrl']?.toString(),
      isActive: (json['isActive'] as bool?) ?? true,
      archivedAt: json['archivedAt'] != null
          ? DateTime.tryParse(json['archivedAt'].toString())
          : null,
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
    'part135SubType': part135SubType,
    'description': description,
    'faaCertificates': faaCertificates,
    'requiredRatings': requiredRatings,
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
    'isExternal': isExternal,
    'externalApplyUrl': externalApplyUrl,
    'contactName': contactName,
    'contactEmail': contactEmail,
    'companyPhone': companyPhone,
    'companyUrl': companyUrl,
    'isActive': isActive,
    'archivedAt': archivedAt?.toIso8601String(),
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
        if (instructorHourOptionSet.contains(item)) item: 0,
    };
  }

  bool get isExpired =>
      deadlineDate != null && deadlineDate!.isBefore(DateTime.now());

  /// True if the job should appear in public listings.
  bool get shouldShow => isActive && !isExpired;

  /// Days remaining until the deadline (negative if already passed).
  int? get daysUntilDeadline {
    if (deadlineDate == null) return null;
    final deadline = DateTime(
      deadlineDate!.year,
      deadlineDate!.month,
      deadlineDate!.day,
    );
    final today = DateTime.now();
    final nowDate = DateTime(today.year, today.month, today.day);
    return deadline.difference(nowDate).inDays;
  }

  JobListing copyWith({
    String? id,
    String? title,
    String? company,
    String? location,
    String? type,
    String? crewRole,
    Object? crewPosition = _sentinel,
    List<String>? faaRules,
    String? part135SubType,
    String? description,
    List<String>? faaCertificates,
    List<String>? requiredRatings,
    List<String>? typeRatingsRequired,
    List<String>? flightExperience,
    Map<String, int>? flightHours,
    List<String>? preferredFlightHours,
    Map<String, int>? instructorHours,
    List<String>? preferredInstructorHours,
    List<String>? specialtyExperience,
    Map<String, int>? specialtyHours,
    List<String>? preferredSpecialtyHours,
    List<String>? aircraftFlown,
    Object? salaryRange = _sentinel,
    Object? minimumHours = _sentinel,
    List<String>? benefits,
    Object? deadlineDate = _sentinel,
    Object? createdAt = _sentinel,
    Object? updatedAt = _sentinel,
    Object? employerId = _sentinel,
    int? autoRejectThreshold,
    int? reapplyWindowDays,
    bool? isExternal,
    Object? externalApplyUrl = _sentinel,
    Object? contactName = _sentinel,
    Object? contactEmail = _sentinel,
    Object? companyPhone = _sentinel,
    Object? companyUrl = _sentinel,
    bool? isActive,
    Object? archivedAt = _sentinel,
  }) {
    return JobListing(
      id: id ?? this.id,
      title: title ?? this.title,
      company: company ?? this.company,
      location: location ?? this.location,
      type: type ?? this.type,
      crewRole: crewRole ?? this.crewRole,
      crewPosition: crewPosition == _sentinel
          ? this.crewPosition
          : crewPosition as String?,
      faaRules: faaRules ?? this.faaRules,
      part135SubType: part135SubType ?? this.part135SubType,
      description: description ?? this.description,
      faaCertificates: faaCertificates ?? this.faaCertificates,
      requiredRatings: requiredRatings ?? this.requiredRatings,
      typeRatingsRequired: typeRatingsRequired ?? this.typeRatingsRequired,
      flightExperience: flightExperience ?? this.flightExperience,
      flightHours: flightHours ?? this.flightHours,
      preferredFlightHours: preferredFlightHours ?? this.preferredFlightHours,
      instructorHours: instructorHours ?? this.instructorHours,
      preferredInstructorHours:
          preferredInstructorHours ?? this.preferredInstructorHours,
      specialtyExperience: specialtyExperience ?? this.specialtyExperience,
      specialtyHours: specialtyHours ?? this.specialtyHours,
      preferredSpecialtyHours:
          preferredSpecialtyHours ?? this.preferredSpecialtyHours,
      aircraftFlown: aircraftFlown ?? this.aircraftFlown,
      salaryRange: salaryRange == _sentinel
          ? this.salaryRange
          : salaryRange as String?,
      minimumHours: minimumHours == _sentinel
          ? this.minimumHours
          : minimumHours as int?,
      benefits: benefits ?? this.benefits,
      deadlineDate: deadlineDate == _sentinel
          ? this.deadlineDate
          : deadlineDate as DateTime?,
      createdAt: createdAt == _sentinel
          ? this.createdAt
          : createdAt as DateTime?,
      updatedAt: updatedAt == _sentinel
          ? this.updatedAt
          : updatedAt as DateTime?,
      employerId: employerId == _sentinel
          ? this.employerId
          : employerId as String?,
      autoRejectThreshold: autoRejectThreshold ?? this.autoRejectThreshold,
      reapplyWindowDays: reapplyWindowDays ?? this.reapplyWindowDays,
      isExternal: isExternal ?? this.isExternal,
      externalApplyUrl: externalApplyUrl == _sentinel
          ? this.externalApplyUrl
          : externalApplyUrl as String?,
      contactName: contactName == _sentinel
          ? this.contactName
          : contactName as String?,
      contactEmail: contactEmail == _sentinel
          ? this.contactEmail
          : contactEmail as String?,
      companyPhone: companyPhone == _sentinel
          ? this.companyPhone
          : companyPhone as String?,
      companyUrl: companyUrl == _sentinel
          ? this.companyUrl
          : companyUrl as String?,
      isActive: isActive ?? this.isActive,
      archivedAt: archivedAt == _sentinel
          ? this.archivedAt
          : archivedAt as DateTime?,
    );
  }
}

// Private sentinel object used by JobListing.copyWith to distinguish
// "not provided" from explicit null for nullable fields.
const Object _sentinel = Object();
