import 'dart:html';
import 'dart:js';

import 'package:devtools/framework/framework.dart';
import 'package:devtools/ui/elements.dart';
import 'package:meta/meta.dart';

import 'fake_flutter/fake_flutter.dart';

const int chunkSize = 512;

bool _debugChunks = false;

int numChunks = 0;

num _dpr = window.devicePixelRatio ?? 1;

class CanvasChunk {
  CanvasChunk(_ChunkPosition position)
      : canvas = new CanvasElement(
            width: chunkSize * _dpr, height: chunkSize * _dpr) {
    canvas.style.position = 'absolute';
    canvas.style.width = '${chunkSize}px';
    canvas.style.height = '${chunkSize}px';
    _context = canvas.context2D;
    _context.scale(_dpr, _dpr);
    _context.save();
    this.position = position;
    _dirty = true;
    if (_debugChunks) {
      canvas.dataset['chunkId'] = numChunks.toString();
      numChunks++;
    }
  }

  final CanvasElement canvas;
  CanvasRenderingContext2D _context;
  bool _empty = true;

  bool get dirty => _dirty;
  bool _dirty;

  bool attached = false;
  int _lastFrameRendered = -1;
  Rect rect;

  void markNeedsPaint() {
    _dirty = true;
  }

  void markPainted() {
    _dirty = false;
    _empty = false;
  }

  _ChunkPosition get position => _position;
  _ChunkPosition _position;

  set position(_ChunkPosition p) {
    if (_position == p) return;
    _position = p;
    rect = new Rect.fromLTWH(
      (position.x * chunkSize).toDouble(),
      (position.y * chunkSize).toDouble(),
      chunkSize.toDouble(),
      chunkSize.toDouble(),
    );
    canvas.style.transform = 'translate(${rect.left}px, ${rect.top}px)';

    context.restore();
    context.save();
    // Move the canvas's coordinate system to match the global instead of
    // chunked coordinates.
    context.translate(-rect.left, -rect.top);

    _debugPaint();
    markNeedsPaint();
  }

  void clear() {
    if (_empty) return;
    _context.clearRect(rect.left, rect.top, chunkSize, chunkSize);
    _debugPaint();
    _empty = true;
  }

  void _debugPaint() {
    if (_debugChunks) {
      _context.save();
      _context.strokeStyle = 'red';
      _context.fillStyle = '#DDDDDD';
      _context.fillRect(
          rect.left + 2, rect.top + 2, rect.width - 2, rect.height - 2);
      _context.fillStyle = 'red';
      _context.fillText('$rect', rect.left + 50, rect.top + 50);
      _context.restore();
    }
  }

  CanvasRenderingContext2D get context => _context;
}

class _ChunkPosition {
  _ChunkPosition(this.x, this.y);

  @override
  bool operator ==(dynamic other) {
    if (other is! _ChunkPosition) return false;
    return y == other.y && x == other.x;
  }

  @override
  int get hashCode => y * 37 + x;

  final int x;
  final int y;
}

typedef CanvasPaintCallback = void Function(
    CanvasRenderingContext2D context, Rect rect);

typedef MouseCallback = void Function(Offset offset);

