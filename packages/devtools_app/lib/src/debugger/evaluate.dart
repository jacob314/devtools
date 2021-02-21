// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vm_service/vm_service.dart';

import '../globals.dart';
import '../notifications.dart';
import 'debugger_controller.dart';

// TODO(devoncarew): We'll want some kind of code completion w/ eval.

class ExpressionEvalField extends StatefulWidget {
  const ExpressionEvalField();

  @override
  _ExpressionEvalFieldState createState() => _ExpressionEvalFieldState();
}

class _ExpressionEvalFieldState extends State<ExpressionEvalField> {
  TextEditingController textController;
  FocusNode textFocus;
  int historyPosition = -1;

  EvalHistory evalHistory;

  @override
  void initState() {
    super.initState();

    // TODO(jacobr): consider moving this to a ConsoleController.
    evalHistory = EvalHistory();
    textController = TextEditingController();
    textFocus = FocusNode();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.focusColor),
        ),
      ),
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          const Text('>'),
          const SizedBox(width: 8.0),
          Expanded(
            child: Focus(
              onKey: (_, RawKeyEvent event) {
                if (event.isKeyPressed(LogicalKeyboardKey.arrowUp)) {
                  _historyNavUp();
                  return true;
                } else if (event.isKeyPressed(LogicalKeyboardKey.arrowDown)) {
                  _historyNavDown();
                  return true;
                }

                return false;
              },
              child: TextField(
                onSubmitted: (value) => _handleExpressionEval(context, value),
                focusNode: textFocus,
                decoration: null,
                controller: textController,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleExpressionEval(
    BuildContext context,
    String expressionText,
  ) async {
    textFocus.requestFocus();

    // Don't try to eval if we're not paused.
    if (!serviceManager
        .isolateManager.mainIsolateDebuggerState.isPaused.value) {
      Notifications.of(context)
          .push('Application must be paused to support expression evaluation.');
      return;
    }

    expressionText = expressionText.trim();

    serviceManager.consoleService.appendStdio('> $expressionText\n');
    setState(() {
      historyPosition = -1;
      evalHistory.pushEvalHistory(expressionText);
    });
    textController.clear();

    try {
      // Response is either a ErrorRef, InstanceRef, or Sentinel.
      final controller =
          Provider.of<DebuggerController>(context, listen: false);
      final isolateRef = controller.isolateRef;
      final response = await controller.evalAtCurrentFrame(expressionText);

      // Display the response to the user.
      if (response is InstanceRef) {
        _emitRefToConsole(response, isolateRef);
      } else {
        var value = response.toString();

        if (response is ErrorRef) {
          value = response.message;
        } else if (response is Sentinel) {
          value = response.valueAsString;
        }

        _emitToConsole(value);
      }
    } catch (e) {
      // Display the error to the user.
      _emitToConsole('$e');
    }
  }

  void _emitToConsole(String text) {
    serviceManager.consoleService.appendStdio(
        '  ${text.replaceAll('\n', '\n  ')}\n',
        forceScrollIntoView: true);
  }

  void _emitRefToConsole(
    InstanceRef ref,
    IsolateRef isolate,
  ) {
    serviceManager.consoleService.appendInstanceRef(
      value: ref,
      inspectorRef: null,
      isolate: isolate,
      forceScrollIntoView: true,
    );
  }

  @override
  void dispose() {
    textFocus.dispose();
    textController.dispose();
    super.dispose();
  }

  void _historyNavUp() {
    if (!evalHistory.canNavigateUp) {
      return;
    }

    setState(() {
      evalHistory.navigateUp();

      final text = evalHistory.currentText;
      textController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
  }

  void _historyNavDown() {
    if (!evalHistory.canNavigateDown) {
      return;
    }

    setState(() {
      evalHistory.navigateDown();

      final text = evalHistory.currentText ?? '';
      textController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
  }
}
