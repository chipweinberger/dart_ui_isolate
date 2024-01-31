import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

export 'src/compute.dart';

class DartUiIsolate {

  static DartUiIsolate? _current;
  static final _control = MethodChannel("com.lib.dart_ui_isolate/control");
  static final _event = EventChannel("com.lib.dart_ui_isolate/event");

  String? _isolateId;

  /// Control port used to send control messages to the isolate.
  SendPort? controlPort;

  /// Capability granting the ability to pause the isolate (not implemented)
  Capability? pauseCapability;

  /// Capability granting the ability to terminate the isolate (not implemented)
  Capability? terminateCapability;

  /// private
  DartUiIsolate._([this._isolateId, this.controlPort, this.pauseCapability, this.terminateCapability]);

  bool get _isCurrentIsolate => _isolateId == null || _current != null && _current!._isolateId == _isolateId;

  /// Requests the isolate to pause. This uses the underlying isolates pause
  /// implementation to pause the isolate from with the pausing isolate
  /// otherwises uses a SendPort to pass through a pause requres to the target
  void pause() => _isCurrentIsolate
      ? Isolate.current.pause()
      : Isolate(controlPort!, pauseCapability: pauseCapability, terminateCapability: terminateCapability)
          .pause(pauseCapability);

  /// Requests the isolate to resume. This uses the underlying isolates resume
  /// implementation to as it takes advangtage of functionality that is not
  /// exposed, ie sending 'out of band' messages to an isolate. Regular 'user'
  /// ports will not be serviced when an isolate is paused.
  void resume() => _isCurrentIsolate
      ? Isolate.current.resume(Capability())
      : Isolate(controlPort!, pauseCapability: pauseCapability, terminateCapability: terminateCapability)
          .resume(pauseCapability!);

  /// Requestes to terminate the flutter isolate. As the isolate that is
  /// created is backed by a FlutterBackgroundView/FlutterEngine for the
  /// platform implementations, the event loop will continue to execute
  /// even after user code has completed. Thus they must be explicitly
  /// terminate using kill if you wish to dispose of them after you have
  /// finished. This should cleanup the native components backing the isolates.
  void kill({int priority = Isolate.beforeNextEvent}) => _isolateId != null
      ? _control.invokeMethod("kill_isolate", {"isolate_id": _isolateId})
      : Isolate.current.kill(priority: priority);

  static DartUiIsolate get current => _current != null ? _current! : DartUiIsolate._();

  @pragma('vm:entry-point')
  static macosIsolateInitialize() {
    _isolateInitialize();
  }

  /// Creates and spawns a flutter isolate that shares the same code
  /// as the current isolate. The spawned isolate will be able to use flutter
  /// plugins. T can be any type that can be normally be passed through to
  /// regular isolate's entry point.
  static Future<DartUiIsolate> spawn<T>(void entryPoint(T message), T message) async {
    final userEntryPointId = PluginUtilities.getCallbackHandle(entryPoint)!.toRawHandle();
    final isolateId = _uuid();
    final isolateResult = Completer<DartUiIsolate>();
    final setupReceivePort = ReceivePort();

    IsolateNameServer.registerPortWithName(setupReceivePort.sendPort, isolateId);
    late StreamSubscription setupSubscription;
    setupSubscription = setupReceivePort.listen((data) {
      final portSetup = (data as List<dynamic>);
      final setupPort = portSetup[0] as SendPort;
      final remoteIsolate = DartUiIsolate._(isolateId, portSetup[1] as SendPort?, portSetup[2], portSetup[3]);

      setupPort.send(<Object?>[userEntryPointId, message]);

      setupSubscription.cancel();
      setupReceivePort.close();
      isolateResult.complete(remoteIsolate);
    });
    _control.invokeMethod("spawn_isolate", {
      "entry_point": PluginUtilities.getCallbackHandle(_flutterIsolateEntryPoint)!.toRawHandle(),
      "isolate_id": isolateId
    });
    return isolateResult.future;
  }

  @pragma('vm:entry-point')
  static void _isolateInitialize() {

    WidgetsFlutterBinding.ensureInitialized();

    late StreamSubscription eventSubscription;

    eventSubscription = _event.receiveBroadcastStream().listen((isolateId) {

      _current = DartUiIsolate._(isolateId, null, null);

      final sendPort = IsolateNameServer.lookupPortByName(_current!._isolateId!)!;

      final setupReceivePort = ReceivePort();

      IsolateNameServer.removePortNameMapping(_current!._isolateId!);

      sendPort.send(<dynamic>[
        setupReceivePort.sendPort,
        Isolate.current.controlPort,
        Isolate.current.pauseCapability,
        Isolate.current.terminateCapability
      ]);

      eventSubscription.cancel();

      late StreamSubscription setupSubscription;
      
      setupSubscription = setupReceivePort.listen((data) {
        final args = data as List<Object?>;
        final userEntryPointHandle = args[0] as int;
        final userMessage = args[1];
        Function userEntryPoint =
            PluginUtilities.getCallbackFromHandle(CallbackHandle.fromRawHandle(userEntryPointHandle))!;
        setupSubscription.cancel();
        setupReceivePort.close();
        userEntryPoint(userMessage);
      });
    });
  }
}

// helper function
String _uuid() {
  var random = Random();
  Uint8List bytes = Uint8List(16);
  for (int i = 0; i < 16; i++) {
    bytes[i] = random.nextInt(256);
  }

  var uuid = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  var a = uuid.substring(0, 8);
  var b = uuid.substring(8, 12);
  var c = uuid.substring(12, 16);
  var d = uuid.substring(16, 20);
  var e = uuid.substring(20);

  return '$a-$b-$c-$d-$e';
}


@pragma('vm:entry-point')
void _flutterIsolateEntryPoint() => DartUiIsolate._isolateInitialize();
