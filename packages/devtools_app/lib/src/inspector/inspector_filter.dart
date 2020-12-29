// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

import '../dialogs.dart';
import '../ui/utils.dart';
import 'inspector_controller.dart';

/// State of the libraries and packages (hidden or not) for the filter dialog.
class LibraryFilter {
  LibraryFilter(this.displayName, this.hide);

  /// Displayed library name.
  final String displayName;

  /// Whether classes in this library hidden (filtered).
  bool hide;
}

class InspectorFilterDialog extends StatelessWidget {
  const InspectorFilterDialog(this.controller);

  final InspectorSettingsController controller;

  @override
  Widget build(BuildContext context) {
    // TODO(devoncarew): Convert to a DevToolsDialog.
    final theme = Theme.of(context);

    return DevToolsDialog(
      title: dialogTitleText(theme, 'Filter summary widget tree'),
      content: Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: Column(
          children: [
            Row(
              children: [
                NotifierCheckbox(notifier: controller.showOnlyUserDefined),
                const Text('Show only user defined widgets'),
              ],
            ),
            Row(
              children: [
                NotifierCheckbox(
                    notifier: controller.expandSelectedBuildMethod),
                const Text('Expand selected build method'),
              ],
            ),
          ],
        ),
      ),
      actions: [
        DialogCloseButton(),
      ],
    );
  }
}
