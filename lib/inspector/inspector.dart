// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

library inspector;

import 'package:devtools/inspector/inspector_tree_html.dart';
import 'package:devtools/ui/icons.dart';
import 'package:devtools/service_extensions.dart' as extensions;
import 'package:devtools/ui/split.dart';
import 'package:devtools/ui/ui_utils.dart';
import 'package:vm_service_lib/vm_service_lib.dart';

import '../framework/framework.dart';
import '../globals.dart';
import '../ui/custom.dart';
import '../ui/elements.dart';
import '../ui/primer.dart';
import 'inspector_controller.dart';
import 'inspector_service.dart';

class InspectorScreen extends Screen {
  InspectorScreen()
      : super(
            name: 'Inspector',
            id: 'inspector',
            iconClass: 'octicon-device-mobile') {
    treeStatus = StatusItem();
    addStatusItem(treeStatus);
  }

  PButton refreshTreeButton;
  StatusItem treeStatus;

  SetStateMixin inspectorStateMixin = SetStateMixin();
  InspectorService inspectorService;
  InspectorController inspectorPanel;
  ProgressElement progressElement;
  CoreElement inspectorContainer;

  @override
  void createContent(Framework framework, CoreElement mainDiv) {
    mainDiv.add(<CoreElement>[
      div(c: 'section'),
      div(c: 'section')
        ..layoutHorizontal()
        ..add(<CoreElement>[
          div(c: 'btn-group')
            ..add([
              createExtensionButton(
                extensions.toggleSelectWidgetMode,
              ),
              refreshTreeButton =
                  PButton.icon('Refresh Tree', FlutterIcons.forceRefresh)
                    ..small()
                    ..disabled = true
                    ..click(_refreshInspector),
            ]),
          progressElement = ProgressElement()
            ..clazz('margin-left')
            ..display = 'none',
          div()..flex(),
          div(c: 'btn-group collapsible')
            ..add(<CoreElement>[
              createExtensionButton(extensions.performanceOverlay),
              // TODO(jacobr): enable toggle platform extension.
              // createExtensionButton(extensions.togglePlatform),
              createExtensionButton(extensions.debugPaint)..clazz('collapsible'),
              createExtensionButton(extensions.debugPaintBaselines),
              // TODO(jacobr): add slow animations extension
              // createExtensionButton(extensions.slowAnimations),

              // These extensions could be demoted to a menu.
              createExtensionButton(extensions.repaintRainbow),
              createExtensionButton(extensions.debugAllowBanner),
            ]),
        ]),
      inspectorContainer = div(c: 'inspector-container'),
    ]);

    serviceManager.onConnectionAvailable.listen(_handleConnectionStart);
    if (serviceManager.hasConnection) {
      _handleConnectionStart(serviceManager.service);
    }
    serviceManager.onConnectionClosed.listen(_handleConnectionStop);
  }

  @override
  HelpInfo get helpInfo {
    return HelpInfo(
      title: 'Inspector docs',
      url: 'https://flutter.io/docs/development/tools/inspector',
    );
  }

  void _handleConnectionStart(VmService service) async {
    refreshTreeButton.disabled = false;

    final Spinner spinner = Spinner()..clazz('padded');
    inspectorContainer.element.children.add(spinner.element);

    inspectorService = await InspectorService.create(service);

    // TODO(jacobr): error handling

    try {
      spinner.element.remove();
    } finally {
      refreshTreeButton.disabled = false;
    }

    inspectorPanel = InspectorController(
      inspectorTreeFactory: ({
        summaryTree,
        treeType,
        onSelectionChange,
        onExpand,
        onHover,
      }) {
        return new InspectorTreeHtml(
          summaryTree: summaryTree,
          treeType: treeType,
          onSelectionChange: onSelectionChange,
          onExpand: onExpand,
          onHover: onHover,
        );
      },
      inspectorService: inspectorService,
      treeType: FlutterTreeType.widget,
    );
    final InspectorTreeHtml inspectorTree = inspectorPanel.inspectorTree;
    final InspectorTreeHtml detailsInspectorTree =
        inspectorPanel.subtreePanel.inspectorTree;

    final elements = [
      inspectorTree.element.element,
      detailsInspectorTree.element.element
    ];
    inspectorContainer.add(elements);
    flexSplitBidirectional(elements);

    inspectorPanel.setVisibleToUser(true);
    inspectorPanel.setActivate(true);
  }

  void _handleConnectionStop(dynamic event) {
    refreshTreeButton.disabled = true;
    inspectorPanel.setActivate(false);

    if (inspectorPanel != null) {
      inspectorPanel.dispose();
      inspectorPanel = null;
    }
  }

  void _refreshInspector() {
    inspectorPanel?.onForceRefresh();
  }
}
