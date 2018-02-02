// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:process/process.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

/// A mock that can be used to fake a process manager that runs commands
/// and returns results.
///
/// Call [setResults] to provide a list of results that will return from
/// each command line (with arguments).
///
/// Call [verifyCalls] to verify that each desired call occurred.
class FakeProcessManager extends Mock implements ProcessManager {
  FakeProcessManager({this.stdinResults}) {
    _setupMock();
  }

  /// The callback that will be called each time stdin input is supplied to
  /// a call.
  final StringReceivedCallback stdinResults;

  /// The list of results that will be sent back, organized by the command line
  /// that will produce them.  Each command line has a list of returned stdout
  /// output that will be returned on each successive call.
  Map<String, List<ProcessResult>> fakeResults = <String, List<ProcessResult>>{};

  /// The list of invocations that occurred, in the order they occurred.
  List<Invocation> invocations = <Invocation>[];

  /// Verify that the given command lines were called, in the given order.
  void verifyCalls(List<String> calls) {
    int index = 0;
    expect(invocations.length, equals(calls.length));
    for (String call in calls) {
      expect(call.split(' '), orderedEquals(invocations[index].positionalArguments[0]));
      index++;
    }
  }

  /// Sets the list of results that will be returned from each successive call.
  void setResults(Map<String, List<String>> results) {
    final Map<String, List<ProcessResult>> resultCodeUnits = <String, List<ProcessResult>>{};
    for (String key in results.keys) {
      resultCodeUnits[key] =
          results[key].map((String result) => new ProcessResult(0, 0, result, '')).toList();
    }
    fakeResults = resultCodeUnits;
  }

  ProcessResult _popResult(String key) {
    expect(fakeResults, isNotEmpty);
    expect(fakeResults, contains(key));
    expect(fakeResults[key], isNotEmpty);
    return fakeResults[key].removeAt(0);
  }

  FakeProcess _popProcess(String key) =>
      new FakeProcess(_popResult(key), stdinResults: stdinResults);

  Future<Process> _nextProcess(Invocation invocation) async {
    invocations.add(invocation);
    return new Future<Process>.value(_popProcess(invocation.positionalArguments[0].join(' ')));
  }

  ProcessResult _nextResultSync(Invocation invocation) {
    invocations.add(invocation);
    return _popResult(invocation.positionalArguments[0].join(' '));
  }

  Future<ProcessResult> _nextResult(Invocation invocation) async {
    invocations.add(invocation);
    return new Future<ProcessResult>.value(_popResult(invocation.positionalArguments[0].join(' ')));
  }

  void _setupMock() {
    // Note that not all possible types of invocations are covered here, just the ones
    // expected to be called.
    // TODO(gspencer): make this more general so that any call will be captured.
    when(
      start(
        typed(captureAny),
        environment: typed(captureAny, named: 'environment'),
        workingDirectory: typed(captureAny, named: 'workingDirectory'),
      ),
    ).thenAnswer(_nextProcess);

    when(
      start(
        typed(captureAny),
      ),
    ).thenAnswer(_nextProcess);

    when(
      run(
        typed(captureAny),
        environment: typed(captureAny, named: 'environment'),
        workingDirectory: typed(captureAny, named: 'workingDirectory'),
      ),
    ).thenAnswer(_nextResult);

    when(
      run(
        typed(captureAny),
      ),
    ).thenAnswer(_nextResult);

    when(
      runSync(
        typed(captureAny),
        environment: typed(captureAny, named: 'environment'),
        workingDirectory: typed(captureAny, named: 'workingDirectory'),
      ),
    ).thenAnswer(_nextResultSync);

    when(
      runSync(
        typed(captureAny),
      ),
    ).thenAnswer(_nextResultSync);

    when(killPid(typed(captureAny), typed(captureAny))).thenReturn(true);

    when(
      canRun(captureAny,
          workingDirectory: typed(
            captureAny,
            named: 'workingDirectory',
          )),
    ).thenReturn(true);
  }
}

/// A fake process that can be used to interact with a process "started" by the FakeProcessManager.
class FakeProcess extends Mock implements Process {
  FakeProcess(ProcessResult result, {void stdinResults(String input)})
      : stdoutStream = new Stream<List<int>>.fromIterable(<List<int>>[result.stdout.codeUnits]),
        stderrStream = new Stream<List<int>>.fromIterable(<List<int>>[result.stderr.codeUnits]),
        desiredExitCode = result.exitCode,
        stdinSink = new IOSink(new StringStreamConsumer(stdinResults)) {
    _setupMock();
  }

  final IOSink stdinSink;
  final Stream<List<int>> stdoutStream;
  final Stream<List<int>> stderrStream;
  final int desiredExitCode;

  void _setupMock() {
    when(kill(typed(captureAny))).thenReturn(true);
  }

  @override
  Future<int> get exitCode => new Future<int>.value(desiredExitCode);

  @override
  int get pid => 0;

  @override
  IOSink get stdin => stdinSink;

  @override
  Stream<List<int>> get stderr => stderrStream;

  @override
  Stream<List<int>> get stdout => stdoutStream;
}

/// Callback used to receive stdin input when it occurs.
typedef void StringReceivedCallback(String received);

/// A stream consumer class that consumes UTF8 strings as lists of ints.
class StringStreamConsumer implements StreamConsumer<List<int>> {
  StringStreamConsumer(this.sendString);

  List<Stream<List<int>>> streams = <Stream<List<int>>>[];
  List<StreamSubscription<List<int>>> subscriptions = <StreamSubscription<List<int>>>[];
  List<Completer<dynamic>> completers = <Completer<dynamic>>[];

  /// The callback called when this consumer receives input.
  StringReceivedCallback sendString;

  @override
  Future<dynamic> addStream(Stream<List<int>> value) {
    streams.add(value);
    completers.add(new Completer<dynamic>());
    subscriptions.add(value.listen((List<int> data) {
      sendString(utf8.decode(data));
    }));
    subscriptions.last.onDone(() => completers.last.complete(null));
    return new Future<dynamic>.value(null);
  }

  @override
  Future<dynamic> close() async {
    for (Completer<dynamic> completer in completers) {
      await completer.future;
    }
    completers.clear();
    streams.clear();
    subscriptions.clear();
    return new Future<dynamic>.value(null);
  }
}