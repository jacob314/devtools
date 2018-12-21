import 'package:devtools/ui/icons.dart';

class FlutterMaterialIcons {

  FlutterMaterialIcons._();

  static final Map<String, String> _iconPaths = {};

  /*
  static {
  icons = new Properties();

  try {
  icons.load(FlutterEditorAnnotator.class.getResourceAsStream("/flutter/material_icons.properties"));
  }
  catch (IOException e) {
  LOG.warn(e);
  }
}
*/

 static Icon getIconForHex(String hexValue) {
   final String iconName = _iconPaths['$hexValue.codepoint'];
   return getIcon(iconName);
 }

  static Icon getIconForName(String name) {
    return getIcon(name);
  }

  static Icon getIcon(String name) {
    if (name == null) {
      return null;
    }
  final String path = _iconPaths[name];
  if (path == null) {
    return null;
  }
  // TODO(jacobr): implement turning these into UrlIcons and dealing with the
    // fact that it now needs to be more async.
  return null;
//  return IconLoader.findIcon(path, FlutterMaterialIcons.class);
}
}
