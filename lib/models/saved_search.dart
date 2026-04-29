class SavedSearch {
  final String id;
  final String name;
  final DateTime createdAt;

  // Encoded filter strings (pipe-delimited)
  final String typeFilter;
  final String locationFilter;
  final String positionFilter;
  final String faaRuleFilter;
  final String airframeScopeFilter;
  final String specialtyFilter;
  final String certificateFilter;
  final String ratingFilter;
  final String instructorHoursFilter;
  final String flightHoursFilter;
  final String specialtyHoursFilter;
  final String statusFilter;
  final String sort;
  final int minimumMatchPercent;

  // Optional: pin frequently used searches
  final bool isFavorite;

  const SavedSearch({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.typeFilter,
    required this.locationFilter,
    required this.positionFilter,
    required this.faaRuleFilter,
    required this.airframeScopeFilter,
    required this.specialtyFilter,
    required this.certificateFilter,
    required this.ratingFilter,
    required this.instructorHoursFilter,
    required this.flightHoursFilter,
    required this.specialtyHoursFilter,
    required this.statusFilter,
    required this.sort,
    required this.minimumMatchPercent,
    this.isFavorite = false,
  });

  factory SavedSearch.fromJson(Map<String, dynamic> json) {
    return SavedSearch(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled Search',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'].toString())
          : DateTime.now(),
      typeFilter: json['type_filter']?.toString() ?? 'all',
      locationFilter: json['location_filter']?.toString() ?? 'all',
      positionFilter: json['position_filter']?.toString() ?? 'all',
      faaRuleFilter: json['faa_rule_filter']?.toString() ?? 'all',
      airframeScopeFilter: json['airframe_scope_filter']?.toString() ?? 'all',
      specialtyFilter: json['specialty_filter']?.toString() ?? 'all',
      certificateFilter: json['certificate_filter']?.toString() ?? 'all',
      ratingFilter: json['rating_filter']?.toString() ?? 'all',
      instructorHoursFilter: json['instructor_hours_filter']?.toString() ?? 'all',
      flightHoursFilter: json['flight_hours_filter']?.toString() ?? 'all',
      specialtyHoursFilter: json['specialty_hours_filter']?.toString() ?? 'all',
      statusFilter: json['status_filter']?.toString() ?? 'active',
      sort: json['sort']?.toString() ?? 'best_match',
      minimumMatchPercent: json['minimum_match_percent'] ?? 0,
      isFavorite: json['is_favorite'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'created_at': createdAt.toIso8601String(),
    'type_filter': typeFilter,
    'location_filter': locationFilter,
    'position_filter': positionFilter,
    'faa_rule_filter': faaRuleFilter,
    'airframe_scope_filter': airframeScopeFilter,
    'specialty_filter': specialtyFilter,
    'certificate_filter': certificateFilter,
    'rating_filter': ratingFilter,
    'instructor_hours_filter': instructorHoursFilter,
    'flight_hours_filter': flightHoursFilter,
    'specialty_hours_filter': specialtyHoursFilter,
    'status_filter': statusFilter,
    'sort': sort,
    'minimum_match_percent': minimumMatchPercent,
    'is_favorite': isFavorite,
  };

  SavedSearch copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    String? typeFilter,
    String? locationFilter,
    String? positionFilter,
    String? faaRuleFilter,
    String? airframeScopeFilter,
    String? specialtyFilter,
    String? certificateFilter,
    String? ratingFilter,
    String? instructorHoursFilter,
    String? flightHoursFilter,
    String? specialtyHoursFilter,
    String? statusFilter,
    String? sort,
    int? minimumMatchPercent,
    bool? isFavorite,
  }) {
    return SavedSearch(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      typeFilter: typeFilter ?? this.typeFilter,
      locationFilter: locationFilter ?? this.locationFilter,
      positionFilter: positionFilter ?? this.positionFilter,
      faaRuleFilter: faaRuleFilter ?? this.faaRuleFilter,
      airframeScopeFilter: airframeScopeFilter ?? this.airframeScopeFilter,
      specialtyFilter: specialtyFilter ?? this.specialtyFilter,
      certificateFilter: certificateFilter ?? this.certificateFilter,
      ratingFilter: ratingFilter ?? this.ratingFilter,
      instructorHoursFilter: instructorHoursFilter ?? this.instructorHoursFilter,
      flightHoursFilter: flightHoursFilter ?? this.flightHoursFilter,
      specialtyHoursFilter: specialtyHoursFilter ?? this.specialtyHoursFilter,
      statusFilter: statusFilter ?? this.statusFilter,
      sort: sort ?? this.sort,
      minimumMatchPercent: minimumMatchPercent ?? this.minimumMatchPercent,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}
