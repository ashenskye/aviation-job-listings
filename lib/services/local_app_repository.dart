import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/application.dart';
import '../models/employer_profiles_data.dart';
import '../models/job_listing.dart';
import '../models/job_listing_template.dart';
import '../models/job_load_result.dart';
import '../models/job_seeker_profile.dart';
import '../repositories/app_repository.dart';

class LocalAppRepository implements AppRepository {
  static const String _favoriteJobIdsKey = 'favorite_job_ids';
  static const String _jobSeekerProfileKey = 'job_seeker_profile';
  static const String _employerProfilesKey = 'employer_profiles';
  static const String _jobTemplatesKey = 'job_templates';
  static const String _applicationsKey = 'job_applications';

  @override
  Future<Set<String>> loadFavoriteIds() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_favoriteJobIdsKey) ?? const [];
    return stored.toSet();
  }

  @override
  Future<void> saveFavoriteIds(Set<String> favoriteIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoriteJobIdsKey, favoriteIds.toList());
  }

  @override
  Future<JobSeekerProfile> loadJobSeekerProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_jobSeekerProfileKey);

    if (stored == null) {
      return const JobSeekerProfile();
    }

    try {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      return JobSeekerProfile.fromJson(json);
    } catch (_) {
      return const JobSeekerProfile();
    }
  }

  @override
  Future<void> saveJobSeekerProfile(JobSeekerProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_jobSeekerProfileKey, jsonEncode(profile.toJson()));
  }

  @override
  Future<EmployerProfilesData> loadEmployerProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_employerProfilesKey);

    if (stored == null) {
      return const EmployerProfilesData.empty();
    }

    try {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      return EmployerProfilesData.fromJson(json);
    } catch (_) {
      return const EmployerProfilesData.empty();
    }
  }

  @override
  Future<void> saveEmployerProfiles(EmployerProfilesData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_employerProfilesKey, jsonEncode(data.toJson()));
  }

  @override
  Future<List<JobListingTemplate>> loadJobTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_jobTemplatesKey);

    if (stored == null) {
      return const [];
    }

    try {
      final decoded = jsonDecode(stored) as List<dynamic>;
      return decoded
          .map(
            (entry) => JobListingTemplate.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> saveJobTemplates(List<JobListingTemplate> templates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _jobTemplatesKey,
      jsonEncode(templates.map((template) => template.toJson()).toList()),
    );
  }

  @override
  Future<JobLoadResult> loadJobs({
    required String backendUrl,
    required List<JobListing> fallbackJobs,
  }) async {
    try {
      final uri = Uri.parse(backendUrl);
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final raw = json.decode(response.body);
      final List<dynamic> data;

      if (raw is List) {
        data = raw;
      } else if (raw is Map<String, dynamic> && raw['jobs'] is List) {
        data = raw['jobs'];
      } else {
        throw Exception('Unexpected JSON structure');
      }

      final jobs = data
          .map((entry) => JobListing.fromJson(entry as Map<String, dynamic>))
          .toList();

      return JobLoadResult(jobs: jobs);
    } catch (_) {
      return JobLoadResult(
        jobs: fallbackJobs,
        warningMessage:
            'Could not fetch from server. Showing example data instead.',
      );
    }
  }

  @override
  Future<JobListing> createJob(JobListing job) async {
    return job;
  }

  @override
  Future<JobListing> updateJob(JobListing job) async {
    return job;
  }

  @override
  Future<void> deleteJob(JobListing job) async {}

  @override
  Future<void> saveApplication(Application app) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_applicationsKey);
    List<Map<String, dynamic>> applications;

    if (stored == null) {
      applications = [];
    } else {
      try {
        final decoded = jsonDecode(stored) as List<dynamic>;
        applications = decoded
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {
        applications = [];
      }
    }

    final index = applications.indexWhere((e) => e['id'] == app.id);
    if (index >= 0) {
      applications[index] = app.toJson();
    } else {
      applications.add(app.toJson());
    }

    await prefs.setString(_applicationsKey, jsonEncode(applications));
  }

  @override
  Future<List<Application>> getApplicationsBySeeker(String seekerId) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_applicationsKey);

    if (stored == null) {
      return const [];
    }

    try {
      final decoded = jsonDecode(stored) as List<dynamic>;
      return decoded
          .map((e) => Application.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((app) => app.jobSeekerId == seekerId)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<Application>> loadApplicationsForEmployer(String employerId) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_applicationsKey);

    if (stored == null) {
      return const [];
    }

    try {
      final decoded = jsonDecode(stored) as List<dynamic>;
      return decoded
          .map((e) => Application.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((app) => app.employerId == employerId)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> updateApplicationStatus(String applicationId, String status) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_applicationsKey);
    List<Map<String, dynamic>> applications;

    if (stored == null) {
      applications = [];
    } else {
      try {
        final decoded = jsonDecode(stored) as List<dynamic>;
        applications = decoded
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {
        applications = [];
      }
    }

    final index = applications.indexWhere((e) => e['id'] == applicationId);
    if (index < 0) {
      return;
    }

    final current = Application.fromJson(applications[index]);
    applications[index] = current
        .copyWith(
          status: status,
          updatedAt: DateTime.now(),
        )
        .toJson();

    await prefs.setString(_applicationsKey, jsonEncode(applications));
  }

  @override
  Future<bool> hasApplied(String seekerId, String jobId) async {
    final apps = await getApplicationsBySeeker(seekerId);
    return apps.any((app) => app.jobId == jobId);
  }
}
