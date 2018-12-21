

import 'dart:html';

import 'package:devtools/framework/framework.dart';
import 'package:devtools/ui/elements.dart';
import 'package:meta/meta.dart';

import 'fake_flutter/fake_flutter.dart';

const int chunkSize = 512;

class CanvasChunk {
  CanvasChunk(_ChunkPosition position) :
        canvas = new CanvasElement(width: chunkSize, height: chunkSize) {
    canvas.style.position = 'absolute';
    _context = canvas.context2D;
    this.position = position;
    _dirty = true;
  }

  final CanvasElement canvas;
  CanvasRenderingContext2D _context;
  bool _empty = true;

  bool get dirty => _dirty;
  bool _dirty;

  void markNeedsPaint() {
    _dirty = true;
  }

  void markPainted() {
    _dirty = false;
    _empty = false;
  }

  Rectangle<int> rect;

  _ChunkPosition get position => _position;
  _ChunkPosition _position;
  set position(_ChunkPosition p) {
    if (_position == p) return;
    _position = p;
    canvas.style.transform = 'translate(${p.x * chunkSize}px, ${p.y * chunkSize}px)';
    rect = new Rectangle(position.x * chunkSize, position.y * chunkSize, chunkSize, chunkSize);

    markNeedsPaint();
  }

  void clear() {
    if (_empty) return;
    _context.clearRect(0, 0, chunkSize, chunkSize);
    _empty = true;
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

typedef CanvasPaintCallback = void Function(CanvasRenderingContext2D context, Rectangle<int> rect);

class ViewportCanvas extends Object with SetStateMixin, OnAddedToDomMixin {

  ViewportCanvas(this._paintCallback) :
        _element = CoreElement('div')
  {
    element.onScroll.listen((_) => _scheduleRebuild());
  }
  final CanvasPaintCallback _paintCallback;
  final CoreElement _element;
  static Map<_ChunkPosition, CanvasChunk> chunks = {};
  static const int maxChunks = 10;

  int _scrollTop = 0;
  int _scrollLeft = 0;
  int _contentWidth;
  int _contentHeight;
  int _viewportWidth;
  int _viewportHeight;
  
  Rectangle<int> _viewport;

  void _scheduleRebuild() {
    rebuild();
    render(false);
  }

  void rebuild() {
    _scrollTop = _element.scrollTop;
    _scrollLeft = _element.scrollLeft;
    _viewportWidth = _element.element.clientWidth;
    _viewportHeight = _element.element.clientHeight;
    _viewport = new Rectangle(_scrollLeft, _scrollTop, _viewportWidth, _viewportHeight,);

  }

  void setContentSize(int width, int height) {
    _contentWidth = width;
    _contentHeight = height;
  }

  void scrollTo(int x, int y) {
    // TEST.
    _element.element.scrollTo(x, y);
  }

  void markNeedsPaint(int x, int y) {
    getExisting(x, y)?.markNeedsPaint();
  }

  _ChunkPosition getChunkPosition(int x, int y) {
    return _ChunkPosition(x ~/ chunkSize, y ~/ chunkSize);
  }
  CanvasChunk getExisting(int x, int y) {
    return chunks[getChunkPosition(x, y)];
  }

  CanvasChunk getChunk(_ChunkPosition position) {
    final int chunkY = position.y * chunkSize;
    final int chunkX = position.x * chunkSize;
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
        if (existing.dirty) {
          existing.clear();
        }
        return existing;
      }
    }
    assert (existing == null);
    final chunk = new CanvasChunk(position);
    chunks[position] = chunk;
    return chunk;
  }

  void render(bool force) {
    var start = getChunkPosition(_viewport.top, _viewport.left);
    var end = getChunkPosition(_viewport.bottom, _viewport.right);
    for (int y = start.y; y <= end.y; y++) {
      for (int x = start.x; x <= end.x; x++) {
        final chunk = getChunk(_ChunkPosition(x, y));
        if (force) {
          chunk.markNeedsPaint();
          chunk.clear();
        }
        if (chunk.dirty) {
          _paintCallback(chunk.canvas.context2D, chunk.rect);
          chunk.markPainted();
        }
      }
    }
  }

  @override
  // TODO: implement element
  CoreElement get element => _element;

  bool _isVisible(CanvasChunk chunk) => chunk.rect.intersects(_viewport);
}