@JS()
library splitter;

import 'dart:html';

import 'package:js/js.dart' show JS, allowInterop, anonymous;
import 'package:js/js_util.dart' as js_util;

typedef ElementStyleCallback = Function(
    Object dimension, Object size, num gutterSize);
typedef GutterStyleCallback = Function(Object dimension, num gutterSize);

@JS()
@anonymous
class SplitOptions {
  external SplitOptions({
    ElementStyleCallback elementStyle,
    GutterStyleCallback gutterStyle,
    String direction,
    num gutterSize,
  });

  external ElementStyleCallback get elementStyle;

  external GutterStyleCallback get gutterStyle;

  external String get direction;

  external num get gutterSize;
}

@JS('Split')
external Splitter _split(List parts, SplitOptions options);

@JS()
@anonymous
class Splitter {
  external void setSizes(List sizes);

  external List getSizes();

  external void collapse();

  external void destroy([bool preserveStyles, bool preserveGutters]);
}

Splitter flexSplit(List parts, {bool horizontal = true, gutterSize = 5}) {
  return _split(
    parts,
    new SplitOptions(
      elementStyle: allowInterop((dimension, size, gutterSize) {
        return js_util.jsify({
          'flex-basis': 'calc($size% - ${gutterSize}px)',
        });
      }),
      gutterStyle: allowInterop((dimension, gutterSize) {
        return js_util.jsify({
          'flex-basis': '${gutterSize}px',
        });
      }),
      direction: horizontal ? 'horizontal' : 'vertical',
      gutterSize: gutterSize,
    ),
  );
}

/// Creates a splitter that changes from horizontal to vertical depending
/// on the window aspect ratio.
void flexSplitBidirectional(List parts, {gutterSize = 5}) {
  // TODO(jacobr): memory associated with this splitter is never released.
  final mediaQueryList = window.matchMedia('(min-aspect-ratio: 1/1)');
  Splitter splitter;
  void createSplitter() {
    splitter = flexSplit(
      parts,
      horizontal: mediaQueryList.matches,
      gutterSize: gutterSize,
    );
  }

  createSplitter();
  mediaQueryList.onChange.listen((e) {
    splitter.destroy(true, false);
    createSplitter();
  });
}
