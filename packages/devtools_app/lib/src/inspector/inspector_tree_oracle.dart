// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

import 'inspector_tree.dart';

/// Class that describes how a node in one tree should be displayed in another
/// tree.
///
/// This class simplifies logic to compute what depth a node should have when
/// have when animating it to display at a consistent location with a different
/// tree.
class RowMatch {
  RowMatch({
    @required this.original,
    @required this.ancestor,
    @required this.match,
  }) : assert(original != null || match != null);

  /// Candidate row being matched.
  ///
  /// Can be null in case we didn't really have a node to match but had a node
  /// in the original tree we knew we wanted to display. This case exists to
  /// normalize logic computing how to display nodes.
  final InspectorTreeRow original;

  /// Common ancestor of the [original] node found in the tree being matched
  /// against. May be null if we cannot determine a common ancestor as will
  /// occur if the trees share no common nodes.
  final InspectorTreeRow ancestor;

  /// Matching row in the new tree.
  final InspectorTreeRow match;

  int get matchDepth {
    if (original == null) return match.depth;
    if (ancestor == null) return original.depth;
    return original.depth + match.depth - ancestor.depth;
  }
}

/// Oracle that can be queried to efficiently lookup rows in a tree.
class TreeStructureOracle {
  TreeStructureOracle();

  // Keys are InspectorTreeNode objects and InspectorInstanceRef objects.
  final Map<Object, InspectorTreeRow> _rowMap = {};

  bool containsNode(InspectorTreeNode node) {
    return this[node] != null;
  }

  /// Returns the row that matches the node or at least has the same ValueRef
  /// as the node.
  InspectorTreeRow operator [](InspectorTreeNode node) {
    if (node == null) return null;
    final exactMatch = _rowMap[node];
    if (exactMatch != null) return exactMatch;
    final diagnostic = node.diagnostic;
    if (diagnostic == null) return null;
    if (diagnostic.isProperty) {
      // It is not safe to assume that the value ref for a property is
      // sufficient to establish equality.
      // TODO(jacobr): we could do a better job here by using the parent node
      // as well. As is, this just means we will false positive and show
      // more properties than necessary as being unchanged.
      return null;
    }
    final valueRef = node?.diagnostic?.valueRef;
    return valueRef != null ? _rowMap[valueRef] : null;
  }

  /// Two nodes are considered equal if they have the same node
  bool matchingNodes(InspectorTreeNode a, InspectorTreeNode b) {
    if (a == b) return true;
    if (a == null || b == null) return false;
    final aDiagnostic = a.diagnostic;
    final bDiagnostic = b.diagnostic;

    if (aDiagnostic == null || b.diagnostic == null) return false;
    if (aDiagnostic.isProperty) {
      if (aDiagnostic.name != bDiagnostic.name) return false;

      if (aDiagnostic.description == bDiagnostic.description &&
          aDiagnostic.name == bDiagnostic.name) {
        return true;
      }
    }

    final aValue = aDiagnostic.valueRef;
    // TODO(jacobr): consider also treating nodes with null value refs equal if
    // all their fields are equal.
    final bValue = bDiagnostic.valueRef;
    return aValue == bValue;
  }

  /// Find first ancestor of the row (probably from a different tree) that
  /// exists in this tree.
  ///
  /// If the matching row is already known, pass [expectedMatch] to indicate
  /// what the match should be.
  RowMatch findFirstMatchingAncestor(
    InspectorTreeRow row, {
    @required InspectorTreeRow expectedMatch,
  }) {
    if (expectedMatch != null) {
      assert(row == null || matchingNodes(row.node, expectedMatch.node));
      return RowMatch(original: row, ancestor: row, match: expectedMatch);
    }
    var candidate = row;
    // Row is from a different tree.
    assert(candidate.oracle != this);
    while (candidate != null) {
      final match = this[candidate.node];
      if (match != null) {
        return RowMatch(
          original: row,
          ancestor: candidate,
          match: match,
        );
      }
      candidate = candidate.parent;
    }
    return RowMatch(original: row, ancestor: null, match: null);
  }

  void trackRow(InspectorTreeRow row) {
    final node = row.node;
    _rowMap[node] = row;
    if (!node.isProperty) {
      // The value ref for a property may not indicate anything useful.
      final valueRef = node?.diagnostic?.valueRef;
      if (valueRef != null) {
        _rowMap[valueRef] = row;
      }
    }
  }
}
