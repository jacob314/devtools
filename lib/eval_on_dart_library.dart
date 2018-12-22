// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'package:devtools/inspector/inspector_service.dart';
import 'package:meta/meta.dart';
import 'package:vm_service_lib/vm_service_lib.dart';

import 'globals.dart';
import 'vm_service_wrapper.dart';

class EvalOnDartLibrary {
  EvalOnDartLibrary(this.libraryName, this.service) {
    _libraryRef = new Completer<LibraryRef>();

    // TODO: do we need to dispose this subscription at some point? Where?
    serviceManager.isolateManager
        .getCurrentFlutterIsolate((IsolateRef isolate) {
      if (_libraryRef.isCompleted) {
        _libraryRef = new Completer<LibraryRef>();
      }

      if (isolate != null) {
        _initialize(isolate.id);
      }
    });
  }

  bool _disposed = false;

  void dispose() {
    _disposed = true;
  }

  final String libraryName;
  final VmServiceWrapper service;
  Completer<LibraryRef> _libraryRef;

  String get isolateId => _isolateId;
  String _isolateId;

  Future<LibraryRef> get libraryRef => _libraryRef.future;
  Completer allPendingRequestsDone;

  void _initialize(String isolateId) async {
    _isolateId = isolateId;

    try {
      final Isolate isolate = await service.getIsolate(_isolateId);
      for (LibraryRef library in isolate.libraries) {
        if (library.uri == libraryName) {
          _libraryRef.complete(library);
          return;
        }
      }
    } catch (e) {
      _handleError(e);
    }
  }

  Future<InstanceRef> eval(
    String expression, {
    @required ObjectGroup isAlive,
    Map<String, String> scope,
  }) {
    return addRequest(isAlive, () => _eval(expression, scope: scope));
  }

  Future<InstanceRef> _eval(
    String expression, {
    @required Map<String, String> scope,
  }) async {
    if (_disposed) return null;

    try {
      final LibraryRef libraryRef = await _libraryRef.future;
      return await service.evaluate(
        _isolateId,
        libraryRef.id,
        expression,
        scope: scope,
      );
    } catch (e) {
      _handleError(e);
    }
    return null;
  }

  void _handleError(dynamic e) {
    if (_disposed) return;

    switch (e.runtimeType) {
      case RPCError:
        print('RPCError ${e.code}: ${e.details}');
        break;
      case Error:
        print('${e.kind}: ${e.message}');
        break;
      default:
        print('Unrecognized error: $e');
    }
  }

  Future<Library> getLibrary(LibraryRef instance, ObjectGroup isAlive) {
    return getObjHelper(instance, isAlive);
  }

  Future<Class> getClass(ClassRef instance, ObjectGroup isAlive) {
    return getObjHelper(instance, isAlive);
  }

  Future<Func> getFunc(FuncRef instance, ObjectGroup isAlive) {
    return getObjHelper(instance, isAlive);
  }

  Future<Instance> getInstance(
    FutureOr<InstanceRef> instanceRefFuture,
    ObjectGroup isAlive,
  ) async {
    return await getObjHelper(await instanceRefFuture, isAlive);
  }

  /// Public so that other related classes such as InspectorService can ensure
  /// their requests are in a consistent order with existing requests. This
  /// eliminates otherwise surprising timing bugs, such as if a request to
  /// dispose an InspectorService.ObjectGroup was issued after a request to read
  /// properties from an object in a group, but the request to dispose the
  /// object group occurred first.
  ///
  /// With this design, we have at most 1 pending request at a time. This
  /// sacrifices some throughput, but we gain the advantage of predictable
  /// semantics and the ability to skip large numbers of requests from object
  /// groups that should no longer be kept alive.
  ///
  /// The optional ObjectGroup specified by [isAlive] indicates whether the
  /// request is still relevant or should be cancelled. This is an optimization
  /// for the Inspector so that it does not overload the service with stale requests.
  /// Stale requests will be generated if the user is quickly navigating through the
  /// UI to view specific details subtrees.
  Future<T> addRequest<T>(ObjectGroup isAlive, Future<T> request()) async {
    if (isAlive != null && isAlive.disposed) return null;

    // Future that completes when the request has finished.
    final Completer<T> response = new Completer();
    // This is an optimization to avoid sending stale requests across the wire.
    void wrappedRequest() async {
      if (isAlive != null && isAlive.disposed || _disposed) {
        response.complete(null);
        return;
      }
      try {
        final T value = await request();
        if (!_disposed) {
          response.complete(value);
        } else {
          response.complete(null);
        }
      } catch (e) {
        if (_disposed) {
          response.complete(null);
        } else {
          response.completeError(e);
        }
      }
    }

    if (allPendingRequestsDone == null || allPendingRequestsDone.isCompleted) {
      allPendingRequestsDone = response;
      wrappedRequest();
    } else {
      if (isAlive != null && isAlive.disposed || _disposed) {
        response.complete(null);
        return response.future;
      }

      final Future previousDone = allPendingRequestsDone.future;
      allPendingRequestsDone = response;
      // Schedule this request only after the previous request completes.
      try {
        await previousDone;
      } catch (e) {
        if (!_disposed) {
          print(e);
        }
      }
      wrappedRequest();
    }
    return response.future;
  }

  Future<T> getObjHelper<T extends Obj>(
    ObjRef instance,
    ObjectGroup isAlive, {
    int offset,
    int count,
  }) async {
    return addRequest<T>(
        isAlive, () async {
      final T value = await service.getObject(_isolateId, instance.id,
        offset: offset, count: count,);
      return value;
    });
  }
}
