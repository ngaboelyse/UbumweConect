import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ubumwe_connect/app/app.dart';

void main() {
  testWidgets('Ubumwe Connect app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: UbumweConnectApp()));
    await tester.pump();

    expect(find.byType(UbumweConnectApp), findsOneWidget);
  });
}
