// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math';

import 'package:devtools_app/src/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pedantic/pedantic.dart';
import 'package:flutter_widgets/flutter_widgets.dart';

import '../../flutter/auto_dispose_mixin.dart';
import '../../flutter/collapsible_mixin.dart';
import '../../flutter/theme.dart';
import '../../ui/colors.dart';
import '../diagnostics_node.dart';
import '../inspector_tree.dart';
import 'diagnostics.dart';

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

class InspectorTreeControllerFlutter extends Object
    with InspectorTreeController {
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
    client?.animateToTargets(targets);
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
}

abstract class InspectorControllerClient {
  void onChanged();

  void animateToTargets(List<InspectorTreeNode> targets);
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

  ItemPositionsListener _itemPositionsListener;

  InspectorTreeControllerFlutter get controller => widget.controller;

  bool get isSummaryTree => widget.isSummaryTree;

  ItemScrollController _scrollControllerY;
  ScrollController _scrollControllerX;
  Future<void> currentAnimateY;
  Rect currentAnimateTarget;

  AnimationController constraintDisplayController;

  @override
  void initState() {
    super.initState();
    _scrollControllerX = ScrollController();
    _scrollControllerY = ItemScrollController();
    _itemPositionsListener = ItemPositionsListener.create();

    if (isSummaryTree) {
      constraintDisplayController = longAnimationController(this);
    }
    _itemPositionsListener.itemPositions.addListener(_onScrollYChange);
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
    constraintDisplayController?.dispose();
  }

  void _onScrollYChange() {
    if (controller == null) return;

    // If the vertical position  is already being animated we should not trigger
    // a new animation of the horizontal position as a more direct animation of
    // the horizontal position has already been triggered.
    if (currentAnimateY != null) return;

    final positions = _itemPositionsListener.itemPositions.value;
    final x = _computeTargetX(positions);
    _scrollControllerX.animateTo(
      x,
      duration: defaultDuration,
      curve: defaultCurve,
    );
  }

  /// Compute the goal x scroll given a y scroll value.
  ///
  /// This enables animating the x scroll as the y scroll changes which helps
  /// keep the relevant content in view while scrolling a large list.
  double _computeTargetX(Iterable<ItemPosition> visibleRows) {
    double requiredOffset;
    double minOffset = double.infinity;
    // TODO(jacobr): use maxOffset as well to better handle the case where the
    // previous row has a significantly larger indent.

    if (visibleRows.isEmpty) {
      return 0;
    }
    for (ItemPosition visibleRow in visibleRows) {
      final row = controller.getCachedRow(visibleRow.index);
      if (row == null) continue;
      // TODO(jacobr)
      final rowOffset = controller.getRowOffset(visibleRow.index);
      if (row.isSelected) {
        requiredOffset = rowOffset;
      }
      minOffset = min(minOffset, rowOffset);
    }
    if (requiredOffset == null) {
      return minOffset;
    }

    return minOffset;
  }


  @override
  void animateToTargets(List<InspectorTreeNode> targets) {
    final Set<InspectorTreeNode> visible = Set.identity();

    for (var position in _itemPositionsListener.itemPositions.value) {
      final row = controller.getCachedRow(position.index);
      if (position.itemLeadingEdge >= 0 && position.itemTrailingEdge <= 1) {
        if (row != null && row.node != null) {
          visible.add(row.node);
        }
      }
    }

    int firstIndex = maxJsInt;
    for (var target in targets) {
      if (!visible.contains(target)) {
        firstIndex = min(firstIndex, controller.getRowForNode(target).index);
      }
    }
    if (firstIndex != maxJsInt) {
      _scrollControllerY.scrollTo(index: firstIndex, duration: longDuration);
    }
  }

  void _bindToController() {
    controller?.client = this;
  }

  @override
  void onChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (controller == null) {
      // Indicate the tree is loading.
      return const Center(child: CircularProgressIndicator());
    }

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: _scrollControllerX,
        child: SizedBox(
          width: controller.rowWidth + controller.maxRowIndent,
          child: Scrollbar(
            child: ScrollablePositionedList.builder(
              itemBuilder: (context, index) {
                final InspectorTreeRow row = controller.getCachedRow(index);
                return _InspectorTreeRowWidget(
                  key: PageStorageKey(row?.node),
                  inspectorTreeState: this,
                  row: row,
                );
              },
              itemPositionsListener: _itemPositionsListener,
              itemCount: controller.numRows,
              itemScrollController: _scrollControllerY,
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

final _defaultPaint = Paint()
// TODO(kenz): try to use color from Theme.of(context) for treeGuidelineColor
  ..color = treeGuidelineColor
  ..strokeWidth = chartLineStrokeWidth;

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
  _RowPainter(this.row, this._controller);

  final InspectorTreeController _controller;
  final InspectorTreeRow row;

  @override
  void paint(Canvas canvas, Size size) {
    double currentX = 0;

    if (row == null) {
      return;
    }
    final InspectorTreeNode node = row.node;
    final bool showExpandCollapse = node.showExpandCollapse;
    for (int tick in row.ticks) {
      currentX = _controller.getDepthIndent(tick) - columnWidth * 0.5;
      // Draw a vertical line for each tick identifying a connection between
      // an ancestor of this node and some other node in the tree.
      canvas.drawLine(
        Offset(currentX, 0.0),
        Offset(currentX, rowHeight),
        _defaultPaint,
      );
    }
    // If this row is itself connected to a parent then draw the L shaped line
    // to make that connection.
    if (row.lineToParent) {
      final paint = _defaultPaint;
      currentX = _controller.getDepthIndent(row.depth - 1) - columnWidth * 0.5;
      final double width = showExpandCollapse ? columnWidth * 0.5 : columnWidth;
      canvas.drawLine(
        Offset(currentX, 0.0),
        Offset(currentX, rowHeight * 0.5),
        paint,
      );
      canvas.drawLine(
        Offset(currentX, rowHeight * 0.5),
        Offset(currentX + width, rowHeight * 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    // TODO(jacobr): check whether the row has different ticks.
    return false;
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

    if (row == null) {
      return const SizedBox();
    }
    Color backgroundColor;
    if (row.isSelected || row.node == controller.hover) {
      backgroundColor =
          row.isSelected ? selectedRowBackgroundColor : hoverColor;
    }

    final node = row.node;
    return CustomPaint(
      painter: _RowPainter(row, controller),
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
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: backgroundColor,
                  ),
                  child: InkWell(
                    onTap: () {
                      controller.onSelectRow(row);
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
      ),
    );
  }
}
