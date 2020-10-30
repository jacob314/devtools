// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:devtools_app/src/framework/framework_core.dart';
import 'package:devtools_app/src/globals.dart';
import 'package:devtools_app/src/navigation.dart';
import 'package:flutter/material.dart';

import 'package:devtools_app/src/analytics/stub_provider.dart'
    if (dart.library.html) 'src/analytics/remote_provider.dart';
import 'package:devtools_app/src/app.dart';
import 'package:devtools_app/src/config_specific/framework_initialize/framework_initialize.dart';
import 'package:devtools_app/src/config_specific/ide_theme/ide_theme.dart';
import 'package:devtools_app/src/preferences.dart';
import 'package:flutter_driver/driver_extension.dart';

void main() async {
  Future<String> handler(
      String message,
      {Duration timeout},
      ) async {
    print("XXX got message: $message");
    final connectPrefix = 'connect:';
    if (message.startsWith(connectPrefix)) {
      final uri = Uri.parse(message.substring(connectPrefix.length));
      final connected = await FrameworkCore.initVmService(
        '',
        explicitUri: uri,
        errorReporter: (message, error) {
          print("Got error: $error");
        },
      );
      if (connected) {
        final connectedUri = serviceManager.service.connectedUri;
        final context =  WidgetsBinding.instance.renderViewElement;
        await
          Navigator.pushNamed(
            context,
            routeNameWithQueryParams(context, '/', {'uri': '$connectedUri'}),
          );
        return connectedUri.toString();
      }
    }
    return null;
  }

  enableFlutterDriverExtension(handler: handler);
  final ideTheme = getIdeTheme();

  final preferences = PreferencesController();
  // Wait for preferences to load before rendering the app to avoid a flash of
  // content with the incorrect theme.
  await preferences.init();

  await initializeFramework();

  // Now run the app.
  runApp(
    DevToolsApp(defaultScreens, preferences, ideTheme, await analyticsProvider),
  );
}
