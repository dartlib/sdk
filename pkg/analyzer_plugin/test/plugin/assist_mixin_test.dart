// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/src/test_utilities/resource_provider_mixin.dart';
import 'package:analyzer_plugin/plugin/assist_mixin.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/protocol/protocol_generated.dart';
import 'package:analyzer_plugin/src/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'mocks.dart';

void main() {
  defineReflectiveTests(AssistsMixinTest);
}

@reflectiveTest
class AssistsMixinTest with ResourceProviderMixin {
  String packagePath1;
  String filePath1;
  ContextRoot contextRoot1;

  MockChannel channel;
  _TestServerPlugin plugin;

  void setUp() {
    packagePath1 = convertPath('/package1');
    filePath1 = join(packagePath1, 'lib', 'test.dart');
    newFile(filePath1);
    contextRoot1 = new ContextRoot(packagePath1, <String>[]);

    channel = new MockChannel();
    plugin = new _TestServerPlugin(resourceProvider);
    plugin.start(channel);
  }

  test_handleEditGetAssists() async {
    await plugin.handleAnalysisSetContextRoots(
        new AnalysisSetContextRootsParams([contextRoot1]));

    EditGetAssistsResult result = await plugin
        .handleEditGetAssists(new EditGetAssistsParams(filePath1, 10, 0));
    expect(result, isNotNull);
    expect(result.assists, hasLength(3));
  }
}

class _TestAssistContributor implements AssistContributor {
  List<PrioritizedSourceChange> changes;

  _TestAssistContributor(this.changes);

  @override
  void computeAssists(AssistRequest request, AssistCollector collector) {
    for (PrioritizedSourceChange change in changes) {
      collector.addAssist(change);
    }
  }
}

class _TestServerPlugin extends MockServerPlugin with AssistsMixin {
  _TestServerPlugin(ResourceProvider resourceProvider)
      : super(resourceProvider);

  PrioritizedSourceChange createChange() {
    return new PrioritizedSourceChange(0, new SourceChange(''));
  }

  @override
  List<AssistContributor> getAssistContributors(String path) {
    return <AssistContributor>[
      new _TestAssistContributor(<PrioritizedSourceChange>[createChange()]),
      new _TestAssistContributor(
          <PrioritizedSourceChange>[createChange(), createChange()])
    ];
  }

  @override
  Future<AssistRequest> getAssistRequest(
      EditGetAssistsParams parameters) async {
    var result = new MockResolvedUnitResult();
    return new DartAssistRequestImpl(
        resourceProvider, parameters.offset, parameters.length, result);
  }
}
