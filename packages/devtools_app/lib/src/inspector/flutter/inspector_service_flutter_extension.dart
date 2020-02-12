import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';

import '../diagnostics_node.dart';
import '../inspector_service.dart';

// TODO(jacobr): merge these into inspector_service once the dart:html
// version of the app is removed.
extension InspectorFlutterService on ObjectGroup {
  Future<void> invokeSetFlexProperties(
    InspectorInstanceRef ref,
    MainAxisAlignment mainAxisAlignment,
    CrossAxisAlignment crossAxisAlignment,
  ) async {
    if (ref == null) return null;
    await invokeServiceExtensionMethod(
      RegistrableServiceExtension.setFlexProperties,
      {
        'id': ref.id,
        'mainAxisAlignment': '$mainAxisAlignment',
        'crossAxisAlignment': '$crossAxisAlignment',
      },
    );
  }

  Future<void> invokeSetFlexFactor(
    InspectorInstanceRef ref,
    int flexFactor,
  ) async {
    if (ref == null) return null;
    await invokeServiceExtensionMethod(
      RegistrableServiceExtension.setFlexFactor,
      {'id': ref.id, 'flexFactor': '$flexFactor'},
    );
  }

  Future<void> invokeSetFlexFit(
    InspectorInstanceRef ref,
    FlexFit flexFit,
  ) async {
    if (ref == null) return null;
    await invokeServiceExtensionMethod(
      RegistrableServiceExtension.setFlexFit,
      {'id': ref.id, 'flexFit': '$flexFit'},
    );
  }

  Future<RemoteDiagnosticsNode> getLayoutExplorerNode(
    RemoteDiagnosticsNode node, {
    int subtreeDepth = 1,
  }) async {
    if (node == null) return null;
    return parseDiagnosticsNodeDaemon(invokeServiceExtensionMethod(
      RegistrableServiceExtension.getLayoutExplorerNode,
      {
        'groupName': groupName,
        'id': node.dartDiagnosticRef.id,
        'subtreeDepth': '$subtreeDepth',
      },
    ));
  }
}
