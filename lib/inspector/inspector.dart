// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

library inspector;

import 'dart:async';

import 'package:vm_service_lib/vm_service_lib.dart';

import '../framework/framework.dart';
import '../globals.dart';
import '../service_extensions.dart' as extensions;
import '../ui/custom.dart';
import '../ui/elements.dart';
import '../ui/icons.dart';
import '../ui/primer.dart';
import '../ui/split.dart';
import '../ui/ui_utils.dart';

import 'inspector_controller.dart';
import 'inspector_service.dart';
import 'inspector_tree_html.dart';

class InspectorScreen extends Screen {
  InspectorScreen()
      : super(
          name: 'Inspector',
          id: 'inspector',
          iconClass: 'octicon-device-mobile',
        );

  PButton refreshTreeButton;

  SetStateMixin inspectorStateMixin = SetStateMixin();
  InspectorService inspectorService;
  InspectorController inspectorPanel;
  ProgressElement progressElement;
  CoreElement inspectorContainer;
  StreamSubscription<Object> splitterSubscription;

  @override
  void createContent(Framework framework, CoreElement mainDiv) {
    mainDiv.add(<CoreElement>[
      div(c: 'section')
        ..layoutHorizontal()
        ..add(<CoreElement>[
          div(c: 'btn-group')
            ..add([
              ServiceExtensionButton(
                extensions.toggleSelectWidgetMode,
              ).button,
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
              ServiceExtensionButton(extensions.performanceOverlay).button,
              ServiceExtensionButton(extensions.togglePlatformMode).button,
              ServiceExtensionButton(extensions.debugPaint).button,
              ServiceExtensionButton(extensions.debugPaintBaselines).button,
              ServiceExtensionButton(extensions.slowAnimations).button,

              // These extensions could be demoted to a menu.
              ServiceExtensionButton(extensions.repaintRainbow).button,
              ServiceExtensionButton(extensions.debugAllowBanner).button,
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
    inspectorContainer.add(spinner);

    try {
      inspectorService = await InspectorService.create(service);
    } finally {
      spinner.element.remove();
      refreshTreeButton.disabled = false;
    }

    // TODO(jacobr): support the Render tree, Layer tree, and Semantic trees as
    // well as the widget tree.

    inspectorPanel = InspectorController(
      inspectorTreeFactory: ({
        summaryTree,
        treeType,
        onSelectionChange,
        onExpand,
        onHover,
      }) {
        return InspectorTreeHtml(
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
        inspectorPanel.details.inspectorTree;

    final elements = [
      inspectorTree.element.element,
      detailsInspectorTree.element.element
    ];
    inspectorContainer.add(elements);
    splitterSubscription = flexSplitBidirectional(elements);

    // TODO(jacobr): update visibility based on whether the screen is visible.
    // That will reduce memory usage on the device running a Flutter application
    // when the inspector panel is not visible.
    inspectorPanel.setVisibleToUser(true);
    inspectorPanel.setActivate(true);
  }

  void _handleConnectionStop(dynamic event) {
    refreshTreeButton.disabled = true;

    if (inspectorPanel != null) {
      inspectorPanel.setActivate(false);
      inspectorPanel.dispose();
      inspectorPanel = null;
    }

    splitterSubscription?.cancel();
    splitterSubscription = null;
  }

  void _refreshInspector() {
    inspectorPanel?.onForceRefresh();
  }
}
