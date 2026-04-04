import 'package:flutter_test/flutter_test.dart';

import 'package:aviation_job_listings/main.dart';

import 'helpers/fake_app_repository.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp(repository: FakeAppRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Aviation Job Listings'), findsOneWidget);
  });
}
