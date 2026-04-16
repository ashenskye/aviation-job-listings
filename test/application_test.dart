import 'package:aviation_job_listings/models/application.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Application model', () {
    final now = DateTime(2026, 4, 16, 12);

    test('isPerfectMatch returns true for matchPercentage >= 90', () {
      final app = Application(
        id: '1',
        jobSeekerId: 'seeker1',
        jobId: 'job1',
        employerId: 'emp1',
        status: 'applied',
        matchPercentage: 90,
        coverLetter: '',
        appliedAt: now,
        updatedAt: now,
      );
      expect(app.isPerfectMatch, isTrue);
      expect(app.isGoodMatch, isFalse);
      expect(app.isStretchMatch, isFalse);
    });

    test('isPerfectMatch is false for matchPercentage < 90', () {
      final app = Application(
        id: '1',
        jobSeekerId: 'seeker1',
        jobId: 'job1',
        employerId: 'emp1',
        status: 'applied',
        matchPercentage: 89,
        coverLetter: '',
        appliedAt: now,
        updatedAt: now,
      );
      expect(app.isPerfectMatch, isFalse);
    });

    test('isGoodMatch returns true for 70-89%', () {
      for (final pct in [70, 75, 89]) {
        final app = Application(
          id: '1',
          jobSeekerId: 'seeker1',
          jobId: 'job1',
          employerId: 'emp1',
          status: 'applied',
          matchPercentage: pct,
          coverLetter: '',
          appliedAt: now,
          updatedAt: now,
        );
        expect(app.isGoodMatch, isTrue, reason: 'expected isGoodMatch at $pct%');
        expect(app.isPerfectMatch, isFalse);
        expect(app.isStretchMatch, isFalse);
      }
    });

    test('isStretchMatch returns true for matchPercentage < 70', () {
      for (final pct in [0, 50, 69]) {
        final app = Application(
          id: '1',
          jobSeekerId: 'seeker1',
          jobId: 'job1',
          employerId: 'emp1',
          status: 'applied',
          matchPercentage: pct,
          coverLetter: '',
          appliedAt: now,
          updatedAt: now,
        );
        expect(
          app.isStretchMatch,
          isTrue,
          reason: 'expected isStretchMatch at $pct%',
        );
        expect(app.isPerfectMatch, isFalse);
        expect(app.isGoodMatch, isFalse);
      }
    });

    test('toJson / fromJson round-trip', () {
      final original = Application(
        id: 'abc123',
        jobSeekerId: 'seeker42',
        jobId: 'job99',
        employerId: 'emp7',
        status: 'reviewed',
        matchPercentage: 75,
        coverLetter: 'Hello, I am interested.',
        appliedAt: now,
        updatedAt: now,
      );

      final json = original.toJson();
      final restored = Application.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.jobSeekerId, original.jobSeekerId);
      expect(restored.jobId, original.jobId);
      expect(restored.employerId, original.employerId);
      expect(restored.status, original.status);
      expect(restored.matchPercentage, original.matchPercentage);
      expect(restored.coverLetter, original.coverLetter);
      expect(restored.appliedAt, original.appliedAt);
      expect(restored.updatedAt, original.updatedAt);
      expect(json['job_seeker_id'], original.jobSeekerId);
      expect(json['job_listing_id'], original.jobId);
      expect(json['employer_id'], original.employerId);
      expect(json['cover_letter'], original.coverLetter);
      expect(json['applied_at'], original.appliedAt.toIso8601String());
      expect(json['updated_at'], original.updatedAt.toIso8601String());
    });

    test('fromJson handles missing/null fields gracefully', () {
      final app = Application.fromJson({});
      expect(app.id, '');
      expect(app.jobSeekerId, '');
      expect(app.jobId, '');
      expect(app.status, 'applied');
      expect(app.matchPercentage, 0);
      expect(app.coverLetter, '');
    });

    test('copyWith returns updated application', () {
      final original = Application(
        id: '1',
        jobSeekerId: 'seeker1',
        jobId: 'job1',
        employerId: 'emp1',
        status: 'applied',
        matchPercentage: 80,
        coverLetter: '',
        appliedAt: now,
        updatedAt: now,
      );

      final updated = original.copyWith(
        status: 'reviewed',
        updatedAt: DateTime(2026, 4, 17),
      );

      expect(updated.status, 'reviewed');
      expect(updated.updatedAt, DateTime(2026, 4, 17));
      // unchanged fields
      expect(updated.id, original.id);
      expect(updated.matchPercentage, original.matchPercentage);
    });

    test('fromJson supports snake_case keys and normalizes viewed to reviewed', () {
      final app = Application.fromJson({
        'id': 'snake-1',
        'job_seeker_id': 'seeker-x',
        'job_listing_id': 'job-x',
        'employer_id': 'employer-x',
        'status': 'viewed',
        'cover_letter': 'Cover note',
        'applied_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      expect(app.jobSeekerId, 'seeker-x');
      expect(app.jobListingId, 'job-x');
      expect(app.employerId, 'employer-x');
      expect(app.status, 'reviewed');
      expect(app.coverLetter, 'Cover note');
      expect(app.appliedAt, now);
      expect(app.updatedAt, now);
    });
  });
}
