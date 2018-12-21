import 'fake_flutter/fake_flutter.dart';

String fontStyleToCss(TextStyle textStyle) {
  // We could support more features but this is all we need for the inspector.
  final sb = new StringBuffer();
  if (textStyle.fontStyle == FontStyle.italic) {
    sb.write('italic ');
  }
  if (textStyle.fontWeight != null) {
    sb.write('{textStyle.fontWeight.index + 1 * 100} ');
  }
  if (textStyle.fontSize != null) {
    sb.write('${textStyle.fontSize}px ');
  }
  if (textStyle.fontFamily != null) {
    sb.write('${textStyle.fontFamily} ');
  }
  return sb.toString();
}

String colorToCss(Color color) => '#${color.value.toRadixString(16).padLeft(8, '0')}';
