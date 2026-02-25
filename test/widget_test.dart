import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class CounterSmokeApp extends StatefulWidget {
  const CounterSmokeApp({super.key});

  @override
  State<CounterSmokeApp> createState() => _CounterSmokeAppState();
}

class _CounterSmokeAppState extends State<CounterSmokeApp> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: Text('$_count')),
        floatingActionButton: FloatingActionButton(
          onPressed: () => setState(() => _count += 1),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const CounterSmokeApp());

    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });
}
