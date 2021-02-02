// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

import '../common_widgets.dart';
import '../console.dart';
import 'debugger_controller.dart';
import 'evaluate.dart';

// TODO(devoncarew): Show some small UI indicator when we receive stdout/stderr.

/// Display the stdout and stderr output from the process under debug.
class DebuggerConsole extends StatefulWidget {
  const DebuggerConsole({
    Key key,
    this.controller,
  }) : super(key: key);

  final DebuggerController controller;

  @override
  _DebuggerConsoleState createState() => _DebuggerConsoleState();

  static const copyToClipboardButtonKey =
      Key('debugger_console_copy_to_clipboard_button');
  static const clearStdioButtonKey = Key('debugger_console_clear_stdio_button');
}

class _DebuggerConsoleState extends State<DebuggerConsole> {
  @override
  Widget build(BuildContext context) {
    return OutlineDecoration(
      child: Column(
        children: [
          Expanded(
            child: Console(
              title: areaPaneHeader(
                context,
                title: 'Console',
                needsTopBorder: false,
                actions: [
                  CopyToClipboardControl(
                    dataProvider: () =>
                        widget.controller.stdio.value?.join('\n') ?? '',
                    buttonKey: DebuggerConsole.copyToClipboardButtonKey,
                  ),
                  DeleteControl(
                    buttonKey: DebuggerConsole.clearStdioButtonKey,
                    tooltip: 'Clear console output',
                    onPressed: widget.controller.clearStdio,
                  ),
                ],
              ),
              lines: widget.controller.stdio,
            ),
          ),
          ExpressionEvalField(controller: widget.controller),
        ],
      ),
    );
  }
}
