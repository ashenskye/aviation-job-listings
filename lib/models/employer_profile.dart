import 'aviation_location_catalogs.dart';

class EmployerProfile {
  final String id;
  final String companyName;
  final String headquartersAddressLine1;
  final String headquartersAddressLine2;
  final String headquartersCity;
  final String headquartersState;
  final String headquartersPostalCode;
  final String headquartersCountry;
  final String companyBannerUrl;
  final String companyLogoUrl;
  final String website;
  final String contactName;
  final String contactEmail;
  final String contactPhone;
  final String companyDescription;
  final List<String> companyBenefits;
  final bool notifyOnNewNonRejectedApplication;
  final bool notifyOnApplicationStatusChanges;
  final bool notifyDailyDigest;

  const EmployerProfile({
    required this.id,
    required this.companyName,
    this.headquartersAddressLine1 = '',
    this.headquartersAddressLine2 = '',
    this.headquartersCity = '',
    this.headquartersState = '',
    this.headquartersPostalCode = '',
    this.headquartersCountry = '',
    this.companyBannerUrl = '',
    this.companyLogoUrl = '',
    this.website = '',
    this.contactName = '',
    this.contactEmail = '',
    this.contactPhone = '',
    this.companyDescription = '',
    this.companyBenefits = const [],
    this.notifyOnNewNonRejectedApplication = true,
    this.notifyOnApplicationStatusChanges = false,
    this.notifyDailyDigest = false,
  });

  factory EmployerProfile.fromJson(Map<String, dynamic> json) {
    final legacyHeadquarters = json['headquarters']?.toString() ?? '';
    return EmployerProfile(
      id: json['id']?.toString() ?? '',
      companyName: json['companyName'] ?? 'Unnamed Company',
      headquartersAddressLine1:
          json['headquartersAddressLine1']?.toString() ?? legacyHeadquarters,
      headquartersAddressLine2:
          json['headquartersAddressLine2']?.toString() ?? '',
      headquartersCity: json['headquartersCity']?.toString() ?? '',
      headquartersState: normalizeStateProvinceValue(json['headquartersState']?.toString() ?? '') ?? json['headquartersState']?.toString() ?? '',
      headquartersPostalCode: json['headquartersPostalCode']?.toString() ?? '',
      headquartersCountry: normalizeCountryValue(json['headquartersCountry']?.toString() ?? '') ?? json['headquartersCountry']?.toString() ?? '',
      companyBannerUrl:
          json['companyBannerUrl']?.toString() ??
          json['company_banner_url']?.toString() ??
          '',
      companyLogoUrl:
          json['companyLogoUrl']?.toString() ??
          json['company_logo_url']?.toString() ??
          '',
      website: json['website']?.toString() ?? '',
      contactName: json['contactName']?.toString() ?? '',
      contactEmail: json['contactEmail']?.toString() ?? '',
      contactPhone: json['contactPhone']?.toString() ?? '',
      companyDescription: json['companyDescription']?.toString() ?? '',
      companyBenefits: List<String>.from(
        (json['companyBenefits'] as List?) ?? const [],
      ),
      notifyOnNewNonRejectedApplication:
          (json['notifyOnNewNonRejectedApplication'] as bool?) ??
          (json['notify_on_new_non_rejected_application'] as bool?) ??
          true,
      notifyOnApplicationStatusChanges:
          (json['notifyOnApplicationStatusChanges'] as bool?) ??
          (json['notify_on_application_status_changes'] as bool?) ??
          false,
      notifyDailyDigest:
          (json['notifyDailyDigest'] as bool?) ??
          (json['notify_daily_digest'] as bool?) ??
          false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'companyName': companyName,
    'headquarters': headquartersAddressLine1,
    'headquartersAddressLine1': headquartersAddressLine1,
    'headquartersAddressLine2': headquartersAddressLine2,
    'headquartersCity': headquartersCity,
    'headquartersState': headquartersState,
    'headquartersPostalCode': headquartersPostalCode,
    'headquartersCountry': headquartersCountry,
    'companyBannerUrl': companyBannerUrl,
    'companyLogoUrl': companyLogoUrl,
    'website': website,
    'contactName': contactName,
    'contactEmail': contactEmail,
    'contactPhone': contactPhone,
    'companyDescription': companyDescription,
    'companyBenefits': companyBenefits,
    'notifyOnNewNonRejectedApplication': notifyOnNewNonRejectedApplication,
    'notifyOnApplicationStatusChanges': notifyOnApplicationStatusChanges,
    'notifyDailyDigest': notifyDailyDigest,
  };
}
