// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Inspector specific tree rendering support designed to be extendable to work
/// either directly with dart:html or with Hummingbird.
///
/// This library must not have direct dependencies on dart:html.
///
/// This allows tests of the complicated logic in this class to run on the VM
/// and will help simplify porting this code to work with Hummingbird.
library inspector_tree;

import 'package:devtools/inspector/inspector_controller.dart';
import 'package:devtools/ui/material_icons.dart';
import 'package:meta/meta.dart';

import '../ui/fake_flutter/fake_flutter.dart';
import '../ui/icons.dart';
import '../utils.dart';

import 'diagnostics_node.dart';
import 'inspector_service.dart';
import 'inspector_text_styles.dart' as inspector_text_styles;

/// Split text into two groups, word characters at the start of a string and all other
/// characters. Skip an <code>-</code> or <code>#</code> between the two groups.
final RegExp _primaryDescriptionPattern = RegExp('([\\w ]+)[-#]?(.*)');

final ColorIconMaker _colorIconMaker = ColorIconMaker();
final CustomIconMaker _customIconMaker = CustomIconMaker();

const bool _showRenderObjectPropertiesAsLinks = false;

typedef TreeEventCallback = void Function(InspectorTreeNode node);

const Color selectedRowBackgroundColor = Color.fromARGB(255, 202, 191, 69);
const Color highlightLineColor = Colors.black;
const Color defaultTreeLineColor = Colors.grey;
const double iconPadding = 3.0;
const double chartLineStrokeWidth = 1.0;
const double columnWidth = 16.0;
const double horizontalPadding = 10.0;
const double verticalPadding = 10.0;
const double rowHeight = 24.0;
const Color arrowColor = Colors.grey;
final Icon defaultIcon = _customIconMaker.fromInfo('Default');

// TODO(jacobr): these arrows are a bit ugly.
// We should create pngs instead of trying to stretch the material icons into
// being good expand collapse arrows.
final Icon collapseArrow = MaterialIcon(
  'arrow_drop_down',
  arrowColor,
  fontSize: 32,
  iconWidth: (columnWidth - iconPadding).toInt(),
);

final Icon expandArrow = MaterialIcon(
  'arrow_right',
  arrowColor,
  fontSize: 32,
  iconWidth: (columnWidth - iconPadding).toInt(),
);

abstract class PaintEntry {
  PaintEntry(this.x);

  Icon get icon;

  final double x;

  double get right;

  void attach(InspectorTree owner) {}
}

abstract class InspectorTreeNodeRenderBuilder {
  void appendText(String text, TextStyle textStyle);
  void addIcon(Icon icon);

  InspectorTreeNodeRender build();
}

class InspectorTreeNodeRender {
  InspectorTreeNodeRender(this.entries, this.size);

  final List<PaintEntry> entries;
  final Size size;

  void attach(InspectorTree owner, Offset offset) {
    if (_owner != owner) {
      _owner = owner;
    }
    _offset = offset;

    for (var entry in entries) {
      entry.attach(owner);
    }
  }

  /// Offset can be updated once the
  Offset get offset => _offset;
  Offset _offset;

  InspectorTree _owner;

  Rect get paintBounds => _offset & size;

  Icon hitTest(Offset location) {
    location = location - _offset;
    if (location.dy < 0 || location.dy >= size.height) {
      return null;
    }
    // There is no need to optimize this but we could perform a binary search.
    for (PaintEntry entry in entries) {
      if (entry.x <= location.dx && entry.right > location.dx) {
        return entry.icon;
      }
    }
    return null;
  }
}

/// This class could be refactored out to be a reasonable generic collapsible
/// tree ui node class but we choose to instead make it widget inspector
/// specific as that is the only case we care about.
abstract class InspectorTreeNode {
  InspectorTreeNode({
    InspectorTreeNode parent,
    bool expandChildren = true,
  })  : _children = <InspectorTreeNode>[],
        _parent = parent,
        _expanded = expandChildren;

  /// Override this method to define a tree node to build render objects
  /// appropriate for a specific platform.
  InspectorTreeNodeRenderBuilder createRenderBuilder();

