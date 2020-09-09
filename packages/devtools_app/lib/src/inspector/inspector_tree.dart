// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Inspector specific tree rendering support.
library inspector_tree;

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Interval;
import 'package:meta/meta.dart';

import '../auto_dispose.dart';
import '../config_specific/logger/logger.dart';
import '../extent_delegate_list.dart';
import '../geometry.dart';
import '../ui/theme.dart';
import '../utils.dart';
import 'diagnostics_node.dart';
import 'inspector_controller.dart';
import 'inspector_service.dart';
import 'inspector_tree_oracle.dart';

/// Split text into two groups, word characters at the start of a string and all
/// other characters.
final RegExp treeNodePrimaryDescriptionPattern = RegExp(r'^([\w ]+)(.*)$');
// TODO(jacobr): temporary workaround for missing structure from assertion thrown building
// widget errors.
final RegExp assertionThrownBuildingError = RegExp(
    r'^(The following assertion was thrown building [a-zA-Z]+)(\(.*\))(:)$');

typedef TreeEventCallback = void Function(InspectorTreeNode node);

// TODO(jacobr): merge this scheme with other color schemes in DevTools.
extension InspectorColorScheme on ColorScheme {
  Color get selectedRowBackgroundColor => isLight
      ? const Color.fromARGB(255, 202, 191, 69)
      : const Color.fromARGB(255, 99, 101, 103);

  Color get hoverColor =>
      isLight ? Colors.yellowAccent : const Color.fromARGB(255, 70, 73, 76);
}

const double iconPadding = 5.0;
const double chartLineStrokeWidth = 1.0;
const double columnWidth = 16.0;
const double verticalPadding = 10.0;
const double rowHeight = 24.0;
const double horizontalPadding = 10.0;

double indentForDepth(num depth) {
  return (depth.toDouble() + 1) * columnWidth + horizontalPadding;
}

/// This class could be refactored out to be a reasonable generic collapsible
/// tree ui node class but we choose to instead make it widget inspector
/// specific as that is the only case we care about.
// TODO(kenz): extend TreeNode class to share tree logic.
class InspectorTreeNode {
  InspectorTreeNode({
    InspectorTreeNode parent,
    bool expandChildren = true,
  })  : _children = <InspectorTreeNode>[],
        _parent = parent,
        _isExpanded = expandChildren;

  bool get showLinesToChildren {
    final childrenFiltered = this.childrenFiltered;
    return childrenFiltered.length > 1 && !childrenFiltered.last.isProperty;
  }

  // Set the filter for a node and all its children.
  set showTest(bool Function(InspectorTreeNode node) value) {
    if (_showTest == value) return;
    _showTest = value;
    isDirty = true;
    for (var child in _children) {
      child.showTest = value;
    }
  }

  bool Function(InspectorTreeNode node) _showTest;

  /*
  bool Function(InspectorTreeNode node) get where {
    if (_where == null) {
      if (parent == null) {
        _where = (InspectorTreeNode node) => true;
      } else {
        _where = parent.where;
      }
    }
    return _where;
  }*/

  bool get isDirty => _isDirty;
  bool _isDirty = true;

  set isDirty(bool dirty) {
    if (dirty) {
      _isDirty = true;
      _shouldShow = null;
      _childrenFiltered = null;
      if (parent != null) {
        parent.isDirty = true;
      }
    } else {
      _isDirty = false;
    }
  }

  /// Returns whether the node is currently visible in the tree.
  void updateShouldShow(bool value) {
    if (value != _shouldShow) {
      _shouldShow = value;
      for (var child in _children) {
        child.updateShouldShow(value);
      }
    }
  }

  bool get shouldShow {
    _shouldShow ??= parent == null || parent.isExpanded && parent.shouldShow;
    return _shouldShow;
  }

  bool _shouldShow;

  bool selected = false;

  RemoteDiagnosticsNode _diagnostic;
  final List<InspectorTreeNode> _children;

  List<InspectorTreeNode> _childrenFiltered;

  @deprecated
  Iterable<InspectorTreeNode> get children => _children;

  Iterable<InspectorTreeNode> get childrenRaw => _children;

  void _addFilteredChildren(List<InspectorTreeNode> filteredChildren) {
    for (var child in _children) {
      if (child.isFiltered) {
        child._addFilteredChildren(filteredChildren);
      } else {
        filteredChildren.add(child);
      }
    }
  }

  List<InspectorTreeNode> get childrenFiltered {
    if (_childrenFiltered == null) {
      if (_showTest == null) {
        _childrenFiltered = _children;
      } else {
        _childrenFiltered = [];
        _addFilteredChildren(_childrenFiltered);
      }
    }
    return _childrenFiltered;
  }

  bool get isCreatedByLocalProject => _diagnostic.isCreatedByLocalProject;

  bool get isProperty => diagnostic == null || diagnostic.isProperty;

  bool get isExpanded => _isExpanded;
  bool _isExpanded;

  bool allowExpandCollapse = true;

  bool get showExpandCollapse {
    return (childrenFiltered.isNotEmpty ||
            (diagnostic != null &&
                !diagnostic.childrenAvailableNow &&
                diagnostic.maybeHasChildren)) &&
        allowExpandCollapse;
  }

  set isExpanded(bool value) {
    if (value != _isExpanded) {
      final bool updateChildren = _shouldShow ?? false;
      _isExpanded = value;
      isDirty = true;
      if (updateChildren) {
        for (var child in childrenFiltered) {
          child.updateShouldShow(value);
        }
      }
    }
  }

  InspectorTreeNode get parent => _parent;
  InspectorTreeNode _parent;

  set parent(InspectorTreeNode value) {
    _parent = value;
    _parent?.isDirty = true;
  }

  RemoteDiagnosticsNode get diagnostic => _diagnostic;

  set diagnostic(RemoteDiagnosticsNode v) {
    _diagnostic = v;
    _isExpanded = v.childrenReady;
    isDirty = true;
  }

  bool get hasPlaceholderChildren {
    final childrenFiltered = this.childrenFiltered;
    return childrenFiltered.length == 1 &&
        childrenFiltered.first.diagnostic == null;
  }

  bool get isFiltered => parent != null && !_showTest(this);

  bool get isLeaf => _children.isEmpty;

  void removeChild(InspectorTreeNode child) {
    child.parent = null;
    final removed = _children.remove(child);
    assert(removed != null);
    isDirty = true;
  }

