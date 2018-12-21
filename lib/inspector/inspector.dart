// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

library inspector;

import 'dart:async';

import 'package:devtools/inspector/diagnostics_node.dart';
import 'package:devtools/inspector/inspector_tree.dart';
import 'package:devtools/ui/inspector_text_styles.dart'
    as inspector_text_styles;
import 'package:meta/meta.dart';
import 'package:vm_service_lib/vm_service_lib.dart';

import '../framework/framework.dart';
import '../globals.dart';
import '../ui/custom.dart';
import '../ui/elements.dart';
import '../ui/fake_flutter/fake_flutter.dart';
import '../ui/primer.dart';
import '../utils.dart';

import 'diagnostics_node.dart';
import 'inspector_service.dart';

void _logError(error) {
  print(error);
}

TextStyle textAttributesForLevel(DiagnosticLevel level) {
  switch (level) {
    case DiagnosticLevel.hidden:
      return inspector_text_styles.grayed;
    case DiagnosticLevel.fine:
      return inspector_text_styles.regular;
    case DiagnosticLevel.warning:
      return inspector_text_styles.warning;
    case DiagnosticLevel.error:
      return inspector_text_styles.error;
    case DiagnosticLevel.debug:
    case DiagnosticLevel.info:
    default:
      return inspector_text_styles.regular;
  }
}

class InspectorSelectionState {
  InspectorInstanceRef ref;
}

class InspectorPanel implements InspectorServiceClient {
  InspectorPanel({
    this.inspectorService,
    this.treeType,
    this.parentTree,
    this.isSummaryTree = true,
  })  : treeGroups = new InspectorObjectGroupManager(inspectorService, 'tree'),
        selectionGroups =
            new InspectorObjectGroupManager(inspectorService, 'selection'),
        myRootsTree = new InspectorTree(
          root: InspectorTreeNode(),
          summaryTree: isSummaryTree,
          treeType: treeType,
        ) {
    _refreshRateLimiter = new RateLimiter(refreshFramesPerSecond, refresh);

    if (isSummaryTree) {
      subtreePanel = new InspectorPanel(
          inspectorService: inspectorService,
          treeType: treeType,
          parentTree: this,
          isSummaryTree: false);
    } else {
      subtreePanel = null;
    }

    myRootsTree.addSelectionChangedListener(selectionChanged);

    // XXX determineSplitterOrientation();

    flutterIsolateSubscription = serviceManager.isolateManager
        .getCurrentFlutterIsolate((IsolateRef flutterIsolate) {
      throw 'Implement... our lifetime is different than intellij';
      if (flutterIsolate == null) {
        onIsolateStopped();
      }
    });
  }

  /// Maximum frame rate to refresh the inspector panel at to avoid taxing the
  /// physical device with too many requests to recompute properties and trees.
  ///
  /// A value up to around 30 frames per second could be reasonable for
  /// debugging highly interactive cases particularly when the user is on a
  /// simulator or high powered native device. The frame rate is set low
  /// for now mainly to minimize the risk of unintended consequences.
  static const double refreshFramesPerSecond = 5.0;

  final bool isSummaryTree;

  /// Parent InspectorPanel if this is a details subtree
  InspectorPanel parentTree;

  @protected
  InspectorPanel subtreePanel;
  final InspectorTree myRootsTree;
  final FlutterTreeType treeType;
  final InspectorService inspectorService;
  StreamSubscription<IsolateRef> flutterIsolateSubscription;

  RateLimiter _refreshRateLimiter;

  /// Groups used to manage and cancel requests to load data to display directly
  /// in the tree.
  final InspectorObjectGroupManager treeGroups;

  /// Groups used to manage and cancel requests to determine what the current
  /// selection is.
  ///
  /// This group needs to be kept separate from treeGroups as the selection is
  /// shared more with the details subtree.
  /// TODO(jacobr): is there a way we can unify the selection and tree groups?
  final InspectorObjectGroupManager selectionGroups;

  /// Node being highlighted due to the current hover.
  InspectorTreeNode currentShowNode;
  bool flutterAppFrameReady = false;
  bool treeLoadStarted = false;
  DiagnosticsNode subtreeRoot;
  bool programaticSelectionChangeInProgress = false;

