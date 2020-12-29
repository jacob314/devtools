// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pedantic/pedantic.dart';

import '../auto_dispose_mixin.dart';
import '../collapsible_mixin.dart';
import '../common_widgets.dart';
import '../extent_delegate_list.dart';
import '../theme.dart';
import '../ui/colors.dart';
import '../utils.dart';
import 'diagnostics.dart';
import 'diagnostics_node.dart';
import 'inspector_controller.dart';
import 'inspector_service.dart';
import 'inspector_tree.dart';
import 'inspector_tree_oracle.dart';

// TODO(jacobr): consider making this a fraction of the tree width although
// that would introduce complexity on resize.
/// Target amount of white space to the left of a node when scrolling to it.
const double targetXOffset = 80.0;

/// Extent delegate tracking a list of
class RowExtentDelegate extends FixedExtentDelegateBase {
  RowExtentDelegate({
    @required this.visibilityCurve,
  });

  @override
  int computeLength() {
    return _rows.length + 2;
  }

  @override
  double computeExtent(int index) {
    if (index == 0) {
      final topSpace = _topSpacer.evaluate(visibilityCurve);
      assert(topSpace >= 0.0);
      return topSpace;
    }
    if (index == _rows.length + 1) {
      final bottomAnimationValue = _bottomSpacer.evaluate(visibilityCurve);
      assert(bottomAnimationValue >= 0.0);
      return bottomAnimationValue;
    }
    return _rows[index - 1].animatedRowHeight(visibilityCurve);
  }

  void configure({
    @required List<AnimatedRow> rows,
    @required Tween<double> topSpacer,
    @required Tween<double> bottomSpacer,
  }) {
    assert(topSpacer != null && bottomSpacer != null);
    _rows = rows ?? const [];
    _topSpacer = topSpacer;
    _bottomSpacer = bottomSpacer;
    recompute();
  }

  List<AnimatedRow> get rows => _rows;
  List<AnimatedRow> _rows = const [];

  /// Index of the row in [rows].
  int rowIndex(InspectorTreeRow row) {
    final index = row.filteredAnimatedIndex;
    assert(_rows[index].current == row);
    return index;
  }

  final Animation<double> visibilityCurve;
  // Animated spacer before any rows.
  Tween<double> _topSpacer = Tween(begin: 0, end: 0);
  // Animated spacer after all rows.
  Tween<double> _bottomSpacer = Tween(begin: 0, end: 0);
}

/// Presents a [TreeNode].
class _InspectorTreeRowWidget extends StatefulWidget {
  /// Constructs a [_InspectorTreeRowWidget] that presents a line in the
  /// Inspector tree.
  const _InspectorTreeRowWidget({
    @required Key key,
    @required this.row,
    @required this.inspectorTreeState,
  }) : super(key: key);

  final InspectorTreeState inspectorTreeState;

  InspectorTreeNode get node => row.node;
  final InspectorTreeRow row;

  @override
  _InspectorTreeRowState createState() => _InspectorTreeRowState();
}

class _InspectorTreeRowState extends State<_InspectorTreeRowWidget>
    with TickerProviderStateMixin, CollapsibleAnimationMixin {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: rowHeight,
      child: InspectorRowContent(
        row: widget.row,
        expandArrowAnimation: expandArrowAnimation,
        controller: widget.inspectorTreeState.controller,
        onToggle: () {
          setExpanded(!isExpanded);
        },
      ),
    );
  }

  @override
  bool get isExpanded => widget.node.isExpanded;

  @override
  void onExpandChanged(bool expanded) {
    setState(() {
      final row = widget.row;
      if (expanded) {
        widget.inspectorTreeState.controller.onExpandRow(row);
      } else {
        widget.inspectorTreeState.controller.onCollapseRow(row);
      }
    });
  }

  @override
  bool shouldShow() => widget.node.shouldShow;
}

/// Presents a [TreeNode].
class _AnimatedInspectorTreeRowWidget extends StatefulWidget {
  /// Constructs a [_InspectorTreeRowWidget] that presents a line in the
  /// Inspector tree.
  const _AnimatedInspectorTreeRowWidget({
    @required Key key,
    @required this.row,
    @required this.inspectorTreeState,
    @required this.visibilityCurve,
  }) : super(key: key);

  final InspectorTreeState inspectorTreeState;
  final Animation<double> visibilityCurve;

  InspectorTreeNode get node => row.node;
  final AnimatedRow row;

  @override
  _AnimatedInspectorTreeRowState createState() =>
      _AnimatedInspectorTreeRowState();
}

class _AnimatedInspectorTreeRowState
    extends State<_AnimatedInspectorTreeRowWidget>
    with TickerProviderStateMixin, CollapsibleAnimationMixin {
  @override
  Widget build(BuildContext context) {
    return AnimatedInspectorRowContent(
      row: widget.row,
      expandArrowAnimation: expandArrowAnimation,
      controller: widget.inspectorTreeState.controller,
      visibilityAnimation: widget.visibilityCurve,
      onToggle: () {
        setExpanded(!isExpanded);
      },
    );
  }

  @override
  bool get isExpanded => widget.node.isExpanded;

  @override
  void onExpandChanged(bool expanded) {
    setState(() {
      final row = widget.row;
      if (row.current == null) {
        // Don't allow manipulating rows that are animating out.
        return;
      }
      if (expanded) {
        widget.inspectorTreeState.controller.onExpandRow(row.current);
      } else {
        widget.inspectorTreeState.controller.onCollapseRow(row.current);
      }
    });
  }

  @override
  bool shouldShow() => widget.node.shouldShow;
}

