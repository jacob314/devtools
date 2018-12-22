// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

library inspector_tree;

import 'dart:html';

import 'package:devtools/ui/material_icons.dart';
import 'package:meta/meta.dart';

import '../framework/framework.dart';
import '../inspector/diagnostics_node.dart';
import '../inspector/inspector.dart';
import '../inspector/inspector_service.dart';
import '../ui/elements.dart';
import '../ui/fake_flutter/fake_flutter.dart';
import '../ui/flutter_html_shim.dart';
import '../ui/icons.dart';
import '../ui/inspector_text_styles.dart' as inspector_text_styles;
import '../utils.dart';

/// Split text into two groups, word characters at the start of a string and all other
/// characters. Skip an <code>-</code> or <code>#</code> between the two groups.
final RegExp _primaryDescriptionPattern = RegExp('([\\w ]+)[-#]?(.*)');

final ColorIconMaker _colorIconMaker = new ColorIconMaker();
final CustomIconMaker _customIconMaker = new CustomIconMaker();

const bool _showRenderObjectPropertiesAsLinks = false;

class InspectorTreeNode {
  InspectorTreeNode({
    InspectorTreeNode parent,
    this.isProperty = false,
    bool expandChildren = false,
  })  : //_diagnostic = diagnostic,
        _children = <InspectorTreeNode>[],
        _parent = parent,
        _expanded = expandChildren;

  static InspectorTreeNode buildTree(
    DiagnosticsNode d, {
    InspectorTreeNode parent,
    bool summaryTree = false,
    bool includeChildren = true,
    DiagnosticsNode selectedValue,
  }) {
    /*
    InspectorTreeNode treeNode; // Null if filtered.
    final DiagnosticsNode value = d.value;
    if (!summaryTree || parent == null || isCreatedByLocalProject) {
      treeNode = new InspectorTreeNode(
        diagnostic: d,
        parent: parent,
        isProperty: false,
      );
      if (parent != null) {
        parent.children.add(treeNode);
      }
    }
    if (selectedValue != null && identical(value, selectedValue)) {
      selectedValueCallback(treeNode ?? parent);
    }
    if (summaryTree == false) {
      // XXX be more lazy about properties for performance?
      final List<DiagnosticsNode> properties = d.getProperties();
      final Map<String, DiagnosticsNode> propertyMap = <String, DiagnosticsNode>{};
      for (DiagnosticsNode property in properties) {
        propertyMap[property.name] = property;
      }
      for (DiagnosticsNode property in properties) {
        if (property.isFiltered(isCreatedByLocalProject ? DiagnosticLevel.fine : DiagnosticLevel.info)) {
          continue;
        }
        InspectorTreeNode propertyTreeNode = new InspectorTreeNode(
          diagnostic: property,
          parent: treeNode,
          isProperty: true,
          isCreatedByLocalProject: false, // XXX infer local properties and bold.
        );
        final propertyValue = property.value;
        propertyTreeNode.expanded = false;
        if (propertyValue is RenderObject) {
          for (DiagnosticsNode renderObjectProperty in propertyValue.toDiagnosticsNode().getProperties()) {
            if (renderObjectProperty.isFiltered(DiagnosticLevel.info)) {
              continue;
            }
            final String name = renderObjectProperty.name;
            if (propertyMap.containsKey(name) && propertyMap[name].value == renderObjectProperty.value) {
// skip dupes.... maybe a bad idea.
              continue;
            }
            propertyTreeNode.children.add(new InspectorTreeNode(
              diagnostic: renderObjectProperty,
              parent: treeNode,
              isProperty: true,
              isCreatedByLocalProject: false, // XXX infer local properties and bold.
            ));
          }
        }
        treeNode.children.add(propertyTreeNode);
      }
    }
    if (includeChildren) {
      for (DiagnosticsNode child in d.getChildren()) {
        buildTree(
          child,
          parent: treeNode ?? parent,
          summaryTree: summaryTree,
          selectedValue: selectedValue,
          selectedValueCallback: selectedValueCallback,
        );
      }
    }
    return treeNode;
    */
    // TODO(jacobr): implement. this implementaiton is too specific to on device render.
    throw 'Unimplemented';
  }

  DiagnosticsNode _diagnostic;
  final List<InspectorTreeNode> _children;

