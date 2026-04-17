import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_action_log.dart';
import '../models/application.dart';
import '../models/employer_profile.dart';
import '../models/job_listing.dart';
import '../models/job_seeker_profile.dart';
import 'admin_repository.dart';

class SupabaseAdminRepository implements AdminRepository {
  const SupabaseAdminRepository(this._client, this._adminUserId);

  final SupabaseClient _client;
  final String _adminUserId;

  // ── Action Logging ────────────────────────────────────────────────────────

  @override
  Future<void> logAdminAction(AdminActionLog log) async {
    // Omit 'id' so the database generates it via gen_random_uuid() default.
    final payload = Map<String, dynamic>.from(log.toJson())..remove('id');
    await _client.from('admin_action_logs').insert(payload);
  }

  @override
  Future<List<AdminActionLog>> getAdminActionLogs({
    DateTime? startDate,
    DateTime? endDate,
    String? actionType,
    String? resourceType,
  }) async {
    var query = _client
        .from('admin_action_logs')
        .select()
        .order('timestamp', ascending: false);

    if (startDate != null) {
      query = query.gte('timestamp', startDate.toIso8601String());
    }
    if (endDate != null) {
      query = query.lte('timestamp', endDate.toIso8601String());
    }
    if (actionType != null && actionType.isNotEmpty) {
      query = query.eq('action_type', actionType);
    }
    if (resourceType != null && resourceType.isNotEmpty) {
      query = query.eq('resource_type', resourceType);
    }

    final rows = await query;
    return rows
        .map((r) => AdminActionLog.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  // ── Read Data ─────────────────────────────────────────────────────────────

  @override
  Future<JobSeekerProfile?> getJobSeekerProfile(String userId) async {
    final row = await _client
        .from('job_seeker_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) {
      return null;
    }
    return JobSeekerProfile.fromJson(Map<String, dynamic>.from(row));
  }

  @override
  Future<EmployerProfile?> getEmployerProfile(String employerId) async {
    final row = await _client
        .from('employer_profiles')
        .select()
        .eq('id', employerId)
        .maybeSingle();
    if (row == null) {
      return null;
    }
    return EmployerProfile.fromJson(Map<String, dynamic>.from(row));
  }

  @override
  Future<List<Application>> getApplicationsForJob(String jobId) async {
    final rows = await _client
        .from('job_applications')
        .select()
        .eq('job_listing_id', jobId)
        .order('applied_at', ascending: false);
    return rows
        .map((r) => Application.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  @override
  Future<List<JobListing>> getAllJobListings() async {
    final rows = await _client
        .from('job_listings')
        .select()
        .order('created_at', ascending: false);
    return rows
        .map((r) => JobListing.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  @override
  Future<List<Application>> getAllApplications() async {
    final rows = await _client
        .from('job_applications')
        .select()
        .order('applied_at', ascending: false);
    return rows
        .map((r) => Application.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  // ── Edit Data ─────────────────────────────────────────────────────────────

  @override
  Future<void> updateJobListing(
    String jobId,
    JobListing updated,
    String reason,
  ) async {
    final beforeRow = await _client
        .from('job_listings')
        .select()
        .eq('id', jobId)
        .maybeSingle();

    await _client
        .from('job_listings')
        .update(updated.toJson())
        .eq('id', jobId);

    await logAdminAction(
      AdminActionLog(
        id: '',
        adminUserId: _adminUserId,
        actionType: AdminActionLog.actionUpdate,
        resourceType: AdminActionLog.resourceJobListing,
        resourceId: jobId,
        changesBefore: beforeRow != null
            ? Map<String, dynamic>.from(beforeRow)
            : null,
        changesAfter: updated.toJson(),
        reason: reason,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> updateApplication(
    String appId,
    Application updated,
    String reason,
  ) async {
    final beforeRow = await _client
        .from('job_applications')
        .select()
        .eq('id', appId)
        .maybeSingle();

    await _client
        .from('job_applications')
        .update(updated.toJson())
        .eq('id', appId);

    await logAdminAction(
      AdminActionLog(
        id: '',
        adminUserId: _adminUserId,
        actionType: AdminActionLog.actionUpdate,
        resourceType: AdminActionLog.resourceApplication,
        resourceId: appId,
        changesBefore: beforeRow != null
            ? Map<String, dynamic>.from(beforeRow)
            : null,
        changesAfter: updated.toJson(),
        reason: reason,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> updateJobSeekerProfile(
    String userId,
    JobSeekerProfile updated,
    String reason,
  ) async {
    final beforeRow = await _client
        .from('job_seeker_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    await _client
        .from('job_seeker_profiles')
        .update(updated.toJson())
        .eq('user_id', userId);

    await logAdminAction(
      AdminActionLog(
        id: '',
        adminUserId: _adminUserId,
        actionType: AdminActionLog.actionUpdate,
        resourceType: AdminActionLog.resourceJobSeekerProfile,
        resourceId: userId,
        changesBefore: beforeRow != null
            ? Map<String, dynamic>.from(beforeRow)
            : null,
        changesAfter: updated.toJson(),
        reason: reason,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> updateEmployerProfile(
    String empId,
    EmployerProfile updated,
    String reason,
  ) async {
    final beforeRow = await _client
        .from('employer_profiles')
        .select()
        .eq('id', empId)
        .maybeSingle();

    await _client
        .from('employer_profiles')
        .update(updated.toJson())
        .eq('id', empId);

    await logAdminAction(
      AdminActionLog(
        id: '',
        adminUserId: _adminUserId,
        actionType: AdminActionLog.actionUpdate,
        resourceType: AdminActionLog.resourceEmployerProfile,
        resourceId: empId,
        changesBefore: beforeRow != null
            ? Map<String, dynamic>.from(beforeRow)
            : null,
        changesAfter: updated.toJson(),
        reason: reason,
        timestamp: DateTime.now(),
      ),
    );
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  @override
  Future<void> deleteApplication(String appId, String reason) async {
    final beforeRow = await _client
        .from('job_applications')
        .select()
        .eq('id', appId)
        .maybeSingle();

    // Soft delete: mark archived
    await _client
        .from('job_applications')
        .update({'is_archived': true})
        .eq('id', appId);

    await logAdminAction(
      AdminActionLog(
        id: '',
        adminUserId: _adminUserId,
        actionType: AdminActionLog.actionDelete,
        resourceType: AdminActionLog.resourceApplication,
        resourceId: appId,
        changesBefore: beforeRow != null
            ? Map<String, dynamic>.from(beforeRow)
            : null,
        reason: reason,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> deleteJobListing(String jobId, String reason) async {
    final beforeRow = await _client
        .from('job_listings')
        .select()
        .eq('id', jobId)
        .maybeSingle();

    // Soft delete: mark status as 'archived' (matches the DB status enum).
    await _client
        .from('job_listings')
        .update({'status': 'archived'})
        .eq('id', jobId);

    await logAdminAction(
      AdminActionLog(
        id: '',
        adminUserId: _adminUserId,
        actionType: AdminActionLog.actionDelete,
        resourceType: AdminActionLog.resourceJobListing,
        resourceId: jobId,
        changesBefore: beforeRow != null
            ? Map<String, dynamic>.from(beforeRow)
            : null,
        reason: reason,
        timestamp: DateTime.now(),
      ),
    );
  }

  // ── Analytics ─────────────────────────────────────────────────────────────

  @override
  Future<int> getApplicationCountForJob(String jobId) async {
    final rows = await _client
        .from('job_applications')
        .select('id')
        .eq('job_listing_id', jobId);
    return rows.length;
  }

  @override
  Future<int> getTotalJobSeekerCount() async {
    final rows = await _client.from('job_seeker_profiles').select('user_id');
    return rows.length;
  }

  @override
  Future<int> getTotalEmployerCount() async {
    final rows = await _client.from('employer_profiles').select('id');
    return rows.length;
  }

}