class InspectorTreeControllerFlutter extends InspectorTreeController {
  InspectorTreeControllerFlutter(
      InspectorSettingsController inspectorSettingsController)
      : super(inspectorSettingsController);

  /// Client the controller notifies to trigger changes to the UI.
  InspectorControllerClient get client => _client;
  InspectorControllerClient _client;

  set client(InspectorControllerClient value) {
    if (_client == value) return;
    // Do not set a new client if there is still an old client.
    assert(value == null || _client == null);
    _client = value;

    if (config.onClientActiveChange != null) {
      config.onClientActiveChange(value != null);
    }
  }

  @override
  InspectorTreeNode createNode() => InspectorTreeNode();

  @override
  void animateToTargets(List<InspectorTreeNode> targets) {
    client.animateToTargets(targets);
  }

  @override
  void setState(VoidCallback fn) {
    fn();
    client?.onChanged();
  }

  // TODO(jacobr): this should be adjusted somewhat based on the window size
  // so that we scale to narrower and wider windows.
  /// Width each row in the tree should have ignoring its indent.
  ///
  /// Content in rows should wrap if it exceeds this width.
  final double rowWidth = 1200;

  void requestFocus() {
    client?.requestFocus();
  }
}

abstract class InspectorControllerClient {
  void onChanged();

  void animateToTargets(List<InspectorTreeNode> targets);

  void requestFocus();
}

class NodeYPair {
  const NodeYPair(this.node, this.y);

  final InspectorTreeNode node;
  final double y;
}

class InspectorTree extends StatefulWidget {
  const InspectorTree({
    Key key,
    @required this.controller,
    this.isSummaryTree = false,
  }) : super(key: key);

  final InspectorTreeControllerFlutter controller;
  final bool isSummaryTree;

  @override
  State<InspectorTree> createState() => InspectorTreeState();
}

/// ScrollController that smoothly adjusts to changing the scroll target.
///
/// Wrapper around ScrollController that handles interupting the current scroll
/// operation to perform a new scroll operation better.
class AnimatedScrollController {
  final ScrollController controller = ScrollController();

  ScrollPosition get position {
    return controller.position;
  }

  double get offset {
    if (!controller.hasClients) return 0.0;
    return controller.offset;
  }

  Future<void> animateTo(
    double offset, {
    Duration duration,
    Curve curve,
    bool navigation = false,
  }) {
    start = controller.offset;
    target = offset;
    this.duration = duration;
    this.curve = curve;
    if (navigation || !isAnimateToInProgress) {
      this.navigation = navigation;
    }
    if (navigation) {
      navigationTarget = offset;
    }
    return controller.animateTo(offset, duration: duration, curve: curve);
  }

  void jumpTo(double offset) {
    return controller.jumpTo(offset);
  }

  bool get isAnimateToInProgress {
    if (!controller.hasClients) return false;
    final position = controller.position;
    if (position.isScrollingNotifier.value == false) {
      // Already at the end.
      return false;
    }
    // TODO(jacobr): find a way to test this that doesn't require using a
    // protected member.
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    return position.activity is DrivenScrollActivity;
  }

  void jumpToAnimationEnd() {
    if (!isAnimateToInProgress) return;
    controller.jumpTo(target);
  }

  double get offsetAfterNavigation {
    if (isAnimateToInProgress && navigation) {
      return navigationTarget;
    } else {
      return offset;
    }
  }

  double start;
  double target;
  Duration duration;
  Curve curve;
  bool navigation = false;
  double navigationTarget;

  void dispose() {
    controller.dispose();
  }
}

