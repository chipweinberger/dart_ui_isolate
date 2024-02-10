## dart_ui_isolate

This plugin let you run `dart:ui` in an isolate.

See this issue: https://github.com/flutter/flutter/issues/10647

## FlutterEngineGroup Support

Unlike [flutter_isolate](https://pub.dev/packages/flutter_isolate), `dart_ui_isolate` supports `FlutterEngineGroup`.

`FlutterEngineGroup` makes spawning isolates instant. It also reduces 99% of RAM for spawned isolates.

**Note**: `FlutterEngineGroup` is supported on both iOS & Android, but not macOS.

## No Platform Plugin Support

Unlike [flutter_isolate](https://pub.dev/packages/flutter_isolate), `dart_ui_isolate` does *not* support calling platform plugins in the spawned isolate. 

**Why?** As of Flutter 3.7, you can call platform plugins from a normal `Isolate`, i.e. should just use a normal `Isolate`. In the rare case you need to use both `dart:ui` & platform plugins from the same isolate, you should preferably use a normal `Isolate` + `dart:ui` isolate and pass data between them, or you can use [flutter_isolate](https://pub.dev/packages/flutter_isolate).**, 

There are a couple more advantages:
1. Removing support for platform plugins makes `dart_ui_isolate` simpler.
2. Removing support for platform plugins allows using `FlutterEngineGroup` See: https://github.com/rmawatson/flutter_isolate/pull/151



## DartUiIsolate API

|                       |      Android       |         iOS          |             Description            |
| :-------------------- | :----------------: | :------------------: |  :-------------------------------- |
| DartUiIsolate.spawn() | :white_check_mark: |  :white_check_mark:  | spawns a new DartUiIsolate         |
| isolate.pause()       | :white_check_mark: |  :white_check_mark:  | pauses the isolate                 |
| isolate.resume()      | :white_check_mark: |  :white_check_mark:  | resumes the isolate                |
| isolate.kill()        | :white_check_mark: |  :white_check_mark:  | kills the an isolate               |
| flutterCompute()      | :white_check_mark: |  :white_check_mark:  | runs code in compute callback      |

## Usage

To spawn a `DartUiIsolate`, call the `spawn()` method, or the `flutterCompute()` method.

## Killing

`DartUiIsolate`s require explict termination with `kill()`.

`DartUiIsolate`s are backed by a platform specific 'view', so the event loop does not automatically terminate when there is no more work left.

## MacOS

Due to limitations on Flutter macOS, you must put this code in your `/lib/main.dart` file.

**/lib/main.dart**
```
@pragma('vm:entry-point')
void _flutterIsolateEntryPoint() => DartUiIsolate.macosIsolateInitialize();
```

## Compute Callback

To use an isolate for a single task (like the Flutter [`compute` method](https://api.flutter.dev/flutter/foundation/compute-constant.html)), use `flutterCompute`:

```dart
@pragma('vm:entry-point')
Future<int> expensiveWork(int arg) async {
  int result;
  // lots of calculations
  return result;
}

Future<int> doExpensiveWorkInBackground() async {
  return await flutterCompute(expensiveWork, arg);
}
```

## Isolate Entry Point

The isolate entrypoint must be a *top-level* function, or a class `static` method.

The isolate entrypoint must decorated with `@pragma('vm:entry-point')`. Otherwise the app will crash in release mode.

**Top-Level Entry Point:**

```dart
@pragma('vm:entry-point')
void topLevelFunction(Map<String, dynamic> args) {
  // performs work in an isolate
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    DartUiIsolate.spawn(topLevelFunction, {});
    super.initState();
  }

  Widget build(BuildContext context) {
    return Container();
  }
}
```

**Class Static Entry Point:**

```dart
class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  
  @pragma('vm:entry-point')
  static void topLevelFunction(Map<String, dynamic> args) {
    // performs work in an isolate
  }

  @override
  void initState() {
    DartUiIsolate.spawn(_MyAppState.staticMethod, {});
    super.initState();
  }

  Widget build(BuildContext context) {
    return Container();
  }
}
```

**A class-level method will *not* work and will throw an Exception:**

```dart
class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {

  
  void classMethod(Map<String, dynamic> args) {
    // don't do this!
  }

  @override
  void initState() {
    // this will throw NoSuchMethodError: The method 'toRawHandle' was called on null.
    DartUiIsolate.spawn(classMethod, {}); 
    super.initState();
  }
  Widget build(BuildContext context) {
    return Container();
  }
}
```




