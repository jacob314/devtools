/*
 * Copyright 2017 The Chromium Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

library icons;

import 'dart:async';
import 'dart:html';

import 'fake_flutter/fake_flutter.dart';

abstract class Icon {
  CanvasImageSource get image;
  bool get loaded => image != null;
  Future<CanvasImageSource> loadImage();

  int get iconWidth => 16;
  int get iconHeight => 16;
}

class UrlIcon extends Icon {
  UrlIcon(this.src);

  final String src;

  @override
  CanvasImageSource get image => _image;
  ImageElement _image;

  Future<ImageElement> _imageFuture;

  @override
  Future<CanvasImageSource> loadImage() {
    if (_imageFuture != null) {
      return _imageFuture;
    }
    final Completer<CanvasImageSource> completer = new Completer();
    final imageElement = new ImageElement(src: src);
    imageElement.onLoad.listen((e) {
      print('XXX onLoad!');
      _image = imageElement;
      completer.complete(imageElement);
    });
    document.head.append(imageElement); // XXX is this needed?
    _imageFuture = completer.future;
    return _imageFuture;
  }
}

class FlutterIcons {
  FlutterIcons._();

  static final Icon flutter13 = UrlIcon('/icons/flutter_13.png');
  static final Icon flutter13_2x = UrlIcon('/icons/flutter_13@2x.png');
  static final Icon flutter64 = UrlIcon('/icons/flutter_64.png');
  static final Icon flutter64_2x = UrlIcon('/icons/flutter_64@2x.png');
  static final Icon flutter = UrlIcon('/icons/flutter.png');
  static final Icon flutter2x = UrlIcon('/icons/flutter@2x.png');
  static final Icon flutterInspect = UrlIcon('/icons/flutter_inspect.png');
  static final Icon flutterTest = UrlIcon('/icons/flutter_test.png');
  static final Icon flutterBadge = UrlIcon('/icons/flutter_badge.png');

  static final Icon phone = UrlIcon('/icons/phone.png');
  static final Icon feedback = UrlIcon('/icons/feedback.png');

  static final Icon openObservatory = UrlIcon('/icons/observatory.png');
  static final Icon openObservatoryGroup =
  UrlIcon('/icons/observatory_overflow.png');

  static final Icon openTimeline = UrlIcon('/icons/timeline.png');

  static final Icon hotRefinal = UrlIcon('/icons/hot-refinal Icon.png');
  static final Icon hotRestart = UrlIcon('/icons/hot-restart.png');

  static final Icon iconRun = UrlIcon('/icons/refinal Icon_run.png');
  static final Icon iconDebug = UrlIcon('/icons/refinal Icon_debug.png');

  static final Icon bazelRun = UrlIcon('/icons/bazel_run.png');

  static final Icon customClass = UrlIcon('/icons/custom/class.png');
  static final Icon customClassAbstract =
  UrlIcon('/icons/custom/class_abstract.png');
  static final Icon customFields = UrlIcon('/icons/custom/fields.png');
  static final Icon customInterface = UrlIcon('/icons/custom/interface.png');
  static final Icon customMethod = UrlIcon('/icons/custom/method.png');
  static final Icon customMethodAbstract =
  UrlIcon('/icons/custom/method_abstract.png');
  static final Icon customProperty = UrlIcon('/icons/custom/property.png');
  static final Icon customInfo = UrlIcon('/icons/custom/info.png');

  static final Icon androidStudioNewProject =
  UrlIcon('/icons/template_new_project.png');
  static final Icon androidStudioNewPackage =
  UrlIcon('/icons/template_new_package.png');
  static final Icon androidStudioNewPlugin =
  UrlIcon('/icons/template_new_plugin.png');
  static final Icon androidStudioNewModule =
  UrlIcon('/icons/template_new_module.png');

  static final Icon attachDebugger = UrlIcon('/icons/attachDebugger.png');

  // Flutter Inspector Widget Icons.
  static final Icon accessibility =
  UrlIcon('/icons/inspector/balloonInformation.png');
  static final Icon animation = UrlIcon('/icons/inspector/resume.png');
  static final Icon assets = UrlIcon('/icons/inspector/any_type.png');
  static final Icon async = UrlIcon('/icons/inspector/threads.png');
  static final Icon diagram = UrlIcon('/icons/inspector/diagram.png');
  static final Icon input = UrlIcon('/icons/inspector/renderer.png');
  static final Icon painting = UrlIcon('/icons/inspector/colors.png');
  static final Icon scrollbar = UrlIcon('/icons/inspector/scrollbar.png');
  static final Icon stack = UrlIcon('/icons/inspector/value.png');
  static final Icon styling = UrlIcon('/icons/inspector/atrule.png');
  static final Icon text = UrlIcon('/icons/inspector/textArea.png');

  static final Icon expandProperty =
  UrlIcon('/icons/inspector/expand_property.png');
  static final Icon collapseProperty =
  UrlIcon('/icons/inspector/collapse_property.png');

  // Flutter Outline Widget Icons.
  static final Icon column = UrlIcon('/icons/preview/column.png');
  static final Icon padding = UrlIcon('/icons/preview/padding.png');
  static final Icon removeWidget = UrlIcon('/icons/preview/remove_widget.png');
  static final Icon row = UrlIcon('/icons/preview/row.png');
  static final Icon center = UrlIcon('/icons/preview/center.png');
  static final Icon container = UrlIcon('/icons/preview/container.png');
  static final Icon up = UrlIcon('/icons/preview/up.png');
  static final Icon down = UrlIcon('/icons/preview/down.png');
  static final Icon extractMethod = UrlIcon('/icons/preview/extract_method.png');

  static final Icon greyProgress = UrlIcon('/icons/perf/grey_progress.gif');
  static final Icon redProgress = UrlIcon('/icons/perf/red_progress.gif');
  static final Icon yellowProgress = UrlIcon('/icons/perf/yellow_progress.gif');
}

typedef DrawIconImageCallback = void Function(CanvasRenderingContext2D element);

class LayeredIcon extends Icon {
  LayeredIcon(this.baseIcon, this._drawCallback);

  final DrawIconImageCallback _drawCallback;

  final Icon baseIcon;


  @override
  // TODO: implement image
  CanvasImageSource get image {
    if (image != null) return _image;
    final baseImage = baseIcon.image;
    if (baseImage == null) return null;

    return _buildImage(baseIcon.image);
  }

  CanvasElement _image;

  @override
  Future<CanvasImageSource> loadImage() async {
    final source = await baseIcon.loadImage();
    return _buildImage(source);
  }

  CanvasElement _buildImage(CanvasImageSource source) {
    _image = new CanvasElement(width: iconWidth, height: iconHeight);
    final context =_image.context2D;
    context.drawImage(source, 0, 0);
    _drawCallback(context);
    return _image;
  }
}

class CustomIconMaker {
  static const String normalColor = '#231F20';

  final Map<String, Icon> iconCache = {};

  Icon getCustomIcon(String fromText,
      [IconKind kind, bool isAbstract = false]) {
    kind ??=  IconKind.classIcon;
    if (fromText?.isEmpty != false) {
      return null;
    }

    final String text = fromText[0].toUpperCase();
    final String mapKey = '${text}_${kind.name}_$isAbstract';

    return iconCache.putIfAbsent(mapKey, () {
      final Icon baseIcon = isAbstract ? kind.abstractIcon : kind.icon;
      return new LayeredIcon(baseIcon, (context) {
        context.strokeStyle = normalColor;

        context.font = 'arial 8px'; // UIUtil.getFont(UIUtil.FontSize.MINI, UIUtil.getTreeFont());
        final iconHeight = baseIcon.iconHeight;
        final iconWidth = baseIcon.iconWidth;
        /* We could use metrics instead. XXX
        var metrics = context.measureText(text);
        final double offsetX = (iconWidth - metrics.width) / 2.0;
        // Some black magic here for vertical centering.
        // TODO(jacobr): verify this black magic is still right.
        /// XXX final double offsetY = iconHeight - ((iconHeight - metrics.alphabeticBaseline) / 2.0f) - 2.0f;
*/
        context.textBaseline = 'middle';
        context.fillText(text, 0, iconHeight / 2, iconWidth);
      },);
    });
  }

  Icon fromWidgetName(String name) {
    if (name == null) {
      return null;
    }

    final bool isPrivate = name.startsWith('_');
    while (name.isNotEmpty && !isAlphabetic(name.codeUnitAt(0))) {
      name = name.substring(1);
    }

    if (name.isEmpty) {
      return null;
    }

    return getCustomIcon(name, isPrivate ? IconKind.method : IconKind.classIcon);
  }

  Icon fromInfo(String name) {
    if (name == null) {
      return null;
    }

    if (name.isEmpty) {
      return null;
    }

    return getCustomIcon(name, IconKind.info);
  }

  bool isAlphabetic(int char) {
    return (char < '0'.codeUnitAt(0) || char > '9'.codeUnitAt(0)) &&
        char != '_'.codeUnitAt(0) &&
        char != r'$'.codeUnitAt(0);
  }
}

