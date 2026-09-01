import 'package:droplet/core/session/providers.dart';
import 'package:droplet/core/session/session_repository.dart';
import 'package:droplet/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots to login route', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRepositoryProvider
              .overrideWithValue(SessionRepository(MemoryKeyValueStore())),
        ],
        child: const DropletApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Droplet'), findsWidgets);
  });
}
