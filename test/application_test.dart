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
        status: 'viewed',
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
        status: 'viewed',
        updatedAt: DateTime(2026, 4, 17),
      );

      expect(updated.status, 'viewed');
      expect(updated.updatedAt, DateTime(2026, 4, 17));
      // unchanged fields
      expect(updated.id, original.id);
      expect(updated.matchPercentage, original.matchPercentage);
    });
  });
}