  void appendChild(InspectorTreeNode child) {
    _children.add(child);
    child.parent = this;
    child.showTest = _showTest;
    isDirty = true;
  }

  void clearChildren() {
    _children.clear();
    isDirty = true;
  }
}

/// A row in the tree with all information required to render it.
class InspectorTreeRow {
  InspectorTreeRow({
    @required this.node,
    @required this.index,
    @required this.depth,
    @required this.lineToParent,
    @required this.parent,
    @required this.filteredChildren,
    @required this.oracle,
    @required this.lineToChildren,
  }) : showExpandCollapse = node.showExpandCollapse;

  @override
  bool operator ==(Object other) {
    if (other is InspectorTreeRow) {
      return equalsIgnoringIndex(other) && index == other.index;
    }
    return false;
  }

  bool equalsIgnoringIndex(InspectorTreeRow other) {
    if (other == null) return false;
    return depth == other.depth &&
        depth == other.depth &&
        lineToParent == other.lineToParent &&
        node == other.node;
  }

  @override
  int get hashCode => hashValues(
        depth,
        index,
        lineToParent,
        node,
      );

  final int depth;
  final int index;

  /// Index within a merged animated list of rows.
  ///
  /// This index is only useful for comparing which rows come before which rows
  /// as post filtering may be done to the animation that removes rows that are
  /// not fully required.
  int animatedIndex;
  int filteredAnimatedIndex;
  bool get inFilteredAnimation => filteredAnimationRow != null;

  /// AnimatedRow containing this row in the currently active animation.
  ///
  /// Not all rows will be included in the filtered animation so this may be
  /// null for a row that should eventually be displayed.
  AnimatedRow filteredAnimationRow;

  final bool lineToParent;
  final InspectorTreeNode node;
  final InspectorTreeRow parent;
  final TreeStructureOracle oracle;
  final List<InspectorTreeRow> filteredChildren;
  final bool lineToChildren;
  final bool showExpandCollapse;

  bool get isSelected => node.selected;
}

/// Callback issued every time a node is added to the tree.
typedef NodeAddedCallback = void Function(
    InspectorTreeNode node, RemoteDiagnosticsNode diagnosticsNode);

class VisibleRange {
  const VisibleRange(this.first, this.last);

  final InspectorTreeNode first;
  final InspectorTreeNode last;
}

class InspectorTreeConfig {
  InspectorTreeConfig({
    @required this.summaryTree,
    @required this.treeType,
    @required this.onNodeAdded,
    this.onClientActiveChange,
    this.onSelectionChange,
    this.onExpand,
    this.onHover,
  });

  final bool summaryTree;
  final FlutterTreeType treeType;
  final NodeAddedCallback onNodeAdded;
  final VoidCallback onSelectionChange;
  final void Function(bool added) onClientActiveChange;
  final TreeEventCallback onExpand;
  final TreeEventCallback onHover;
}

final alwaysVisible = Tween<double>(begin: 1.0, end: 1.0);
final tweenIn = Tween<double>(begin: 0.0, end: 1.0);
final tweenOut = Tween<double>(begin: 1.0, end: 0.0);

enum AnimationComparison {
  /// The two animations are the same.
  equal,

  /// One animation is the reverse of the other animation.
  reverse,

  /// The two animations are different.
  different,
}

abstract class AnimatedLine {
  AnimatedLine(this.rowIndex, this._opacityTween);

  final int rowIndex;
  final Tween<double> _opacityTween;

  LineSegment toLineSegment(
    Rect visibleRect,
    Animation<double> animation,
    ExtentDelegate extentDelegate,
  );

  double opacity(Animation<double> visibilityAnimation) {
    if (_opacityTween == null) return 1.0;
    return _opacityTween.transform(visibilityAnimation.value);
  }
}

class AnimatedHorizontalLine extends AnimatedLine
    implements Comparable<AnimatedHorizontalLine> {
  AnimatedHorizontalLine({
    @required this.startDepth,
    @required this.endDepth,
    @required int rowIndex,
    Tween<double> opacityTween,
  }) : super(rowIndex, opacityTween);

  final Tween<double> startDepth;
  final Tween<double> endDepth;

  @override
  int compareTo(AnimatedHorizontalLine other) {
    return rowIndex.compareTo(other.rowIndex);
  }

  @override
  LineSegment toLineSegment(
    Rect visibleRect,
    Animation<double> animation,
    ExtentDelegate extentDelegate,
  ) {
    final xStart =
        max(visibleRect.left, indentForDepth(startDepth.evaluate(animation)));
    final xEnd =
        min(visibleRect.right, indentForDepth(endDepth.evaluate(animation)));
    if (xEnd < xStart) return null;

    final y = extentDelegate.layoutOffset(rowIndex) +
        extentDelegate.itemExtent(rowIndex) * 0.5;

    if (y < visibleRect.top || y > visibleRect.bottom) return null;
    return HorizontalLineSegment(
      Offset(xStart, y),
      Offset(xEnd, y),
      opacity: opacity(animation),
    );
  }
}

// Vertical line with offsets described in terms of rows and fractional rows
// rather than absolute coordinates.
class AnimatedVerticalLine extends AnimatedLine {
  AnimatedVerticalLine({
    @required this.rowStart,
    @required int rowEnd,
    @required this.rowEndFraction,
    @required this.depth,
    Tween<double> opacityTween,
  }) : super(rowEnd, opacityTween);

  /// Index of the row the vertical line starts at.
  final int rowStart;
  int get rowEnd => rowIndex;

  /// Fraction of the way down the ending row that the end of the line segment
  /// is at.
  final double rowEndFraction;

  final Tween<double> depth;

  bool isVisible(int firstVisible, int lastVisible) {
    return rowEnd >= firstVisible && rowStart <= lastVisible;
  }

  @override
  LineSegment toLineSegment(
    Rect visibleRect,
    Animation<double> animation,
    ExtentDelegate extentDelegate,
  ) {
    final yStart = max(visibleRect.top, extentDelegate.layoutOffset(rowStart));
    final yEnd = min(
        visibleRect.bottom,
        extentDelegate.layoutOffset(rowEnd) +
            extentDelegate.itemExtent(rowEnd) * rowEndFraction);
    if (yStart >= yEnd) return null;

    final x = indentForDepth(depth.evaluate(animation));

    if (x < visibleRect.left || x > visibleRect.right) return null;
    return VerticalLineSegment(
      Offset(x, yStart),
      Offset(x, yEnd),
      opacity: opacity(animation),
    );
  }
}