  InspectorTreeNodeRender get renderObject {
    if (_renderObject != null || diagnostic == null) {
      return _renderObject;
    }

    final builder = createRenderBuilder();
    final icon = diagnostic.icon;
    if (showExpandCollapse) {
      builder.addIcon(expanded ? collapseArrow : expandArrow);
    }
    if (icon != null) {
      builder.addIcon(icon);
    }
    final String name = diagnostic.name;
    TextStyle textStyle = textAttributesForLevel(diagnostic.level);
    if (diagnostic.isProperty) {
      // Display of inline properties.
      final String propertyType = diagnostic.propertyType;
      final Map<String, Object> properties = diagnostic.valuePropertiesJson;
      if (isCreatedByLocalProject) {
        textStyle = textStyle.merge(inspector_text_styles.regularItalic);
      }

      if (name?.isNotEmpty == true && diagnostic.showName) {
        builder.appendText('$name${diagnostic.separator} ', textStyle);
      }

      String description = diagnostic.description;
      if (propertyType != null && properties != null) {
        switch (propertyType) {
          case 'Color':
            {
              final int alpha = JsonUtils.getIntMember(properties, 'alpha');
              final int red = JsonUtils.getIntMember(properties, 'red');
              final int green = JsonUtils.getIntMember(properties, 'green');
              final int blue = JsonUtils.getIntMember(properties, 'blue');
              String radix(int chan) => chan.toRadixString(16).padLeft(2, '0');
              if (alpha == 255) {
                description = '#${radix(red)}${radix(green)}${radix(blue)}';
              } else {
                description =
                    '#${radix(alpha)}${radix(red)}${radix(green)}${radix(blue)}';
              }

              final Color color = Color.fromARGB(alpha, red, green, blue);
              builder.addIcon(_colorIconMaker.getCustomIcon(color));
              break;
            }

          case 'IconData':
            {
              final int codePoint =
                  JsonUtils.getIntMember(properties, 'codePoint');
              if (codePoint > 0) {
                // final Icon icon = FlutterMaterialIcons.getIconForHex(
                //    codePoint.toRadixString(16).padLeft(4, '0'));
                final Icon icon =
                    FlutterMaterialIcons.getIconForCodePoint(codePoint);
                if (icon != null) {
                  builder.addIcon(icon);
                }
              }
              break;
            }
        }
      }

      if (_showRenderObjectPropertiesAsLinks &&
          propertyType == 'RenderObject') {
        textStyle = textStyle..merge(inspector_text_styles.link);
      }

      // TODO(jacobr): custom display for units, iterables, and padding.
      builder.appendText(description, textStyle);
      if (diagnostic.level == DiagnosticLevel.fine &&
          diagnostic.hasDefaultValue) {
        builder.appendText(' ', textStyle);
        builder.addIcon(defaultIcon);
      }
    } else {
      // Non property, regular node case.
      if (name?.isNotEmpty == true && diagnostic.showName && name != 'child') {
        if (name.startsWith('child ')) {
          builder.appendText(name, inspector_text_styles.grayed);
        } else {
          builder.appendText(name, textStyle);
        }

        if (diagnostic.showSeparator) {
          builder.appendText(
              diagnostic.separator, inspector_text_styles.grayed);
        } else {
          builder.appendText(' ', inspector_text_styles.grayed);
        }
      }

      if (!diagnostic.isSummaryTree && diagnostic.isCreatedByLocalProject) {
        textStyle = textStyle.merge(inspector_text_styles.regularBold);
      }

      final String description = diagnostic.description;
      final match = _primaryDescriptionPattern.firstMatch(description);
      if (match != null) {
        builder.appendText(' ', inspector_text_styles.grayed);
        builder.appendText(match.group(1), textStyle);
        builder.appendText(' ', textStyle);
        builder.appendText(match.group(2), inspector_text_styles.grayed);
      } else if (diagnostic.description?.isNotEmpty == true) {
        builder.appendText(' ', inspector_text_styles.grayed);
        builder.appendText(diagnostic.description, textStyle);
      }
    }
    _renderObject = builder.build();
    return _renderObject;
  }

