import 'package:aviation_job_listings/models/application.dart';
import 'package:aviation_job_listings/models/job_listing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_app_repository.dart';

void main() {
  final now = DateTime.now();

  Application makeApp({
    String id = 'app-1',
    String jobId = 'job-1',
    String status = Application.statusApplied,
    int matchPercentage = 80,
    bool isArchived = false,
  }) {
    return Application(
      id: id,
      jobSeekerId: 'seeker-1',
      jobId: jobId,
      employerId: 'emp-1',
      status: status,
      matchPercentage: matchPercentage,
      coverLetter: '',
      appliedAt: now,
      updatedAt: now,
      isArchived: isArchived,
    );
  }

  // ── Application model ───────────────────────────────────────────────────────

  group('Application.isArchived', () {
    test('defaults to false', () {
      final app = makeApp();
      expect(app.isArchived, isFalse);
    });

    test('can be set to true', () {
      final app = makeApp(isArchived: true);
      expect(app.isArchived, isTrue);
    });

    test('copyWith updates isArchived', () {
      final app = makeApp();
      final archived = app.copyWith(isArchived: true);
      expect(archived.isArchived, isTrue);
      expect(archived.id, app.id);
      expect(archived.status, app.status);
    });

    test('toJson / fromJson round-trip preserves isArchived=true', () {
      final app = makeApp(isArchived: true);
      final json = app.toJson();
      expect(json['is_archived'], isTrue);
      final restored = Application.fromJson(json);
      expect(restored.isArchived, isTrue);
    });

    test('fromJson defaults isArchived to false when key is absent', () {
      final json = makeApp().toJson()..remove('is_archived');
      final restored = Application.fromJson(json);
      expect(restored.isArchived, isFalse);
    });
  });

  // ── JobListing model ────────────────────────────────────────────────────────

  group('JobListing.isActive / archivedAt', () {
    JobListing makeJob({
      bool isActive = true,
      String? status,
      DateTime? archivedAt,
      DateTime? deadlineDate,
    }) {
      return JobListing(
        id: 'job-1',
        title: 'Captain',
        company: 'Phoenix Air',
        location: 'Phoenix, AZ',
        type: 'Full-time',
        crewRole: 'Single Pilot',
        faaRules: const [],
        description: 'Test job',
        faaCertificates: const [],
        flightExperience: const [],
        aircraftFlown: const [],
        status: status,
        isActive: isActive,
        archivedAt: archivedAt,
        deadlineDate: deadlineDate,
      );
    }

    test('isActive defaults to true', () {
      final job = makeJob();
      expect(job.isActive, isTrue);
    });

    test('archivedAt defaults to null', () {
      final job = makeJob();
      expect(job.archivedAt, isNull);
    });

    test('isExpired false when no deadline', () {
      final job = makeJob();
      expect(job.isExpired, isFalse);
    });

    test('isExpired false when deadline is in the future', () {
      final job = makeJob(deadlineDate: now.add(const Duration(days: 10)));
      expect(job.isExpired, isFalse);
    });

    test('isExpired true when deadline is in the past', () {
      final job = makeJob(deadlineDate: now.subtract(const Duration(days: 1)));
      expect(job.isExpired, isTrue);
    });

    test('shouldShow true for active non-expired job', () {
      final job = makeJob(deadlineDate: now.add(const Duration(days: 5)));
      expect(job.shouldShow, isTrue);
    });

    test('shouldShow false for expired job (isActive=true but deadline past)', () {
      final job = makeJob(deadlineDate: now.subtract(const Duration(days: 1)));
      expect(job.shouldShow, isFalse);
    });

    test('shouldShow false for archived job', () {
      final job = makeJob(isActive: false);
      expect(job.shouldShow, isFalse);
    });

    test('explicit expired status hides the job even without deadline', () {
      final job = makeJob(status: JobListing.statusExpired);
      expect(job.isExpired, isTrue);
      expect(job.shouldShow, isFalse);
    });

    test('toJson / fromJson round-trip preserves explicit status', () {
      final job = makeJob(status: JobListing.statusExpired);
      final restored = JobListing.fromJson(job.toJson());
      expect(restored.status, JobListing.statusExpired);
      expect(restored.isActive, isFalse);
      expect(restored.isExpired, isTrue);
    });

    test('daysUntilDeadline is null when no deadline', () {
      final job = makeJob();
      expect(job.daysUntilDeadline, isNull);
    });

    test('daysUntilDeadline is positive for future deadline', () {
      final job = makeJob(deadlineDate: now.add(const Duration(days: 5)));
      expect(job.daysUntilDeadline, greaterThan(0));
    });

    test('toJson / fromJson round-trip for isActive and archivedAt', () {
      final archived = DateTime(2026, 4, 10, 8);
      final job = makeJob(isActive: false, archivedAt: archived);
      final json = job.toJson();
      expect(json['isActive'], isFalse);
      expect(json['archivedAt'], archived.toIso8601String());
      final restored = JobListing.fromJson(json);
      expect(restored.isActive, isFalse);
      expect(restored.archivedAt, archived);
    });

    test('fromJson defaults isActive to true when absent', () {
      final json = makeJob().toJson()..remove('isActive');
      final restored = JobListing.fromJson(json);
      expect(restored.isActive, isTrue);
    });

    test('copyWith can archive a job', () {
      final job = makeJob();
      final archived = job.copyWith(isActive: false, archivedAt: now);
      expect(archived.isActive, isFalse);
      expect(archived.archivedAt, now);
      expect(archived.id, job.id);
    });

    test('copyWith can reopen a job (clear archivedAt)', () {
      final job = makeJob(isActive: false, archivedAt: now);
      final future = now.add(const Duration(days: 30));
      final reopened = job.copyWith(
        isActive: true,
        archivedAt: null,
        deadlineDate: future,
      );
      expect(reopened.isActive, isTrue);
      expect(reopened.archivedAt, isNull);
      expect(reopened.deadlineDate, future);
    });
  });

  // ── Repository: archive / delete ────────────────────────────────────────────

  group('FakeAppRepository archive / delete', () {
    late FakeAppRepository repo;

    setUp(() {
      repo = FakeAppRepository();
    });

    test('updateApplicationArchived sets isArchived to true', () async {
      final app = makeApp();
      await repo.saveApplication(app);
      await repo.updateApplicationArchived(app.id, true);
      final apps = await repo.getApplicationsBySeeker('seeker-1');
      expect(apps.first.isArchived, isTrue);
    });

    test('updateApplicationArchived can unarchive', () async {
      final app = makeApp(isArchived: true);
      await repo.saveApplication(app);
      await repo.updateApplicationArchived(app.id, false);
      final apps = await repo.getApplicationsBySeeker('seeker-1');
      expect(apps.first.isArchived, isFalse);
    });

    test('deleteApplication removes the application', () async {
      final app1 = makeApp(id: 'app-1');
      final app2 = makeApp(id: 'app-2');
      await repo.saveApplication(app1);
      await repo.saveApplication(app2);
      await repo.deleteApplication('app-1');
      final apps = await repo.getApplicationsBySeeker('seeker-1');
      expect(apps.map((a) => a.id).toList(), ['app-2']);
    });

    test('deleteApplication is a no-op for unknown id', () async {
      final app = makeApp();
      await repo.saveApplication(app);
      await repo.deleteApplication('nonexistent');
      final apps = await repo.getApplicationsBySeeker('seeker-1');
      expect(apps.length, 1);
    });

    test('deleteApplications removes multiple applications', () async {
      final app1 = makeApp(id: 'app-1');
      final app2 = makeApp(id: 'app-2');
      final app3 = makeApp(id: 'app-3');
      await repo.saveApplication(app1);
      await repo.saveApplication(app2);
      await repo.saveApplication(app3);
      await repo.deleteApplications(['app-1', 'app-3']);
      final apps = await repo.getApplicationsBySeeker('seeker-1');
      expect(apps.map((a) => a.id).toList(), ['app-2']);
    });

    test('deleteApplications with empty list is a no-op', () async {
      final app = makeApp();
      await repo.saveApplication(app);
      await repo.deleteApplications([]);
      final apps = await repo.getApplicationsBySeeker('seeker-1');
      expect(apps.length, 1);
    });
  });

  // ── Grouping logic ──────────────────────────────────────────────────────────

  group('Group applications by job', () {
    test('groups applications by jobId', () {
      final apps = [
        makeApp(id: 'a1', jobId: 'job-1'),
        makeApp(id: 'a2', jobId: 'job-2'),
        makeApp(id: 'a3', jobId: 'job-1'),
      ];
      final groups = <String, List<Application>>{};
      for (final app in apps) {
        groups.putIfAbsent(app.jobId, () => []).add(app);
      }
      expect(groups['job-1']!.length, 2);
      expect(groups['job-2']!.length, 1);
    });
  });

  // ── Archive filter logic ────────────────────────────────────────────────────

  group('Filter applications by archive status', () {
    final apps = [
      Application(
        id: 'a1',
        jobSeekerId: 's',
        jobId: 'j1',
        employerId: 'e',
        status: Application.statusApplied,
        matchPercentage: 80,
        coverLetter: '',
        appliedAt: now,
        updatedAt: now,
        isArchived: false,
      ),
      Application(
        id: 'a2',
        jobSeekerId: 's',
        jobId: 'j1',
        employerId: 'e',
        status: Application.statusApplied,
        matchPercentage: 70,
        coverLetter: '',
        appliedAt: now,
        updatedAt: now,
        isArchived: true,
      ),
      Application(
        id: 'a3',
        jobSeekerId: 's',
        jobId: 'j2',
        employerId: 'e',
        status: Application.statusRejected,
        matchPercentage: 50,
        coverLetter: '',
        appliedAt: now,
        updatedAt: now,
        isArchived: false,
      ),
    ];

    test('active filter returns only non-archived', () {
      final active = apps.where((app) => !app.isArchived).toList();
      expect(active.length, 2);
      expect(active.every((a) => !a.isArchived), isTrue);
    });

    test('archived filter returns only archived', () {
      final archived = apps.where((app) => app.isArchived).toList();
      expect(archived.length, 1);
      expect(archived.first.id, 'a2');
    });

    test('rejected filter returns only rejected', () {
      final rejected = apps
          .where((app) => app.status == Application.statusRejected)
          .toList();
      expect(rejected.length, 1);
      expect(rejected.first.id, 'a3');
    });

    test('all filter returns all applications', () {
      expect(apps.length, 3);
    });
  });
}