const rowIndexOffset = 1;

extension TweenUtil on Tween<double> {
  Tween<double> translate(double delta) {
    return Tween(begin: begin + delta, end: end + delta);
  }
}

/// Model that tracks what lines should be drawn between parent and child rows.
class TreeStructureLineModel {
  TreeStructureLineModel({
    @required List<AnimatedRow> allRows,
  }) {
    final rawVerticalLines = <AnimatedVerticalLine>[];
    final rawHorizontalLines = <AnimatedHorizontalLine>[];

    // We need to draw vertical lines for all rows even for rows filtered out of
    // the animation because while the specific row the vertical line starts out
    // maybe be filtered out as it isn't visible when the animation starts and
    // ends, its descendants may be visible so the line segment needs to be
    // drawn.
    for (var row in allRows) {
      // Most rows don't have a line to children so optimize by bailing early.
      if ((row.last?.lineToChildren ?? false) ||
          (row.current?.lineToChildren ?? false)) {
        if (row.isSameNode &&
            row.last.lineToChildren == row.current.lineToChildren &&
            row.last.filteredChildren.last.index ==
                row.current.filteredChildren.last.index) {
          _addVerticalLineForRow(
            row.last,
            row,
            alwaysVisible,
            rawVerticalLines,
            rawHorizontalLines,
          );
        } else {
          if (row.last != null) {
            _addVerticalLineForRow(
              row.last,
              row,
              tweenOut,
              rawVerticalLines,
              rawHorizontalLines,
            );
          }
          if (row.current != null) {
            _addVerticalLineForRow(
              row.current,
              row,
              tweenIn,
              rawVerticalLines,
              rawHorizontalLines,
            );
          }
        }
      }
    }
    // Ensure horizontal lines are in ascending row order to optimize painting.
    rawHorizontalLines.sort();

    // We may end up with overlapping line segments on of which is fading in and
    // one is fading out. For these cases we should instead have one line
    // segment that is always present to avoid noticeable flicker due to how
    // alpha values are combined. If there was a way to combine the alpha values
    // more additively this code could be removed as the performance
    // optimization of reducing the # of line segments is not important.

    {
      AnimatedHorizontalLine last;
      // Merge pairs of tween in and tween out that are equal to avoid flicker
      // due to blending a tween
      for (var current in rawHorizontalLines) {
        if (last != null) {
          if (last.rowIndex == current.rowIndex &&
              equalTween(last.startDepth, current.startDepth) &&
              equalTween(last.endDepth, current.endDepth) &&
              isTweenInOut(last._opacityTween, current._opacityTween)) {
            // merge.
            _horizontalLines.add(AnimatedHorizontalLine(
                startDepth: last.startDepth,
                endDepth: last.endDepth,
                rowIndex: last.rowIndex,
                opacityTween: alwaysVisible));
            last = null;
          } else {
            // TODO(jacobr): we could handle more complex horizontal line
            // intersection as well but the flicker is only really noticeable
            // for the simple case.
            _horizontalLines.add(last);
            last = current;
          }
        } else {
          last = current;
        }
      }
      if (last != null) {
        _horizontalLines.add(last);
      }
    }

    {
      // Ensure vertical line segments are in order to find segments that start
      // with the same depth. We do not rely on the order of the vertical line
      // segments to optimize painting as we would need to use intersection sets
      // to do that efficiently.
      rawVerticalLines.sort((AnimatedVerticalLine a, AnimatedVerticalLine b) {
        // Ensure that rows are sorted by rowIndex and for rows with the same row
        // index the row with the larger end index is sorted last. We sort by depth
        // as well to ensure rows with the same depth are next to each other.
        var delta = a.rowIndex.compareTo(b.rowIndex);
        if (delta != 0) return delta;

        delta = a.depth.begin.compareTo(b.depth.begin);
        if (delta != 0) return delta;
        delta = a.depth.end.compareTo(b.depth.end);
        if (delta != 0) return delta;

        delta = a.rowEnd.compareTo(b.rowEnd);
        if (delta != 0) return delta;
        return a.rowEndFraction.compareTo(b.rowEndFraction);
      });
      AnimatedVerticalLine last;
      // Merge pairs of tween in and tween out that are equal to avoid flicker
      // due to blending a tween
      for (var current in rawVerticalLines) {
        if (last != null) {
          if (last.rowIndex == current.rowIndex &&
              equalTween(last.depth, current.depth) &&
              isTweenInOut(last._opacityTween, current._opacityTween)) {
            // merge.
            _verticalLines.add(AnimatedVerticalLine(
              rowStart: last.rowStart,
              rowEnd: last.rowEnd,
              rowEndFraction: last.rowEndFraction,
              depth: last.depth,
              opacityTween: alwaysVisible,
            ));
            if (last.rowEnd != current.rowEnd ||
                last.rowEndFraction != current.rowEndFraction) {
              assert(current.rowEnd > last.rowEnd ||
                  current.rowEndFraction >= last.rowEndFraction);
              _verticalLines.add(AnimatedVerticalLine(
                rowStart: last.rowEnd,
                rowEnd: current.rowEnd,
                rowEndFraction: current.rowEndFraction,
                depth: current.depth,
                opacityTween: alwaysVisible,
              ));
            }
            last = null;
          } else {
            _verticalLines.add(last);
            last = current;
          }
        } else {
          last = current;
        }
      }
      if (last != null) {
        _verticalLines.add(last);
      }
    }
  }

  /// Returns if one transition is a tween in and the other is a tween out.
  bool isTweenInOut(Tween<double> a, Tween<double> b) {
    return (a == tweenIn && b == tweenOut) || (a == tweenOut && b == tweenIn);
  }

  bool equalTween(Tween<double> a, Tween<double> b) {
    return a.begin == b.begin && a.end == b.end;
  }

  final List<AnimatedVerticalLine> _verticalLines = [];
  final List<AnimatedHorizontalLine> _horizontalLines = [];

