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
import '../extent_delegate_list.dart';
import '../theme.dart';
import '../ui/colors.dart';
import '../ui/theme.dart';
import '../utils.dart';
import 'diagnostics.dart';
import 'diagnostics_node.dart';
import 'inspector_tree.dart';

/// Presents a [TreeNode].
class _InspectorTreeRowWidget extends StatefulWidget {
  /// Constructs a [_InspectorTreeRowWidget] that presents a line in the
  /// Inspector tree.
  const _InspectorTreeRowWidget({
    @required Key key,
    @required this.row,
    @required this.inspectorTreeState,
  }) : super(key: key);

  final _InspectorTreeState inspectorTreeState;

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

  final _InspectorTreeState inspectorTreeState;
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

class InspectorTreeControllerFlutter extends Object
    with InspectorTreeController, InspectorTreeFixedRowHeightController {
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
  Rect getBoundingBox(InspectorTreeRow row) {
    // For future reference: the bounding box likely needs to be in terms of
    // positions after the current animations are complete so that computations
    // to start animations to show specific widget scroll to where the target
    // nodes will be displayed rather than where they are currently displayed.
    return Rect.fromLTWH(
      getDepthIndent(row.depth),
      getRowY(row.index),
      rowWidth,
      rowHeight,
    );
  }

  @override
  void scrollToRect(Rect targetRect) {
    client?.scrollToRect(targetRect);
  }

  @override
  void setState(VoidCallback fn) {
    fn();
    client?.onChanged();
  }

  /// Width each row in the tree should have ignoring its indent.
  ///
  /// Content in rows should wrap if it exceeds this width.
  final double rowWidth = 1200;

  /// Maximum indent of the tree in pixels.
  double _maxIndent;

  double get maxRowIndent {
    if (lastContentWidth == null) {
      double maxIndent = 0;
      for (int i = 0; i < numRows; i++) {
        final row = getCachedRow(i);
        if (row != null) {
          maxIndent = max(maxIndent, getDepthIndent(row.depth));
        }
      }
      lastContentWidth = maxIndent + maxIndent;
      _maxIndent = maxIndent;
    }
    return _maxIndent;
  }

  void requestFocus() {
    client?.requestFocus();
  }
}

abstract class InspectorControllerClient {
  void onChanged();

  void scrollToRect(Rect rect);

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

  final InspectorTreeController controller;
  final bool isSummaryTree;