  InspectorTreeNodeRender _renderObject;
  DiagnosticsNode _diagnostic;
  final List<InspectorTreeNode> _children;

  Iterable<InspectorTreeNode> get children => _children;

  bool get isCreatedByLocalProject => _diagnostic.isCreatedByLocalProject;
  bool get isProperty => diagnostic == null || diagnostic.isProperty;

  bool get expanded => _expanded;
  bool _expanded;

  bool get showExpandCollapse {
    return diagnostic?.hasChildren == true || children.isNotEmpty;
  }

  set expanded(bool value) {
    if (value != _expanded) {
      _expanded = value;
      dirty();
    }
  }

  InspectorTreeNode get parent => _parent;
  InspectorTreeNode _parent;

  set parent(InspectorTreeNode value) {
    _parent = value;
    _parent?.dirty();
  }

  DiagnosticsNode get diagnostic => _diagnostic;

  set diagnostic(DiagnosticsNode v) {
    _diagnostic = v;
    _expanded = v.childrenReady;
    dirty();
  }

  void dirty() {
    _renderObject = null;
    if (_childrenCount == null) {
      // Already dirty.
      return;
    }
    _childrenCount = null;
    if (parent != null) {
      parent.dirty();
    }
  }

  int get childrenCount {
    if (!expanded) {
      _childrenCount = 0;
    }
    if (_childrenCount != null) {
      return _childrenCount;
    }
    int count = 0;
    for (InspectorTreeNode child in _children) {
      count += child.subtreeSize;
    }
    _childrenCount = count;
    return _childrenCount;
  }

  int _childrenCount;

  int get subtreeSize => childrenCount + 1;

  bool get isLeaf => _children.isEmpty;

  // XXX on wrong class
  int getRowIndex(InspectorTreeNode node) {
    int index = 0;
    while (true) {
      final InspectorTreeNode parent = node.parent;
      if (parent == null) {
        break;
      }
      for (InspectorTreeNode sibling in parent._children) {
        if (sibling == node) {
          break;
        }
        index += sibling.subtreeSize;
      }
      index += 1; // For parent itself.
      node = parent;
    }
    return index;
  }

  /// TODO(jacobr): move this method to a different class.
  TreeRow getRow(int index, {InspectorTreeNode selection}) {
    final List<int> ticks = <int>[];
    int highlightDepth;
    InspectorTreeNode node = this;
    if (subtreeSize <= index) {
      return null;
    }
    int current = 0;
    int depth = 0;
    while (node != null) {
      if (selection == node) {
        highlightDepth = depth;
      }
      if (current == index) {
        return TreeRow(
          node: node,
          index: index,
          ticks: ticks,
          depth: depth,
          isSelected: selection == node,
          highlightDepth: highlightDepth,
          lineToParent: !node.isProperty && index != 0,
        );
      }
      assert(index > current);
      current++;
      final List<InspectorTreeNode> children = node._children;
      int i;
      for (i = 0; i < children.length; ++i) {
        final child = children[i];
        final subtreeSize = child.subtreeSize;
        if (current + subtreeSize > index) {
          node = child;
          if (children.length > 1 &&
              i + 1 != children.length &&
              !children.last.isProperty) {
            ticks.add(depth);
          }
          break;
        }
        current += subtreeSize;
      }
      assert(i < children.length);
      depth++;
    }
    assert(false); // internal error.
    return null;
  }

  void removeChild(InspectorTreeNode child) {
    child.parent = null;
    final removed = _children.remove(child);
    assert(removed != null);
    dirty();
  }

  void appendChild(InspectorTreeNode child) {
    _children.add(child);
    child.parent = this;
    dirty();
  }

  void clearChildren() {
    _children.clear();
    dirty();
  }
}

/// A row in the tree with all information required to render it.
class TreeRow {
  const TreeRow({
    @required this.node,
    @required this.index,
    @required this.ticks,
    @required this.depth,
    @required this.isSelected,
    @required this.highlightDepth,
    this.lineToParent = true,
  });

  final InspectorTreeNode node;