  void _addVerticalLineForRow(
    InspectorTreeRow row,
    AnimatedRow animatedRow,
    Tween<double> opacityTween,
    List<AnimatedVerticalLine> rawVerticalLines,
    List<AnimatedHorizontalLine> rawHorizontalLines,
  ) {
    if (!row.lineToChildren) return;
    final rowStart = row.filteredAnimatedIndex + 1 + rowIndexOffset;
    final lastChild = row.filteredChildren.last;
    final rowEnd = lastChild.filteredAnimatedIndex + rowIndexOffset;
    if (rowEnd < rowStart) {
      // The line will never be visible given how the animation is filtered.
      return;
    }
    // Only draw the line segment to the middle of the row of the last child if
    // the last child is actually visible in the animation.
    final rowEndFraction = lastChild.inFilteredAnimation ? 0.5 : 0.0;

    final lineDepth = animatedRow.depth.translate(-0.5);
    rawVerticalLines.add(AnimatedVerticalLine(
      rowStart: rowStart,
      rowEnd: rowEnd,
      rowEndFraction: rowEndFraction,
      depth: lineDepth,
      opacityTween: opacityTween,
    ));
    for (var child in row.filteredChildren) {
      // Only horizontal lines for rows visible in the filtered animation
      // matter
      if (child.inFilteredAnimation) {
        _addHorizontalLineForRow(
          child,
          lineDepth,
          opacityTween,
          rawHorizontalLines,
        );
      }
    }
  }

  void _addHorizontalLineForRow(
    InspectorTreeRow row,
    Tween<double> startDepth,
    Tween<double> opacityTween,
    List<AnimatedHorizontalLine> rawHorizontalLines,
  ) {
    if (!row.lineToParent) return;
    final animatedRow = row.filteredAnimationRow;
    assert(animatedRow != null);
    // Only draw the line segment to the middle of the row of the last child if
    // the last child is actually visible in the animation.
    final rowDepth = animatedRow.depth;
    final lastRow = animatedRow.last ?? row;
    final currentRow = animatedRow.current ?? row;

    rawHorizontalLines.add(AnimatedHorizontalLine(
      startDepth: startDepth,
      endDepth: Tween<double>(
        begin: rowDepth.begin - (lastRow.showExpandCollapse ? 1.0 : 0.5),
        end: rowDepth.end - (currentRow.showExpandCollapse ? 1.0 : 0.5),
      ),
      rowIndex: row.filteredAnimatedIndex + rowIndexOffset,
      opacityTween: opacityTween,
    ));
  }

  Iterable<LineSegment> visibleLines(
      Rect visibleRect,
      ExtentDelegate extentDelegate,
      Animation<double> animation,
      InspectorTreeController inspectorTreeController) {
    final startRow =
        extentDelegate.minChildIndexForScrollOffset(visibleRect.top);
    final endRow =
        extentDelegate.maxChildIndexForScrollOffset(visibleRect.bottom);
    // TODO(jacobr): optimize this ideally with an IntersectionTree for cheap
    // queries to find all lines matching the interval.
    final visible = <LineSegment>[];
    void _maybeAddLine(AnimatedLine line) {
      final candidate =
          line.toLineSegment(visibleRect, animation, extentDelegate);
      if (candidate != null) {
        assert(candidate.intersects(visibleRect));
        visible.add(candidate);
      }
    }

    // TODO(jacobr): use an intersection tree to optimize finding vertical line
    // matches. Using lowerBound on a sorted list wouldn't help much as only
    // half the rows would be filtered out as you cannot terminate early because
    //
    for (var line in _verticalLines) {
      if (line.isVisible(startRow, endRow)) {
        _maybeAddLine(line);
      }
    }

    final firstHorizontalLineIndex = lowerBound(
        _horizontalLines,
        AnimatedHorizontalLine(
          startDepth: Tween(begin: 0.0, end: 0.0),
          endDepth: Tween(begin: 0.0, end: 0.0),
          rowIndex: startRow,
        ));

    for (var i = firstHorizontalLineIndex; i < _horizontalLines.length; ++i) {
      final line = _horizontalLines[i];
      if (line.rowIndex > endRow) break;
      _maybeAddLine(line);
    }
    return visible;
  }
}

class AnimatedRow {
  AnimatedRow({
    this.last,
    this.current,
    this.snapAnimationToEnd = false,
    @required TreeStructureOracle lastTreeStructure,
    @required TreeStructureOracle currentTreeStructure,
  })  : _lastTreeStructure = lastTreeStructure,
        _currentTreeStructure = currentTreeStructure,
        animateRow = !_isEquivalentRows(last, current);

  AnimatedRow.fixed(
    this.last, {
    @required TreeStructureOracle lastTreeStructure,
    @required TreeStructureOracle currentTreeStructure,
  })  : current = last,
        animateRow = false,
        snapAnimationToEnd = true,
        _lastTreeStructure = lastTreeStructure,
        _currentTreeStructure = currentTreeStructure;

  final InspectorTreeRow last;
  final InspectorTreeRow current;
  final TreeStructureOracle _lastTreeStructure;
  final TreeStructureOracle _currentTreeStructure;
  final bool animateRow;
  final bool snapAnimationToEnd;

  bool get isSameNode => identical(last?.node, current?.node);

  Tween<double> get depth {
    if (_depth == null) {
      final matchingLastAncestor = _lastTreeStructure
          .findFirstMatchingAncestor(current, expectedMatch: last);
      final matchingCurrentAncestor = _currentTreeStructure
          .findFirstMatchingAncestor(last, expectedMatch: current);

      _depth = Tween(
        begin: matchingLastAncestor.matchDepth.toDouble(),
        end: matchingCurrentAncestor.matchDepth.toDouble(),
      );
    }
    return _depth;
  }

  Tween<double> _depth;

  InspectorTreeNode get node => targetRow.node;

  InspectorTreeRow get targetRow => current != null ? current : last;

  bool get isSelected => targetRow?.isSelected ?? false;

  static bool _isEquivalentRows(
      InspectorTreeRow last, InspectorTreeRow current) {
    if (identical(last, current)) return true;
    if (last == null || current == null) return false;
    return last.equalsIgnoringIndex(current);
  }

  static bool isEquivalentAnimatedRows(AnimatedRow a, AnimatedRow b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return _isEquivalentRows(a.last, b.last) &&
        _isEquivalentRows(a.current, b.current);
  }

  /// Returns true if row a is the same as row b just with the reverse animation.
  static bool isReversedAnimatedRow(AnimatedRow a, AnimatedRow b) {
    if (a == null || b == null) return false;
    return _isEquivalentRows(a.last, b.current) &&
        _isEquivalentRows(a.current, b.last);
  }

