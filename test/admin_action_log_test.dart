import 'package:aviation_job_listings/models/admin_action_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdminActionLog model', () {
    final now = DateTime(2026, 4, 17, 12, 30);

    test('constants are defined correctly', () {
      expect(AdminActionLog.actionCreate, 'create');
      expect(AdminActionLog.actionUpdate, 'update');
      expect(AdminActionLog.actionDelete, 'delete');
      expect(AdminActionLog.actionView, 'view');

      expect(AdminActionLog.resourceApplication, 'application');
      expect(AdminActionLog.resourceJobListing, 'job_listing');
      expect(AdminActionLog.resourceJobSeekerProfile, 'job_seeker_profile');
      expect(AdminActionLog.resourceEmployerProfile, 'employer_profile');
    });

    test('toJson / fromJson round-trip (minimal fields)', () {
      final original = AdminActionLog(
        id: 'log-1',
        adminUserId: 'admin-uuid',
        actionType: AdminActionLog.actionView,
        resourceType: AdminActionLog.resourceJobListing,
        resourceId: 'job-42',
        timestamp: now,
      );

      final json = original.toJson();
      final restored = AdminActionLog.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.adminUserId, original.adminUserId);
      expect(restored.actionType, original.actionType);
      expect(restored.resourceType, original.resourceType);
      expect(restored.resourceId, original.resourceId);
      expect(restored.timestamp, original.timestamp);
      expect(restored.changesBefore, isNull);
      expect(restored.changesAfter, isNull);
      expect(restored.reason, isNull);
      expect(restored.ipAddress, isNull);
    });

    test('toJson / fromJson round-trip (full fields)', () {
      final original = AdminActionLog(
        id: 'log-2',
        adminUserId: 'admin-uuid',
        actionType: AdminActionLog.actionUpdate,
        resourceType: AdminActionLog.resourceApplication,
        resourceId: 'app-99',
        changesBefore: {'status': 'applied'},
        changesAfter: {'status': 'reviewed'},
        reason: 'Fixed typo in status',
        timestamp: now,
        ipAddress: '127.0.0.1',
      );

      final json = original.toJson();
      final restored = AdminActionLog.fromJson(json);

      expect(restored.changesBefore, {'status': 'applied'});
      expect(restored.changesAfter, {'status': 'reviewed'});
      expect(restored.reason, 'Fixed typo in status');
      expect(restored.ipAddress, '127.0.0.1');
    });

    test('toJson uses snake_case keys', () {
      final log = AdminActionLog(
        id: 'log-3',
        adminUserId: 'admin-abc',
        actionType: AdminActionLog.actionDelete,
        resourceType: AdminActionLog.resourceJobListing,
        resourceId: 'job-7',
        timestamp: now,
        reason: 'Duplicate listing',
      );

      final json = log.toJson();
      expect(json['admin_user_id'], 'admin-abc');
      expect(json['action_type'], 'delete');
      expect(json['resource_type'], 'job_listing');
      expect(json['resource_id'], 'job-7');
      expect(json['timestamp'], now.toIso8601String());
      expect(json['reason'], 'Duplicate listing');
    });

    test('fromJson handles snake_case and camelCase keys', () {
      // snake_case
      final fromSnake = AdminActionLog.fromJson({
        'id': 'log-4',
        'admin_user_id': 'admin-uuid',
        'action_type': 'create',
        'resource_type': 'employer_profile',
        'resource_id': 'emp-1',
        'timestamp': now.toIso8601String(),
      });
      expect(fromSnake.adminUserId, 'admin-uuid');
      expect(fromSnake.actionType, 'create');
      expect(fromSnake.resourceType, 'employer_profile');

      // camelCase
      final fromCamel = AdminActionLog.fromJson({
        'id': 'log-5',
        'adminUserId': 'admin-xyz',
        'action_type': 'view',
        'resourceType': 'job_seeker_profile',
        'resource_id': 'user-1',
        'timestamp': now.toIso8601String(),
      });
      expect(fromCamel.adminUserId, 'admin-xyz');
      expect(fromCamel.resourceType, 'job_seeker_profile');
    });

    test('fromJson falls back to created_at for timestamp', () {
      final log = AdminActionLog.fromJson({
        'id': 'log-6',
        'admin_user_id': 'admin-uuid',
        'action_type': 'view',
        'resource_type': 'application',
        'resource_id': 'app-1',
        'created_at': now.toIso8601String(),
        // no 'timestamp' key
      });
      expect(log.timestamp, now);
    });

    test('copyWith preserves unchanged fields', () {
      final original = AdminActionLog(
        id: 'log-7',
        adminUserId: 'admin-uuid',
        actionType: AdminActionLog.actionView,
        resourceType: AdminActionLog.resourceApplication,
        resourceId: 'app-5',
        timestamp: now,
        reason: 'Support request',
      );

      final copy = original.copyWith(
        actionType: AdminActionLog.actionUpdate,
        reason: 'Admin correction',
      );

      expect(copy.id, original.id);
      expect(copy.adminUserId, original.adminUserId);
      expect(copy.resourceType, original.resourceType);
      expect(copy.resourceId, original.resourceId);
      expect(copy.timestamp, original.timestamp);
      expect(copy.actionType, AdminActionLog.actionUpdate);
      expect(copy.reason, 'Admin correction');
    });

    test('optional fields absent from toJson when null', () {
      final log = AdminActionLog(
        id: 'log-8',
        adminUserId: 'admin-uuid',
        actionType: AdminActionLog.actionView,
        resourceType: AdminActionLog.resourceJobListing,
        resourceId: 'job-1',
        timestamp: now,
      );

      final json = log.toJson();
      expect(json.containsKey('changes_before'), isFalse);
      expect(json.containsKey('changes_after'), isFalse);
      expect(json.containsKey('reason'), isFalse);
      expect(json.containsKey('ip_address'), isFalse);
    });
  });
}