class ViewportCanvas extends Object with SetStateMixin {
  ViewportCanvas(
      {@required CanvasPaintCallback paintCallback,
      MouseCallback onTap,
      MouseCallback onMouseMove,
      VoidCallback onMouseLeave})
      : _paintCallback = paintCallback,
        _onTap = onTap,
        _onMouseMove = onMouseMove,
        _onMouseLeave = onMouseLeave,
        _element = div(
          a: 'flex',
          c: 'overflow viewport-border viewport-virtual inspector-pane',
        ),
        _content = div(c: 'viewport-content'),
        _spaceTop = div(c: 'viewport-spacer space-top'),
        _spaceBottom = div(c: 'viewport-spacer space-bottom'),
        _spaceLeft = div(c: 'viewport-spacer space-left'),
        _spaceRight = div(c: 'viewport-spacer space-right'),
        _fakeScrollTarget = div(c: 'fake-scroll-target') {
    _element.add(_content);
    _content
      ..add(_fakeScrollTarget)
      ..add(_spaceTop)
      ..add(_spaceBottom)
      ..add(_spaceLeft)
      ..add(_spaceRight);

    // TODO(jacobr): remove call to allowInterop once bug in dart:html is fixed.
    _visibilityObserver =
        new IntersectionObserver(allowInterop(_visibilityChange), {
      'root': _element.element,
      'rootMargin': '0px',
      'threshold': [0.0, 0.1, 0.2, .5],
    });
    _visibilityObserver.observe(_spaceTop.element);
    _visibilityObserver.observe(_spaceBottom.element);
    _visibilityObserver.observe(_spaceLeft.element);
    _visibilityObserver.observe(_spaceRight.element);
    element.onScroll.listen((_) {
      if (_currentMouseHover != null) {
        _dispatchMouseMoveEvent();
      }
      rebuild(false);
    });
    if (_onTap != null) {
      _content.onClick.listen((e) {
        _onTap(_clientToGlobal(e.client));
      });
    }
    _content.element.onMouseLeave.listen((_) {
      _currentMouseHover = null;
      if (_onMouseLeave != null) {
        _onMouseLeave();
      }
    });
    _content.element.onMouseMove.listen((e) {
      _currentMouseHover = e.client;
      _dispatchMouseMoveEvent();
    });
  }

  void _dispatchMouseMoveEvent() {
    if (_onMouseMove != null) {
      _onMouseMove(_clientToGlobal(_currentMouseHover));
    }
  }

  Offset _clientToGlobal(Point client) {
    final elementRect = _content.element.getBoundingClientRect();
    return Offset(client.x - elementRect.left, client.y - elementRect.top);
  }

  Point _currentMouseHover;

  int _frameId = 0;
  final CanvasPaintCallback _paintCallback;
  final MouseCallback _onTap;
  final MouseCallback _onMouseMove;
  final VoidCallback _onMouseLeave;
  Map<_ChunkPosition, CanvasChunk> chunks = {};
  static const int maxChunks = 20;
  IntersectionObserver _visibilityObserver;

  final CoreElement _element;
  final CoreElement _content;
  final CoreElement _spaceTop;
  final CoreElement _spaceBottom;
  final CoreElement _spaceLeft;
  final CoreElement _spaceRight;
  final CoreElement _fakeScrollTarget;

  double _contentWidth = 0;
  double _contentHeight = 0;
  bool contentSizeChanged = true;

  bool _hasPendingRebuild = false;

  Rect get viewport => _viewport;
  Rect _viewport = Rect.zero;

  void dispose() {
    _visibilityObserver.disconnect();
  }

  void _visibilityChange(List entries, IntersectionObserver observer) {
    _scheduleRebuild();
  }

  void _scheduleRebuild() {
    if (!_hasPendingRebuild) {
      // Set a flag to ensure we don't schedule rebuilds if there's already one
      // in the queue.
      _hasPendingRebuild = true;
      setState(() {
        _hasPendingRebuild = false;
        rebuild(false);
      });
    }
  }

  void rebuild(bool force) {
    final lastViewport = _viewport;
    _viewport = new Rect.fromLTWH(
      _element.scrollLeft.toDouble(),
      _element.scrollTop.toDouble(),
      _element.element.clientWidth.toDouble(),
      _element.element.clientHeight.toDouble(),
    );
    // TODO(jacobr): round viewport to the nearest chunk multiple so we
    // don't get notifications until we actually need them.

    // Position spacers to take up all the space around the viewport so we are notified immediately
    // when the viewport size shrinks.
    if (lastViewport.left != _viewport.left || contentSizeChanged) {
      _spaceLeft.element.style.width = '${_viewport.left}px';
    }
    if (lastViewport.right != _viewport.right || contentSizeChanged) {
      _spaceRight.element.style.width = '${_contentWidth - _viewport.right}px';
    }
    if (lastViewport.top != _viewport.top || contentSizeChanged) {
      _spaceTop.element.style.height = '${_viewport.top}px';
    }
    if (lastViewport.bottom != _viewport.bottom || contentSizeChanged) {
      _spaceBottom.element.style.height =
          '${_contentHeight - _viewport.bottom}px';
    }
    contentSizeChanged = false;

    _render(force);
  }

