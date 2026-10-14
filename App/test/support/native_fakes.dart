import 'dart:async';

import 'package:necaramba/domain/entities/native_state.dart';
import 'package:necaramba/domain/repositories/native_repository.dart';

NativeState fixture({
  int revision = 1,
  bool auto = true,
  String sessionID = 'test',
  String status = 'permissionRequired',
  Map<String, bool>? capabilities,
}) => NativeState(
  sessionID: sessionID,
  revision: revision,
  preferences: {
    'autoEnabled': auto,
    'typoEnabled': true,
    'yoEnabled': true,
    'singleShiftEnabled': true,
    'optionEnabled': false,
    'splitShiftEnabled': true,
    'plainPasteEnabled': true,
    'soundEnabled': true,
  },
  capabilities:
      capabilities ??
      {'listen': true, 'post': false, 'axTrusted': false, 'secureInput': false},
  status: status,
  words: [],
  apps: [],
  model: {'version': '1', 'lastChecked': null, 'state': 'current'},
  license: {'state': 'trial', 'expiresAt': null},
  statistics: {'layout': 3, 'typo': 2},
  appearance: {
    'colorIndex': 0,
    'hasCustomSound': false,
    'hasHeaderImage': false,
  },
  login: {'enabled': false, 'status': 'disabled'},
);

class FakeNativeRepository implements NativeRepository {
  NativeState current = fixture(
    capabilities: {
      'listen': true,
      'post': true,
      'axTrusted': true,
      'secureInput': false,
    },
  );
  final controller = StreamController<NativeState>.broadcast();
  final calls = <({String method, Map<String, Object?> arguments})>[];
  NativeFailure? failure;
  Completer<NativeReply>? pending;
  Map<String, Object?> result = {};
  @override
  Stream<NativeState> get states => controller.stream;
  void publish(NativeState value) {
    current = value;
    controller.add(value);
  }

  @override
  Future<NativeState> refresh() async => current;
  @override
  Future<NativeReply> command(
    String method,
    Map<String, Object?> arguments,
  ) async {
    calls.add((method: method, arguments: arguments));
    if (failure != null) {
      final error = failure!;
      failure = null;
      throw error;
    }
    if (pending != null) return pending!.future;
    return NativeReply(requestID: 'test', state: current, result: result);
  }

  @override
  Future<void> dispose() => controller.close();
}