// AutomaticKeepAlive is necessary so that the tree does not get recreated when we switch tabs.
class InspectorTreeState extends State<InspectorTree>
    with
        SingleTickerProviderStateMixin,
        AutomaticKeepAliveClientMixin<InspectorTree>,
        AutoDisposeMixin
    implements InspectorControllerClient {
  InspectorTreeControllerFlutter get controller => widget.controller;

  bool get isSummaryTree => widget.isSummaryTree;

  AnimatedScrollController _scrollControllerY;
  AnimatedScrollController _scrollControllerX;
  List<InspectorTreeNode> _scrollToTargets;
  Future<void> currentAnimateY;

  FocusNode _focusNode;
  AnimationController visibilityController;

  /// A curved animation that matches [expandController], moving from 0.0 to 1.0
  /// Useful for animating the size of a child that is appearing.
  Animation<double> visibilityCurve;
  RowExtentDelegate extentDelegate;
  RowExtentDelegate animationDoneExtentDelegate;

  @override
  void initState() {
    super.initState();
    _scrollControllerX = AnimatedScrollController();
    _scrollControllerY = AnimatedScrollController();
    // TODO(devoncarew): Commented out as per flutter/devtools/pull/2001.
    //_scrollControllerY.addListener(_onScrollYChange);
    _focusNode = FocusNode();
    visibilityController = longAnimationController(this);
    visibilityCurve = visibilityController.view;
    visibilityController.addStatusListener((status) {
      if (AnimationStatus.completed ==
              status // || AnimationStatus.dismissed == status
          ) {
        controller.animationDone();
        // nudge offset and switch to non-animating view.
      }
    });
    extentDelegate = RowExtentDelegate(
      visibilityCurve: visibilityCurve,
    );
    animationDoneExtentDelegate = RowExtentDelegate(
      visibilityCurve: const AlwaysStoppedAnimation(1.0),
    );

    visibilityController.addListener(extentDelegate.recompute);
    _bindToController();
  }

  @override
  void didUpdateWidget(InspectorTree oldWidget) {
    if (oldWidget.controller != widget.controller) {
      final oldController = oldWidget.controller;
      oldController?.client = null;
      cancel();

      _bindToController();
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    super.dispose();
    controller?.client = null;
    _scrollControllerX.dispose();
    _scrollControllerY.dispose();
    _focusNode.dispose();
    visibilityController?.dispose();
  }

  @override
  void requestFocus() {
    _focusNode.requestFocus();
  }

  // TODO(devoncarew): Commented out as per flutter/devtools/pull/2001.
//  void _onScrollYChange() {
//    if (controller == null) return;
//
//    // If the vertical position  is already being animated we should not trigger
//    // a new animation of the horizontal position as a more direct animation of
//    // the horizontal position has already been triggered.
//    if (currentAnimateY != null) return;
//
//    final x = _computeTargetX(_scrollControllerY.offset);
//    _scrollControllerX.animateTo(
//      x,
//      duration: defaultDuration,
//      curve: defaultCurve,
//    );
//  }

  /// Animate so that the entire range minOffset to maxOffset is within view.
  static double _computeTargetOffsetY({
    @required double currentOffset,
    @required double viewportDimension,
    @required Rect rect,
    @required ExtentDelegate extentDelegate,
  }) {
    final minOffset = rect.top;
    var maxOffset = rect.bottom;
    final currentEndOffset = viewportDimension + currentOffset;

    // If the requested range is larger than what the viewport can show at once,
    // prioritize showing the start of the range.
    maxOffset = min(viewportDimension + minOffset, maxOffset);
    if (currentOffset <= minOffset && currentEndOffset >= maxOffset) {
      return currentOffset; // Nothing to do. The whole range is already in view.
    }
    if (currentOffset > minOffset) {
      // Need to scroll so the minOffset is in view.
      return minOffset;
    }

    assert(currentEndOffset < maxOffset);
    // Need to scroll so the maxOffset is in view at the very bottom of the
    // list view while ensuring we do not scroll to above the start of the
    // spacer at the top of the list view.
    return max(maxOffset - viewportDimension, extentDelegate.layoutOffset(1));
  }

  /// Compute the goal x scroll given a y scroll value.
  ///
  /// This enables animating the x scroll as the y scroll changes which helps
  /// keep the relevant content in view while scrolling a large list.
  static double _computeTargetX({
    @required double y,
    @required Size viewportDimensions,
    @required RowExtentDelegate extentDelegate,
  }) {
    final childIndex = extentDelegate.minChildIndexForScrollOffset(y);
    final rows = extentDelegate.rows;
    double requiredOffset;
    double minOffset = double.infinity;
    // TODO(jacobr): use maxOffset as well to better handle the case where the
    // previous row has a significantly larger indent.

    // TODO(jacobr): if the first or last row is only partially visible, tween
    // between its indent and the next row to more smoothly change the target x
    // as the y coordinate changes.
    if (childIndex + rowIndexOffset >= rows.length) {
      return 0;
    }
    final endY = y + viewportDimensions.height;
    for (int i = childIndex;
        i < extentDelegate.length && i < rows.length;
        i++) {
      final childY = extentDelegate.layoutOffset(i);
      if (childY >= endY) break;

      final rowIndex = i - rowIndexOffset;
      if (rowIndex >= 0 && rowIndex < rows.length) {
        final row = rows[rowIndex];
        if (row == null) continue;
        final rowOffset =
            indentForDepth(row.depth.evaluate(extentDelegate.visibilityCurve));
        if (row.isSelected) {
          requiredOffset = rowOffset;
        }
        minOffset = min(minOffset, rowOffset);
      }
    }
    minOffset = max(0, minOffset - targetXOffset);
    if (requiredOffset != null) {
      // Ensure the selected row is indented no more than half way into the
      // viewport.
      minOffset =
          max(minOffset, requiredOffset - viewportDimensions.width * 0.5);
    }

    return minOffset;
  }

  /// Handle arrow keys for the InspectorTree. Ignore other key events so that
  /// other widgets have a chance to respond to them.
  bool _handleKeyEvent(FocusNode _, RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return false;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      controller.navigateDown();
      return true;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      controller.navigateUp();
      return true;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      controller.navigateLeft();
      return true;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      controller.navigateRight();
      return true;
    }

    return false;
  }

  void _bindToController() {
    controller?.client = this;
  }

  // TODO(jacobr): use value notifier?
  List<AnimatedRow> _currentAnimatedRows;
  List<AnimatedRow> _currentRawAnimatedRows;
  Tween<double> topSpacer = Tween(begin: 0, end: 0);
  Tween<double> bottomSpacer = Tween(begin: 0, end: 0);

  @override
  void onChanged() {
    setState(() {
      // TODO(jacobr): update some state.
    });
  }

  /// Returns a bounding box for a row.
  Rect computeBoundingBox(
      InspectorTreeRow row, RowExtentDelegate extentDelegate) {
    final index = extentDelegate.rowIndex(row);
    return Rect.fromLTWH(
      indentForDepth(row.depth),
      extentDelegate.layoutOffset(index),
      controller.rowWidth,
      extentDelegate.computeExtent(index),
    );
  }

  Rect computeTargetRect({
    @required List<InspectorTreeNode> targets,
    @required TreeStructureOracle treeStructure,
    @required RowExtentDelegate extentDelegate,
  }) {
    Rect targetRect; // y coordinates in this rect are animated indexes

    for (InspectorTreeNode target in targets) {
      final row = treeStructure[target];
      if (row != null && row.inFilteredAnimation) {
        final rowRect = computeBoundingBox(row, extentDelegate);
        targetRect =
            targetRect == null ? rowRect : targetRect.expandToInclude(rowRect);
      }
    }

    return targetRect;
  }

  /// Scroll a rectangle into view.
  ///
  /// The [extentDelegate] describes how rows in the view are expected to be
  /// laid out at the time the scroll animation completes.
  Future<void> scrollToRect({
    @required Rect rect,
    @required RowExtentDelegate extentDelegate,
    @required Size viewportDimensions,
    @required Duration duration,
  }) async {
    final left = max(rect.left, 0.0);
    // Ensure we don't ask to scroll so the top spacer is visible.
    final top = max(rect.top, extentDelegate.layoutOffset(1));
    final right = max(left, rect.right);
    // Ensure we don't ask to scroll so that the bottom spacer is vislbe.
    final bottom = min(max(top, rect.bottom),
        extentDelegate.layoutOffset(extentDelegate.length - 1));
    rect = Rect.fromLTRB(left, top, right, bottom);
    final targetY = _computeTargetOffsetY(
      currentOffset: _scrollControllerY.controller.offset,
      viewportDimension: viewportDimensions.height,
      rect: rect,
      extentDelegate: extentDelegate,
    );
    currentAnimateY = _scrollControllerY.animateTo(
      targetY,
      duration: duration,
      curve: defaultCurve,
    );

    // Determine a target X coordinate consistent with the target Y coordinate
    // we will end up as so we get a smooth animation to the final destination.
    final targetX = _computeTargetX(
      y: targetY,
      viewportDimensions: viewportDimensions,
      extentDelegate: extentDelegate,
    );

    unawaited(_scrollControllerX.animateTo(
      targetX,
      duration: duration,
      curve: defaultCurve,
    ));

    try {
      await currentAnimateY;
    } catch (e) {
      // Doesn't matter if the animation was cancelled.
    }
    currentAnimateY = null;
  }

  static VisibleRange computeNewVisibleRange(InspectorTreeNode targetNode,
      List<AnimatedRow> rawAnimatedRows, double viewHeight) {
    InspectorTreeNode firstVisible;
    InspectorTreeNode lastVisible;
    for (int i = 0; i < rawAnimatedRows.length; ++i) {
      final row = rawAnimatedRows[i];
      final currentNode = row.current?.node;
      if (currentNode == targetNode) {
        {
          // ensure viewHeight of nodes are visible before and after the
          // target node. We could use a larger range if animation performance
          // is good. We don't know exactly where in the viewport the target
          // node will appear so it is safest to include at least the viewport
          // height of nodes on either side.
          var offsetY = viewHeight;
          // Find first visible.
          for (int j = i; j >= 0; j--) {
            final r = rawAnimatedRows[j];
            final node = r.current?.node;
            if (node != null) {
              firstVisible = node;
            }
            if (offsetY < 0) break;
            offsetY -= r.endHeight;
          }
        }
        {
          var offsetY = 0.0;
          // Find last visible.
          lastVisible = targetNode;
          for (int j = i; j < rawAnimatedRows.length; j++) {
            final r = rawAnimatedRows[j];
            final node = r.current?.node;
            if (offsetY >= viewHeight) break;
            if (node != null) {
              lastVisible = node;
            }
            offsetY += r.endHeight;
          }
        }
        break;
      }
    }
    return VisibleRange(
      firstVisible,
      lastVisible,
    );
  }

  void maybeComputeNextAnimationFrame(BoxConstraints constraints) {
    if (controller == null) return;
    final viewportDimensions =
        Size(constraints.maxWidth, constraints.maxHeight);
    var animationTime = longDuration;
    final rawAnimatedRows = controller.rawAnimatedRows;
    final relationToExistingAnimation =
        AnimatedRow.compareAnimations(_currentRawAnimatedRows, rawAnimatedRows);
    // TODO(jacobr): simplify and cleanup this logic.
    if (relationToExistingAnimation != AnimationComparison.equal) {
      final lastAnimatedRows = _currentAnimatedRows;

      final lastTopSpacerHeight = topSpacer.evaluate(visibilityCurve);

      final scrollY = _scrollControllerY.offset;
      final visibleNodeOffsets =
          LinkedHashMap<InspectorTreeNode, double>.identity();
      final Map<InspectorInstanceRef, InspectorTreeNode> visibleNodeRefs = {};

      final alreadyHidden = Set<InspectorTreeNode>.identity();
      final rowsToAnimateOut = Set<AnimatedRow>.identity();

      // Determine where relevant nodes were in the previous animation.
      double y = lastTopSpacerHeight;
      if (lastAnimatedRows != null) {
        for (final row in lastAnimatedRows) {
          final height = row.animatedRowHeight(visibilityCurve);
          final node = row.current?.node;
          // We are only interested in nodes that are still relevant for the
          // new animation which means only nodes from the end of the previous
          // animation.
          if (node != null) {
            if (height > 0) {
              if (y + height >= scrollY &&
                  y <= scrollY + viewportDimensions.height) {
                visibleNodeOffsets[node] = y;
                final diagnostic = node.diagnostic;
                if (diagnostic != null && !diagnostic.isProperty) {
                  // The value ref is not safe to establish identity for
                  // property nodes.
                  final valueRef = node?.diagnostic?.valueRef;
                  if (valueRef != null) {
                    visibleNodeRefs[valueRef] = node;
                  }
                }
              }
            } else {
              alreadyHidden.add(node);
            }
          }
          y += height;
        }
      }

      InspectorTreeNode fixedPointNodeCurrent;
      InspectorTreeNode fixedPointNodeLast;
      if (rawAnimatedRows != null) {
        for (var row in rawAnimatedRows) {
          final node = row.current?.node;
          if (node != null) {
            if (visibleNodeOffsets.containsKey(node)) {
              // exact match so break.
              fixedPointNodeCurrent = node;
              fixedPointNodeLast = node;
              break;
            } else {
              final valueRef = node?.diagnostic?.valueRef;
              if (fixedPointNodeCurrent == null &&
                  valueRef != null &&
                  visibleNodeRefs.containsKey(valueRef)) {
                // Don't break as it would be better if we found an exact match.
                // It is possible the same diagnostic occurred at multiple
                // locations in the tree.
                fixedPointNodeCurrent = node;
                fixedPointNodeLast = visibleNodeRefs[valueRef];
              }
            }
          }
        }
      }
      if (fixedPointNodeCurrent == null) {
        // Find the first node in the new tree and pretend it is the fixed point
        // node.
        for (var row in rawAnimatedRows) {
          if (row.current != null) {
            fixedPointNodeCurrent = row.current.node;
            fixedPointNodeLast = visibleNodeOffsets.keys.safeFirst;
            break;
          }
        }
      }

      var fixedPointCurrentRow =
          _findMatchingRow(rawAnimatedRows, fixedPointNodeCurrent);

      final fixedPointWasVisible =
          visibleNodeOffsets.containsKey(fixedPointNodeCurrent);
      if (fixedPointNodeLast != null) {
        final fixedPointY = visibleNodeOffsets[fixedPointNodeLast];
        final double fixedPointYOffset =
            fixedPointY - _scrollControllerY.offset;
        for (int i = 0; i < rawAnimatedRows.length; ++i) {
          final row = rawAnimatedRows[i];
          final lastNode = row.last?.node;
          if (lastNode == fixedPointNodeLast) {
            {
              var offsetY = fixedPointYOffset;
              // Find first visible.
              for (int j = i; j >= 0; j--) {
                final r = rawAnimatedRows[j];
                if (r.current == null && !alreadyHidden.contains(r.last.node)) {
                  rowsToAnimateOut.add(r);
                }
                // TODO(jacobr): this check could be offsetY < 0 but we add an
                // extra viewport of height to be safe because we might be up
                // to 1 viewport off in terms of what nodes are visible because
                // we may be wrong about what the final scroll offset is.
                if (offsetY < -viewportDimensions.height) break;
                offsetY -= r.beginHeight;
              }
            }
            {
              // Starting at fixedPointYOffset would be technically correct but
              // we don't know exactly how far
              var offsetY = 0.0;
              for (int j = i; j < rawAnimatedRows.length; j++) {
                final row = rawAnimatedRows[j];
                // TODO(jacobr): this check could be offsetY > viewHeight but we
                // add an extra viewport of height to be safe because we might
                // be up to 1 viewport off in terms of what nodes are visible
                // because we may be wrong about what the final scroll offset
                // is.
                if (offsetY > viewportDimensions.height * 2) break;
                if (row.current == null &&
                    row.last != null &&
                    !alreadyHidden.contains(row.last.node)) {
                  assert(row.last.node != null);
                  rowsToAnimateOut.add(row);
                }
                offsetY += row.beginHeight;
              }
            }
            break;
          }
        }
      }

      controller.optimizeRowAnimation(
        currentVisibleRange: computeNewVisibleRange(
          _scrollToTargets?.isNotEmpty ?? false
              ? _scrollToTargets.first
              : fixedPointNodeCurrent,
          rawAnimatedRows,
          viewportDimensions.height,
        ),
        rowsToAnimateOut: rowsToAnimateOut,
      );
      _currentAnimatedRows = controller.animatedRows;
      _currentRawAnimatedRows = rawAnimatedRows;

      // As part of optimizing the animation, the fixed row may have changed.
      fixedPointCurrentRow =
          _findMatchingRow(_currentAnimatedRows, fixedPointNodeCurrent);

      double beginY = 0;
      double endY = 0;

      double targetDelta;
      // Number of pixels from the target delta that are a single
      // snap at the end of the animation rather than a smooth transition.
      double nextFixedPointY;
      for (int i = 0; i < _currentAnimatedRows.length; ++i) {
        final row = _currentAnimatedRows[i];
        final lastNode = row.last?.node;
        // Assert all snap to end animations have been removed.
        if (lastNode != null && lastNode == fixedPointNodeLast) {
          // We are only interested in nodes that are still relevant for the
          // new animation which means only nodes from the end of the previous
          // animation
          targetDelta = endY - beginY;
          nextFixedPointY = beginY;
        }
        beginY += row.beginHeight;
        endY += row.endHeight;
      }

      double targetOffset;

      // If we aren't attempting to scroll to a specific node, add an extra
      // spacer at the top of the list to keep the rows stable.
      if (targetDelta != null) {
        // We need to construct a tween where both ends are greater than zero.
        // The two ends are [0, -targetDelta]
        final double extraTopPadding = max(0, targetDelta);
        topSpacer =
            Tween(begin: extraTopPadding, end: extraTopPadding - targetDelta);
        final fixedPointY = visibleNodeOffsets[fixedPointNodeLast];
        if (fixedPointY != null && nextFixedPointY != null) {
          final fixedPointDelta =
              (nextFixedPointY + topSpacer.begin) - fixedPointY;
          targetOffset = _scrollControllerY.offset + fixedPointDelta;
          if (targetOffset < 0) {
            topSpacer = Tween(
                begin: topSpacer.begin - targetOffset,
                end: fixedPointWasVisible ? (topSpacer.end - targetOffset) : 0);
            targetOffset = 0;
          }
        }
      } else {
        topSpacer = Tween(begin: 0, end: 0);
      }

      final lengthDelta = endY - beginY;
      // We need to construct a tween where all 3 values in the tween are > 0
      // so that we never have to request negative offsets.
      final double extraBottomPadding = max(0, lengthDelta);
      // TODO(jacobr): grow the bottom spacer further to make room for scrolls
      // to the bottom of the list?
      bottomSpacer = Tween(
        begin: extraBottomPadding,
        end: extraBottomPadding - lengthDelta,
      );
      // If the current animation is the reverse of the previous, we want to
      // start the new animation to line up exactly with the previous animation.
      final visibilityStartNewAnimation = visibilityController.value != 1.0 &&
              relationToExistingAnimation == AnimationComparison.reverse &&
              visibilityController.value != 0.0
          ?
          // There is an old animation in progress.
          // We could handle this case better with more complexity in how we run
          // animations. Instead, we assume this case is rare and just handle the
          // simple case where the only time multiple animations are triggered in
          // close enough succession for this to be a problem is when the second
          // animation is undoing the first animation.

          // This logic assumes a symmetric animation curve.
          // TODO(jacobr): Flutter may have some intersection logic for
          // animation curves so we don't have to assume this.
          1.0 - visibilityController.value
          :
          // The previous animation was done. We can run the new animation without
          // concern that the combination of the intermediate state of the
          // previous animation and
          // the current
          0.0;

      // TODO(jacobr): more gracefully handle existing animations by
      // tracking what the current animation value was.
      if (targetOffset != null &&
          (targetOffset - _scrollControllerY.offset).abs() >= 0.001) {
        // XXX use epsilon
        _scrollControllerY.jumpTo(targetOffset);
      }

      // Determine a target X coordinate consistent with the target Y coordinate
      // we will end up as so we get a smooth animation to the final destination.

      final effectiveCurrentX = _scrollControllerX.offsetAfterNavigation;
      double targetX = effectiveCurrentX;
      if (fixedPointCurrentRow != null) {
        // Scroll in X so the fixed point node doesn't change its indent

        // This is also updated later in this method but there is no harm in
        // updating it here as well.
        visibilityController.value = visibilityStartNewAnimation;
        final currentXDelta = effectiveCurrentX -
            indentForDepth(
                fixedPointCurrentRow.depth.evaluate(visibilityCurve));

        targetX =
            indentForDepth(fixedPointCurrentRow.current.depth) + currentXDelta;
      } else if (!_scrollControllerX.isAnimateToInProgress) {
        // XXX TODO(jacobr): what should we do?
        // targetX = _computeTargetX(targetOffset ?? _scrollControllerY.offset);
      }
      targetX = max(0, targetX);

      // If we are starting the animation part way through, use a shorter total
      // time but never shrink the animation time bellow 0.3 of the target
      // animation time so the animation is not too short.
      // As we typically use an easeInOut curve that starts slowly
      // and accelerates, using just (1 - visibilityStartNewAnimation) which
      // would make the new animation run for same length as the animation we
      // are reversing. TODO(jacobr): find a more principled way to do this.
      animationTime = longDuration * (1 - 0.7 * visibilityStartNewAnimation);
      if (effectiveCurrentX != targetX) {
        unawaited(_scrollControllerX.animateTo(
          targetX,
          duration: animationTime,
          curve: defaultCurve,
        ));
      }
      visibilityController.value = visibilityStartNewAnimation;
      visibilityController.animateTo(
        1.0,
        duration: animationTime,
        curve: defaultCurve,
      );
      extentDelegate.configure(
        rows: controller.animatedRows,
        topSpacer: topSpacer,
        bottomSpacer: bottomSpacer,
      );
      animationDoneExtentDelegate.configure(
        rows: controller.animatedRows,
        topSpacer: topSpacer,
        bottomSpacer: bottomSpacer,
      );
    }
    if (_scrollToTargets != null) {
      var target = computeTargetRect(
        targets: _scrollToTargets,
        treeStructure: controller.currentTreeStructure,
        extentDelegate: animationDoneExtentDelegate,
      );
      if (target != null && !target.isEmpty) {
        target = target.inflate(targetXOffset);
        scrollToRect(
            rect: target,
            viewportDimensions: viewportDimensions,
            extentDelegate: animationDoneExtentDelegate,
            duration: animationTime);
      }
    }

    _scrollToTargets = null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (controller == null) {
      // Indicate the tree is loading.
      return const CenteredCircularProgressIndicator();
    }

    return LayoutBuilder(builder: (context, constraints) {
      final colorScheme = Theme.of(context).colorScheme;
      // We need the current constraints to determine how to optimize the
      // animation to avoid animating content that doesn't matter.
      maybeComputeNextAnimationFrame(constraints);
      return ClipRect(
        child: Scrollbar(
          child: Stack(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: _scrollControllerX.controller,
                physics: const BouncingScrollPhysics(),
                child: SizedBox(
                  width:
                      controller.rowWidth + indentForDepth(controller.maxDepth),
                  child: Scrollbar(
                    child: GestureDetector(
                      onTap: _focusNode.requestFocus,
                      child: Focus(
                        onKey: _handleKeyEvent,
                        autofocus: widget.isSummaryTree,
                        focusNode: _focusNode,
                        child: ExtentDelegateListView(
                          physics: const BouncingScrollPhysics(),
                          extentDelegate: extentDelegate,
                          controller: _scrollControllerY.controller,
                          childrenDelegate: SliverChildBuilderDelegate(
                            (context, index) {
                              if (index == 0 ||
                                  index == controller.animatedRows.length + 1) {
                                return const SizedBox();
                              }
                              final row = _currentAnimatedRows[index - 1];
                              if (row == null) return const SizedBox();
                              if (!row.animateRow) {
                                return _InspectorTreeRowWidget(
                                  key: PageStorageKey(row?.node),
                                  inspectorTreeState: this,
                                  row: row.targetRow,
                                );
                              }
                              return _AnimatedInspectorTreeRowWidget(
                                key: PageStorageKey(row?.node),
                                inspectorTreeState: this,
                                row: row,
                                visibilityCurve: visibilityCurve,
                              );
                            },
                            childCount: controller.animatedRows.length + 2,
                          ),
                        ),
                      ),
                    ),
                    controller: _scrollControllerY.controller,
                  ),
                ),
              ),
              CustomPaint(
                painter: TreeStructurePainter(
                  constraints: constraints,
                  horizontalScroll: _scrollControllerX.controller,
                  verticalScroll: _scrollControllerY.controller,
                  lineModel: controller.lineModel,
                  extentDelegate: extentDelegate,
                  inspectorTreeController: controller,
                  animation: visibilityCurve,
                  colorScheme: colorScheme,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  @override
  bool get wantKeepAlive => true;

  /// Find the best matching row for a node.
  ///
  /// If there is a current row matching the node than is prefered to a row
  /// from the last (animated out) list rows.
  AnimatedRow _findMatchingRow(
    List<AnimatedRow> rows,
    InspectorTreeNode node,
  ) {
    if (node == null || rows == null) return null;
    for (final row in rows) {
      if (row.current?.node == node) {
        return row;
      }
    }
    return null;
  }

  @override
  void animateToTargets(List<InspectorTreeNode> targets) {
    setState(() {
      _scrollToTargets = targets;
    });
  }
}

class TreeStructurePainter extends CustomPainter {
  TreeStructurePainter({
    @required this.constraints,
    @required this.verticalScroll,
    @required this.horizontalScroll,
    @required this.lineModel,
    @required this.extentDelegate,
    @required this.animation,
    @required this.colorScheme,
    @required this.inspectorTreeController,
  })  : assert(colorScheme != null),
        super(
          repaint: Listenable.merge(
            [
              verticalScroll,
              horizontalScroll,
              animation,
              extentDelegate.layoutDirty,
            ],
          ),
        );

  final BoxConstraints constraints;
  final ScrollController verticalScroll;
  final ScrollController horizontalScroll;
  final TreeStructureLineModel lineModel;
  final ColorScheme colorScheme;
  final Animation<double> animation;
  final ExtentDelegate extentDelegate;
  final InspectorTreeController inspectorTreeController;

  @override
  void paint(Canvas canvas, Size size) {
    final defaultPaint = _defaultPaint(colorScheme);
    final verticalScrollOffset = verticalScroll.offset;
    final horizontalScrollOffset = horizontalScroll.offset;
    final visible = Rect.fromLTWH(
      horizontalScrollOffset,
      verticalScrollOffset,
      constraints.maxWidth,
      constraints.maxHeight,
    );
    canvas.save();
    canvas.translate(-horizontalScrollOffset, -verticalScrollOffset);
    for (var line in lineModel.visibleLines(
        visible, extentDelegate, animation, inspectorTreeController)) {
      final opacity = line.opacity;
      if (opacity == 0.0) continue;
      canvas.drawLine(
        line.start,
        line.end,
        opacity == 1.0 ? defaultPaint : _paintWithOpacity(opacity, colorScheme),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    if (oldDelegate is TreeStructurePainter) {
      if (oldDelegate == this) {
        return false;
      }
      return constraints != oldDelegate.constraints ||
          verticalScroll != oldDelegate.verticalScroll ||
          colorScheme != oldDelegate.colorScheme ||
          animation != oldDelegate.animation ||
          extentDelegate != oldDelegate.extentDelegate;
    }

    return true;
  }
}

/// Tween that combines a base [tween] with a snap by [snapToEndDelta]
/// at the end of the tween.
class SnapTween extends Tween<double> {
  SnapTween({
    @required this.tween,
    @required this.snapToEndDelta,
  })  : assert(tween.begin >= 0.0),
        assert(tween.end >= 0.0),
        assert(tween.end + snapToEndDelta >= 0.0),
        super(begin: tween.begin, end: tween.end + snapToEndDelta);

  final double snapToEndDelta;

  final Tween<double> tween;

  // The inherited lerp() function doesn't work with ints because it multiplies
  // the begin and end types by a double, and int * double returns a double.
  @override
  double lerp(double t) {
    double value = tween.lerp(t);
    if (t == 1.0) {
      value += snapToEndDelta;
    }
    return value;
  }
}

Paint _defaultPaint(ColorScheme colorScheme) => Paint()
  ..color = colorScheme.treeGuidelineColor
  ..strokeWidth = chartLineStrokeWidth;

class AnimatedSpacer extends StatelessWidget {
  const AnimatedSpacer({
    Key key,
    @required this.animation,
    this.visibilityCurve,
  }) : super(key: key);

  final Animation<double> animation;
  final Animation<double> visibilityCurve;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: visibilityCurve,
      builder: (_, __) {
        if (animation == null) {
          return const SizedBox();
        }
        return SizedBox(height: animation.value);
      },
    );
  }
}

// TODO(jacobr): optimize so we cache this value rather than computing it for
// every single line segment.
Paint _paintWithOpacity(double opacity, ColorScheme colorScheme) {
  // ColorTween is used instead of opacity so that we can intentionally overdraw
  // line segments slightly to avoid gaps between line segments likely due to
  // floating point rounding errors.
  return Paint()
    ..color = colorScheme.treeGuidelineColor.withOpacity(opacity)
    ..strokeWidth = chartLineStrokeWidth;
}

const disableOldRowPainters = false;

/// Widget defining the contents of a single row in the InspectorTree.
///
/// This class defines the scaffolding around the rendering of the actual
/// content of a [RemoteDiagnosticsNode] provided by
/// [DiagnosticsNodeDescription] to provide a tree implementation with lines
/// drawn between parent and child nodes when nodes have multiple children.
///
/// Changes to how the actual content of the node within the row should
/// be implemented by changing [DiagnosticsNodeDescription] instead.
class InspectorRowContent extends StatelessWidget {
  const InspectorRowContent({
    @required this.row,
    @required this.controller,
    @required this.onToggle,
    @required this.expandArrowAnimation,
  });

  final InspectorTreeRow row;
  final InspectorTreeControllerFlutter controller;
  final VoidCallback onToggle;
  final Animation<double> expandArrowAnimation;

  @override
  Widget build(BuildContext context) {
    final double currentX = indentForDepth(row.depth) - columnWidth;
    final colorScheme = Theme.of(context).colorScheme;

    if (row == null) {
      return const SizedBox();
    }
    Color backgroundColor;
    if (row.isSelected || row.node == controller.hover) {
      backgroundColor = row.isSelected
          ? colorScheme.selectedRowBackgroundColor
          : colorScheme.hoverColor;
    }

    final node = row.node;
    return Padding(
      padding: EdgeInsets.only(left: currentX),
      child: ClipRect(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            node.showExpandCollapse
                ? InkWell(
                    onTap: onToggle,
                    child: RotationTransition(
                      turns: expandArrowAnimation,
                      child: const Icon(
                        Icons.expand_more,
                        size: defaultIconSize,
                      ),
                    ),
                  )
                : const SizedBox(width: defaultSpacing, height: defaultSpacing),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: backgroundColor,
                ),
                child: InkWell(
                  onTap: () {
                    controller.onSelectRow(row);
                    // TODO(gmoothart): It may be possible to capture the tap
                    // and request focus directly from the InspectorTree. Then
                    // we wouldn't need this.
                    controller.requestFocus();
                  },
                  child: Container(
                    height: rowHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: DiagnosticsNodeDescription(node.diagnostic),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget defining the contents of a single row in the InspectorTree.
///
/// This class defines the scaffolding around the rendering of the actual
/// content of a [RemoteDiagnosticsNode] provided by
/// [DiagnosticsNodeDescription] to provide a tree implementation with lines
/// drawn between parent and child nodes when nodes have multiple children.
///
/// Changes to how the actual content of the node within the row should
/// be implemented by changing [DiagnosticsNodeDescription] instead.
class AnimatedInspectorRowContent extends StatelessWidget {
  const AnimatedInspectorRowContent({
    @required this.row,
    @required this.controller,
    @required this.onToggle,
    @required this.expandArrowAnimation,
    @required this.visibilityAnimation,
  });

  final AnimatedRow row;
  final InspectorTreeControllerFlutter controller;
  final VoidCallback onToggle;
  final Animation<double> expandArrowAnimation;
  final Animation<double> visibilityAnimation;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (row == null) {
      return const SizedBox();
    }
    Color backgroundColor;
    final targetRow = row.targetRow;
    if (targetRow.isSelected || row.node == controller.hover) {
      backgroundColor = row.isSelected
          ? colorScheme.selectedRowBackgroundColor
          : colorScheme.hoverColor;
    }

    final node = row.node;

    final rowContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        row.showExpandCollapse
            ? FadeTransition(
                opacity: row.expandCollapseTween.animate(visibilityAnimation),
                child: InkWell(
                  onTap: onToggle,
                  child: RotationTransition(
                    turns: expandArrowAnimation,
                    child: const Icon(
                      Icons.expand_more,
                      size: 16.0,
                    ),
                  ),
                ),
              )
            : const SizedBox(width: 16.0, height: 16.0),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: backgroundColor,
            ),
            child: InkWell(
              onTap: () {
                controller.onSelectRow(row.targetRow);
              },
              child: Container(
                height: rowHeight,
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: DiagnosticsNodeDescription(node.diagnostic),
              ),
            ),
          ),
        ),
      ],
    );
    return AnimatedBuilder(
      animation: visibilityAnimation,
      builder: (context, child) {
        final double currentX =
            indentForDepth(row.depth.evaluate(visibilityAnimation)) -
                columnWidth;
        final currentRowHeight = row.animatedRowHeight(visibilityAnimation);
        if (currentRowHeight <= 1) {
          return const SizedBox();
        }
        return SizedBox(
          height: rowHeight,
          child: Padding(
            padding: EdgeInsets.only(left: currentX),
            child: rowContent,
          ),
        );
      },
    );
  }
}
