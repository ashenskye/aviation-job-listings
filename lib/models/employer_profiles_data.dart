import 'employer_profile.dart';

class EmployerProfilesData {
  final List<EmployerProfile> profiles;
  final String? currentEmployerId;

  const EmployerProfilesData({
    required this.profiles,
    required this.currentEmployerId,
  });

  const EmployerProfilesData.empty()
    : profiles = const [],
      currentEmployerId = null;

  factory EmployerProfilesData.fromJson(Map<String, dynamic> json) {
    return EmployerProfilesData(
      profiles: (json['profiles'] as List<dynamic>?)
              ?.map((e) => EmployerProfile.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      currentEmployerId: json['currentId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'profiles': profiles.map((profile) => profile.toJson()).toList(),
    'currentId': currentEmployerId,
  };
}
