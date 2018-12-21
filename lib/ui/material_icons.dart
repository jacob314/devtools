library material_icons;

import 'fake_flutter/fake_flutter.dart';
import 'icons.dart';

// TODO(jacobr): there is currently a race condition if we try to render a
// material icon before the material web font has loaded. Fix it by making
// loadImage truly async and block until the font is loaded.
// TODO(jacobr): this class is actually very similar to the Flutter Icon
// Widget class.
class MaterialIcon extends Icon {
  const MaterialIcon(
    this.text,
    this.color, {
    this.fontSize = 18,
    this.iconWidth = 18,
  });

  final String text;
  final Color color;
  final int fontSize;

  @override
  final int iconWidth;
}

class FlutterMaterialIcons {
  FlutterMaterialIcons._();
  static final Map<String, MaterialIcon> _iconCache = {};

  static Icon getIconForCodePoint(int charCode) {
    final String code = String.fromCharCode(charCode);
    return _iconCache.putIfAbsent(code, () => MaterialIcon(code, Colors.black));
  }
}
