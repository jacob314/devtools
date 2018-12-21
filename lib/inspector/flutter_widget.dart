library flutter_widget;

import 'dart:convert';

import 'package:devtools/ui/icons.dart';
import 'package:devtools/utils.dart';
import 'package:http/http.dart';

class Category {
  Category(this.label, this.icon);

  static final Category accessibility =
      Category('Accessibility', FlutterIcons.accessibility);
  static final Category animationAndMotion =
      Category('Animation and Motion', FlutterIcons.animation);
  static final Category assetsImagesAndIcons =
      Category('Assets, Images, and Icons', FlutterIcons.assets);
  static final Category async = Category('Async', FlutterIcons.async);
  static final Category basics =
      Category('Basics', null); // TODO(jacobr): add an icon.
  static final Category cupertino = Category(
      'Cupertino (iOS-style widgets)', null); // TODO(jacobr): add an icon.
  static final Category input = Category('Input', FlutterIcons.input);
  static final Category paintingAndEffects =
      Category('Painting and effects', FlutterIcons.painting);
  static final Category scrolling =
      Category('Scrolling', FlutterIcons.scrollbar);
  static final Category stack = Category('Stack', FlutterIcons.stack);
  static final Category styling = Category('Styling', FlutterIcons.styling);
  static final Category text = Category('Text', FlutterIcons.text);

  static final List<Category> values = [
    accessibility,
    animationAndMotion,
    assetsImagesAndIcons,
    async,
    basics,
    cupertino,
    input,
    paintingAndEffects,
    scrolling,
    stack,
    styling,
    text,
  ];

  final String label;
  final Icon icon;

  static Map<String, Category> _categories;

  static Category forLabel(String label) {
    if (_categories == null) {
      _categories = {};
      for (var category in values) {
        _categories[category.label] = category;
      }
    }
    return _categories[label];
  }
}

class FlutterWidget {
  FlutterWidget(this.json) : icon = initIcon(json);

  final Map<String, Object> json;
  final Icon icon;

  static Icon initIcon(Map<String, Object> json) {
    final List<Object> categories = json['categories'];
    if (categories != null) {
      // TODO(pq): consider priority over first match.
      for (String label in categories) {
        final Category category = Category.forLabel(label);
        if (category != null) {
          final Icon icon = category.icon;
          if (icon != null) return icon;
        }
      }
    }
    return null;
  }

  String get name => JsonUtils.getStringMember(json, 'name');

  List<String> get categories => JsonUtils.getValues(json, 'categories');

  List<String> get subCategories => JsonUtils.getValues(json, 'subcategories');
}

/// Catalog of widgets derived from widgets.json.
class Catalog {
  Catalog._(this.widgets);

  final Map<String, FlutterWidget> widgets;

  static Future<Catalog> load() async {
    final Map<String, FlutterWidget> widgets = {};
    // Local copy of: https\://github.com/flutter/website/tree/master/_data/catalog/widget.json
    final Response response = await get('widgets.json');
    final List<Object> json = jsonDecode(response.body);

    for (Map<String, Object> element in json) {
      final FlutterWidget widget = new FlutterWidget(element);
      final String name = widget.name;
      // TODO(pq): add validation once json is repaired (https://github.com/flutter/flutter/issues/12930).
      // if (widgets.containsKey(name)) throw new IllegalStateException('Unexpected contents: widget `${name}` is duplicated');
      widgets[name] = widget;
    }
    return new Catalog._(widgets);
  }

  List<FlutterWidget> get allWidgets {
    return widgets.values.toList();
  }

  FlutterWidget getWidget(String name) {
    return name != null ? widgets[name] : null;
  }

  String dumpJson() {
    return jsonEncode(json);
  }
}
