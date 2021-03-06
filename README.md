# Flutter DevTools
[![Build Status](https://travis-ci.org/flutter/devtools.svg?branch=master)](https://travis-ci.org/flutter/devtools)

Performance tools for Flutter.

## What is this?

This repo is a companion repo to the main [flutter
repo](https://github.com/flutter/flutter). It contains the source code for
a suite of Flutter performance tools.

## But there's not much here?

It's still very early in development - stay tuned.

## Development

- git clone https://github.com/flutter/devtools
- cd devtools
- pub get

From a separate terminal:
- cd <path/to/flutter-sdk>/examples/flutter_gallery
- ensure the iOS Simulator is open (or a physical device is connected)
- flutter run

From the devtools directory:
- pub run webdev serve

Then, open a browser window to the local url specified by webdev. After the page has loaded, append
`?port=xxx` to the url, where xxx is the port number of the service protocol port, as specified by 
the `flutter run` output.

For more efficient development, launch your flutter application specifying
`--observatory-port` so the observatory is available on a fixed port. This
lets you avoid manually entering the observatory port paremeter each time
you launch the application.

- flutter run --observatory-port=8888
- open http://localhost:8080/?port=8888

## Deployment

The strategy to deploy this tool has not yet been finalized.
An important thing to be aware of is that the development steps build the
application using [dartdevc](https://webdev.dartlang.org/tools/dartdevc)
while the application will be deployed using the Dart2Js compiler which
generally generates more efficient JS.
