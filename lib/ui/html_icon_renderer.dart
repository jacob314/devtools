/// Icons are defined in a platform independent way so tests can run on the VM
/// and to simplify porting code to work with Hummingbird.
library icon_renderer;

import 'dart:async';
import 'dart:html';

import 'package:devtools/ui/fake_flutter/fake_flutter.dart';
import 'package:devtools/ui/flutter_html_shim.dart';
import 'package:devtools/ui/material_icons.dart';
import 'package:meta/meta.dart';

import 'elements.dart';
import 'icons.dart';

final Expando<HtmlIconRenderer> rendererExpando = Expando('IconRenderer');

typedef DrawIconImageCallback = void Function(CanvasRenderingContext2D element);

abstract class HtmlIconRenderer<T extends Icon> {
  HtmlIconRenderer(this.icon);

  CanvasImageSource get image;
  bool get loaded => image != null;

  CoreElement createElement() {
    // All CanvasImageSource types are really elements but Dart can't quite
    // figure that out.
    final Element element = createCanvasSource() as Element;

    element.style.width = '${icon.iconWidth}px';
    element.style.height = '${icon.iconWidth}px';
    // Somne icons may have incorrect heights.
    element.classes.add('flutter-icon');
    return new CoreElement.from(element);
  }
  
  @protected
  CanvasImageSource createCanvasSource();

  Future<CanvasImageSource> loadImage();

  final T icon;

  int get iconWidth => icon.iconWidth;
  int get iconHeight => icon.iconHeight;
}


class UrlIconRenderer extends HtmlIconRenderer<UrlIcon> {
  UrlIconRenderer(UrlIcon icon) :
    src = _maybeRewriteIconUrl(icon.src),
    super(icon);

  static String _maybeRewriteIconUrl(String url) {
    if (window.devicePixelRatio > 1 &&
        url.endsWith('.png') &&
        !url.endsWith('@2x.png')) {
      // By convention icons all have high DPI verisons with @2x added to the
      // file name.
      return '${url.substring(0, url.length - 4)}@2x.png';
    }
    return url;
  }

  final String src;

  @override
  CanvasImageSource get image => _image;
  ImageElement _image;

  Future<CanvasImageSource> _imageFuture;

  @override
  ImageElement createCanvasSource() => new ImageElement(src: src);

  @override
  CoreElement createElement() {
    // We use a div rather than an ImageElement to display the image directly
    // in the DOM as backgroundImage styling is more flexible.
    final element = div(c: 'flutter-icon');
    element.element.style
      ..width = '${icon.iconWidth}px'
      ..height ='${icon.iconHeight}px'
      ..backgroundImage = 'url($src)';
    return element;
  }

  @override
  Future<CanvasImageSource> loadImage() {
    if (_imageFuture != null) {
      return _imageFuture;
    }
    final Completer<CanvasImageSource> completer = new Completer();
    final imageElement = createCanvasSource();
    imageElement.onLoad.listen((e) {
      _image = imageElement;
      completer.complete(imageElement);
    });
    document.head.append(imageElement); // XXX is this needed?
    _imageFuture = completer.future;
    return _imageFuture;
  }
}


class ColorIconRenderer extends HtmlIconRenderer<ColorIcon> {
  ColorIconRenderer(ColorIcon icon) : super(icon);

  static const int iconMargin = 1;

  Color get color => icon.color;

  @override
  CanvasElement createCanvasSource() {
    final devicePixelRatio = window.devicePixelRatio;
    final canvas = new CanvasElement(
      width: iconWidth * devicePixelRatio,
      height: iconHeight * devicePixelRatio,
    );
    canvas.style
      ..width = '${iconWidth}px'
      ..height = '${iconHeight}px';
    final context = canvas.context2D;

    context.scale(devicePixelRatio, devicePixelRatio);
    context.clearRect(0, 0, iconWidth, iconHeight);

    // draw a black and gray grid to use as the background to disambiguate
    // opaque colors from translucent colors.
    context
      ..fillStyle = 'white'
      ..fillRect(iconMargin, iconMargin, iconWidth - iconMargin * 2,
          iconHeight - iconMargin * 2)
      ..fillStyle = 'gray'
      ..fillRect(iconMargin, iconMargin, iconWidth / 2 - iconMargin,
          iconHeight / 2 - iconMargin)
      ..fillRect(iconWidth / 2, iconHeight / 2, iconWidth / 2 - iconMargin,
          iconHeight / 2 - iconMargin)
      ..fillStyle = colorToCss(color)
      ..fillRect(iconMargin, iconMargin, iconWidth - iconMargin * 2,
          iconHeight - iconMargin * 2)
      ..strokeStyle = 'black'
      ..rect(iconMargin, iconMargin, iconWidth - iconMargin * 2,
          iconHeight - iconMargin * 2)
      ..stroke();
    return canvas;
  }