  void setContentSize(double width, double height) {
    if (width == _contentWidth && height == _contentHeight) {
      return;
    }
    _contentWidth = width;
    _contentHeight = height;
    _content.element.style
      ..width = '${width}px'
      ..height = '${height}px';
    if (!contentSizeChanged) {
      contentSizeChanged = true;
      _scheduleRebuild();
    }
  }

  void markNeedsPaint(double x, double y) {
    _getExisting(x, y)?.markNeedsPaint();
  }

  _ChunkPosition _getChunkPosition(double x, double y) {
    return _ChunkPosition(x ~/ chunkSize, y ~/ chunkSize);
  }

  CanvasChunk _getExisting(double x, double y) {
    return chunks[_getChunkPosition(x, y)];
  }

  CanvasChunk _getChunk(_ChunkPosition position) {
    var existing = chunks[position];
    if (existing != null) {
      if (existing.dirty) {
        existing.clear();
      }
      return existing;
    }
    // find an unused chunk. TODO(jacobr): consider using a LRU cached
    for (CanvasChunk chunk in chunks.values) {
      if (!_isVisible(chunk)) {
        existing = chunk;
        final removed = chunks.remove(chunk.position);
        assert(removed == existing);
        existing.position = position;
        chunks[position] = existing;
        if (existing.dirty) {
          existing.clear();
        }
        return existing;
      }
    }
    assert(existing == null);
    final chunk = new CanvasChunk(position);
    chunks[position] = chunk;
    return chunk;
  }

  void _render(bool force) {
    if (force) {
      for (var chunk in chunks.values) {
        chunk.markNeedsPaint();
        chunk.clear();
      }
    }
    _frameId++;
    // Note: we do not currently hide chunks that are outside the viewport.

    final start = _getChunkPosition(_viewport.left, _viewport.top);
    final end = _getChunkPosition(_viewport.right, _viewport.bottom);
    for (int y = start.y; y <= end.y; y++) {
      for (int x = start.x; x <= end.x; x++) {
        final chunk = _getChunk(_ChunkPosition(x, y));
        if (chunk.dirty) {
          try {
            _paintCallback(chunk.canvas.context2D, chunk.rect);
          } catch (e, st) {
            window.console.error(e);
            window.console.error(st);
          }
          chunk.markPainted();
        }
        chunk._lastFrameRendered = _frameId;
      }
    }
    for (CanvasChunk chunk in chunks.values) {
      final attach = chunk._lastFrameRendered == _frameId;
      if (attach != chunk.attached) {
        if (attach) {
          _content.element.append(chunk.canvas);
        } else {
          chunk.canvas.remove();
        }
        chunk.attached = attach;
      }
    }
  }

  CoreElement get element => _element;

  bool _isVisible(CanvasChunk chunk) => chunk.rect.overlaps(_viewport);

  void scrolToRect(Rect target) {
    setState(() {
      rebuild(false);
      // We have to reimplement scrolling functionality as modifying the dom
      // like this class does messes with built in scrolling into view
      // logic.
      if (_viewport.contains(target.topLeft) &&
          _viewport.contains(target.bottomLeft)) {
        // Already fully in view. Do nothing.
        return;
      }
      final bool overlaps = _viewport.overlaps(target);

      num x = _viewport.left;
      num y = _viewport.top;
      if (viewport.top > target.top) {
        // Scroll up
        y = target.top.toInt();
      } else if (viewport.bottom < target.bottom) {
        // Scroll down only as much as needed if the viewport overlaps
        y = overlaps ? target.bottom - viewport.height : target.top;
      }

      if (viewport.left > target.left) {
        // Scroll left.
        x = target.left.toInt();
      } else if (viewport.right < target.right) {
        // Scroll right
        x = (target.right - viewport.width).toInt();
      }
      _element.element.scrollTo(x, y);
    });
  }
}