  /// Compares the two animations.
  ///
  /// If the animations are the same, returns [AnimationComparison.equal]
  /// indicating that the previous animation can still be used and no real
  /// change has occurred.
  /// If the animations are the reverse of each other then returns
  /// [AnimationComparsion.reverse] which can help indicate when an animation
  /// should be run in reverse to smoothly undo an under way animation. For a
  /// reverse animation, all rows are the same except for 1 or more rows that
  /// are in reverse.
  ///
  /// Otherwise returns [AnimationComparison.different] and no assumptions
  /// should be made about whether the two animations are similar.
  static AnimationComparison compareAnimations(
      List<AnimatedRow> aRows, List<AnimatedRow> bRows) {
    AnimationComparison ret = AnimationComparison.equal;
    if (aRows == bRows) return AnimationComparison.equal;
    if (aRows == null || bRows == null) return AnimationComparison.different;
    if (aRows.length != bRows.length) return AnimationComparison.different;
    for (int i = 0; i < aRows.length; i++) {
      final aRow = aRows[i];
      final bRow = bRows[i];
      if (!AnimatedRow.isEquivalentAnimatedRows(aRow, bRow)) {
        if (AnimatedRow.isReversedAnimatedRow(aRow, bRow)) {
          ret = AnimationComparison.reverse;
        } else {
          return AnimationComparison.different;
        }
      }
    }
    return ret;
  }

  double animatedRowHeight(Animation<double> visibilityAnimation) {
    if (!animateRow) {
      return rowHeight;
    }
    if (snapAnimationToEnd && visibilityAnimation.value < 1) {
      return beginHeight;
    }
    return Tween<double>(begin: beginHeight, end: endHeight)
        .evaluate(visibilityAnimation);
  }

  /// Whether to ever show the expand collapse.
  bool get showExpandCollapse =>
      (last?.showExpandCollapse ?? false) ||
      (current?.showExpandCollapse ?? false);

  Tween<double> get expandCollapseTween {
    return Tween<double>(
      begin: last?.showExpandCollapse ?? false ? 1 : 0,
      end: current?.showExpandCollapse ?? false ? 1 : 0,
    );
  }

  double get beginHeight => last != null ? rowHeight : 0.0;

  double get endHeight => current != null ? rowHeight : 0.0;
}