  InspectorTreeNode selectedNode;
  InspectorTreeNode lastExpanded;
  bool isActive = false;
  final Map<InspectorInstanceRef, InspectorTreeNode> valueToInspectorTreeNode =
      {};

  /// When visibleToUser is false we should dispose all allocated objects and
  /// not perform any actions.
  bool visibleToUser = false;
  bool highlightNodesShownInBothTrees = false;

  bool get detailsSubtree => parentTree != null;

  DiagnosticsNode get selectedDiagnostic => selectedNode?.diagnostic;

  FlutterTreeType getTreeType() {
    return treeType;
  }

  void setVisibleToUser(bool visible) {
    if (visibleToUser == visible) {
      return;
    }
    visibleToUser = visible;

    if (subtreePanel != null) {
      subtreePanel.setVisibleToUser(visible);
    }
    if (visibleToUser) {
      if (parentTree == null) {
        maybeLoadUI();
      }
    } else {
      shutdownTree(false);
    }
  }

  /* XXX remove
  void determineSplitterOrientation() {
    if (treeSplitter == null) {
      return;
    }
    final double aspectRatio = getWidth() / getHeight();
    final bool vertical = aspectRatio < 1.4;
    if (vertical != treeSplitter.getOrientation()) {
      treeSplitter.setOrientation(vertical);
    }
  }
  */

  bool hasDiagnosticsValue(InspectorInstanceRef ref) {
    return valueToInspectorTreeNode.containsKey(ref);
  }

  DiagnosticsNode findDiagnosticsValue(InspectorInstanceRef ref) {
    return valueToInspectorTreeNode[ref]?.diagnostic;
  }

  void endShowNode() {
    highlightShowNode(null);
  }

  bool highlightShowFromNodeInstanceRef(InspectorInstanceRef ref) {
    return highlightShowNode(valueToInspectorTreeNode[ref]);
  }

  bool highlightShowNode(InspectorTreeNode node) {
    if (node == null && parentTree != null) {
      // If nothing is highlighted, highlight the node selected in the parent
      // tree so user has context of where the node selected in the parent is
      // in the details tree.
      node = findMatchingInspectorTreeNode(parentTree.selectedDiagnostic);
    }

    myRootsTree.nodeChanged(currentShowNode);
    myRootsTree.nodeChanged(node);
    currentShowNode = node;
    return true;
  }

  InspectorTreeNode findMatchingInspectorTreeNode(DiagnosticsNode node) {
    if (node?.valueRef == null) {
      return null;
    }
    return valueToInspectorTreeNode[node.valueRef];
  }

  Future<void> getPendingUpdateDone() async {
    // Wait for the selection to be resolved followed by waiting for the tree to be computed.
    await selectionGroups.pendingUpdateDone;
    await treeGroups.pendingUpdateDone;
    // TODO(jacobr): are there race conditions we need to think mroe carefully about here?
  }

  Future<void> refresh() {
    if (!visibleToUser) {
      // We will refresh again once we are visible.
      // There is a risk a refresh got triggered before the view was visble.
      return Future.value(null);
    }

    // TODO(jacobr): refresh the tree as well as just the properties.
    if (subtreePanel != null) {
      return Future.wait(
          [getPendingUpdateDone(), subtreePanel.getPendingUpdateDone()]);
    } else {
      return getPendingUpdateDone();
    }
  }

  void shutdownTree(bool isolateStopped) {
    // It is critical we clear all data that is kept alive by inspector object
    // references in this method as that stale data will trigger inspector
    // exceptions.
    programaticSelectionChangeInProgress = true;
    treeGroups.clear(isolateStopped);
    selectionGroups.clear(isolateStopped);

    currentShowNode = null;
    selectedNode = null;
    lastExpanded = null;

    selectedNode = null;
    subtreeRoot = null;

    myRootsTree.root = new InspectorTreeNode();
    if (subtreePanel != null) {
      subtreePanel.shutdownTree(isolateStopped);
    }
    programaticSelectionChangeInProgress = false;
    valueToInspectorTreeNode.clear();
  }

