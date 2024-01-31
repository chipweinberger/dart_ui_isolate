import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:dart_ui_isolate/dart_ui_isolate.dart';

@pragma('vm:entry-point')
void _flutterIsolateEntryPoint() => DartUiIsolate.macosIsolateInitialize();

@pragma('vm:entry-point')
void isolateEntryPoint(String arg) async {
  // setup
  print('isolate: setup canvas');
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint();
  paint.style = ui.PaintingStyle.fill;

  // draw circle
  print('isolate: drawing circle');
  final size = ui.Size(300, 300);
  final center = ui.Offset(size.width / 2, size.height / 2);
  final radius = size.width / 4;
  canvas.drawCircle(center, radius, paint);

  // end
  print('isolate: ending recording');
  recorder.endRecording();
}

void main() async {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        home: Scaffold(
            appBar: AppBar(
              title: const Text('Dart UI Isolate'),
            ),
            body: AppWidget()));
  }
}

class AppWidget extends StatelessWidget {
  static void downloaderCallback(String id, int status, int progress) {
    print("progress: $progress");
  }

  Future<void> _runTest() async {
    final isolate = await DartUiIsolate.spawn(isolateEntryPoint, "painter");
    Timer(Duration(seconds: 5), () {
      print("Pausing Isolate 1");
      isolate.pause();
    });
    Timer(Duration(seconds: 10), () {
      print("Resuming Isolate 1");
      isolate.resume();
    });
    Timer(Duration(seconds: 20), () {
      print("Killing Isolate 1");
      isolate.kill();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Padding(
          padding: const EdgeInsets.only(top: 30),
          child: ElevatedButton(
            child: Text('Test Dart UI Isolate'),
            onPressed: _runTest,
          ),
        ),
      ]),
    );
  }
}
