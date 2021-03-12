// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meta/meta.dart';
import 'package:pedantic/pedantic.dart';
import 'package:vm_service/vm_service.dart';

import '../globals.dart';
import '../inspector/diagnostics_node.dart';
import '../trees.dart';
import '../utils.dart';

/// A reference to an object that may be referenced by 1 or more of the object
/// reference schemes.
///
/// If both an inspectorRef and instanceRef are provided they are assumed to
/// reference the same object. If an additional persistent object scheme for the
/// DartVM itself is added, it would be reasonable to add it here.
class GenericRef {
  const GenericRef({
    @required this.isolateRef,
    this.instanceRef,
    this.diagnostic,
  });

  final InstanceRef instanceRef;

  final RemoteDiagnosticsNode diagnostic;
  final IsolateRef isolateRef;
}

/// A tuple of a script and an optional location.
class ScriptLocation {
  ScriptLocation(this.scriptRef, {this.location});

  final ScriptRef scriptRef;

  /// This field can be null.
  final SourcePosition location;

  @override
  bool operator ==(other) {
    return other is ScriptLocation &&
        other.scriptRef == scriptRef &&
        other.location == location;
  }

  @override
  int get hashCode => hashValues(scriptRef, location);

  @override
  String toString() => '${scriptRef.uri} $location';
}

/// A line, column, and an optional tokenPos.
class SourcePosition {
  SourcePosition({@required this.line, @required this.column, this.tokenPos});

  final int line;
  final int column;
  final int tokenPos;

  @override
  bool operator ==(other) {
    return other is SourcePosition &&
        other.line == line &&
        other.column == column &&
        other.tokenPos == tokenPos;
  }

  @override
  int get hashCode => (line << 7) ^ column;

  @override
  String toString() => '$line:$column';
}

/// A tuple of a breakpoint and a source position.
abstract class BreakpointAndSourcePosition
    implements Comparable<BreakpointAndSourcePosition> {
  BreakpointAndSourcePosition._(this.breakpoint, [this.sourcePosition]);

  factory BreakpointAndSourcePosition.create(Breakpoint breakpoint,
      [SourcePosition sourcePosition]) {
    if (breakpoint.location is SourceLocation) {
      return _BreakpointAndSourcePositionResolved(
          breakpoint, sourcePosition, breakpoint.location as SourceLocation);
    } else if (breakpoint.location is UnresolvedSourceLocation) {
      return _BreakpointAndSourcePositionUnresolved(breakpoint, sourcePosition,
          breakpoint.location as UnresolvedSourceLocation);
    } else {
      throw 'invalid value for breakpoint.location';
    }
  }

  final Breakpoint breakpoint;
  final SourcePosition sourcePosition;

  bool get resolved => breakpoint.resolved;

  ScriptRef get scriptRef;

  String get scriptUri;

  int get line;

  int get column;

  int get tokenPos;

  String get id => breakpoint.id;

  @override
  int get hashCode => breakpoint.hashCode;

  @override
  bool operator ==(other) {
    return other is BreakpointAndSourcePosition &&
        other.breakpoint == breakpoint;
  }

  @override
  int compareTo(BreakpointAndSourcePosition other) {
    final result = scriptUri.compareTo(other.scriptUri);
    if (result != 0) return result;

    if (resolved != other.resolved) return resolved ? 1 : -1;

    if (resolved) {
      return tokenPos - other.tokenPos;
    } else {
      return line - other.line;
    }
  }
}

class _BreakpointAndSourcePositionResolved extends BreakpointAndSourcePosition {
  _BreakpointAndSourcePositionResolved(
      Breakpoint breakpoint, SourcePosition sourcePosition, this.location)
      : super._(breakpoint, sourcePosition);

  final SourceLocation location;

  @override
  ScriptRef get scriptRef => location.script;

  @override
  String get scriptUri => location.script.uri;

  @override
  int get tokenPos => location.tokenPos;

  @override
  int get line => sourcePosition?.line;

  @override
  int get column => sourcePosition?.column;
}

class _BreakpointAndSourcePositionUnresolved
    extends BreakpointAndSourcePosition {
  _BreakpointAndSourcePositionUnresolved(
      Breakpoint breakpoint, SourcePosition sourcePosition, this.location)
      : super._(breakpoint, sourcePosition);

  final UnresolvedSourceLocation location;

  @override
  ScriptRef get scriptRef => location.script;

  @override
  String get scriptUri => location.script?.uri ?? location.scriptUri;

  @override
  int get tokenPos => location.tokenPos;

  @override
  int get line => sourcePosition?.line ?? location.line;

  @override
  int get column => sourcePosition?.column ?? location.column;
}

/// A tuple of a stack frame and a source position.
class StackFrameAndSourcePosition {
  StackFrameAndSourcePosition(
    this.frame, {
    this.position,
  });