  /// Column indexes of ticks to draw lines from parents to children.
  final List<int> ticks;
  final int depth;
  final int index;
  final bool lineToParent;
  final bool isSelected;
  final int highlightDepth;
}

typedef InspectorTreeFactory = InspectorTree Function({
  @required bool summaryTree,
  @required FlutterTreeType treeType,
  VoidCallback onSelectionChange,
  TreeEventCallback onExpand,
  TreeEventCallback onHover,
});

abstract class InspectorTree {
  InspectorTree({
    @required this.summaryTree,
    @required this.treeType,
    VoidCallback onSelectionChange,
    this.onExpand,
    this.onHover,
  }) : _onSelectionChange = onSelectionChange;

  final TreeEventCallback onHover;
  final TreeEventCallback onExpand;
  final VoidCallback _onSelectionChange;

  InspectorTreeNode get root => _root;
  InspectorTreeNode _root;
  set root(InspectorTreeNode node) {
    setState(() {
      _root = node;
    });
  }

  DiagnosticsNode subtreeRoot; // Optional.

  InspectorTreeNode get selection => _selection;
  InspectorTreeNode _selection;
  set selection(InspectorTreeNode node) {
    setState(() {
      _selection = node;
      expandPath(node);
      if (_onSelectionChange != null) {
        _onSelectionChange();
      }
    });
  }

  InspectorTreeNode get hover => _hover;
  InspectorTreeNode _hover;

  Set<VoidCallback> selectionChangeCallbacks = Set<VoidCallback>();
  final bool summaryTree;
  final FlutterTreeType treeType;

  void setState(VoidCallback modifyState);
  InspectorTreeNode createNode();

  double getRowOffset(int index) {
    return (root.getRow(index)?.depth ?? 0) * columnWidth;
  }

  void addSelectionChangedListener(VoidFunction callback) {
    selectionChangeCallbacks.add(callback);
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

  /// Split text into two groups, word characters at the start of a string
  /// and all other characters. Skip an <code>-</code> or <code>#</code> between
  /// the two groups.
  static final RegExp primaryDescriptionRegExp = RegExp(r'(\w+)[-#]?(.*)');

  double getDepthIndent(int depth) {
    return (depth + 1) * columnWidth + horizontalPadding;
  }

  double getRowY(int index) {
    return rowHeight * index + verticalPadding;
  }

  void nodeChanged(InspectorTreeNode node) {
    if (node == null) return;
    setState(() {
      node.dirty();
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
      while (node != null) {
        if (!node.expanded) {
          node.expanded = true;
        }
        node = node.parent;
      }
    });
  }

  int get numRows => root != null ? root.subtreeSize : 0;

  int getRowIndex(double y) => (y - verticalPadding) ~/ rowHeight;

  TreeRow _getRowForNode(InspectorTreeNode node) {
    return root.getRow(root.getRowIndex(node));
  }

  TreeRow getRow(Offset offset) {
    if (root == null) return null;
    final int row = getRowIndex(offset.dy);
    return row < root.subtreeSize ? root.getRow(row) : null;
  }

  Rect getBoundingBox(TreeRow row);

  void animateToTargets(List<InspectorTreeNode> targets) {
    Rect targetRect;
    if (targets.isEmpty) return;

    for (InspectorTreeNode target in targets) {
      final row = _getRowForNode(target);
      final rowRect = getBoundingBox(row);
      targetRect =
          targetRect == null ? rowRect : targetRect.expandToInclude(rowRect);
    }

    targetRect = targetRect.inflate(20.0);
    scrollToRect(targetRect);
  }

  void scrollToRect(Rect targetRect);

  void onTap(Offset offset) {
    final row = getRow(offset);
    if (row != null) {
      final icon = row.node.renderObject?.hitTest(offset);
      if (icon == expandArrow) {
        setState(() {
          row.node.expanded = true;
          onExpand(row.node);
        });
        return;
      }
      if (icon == collapseArrow) {
        setState(() {
          row.node.expanded = false;
        });
        return;
      }
      // TODO(jacobr): add other interactive elements here.
      selection = row.node;
    }
  }
}
