// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:devtools_app/src/inspector/diagnostics_node.dart';
import 'package:devtools_app/src/inspector/inspector_controller.dart';
import 'package:devtools_app/src/inspector/inspector_service.dart';
import 'package:devtools_app/src/inspector/inspector_tree.dart';
import 'package:devtools_app/src/inspector/inspector_tree_flutter.dart';
import 'package:devtools_testing/support/fake_inspector_tree.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inspector_tree_json.dart';
import 'support/wrappers.dart';

class TestClient implements InspectorControllerClient {
  @override
  void onChanged() {
    // TODO: implement onChanged
  }

  @override
  void requestFocus() {
    // TODO: implement requestFocus
  }

  @override
  void animateToTargets(List<InspectorTreeNode> targets) {
    // TODO: implement animateToTargets
  }
}

void main() {
  group('inspector tree animation', () {
    testWidgets('expand collapse', (WidgetTester tester) async {
      final node =
          RemoteDiagnosticsNode(jsonDecode(summaryTreeJson), null, false, null);
      final inspectorSettingsController = InspectorSettingsController();
      final inspectorTree = FakeInspectorTree(
          inspectorSettingsController); // InspectorTreeControllerFlutter();

      inspectorTree.config = InspectorTreeConfig(
        treeType: FlutterTreeType.widget,
        summaryTree: true,
        onNodeAdded: (_, __) {},
      );
      final InspectorTreeNode rootNode = inspectorTree.setupInspectorTreeNode(
        inspectorTree.createNode(),
        node,
        expandChildren: true,
        expandProperties: false,
      );
      inspectorTree.root = rootNode;
      inspectorTree.animatedRows;

      expect(
        inspectorTree.toStringDeep(),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold\n'
          '        ▼[C]Center\n'
          '          [T]Text\n'
          '        ▼[A]AppBar\n'
          '          [T]Text\n',
        ),
      );

      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[R][root] (animate in)\n'
          '  ▼[M]MyApp (animate in)\n'
          '    ▼[M]MaterialApp (animate in)\n'
          '      ▼[S]Scaffold (animate in)\n'
          '        ▼[C]Center (animate in)\n'
          '          [T]Text (animate in)\n'
          '        ▼[A]AppBar (animate in)\n'
          '          [T]Text (animate in)\n',
        ),
      );
      inspectorTree.animationDone();
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold\n'
          '        ▼[C]Center\n'
          '          [T]Text\n'
          '        ▼[A]AppBar\n'
          '          [T]Text\n',
        ),
      );

      inspectorTree.animatedRows[3].node.isExpanded = false;
      expect(
        inspectorTree.toStringDeep(),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▶[S]Scaffold\n',
        ),
      );
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▶[S]Scaffold\n'
          '        ▼[C]Center (animate out)\n'
          '          [T]Text (animate out)\n'
          '        ▼[A]AppBar (animate out)\n'
          '          [T]Text (animate out)\n'
          '',
        ),
      );
      inspectorTree.animationDone();

      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▶[S]Scaffold\n',
        ),
      );
      inspectorTree.animatedRows[3].node.isExpanded = true;
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold\n'
          '        ▼[C]Center (animate in)\n'
          '          [T]Text (animate in)\n'
          '        ▼[A]AppBar (animate in)\n'
          '          [T]Text (animate in)\n',
        ),
      );

      inspectorTree.animationDone();
      inspectorTree.animatedRows[4].node.isExpanded = false;
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold\n'
          '        ▶[C]Center\n'
          '          [T]Text (animate out)\n'
          '        ▼[A]AppBar\n'
          '          [T]Text\n',
        ),
      );

      inspectorTree.animationDone();
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold\n'
          '        ▶[C]Center\n'
          '        ▼[A]AppBar\n'
          '          [T]Text\n',
        ),
      );

      inspectorTree.animatedRows[4].node.isExpanded = true;
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold\n'
          '        ▼[C]Center\n'
          '          [T]Text (animate in)\n'
          '        ▼[A]AppBar\n'
          '          [T]Text\n',
        ),
      );
    });

    testWidgets('optimize', (WidgetTester tester) async {
      final node =
          RemoteDiagnosticsNode(jsonDecode(summaryTreeJson), null, false, null);
      final inspectorTree = FakeInspectorTree(
          InspectorSettingsController()); // InspectorTreeControllerFlutter();

      inspectorTree.config = InspectorTreeConfig(
        treeType: FlutterTreeType.widget,
        summaryTree: true,
        onNodeAdded: (_, __) {},
      );
      final InspectorTreeNode rootNode = inspectorTree.setupInspectorTreeNode(
        inspectorTree.createNode(),
        node,
        expandChildren: true,
        expandProperties: false,
      );
      inspectorTree.root = rootNode;

      expect(
        inspectorTree.toStringDeep(),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold\n'
          '        ▼[C]Center\n'
          '          [T]Text\n'
          '        ▼[A]AppBar\n'
          '          [T]Text\n',
        ),
      );

      inspectorTree.animationDone();
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold\n'
          '        ▼[C]Center\n'
          '          [T]Text\n'
          '        ▼[A]AppBar\n'
          '          [T]Text\n',
        ),
      );

      inspectorTree.animatedRows[3].node.isExpanded = false;
      final animatedRows = inspectorTree.animatedRows;
      expect(
        inspectorTree.toStringDeep(),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▶[S]Scaffold\n',
        ),
      );
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▶[S]Scaffold\n'
          '        ▼[C]Center (animate out)\n'
          '          [T]Text (animate out)\n'
          '        ▼[A]AppBar (animate out)\n'
          '          [T]Text (animate out)\n',
        ),
      );
      inspectorTree.optimizeRowAnimation(
        rowsToAnimateOut: {animatedRows[4], animatedRows[5]},
        currentVisibleRange:
            VisibleRange(animatedRows[0].node, animatedRows[3].node),
      );
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▶[S]Scaffold\n'
          '        ▼[C]Center (animate out)\n'
          '          [T]Text (animate out)\n',
        ),
      );
      // Verify that animate row out animations still occur even if the
      // animated out rows aren't visible when the animation ends.
      inspectorTree.optimizeRowAnimation(
        rowsToAnimateOut: {animatedRows[4], animatedRows[5]},
        currentVisibleRange:
            VisibleRange(animatedRows[0].node, animatedRows[1].node),
      );
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▶[S]Scaffold\n'
          '        ▼[C]Center (animate out)\n'
          '          [T]Text (animate out)\n',
        ),
      );

      inspectorTree.animationDone();
      inspectorTree.animatedRows[3].node.isExpanded = true;
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold\n'
          '        ▼[C]Center (animate in)\n'
          '          [T]Text (animate in)\n'
          '        ▼[A]AppBar (animate in)\n'
          '          [T]Text (animate in)\n',
        ),
      );

      inspectorTree.optimizeRowAnimation(
        rowsToAnimateOut: {}..addAll(animatedRows.sublist(0, 4)),
        currentVisibleRange:
            VisibleRange(animatedRows[0].node, animatedRows[5].node),
      );
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold\n'
          '        ▼[C]Center (animate in)\n'
          '          [T]Text (animate in)\n',
          // AppBar and Text widgets are not included as they are not visible
          // at the end of the animation.
        ),
      );

      inspectorTree.animationDone();
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold\n'
          '        ▼[C]Center\n'
          '          [T]Text\n'
          '        ▼[A]AppBar\n'
          '          [T]Text\n',
        ),
      );

      inspectorTree.animatedRows.first.node.isExpanded = false;
      inspectorTree.animationDone();
      inspectorTree.animatedRows.first.node.isExpanded = true;
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp (animate in)\n'
          '    ▼[M]MaterialApp (animate in)\n'
          '      ▼[S]Scaffold (animate in)\n'
          '        ▼[C]Center (animate in)\n'
          '          [T]Text (animate in)\n'
          '        ▼[A]AppBar (animate in)\n'
          '          [T]Text (animate in)\n',
        ),
      );
      inspectorTree.optimizeRowAnimation(
        rowsToAnimateOut: {animatedRows[0], animatedRows[1]},
        currentVisibleRange:
            VisibleRange(animatedRows[0].node, animatedRows[5].node),
      );
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp (animate in)\n'
          '    ▼[M]MaterialApp (animate in)\n'
          '      ▼[S]Scaffold (animate in)\n'
          '        ▼[C]Center (animate in)\n'
          '          [T]Text (animate in)\n',
        ),
      );
    });

    testWidgets('details tree navigate to parent', (WidgetTester tester) async {
      // The details tree contains properties so puts additional pressure
      final childRoot = RemoteDiagnosticsNode(
          jsonDecode(detailsTreeChild), null, false, null);
      final parentRoot = RemoteDiagnosticsNode(
          jsonDecode(detailsTreeParent), null, false, null);
      final inspectorTree = FakeInspectorTree(
        InspectorSettingsController(),
      ); // InspectorTreeControllerFlutter();

      inspectorTree.config = InspectorTreeConfig(
        treeType: FlutterTreeType.widget,
        summaryTree: true,
        onNodeAdded: (_, __) {},
      );
      final InspectorTreeNode rootNode = inspectorTree.setupInspectorTreeNode(
        inspectorTree.createNode(),
        childRoot,
        expandChildren: true,
        expandProperties: false,
      );
      inspectorTree.root = rootNode;
      inspectorTree.animatedRows;

      inspectorTree.animationDone();
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[A]AnimatedBuilder\n'
          '  animation: AnimationController#26551(⏮ 0.000; paused)\n'
          '  dependencies: [_LocalizationsScope-[GlobalKey#8de0c], PageStatus, _ModelBindingScope, _InheritedTheme, MediaQuery]\n'
          '  state: _AnimatedState#dec96\n'
          '  ▼[E]ExcludeSemantics\n'
          '    excluding: false\n'
          '    ▶renderObject: RenderExcludeSemantics#b8f11 relayoutBoundary=up9\n'
          '    ▶[C]Center\n',
        ),
      );
      // Verify that the parent node animates in nicely for this tricky case
      // with multiple nested nodes with the same names and similar properties.
      inspectorTree.root = inspectorTree.setupInspectorTreeNode(
        inspectorTree.createNode(),
        parentRoot,
        expandChildren: true,
        expandProperties: false,
      );
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[A]AnimatedBuilder (animate in)\n'
          '  animation: AnimationController#b7d8d(⏮ 0.000; paused) (animate in)\n'
          '  dependencies: [PageStatus] (animate in)\n'
          '  state: _AnimatedState#8b9de (animate in)\n'
          '  ▼[A]AnimatedBuilder (changing node depth from 0 to 1)\n'
          '    animation: AnimationController#26551(⏮ 0.000; paused) (changing node depth from 1 to 2)\n'
          '    dependencies: [_LocalizationsScope-[GlobalKey#8de0c], PageStatus, _ModelBindingScope, _InheritedTheme, MediaQuery] (changing node depth from 1 to 2)\n'
          '    state: _AnimatedState#dec96 (changing node depth from 1 to 2)\n'
          '    ▶[E]ExcludeSemantics (changing node depth from 1 to 2)\n'
          '    excluding: false (animate out)\n'
          '    ▶renderObject: RenderExcludeSemantics#b8f11 relayoutBoundary=up9 (animate out)\n'
          '    ▶[C]Center (animate out)\n',
        ),
      );
      // New tree with different by identical diagnostics nodes.
      inspectorTree.root = inspectorTree.setupInspectorTreeNode(
        inspectorTree.createNode(),
        childRoot,
        expandChildren: true,
        expandProperties: false,
      );
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[A]AnimatedBuilder (animate out)\n'
          '  animation: AnimationController#b7d8d(⏮ 0.000; paused) (animate out)\n'
          '  dependencies: [PageStatus] (animate out)\n'
          '  state: _AnimatedState#8b9de (animate out)\n'
          '▼[A]AnimatedBuilder (changing node depth from 1 to 0)\n'
          '  animation: AnimationController#26551(⏮ 0.000; paused) (changing node depth from 2 to 1)\n'
          '  dependencies: [_LocalizationsScope-[GlobalKey#8de0c], PageStatus, _ModelBindingScope, _InheritedTheme, MediaQuery] (changing node depth from 2 to 1)\n'
          '  state: _AnimatedState#dec96 (changing node depth from 2 to 1)\n'
          '  ▼[E]ExcludeSemantics (changing node depth from 2 to 1)\n'
          '    excluding: false (animate in)\n'
          '    ▶renderObject: RenderExcludeSemantics#b8f11 relayoutBoundary=up9 (animate in)\n'
          '    ▶[C]Center (animate in)\n',
        ),
      );
    });

    testWidgets('change tree', (WidgetTester tester) async {
      final root =
          RemoteDiagnosticsNode(jsonDecode(summaryTreeJson), null, false, null);
      final inspectorSettingsController = InspectorSettingsController();
      final inspectorTree = FakeInspectorTree(
          inspectorSettingsController); // InspectorTreeControllerFlutter();

      inspectorTree.config = InspectorTreeConfig(
        treeType: FlutterTreeType.widget,
        summaryTree: true,
        onNodeAdded: (_, __) {},
      );
      final InspectorTreeNode rootNode = inspectorTree.setupInspectorTreeNode(
        inspectorTree.createNode(),
        root,
        expandChildren: true,
        expandProperties: false,
      );
      inspectorTree.root = rootNode;
      inspectorTree.animatedRows;

      inspectorTree.animationDone();
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[R][root]\n'
          '  ▼[M]MyApp\n'
          '    ▼[M]MaterialApp\n'
          '      ▼[S]Scaffold\n'
          '        ▼[C]Center\n'
          '          [T]Text\n'
          '        ▼[A]AppBar\n'
          '          [T]Text\n',
        ),
      );
      // New tree with identical diagnostics nodes.
      inspectorTree.root = inspectorTree.setupInspectorTreeNode(
        inspectorTree.createNode(),
        root,
        expandChildren: true,
        expandProperties: false,
      );
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[R][root] (changing node)\n'
          '  ▼[M]MyApp (changing node)\n'
          '    ▼[M]MaterialApp (changing node)\n'
          '      ▼[S]Scaffold (changing node)\n'
          '        ▼[C]Center (changing node)\n'
          '          [T]Text (changing node)\n'
          '        ▼[A]AppBar (changing node)\n'
          '          [T]Text (changing node)\n',
        ),
      );
      // New tree with different by identical diagnostics nodes.
      inspectorTree.root = inspectorTree.setupInspectorTreeNode(
        inspectorTree.createNode(),
        root,
        expandChildren: true,
        expandProperties: false,
      );
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[R][root] (changing node)\n'
          '  ▼[M]MyApp (changing node)\n'
          '    ▼[M]MaterialApp (changing node)\n'
          '      ▼[S]Scaffold (changing node)\n'
          '        ▼[C]Center (changing node)\n'
          '          [T]Text (changing node)\n'
          '        ▼[A]AppBar (changing node)\n'
          '          [T]Text (changing node)\n',
        ),
      );
    });

    testWidgets('details tree re-route regression test',
        (WidgetTester tester) async {
      // This is an example where bugs in the animation library could result in
      // a switch between the unrelated trees routed on a Container widget
      // and a center widget resulting in rendering
      final containerTree = RemoteDiagnosticsNode(
          jsonDecode(containerWidgetDetailsTreeJson), null, false, null);
      final centerTree = RemoteDiagnosticsNode(
          jsonDecode(centerWidgetDetailsTreeJson), null, false, null);
      final inspectorSettingsController = InspectorSettingsController();
      final inspectorTree = FakeInspectorTree(inspectorSettingsController);

      inspectorTree.config = InspectorTreeConfig(
        treeType: FlutterTreeType.widget,
        summaryTree: true,
        onNodeAdded: (_, __) {},
      );
      final InspectorTreeNode rootNode = inspectorTree.setupInspectorTreeNode(
        inspectorTree.createNode(),
        containerTree,
        expandChildren: true,
        expandProperties: false,
      );
      inspectorTree.root = rootNode;
      inspectorTree.animatedRows;

      inspectorTree.animationDone();
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[C]Container\n'
          '  alignment: null\n'
          '  padding: null\n'
          '  clipBehavior: Clip.none\n'
          '  bg: null\n'
          '  fg: null\n'
          '  constraints: BoxConstraints(w=375.0, h=216.0)\n'
          '  margin: null\n'
          '  ▼[C]ConstrainedBox\n'
          '    constraints: BoxConstraints(w=375.0, h=216.0)\n'
          '    ▶renderObject: RenderConstrainedBox#c0a18 relayoutBoundary=up7\n'
          '    ▶[P]PageView-[<\'studyDemoList\'>]\n',
        ),
      );
      // Switch to the center tree. If there is a layout bug we will add
      // excess vertical padding above the top of the center tree when the
      // animation completes.
      inspectorTree.root = inspectorTree.setupInspectorTreeNode(
        inspectorTree.createNode(),
        centerTree,
        expandChildren: true,
        expandProperties: false,
      );
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[C]Container (animate out)\n'
          '  alignment: null (animate out)\n'
          '  padding: null (animate out)\n'
          '  clipBehavior: Clip.none (animate out)\n'
          '  bg: null (animate out)\n'
          '  fg: null (animate out)\n'
          '  constraints: BoxConstraints(w=375.0, h=216.0) (animate out)\n'
          '  margin: null (animate out)\n'
          '  ▼[C]ConstrainedBox (animate out)\n'
          '    constraints: BoxConstraints(w=375.0, h=216.0) (animate out)\n'
          '    ▶renderObject: RenderConstrainedBox#c0a18 relayoutBoundary=up7 (animate out)\n'
          '    ▶[P]PageView-[<\'studyDemoList\'>] (animate out)\n'
          '▼[C]Center (animate in)\n'
          '  alignment: center (animate in)\n'
          '  widthFactor: null (animate in)\n'
          '  heightFactor: null (animate in)\n'
          '  dependencies: [Directionality] (animate in)\n'
          '  ▶renderObject: RenderPositionedBox#1f77b (animate in)\n'
          '  ▼[T]Transform (animate in)\n'
          '    dependencies: [Directionality] (animate in)\n'
          '    ▶renderObject: RenderTransform#008a4 relayoutBoundary=up1 (animate in)\n'
          '    ▶[C]_CarouselCard (animate in)\n',
        ),
      );
      // Navigate back to the container tree for completeness.
      inspectorTree.root = inspectorTree.setupInspectorTreeNode(
        inspectorTree.createNode(),
        containerTree,
        expandChildren: true,
        expandProperties: false,
      );
      expect(
        inspectorTree.toStringDeep(showAnimation: true),
        equals(
          '▼[C]Center (animate out)\n'
          '  alignment: center (animate out)\n'
          '  widthFactor: null (animate out)\n'
          '  heightFactor: null (animate out)\n'
          '  dependencies: [Directionality] (animate out)\n'
          '  ▶renderObject: RenderPositionedBox#1f77b (animate out)\n'
          '  ▼[T]Transform (animate out)\n'
          '    dependencies: [Directionality] (animate out)\n'
          '    ▶renderObject: RenderTransform#008a4 relayoutBoundary=up1 (animate out)\n'
          '    ▶[C]_CarouselCard (animate out)\n'
          '▼[C]Container (animate in)\n'
          '  alignment: null (animate in)\n'
          '  padding: null (animate in)\n'
          '  clipBehavior: Clip.none (animate in)\n'
          '  bg: null (animate in)\n'
          '  fg: null (animate in)\n'
          '  constraints: BoxConstraints(w=375.0, h=216.0) (animate in)\n'
          '  margin: null (animate in)\n'
          '  ▼[C]ConstrainedBox (animate in)\n'
          '    constraints: BoxConstraints(w=375.0, h=216.0) (animate in)\n'
          '    ▶renderObject: RenderConstrainedBox#c0a18 relayoutBoundary=up7 (animate in)\n'
          '    ▶[P]PageView-[<\'studyDemoList\'>] (animate in)\n',
        ),
      );
    });

    testWidgets('summary tree golden test', (WidgetTester tester) async {
      // This is an example where bugs in the animation library could result in
      // a switch between the unrelated trees routed on a Container widget
      // and a center widget resulting in rendering
      final summaryTree =
          RemoteDiagnosticsNode(jsonDecode(summaryTreeJson), null, false, null);
      final controller =
          InspectorTreeControllerFlutter(InspectorSettingsController())
            ..config = InspectorTreeConfig(
              treeType: FlutterTreeType.widget,
              summaryTree: true,
              onNodeAdded: (_, __) {},
            );

      controller.root = controller.setupInspectorTreeNode(
        controller.createNode(),
        summaryTree,
        expandChildren: true,
        expandProperties: false,
      );
      await pumpInspectorTree(tester, controller);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await expectLater(
        find.byType(InspectorTree),
        matchesGoldenFile('goldens/summary_tree.png'),
      );
    });

    testWidgets('details tree re-route regression test',
        (WidgetTester tester) async {
      // This is an example where bugs in the animation library could result in
      // a switch between the unrelated trees routed on a Container widget
      // and a center widget resulting in rendering
      final containerTree = RemoteDiagnosticsNode(
          jsonDecode(containerWidgetDetailsTreeJson), null, false, null);
      final centerTree = RemoteDiagnosticsNode(
          jsonDecode(centerWidgetDetailsTreeJson), null, false, null);
      final controller =
          InspectorTreeControllerFlutter(InspectorSettingsController())
            ..config = InspectorTreeConfig(
              treeType: FlutterTreeType.widget,
              summaryTree: false,
              onNodeAdded: (_, __) {},
            );

      controller.root = controller.setupInspectorTreeNode(
        controller.createNode(),
        containerTree,
        expandChildren: true,
        expandProperties: false,
      );
      await pumpInspectorTree(tester, controller);
      await expectLater(
        find.byType(InspectorTree),
        matchesGoldenFile('goldens/details_tree_container_first_frame.png'),
      );

      await tester.pumpAndSettle(const Duration(seconds: 1));
      await expectLater(
        find.byType(InspectorTree),
        matchesGoldenFile('goldens/details_tree_container.png'),
      );

      // Switch to the center tree. If there is a layout bug we will add
      // excess vertical padding above the top of the center tree when the
      // animation completes.
      controller.root = controller.setupInspectorTreeNode(
        controller.createNode(),
        centerTree,
        expandChildren: true,
        expandProperties: false,
      );
      await tester.pumpAndSettle(const Duration(seconds: 10));
      final InspectorTreeState state =
          tester.firstState(find.byType(InspectorTree));

      expect(state.topSpacer.end, equals(0.0));
      await expectLater(
        find.byType(InspectorTree),
        matchesGoldenFile('goldens/details_tree_center.png'),
      );
    });
  });
}

Future<void> pumpInspectorTree(
    WidgetTester tester, InspectorTreeControllerFlutter controller) {
  return tester.pumpWidget(
    wrapWithControllers(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: InspectorTree(controller: controller)),
        ],
      ),
    ),
  );
}
