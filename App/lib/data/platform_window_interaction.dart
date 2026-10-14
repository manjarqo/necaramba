import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/repositories/window_interaction.dart';

/// Engine-local window geometry and opaque image handles only.
final class PlatformWindowInteraction implements WindowInteractionPort {
  PlatformWindowInteraction({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('necaramba/window.v1') {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'headerDrop') return;
      final arguments = call.arguments;
      if (arguments is! Map || arguments.length != 1) return;
      final handle = arguments['handle'];
      if (handle is String &&
          RegExp(r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')
              .hasMatch(handle)) {
        _drops.add(handle);
      }
    });
  }

  final MethodChannel _channel;
  final _drops = StreamController<String>.broadcast();
  @override
  Stream<String> get headerDropHandles => _drops.stream;

  @override
  Future<void> updateHeaderDropRegion(HeaderDropRegion? region) =>
      _channel.invokeMethod<void>(
        'updateHeaderDropRegion',
        region == null
            ? null
            : {
                'x': region.x,
                'y': region.y,
                'width': region.width,
                'height': region.height,
              },
      );

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _drops.close();
  }
}
