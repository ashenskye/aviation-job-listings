import 'job_listing.dart';

class JobListingTemplate {
  final String id;
  final String employerId;
  final String name;
  final JobListing listing;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const JobListingTemplate({
    required this.id,
    required this.employerId,
    required this.name,
    required this.listing,
    this.createdAt,
    this.updatedAt,
  });

  factory JobListingTemplate.fromJson(Map<String, dynamic> json) {
    return JobListingTemplate(
      id: json['id']?.toString() ?? '',
      employerId: json['employerId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled Template',
      listing: JobListing.fromJson(
        Map<String, dynamic>.from(
          (json['listing'] as Map<String, dynamic>?) ?? const {},
        ),
      ),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'employerId': employerId,
    'name': name,
    'listing': listing.toJson(),
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };
}
