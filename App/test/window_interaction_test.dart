import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:necaramba/data/platform_window_interaction.dart';
import 'package:necaramba/domain/repositories/window_interaction.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'window bridge sends geometry and admits opaque UUID handles only',
    () async {
      const channel = MethodChannel('test.window');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      final port = PlatformWindowInteraction(channel: channel);
      final values = <String>[];
      final subscription = port.headerDropHandles.listen(values.add);
      await port.updateHeaderDropRegion(const HeaderDropRegion(1, 2, 300, 120));
      await port.updateHeaderDropRegion(null);
      expect(calls.first.arguments, {
        'x': 1.0,
        'y': 2.0,
        'width': 300.0,
        'height': 120.0,
      });
      expect(calls.last.arguments, isNull);
      Future<void> send(Object arguments) async {
        await messenger.handlePlatformMessage(
          'test.window',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('headerDrop', arguments),
          ),
          (ByteData? _) {},
        );
        await Future<void>.delayed(Duration.zero);
      }

      await send({'handle': '/private/arbitrary/path'});
      await send({'handle': '12345678-1234-1234-1234-123456789abc'});
      expect(values, ['12345678-1234-1234-1234-123456789abc']);
      await subscription.cancel();
      await port.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
}