  void onIsolateStopped() {
    flutterAppFrameReady = false;
    treeLoadStarted = false;
    shutdownTree(true);
  }

  @override
  Future<void> onForceRefresh() {
    if (!visibleToUser) {
      return Future.value(null);
    }
    // We can't efficiently refresh the full tree in legacy mode.
    recomputeTreeRoot(null, null, false);

    return getPendingUpdateDone();
  }

  void setActivate(bool enabled) {
    if (!enabled) {
      onIsolateStopped();
      isActive = false;
      return;
    }
    if (isActive) {
      // Already activated.
      return;
    }

    isActive = true;
    inspectorService.addClient(this);
    maybeLoadUI();
  }

  Future<void> maybeLoadUI() async {
    if (!visibleToUser || !isActive) {
      return;
    }

    if (flutterAppFrameReady) {
      // We need to start by querying the inspector service to find out the
      // current state of the UI.
      await updateSelectionFromService();
    } else {
      final ready = await inspectorService.isWidgetTreeReady();
      flutterAppFrameReady = ready;
      if (isActive && ready) {
        await maybeLoadUI();
      }
    }
  }

  Future<void> recomputeTreeRoot(DiagnosticsNode newSelection,
      DiagnosticsNode detailsSelection, bool setSubtreeRoot) async {
    treeGroups.cancelNext();
    try {
      final group = treeGroups.next;
      final node = await (detailsSubtree
          ? group.getDetailsSubtree(subtreeRoot)
          : group.getRoot(treeType));
      if (node == null || group.disposed) {
        return;
      }
      // TODO(jacobr): as a performance optimization we should check if the
      // new tree is identical to the existing tree in which case we should
      // dispose the new tree and keep the old tree.
      treeGroups.promoteNext();
      clearValueToInspectorTreeNodeMapping();
      if (node != null) {
        final InspectorTreeNode rootNode =
            setupInspectorTreeNode(new InspectorTreeNode(), node, true);
        myRootsTree.root = rootNode;
      } else {
        myRootsTree.root = new InspectorTreeNode();
      }
      refreshSelection(newSelection, detailsSelection, setSubtreeRoot);
    } catch (error) {
      _logError(error);
      treeGroups.cancelNext();
      return;
    }
  }

  void clearValueToInspectorTreeNodeMapping() {
    if (parentTree != null) {
      valueToInspectorTreeNode.keys.forEach(parentTree.maybeUpdateValueUI);
    }
    valueToInspectorTreeNode.clear();
  }

  /// Show the details subtree starting with node subtreeRoot highlighting
  /// node subtreeSelection.
  void showDetailSubtrees(
      DiagnosticsNode subtreeRoot, DiagnosticsNode subtreeSelection) {
    // TODO(jacobr): handle render objects subtree panel and other subtree panels here.

    this.subtreeRoot = subtreeRoot;
    myRootsTree.highlightedRoot = getSubtreeRootNode();
    if (subtreePanel != null) {
      subtreePanel.setSubtreeRoot(subtreeRoot, subtreeSelection);
    }
  }

  InspectorInstanceRef getSubtreeRootValue() {
    return subtreeRoot != null ? subtreeRoot.valueRef : null;
  }

  void setSubtreeRoot(DiagnosticsNode node, DiagnosticsNode selection) {
    assert(detailsSubtree);
    selection ??= node;
    if (node != null && node == subtreeRoot) {
      //  Select the new node in the existing subtree.
      applyNewSelection(selection, null, false);
      return;
    }
    subtreeRoot = node;
    if (node == null) {
      // Passing in a null node indicates we should clear the subtree and free any memory allocated.
      shutdownTree(false);
      return;
    }

    // Clear now to eliminate frame of highlighted nodes flicker.
    clearValueToInspectorTreeNodeMapping();
    recomputeTreeRoot(selection, null, false);
  }

  InspectorTreeNode getSubtreeRootNode() {
    if (subtreeRoot == null) {
      return null;
    }
    return valueToInspectorTreeNode[subtreeRoot.valueRef];
  }

