import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/application.dart';
import '../models/application_feedback.dart';
import '../models/employer_profiles_data.dart';
import '../models/job_listing.dart';
import '../models/job_listing_report.dart';
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
  static const String _feedbackKey = 'application_feedback';
  static const String _jobListingReportsKey = 'job_listing_reports';

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
  Future<List<Application>> loadApplicationsForEmployer(
    String employerId,
  ) async {
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
  Future<void> updateApplicationStatus(
    String applicationId,
    String status,
  ) async {
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
        .copyWith(status: status, updatedAt: DateTime.now())
        .toJson();

    await prefs.setString(_applicationsKey, jsonEncode(applications));
  }

  @override
  Future<void> updateApplicationArchived(
    String applicationId,
    bool isArchived,
  ) async {
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
        .copyWith(isArchived: isArchived, updatedAt: DateTime.now())
        .toJson();

    await prefs.setString(_applicationsKey, jsonEncode(applications));
  }

  @override
  Future<void> deleteApplication(String applicationId) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_applicationsKey);
    if (stored == null) return;

    try {
      final decoded = jsonDecode(stored) as List<dynamic>;
      final applications = decoded
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => e['id'] != applicationId)
          .toList();
      await prefs.setString(_applicationsKey, jsonEncode(applications));
    } catch (_) {}
  }

  @override
  Future<void> deleteApplications(List<String> applicationIds) async {
    if (applicationIds.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_applicationsKey);
    if (stored == null) return;

    try {
      final idSet = applicationIds.toSet();
      final decoded = jsonDecode(stored) as List<dynamic>;
      final applications = decoded
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => !idSet.contains(e['id']))
          .toList();
      await prefs.setString(_applicationsKey, jsonEncode(applications));
    } catch (_) {}
  }

  @override
  Future<bool> hasApplied(String seekerId, String jobId) async {
    final apps = await getApplicationsBySeeker(seekerId);
    return apps.any((app) => app.jobId == jobId);
  }

  @override
  Future<Application?> getLatestApplicationForJob(
    String seekerId,
    String jobId,
  ) async {
    final apps = await getApplicationsBySeeker(seekerId);
    final matching = apps.where((app) => app.jobId == jobId).toList()
      ..sort((a, b) => b.appliedAt.compareTo(a.appliedAt));
    return matching.isEmpty ? null : matching.first;
  }

  @override
  Future<void> reportJobListing(JobListingReport report) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_jobListingReportsKey);
    List<Map<String, dynamic>> reports;

    if (stored == null) {
      reports = [];
    } else {
      try {
        final decoded = jsonDecode(stored) as List<dynamic>;
        reports = decoded
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {
        reports = [];
      }
    }

    reports.add(report.toJson());
    await prefs.setString(_jobListingReportsKey, jsonEncode(reports));
  }

  @override
  Future<FeedbackSaveDestination> saveFeedback(
    ApplicationFeedback feedback,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_feedbackKey);
    List<Map<String, dynamic>> feedbackList;

    if (stored == null) {
      feedbackList = [];
    } else {
      try {
        final decoded = jsonDecode(stored) as List<dynamic>;
        feedbackList = decoded
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {
        feedbackList = [];
      }
    }

    final index = feedbackList.indexWhere(
      (e) => e['application_id'] == feedback.applicationId,
    );
    if (index >= 0) {
      feedbackList[index] = feedback.toJson();
    } else {
      feedbackList.add(feedback.toJson());
    }

    await prefs.setString(_feedbackKey, jsonEncode(feedbackList));
    return FeedbackSaveDestination.local;
  }

  @override
  Future<List<ApplicationFeedback>> getAllFeedback() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_feedbackKey);

    if (stored == null) {
      return const [];
    }

    try {
      final decoded = jsonDecode(stored) as List<dynamic>;
      return decoded
          .map(
            (e) => ApplicationFeedback.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<ApplicationFeedback?> getFeedbackForApplication(
    String applicationId,
  ) async {
    final all = await getAllFeedback();
    try {
      return all.firstWhere((f) => f.applicationId == applicationId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> sendEmployerNotificationTestEmail(String employerId) async {
    return 'Test email is available when Supabase mode is enabled.';
  }
}
