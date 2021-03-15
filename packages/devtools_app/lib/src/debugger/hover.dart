// Copyright 2021 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Returns the word in the [line] for the provided hover [dx] offset given
/// the [line]'s [textStyle].
String wordForHover(double dx, TextSpan line, TextStyle textStyle) {
  final index = _hoverIndex(dx, line, textStyle);
  var word = '';
  if (index == -1) return word;
  word = line.children[index].toPlainText();
  word = _mergedLinkedWords(word, index, line);
  return word;
}

/// Merges words linked by a `.`.
///
/// For example, hovering over `bar` in `foo.bar.baz` would return
/// `foo.bar`.
String _mergedLinkedWords(String word, int index, TextSpan line) {
  var left = index - 1;
  while (left > 1) {
    final prev = line.children[left].toPlainText();
    final prevprev = line.children[left - 1].toPlainText();
    if (prev == '.') {
      word = '$prevprev$prev$word';
      left -= 2;
    } else {
      break;
    }
  }
  return word;
}

/// Returns the index in the [line]'s children for which the hover offset is
/// located.
int _hoverIndex(double dx, TextSpan line, TextStyle textStyle) {
  int index = 0;
  var cumulativeWidth = 0.0;
  while (index < line.children.length) {
    final span = line.children[index];
    final painter = TextPainter(
      text: TextSpan(children: [span], style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    cumulativeWidth += painter.width;
    if (cumulativeWidth >= dx) return index;
    index++;
  }
  return -1;
}

const _hoverCardBorderWidth = 2.0;
const _hoverYOffset = 10;

class HoverCardData {
  HoverCardData({
    @required this.title,
    @required this.contents,
    this.width = HoverCardTip.defaultHoverWidth,
  });

  final String title;
  final Widget contents;
  final double width;
}

/// A card to display content while hovering over a widget.
///
/// This widget will automatically remove itself after the mouse has entered
/// and left its region.
///
/// Note that if a mouse has never entered, it will not remove itself.
class HoverCard {
  HoverCard({
    @required BuildContext context,
    @required PointerHoverEvent event,
    @required String title,
    @required Widget contents,
    @required double width,
  }) {
    final overlayState = Overlay.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final focusColor = Theme.of(context).focusColor;
    final hoverHeading = colorScheme.hoverTitleTextStyle;
    final position = event.position;

    _overlayEntry = OverlayEntry(builder: (context) {
      return Positioned(
        left: math.max(0, position.dx - (width / 2.0)),
        top: position.dy + _hoverYOffset,
        child: MouseRegion(
          onExit: (_) {
            remove();
          },
          onEnter: (_) {
            _hasMouseEntered = true;
          },
          child: Container(
            padding: const EdgeInsets.all(denseSpacing),
            decoration: BoxDecoration(
              color: colorScheme.defaultBackgroundColor,
              border: Border.all(
                color: focusColor,
                width: _hoverCardBorderWidth,
              ),
              borderRadius: BorderRadius.circular(defaultBorderRadius),
            ),
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: width,
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: hoverHeading,
                    textAlign: TextAlign.center,
                  ),
                ),
                Divider(color: colorScheme.hoverTextStyle.color),
                contents,
              ],
            ),
          ),
        ),
      );
    });
    overlayState.insert(_overlayEntry);
  }

  OverlayEntry _overlayEntry;

  bool _isRemoved = false;

  bool _hasMouseEntered = false;

  /// Attempts to remove the HoverCard from the screen.
  ///
  /// The HoverCard will not be removed if the mouse is currently inside the
  /// widget.
  void maybeRemove() {
    if (!_hasMouseEntered) remove();
  }

  /// Removes the HoverCard even if the mouse is in the corresponding mouse
  /// region.
  void remove() {
    if (!_isRemoved) _overlayEntry.remove();
    _isRemoved = true;
  }
}

class HoverCardTip extends StatefulWidget {
  const HoverCardTip({
    @required this.enabled,
    @required this.onHover,
    @required this.child,
  });

  static const _hoverDelay = Duration(milliseconds: 500);
  static const defaultHoverWidth = 450.0;

  final bool Function() enabled;
  final Future<HoverCardData> Function(PointerHoverEvent event) onHover;
  final Widget child;

  @override
  _HoverCardTipState createState() => _HoverCardTipState();
}

class _HoverCardTipState extends State<HoverCardTip> {
  /// A timer that shows a [HoverCard] with an evaluation result when completed.
  Timer _showTimer;

  /// A timer that removes a [HoverCard] when completed.
  Timer _removeTimer;

  /// Displays the evaluation result of a source code item.
  HoverCard _hoverCard;

  void _onHoverExit() {
    _showTimer?.cancel();
    _removeTimer = Timer(HoverCardTip._hoverDelay, () {
      _hoverCard?.maybeRemove();
    });
  }

  void _onHover(PointerHoverEvent event) {
    _showTimer?.cancel();
    _showTimer = null;
    _removeTimer?.cancel();
    _removeTimer = null;

    if (!widget.enabled()) return;
    _showTimer = Timer(HoverCardTip._hoverDelay, () async {
      _hoverCard?.remove();
      _hoverCard = null;
      final hoverCardData = await widget.onHover(event);
      if (hoverCardData != null) {
        _hoverCard = HoverCard(
          context: context,
          event: event,
          title: hoverCardData.title,
          contents: hoverCardData.contents,
          width: hoverCardData.width,
        );
      }
    });
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _removeTimer?.cancel();
    _hoverCard?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onExit: (_) => _onHoverExit(),
      onHover: _onHover,
      child: widget.child,
    );
  }
}