  void refreshSelection(DiagnosticsNode newSelection,
      DiagnosticsNode detailsSelection, bool setSubtreeRoot) {
    newSelection ??= getSelectedDiagnostic();
    setSelectedNode(findMatchingInspectorTreeNode(newSelection));
    syncSelectionHelper(setSubtreeRoot, detailsSelection);

    if (subtreePanel != null) {
      if (subtreeRoot != null && getSubtreeRootNode() == null) {
        subtreeRoot = newSelection;
        subtreePanel.setSubtreeRoot(newSelection, detailsSelection);
      }
    }
    myRootsTree.highlightedRoot = getSubtreeRootNode();

    syncTreeSelection();
  }

  void syncTreeSelection() {
    programaticSelectionChangeInProgress = true;
    myRootsTree.selection = selectedNode;
    programaticSelectionChangeInProgress = false;
    animateTo(selectedNode);
  }

  void selectAndShowNode(DiagnosticsNode node) {
    if (node == null) {
      return;
    }
    selectAndShowInspectorInstanceRef(node.valueRef);
  }

  void selectAndShowInspectorInstanceRef(InspectorInstanceRef ref) {
    final node = valueToInspectorTreeNode[ref];
    if (node == null) {
      return;
    }
    setSelectedNode(node);
    syncTreeSelection();
  }

  InspectorTreeNode getTreeNode(DiagnosticsNode node) {
    if (node == null) {
      return null;
    }
    return valueToInspectorTreeNode[node.valueRef];
  }

  void maybeUpdateValueUI(InspectorInstanceRef valueRef) {
    final node = valueToInspectorTreeNode[valueRef];
    if (node == null) {
      // The value isn't shown in the parent tree. Nothing to do.
      return;
    }
    myRootsTree.nodeChanged(node);
  }

  InspectorTreeNode setupInspectorTreeNode(InspectorTreeNode node,
      DiagnosticsNode diagnosticsNode, bool expandChildren) {
    node.diagnostic = diagnosticsNode;
    final InspectorInstanceRef valueRef = diagnosticsNode.valueRef;
    // Properties do not have unique values so should not go in the valueToInspectorTreeNode map.
    if (valueRef.id != null && !diagnosticsNode.isProperty) {
      valueToInspectorTreeNode[valueRef] = node;
    }
    if (parentTree != null) {
      parentTree.maybeUpdateValueUI(valueRef);
    }
    if (diagnosticsNode.hasChildren ||
        diagnosticsNode.inlineProperties.isNotEmpty) {
      if (diagnosticsNode.childrenReady || !diagnosticsNode.hasChildren) {
        setupChildren(
            diagnosticsNode, node, node.diagnostic.childrenNow, expandChildren);
      } else {
        node.clearChildren();
        node.appendChild(new InspectorTreeNode());
      }
    }
    return node;
  }

  void setupChildren(DiagnosticsNode parent, InspectorTreeNode treeNode,
      List<DiagnosticsNode> children, bool expandChildren) {
    if (treeNode.children.isNotEmpty) {
      // Only case supported is this is the loading node.
      assert(treeNode.children.length == 1);
      myRootsTree.removeNodeFromParent(treeNode.children.first);
    }
    final inlineProperties = parent.inlineProperties;

    if (inlineProperties != null) {
      for (DiagnosticsNode property in inlineProperties) {
        myRootsTree.appendChild(treeNode,
            setupInspectorTreeNode(new InspectorTreeNode(), property, false));
      }
    }
    for (DiagnosticsNode child in children) {
      myRootsTree.appendChild(
          treeNode,
          setupInspectorTreeNode(
              new InspectorTreeNode(), child, expandChildren));
    }
  }

