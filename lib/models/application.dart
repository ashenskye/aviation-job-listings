class Application {
  final String id;
  final String jobSeekerId;
  final String jobId;
  final String employerId;
  final String applicantName;
  final String applicantEmail;
  final String applicantPhone;
  final String applicantCity;
  final String applicantStateOrProvince;
  final String applicantCountry;
  final int applicantTotalFlightHours;
  final List<String> applicantFaaCertificates;
  final List<String> applicantTypeRatings;
  final List<String> applicantAircraftFlown;
  final Map<String, int> applicantFlightHours;
  final List<String> applicantFlightHoursTypes;
  final List<String> applicantSpecialtyFlightHours;
  final Map<String, int> applicantSpecialtyFlightHoursMap;
  final String status; // 'applied', 'reviewed', 'rejected', 'interested'
  final int matchPercentage;
  final String coverLetter;
  final DateTime appliedAt;
  final DateTime updatedAt;
  final bool isArchived;

  static const String statusApplied = 'applied';
  static const String statusReviewed = 'reviewed';
  static const String statusRejected = 'rejected';
  static const String statusInterested = 'interested';

  const Application({
    required this.id,
    required this.jobSeekerId,
    required this.jobId,
    required this.employerId,
    String? applicantName,
    String? applicantEmail,
    String? applicantPhone,
    String? applicantCity,
    String? applicantStateOrProvince,
    String? applicantCountry,
    this.applicantTotalFlightHours = 0,
    List<String>? applicantFaaCertificates,
    List<String>? applicantTypeRatings,
    List<String>? applicantAircraftFlown,
    Map<String, int>? applicantFlightHours,
    List<String>? applicantFlightHoursTypes,
    List<String>? applicantSpecialtyFlightHours,
    Map<String, int>? applicantSpecialtyFlightHoursMap,
    required this.status,
    required this.matchPercentage,
    required this.coverLetter,
    required this.appliedAt,
    required this.updatedAt,
    this.isArchived = false,
  }) : applicantName = applicantName ?? '',
       applicantEmail = applicantEmail ?? '',
       applicantPhone = applicantPhone ?? '',
       applicantCity = applicantCity ?? '',
       applicantStateOrProvince = applicantStateOrProvince ?? '',
       applicantCountry = applicantCountry ?? '',
       applicantFaaCertificates = applicantFaaCertificates ?? const [],
       applicantTypeRatings = applicantTypeRatings ?? const [],
         applicantAircraftFlown = applicantAircraftFlown ?? const [],
         applicantFlightHours = applicantFlightHours ?? const {},
         applicantFlightHoursTypes = applicantFlightHoursTypes ?? const [],
         applicantSpecialtyFlightHours = applicantSpecialtyFlightHours ?? const [],
         applicantSpecialtyFlightHoursMap =
           applicantSpecialtyFlightHoursMap ??
           const {};

  bool get isPerfectMatch => matchPercentage >= 90;
  bool get isGoodMatch => matchPercentage >= 70 && matchPercentage < 90;
  bool get isStretchMatch => matchPercentage < 70;

  String get jobListingId => jobId;

  static String normalizeStatus(String value) {
    switch (value.trim().toLowerCase()) {
      case 'viewed':
        return statusReviewed;
      case statusReviewed:
      case statusRejected:
      case statusInterested:
        return value.trim().toLowerCase();
      case statusApplied:
      default:
        return statusApplied;
    }
  }

  factory Application.fromJson(Map<String, dynamic> json) {
    return Application(
      id: json['id']?.toString() ?? '',
      jobSeekerId:
          json['job_seeker_id']?.toString() ??
          json['jobSeekerId']?.toString() ??
          '',
      jobId:
          json['job_listing_id']?.toString() ??
          json['jobId']?.toString() ??
          '',
      employerId:
          json['employer_id']?.toString() ??
          json['employerId']?.toString() ??
          '',
      applicantName:
          json['applicant_name']?.toString() ??
          json['applicantName']?.toString() ??
          '',
      applicantEmail:
          json['applicant_email']?.toString() ??
          json['applicantEmail']?.toString() ??
          '',
      applicantPhone:
          json['applicant_phone']?.toString() ??
          json['applicantPhone']?.toString() ??
          '',
      applicantCity:
          json['applicant_city']?.toString() ??
          json['applicantCity']?.toString() ??
          '',
      applicantStateOrProvince:
          json['applicant_state_or_province']?.toString() ??
          json['applicantStateOrProvince']?.toString() ??
          '',
      applicantCountry:
          json['applicant_country']?.toString() ??
          json['applicantCountry']?.toString() ??
          '',
      applicantTotalFlightHours:
          (json['applicant_total_flight_hours'] as num?)?.toInt() ??
          (json['applicantTotalFlightHours'] as num?)?.toInt() ??
          0,
      applicantFaaCertificates:
          ((json['applicant_faa_certificates'] as List<dynamic>?) ??
                  (json['applicantFaaCertificates'] as List<dynamic>?))
              ?.map((item) => item.toString())
              .toList() ??
          const [],
      applicantTypeRatings:
          ((json['applicant_type_ratings'] as List<dynamic>?) ??
                  (json['applicantTypeRatings'] as List<dynamic>?))
              ?.map((item) => item.toString())
              .toList() ??
          const [],
      applicantAircraftFlown:
          ((json['applicant_aircraft_flown'] as List<dynamic>?) ??
                  (json['applicantAircraftFlown'] as List<dynamic>?))
              ?.map((item) => item.toString())
              .toList() ??
          const [],
        applicantFlightHours: Map<String, int>.from(
        (json['applicant_flight_hours'] as Map<String, dynamic>?) ??
          (json['applicantFlightHours'] as Map<String, dynamic>?) ??
          const {},
        ),
        applicantFlightHoursTypes:
          ((json['applicant_flight_hours_types'] as List<dynamic>?) ??
              (json['applicantFlightHoursTypes'] as List<dynamic>?))
            ?.map((item) => item.toString())
            .toList() ??
          const [],
        applicantSpecialtyFlightHours:
          ((json['applicant_specialty_flight_hours'] as List<dynamic>?) ??
              (json['applicantSpecialtyFlightHours'] as List<dynamic>?))
            ?.map((item) => item.toString())
            .toList() ??
          const [],
        applicantSpecialtyFlightHoursMap: Map<String, int>.from(
        (json['applicant_specialty_flight_hours_map'] as Map<String, dynamic>?) ??
          (json['applicantSpecialtyFlightHoursMap'] as Map<String, dynamic>?) ??
          const {},
        ),
      status: normalizeStatus(json['status']?.toString() ?? statusApplied),
      matchPercentage: (json['matchPercentage'] as num?)?.toInt() ?? 0,
      coverLetter:
          json['cover_letter']?.toString() ??
          json['coverLetter']?.toString() ??
          '',
      appliedAt: json['applied_at'] != null
          ? DateTime.tryParse(json['applied_at'].toString()) ?? DateTime.now()
          : json['appliedAt'] != null
          ? DateTime.tryParse(json['appliedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isArchived:
          (json['is_archived'] as bool?) ??
          (json['isArchived'] as bool?) ??
          false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'job_seeker_id': jobSeekerId,
    'job_listing_id': jobId,
    'employer_id': employerId,
    'applicant_name': applicantName,
    'applicant_email': applicantEmail,
    'applicant_phone': applicantPhone,
    'applicant_city': applicantCity,
    'applicant_state_or_province': applicantStateOrProvince,
    'applicant_country': applicantCountry,
    'applicant_total_flight_hours': applicantTotalFlightHours,
    'applicant_faa_certificates': applicantFaaCertificates,
    'applicant_type_ratings': applicantTypeRatings,
    'applicant_aircraft_flown': applicantAircraftFlown,
    'applicant_flight_hours': applicantFlightHours,
    'applicant_flight_hours_types': applicantFlightHoursTypes,
    'applicant_specialty_flight_hours': applicantSpecialtyFlightHours,
    'applicant_specialty_flight_hours_map': applicantSpecialtyFlightHoursMap,
    'status': normalizeStatus(status),
    'matchPercentage': matchPercentage,
    'cover_letter': coverLetter,
    'applied_at': appliedAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'is_archived': isArchived,
  };

  Application copyWith({
    String? status,
    DateTime? updatedAt,
    String? applicantName,
    String? applicantEmail,
    String? applicantPhone,
    String? applicantCity,
    String? applicantStateOrProvince,
    String? applicantCountry,
    int? applicantTotalFlightHours,
    List<String>? applicantFaaCertificates,
    List<String>? applicantTypeRatings,
    List<String>? applicantAircraftFlown,
    Map<String, int>? applicantFlightHours,
    List<String>? applicantFlightHoursTypes,
    List<String>? applicantSpecialtyFlightHours,
    Map<String, int>? applicantSpecialtyFlightHoursMap,
    bool? isArchived,
  }) {
    return Application(
      id: id,
      jobSeekerId: jobSeekerId,
      jobId: jobId,
      employerId: employerId,
      applicantName: applicantName ?? this.applicantName,
      applicantEmail: applicantEmail ?? this.applicantEmail,
      applicantPhone: applicantPhone ?? this.applicantPhone,
      applicantCity: applicantCity ?? this.applicantCity,
      applicantStateOrProvince:
          applicantStateOrProvince ?? this.applicantStateOrProvince,
      applicantCountry: applicantCountry ?? this.applicantCountry,
      applicantTotalFlightHours:
          applicantTotalFlightHours ?? this.applicantTotalFlightHours,
      applicantFaaCertificates:
          applicantFaaCertificates ?? this.applicantFaaCertificates,
      applicantTypeRatings: applicantTypeRatings ?? this.applicantTypeRatings,
      applicantAircraftFlown:
          applicantAircraftFlown ?? this.applicantAircraftFlown,
        applicantFlightHours: applicantFlightHours ?? this.applicantFlightHours,
        applicantFlightHoursTypes:
          applicantFlightHoursTypes ?? this.applicantFlightHoursTypes,
        applicantSpecialtyFlightHours:
          applicantSpecialtyFlightHours ?? this.applicantSpecialtyFlightHours,
        applicantSpecialtyFlightHoursMap:
          applicantSpecialtyFlightHoursMap ??
          this.applicantSpecialtyFlightHoursMap,
      status: normalizeStatus(status ?? this.status),
      matchPercentage: matchPercentage,
      coverLetter: coverLetter,
      appliedAt: appliedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isArchived: isArchived ?? this.isArchived,
    );
  }
}
