import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/widgets/empty_state.dart';

void main() {
  testWidgets('EmptyState renders title and message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyState(
            title: 'No tracks',
            message: 'The server returned an empty track list.',
          ),
        ),
      ),
    );

    expect(find.text('No tracks'), findsOneWidget);
    expect(
        find.text('The server returned an empty track list.'), findsOneWidget);
  });
}