  @override
  State<InspectorTree> createState() => _InspectorTreeState();
}

// AutomaticKeepAlive is necessary so that the tree does not get recreated when we switch tabs.
class _InspectorTreeState extends State<InspectorTree>
    with
        SingleTickerProviderStateMixin,
        AutomaticKeepAliveClientMixin<InspectorTree>,
        AutoDisposeMixin
    implements InspectorControllerClient {
  BoxConstraints _lastConstraints;

  InspectorTreeControllerFlutter get controller => widget.controller;

  bool get isSummaryTree => widget.isSummaryTree;

  ScrollController _scrollControllerY;
  ScrollController _scrollControllerX;
  Future<void> currentAnimateY;
  Rect currentAnimateTarget;

  FocusNode _focusNode;
  AnimationController visibilityController;

  /// A curved animation that matches [expandController], moving from 0.0 to 1.0
  /// Useful for animating the size of a child that is appearing.
  Animation<double> visibilityCurve;
  FixedExtentDelegate extentDelegate;

  @override
  void initState() {
    super.initState();
    _scrollControllerX = ScrollController();
    _scrollControllerY = ScrollController();
    // TODO(devoncarew): Commented out as per flutter/devtools/pull/2001.
    //_scrollControllerY.addListener(_onScrollYChange);
    _focusNode = FocusNode();
    visibilityController = longAnimationController(this);
    visibilityCurve = defaultCurvedAnimation(visibilityController);
    visibilityController.addStatusListener((status) {
      setState(() {});
      if (AnimationStatus.completed == status ||
          AnimationStatus.dismissed == status) {
        print("XX status done. TODO(jacobr): do somethign");
        // nudge offset and switch to non-animating view.
      }
    });
    extentDelegate = FixedExtentDelegate(computeExtent: (index) {
      if (controller?.animatedRows == null) return 0;
      if (index == 0) {
        return topAnimation?.value ?? 0;
      }
      if (index == controller.animatedRows.length + 1) {
        return bottomAnimation?.value ?? 0.0;
      }
      return controller.animatedRows[index - 1]
          .animatedRowHeight(visibilityCurve);
    }, computeLength: () {
      final rows = controller?.animatedRows;
      if (rows == null) return 0;
      return rows.length + 2;
    });
    visibilityController.addListener(extentDelegate.recompute);
    _bindToController();
  }

  @override
  void didUpdateWidget(InspectorTree oldWidget) {
    if (oldWidget.controller != widget.controller) {
      final InspectorTreeControllerFlutter oldController = oldWidget.controller;
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

  /// Compute the goal x scroll given a y scroll value.
  ///
  /// This enables animating the x scroll as the y scroll changes which helps
  /// keep the relevant content in view while scrolling a large list.
  double _computeTargetX(double y) {
    final rowIndex = controller.getRowIndex(y);
    double requiredOffset;
    double minOffset = double.infinity;
    // TODO(jacobr): use maxOffset as well to better handle the case where the
    // previous row has a significantly larger indent.

    // TODO(jacobr): if the first or last row is only partially visible, tween
    // between its indent and the next row to more smoothly change the target x
    // as the y coordinate changes.
    if (rowIndex == controller.numRows) {
      return 0;
    }
    final endY = y += _scrollControllerY.position.viewportDimension;
    for (int i = rowIndex; i < controller.numRows; i++) {
      final rowY = controller.getRowY(i);
      if (rowY >= endY) break;

      final row = controller.getCachedRow(i);
      if (row == null) continue;
      final rowOffset = controller.getRowOffset(i);
      if (row.isSelected) {
        requiredOffset = rowOffset;
      }
      minOffset = min(minOffset, rowOffset);
    }
    if (requiredOffset == null) {
      return minOffset;
    }

    // If there is no target offset, use zero.
    if (minOffset == double.infinity) return 0;

    return minOffset;
  }

  @override
  Future<void> scrollToRect(Rect rect) async {
    // TODO(jacobr): this probably needs to be reworked.
    if (rect == currentAnimateTarget) {
      // We are in the middle of an animation to this exact rectangle.
      return;
    }
    currentAnimateTarget = rect;
    final targetY = _computeTargetOffsetY(
      _scrollControllerY,
      rect.top,
      rect.bottom,
    );
    assert(targetY != double.infinity);

    currentAnimateY = _scrollControllerY.animateTo(
      targetY,
      duration: longDuration,
      curve: defaultCurve,
    );

    // Determine a target X coordinate consistent with the target Y coordinate
    // we will end up as so we get a smooth animation to the final destination.
    final targetX = _computeTargetX(targetY);

    assert(targetX != double.infinity);
    unawaited(_scrollControllerX.animateTo(
      targetX,
      duration: longDuration,
      curve: defaultCurve,
    ));

    try {
      await currentAnimateY;
    } catch (e) {
      // Doesn't matter if the animation was cancelled.
    }
    currentAnimateY = null;
    currentAnimateTarget = null;
  }

  /// Animate so that the entire range minOffset to maxOffset is within view.
  double _computeTargetOffsetY(
    ScrollController controller,
    double minOffset,
    double maxOffset,
  ) {
    // Probably needs to be reworked.
    final currentOffset = controller.offset;
    final viewportDimension = _scrollControllerY.position.viewportDimension;
    final currentEndOffset = viewportDimension + currentOffset;

    // If the requested range is larger than what the viewport can show at once,
    // prioritize showing the start of the range.
    maxOffset = min(viewportDimension + minOffset, maxOffset);
    if (currentOffset <= minOffset && currentEndOffset >= maxOffset) {
      return controller
          .offset; // Nothing to do. The whole range is already in view.
    }
    if (currentOffset > minOffset) {
      // Need to scroll so the minOffset is in view.
      return minOffset;
    }

    assert(currentEndOffset < maxOffset);
    // Need to scroll so the maxOffset is in view at the very bottom of the
    // list view.
    return maxOffset - viewportDimension;
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

  List<AnimatedRow> _currentAnimatedRows;
  Tween<double> topTween;
  Tween<double> bottomTween;
  Animation<double> topAnimation;
  Animation<double> bottomAnimation;

  int get countSpacerAnimations {
    int count = 0;
    if (topAnimation != null) count++;
    if (bottomAnimation != null) count++;
    return count;
  }

  @override
  void onChanged() {
    if (_currentAnimatedRows != controller.animatedRows) {
      final lastAnimatedRows = _currentAnimatedRows;

      double viewHeight = 1000.0; // Arbitrary. We could let it be zero.
      if (_lastConstraints != null) {
        viewHeight = _lastConstraints.maxHeight;
      }

      final lastTopSpacerHeight = topAnimation?.value ?? 0;
      double y = lastTopSpacerHeight;

      final scrollY = _scrollControllerY.offset;
      final Map<InspectorTreeNode, double> visibleNodeOffsets =
          LinkedHashMap.identity();

      final selection = controller.selection;
      // Determine where relevant nodes were in the previous animation.
      if (lastAnimatedRows != null) {
        for (final row in lastAnimatedRows) {
          final height = row.animatedRowHeight(visibilityCurve);
          // We are only interested in nodes that are still relevant for the
          // new animation which means only nodes from the end of the previous
          // animation.
          final node = row.current?.node;
          if (node != null) {
            if (y + height >= scrollY && y <= scrollY + viewHeight) {
              visibleNodeOffsets[node] = y;
            }
          }
          y += height;
        }
      }

      InspectorTreeNode fixedPointNode;
      if (selection != null && visibleNodeOffsets.containsKey(selection)) {
        fixedPointNode = selection;
      }
      if (fixedPointNode == null && _currentAnimatedRows != null) {
        for (var row in _currentAnimatedRows) {
          final node = row.current?.node;
          if (node != null && visibleNodeOffsets.containsKey(node)) {
            fixedPointNode = node;
            break;
          }
        }
      }

      InspectorTreeNode firstVisible;
      InspectorTreeNode lastVisible;
      if (fixedPointNode != null &&
          visibleNodeOffsets.containsKey(fixedPointNode)) {
        final fixedPointY = visibleNodeOffsets[fixedPointNode];
        final double fixedPointYOffset =
            fixedPointY - _scrollControllerY.offset;
        print("XXX fixedPointYOffset: $fixedPointYOffset");
        final nextAnimatedRows = controller.animatedRows;
        for (int i = 0; i < nextAnimatedRows.length; ++i) {
          final row = nextAnimatedRows[i];
          final currentNode = row.current?.node;
          if (currentNode == fixedPointNode) {
            {
              var offsetY = fixedPointYOffset;
              // Find first visible.
              for (int j = i; j >= 0; j--) {
                final r = nextAnimatedRows[j];
                final node = r.current?.node;
                if (node != null) {
                  firstVisible = node;
                }
                if (offsetY < 0) break;
                offsetY -= r.endHeight;
              }
            }
            {
              var offsetY = fixedPointYOffset;
              // Find last visible.
              for (int j = i; j < nextAnimatedRows.length; j++) {
                final r = nextAnimatedRows[j];
                final node = r.current?.node;
                if (node != null) {
                  lastVisible = node;
                }
                if (offsetY >= viewHeight) break;
                offsetY += r.endHeight;
              }
            }
            break;
          }
        }
      }

      controller.optimizeRowAnimation(
          lastVisibleRange: VisibleRange(
            visibleNodeOffsets.keys.safeFirst,
            visibleNodeOffsets.keys.safeLast,
          ),
          currentVisibleRange: VisibleRange(
            firstVisible,
            lastVisible,
          ));
      _currentAnimatedRows = controller.animatedRows;

      double beginY = 0;
      double endY = 0;

      double targetDelta;
      double nextFixedPointY;
      for (int i = 0; i < _currentAnimatedRows.length; ++i) {
        final row = _currentAnimatedRows[i];
        final currentNode = row.current?.node;
        if (currentNode != null && currentNode == fixedPointNode) {
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
      if (targetDelta != null) {
        if (targetDelta > 0) {
          topTween = Tween(begin: targetDelta, end: 0);
        } else {
          topTween = Tween(begin: 0, end: -targetDelta);
        }
        final fixedPointY = visibleNodeOffsets[fixedPointNode];
        if (fixedPointY != null && nextFixedPointY != null) {
          final fixedPointDelta =
              (nextFixedPointY + topTween.begin) - fixedPointY;
          targetOffset = _scrollControllerY.offset + fixedPointDelta;
          if (targetOffset < 0) {
            topTween = Tween(
                begin: topTween.begin - targetOffset,
                end: topTween.end - targetOffset);
            targetOffset = 0;
          }
        }
        topAnimation = topTween.animate(visibilityCurve);
      } else {
        topTween = null;
        topAnimation = null;
      }

      // XXX not right?
      final lengthDelta = endY - beginY;
      if (lengthDelta > 0) {
        bottomTween = Tween(begin: lengthDelta, end: 0);
      } else {
        bottomTween = Tween(begin: 0, end: -lengthDelta);
      }
      // TODO(jacobr): grow the bottom tween to make room for scrolls to the bottom of the list?
      bottomAnimation = bottomTween.animate(visibilityCurve);

      if (visibilityController.value != 1.0) {
        // There is an old animation in progress.
        // We could handle this case better with more complexity in how we run
        // animations. Instead, we assume this case is rare and just handle the
        // simple case where the only time multiple animations are triggered in
        // close enough succession for this to be a problem is when the second
        // animation is undoing the first animation.

        // This logic assumes a symmetric animation curve. Basically we snap closer
        visibilityController.value = 1 - visibilityController.value;
        // we could just completely cancel the old animation but this logic
      } else {
        // The previous animation was done. We can run the new animation without
        // concern that the combination of the intermediate state of the
        // previous animation and
        // the current
        visibilityController.reset();
      }
      visibilityController.animateTo(1, duration: longDuration);

      // TODO(jacobr): more gracefully handle existing animations by
      // tracking what the current animation value was.
      if (targetOffset != null &&
          (targetOffset - _scrollControllerY.offset).abs() >= 0.001) {
        print("XXX JUMPED TO $targetOffset from ${_scrollControllerY.offset}");
        _scrollControllerY.jumpTo(targetOffset);
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (controller == null) {
      // Indicate the tree is loading.
      return const Center(child: CircularProgressIndicator());
    }
    final child = Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: _scrollControllerX,
        child: SizedBox(
          width: controller.rowWidth + controller.maxRowIndent,
          child: Scrollbar(
            child: GestureDetector(
              onTap: _focusNode.requestFocus,
              child: Focus(
                onKey: _handleKeyEvent,
                autofocus: widget.isSummaryTree,
                focusNode: _focusNode,
                child: ExtentDelegateListView(
                  extentDelegate: extentDelegate,
                  controller: _scrollControllerY,
                  childrenDelegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index == 0 ||
                          index == controller.animatedRowsLength + 1) {
                        return const SizedBox();
                      }
                      final row = controller.getAnimatedRow(index - 1);
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
                    childCount:
                        controller.animatedRowsLength + countSpacerAnimations,
                  ),
                ),
              ),
            ),
            controller: _scrollControllerY,
          ),
        ),
      ),
    );
    return LayoutBuilder(builder: (context, constraints) {
      _lastConstraints = constraints;
      return child;
    });
  }

  @override
  bool get wantKeepAlive => true;
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

Paint _paintWithOpacity(double opacity, ColorScheme colorScheme) {
  return Paint()
    // TODO(kenz): try to use color from Theme.of(context) for treeGuidelineColor
    ..color = colorScheme.treeGuidelineColor.withOpacity(opacity)
    ..strokeWidth = chartLineStrokeWidth;
}

/// Custom painter that draws lines indicating how parent and child rows are
/// connected to each other.
///
/// Each rows object contains a list of ticks that indicate the x coordinates of
/// vertical lines connecting other rows need to be drawn within the vertical
/// area of the current row. This approach has the advantage that a row contains
/// all information required to render all content within it but has the
/// disadvantage that the x coordinates of each line connecting rows must be
/// computed in advance.
class _RowPainter extends CustomPainter {
  _RowPainter(this.row, this._controller, this.colorScheme);

  final InspectorTreeController _controller;
  final InspectorTreeRow row;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    double currentX = 0;

    if (row == null) {
      return;
    }
    final paint = _defaultPaint(colorScheme);
    final InspectorTreeNode node = row.node;
    final bool showExpandCollapse = node.showExpandCollapse;
    for (var tick in row.ticks) {
      currentX = _controller.getDepthIndent(tick.index) - columnWidth * 0.5;
      // Draw a vertical line for each tick identifying a connection between
      // an ancestor of this node and some other node in the tree.
      canvas.drawLine(
        Offset(currentX, 0.0),
        Offset(currentX, rowHeight),
        paint,
      );
    }
    // If this row is itself connected to a parent then draw the L shaped line
    // to make that connection.
    if (row.lineToParent) {
      final paint = _defaultPaint(colorScheme);
      currentX = _controller.getDepthIndent(row.depth - 1) - columnWidth * 0.5;
      final double width = showExpandCollapse ? columnWidth * 0.5 : columnWidth;
      if (row.ticks.isEmpty || row.ticks.last.index != row.depth - 1) {
        canvas.drawLine(
          Offset(currentX, 0.0),
          Offset(currentX, rowHeight * 0.5),
          paint,
        );
      }
      canvas.drawLine(
        Offset(currentX, rowHeight * 0.5),
        Offset(currentX + width, rowHeight * 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    if (oldDelegate is _RowPainter) {
      // TODO(jacobr): check whether the row has different ticks.
      return oldDelegate.colorScheme.isLight != colorScheme.isLight;
    }
    return true;
  }
}

/// Custom painter that draws lines indicating how parent and child rows are
/// connected to each other.
///
/// Each rows object contains a list of ticks that indicate the x coordinates of
/// vertical lines connecting other rows need to be drawn within the vertical
/// area of the current row. This approach has the advantage that a row contains
/// all information required to render all content within it but has the
/// disadvantage that the x coordinates of each line connecting rows must be
/// computed in advance.
class _AnimatedRowPainter extends CustomPainter {
  _AnimatedRowPainter(
      this.row, this._controller, this.visibilityAnimation, this.colorScheme);

  final InspectorTreeController _controller;
  final AnimatedRow row;
  final Animation<double> visibilityAnimation;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    double currentX = 0;

    if (row == null || size.height == 0) {
      return;
    }
    final InspectorTreeNode node = row.node;
    final bool showExpandCollapse = node.showExpandCollapse;

    final rowHeight = row.animatedRowHeight(visibilityAnimation);
    for (var tick in row.ticks) {
      currentX = _controller.getDepthIndent(tick.depth(visibilityAnimation)) -
          columnWidth * 0.5;
      final opacity = tick.opacity(visibilityAnimation);
      // Draw a vertical line for each tick identifying a connection between
      // an ancestor of this node and some other node in the tree.
      if (opacity > 0) {
        canvas.drawLine(
          Offset(currentX, 0.0),
          Offset(currentX, rowHeight),
          opacity == 1.0
              ? _defaultPaint(colorScheme)
              : _paintWithOpacity(opacity, colorScheme),
        );
      }
    }

    // If this row is itself connected to a parent then draw the L shaped line
    // to make that connection.
    if (row.lineToParent != null) {
      final opacity = row.lineToParent.opacity(visibilityAnimation);
      final paint = opacity == 1.0
          ? _defaultPaint(colorScheme)
          : _paintWithOpacity(opacity, colorScheme);
      currentX = _controller
              .getDepthIndent(row.lineToParent.depth(visibilityAnimation)) -
          columnWidth * 0.5;
      final double width = showExpandCollapse ? columnWidth * 0.5 : columnWidth;
      // XX add back if (row.ticks.isEmpty || row.ticks.last != row.depth - 1)
      {
        canvas.drawLine(
          Offset(currentX, 0.0),
          Offset(currentX, rowHeight * 0.5),
          paint,
        );
      }
      canvas.drawLine(
        Offset(currentX, rowHeight * 0.5),
        Offset(currentX + width, rowHeight * 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    if (oldDelegate is _RowPainter) {
      // TODO(jacobr): check whether the row has different ticks.
      return oldDelegate.colorScheme.isLight != colorScheme.isLight;
    }
    return true;
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
    final double currentX = controller.getDepthIndent(row.depth) - columnWidth;
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
    return CustomPaint(
      painter: _RowPainter(row, controller, colorScheme),
      size: Size(currentX, rowHeight),
      child: Padding(
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
                  : const SizedBox(
                      width: defaultSpacing, height: defaultSpacing),
              DecoratedBox(
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
            ],
          ),
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
    final double currentX =
        controller.getDepthIndent(row.depth(visibilityAnimation)) - columnWidth;
    final colorScheme = Theme.of(context).colorScheme;

    if (row == null) {
      return const SizedBox();
    }
    Color backgroundColor;
    if (row.targetRow.isSelected || row.node == controller.hover) {
      backgroundColor = row.isSelected
          ? colorScheme.selectedRowBackgroundColor
          : colorScheme.hoverColor;
    }

    final node = row.node;
    final childSmall = CustomPaint(
        painter: _AnimatedRowPainter(
            row, controller, visibilityAnimation, colorScheme),
        size: Size(currentX, rowHeight));
    final childFull = CustomPaint(
      painter: _AnimatedRowPainter(
          row, controller, visibilityAnimation, colorScheme),
      size: Size(currentX, rowHeight),
      child: Padding(
        padding: EdgeInsets.only(left: currentX),
        child: ClipRect(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            textBaseline: TextBaseline.alphabetic,
            children: [
              node.showExpandCollapse
                  ? InkWell(
                      onTap: onToggle,
                      child: RotationTransition(
                        turns: expandArrowAnimation,
                        child: const Icon(
                          Icons.expand_more,
                          size: 16.0,
                        ),
                      ),
                    )
                  : const SizedBox(width: 16.0, height: 16.0),
              DecoratedBox(
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
            ],
          ),
        ),
      ),
    );
    return AnimatedBuilder(
      animation: visibilityAnimation,
      builder: (context, child) {
        return (row.animatedRowHeight(visibilityAnimation) > 4)
            ? childFull
            : childSmall;
      },
    );
  }
}