  final Frame frame;

  /// This can be null.
  final SourcePosition position;

  ScriptRef get scriptRef => frame.location?.script;

  String get scriptUri => frame.location?.script?.uri;

  int get line => position?.line;

  int get column => position?.column;
}

Future<Obj> getObjectHelper(IsolateRef isolateRef, ObjRef objRef) {
  return serviceManager.service.getObject(isolateRef.id, objRef.id);
}

/// Builds the tree representation for a [Variable] object by querying data,
/// creating child Variable objects, and assigning parent-child relationships.
///
/// We call this method as we expand variables in the variable tree, because
/// building the tree for all variable data at once is very expensive.
Future<void> buildVariablesTree(Variable variable) async {
  if (!variable.isExpandable ||
      variable.treeInitialized ||
      variable.boundVar.value is! InstanceRef) return;

  final InstanceRef instanceRef = variable.boundVar.value;
  try {
    final dynamic result =
        await getObjectHelper(variable.ref.isolateRef, instanceRef);
    if (result is Instance) {
      if (result.associations != null) {
        variable.addAllChildren(
            _createVariablesForAssociations(result, variable.ref.isolateRef));
      } else if (result.elements != null) {
        variable.addAllChildren(
            _createVariablesForElements(result, variable.ref.isolateRef));
      } else if (result.bytes != null) {
        variable.addAllChildren(
            _createVariablesForBytes(result, variable.ref.isolateRef));
        // Check fields last, as all instanceRefs may have a non-null fields
        // with no entries.
      } else if (result.fields != null) {
        variable.addAllChildren(
            _createVariablesForFields(result, variable.ref.isolateRef));
      }
    }
  } on SentinelException {
    // Fail gracefully if calling `getObject` throws a SentinelException.
  }
  variable.treeInitialized = true;
}

List<Variable> _createVariablesForAssociations(
    Instance instance, IsolateRef isolateRef) {
  final variables = <Variable>[];
  for (var i = 0; i < instance.associations.length; i++) {
    final association = instance.associations[i];
    if (association.key is! InstanceRef) {
      continue;
    }
    final key = BoundVariable(
      name: '[key]',
      value: association.key,
      scopeStartTokenPos: null,
      scopeEndTokenPos: null,
      declarationTokenPos: null,
    );
    final value = BoundVariable(
      name: '[value]',
      value: association.value,
      scopeStartTokenPos: null,
      scopeEndTokenPos: null,
      declarationTokenPos: null,
    );
    final variable = Variable.create(
      BoundVariable(
        name: '[Entry $i]',
        value: '',
        scopeStartTokenPos: null,
        scopeEndTokenPos: null,
        declarationTokenPos: null,
      ),
      isolateRef,
    );
    variable.addChild(Variable.create(key, isolateRef));
    variable.addChild(Variable.create(value, isolateRef));
    variables.add(variable);
  }
  return variables;
}

/// Decodes the bytes into the correctly sized values based on
/// [Instance.kind], falling back to raw bytes if a type is not
/// matched.
///
/// This method does not currently support [Uint64List] or
/// [Int64List].
List<Variable> _createVariablesForBytes(
    Instance instance, IsolateRef isolateRef) {
  final bytes = base64.decode(instance.bytes);
  final boundVariables = <BoundVariable>[];
  List<dynamic> result;
  switch (instance.kind) {
    case InstanceKind.kUint8ClampedList:
    case InstanceKind.kUint8List:
      result = bytes;
      break;
    case InstanceKind.kUint16List:
      result = Uint16List.view(bytes.buffer);
      break;
    case InstanceKind.kUint32List:
      result = Uint32List.view(bytes.buffer);
      break;
    case InstanceKind.kUint64List:
      // TODO: https://github.com/flutter/devtools/issues/2159
      if (kIsWeb) {
        return <Variable>[];
      }
      result = Uint64List.view(bytes.buffer);
      break;
    case InstanceKind.kInt8List:
      result = Int8List.view(bytes.buffer);
      break;
    case InstanceKind.kInt16List:
      result = Int16List.view(bytes.buffer);
      break;
    case InstanceKind.kInt32List:
      result = Int32List.view(bytes.buffer);
      break;
    case InstanceKind.kInt64List:
      // TODO: https://github.com/flutter/devtools/issues/2159
      if (kIsWeb) {
        return <Variable>[];
      }
      result = Int64List.view(bytes.buffer);
      break;
    case InstanceKind.kFloat32List:
      result = Float32List.view(bytes.buffer);
      break;
    case InstanceKind.kFloat64List:
      result = Float64List.view(bytes.buffer);
      break;
    case InstanceKind.kInt32x4List:
      result = Int32x4List.view(bytes.buffer);
      break;
    case InstanceKind.kFloat32x4List:
      result = Float32x4List.view(bytes.buffer);
      break;
    case InstanceKind.kFloat64x2List:
      result = Float64x2List.view(bytes.buffer);
      break;
    default:
      result = bytes;
  }

  for (int i = 0; i < result.length; i++) {
    boundVariables.add(BoundVariable(
      name: '[$i]',
      value: result[i],
      scopeStartTokenPos: null,
      scopeEndTokenPos: null,
      declarationTokenPos: null,
    ));
  }
  return boundVariables.map((bv) => Variable.create(bv, isolateRef)).toList();
}

