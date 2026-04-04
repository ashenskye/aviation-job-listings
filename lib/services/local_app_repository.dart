import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/employer_profiles_data.dart';
import '../models/job_listing.dart';
import '../models/job_load_result.dart';
import '../models/job_seeker_profile.dart';
import '../repositories/app_repository.dart';

class LocalAppRepository implements AppRepository {
  static const String _favoriteJobIdsKey = 'favorite_job_ids';
  static const String _jobSeekerProfileKey = 'job_seeker_profile';
  static const String _employerProfilesKey = 'employer_profiles';

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
  Future<JobLoadResult> loadJobs({
    required String backendUrl,
    required List<JobListing> fallbackJobs,
    required JobListing testingJob,
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

      return JobLoadResult(jobs: _withSyncedTestingJob(jobs, testingJob));
    } catch (_) {
      return JobLoadResult(
        jobs: _withSyncedTestingJob(fallbackJobs, testingJob),
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

  List<JobListing> _withSyncedTestingJob(
    List<JobListing> jobs,
    JobListing testingJob,
  ) {
    final nonTestJobs = jobs.where((job) => job.id != testingJob.id).toList();
    return [testingJob, ...nonTestJobs];
  }
}
