import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_camera_next/core/widgets/stash_dial.dart';

void main() {
  testWidgets('tap and drag select a dial stop', (tester) async {
    final selections = <int>[];
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              child: StatefulBuilder(
                builder: (context, setState) => StashDial(
                  labels: const ['Photo', 'Video'],
                  icons: const [Icons.photo_camera, Icons.videocam],
                  selected: selected,
                  onChanged: (index) {
                    selections.add(index);
                    setState(() => selected = index);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.videocam));
    await tester.pumpAndSettle();
    expect(selections, [1]);

    await tester.drag(find.byIcon(Icons.videocam), const Offset(-85, 0));
    await tester.pumpAndSettle();
    expect(selections, [1, 0]);
  });

  for (final axis in Axis.values) {
    testWidgets('short flick advances the ${axis.name} dial', (tester) async {
      final selections = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: axis == Axis.horizontal ? 160 : 44,
              height: axis == Axis.vertical ? 160 : 44,
              child: StashDial(
                axis: axis,
                labels: const ['First', 'Second'],
                selected: 0,
                onChanged: selections.add,
              ),
            ),
          ),
        ),
      );

      final distance = axis == Axis.horizontal
          ? const Offset(30, 0)
          : const Offset(0, 30);
      await tester.timedDrag(
        find.text('First'),
        distance,
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();
      expect(selections, [0]);

      await tester.fling(find.text('First'), distance, 900);
      await tester.pumpAndSettle();
      expect(selections, [0, 1]);
    });
  }
}
