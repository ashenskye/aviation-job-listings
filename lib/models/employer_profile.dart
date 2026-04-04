class EmployerProfile {
  final String id;
  final String companyName;
  final String headquartersAddressLine1;
  final String headquartersAddressLine2;
  final String headquartersCity;
  final String headquartersState;
  final String headquartersPostalCode;
  final String headquartersCountry;
  final String website;
  final String contactName;
  final String contactEmail;
  final String contactPhone;
  final String companyDescription;

  const EmployerProfile({
    required this.id,
    required this.companyName,
    this.headquartersAddressLine1 = '',
    this.headquartersAddressLine2 = '',
    this.headquartersCity = '',
    this.headquartersState = '',
    this.headquartersPostalCode = '',
    this.headquartersCountry = '',
    this.website = '',
    this.contactName = '',
    this.contactEmail = '',
    this.contactPhone = '',
    this.companyDescription = '',
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
      headquartersState: json['headquartersState']?.toString() ?? '',
      headquartersPostalCode:
          json['headquartersPostalCode']?.toString() ?? '',
      headquartersCountry: json['headquartersCountry']?.toString() ?? '',
      website: json['website']?.toString() ?? '',
      contactName: json['contactName']?.toString() ?? '',
      contactEmail: json['contactEmail']?.toString() ?? '',
      contactPhone: json['contactPhone']?.toString() ?? '',
      companyDescription: json['companyDescription']?.toString() ?? '',
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
    'website': website,
    'contactName': contactName,
    'contactEmail': contactEmail,
    'contactPhone': contactPhone,
    'companyDescription': companyDescription,
  };
}