List<Variable> _createVariablesForElements(
    Instance instance, IsolateRef isolateRef) {
  final boundVariables = <BoundVariable>[];
  for (int i = 0; i < instance.elements.length; i++) {
    boundVariables.add(BoundVariable(
      name: '[$i]',
      value: instance.elements[i],
      scopeStartTokenPos: null,
      scopeEndTokenPos: null,
      declarationTokenPos: null,
    ));
  }
  return boundVariables.map((bv) => Variable.create(bv, isolateRef)).toList();
}

List<Variable> _createVariablesForFields(
    Instance instance, IsolateRef isolateRef) {
  final boundVariables = instance.fields.map((field) {
    return BoundVariable(
      name: field.decl.name,
      value: field.value,
      scopeStartTokenPos: null,
      scopeEndTokenPos: null,
      declarationTokenPos: null,
    );
  });
  return boundVariables.map((bv) => Variable.create(bv, isolateRef)).toList();
}

// TODO(jacobr): gracefully handle cases where the isolate has closed and
// InstanceRef objects have become sentinels.
class Variable extends TreeNode<Variable> {
  Variable._(this.boundVar, this.ref, this.text);

  factory Variable.fromRef({
    String name = '',
    @required InstanceRef value,
    @required RemoteDiagnosticsNode diagnostic,
    @required IsolateRef isolateRef,
  }) {
    return Variable._(
      BoundVariable(
        name: name,
        value: value,
        declarationTokenPos: -1,
        scopeStartTokenPos: -1,
        scopeEndTokenPos: -1,
      ),
      GenericRef(
          isolateRef: isolateRef, diagnostic: diagnostic, instanceRef: value),
      null,
    );
  }

  factory Variable.create(BoundVariable variable, IsolateRef isolateRef,
      {RemoteDiagnosticsNode diagnostic}) {
    final value = variable.value;
    return Variable._(
      variable,
      GenericRef(
        isolateRef: isolateRef,
        diagnostic: diagnostic,
        instanceRef: value is InstanceRef ? value : null,
      ),
      null,
    );
  }

  factory Variable.text(String text) {
    return Variable._(null, null, text);
  }

  final String text;
  final BoundVariable boundVar;
  final GenericRef ref;

  bool treeInitialized = false;

  @override
  bool get isExpandable =>
      children.isNotEmpty ||
      (boundVar.value is InstanceRef &&
          (boundVar.value as InstanceRef).valueAsString == null);

  Object get value => boundVar.value;

  // TODO(kenz): add custom display for lists with more than 100 elements
  String get displayValue {
    if (text != null) {
      return text;
    }
    final value = this.value;

    String valueStr;

    if (value is InstanceRef) {
      if (value.valueAsString == null) {
        valueStr = value.classRef.name;
      } else {
        valueStr = value.valueAsString;
        if (value.valueAsStringIsTruncated == true) {
          valueStr += '...';
        }
        if (value.kind == InstanceKind.kString) {
          // TODO(devoncarew): Handle multi-line strings.
          valueStr = "'$valueStr'";
        }
      }

      if (value.kind == InstanceKind.kList) {
        valueStr = '$valueStr (${_itemCount(value.length)})';
      } else if (value.kind == InstanceKind.kMap) {
        valueStr = '$valueStr (${_itemCount(value.length)})';
      } else if (value.kind != null && value.kind.endsWith('List')) {
        // Uint8List, Uint16List, ...
        valueStr = '$valueStr (${_itemCount(value.length)})';
      }
    } else if (value is Sentinel) {
      valueStr = value.valueAsString;
    } else if (value is TypeArgumentsRef) {
      valueStr = value.name;
    } else {
      valueStr = value.toString();
    }

    return valueStr;
  }

  String _itemCount(int count) {
    return '${nf.format(count)} ${pluralize('item', count)}';
  }

  @override
  String toString() {
    if (text != null) return text;

    final value = boundVar.value is InstanceRef
        ? (boundVar.value as InstanceRef).valueAsString
        : boundVar.value;
    return '${boundVar.name} - $value';
  }

