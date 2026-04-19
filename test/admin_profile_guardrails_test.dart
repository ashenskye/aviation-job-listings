import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aviation_job_listings/main.dart';
import 'package:aviation_job_listings/models/admin_action_log.dart';
import 'package:aviation_job_listings/models/application.dart';
import 'package:aviation_job_listings/models/job_listing.dart';
import 'package:aviation_job_listings/repositories/admin_repository.dart';
import 'package:aviation_job_listings/screens/admin_dashboard.dart';

import 'helpers/fake_app_repository.dart';

void main() {
  testWidgets('profile menu always includes Admin option', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyApp(repository: FakeAppRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();

    expect(find.text('Job Seeker'), findsOneWidget);
    expect(find.text('Employer'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
  });

  testWidgets('selecting Admin without Supabase shows safe message', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyApp(repository: FakeAppRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Admin').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Admin dashboard requires Supabase sign-in.'),
      findsOneWidget,
    );
  });

  testWidgets('Admin dashboard menu can switch to employer', (
    WidgetTester tester,
  ) async {
    Future<void> pumpAdminDashboard() async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdminDashboard(
            adminRepository: _TestAdminRepository(),
            appRepository: FakeAppRepository(),
            adminEmail: 'admin@example.com',
            adminRoleLabel: 'admin',
            currentView: AdminInterfaceView.admin,
            onSwitchView: (switchContext, view) {
              if (view == AdminInterfaceView.admin) {
                return;
              }

              final label = view == AdminInterfaceView.employer
                  ? 'Employer Home'
                  : 'Job Seeker Home';

              Navigator.of(switchContext).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => Scaffold(body: Center(child: Text(label))),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpAdminDashboard();
    final adminProfileMenu = find.byKey(
      const ValueKey('admin-dashboard-profile-switcher'),
    );

    await tester.tap(adminProfileMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Employer').last);
    await tester.pumpAndSettle();
    expect(find.text('Employer Home'), findsOneWidget);
  });

  testWidgets('Admin dashboard menu can switch to job seeker', (
    WidgetTester tester,
  ) async {
    Future<void> pumpAdminDashboard() async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdminDashboard(
            adminRepository: _TestAdminRepository(),
            appRepository: FakeAppRepository(),
            adminEmail: 'admin@example.com',
            adminRoleLabel: 'admin',
            currentView: AdminInterfaceView.admin,
            onSwitchView: (switchContext, view) {
              if (view == AdminInterfaceView.admin) {
                return;
              }

              final label = view == AdminInterfaceView.employer
                  ? 'Employer Home'
                  : 'Job Seeker Home';

              Navigator.of(switchContext).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => Scaffold(body: Center(child: Text(label))),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpAdminDashboard();
    final adminProfileMenu = find.byKey(
      const ValueKey('admin-dashboard-profile-switcher'),
    );

    await tester.tap(adminProfileMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Job Seeker').last);
    await tester.pumpAndSettle();
    expect(find.text('Job Seeker Home'), findsOneWidget);
  });

  testWidgets('main profile menu can enter Admin and switch back to employer', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MyHomePage(
          title: 'Aviation Job Listings',
          repository: FakeAppRepository(),
          adminDashboardBuilder: (context, onSwitchView) => AdminDashboard(
            adminRepository: _TestAdminRepository(),
            appRepository: FakeAppRepository(),
            adminEmail: 'admin@example.com',
            adminRoleLabel: 'admin',
            currentView: AdminInterfaceView.admin,
            onSwitchView: onSwitchView,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-profile-switcher')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Admin').last);
    await tester.pumpAndSettle();

    expect(find.text('Admin Dashboard'), findsOneWidget);
    expect(find.text('acct: Admin'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('admin-dashboard-profile-switcher')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Employer').last);
    await tester.pumpAndSettle();

    expect(find.text('Create New Listing'), findsOneWidget);
  });

  testWidgets(
    'main profile menu can enter Admin and switch back to job seeker',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MyHomePage(
            title: 'Aviation Job Listings',
            repository: FakeAppRepository(),
            adminDashboardBuilder: (context, onSwitchView) => AdminDashboard(
              adminRepository: _TestAdminRepository(),
              appRepository: FakeAppRepository(),
              adminEmail: 'admin@example.com',
              adminRoleLabel: 'admin',
              currentView: AdminInterfaceView.admin,
              onSwitchView: onSwitchView,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('home-profile-switcher')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Admin').last);
      await tester.pumpAndSettle();

      expect(find.text('Admin Dashboard'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('admin-dashboard-profile-switcher')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Job Seeker').last);
      await tester.pumpAndSettle();

      expect(find.text('Favorites'), findsOneWidget);
    },
  );

  testWidgets('employer profile benefits includes Company Housing option', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyApp(repository: FakeAppRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Employer').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Employer Profile'));
    await tester.pumpAndSettle();

    final editButton = find.widgetWithText(OutlinedButton, 'Edit');
    await tester.ensureVisible(editButton);
    await tester.tap(editButton.hitTestable());
    await tester.pumpAndSettle();

    expect(find.text('Company Benefits'), findsOneWidget);
    expect(find.text('Company Housing'), findsOneWidget);
  });
}

class _TestAdminRepository implements AdminRepository {
  @override
  Future<List<AdminActionLog>> getAdminActionLogs({
    DateTime? startDate,
    DateTime? endDate,
    String? actionType,
    String? resourceType,
  }) async {
    return const [];
  }

  @override
  Future<int> getTotalJobSeekerCount() async => 0;

  @override
  Future<int> getTotalEmployerCount() async => 0;

  @override
  Future<List<JobListing>> getAllJobListings() async => const [];

  @override
  Future<List<Application>> getAllApplications() async => const [];

  @override
  Future<List<JobListing>> getExternalJobListings() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      'Method not needed for this test: ${invocation.memberName}',
    );
  }
}