abstract class InspectorTreeController extends DisposableController
    with AutoDisposeControllerMixin {
  InspectorTreeController(this.inspectorSettingsController);

  bool _showOnlyUserDefined = false;
  bool _expandSelectedBuildMethod = true;

  final InspectorSettingsController inspectorSettingsController;

  TreeStructureLineModel lineModel;

  // Abstract method defined to avoid a direct Flutter dependency.
  // TODO(jacobr): remove.
  @protected
  void setState(VoidCallback fn);

  InspectorTreeNode get root => _root;
  InspectorTreeNode _root;

  Set<InspectorTreeNode> _nodesToAlwaysShow = Set.identity();

  /// Compute the
  ///
  ///
  Set<InspectorTreeNode> _computeNodesToAlwaysShow(
      InspectorTreeNode selection) {
    final Set<InspectorTreeNode> alwaysShow = Set.identity();
    void computeNodesToNeverFilterHelper(InspectorTreeNode node) {
      if (node == null || alwaysShow.contains(node) || _rawShowTest(node))
        return;
      alwaysShow.add(node);
      computeNodesToNeverFilterHelper(node.parent);
      node.childrenRaw.forEach(computeNodesToNeverFilterHelper);
    }

    if (selection != null) {
      computeNodesToNeverFilterHelper(selection);
      if (_expandSelectedBuildMethod) {
        // Show all children of the node even if the node itself isn't selected.
        selection.childrenRaw.forEach(computeNodesToNeverFilterHelper);
      }
    }
    return alwaysShow;
  }

  set root(InspectorTreeNode node) {
    setState(() {
      _root = node;
      _updateFilter(true);
    });
  }

  void _updateFilter(bool updateSelection) {
    updateSelection = false;
    if (updateSelection) {
      var firstVisible = _selection;
      while (firstVisible != null && !_rawShowTest(firstVisible)) {
        firstVisible = firstVisible.parent;
      }
      if (firstVisible != null && firstVisible != _selection) {
        selection = firstVisible;
      }
    }

    final nodesToAlwaysShow = _computeNodesToAlwaysShow(selection);
    _nodesToAlwaysShow = nodesToAlwaysShow;
    _root.showTest = (InspectorTreeNode node) {
      return _rawShowTest(node) || nodesToAlwaysShow.contains(node);
    };
  }

  /// Whether a node should be shown without factoring in the set of nodes to
  /// always show.
  bool _rawShowTest(InspectorTreeNode node) {
    if (!_showOnlyUserDefined) return true;
    return node.diagnostic.isLocalClass;
  }

  RemoteDiagnosticsNode subtreeRoot; // Optional.

  InspectorTreeNode get selection => _selection;
  InspectorTreeNode _selection;

  InspectorTreeConfig get config => _config;
  InspectorTreeConfig _config;

  set config(InspectorTreeConfig value) {
    // Only allow setting config once.
    assert(_config == null);
    _config = value;
    if (config.summaryTree) {
      addAutoDisposeListener(inspectorSettingsController.showOnlyUserDefined,
          () {
        setState(() {
          if (_showOnlyUserDefined !=
              inspectorSettingsController.showOnlyUserDefined.value) {
            _showOnlyUserDefined =
                inspectorSettingsController.showOnlyUserDefined.value;
            _updateFilter(true);
          }
        });
      });

      addAutoDisposeListener(
          inspectorSettingsController.expandSelectedBuildMethod, () {
        setState(() {
          if (_expandSelectedBuildMethod !=
              inspectorSettingsController.expandSelectedBuildMethod.value) {
            _expandSelectedBuildMethod =
                inspectorSettingsController.expandSelectedBuildMethod.value;
            _updateFilter(true);
          }
        });
      });
    }
  }

  set selection(InspectorTreeNode node) {
    if (node == _selection) return;

    setState(() {
      _selection?.selected = false;
      _selection = node;
      _selection?.selected = true;
      if (node != null &&
          !setEquals(_computeNodesToAlwaysShow(node), _nodesToAlwaysShow)) {
        // Update the filter so that the selected node is not filtered.
        _updateFilter(false);
      }
      if (config.onSelectionChange != null) {
        config.onSelectionChange();
      }
    });
  }

  InspectorTreeNode get hover => _hover;
  InspectorTreeNode _hover;

  int get maxDepth {
    _syncCache();
    return _maxDepth;
  }

  int _maxDepth;

  InspectorTreeNode createNode();

  List<InspectorTreeRow> _cachedRows = const [];
  List<InspectorTreeRow> _lastCachedRows = const [];

  void _syncCache() {
    if (root?.isDirty ?? false) {
      _lastCachedRows = _cachedRows;
      _cachedRows = const [];
      root.isDirty = false;
      _animatedRows = const [];
      _rawAnimatedRows = const [];
    }
    if (_cachedRows.isEmpty) {
      _lastTreeStructure = _currentTreeStructure;
      _currentTreeStructure = TreeStructureOracle();
      _cachedRows = [];
      _maxDepth = 0;
      if (_root != null) {
        _computeRows(_root, null, 0, _currentTreeStructure);
      }
    }
    if (_rawAnimatedRows.isEmpty) {
      _rawAnimatedRows = [];
      _animatedRows = _rawAnimatedRows;
      _animatedRowsAfter = [
        for (var row in _cachedRows)
          AnimatedRow.fixed(
            row,
            lastTreeStructure: _lastTreeStructure,
            currentTreeStructure: _currentTreeStructure,
          )
      ];

      var lastIndex = 0;
      var index = 0;
      while (lastIndex < _lastCachedRows.length || index < _cachedRows.length) {
        final row = _cachedRows.safeGet(index);
        final oldRow = _lastCachedRows.safeGet(lastIndex);
        if (row == null ||
            oldRow == null ||
            _currentTreeStructure.matchingNodes(row.node, oldRow.node)) {
          _rawAnimatedRows.add(AnimatedRow(
            last: oldRow,
            current: row,
            lastTreeStructure: _lastTreeStructure,
            currentTreeStructure: _currentTreeStructure,
          ));
          // It is fine that we increment the indexes past the end of the cache
          // for the case where we are out of rows.
          lastIndex++;
          index++;
        } else {
          // We optimize for the common case where changes are mainly additions
          // or subtractions. if a none is reordered, we will treat it as
          // animating out in the old position and animating back in at the
          // new position as reorders are not the common use case for changes
          // made to the tree.
          final lastInCurrent = _currentTreeStructure.containsNode(oldRow.node);
          final onlyInLast = !lastInCurrent;
          final currentInLast = _lastTreeStructure.containsNode(row.node);
          final onlyInCurrent = !currentInLast;
          final inBothTrees = lastInCurrent && currentInLast;
          if (onlyInLast || inBothTrees) {
            // The row from the last tree is not in the current tree or it is in
            // both trees but the change between trees includes reorders rather
            // than simple additions and subtractions.
            _rawAnimatedRows.add(AnimatedRow(
              last: oldRow,
              lastTreeStructure: _lastTreeStructure,
              currentTreeStructure: _currentTreeStructure,
            ));
            lastIndex++;
          } else if (onlyInCurrent) {
            _rawAnimatedRows.add(AnimatedRow(
              current: row,
              lastTreeStructure: _lastTreeStructure,
              currentTreeStructure: _currentTreeStructure,
            ));
            index++;
          }
        }
      }
    }
  }

  List<InspectorTreeRow> get lastRows {
    _syncCache();
    return _lastCachedRows;
  }

  List<InspectorTreeRow> get rows {
    _syncCache();
    return _cachedRows;
  }

  /// Animated rows before any post processing occurred.
  ///
  /// Post processing may filter out rows that aren't visible at the start or
  /// end of the animation so don't need to be lincluded.
  List<AnimatedRow> get rawAnimatedRows {
    _syncCache();
    return _rawAnimatedRows;
  }

  List<AnimatedRow> _rawAnimatedRows = [];

  List<AnimatedRow> get animatedRows {
    _syncCache();
    return _animatedRows;
  }

  List<AnimatedRow> _animatedRows = [];

  /// Animated rows after the animation completes.
  List<AnimatedRow> get animatedRowsAfterAnimation {
    _syncCache();
    return _animatedRowsAfter;
  }

  List<AnimatedRow> _animatedRowsAfter = [];

  AnimationController animationController;

  TreeStructureOracle get currentTreeStructure => _currentTreeStructure;
  TreeStructureOracle _currentTreeStructure = TreeStructureOracle();
  TreeStructureOracle _lastTreeStructure = TreeStructureOracle();

  @deprecated
  InspectorTreeRow getCachedRow(int index) {
    _syncCache();
    if (_cachedRows.length <= index) return null;
    return _cachedRows[index];
  }

  InspectorTreeRow _computeRows(
    InspectorTreeNode node,
    InspectorTreeRow parent,
    int depth,
    TreeStructureOracle oracle,
  ) {
    final style = node.diagnostic?.style;
    final bool indented = style != DiagnosticsTreeStyle.flat &&
        style != DiagnosticsTreeStyle.error;
    final index = _cachedRows.length;
    final List<InspectorTreeNode> children =
        node.isExpanded ? node.childrenFiltered : const [];
    final rowChildren = <InspectorTreeRow>[];
    final row = InspectorTreeRow(
      node: node,
      index: index,
      depth: depth,
      lineToParent:
          !node.isProperty && parent != null && parent.node.showLinesToChildren,
      parent: parent,
      filteredChildren: rowChildren,
      lineToChildren: children.length > 1 &&
          !children.last.isProperty &&
          indented &&
          !node.isFiltered,
      oracle: oracle,
    );
    _cachedRows.add(row);
    _currentTreeStructure.trackRow(row);

    if (indented) {
      depth++;
      if (depth > _maxDepth) {
        _maxDepth = depth;
      }
    }

    for (var child in children) {
      rowChildren.add(_computeRows(child, row, depth, oracle));
    }
    return row;
  }

  void optimizeRowAnimation({
    @required VisibleRange currentVisibleRange,
    @required Set<AnimatedRow> rowsToAnimateOut,
  }) {
    // Strip out animations at are animating nodes that are not actually in
    // view.
    // TODO(jacobr): consider providing an option to enable animations for nodes
    // slightly outside of view as the difference in handling of outside and
    // inside of view animations could be a little jarring at times.

    bool withinDestinationVisibleRange = false;

    final simplifiedRows = <AnimatedRow>[];
    /* if (lastVisibleRange.first == null) {
      // No rows were visible previously so no need to perform any animation.
      for (final row in animatedRows) {
        if (row.current != null) {
          simplifiedRows.add(AnimatedRow.fixed(
            row.current,
            lastTreeStructure: _lastTreeStructure,
            currentTreeStructure: _currentTreeStructure,
          ));
        }
      }
    } else */
    {
      // We have now reached the first previously visible row.
      for (int i = 0; i < animatedRows.length; ++i) {
        final row = animatedRows[i];
        if (row.current != null &&
            row.current.node == currentVisibleRange.first) {
          withinDestinationVisibleRange = true;
        }

        if ((row.current == null && row.last != null) &&
            !rowsToAnimateOut.contains(row)) {
          // Omit the previous row as it is hidden at the end of the animation
          // and not visible at the start of the animation.
        } else if (!withinDestinationVisibleRange && row.last == null) {
          // The row won't be on screen when the animation completes and isn't
          // visible when the animation starts so avoid showing it while the
          // animation is in progress.
          simplifiedRows.add(
            AnimatedRow(
              last: row.last,
              current: row.current,
              snapAnimationToEnd: true,
              lastTreeStructure: _lastTreeStructure,
              currentTreeStructure: _currentTreeStructure,
            ),
          );
        } else {
          simplifiedRows.add(row);
        }
        if (row.current != null &&
            row.current.node == currentVisibleRange.last) {
          withinDestinationVisibleRange = false;
        }
      }
    }

    void setupAnimatedIndex(InspectorTreeRow row, int index) {
      if (row == null) return;
      row
        ..animatedIndex = index
        ..filteredAnimatedIndex = null
        ..filteredAnimationRow = null;
    }

    for (int i = 0; i < _animatedRows.length; ++i) {
      final row = _animatedRows[i];
      setupAnimatedIndex(row.last, i);
      setupAnimatedIndex(row.current, i);
    }
    final filteredRows = <AnimatedRow>[];
    for (var row in simplifiedRows) {
      // Including a large number of snap to end rows in the animation causes
      // performance problems for large widget trees where most nodes are
      // filtered out.
      if (row.beginHeight > 0 || !row.snapAnimationToEnd) {
        filteredRows.add(row);
      }
    }

    void _markInFiltered(
        InspectorTreeRow row, AnimatedRow animatedRow, int index) {
      if (row != null) {
        row.filteredAnimationRow = animatedRow;
        row.filteredAnimatedIndex = index;
      }
    }

    for (int i = 0; i < filteredRows.length; ++i) {
      final row = filteredRows[i];
      _markInFiltered(row.last, row, i);
      _markInFiltered(row.current, row, i);
    }
    int nextFilteredAnimatedIndex = 0;
    void updateFilteredIndex(InspectorTreeRow row) {
      if (row == null) return;
      if (row.inFilteredAnimation) {
        nextFilteredAnimatedIndex = row.filteredAnimatedIndex + 1;
      } else {
        row.filteredAnimatedIndex = nextFilteredAnimatedIndex;
      }
    }

    for (int i = 0; i < _animatedRows.length; ++i) {
      final row = _animatedRows[i];
      updateFilteredIndex(row.last);
      updateFilteredIndex(row.current);
    }

    final allAnimatedRows = _animatedRows;
    _animatedRows = filteredRows;

    lineModel = TreeStructureLineModel(
      allRows: allAnimatedRows,
    );
  }

  AnimatedRow getAnimatedRow(int index) {
    _syncCache();
    return _animatedRows.safeGet(index);
  }

  void animationDone() {
    _lastCachedRows = _cachedRows;
    _syncCache();
    setState(() {
      // We need to connect up the InspectorTreeRow rows in _animatedRowsAfter
      // to point to the animated rows in _animatedRowsAfter rather than the
      // animated rows from the previous animation.
      // TODO(jacobr): consider an alternate solution such as not treating the
      // state after the animation was complete as an animated row case and
      // adding a simpler code path for the non-animated case.
      for (int i = 0; i < _animatedRowsAfter.length; ++i) {
        final row = _animatedRowsAfter[i];
        assert(identical(row.last, row.current));
        // Update the row state to reflect that no animation is running.
        // This is a little paranoid but ensures we don't have mixed state from
        // rows from before and after the animation.
        row.last
          ..animatedIndex = i
          ..filteredAnimatedIndex = i
          ..filteredAnimationRow = row;
      }
      _rawAnimatedRows = _animatedRowsAfter;
      _animatedRows = _animatedRowsAfter;

      lineModel = TreeStructureLineModel(
        allRows: _animatedRows,
      );
    });
  }

  set hover(InspectorTreeNode node) {
    if (node == _hover) {
      return;
    }
    setState(() {
      _hover = node;
      // TODO(jacobr): we could choose to repaint only a portion of the UI
    });
  }

  RemoteDiagnosticsNode currentHoverDiagnostic;

  void navigateUp() {
    _navigateHelper(-1);
  }

  void navigateDown() {
    _navigateHelper(1);
  }

  void navigateLeft() {
    // This logic is consistent with how IntelliJ handles tree navigation on
    // on left arrow key press.
    if (selection == null) {
      _navigateHelper(-1);
      return;
    }

    if (selection.isExpanded) {
      setState(() {
        selection.isExpanded = false;
      });
      return;
    }
    if (selection.parent != null) {
      selection = selection.parent;
    }
  }

  void navigateRight() {
    // This logic is consistent with how IntelliJ handles tree navigation on
    // on right arrow key press.

    if (selection == null || selection.isExpanded) {
      _navigateHelper(1);
      return;
    }

    setState(() {
      selection.isExpanded = true;
    });
  }

  void _navigateHelper(int indexOffset) {
    final direction = indexOffset > 0 ? 1 : -1;
    final numRows = animatedRows.length;
    if (numRows == 0) return;

    if (selection == null) {
      selection = root;
      return;
    }

    // TODO(jacobr): switch this to use the cached row.
    final selectedRow = currentTreeStructure[selection];
    if (selectedRow == null) return;
    final lastIndex = selectedRow.animatedIndex;
    final targetIndex = lastIndex + indexOffset;
    int index = lastIndex;
    AnimatedRow bestMatch;
    bool foundTarget = false;
    while (index >= 0 && index < numRows) {
      index += direction;
      final candidate = animatedRows[index];
      if (index == targetIndex) {
        foundTarget = true;
      }
      if (candidate.current != null) {
        bestMatch = candidate;
        if (foundTarget) {
          // We want the first match past the target if possible. If there are
          // no matches past the target we are ok with accepting a match from
          // before the target.
          break;
        }
      }
    }
    if (bestMatch != null) {
      selection = bestMatch.current.node;
    }
  }

  void nodeChanged(InspectorTreeNode node) {
    if (node == null) return;
    setState(() {
      node.isDirty = true;
    });
  }

  void removeNodeFromParent(InspectorTreeNode node) {
    setState(() {
      node.parent?.removeChild(node);
    });
  }

  void appendChild(InspectorTreeNode node, InspectorTreeNode child) {
    setState(() {
      node.appendChild(child);
    });
  }

  void expandPath(InspectorTreeNode node) {
    setState(() {
      _expandPath(node);
    });
  }

  void _expandPath(InspectorTreeNode node) {
    while (node != null) {
      if (!node.isExpanded) {
        node.isExpanded = true;
      }
      node = node.parent;
    }
  }

  void collapseToSelected() {
    setState(() {
      _collapseAllNodes(root);
      if (selection == null) return;
      _expandPath(selection);
    });
  }

  void _collapseAllNodes(InspectorTreeNode root) {
    root.isExpanded = false;
    root._children.forEach(_collapseAllNodes);
  }

  @deprecated
  InspectorTreeRow getRowForNode(InspectorTreeNode node) {
    _syncCache();
    return _currentTreeStructure[node];
  }

  void animateToTargets(List<InspectorTreeNode> targets);

  void onExpandRow(InspectorTreeRow row) {
    setState(() {
      row.node.isExpanded = true;
      if (config.onExpand != null) {
        config.onExpand(row.node);
      }
    });
  }

  void onCollapseRow(InspectorTreeRow row) {
    setState(() {
      row.node.isExpanded = false;
    });
  }

  void onSelectRow(InspectorTreeRow row) {
    selection = row.node;
    expandPath(row.node);
  }

  bool expandPropertiesByDefault(DiagnosticsTreeStyle style) {
    // This code matches the text style defaults for which styles are
    //  by default and which aren't.
    switch (style) {
      case DiagnosticsTreeStyle.none:
      case DiagnosticsTreeStyle.singleLine:
      case DiagnosticsTreeStyle.errorProperty:
        return false;

      case DiagnosticsTreeStyle.sparse:
      case DiagnosticsTreeStyle.offstage:
      case DiagnosticsTreeStyle.dense:
      case DiagnosticsTreeStyle.transition:
      case DiagnosticsTreeStyle.error:
      case DiagnosticsTreeStyle.whitespace:
      case DiagnosticsTreeStyle.flat:
      case DiagnosticsTreeStyle.shallow:
      case DiagnosticsTreeStyle.truncateChildren:
        return true;
    }
    return true;
  }

  InspectorTreeNode setupInspectorTreeNode(
    InspectorTreeNode node,
    RemoteDiagnosticsNode diagnosticsNode, {
    @required bool expandChildren,
    @required bool expandProperties,
  }) {
    assert(expandChildren != null);
    assert(expandProperties != null);
    node.diagnostic = diagnosticsNode;
    if (config.onNodeAdded != null) {
      config.onNodeAdded(node, diagnosticsNode);
    }

    if (diagnosticsNode.maybeHasChildren ||
        diagnosticsNode.inlineProperties.isNotEmpty) {
      if (diagnosticsNode.childrenReady || !diagnosticsNode.maybeHasChildren) {
        final bool styleIsMultiline =
            expandPropertiesByDefault(diagnosticsNode.style);
        setupChildren(
          diagnosticsNode,
          node,
          node.diagnostic.childrenNow,
          expandChildren: expandChildren && styleIsMultiline,
          expandProperties: expandProperties && styleIsMultiline,
        );
      } else {
        node.clearChildren();
        node.appendChild(createNode());
      }
    }
    return node;
  }

  void setupChildren(
    RemoteDiagnosticsNode parent,
    InspectorTreeNode treeNode,
    List<RemoteDiagnosticsNode> children, {
    @required bool expandChildren,
    @required bool expandProperties,
  }) {
    assert(expandChildren != null);
    assert(expandProperties != null);
    treeNode.isExpanded = expandChildren;
    if (treeNode.childrenFiltered.isNotEmpty) {
      // Only case supported is this is the loading node.
      assert(treeNode.childrenFiltered.length == 1);
      removeNodeFromParent(treeNode.childrenFiltered.first);
    }
    final inlineProperties = parent.inlineProperties;

    if (inlineProperties != null) {
      for (RemoteDiagnosticsNode property in inlineProperties) {
        appendChild(
          treeNode,
          setupInspectorTreeNode(
            createNode(),
            property,
            // We are inside a property so only expand children if
            // expandProperties is true.
            expandChildren: expandProperties,
            expandProperties: expandProperties,
          ),
        );
      }
    }
    if (children != null) {
      for (RemoteDiagnosticsNode child in children) {
        appendChild(
          treeNode,
          setupInspectorTreeNode(
            createNode(),
            child,
            expandChildren: expandChildren,
            expandProperties: expandProperties,
          ),
        );
      }
    }
  }

  Future<void> maybePopulateChildren(InspectorTreeNode treeNode) async {
    final RemoteDiagnosticsNode diagnostic = treeNode.diagnostic;
    if (diagnostic != null &&
        diagnostic.maybeHasChildren &&
        (treeNode.hasPlaceholderChildren ||
            treeNode.childrenFiltered.isEmpty)) {
      try {
        final children = await diagnostic.children;
        if (treeNode.hasPlaceholderChildren ||
            treeNode.childrenFiltered.isEmpty) {
          setupChildren(
            diagnostic,
            treeNode,
            children,
            expandChildren: true,
            expandProperties: false,
          );
          nodeChanged(treeNode);
          if (treeNode == selection) {
            expandPath(treeNode);
          }
        }
      } catch (e) {
        log(e.toString(), LogLevel.error);
      }
    }
  }
}
