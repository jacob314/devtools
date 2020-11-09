// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:devtools_app/src/globals.dart';
import 'package:devtools_app/src/inspector/inspector_screen.dart';
import 'package:devtools_app/src/inspector/inspector_tree_flutter.dart';
import 'package:devtools_testing/support/file_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devtools_testing/support/flutter_test_driver.dart'
    show FlutterRunConfiguration;
import 'package:devtools_testing/support/flutter_test_environment.dart';

import 'package:devtools_app/src/inspector/inspector_controller.dart';
import 'package:devtools_app/src/inspector/inspector_service.dart';
import 'package:flutter_test/flutter_test.dart' show TestWidgetsFlutterBinding;

import 'support/wrappers.dart';

void main() async {
  // We need to use real async in this test so we need to use this binding.
  TestWidgetsFlutterBinding.ensureInitialized({'FLUTTER_TEST': 'false'});
  const windowSize = Size(2600.0, 1200.0);

  final FlutterTestEnvironment env = FlutterTestEnvironment(
    const FlutterRunConfiguration(withDebugger: true),
  );

  InspectorService inspectorService;

  env.afterNewSetup = () async {
    await ensureInspectorServiceDependencies();
  };

  env.afterEverySetup = () async {
    inspectorService = await InspectorService.create(env.service);
    if (env.reuseTestEnvironment) {
      // Ensure the previous test did not set the selection on the device.
      // TODO(jacobr): add a proper method to WidgetInspectorService that does
      // this. setSelection currently ignores null selection requests which is
      // a misfeature.
      await inspectorService.inspectorLibrary.eval(
        'WidgetInspectorService.instance.selection.clear()',
        isAlive: null,
      );
    }

    await inspectorService.inferPubRootDirectoryIfNeeded();
  };

  env.beforeEveryTearDown = () async {
    //inspectorController?.dispose();
    //inspectorController = null;
    inspectorService?.dispose();
    inspectorService = null;
  };

  group('inspector controller tests', () {
    tearDownAll(() async {
      await env.tearDownEnvironment(force: true);
    });

    testWidgetsWithWindowSize('inititial state', windowSize,
              (WidgetTester tester) async {
      print("XXX setting up env");
      await env.setupEnvironment();
      expect(serviceManager.service, equals(env.service));
      expect(serviceManager.isolateManager, isNotNull);

      const screen = InspectorScreen();
      await tester.pumpWidget(
          wrapWithInspectorControllers(Builder(builder: screen.build)));
      print ("XXX env. ${env.service.connectedUri}");
      await tester.pumpAndSettle(const Duration(seconds: 1));
      InspectorScreenBodyState state = tester.state(find.byType(InspectorScreenBody));
      final controller = state.inspectorController;
      while(!controller.flutterAppFrameReady) {
        await state.inspectorController.maybeLoadUI();
        print("XXX checking if loaded. ${controller.flutterAppFrameReady}");
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }
      print("DONESZO");
      await tester.pumpAndSettle(const Duration(seconds: 15));
      await expectLater(
        find.byType(InspectorScreenBody),
        matchesGoldenFile('goldens/integration_inspector_initial_load.png'),
      );
      // TODO(jacobr): remove.
      await tester.pumpWidget(const SizedBox());
      await env.tearDownEnvironment();
    });

    // TODO(jacobr): convert these tests to screenshot tests like the initial
    // state test.
    /*
    test('select widget', () async {
      await env.setupEnvironment();

      // select row index 5.
      simulateRowClick(tree, rowIndex: 5);
      const textSelected = // Comment to make dartfmt behave.
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold\n'
          '      ├───▼[C]Center\n'
          '      │     [/icons/inspector/textArea.png]Text <-- selected\n'
          '      └─▼[A]AppBar\n'
          '          [/icons/inspector/textArea.png]Text\n';

      expect(tree.toStringDeep(), equalsIgnoringHashCodes(textSelected));
      expect(
        tree.toStringDeep(includeTextStyles: true),
        equalsGoldenIgnoringHashCodes(
            'inspector_controller_selection_with_styles.txt'),
      );

      await detailsTree.nextUiFrame;
      expect(
        detailsTree.toStringDeep(),
        equalsGoldenIgnoringHashCodes(
            'inspector_controller_text_details_tree.txt'),
      );

      expect(
        detailsTree.toStringDeep(includeTextStyles: true),
        equalsGoldenIgnoringHashCodes(
            'inspector_controller_text_details_tree_with_styles.txt'),
      );

      // Select the RichText row.
      simulateRowClick(detailsTree, rowIndex: 10);
      expect(
        detailsTree.toStringDeep(),
        equalsGoldenIgnoringHashCodes(
            'inspector_controller_text_details_tree_richtext_selected.txt'),
      );

      // Test hovering over the icon shown when a property has its default
      // value.
      const int rowIndex = 2;
      final double y = detailsTree.getRowY(rowIndex);
      final textAlignRow = detailsTree.getRow(Offset(0, y));
      final FakeInspectorTreeNode node = textAlignRow.node;
      final FakePaintEntry lastIconEntry = node.renderObject.entries
          .firstWhere((entry) => entry.icon == defaultIcon, orElse: () => null);
      // If the entry doesn't have the defaultIcon then the tree has changed
      // and the rest of this test case won't make sense.
      expect(lastIconEntry.icon, equals(defaultIcon));
      expect(tree.tooltip, isEmpty);
      await tree.onHover(textAlignRow.node, lastIconEntry);
      expect(tree.tooltip, equals('Default value'));
      await tree.onHover(null, null);
      expect(tree.tooltip, isEmpty);
      // TODO(jacobr): add a test that covers hovering over an enum value
      // and getting a tooltip containing all its values.

      // make sure the main tree didn't change due to changing selection in the
      // detail tree
      expect(tree.toStringDeep(), equalsIgnoringHashCodes(textSelected));

      // select row index 3.
      simulateRowClick(tree, rowIndex: 3);

      expect(
        tree.toStringDeep(),
        equalsIgnoringHashCodes(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold <-- selected\n'
          '      ├───▼[C]Center\n'
          '      │     [/icons/inspector/textArea.png]Text\n'
          '      └─▼[A]AppBar\n'
          '          [/icons/inspector/textArea.png]Text\n',
        ),
      );

      await detailsTree.nextUiFrame;
      // This tree is huge. If there is a change to package:flutter it may
      // change. If this happens don't panic and rebaseline the content.
      expect(
        detailsTree.toStringDeep(),
        equalsGoldenIgnoringHashCodes(
            'inspector_controller_details_tree_scaffold.txt'),
      );

      // The important thing about this is that the details tree should scroll
      // instead of re-rooting as the selected row is already visible in the
      // details tree.
      simulateRowClick(tree, rowIndex: 4);
      expect(
        tree.toStringDeep(),
        equalsIgnoringHashCodes(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold\n'
          '      ├───▼[C]Center <-- selected\n'
          '      │     [/icons/inspector/textArea.png]Text\n'
          '      └─▼[A]AppBar\n'
          '          [/icons/inspector/textArea.png]Text\n',
        ),
      );

      await detailsTree.nextUiFrame;
      expect(
        detailsTree.toStringDeep(hidePropertyLines: true),
        equalsGoldenIgnoringHashCodes(
            'inspector_controller_details_tree_scrolled_to_center.txt'),
      );

      // Selecting the root node of the details tree should change selection
      // in the main tree.
      simulateRowClick(detailsTree, rowIndex: 0);
      expect(
        tree.toStringDeep(),
        equalsIgnoringHashCodes(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold <-- selected\n'
          '      ├───▼[C]Center\n'
          '      │     [/icons/inspector/textArea.png]Text\n'
          '      └─▼[A]AppBar\n'
          '          [/icons/inspector/textArea.png]Text\n',
        ),
      );

      // Verify that the details tree scrolled back as well.
      // However, now more nodes are expanded.
      expect(
        detailsTree.toStringDeep(hidePropertyLines: true),
        equalsGoldenIgnoringHashCodes(
            'inspector_controller_details_tree_scaffold_expanded.txt'),
      );

      expect(
        detailsTree.toStringDeep(
            hidePropertyLines: true, includeTextStyles: true),
        equalsGoldenIgnoringHashCodes(
            'inspector_controller_details_tree_scaffold_with_styles.txt'),
      );

      // TODO(jacobr): add tests that verified that we scrolled the view to the
      // correct points on selection.

      // Intentionally trigger multiple quick navigate action to ensure that
      // multiple quick navigation commands in a row do not trigger race
      // conditions getting out of order updates from the server.
      tree.navigateDown();
      tree.navigateDown();
      tree.navigateDown();
      await detailsTree.nextUiFrame;
      expect(
        tree.toStringDeep(),
        equalsIgnoringHashCodes(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold\n'
          '      ├───▼[C]Center\n'
          '      │     [/icons/inspector/textArea.png]Text\n'
          '      └─▼[A]AppBar <-- selected\n'
          '          [/icons/inspector/textArea.png]Text\n',
        ),
      );
      // Make sure we don't go off the bottom of the tree.
      tree.navigateDown();
      tree.navigateDown();
      tree.navigateDown();
      tree.navigateDown();
      tree.navigateDown();
      expect(
        tree.toStringDeep(),
        equalsIgnoringHashCodes(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold\n'
          '      ├───▼[C]Center\n'
          '      │     [/icons/inspector/textArea.png]Text\n'
          '      └─▼[A]AppBar\n'
          '          [/icons/inspector/textArea.png]Text <-- selected\n',
        ),
      );
      tree.navigateUp();
      expect(
        tree.toStringDeep(),
        equalsIgnoringHashCodes(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold\n'
          '      ├───▼[C]Center\n'
          '      │     [/icons/inspector/textArea.png]Text\n'
          '      └─▼[A]AppBar <-- selected\n'
          '          [/icons/inspector/textArea.png]Text\n',
        ),
      );
      tree.navigateLeft();
      await detailsTree.nextUiFrame;
      expect(
        tree.toStringDeep(),
        equalsIgnoringHashCodes(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold\n'
          '      ├───▼[C]Center\n'
          '      │     [/icons/inspector/textArea.png]Text\n'
          '      └─▶[A]AppBar <-- selected\n',
        ),
      );
      tree.navigateLeft();
      // First navigate left goes to the parent.
      expect(
        tree.toStringDeep(),
        equalsIgnoringHashCodes(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold <-- selected\n'
          '      ├───▼[C]Center\n'
          '      │     [/icons/inspector/textArea.png]Text\n'
          '      └─▶[A]AppBar\n',
        ),
      );
      tree.navigateLeft();
      // Next navigate left closes the parent.
      expect(
        tree.toStringDeep(),
        equalsIgnoringHashCodes(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▶[S]Scaffold <-- selected\n',
        ),
      );

      tree.navigateRight();
      expect(
        tree.toStringDeep(),
        equalsIgnoringHashCodes(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold <-- selected\n'
          '      ├───▼[C]Center\n'
          '      │     [/icons/inspector/textArea.png]Text\n'
          '      └─▶[A]AppBar\n',
        ),
      );

      // Node is already expanded so this is equivalent to navigate down.
      tree.navigateRight();
      expect(
        tree.toStringDeep(),
        equalsIgnoringHashCodes(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold\n'
          '      ├───▼[C]Center <-- selected\n'
          '      │     [/icons/inspector/textArea.png]Text\n'
          '      └─▶[A]AppBar\n',
        ),
      );

      await detailsTree.nextUiFrame;

      // Make sure the details and main trees have not gotten out of sync.
      expect(
        detailsTree.toStringDeep(hidePropertyLines: true),
        equalsIgnoringHashCodes('▼[C]Center <-- selected\n'
            '└─▼[/icons/inspector/textArea.png]Text\n'
            '  └─▼[/icons/inspector/textArea.png]RichText\n'),
      );

      await env.tearDownEnvironment();
    });
    */

    // TODO(jacobr): uncomment hotReload test once the hot reload test is not
    // flaky. https://github.com/flutter/devtools/issues/642
    /*
    test('hotReload', () async {
      if (flutterVersion == '1.2.1') {
        // This test can be flaky in Flutter 1.2.1 because of
        // https://github.com/dart-lang/sdk/issues/33838
        // so we just skip it. This block of code can be removed after the next
        // stable flutter release.
        // TODO(dantup): Remove this.
        return;
      }
      await env.setupEnvironment();

      await serviceManager.performHotReload();
      // Ensure the inspector does not fall over and die after a hot reload.
      expect(
        tree.toStringDeep(),
        equalsIgnoringHashCodes(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold\n'
          '      ├───▼[C]Center\n'
          '      │     [/icons/inspector/textArea.png]Text <-- selected\n'
          '      └─▼[A]AppBar\n'
          '          [/icons/inspector/textArea.png]Text\n',
        ),
      );

      // TODO(jacobr): would be nice to have some tests that trigger a hot
      // reload that actually changes app state in a meaningful way.

      await env.tearDownEnvironment();
    });
    */
// TODO(jacobr): uncomment out the hotRestart tests once
// https://github.com/flutter/devtools/issues/337 is fixed.
/*
    test('hotRestart', () async {
      await env.setupEnvironment();

      // The important thing about this is that the details tree should scroll
      // instead of re-rooting as the selected row is already visible in the
      // details tree.
      simulateRowClick(tree, rowIndex: 4);
      expect(
        tree.toStringDeep(),
        equalsIgnoringHashCodes(
          '▼[R]root]\n'
              '  ▼[M]MyApp\n'
              '    ▼[M]MaterialApp\n'
              '      ▼[S]Scaffold\n'
              '      ├───▼[C]Center <-- selected\n'
              '      │     ▼[/icons/inspector/textArea.png]Text\n'
              '      └─▼[A]AppBar\n'
              '          ▼[/icons/inspector/textArea.png]Text\n',
        ),
      );

      /// After the hot restart some existing calls to the vm service may
      /// timeout and that is ok.
      serviceManager.service.doNotWaitForPendingFuturesBeforeExit();

      await serviceManager.performHotRestart();
      // The isolate starts out paused on a hot restart so we have to resume
      // it manually to make the test pass.

      await serviceManager.service
          .resume(serviceManager.isolateManager.selectedIsolate.id);

      // First UI transition is to an empty tree.
      await detailsTree.nextUiFrame;
      expect(tree.toStringDeep(), equalsIgnoringHashCodes('<empty>\n'));

      // Notice that the selection has been lost due to the hot restart.
      await detailsTree.nextUiFrame;
      expect(
        tree.toStringDeep(),
        equalsIgnoringHashCodes(
          '▼[R][root]\n'
              '  ▼[M]MyApp\n'
              '    ▼[M]MaterialApp\n'
              '      ▼[S]Scaffold\n'
              '      ├───▼[C]Center\n'
              '      │     ▼[/icons/inspector/textArea.png]Text\n'
              '      └─▼[A]AppBar\n'
              '          ▼[/icons/inspector/textArea.png]Text\n',
        ),
      );

      // Verify that the selection can actually be changed after a restart.
      simulateRowClick(tree, rowIndex: 4);
      expect(
        tree.toStringDeep(),
        equalsIgnoringHashCodes(
          '▼[R][root]\n'
              '  ▼[M]MyApp\n'
              '    ▼[M]MaterialApp\n'
              '      ▼[S]Scaffold\n'
              '      ├───▼[C]Center <-- selected\n'
              '      │     ▼[/icons/inspector/textArea.png]Text\n'
              '      └─▼[A]AppBar\n'
              '          ▼[/icons/inspector/textArea.png]Text\n',
        ),
      );
      await env.tearDownEnvironment();
    });
*/
  });
}