  /// Selects the object in the Flutter Widget inspector.
  ///
  /// Returns whether the inspector selection was changed
  Future<bool> inspectWidget() async {
    if (ref == null || ref.instanceRef == null) {
      return false;
    }
    final inspectorService = serviceManager.inspectorService;
    if (inspectorService == null) {
      return false;
    }
    // Group name doesn't matter in this case.
    final group = inspectorService.createObjectGroup('inspect-variables');

    try {
      return await group.setSelection(ref);
    } catch (e) {
      // This is somewhat unexpected. The inspectorRef must have been disposed.
      return false;
    } finally {
      // Not really needed as we shouldn't actually be allocating anything.
      unawaited(group.dispose());
    }
  }

  Future<bool> get isInspectable async {
    if (_isInspectable != null) return _isInspectable;

    if (ref == null) return false;
    final inspectorService = serviceManager.inspectorService;
    if (inspectorService == null) {
      return false;
    }

    // Group name doesn't matter in this case.
    final group = inspectorService.createObjectGroup('inspect-variables');

    try {
      _isInspectable = await group.isInspectable(ref);
    } catch (e) {
      _isInspectable = false;
      // This is somewhat unexpected. The inspectorRef must have been disposed.
    } finally {
      // Not really needed as we shouldn't actually be allocating anything.
      unawaited(group.dispose());
    }
    return _isInspectable;
  }

  bool _isInspectable;
}

/// A node in a tree of scripts.
///
/// A node can either be a directory (a name with potentially some child nodes),
/// a script reference (where [scriptRef] is non-null), or a combination of both
/// (where the node has a non-null [scriptRef] but also contains child nodes).
class FileNode extends TreeNode<FileNode> {
  FileNode(this.name);

  final String name;

  // This can be null.
  ScriptRef scriptRef;

  /// This exists to allow for O(1) lookup of children when building the tree.
  final Map<String, FileNode> _childrenAsMap = {};

  bool get hasScript => scriptRef != null;

  String _fileName = '';

  /// Returns the name of the file.
  ///
  /// May be empty.
  String get fileName => _fileName;

  /// Given a flat list of service protocol scripts, return a tree of scripts
  /// representing the best hierarchical grouping.
  static List<FileNode> createRootsFrom(List<ScriptRef> scripts) {
    // The name of this node is not exposed to users.
    final root = FileNode('<root>');

    for (var script in scripts) {
      final directoryParts = ScriptRefUtils.splitDirectoryParts(script);

      FileNode node = root;

      for (var name in directoryParts) {
        node = node._getCreateChild(name);
      }

      node.scriptRef = script;
      node._fileName = ScriptRefUtils.fileName(script);
    }

    // Clear out the _childrenAsMap map.
    root._trimChildrenAsMapEntries();

    return root.children;
  }

  FileNode _getCreateChild(String name) {
    return _childrenAsMap.putIfAbsent(name, () {
      final child = FileNode(name);
      child.parent = this;
      children.add(child);
      return child;
    });
  }

  /// Clear the _childrenAsMap map recursively to save memory.
  void _trimChildrenAsMapEntries() {
    _childrenAsMap.clear();

    for (var child in children) {
      child._trimChildrenAsMapEntries();
    }
  }

  @override
  int get hashCode => scriptRef?.hashCode ?? name.hashCode;

  @override
  bool operator ==(Object other) {
    if (other is! FileNode) return false;
    final FileNode node = other;

    if (scriptRef == null) {
      return node.scriptRef != null ? false : name == node.name;
    } else {
      return node.scriptRef == null ? false : scriptRef == node.scriptRef;
    }
  }
}

class ScriptRefUtils {
  static String fileName(ScriptRef scriptRef) =>
      Uri.parse(scriptRef.uri).path.split('/').last;

  /// Return the Uri for the given ScriptRef split into path segments.
  ///
  /// This is useful for converting a flat list of scripts into a directory tree
  /// structure.
  static List<String> splitDirectoryParts(ScriptRef scriptRef) {
    final uri = Uri.parse(scriptRef.uri);
    final scheme = uri.scheme;
    var parts = uri.path.split('/');

    // handle google3:///foo/bar
    if (parts.first.isEmpty) {
      parts = parts.where((part) => part.isNotEmpty).toList();
      // Combine the first non-empty path segment with the scheme:
      // 'google3:foo'.
      parts = [
        '$scheme:${parts.first}',
        ...parts.sublist(1),
      ];
    } else if (parts.first.contains('.')) {
      // Look for and handle dotted package names (package:foo.bar).
      final dottedParts = parts.first.split('.');
      parts = [
        '$scheme:${dottedParts.first}',
        ...dottedParts.sublist(1),
        ...parts.sublist(1),
      ];
    } else {
      parts = [
        '$scheme:${parts.first}',
        ...parts.sublist(1),
      ];
    }

    if (parts.length > 1) {
      return [
        parts.first,
        parts.sublist(1).join('/'),
      ];
    } else {
      return parts;
    }
  }
}