  Iterable<InspectorTreeNode> get children => _children;

  bool get isCreatedByLocalProject => _diagnostic.isCreatedByLocalProject;
  final bool isProperty;

  bool get expanded => _expanded;
  bool _expanded = true;
  set expanded(bool value) {
    if (value != expanded) {
      _expanded = value;
      dirty();
    }
  }

  InspectorTreeNode get parent => _parent;
  InspectorTreeNode _parent;
  set parent(InspectorTreeNode value) {
    _parent = value;
    _parent.dirty();
  }

  DiagnosticsNode get diagnostic => _diagnostic;

  set diagnostic(DiagnosticsNode v) {
    _diagnostic = v;
    dirty();
  }

  void dirty() {
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
      return 0;
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
  TreeRow getRow(int index,
      {InspectorTreeNode selection, InspectorTreeNode highlightedRoot}) {
    final List<int> ticks = <int>[];
    int highlightDepth;
    InspectorTreeNode node = this;
    if (subtreeSize <= index) {
      return null;
    }
    int current = 0;
    int depth = 0;
    while (node != null) {
      if (highlightedRoot == node) {
        highlightDepth = depth;
      }
      if (current == index) {
        return new TreeRow(
          node: node,
          ticks: ticks,
          depth: depth,
          isSelected: selection == node,
          highlightDepth: highlightDepth,
          lineToParent: !node.isProperty,
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
    dirty();
  }

  void clearChildren() {
    _children.clear();
  }
}

/// A row in the tree with all information required to render it.
class TreeRow {
  const TreeRow(
      {this.node,
      this.ticks,
      this.depth,
      this.lineToParent = true,
      this.isSelected,
      this.highlightDepth});

  final InspectorTreeNode node;

  /// Column indexes of ticks to draw lines from parents to children.
  final List<int> ticks;
  final int depth;
  final bool lineToParent;
  final bool isSelected;
  final int highlightDepth;
}

typedef CanvasPaintCallback = void Function(
    CanvasRenderingContext2D canvas, int index, double width, double height);

class InspectorTree extends Object with SetStateMixin, OnAddedToDomMixin {
  InspectorTree({
    @required InspectorTreeNode root,
    @required this.summaryTree,
    @required this.treeType,
  }) : defaultIcon = _customIconMaker.fromInfo('Default');

  static const double iconPadding = 3.0;

  InspectorTreeNode root;
  DiagnosticsNode subtreeRoot; // Optional.
  InspectorTreeNode _selection;
  InspectorTreeNode highlightedRoot;
  DiagnosticsNode selectedValue;

  Set<VoidCallback> selectionChangeCallbacks = new Set();
  final bool summaryTree;
  final FlutterTreeType treeType;
  final Icon defaultIcon;

  @override
  // TODO: implement element
  CoreElement get element => CoreElement('div');

  double getRowOffset(int index) {
    return (root.getRow(index)?.depth ?? 0) * columnWidth;
  }

  set selection(InspectorTreeNode node) {
    setState(() {
      _selection = node;
      while (node != null) {
        node = node.parent;
        if (!node.expanded) {
          node.expanded = true;
        }
      }
    });
  }

  InspectorTreeNode get selection => _selection;

  void addSelectionChangedListener(VoidFunction callback) {
    selectionChangeCallbacks.add(callback);
  }

  /* XXX
  Future<void> _scrollChanged() async {
    if (root == null) {
      return null;
    }
    if (animateX == null) {
      pendingXScrollToView = false;
      final ScrollPosition position = scrollControllerY.position;
      double y = position.pixels;
      double row = ((y - scrollOffsetY) / rowHeight) - 1; // XXX off by 1 errors /?.
      row = row.clamp(0.0, root.subtreeSize.toDouble() - 1.0);
      int rowIndex = row.floor();
      final double fraction = row - rowIndex;
      double target = new Tween<double>(
        begin: getRowOffset(rowIndex),
        end: getRowOffset(rowIndex+1),
      ).lerp(fraction);
      target = math.max(0.0, target - scrollOffsetX);
      print('XXX target = $target');
      // if ((target -  scrollControllerX.position.pixels).abs() > 30.0)
          {
        scrollControllerX.animateTo(
            target, duration: const Duration(milliseconds: 500),
            curve: Curves.linear);
      }
    } else if (!pendingXScrollToView){
      pendingXScrollToView = true;
      await animateX;
      _scrollChanged();
    }
  }

  Future<Null> animateX;
  Future<Null> animateY;
  bool pendingXScrollToView = false;

  void _onSelectionChanged() {
    setState(() {
      final WidgetInspectorService service = WidgetInspectorService.instance;
      selectedValue = widget.treeType == InspectorTreeType.widget ? service.selection.currentElement : service.selection.current;
      _rebuildTree();
      if (selection != null) {
        final int selectionIndex = root.getRowIndex(selection);
        final TreeRow row = root.getRow(selectionIndex);
        if (row == null) {
          return;
        }
        if (row.node != selection) {
          print('MISMATCH ${row.node.diagnostic}, ${selection.diagnostic}, isSummary. index=$selectionIndex ${widget.summaryTree}');
        }

        double x = math.max(0.0, getDepthIndent(row.depth) - scrollOffsetX);
        double y = math.max(0.0, (selectionIndex + 1) * rowHeight - scrollOffsetY); // XXX off by one error. why?
        if (widget.summaryTree && false) { // XXX boring selection
          scrollControllerX.jumpTo(x);
          scrollControllerY.jumpTo(y);
        } else {
          animateX = scrollControllerX.animateTo(
              x, duration: const Duration(milliseconds: 500),
              curve: Curves.linear);
          animateY = scrollControllerY.animateTo(
              y, duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut);
          animateX.then(
                (_) {
              animateX = null;
            }, onError: () {
            animateX = null;
          },
          );
          animateY.then(
                (_) {
              animateY = null;
            },
            onError: () {
              animateY = null;
            },
          );
        }
      }
    });
  }
*/

  static double chartLineStrokeWidth = 1.0;
  static const double columnWidth = 12.0;
  static const double rowHeight =
      20.0; // TODO(jacobr): compute from font size, etc.

  /// Split text into two groups, word characters at the start of a string
  /// and all other characters. Skip an <code>-</code> or <code>#</code> between
  /// the two groups.
  static final RegExp primaryDescriptionRegExp = new RegExp(r'(\w+)[-#]?(.*)');

  static double getDepthIndent(int depth) {
    return depth.toDouble() * columnWidth;
  }

  void paintRow(
    CanvasRenderingContext2D canvas,
    int index,
    Rect visible,
  ) {
    canvas.save();
    double y = rowHeight * index;
    canvas.translate(0, y);
    // Variables incremented as part of painting.
    double currentX = 0;
    TextStyle currentStyle;
    Color currentColor;

    bool isVisible(double width) {
      return currentX <= visible.left + visible.width &&
          visible.left <= currentX + width;
    }

    void appendText(String text, TextStyle textStyle) {
      if (currentX > visible.right) {
        return; // We might also want to wrap.
      }
      if (text.isEmpty) {
        return;
      }
      if (textStyle != currentStyle) {
        currentStyle = textStyle;
        canvas.font = fontStyleToCss(currentStyle);
      }
      double width = canvas.measureText(text).width;

      if (isVisible(width)) {
        if (currentColor != textStyle.color) {
          currentColor = textStyle.color;
          canvas.fillStyle = colorToCss(currentColor);
        }
        canvas.fillText(text, currentX, 0);
      }
      currentX += width;
    }

    void addIcon(Icon icon) {
      if (currentX > visible.right) {
        return; // We might also want to wrap.
      }
      final image = icon.image;
      double width = icon.iconWidth + iconPadding;
      if (isVisible(width)) {
        if (image != null) {
          canvas.drawImage(image, currentX, 0);
        }
      }
      currentX += width;
    }

    canvas.save(); // not really needed outside of debug mode.

    final TreeRow row = root?.getRow(index,
        selection: selection, highlightedRoot: highlightedRoot);
    if (row == null) {
      return;
    }
    final InspectorTreeNode node = row.node;
    final DiagnosticsNode diagnostic = node.diagnostic;

    if (row.highlightDepth != null) {
      final double x = getDepthIndent(row.highlightDepth) - columnWidth * 0.5;
      if (x <= visible.right) {
        canvas.strokeStyle = colorToCss(Colors.white);
        canvas.rect(x, 0.0, visible.right - x, rowHeight);
      }
    }
    if (row.isSelected) {
      final double x = getDepthIndent(row.depth) - columnWidth * 0.15;
      if (x <= visible.right) {
        canvas.fillStyle = colorToCss(Colors.blueAccent);
        canvas.fillRect(x, 0.0, visible.right - x, rowHeight);
      }
    }
    bool hasPath = false;
    void _maybeStart() {
      if (!hasPath) {
        hasPath = true;
        canvas.beginPath();
      }
    }

    for (int tick in row.ticks) {
      currentX = getDepthIndent(tick) + columnWidth * 0.25;
      if (isVisible(1.0)) {
        _maybeStart();
        canvas
          ..moveTo(currentX, 0.0)
          ..lineTo(currentX, rowHeight);
      }
    }
    if (row.lineToParent) {
      currentX = getDepthIndent(row.depth - 1) + columnWidth * 0.25;
      final double width = columnWidth * 0.5;
      if (isVisible(width)) {
        _maybeStart();
        canvas
          ..moveTo(currentX, 0.0)
          ..lineTo(currentX, rowHeight * 0.5)
          ..lineTo(currentX + width, rowHeight * 0.5);
      }
    }
    if (hasPath) {
      canvas.lineWidth = chartLineStrokeWidth;
      canvas.strokeStyle = colorToCss(Colors.black38);
      canvas.stroke();
    }

    // Now draw main content.
    currentX = getDepthIndent(row.depth);
    if (currentX >= visible.right) {
      // Short circut as nothing can be drawn within the view.
      canvas.restore();
      return;
    }
    final String name = diagnostic.name;
    TextStyle textStyle = textAttributesForLevel(diagnostic.level);
    if (diagnostic.isProperty) {
      // Display of inline properties.
      final String propertyType = diagnostic.propertyType;
      final Map<String, Object> properties = diagnostic.valuePropertiesJson;
      if (node.isCreatedByLocalProject) {
        textStyle = textStyle.merge(inspector_text_styles.regularItalic);
      }

      if (name?.isNotEmpty == true && diagnostic.showName) {
        appendText('$name${diagnostic.separator} ', textStyle);
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

              final Color color = new Color.fromARGB(alpha, red, green, blue);
              addIcon(_colorIconMaker.getCustomIcon(color));
              break;
            }

          case 'IconData':
            {
              final int codePoint =
                  JsonUtils.getIntMember(properties, 'codePoint');
              if (codePoint > 0) {
                final Icon icon = FlutterMaterialIcons.getIconForHex(
                    codePoint.toRadixString(16).padLeft(4, '0'));
                if (icon != null) {
                  addIcon(icon);
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
      appendText(description, textStyle);
      if (diagnostic.level == DiagnosticLevel.fine &&
          diagnostic.hasDefaultValue) {
        appendText(' ', textStyle);
        addIcon(defaultIcon);
      }
    } else {
      // Non property, regular node case.
      if (name?.isNotEmpty == true && diagnostic.showName && name != 'child') {
        if (name.startsWith('child ')) {
          appendText(name, inspector_text_styles.grayed);
        } else {
          appendText(name, textStyle);
        }

        if (diagnostic.showSeparator) {
          appendText(diagnostic.separator, inspector_text_styles.grayed);
        } else {
          appendText(' ', inspector_text_styles.grayed);
        }
      }

      if (!summaryTree && diagnostic.isCreatedByLocalProject) {
        textStyle = textStyle.merge(inspector_text_styles.regularBold);
      }

      final String description = diagnostic.description;
      final match = _primaryDescriptionPattern.firstMatch(description);
      if (match != null) {
        appendText(' ', inspector_text_styles.grayed);
        appendText(match.group(1), textStyle);
        appendText(' ', textStyle);
        appendText(match.group(2), inspector_text_styles.grayed);
      } else if (diagnostic.description?.isNotEmpty == true) {
        appendText(' ', inspector_text_styles.grayed);
        appendText(diagnostic.description, textStyle);
      }
    }

    // TODO(devoncarew): For widgets that are definied in the current project, we could consider
    // appending the relative path to the defining library ('lib/src/foo_page.dart').

    canvas.restore();
  }

  void nodeChanged(InspectorTreeNode node) {
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

  void expandPath(InspectorTreeNode treeNode) {
    setState(() {});
  }
}

class CanvasListViewBuilder {}