  Future<void> maybeLoadChildren(InspectorTreeNode node) async {
    if (node?.diagnostic == null) return;
    final DiagnosticsNode diagnosticsNode = node.diagnostic;
    if (diagnosticsNode.hasChildren ||
        diagnosticsNode.inlineProperties.isNotEmpty) {
      if (hasPlaceholderChildren(node)) {
        try {
          final children = await diagnosticsNode.children;
          if (!identical(node.diagnostic, diagnosticsNode) ||
              children == null) {
            // Node changed, this data is stale.
            return;
          }
          setupChildren(diagnosticsNode, node, children, true);
          if (node == selectedNode || node == lastExpanded) {
            animateTo(node);
          }
        } catch (e) {
          // ignore error.
        }
      }
    }
  }

  @override
  void onFlutterFrame() {
    flutterAppFrameReady = true;
    if (!visibleToUser) {
      return;
    }

    if (!treeLoadStarted) {
      treeLoadStarted = true;
      // This was the first frame.
      maybeLoadUI();
    }
    _refreshRateLimiter.scheduleRequest();
  }

  bool identicalDiagnosticsNodes(DiagnosticsNode a, DiagnosticsNode b) {
    if (a == b) {
      return true;
    }
    if (a == null || b == null) {
      return false;
    }
    return a.getDartDiagnosticRef() == b.getDartDiagnosticRef();
  }

  @override
  void onInspectorSelectionChanged() {
    if (!visibleToUser) {
      // Don't do anything. We will update the view once it is visible again.
      return;
    }
    if (detailsSubtree) {
      // Wait for the master to update.
      return;
    }
    updateSelectionFromService();
  }

  Future<void> updateSelectionFromService() async {
    treeLoadStarted = true;
    selectionGroups.cancelNext();

    final group = selectionGroups.next;
    final pendingSelectionFuture =
        group.getSelection(getSelectedDiagnostic(), treeType, isSummaryTree);

    final Future<DiagnosticsNode> pendingDetailsFuture = isSummaryTree
        ? group.getSelection(getSelectedDiagnostic(), treeType, false)
        : null;

    try {
      final DiagnosticsNode newSelection = await pendingSelectionFuture;
      if (group.disposed) return;
      DiagnosticsNode detailsSelection;

      if (pendingDetailsFuture != null) {
        detailsSelection = await pendingDetailsFuture;
        if (group.disposed) return;
      }

      selectionGroups.promoteNext();

      subtreeRoot = newSelection;

      applyNewSelection(newSelection, detailsSelection, true);
    } catch (error) {
      if (selectionGroups.next == group) {
        _logError(error);
        selectionGroups.cancelNext();
      }
    }
  }

  void applyNewSelection(DiagnosticsNode newSelection,
      DiagnosticsNode detailsSelection, bool setSubtreeRoot) {
    final InspectorTreeNode nodeInTree =
        findMatchingInspectorTreeNode(newSelection);

    if (nodeInTree == null) {
      // The tree has probably changed since we last updated. Do a full refresh
      // so that the tree includes the new node we care about.
      recomputeTreeRoot(newSelection, detailsSelection, setSubtreeRoot);
    }

    refreshSelection(newSelection, detailsSelection, setSubtreeRoot);
  }

  DiagnosticsNode getSelectedDiagnostic() => selectedNode?.diagnostic;

  void animateTo(InspectorTreeNode node) {
    if (node == null) {
      return;
    }
    final List<InspectorTreeNode> targets = [node];

    // Backtrack to the the first non-property parent so that all properties
    // for the node are visible if one property is animated to. This is helpful
    // as typically users want to view the properties of a node as a chunk.
    while (node != null && node.diagnostic?.isProperty == true) {
      node = node.parent;
    }
    // Make sure we scroll so that immediate un-expanded children
    // are also in view. There is no risk in including these children as
    // the amount of space they take up is bounded. This also ensures that if
    // a node is selected, its properties will also be selected as by
    // convention properties are the first children of a node and properties
    // typically do not have children and are never expanded by default.
    for (InspectorTreeNode child in node.children) {
      final DiagnosticsNode diagnosticsNode = child.diagnostic;
      targets.add(child);
      if (!child.isLeaf && child.expanded) {
        // Stop if we get to expanded children as they might be too large
        // to try to scroll into view.
        break;
      }
      if (diagnosticsNode != null && !diagnosticsNode.isProperty) {
        break;
      }
    }
    animateToTargets(targets);
  }

