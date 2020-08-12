// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:vm_service/vm_service.dart';

import '../auto_dispose_mixin.dart';
import '../dialogs.dart';
import '../flutter_widgets/linked_scroll_controller.dart';
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

class InspectorFilterDialog extends StatefulWidget {
  const InspectorFilterDialog(this.controller);

  final InspectorController controller;

  @override
  InspectorFilterDialogState createState() => InspectorFilterDialogState();
}

class InspectorFilterDialogState extends State<InspectorFilterDialog>
    with AutoDisposeMixin {
  InspectorController controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (controller == widget.controller) return;

    controller = widget.controller;

    cancel();

    // Detect and handle checkboxes state changing.
    addAutoDisposeListener(controller.filterPrivateClassesListenable, () {
      setState(() {
        privateClasses.notifier.value = controller.filterPrivateClasses.value;
      });
    });
    addAutoDisposeListener(controller.filterLibraryNoInstancesListenable, () {
      setState(() {
        libraryNoInstances.notifier.value =
            controller.filterLibraryNoInstances.value;
      });
    });
    addAutoDisposeListener(controller.filterZeroInstancesListenable, () {
      setState(() {
        zeroInstances.notifier.value = controller.filterZeroInstances.value;
      });
    });
  }

  void addLibrary(String libraryName, {bool hideState = false}) {
    final filteredGroup = controller.filteredLibrariesByGroupName;
    final filters = controller.libraryFilters;

    final isFiltered = filters.isLibraryFiltered(libraryName);
    String groupedName = libraryName;
    bool hide = hideState;
    if (isFiltered) {
      if (filters.isDartLibraryName(libraryName)) {
        groupedName = _prettyPrintDartAbbreviation;
      } else if (filters.isFlutterLibraryName(libraryName)) {
        groupedName = _prettyPrintFlutterAbbreviation;
      }
    }
    hide = isFiltered;

    // Used by checkboxes in dialog.
    filteredGroup[groupedName] ??= [];
    filteredGroup[groupedName].add(LibraryFilter(libraryName, hide));
  }

  void buildFilters() {
    if (controller == null) return;

    // First time filters created, populate with the default list of libraries
    // to filters
    if (controller.filteredLibrariesByGroupName.isEmpty) {
      for (final library in controller.libraryFilters.librariesFiltered) {
        addLibrary(library, hideState: true);
      }
      // If not snapshots, return no libraries to process.
      if (controller.snapshots.isEmpty) return;
    }

    // No libraries to compute until a snapshot exist.
    if (controller.snapshots.isEmpty) return;

    final libraries = controller.libraryRoot == null
        ? controller.activeSnapshot.children
        : controller.libraryRoot.children;

    libraries..sort((a, b) => a.name.compareTo(b.name));

    for (final library in libraries) {
      // Don't include external and filtered these are a composite and can't be filtered out.
      if (library.name != externalLibraryName &&
          library.name != filteredLibrariesName) {
        addLibrary(library.name);
      }
    }
  }

  /// Process wildcard groups dart:* and package:flutter*. If a wildcard group is
  /// toggled from on to off then all the dart: packages will appear if the group
  /// dart:* is toggled back on then all the dart: packages must be removed.
  void cleanupFilteredLibrariesByGroupName() {
    final filteredGroup = controller.filteredLibrariesByGroupName;
    final dartGlobal = filteredGroup[_prettyPrintDartAbbreviation].first.hide;
    final flutterGlobal =
        filteredGroup[_prettyPrintFlutterAbbreviation].first.hide;

    filteredGroup.removeWhere((groupName, libraryFilter) {
      if (dartGlobal &&
          groupName != _prettyPrintDartAbbreviation &&
          groupName.startsWith(_dartLibraryUriPrefix)) {
        return true;
      } else if (flutterGlobal &&
          groupName != _prettyPrintFlutterAbbreviation &&
          groupName.startsWith(_flutterLibraryUriPrefix)) {
        return true;
      }

      return false;
    });
  }

  Widget createLibraryListBox(BoxConstraints constraints) {
    return SizedBox(
      height: constraints.maxHeight / 4,
      child: ListView(
        controller: _letters,
        children:
            controller.filteredLibrariesByGroupName.keys.map((String key) {
          return CheckboxListTile(
            title: Text(key),
            dense: true,
            value: controller.filteredLibrariesByGroupName[key].first.hide,
            onChanged: (bool value) {
              setState(() {
                for (var filter
                    in controller.filteredLibrariesByGroupName[key]) {
                  filter.hide = value;
                }
              });
            },
          );
        }).toList(),
      ),
    );
  }

  Widget okCancelButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        DialogOkButton(
          () {
            // Re-generate librariesFiltered
            controller.libraryFilters.clearFilters();
            controller.filteredLibrariesByGroupName.forEach((groupName, value) {
              if (value.first.hide) {
                var filteredName = groupName;
                if (filteredName.endsWith('*')) {
                  filteredName = filteredName.substring(
                    0,
                    filteredName.length - 1,
                  );
                }
                controller.libraryFilters.addFilter(filteredName);
              }
            });
            // Re-filter the groups.
            controller.libraryRoot = null;
            if (controller.lastSnapshot != null) {
              controller.heapGraph.computeFilteredGroups();
              controller.computeAllLibraries(
                graph: controller.lastSnapshot.snapshotGraph,
              );
            }
            cleanupFilteredLibrariesByGroupName();
            controller.updateFilter();
          },
        ),
        DialogCancelButton(),
      ],
    );
  }

  NotifierCheckbox privateClasses;
  NotifierCheckbox zeroInstances;
  NotifierCheckbox libraryNoInstances;

  @override
  Widget build(BuildContext context) {
    buildFilters();

    privateClasses =
        NotifierCheckbox(notifier: controller.filterPrivateClasses);
    zeroInstances = NotifierCheckbox(notifier: controller.filterZeroInstances);
    libraryNoInstances =
        NotifierCheckbox(notifier: controller.filterLibraryNoInstances);

    // Dialog has three main vertical sections:
    //      - three checkboxes
    //      - one list of libraries with at least 5 entries
    //      - one row of buttons Ok/Cancel
    // For very tall app keep the dialog at a reasonable height w/o too much vertical whitespace.
    // The listbox area is the area that grows to accommodate the list of known libraries.
    // TODO(devoncarew): Convert to a DevToolsDialog.
    return Dialog(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return Container(
            width: MediaQuery.of(context).size.width / 3,
            height: constraints.maxHeight < 400
                ? constraints.maxHeight
                : constraints.maxHeight * .3 + (400 * .7),
            child: Padding(
              padding: const EdgeInsets.only(left: 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      const TextField(
                        decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            labelText: 'Filter Snapshot'),
                      ),
                      Row(
                        children: [
                          privateClasses,
                          const Text('Hide Private Class e.g.,_className'),
                        ],
                      ),
                      Row(
                        children: [
                          zeroInstances,
                          const Text('Hide Classes with No Instances'),
                        ],
                      ),
                      Row(
                        children: [
                          libraryNoInstances,
                          const Text('Hide Library with No Instances'),
                        ],
                      ),
                      Row(
                        children: [
                          const Padding(padding: EdgeInsets.only(top: 30)),
                          Text('Hide Libraries or Packages '
                              '(${controller.filteredLibrariesByGroupName.length}):'),
                        ],
                      ),
                      createLibraryListBox(constraints),
                      const Padding(padding: EdgeInsets.only(top: 40)),
                      okCancelButtons(),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