// Strip Java naming convention;
class IconKind {
  const IconKind(this.name, this.icon, [abstractIcon])
      : abstractIcon = abstractIcon ?? icon;

  static final IconKind classIcon = IconKind(
      'class', FlutterIcons.customClass, FlutterIcons.customClassAbstract);
  static final IconKind field = IconKind('fields', FlutterIcons.customFields);
  static final IconKind interface =
      IconKind('interface', FlutterIcons.customInterface);
  static final IconKind method = IconKind(
      'method', FlutterIcons.customMethod, FlutterIcons.customMethodAbstract);
  static final IconKind property =
      IconKind('property', FlutterIcons.customProperty);
  static final IconKind info = IconKind('info', FlutterIcons.customInfo);

  final String name;
  final Icon icon;
  final Icon abstractIcon;
}

class ColorIcon extends Icon {
  ColorIcon(this.color);

  static const int iconMargin = 3;

  final Color color;

  @override
  // TODO: implement image
  CanvasImageSource get image {
    if (_image != null) {
      return _image;
    }
    _image = new CanvasElement(width: iconWidth, height: iconHeight);
    final context = _image.context2D;

      // draw a black and gray grid to use as the background to disambiguate
      // opaque colors from translucent colors.
    context.fillStyle = 'white';
    context.fillRect(iconMargin, iconMargin, iconWidth - iconMargin * 2, iconHeight - iconMargin * 2);
    context.fillStyle = 'gray';
    context.fillRect(iconMargin, iconMargin, iconWidth / 2 - iconMargin, iconHeight / 2 - iconMargin);
    context.fillRect(iconWidth / 2, iconHeight / 2, iconWidth / 2 - iconMargin, iconHeight / 2 - iconMargin);
    context.fillStyle = color.value;
    context.fillRect(iconMargin, iconMargin, iconWidth - iconMargin * 2, iconHeight - iconMargin * 2);
    context.strokeStyle = 'black';
    context.rect( iconMargin, iconMargin, iconWidth - iconMargin * 2, iconHeight - iconMargin * 2);
    return _image;
  }

  CanvasElement _image;

  @override
  Future<CanvasImageSource> loadImage() async {
    // This icon does not perform any async work.
    return image;
  }

  @override int get iconWidth => 22;
  @override int get iconHeight => 22;

}
class ColorIconMaker {
  final Map<Color, Icon> iconCache = {};

  Icon getCustomIcon(Color color) {
    return iconCache.putIfAbsent(color, () => new ColorIcon(color));
  }
}