  void animateToTargets(List<InspectorTreeNode> targets) {
    throw 'Unimplemented';
  }

  Future<void> maybePopulateChildren(InspectorTreeNode treeNode) async {
    final DiagnosticsNode diagnostic = treeNode.diagnostic;
    if (diagnostic.hasChildren && treeNode.children.isEmpty) {
      try {
        final children = await diagnostic.children;
        if (treeNode.children.isEmpty) {
          setupChildren(diagnostic, treeNode, children, true);
        }
        myRootsTree.nodeChanged(treeNode);
        if (treeNode == selectedNode) {
          myRootsTree.expandPath(treeNode);
        }
      } catch (e) {
        _logError(e);
      }
    }
  }

  void setSelectedNode(InspectorTreeNode newSelection) {
    if (newSelection == selectedNode) {
      return;
    }
    if (selectedNode != null) {
      if (!detailsSubtree) {
        myRootsTree.nodeChanged(selectedNode.parent);
      }
    }
    selectedNode = newSelection;
    animateTo(selectedNode);

    lastExpanded = null; // New selected node takes prescidence.
    endShowNode();
    if (subtreePanel != null) {
      subtreePanel.endShowNode();
    } else if (parentTree != null) {
      parentTree.endShowNode();
    }
  }

  void selectionChanged() {
    if (visibleToUser == false) {
      return;
    }

    final InspectorTreeNode node = myRootsTree.selection;
    if (node != null) {
      maybePopulateChildren(node);
    }
    if (programaticSelectionChangeInProgress) {
      return;
    }
    if (node != null) {
      setSelectedNode(node);

      final DiagnosticsNode selectedDiagnostic = getSelectedDiagnostic();
      // Don't reroot if the selected value is already visible in the details tree.
      final bool maybeReroot = isSummaryTree &&
          subtreePanel != null &&
          selectedDiagnostic != null &&
          !subtreePanel.hasDiagnosticsValue(selectedDiagnostic.valueRef);
      syncSelectionHelper(maybeReroot, null);
      if (maybeReroot == false) {
        if (isSummaryTree && subtreePanel != null) {
          subtreePanel.selectAndShowNode(selectedDiagnostic);
        } else if (parentTree != null) {
          parentTree.selectAndShowNode(firstAncestorInParentTree(selectedNode));
        }
      }
    }
  }

  DiagnosticsNode firstAncestorInParentTree(InspectorTreeNode node) {
    if (parentTree == null) {
      return node.diagnostic;
    }
    while (node != null) {
      final diagnostic = node.diagnostic;
      if (diagnostic != null &&
          parentTree.hasDiagnosticsValue(diagnostic.valueRef)) {
        return parentTree.findDiagnosticsValue(diagnostic.valueRef);
      }
      node = node.parent;
    }
    return null;
  }

  void syncSelectionHelper(
      bool maybeRerootSubtree, DiagnosticsNode detailsSelection) {
    if (!detailsSubtree && selectedNode != null) {
      myRootsTree.nodeChanged(selectedNode.parent);
    }
    final DiagnosticsNode diagnostic = getSelectedDiagnostic();
    if (diagnostic != null) {
      if (diagnostic.isCreatedByLocalProject) {
        _navigateTo(diagnostic);
      }
    }
    if (detailsSubtree || subtreePanel == null) {
      if (diagnostic != null) {
        var toSelect = selectedNode;

        while (toSelect != null && toSelect.diagnostic.isProperty) {
          toSelect = toSelect.parent;
        }
        if (toSelect != null) {
          final diagnosticToSelect = toSelect.diagnostic;
          diagnosticToSelect.inspectorService
              .setSelectionInspector(diagnosticToSelect.valueRef, true);
        }
      }
    }

    if (maybeRerootSubtree) {
      showDetailSubtrees(diagnostic, detailsSelection);
    } else if (diagnostic != null) {
      // We can't rely on the details tree to update the selection on the server in this case.
      final selection =
          detailsSelection != null ? detailsSelection : diagnostic;
      selection.inspectorService
          .setSelectionInspector(selection.valueRef, true);
    }
  }

