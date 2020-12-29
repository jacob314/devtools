// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:devtools_app/src/inspector/inspector_tree.dart';
import 'package:devtools_app/src/inspector/inspector_controller.dart';
import 'package:devtools_app/src/ui/icons.dart';

const double fakeRowWidth = 200.0;

class FakeInspectorTree extends InspectorTreeController {
  FakeInspectorTree(InspectorSettingsController inspectorSettingsController)
      : super(inspectorSettingsController);

  final List<Rect> scrollToRequests = [];

  @override
  InspectorTreeNode createNode() {
    return InspectorTreeNode();
  }

  Completer<void> setStateCalled;

  /// Hack to allow tests to wait until the next time this UI is updated.
  Future<void> get nextUiFrame {
    setStateCalled ??= Completer();

    return setStateCalled.future;
  }

  @override
  void setState(VoidCallback fn) {
    // Execute async calls synchronously for faster test execution.
    fn();

    setStateCalled?.complete(null);
    setStateCalled = null;
  }

  // Debugging string to make it easy to write integration tests.
  String toStringDeep(
      {bool hidePropertyLines = false,
      bool includeTextStyles = false,
      bool showAnimation = false}) {
    if (root == null) return '<empty>\n';
    // Visualize the ticks computed for this node so that bugs in the tick
    // computation code will result in rendering artifacts in the text output.
    final StringBuffer sb = StringBuffer();

    for (var animatedRow in animatedRows) {
      if (!showAnimation && animatedRow.current == null) {
        continue;
      }
      if (hidePropertyLines &&
          animatedRow?.node?.diagnostic?.isProperty == true) {
        continue;
      }
      final row = animatedRow.targetRow;
      sb.write('  ' * row.depth);
      final InspectorTreeNode node = row?.node;
      final diagnostic = node?.diagnostic;
      if (diagnostic == null) {
        sb.write('<empty>\n');
        continue;
      }

      if (node.showExpandCollapse) {
        if (node.isExpanded) {
          sb.write('▼');
        } else {
          sb.write('▶');
        }
      }

      final icon = node.diagnostic.icon;
      if (icon is CustomIcon) {
        sb.write('[${icon.text}]');
      } else if (icon is ColorIcon) {
        sb.write('[${icon.color.value}]');
      } else if (icon is Image) {
        sb.write('[${(icon.image as AssetImage).assetName}]');
      }
      if (node.diagnostic.isProperty) {
        sb.write('${node.diagnostic.name}: ');
      }
      sb.write(node.diagnostic.description);

//      // TODO(jacobr): optionally visualize colors as well.
//      if (entry.text != null) {
//        if (entry.textStyle != null && includeTextStyles) {
//          final String shortStyle = styles.debugStyleNames[entry.textStyle];
//          if (shortStyle == null) {
//            // Display the style a little like an html style.
//            sb.write('<style ${entry.textStyle}>${entry.text}</style>');
//          } else {
//            if (shortStyle == '') {
//              // Omit the default text style completely for readability of
//              // the debug output.
//              sb.write(entry.text);
//            } else {
//              sb.write('<$shortStyle>${entry.text}</$shortStyle>');
//            }
//          }
//        } else {
//          sb.write(entry.text);
//        }
//      }

      if (row.isSelected) {
        sb.write(' <-- selected');
      }
      if (showAnimation) {
        if (animatedRow.animateRow) {
          if (animatedRow.current == null) {
            sb.write(' (animate out)');
          } else if (animatedRow.last == null) {
            sb.write(' (animate in)');
          } else {
            sb.write(' (changing');
            if (animatedRow.current.node != animatedRow.last.node) {
              sb.write(' node');
            }
            if (animatedRow.current.depth != animatedRow.last.depth) {
              sb.write(
                  ' depth from ${animatedRow.last.depth} to ${animatedRow.current.depth}');
            }
            sb.write(')');
          }

          if (animatedRow.snapAnimationToEnd) {
            sb.write(' snapAnimationToEnd');
          }
        }
      }
      sb.write('\n');
    }
    return sb.toString();
  }

  @override
  void animateToTargets(List<InspectorTreeNode> targets) {
    // No need to support.
  }
}