  @override
  // TODO: implement image
  CanvasImageSource get image {
    if (_image != null) {
      return _image;
    }
    _image = createCanvasSource();
    return _image;
  }

  CanvasElement _image;

  @override
  Future<CanvasImageSource> loadImage() async {
    // This icon does not perform any async work.
    return image;
  }

  @override
  int get iconWidth => 18;
  @override
  int get iconHeight => 18;
}

class CustomIconRenderer extends HtmlIconRenderer<CustomIcon> {
  CustomIconRenderer(CustomIcon icon) :
        baseIconRenderer = getIconRenderer(icon.baseIcon),
        super(icon);

  final HtmlIconRenderer baseIconRenderer;

  @override
  CanvasImageSource createCanvasSource() {
    final baseImage = baseIconRenderer.image;
    if (baseImage == null) return null;

    return _buildImage(baseImage);
  }

  @override
  CanvasImageSource get image {
    if (_image != null) return _image;
    final baseImage = baseIconRenderer.image;
    if (baseImage == null) return null;

    _image = createCanvasSource();
    return _image;
  }

  CanvasElement _image;

  @override
  Future<CanvasImageSource> loadImage() async {
    final source = await baseIconRenderer.loadImage();
    return _buildImage(source);
  }

  CanvasElement _buildImage(CanvasImageSource source) {
    final num devicePixelRatio = window.devicePixelRatio;
    final canvas = new CanvasElement(
      width: iconWidth * devicePixelRatio,
      height: iconHeight * devicePixelRatio,
    );
    canvas.style
      ..width = '${iconWidth}px'
      ..height = '${iconHeight}px';

    // TODO(JACOBR): define this color in terms of Color objects.
    const String normalColor = '#231F20';

    canvas.context2D
      ..scale(devicePixelRatio, devicePixelRatio)
      ..drawImageScaled(source, 0, 0, iconWidth, iconHeight)
      ..strokeStyle = normalColor
      // In IntelliJ this was:
      // UIUtil.getFont(UIUtil.FontSize.MINI, UIUtil.getTreeFont());
      ..font = 'arial 8px'
      ..textBaseline = 'middle'
      ..textAlign = 'center'
      ..fillText(icon.text, iconWidth / 2, iconHeight / 2, iconWidth);

    return canvas;
  }
}

class MaterialIconRenderer extends HtmlIconRenderer<MaterialIcon> {
  MaterialIconRenderer(MaterialIcon icon) : super(icon);

  @override
  CanvasImageSource get image {
    if (_image != null) return _image;

    _image = createCanvasSource();
    return _image;
  }

  CanvasElement _image;

  @override
  Future<CanvasImageSource> loadImage() async => image;

  @override
  CanvasImageSource createCanvasSource() {
    final canvas = new CanvasElement(
      width: iconWidth * window.devicePixelRatio,
      height: iconHeight * window.devicePixelRatio,
    );
    canvas.context2D
      ..scale(window.devicePixelRatio, window.devicePixelRatio)
      ..font = '${icon.fontSize}px Material Icons'
      ..fillStyle = colorToCss(icon.color)
      ..textBaseline = 'middle'
      ..textAlign = 'center'
      ..fillText(icon.text, iconWidth / 2, iconHeight / 2, iconWidth + 10);
    return canvas;
  }
}

CoreElement createIconElement(Icon icon) {
  return getIconRenderer(icon).createElement();
}

HtmlIconRenderer getIconRenderer(Icon icon) {
  HtmlIconRenderer renderer = rendererExpando[icon];
  if (renderer != null) {
    return renderer;
  }

  if (icon is UrlIcon) {
    renderer = UrlIconRenderer(icon);
  } else if (icon is ColorIcon) {
    renderer = ColorIconRenderer(icon);
  } else if (icon is CustomIcon) {
    renderer = CustomIconRenderer(icon);
  } else if (icon is MaterialIcon) {
    renderer = MaterialIconRenderer(icon);
  } else {
    throw UnimplementedError('No icon renderer defined for $icon');
  }

  rendererExpando[icon] = renderer;
  return renderer;
}