  void _navigateTo(DiagnosticsNode diagnostic) {
    // Dispatch an event over the inspectorService requesting a navigate operation.
    throw 'Unimplemented';
  }

/* XXX
  void initTree(final Tree tree) {
    // XXX
    // tree.setCellRenderer(new DiagnosticsTreeCellRenderer(this));
  }
  */

  void dispose() {
    flutterIsolateSubscription.cancel();
    // TODO(jacobr): actually implement.
    if (inspectorService != null) {
      shutdownTree(false);
    }
    // TODO(jacobr): verify subpanels are disposed as well.
  }

  static String treeTypeDisplayName(FlutterTreeType treeType) {
    switch (treeType) {
      case FlutterTreeType.widget:
        return 'Widget';
      case FlutterTreeType.renderObject:
        return 'Render Objects';
    }
    return null;
  }

  bool hasPlaceholderChildren(InspectorTreeNode node) {
    return node.children.length == 1 && node.children.first.diagnostic == null;
  }
}

//
class InspectorScreen extends Screen {
  InspectorScreen()
      : super(
            name: 'Inspector',
            id: 'inspector',
            iconClass: 'octicon-telescope') {
    treeStatus = new StatusItem();
    addStatusItem(treeStatus);
  }

  PButton refreshTreeButton;
  StatusItem treeStatus;

  SetStateMixin inspectorStateMixin = new SetStateMixin();
  InspectorService inspectorService;
  InspectorPanel inspectorPanel;
  ProgressElement progressElement;
  CoreElement tableContainer;

  @override
  void createContent(Framework framework, CoreElement mainDiv) {
    mainDiv.add(<CoreElement>[
      div(c: 'section'),
      div(c: 'section')
        ..add(<CoreElement>[
          form()
            ..layoutHorizontal()
            ..clazz('align-items-center')
            ..add(<CoreElement>[
              refreshTreeButton = new PButton('Refresh Tree')
                ..small()
                ..primary()
                ..disabled = true
                ..click(_refreshInspector),
              progressElement = new ProgressElement()
                ..clazz('margin-left')
                ..display = 'none',
              div()..flex(),
            ])
        ]),
      tableContainer = div(c: 'section overflow-auto')..layoutHorizontal(),
    ]);

    // TODO(devoncarew): don't rebuild until the component is active
    serviceManager.isolateManager.onSelectedIsolateChanged.listen((_) {
      _handleIsolateChanged();
    });

    serviceManager.onConnectionAvailable.listen(_handleConnectionStart);
    if (serviceManager.hasConnection) {
      _handleConnectionStart(serviceManager.service);
    }
    serviceManager.onConnectionClosed.listen(_handleConnectionStop);
  }

  void _handleIsolateChanged() {
    // TODO(devoncarew): update buttons
  }

  String get _isolateId => serviceManager.isolateManager.selectedIsolate.id;

  Future<Null> _loadInspector() async {
    refreshTreeButton.disabled = true;

    final Spinner spinner = new Spinner()..clazz('padded');
    tableContainer.element.children.add(spinner.element);

    // TODO(devoncarew): error handling

    try {
      spinner.element.remove();
    } finally {
      refreshTreeButton.disabled = false;
    }
  }

  // TODO(jacobr): Update this url.
  @override
  HelpInfo get helpInfo =>
      new HelpInfo(title: 'Inspector docs', url: 'http://www.cheese.com');

  void _handleConnectionStart(VmService service) async {
    refreshTreeButton.disabled = false;

    inspectorService = await InspectorService.create(service);
    // TODO(jacobr): handle connections that started and stopped immediately.

    inspectorPanel = new InspectorPanel(
      inspectorService: inspectorService,
      treeType: FlutterTreeType.widget,
    );
    // XXX update UI.
  }

  void _handleConnectionStop(dynamic event) {
    refreshTreeButton.disabled = true;
    if (inspectorPanel != null) {
      inspectorPanel.dispose();
      inspectorPanel = null;
    }
  }

  void _refreshInspector() {
    print('XXX refresh inspector');
  }
}
