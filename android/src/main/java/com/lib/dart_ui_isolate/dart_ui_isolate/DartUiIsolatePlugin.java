package com.lib.dart_ui_isolate;

import android.content.Context;

import androidx.annotation.NonNull;

import java.lang.reflect.InvocationTargetException;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.Queue;
import java.util.Set;

import io.flutter.FlutterInjector;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.embedding.engine.FlutterEngineGroup;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.EventChannel.StreamHandler;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.view.FlutterCallbackInformation;
import io.flutter.view.FlutterRunArguments;

class IsolateHolder {
    FlutterEngine engine;
    String isolateId;

    EventChannel startupChannel;
    MethodChannel controlChannel;

    Long entryPoint;
    Result result;
}

public class DartUiIsolatePlugin implements FlutterPlugin, MethodCallHandler, StreamHandler {

    private Queue<IsolateHolder> queuedIsolates;
    private Map<String, IsolateHolder> activeIsolates;
    private Context context;
    private FlutterEngineGroup engineGroup;

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        engineGroup = new FlutterEngineGroup(binding.getApplicationContext()); 
        setupChannel(binding.getBinaryMessenger(), binding.getApplicationContext());
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    }

    private void setupChannel(BinaryMessenger messenger, Context context) {
        this.context = context;
        MethodChannel controlChannel = new MethodChannel(messenger, "com.lib.dart_ui_isolate/control");
        queuedIsolates = new LinkedList<>();
        activeIsolates = new HashMap<>();

        controlChannel.setMethodCallHandler(this);
    }

    private void startNextIsolate() {
        IsolateHolder isolate = queuedIsolates.peek();

        FlutterInjector.instance().flutterLoader().ensureInitializationComplete(context, null);

        FlutterCallbackInformation cbInfo = FlutterCallbackInformation.lookupCallbackInformation(isolate.entryPoint);

        isolate.engine = engineGroup.createAndRunEngine(context, new DartExecutor.DartEntrypoint(
            FlutterInjector.instance().flutterLoader().findAppBundlePath(),
            cbInfo.callbackLibraryPath,
            cbInfo.callbackName
        ));

        isolate.controlChannel = new MethodChannel(isolate.engine.getDartExecutor().getBinaryMessenger(), "com.lib.dart_ui_isolate/control");
        isolate.startupChannel = new EventChannel(isolate.engine.getDartExecutor().getBinaryMessenger(), "com.lib.dart_ui_isolate/event");

        isolate.startupChannel.setStreamHandler(this);
        isolate.controlChannel.setMethodCallHandler(this);
    }

    @Override
    public void onMethodCall(MethodCall call, @NonNull Result result) {

        if (call.method.equals("spawn_isolate")) {

            IsolateHolder isolate = new IsolateHolder();

            final Object entryPoint = call.argument("entry_point");

            if(entryPoint instanceof Long) {
                isolate.entryPoint = (Long) entryPoint;
            }

            if(entryPoint instanceof Integer) {
                isolate.entryPoint = Long.valueOf((Integer) entryPoint);
            }

            isolate.isolateId = call.argument("isolate_id");
            isolate.result = result;

            queuedIsolates.add(isolate);

            // no other pending isolate
            if (queuedIsolates.size() == 1) { 
                startNextIsolate();
            }

        } else if (call.method.equals("kill_isolate")) {

            String isolateId = call.argument("isolate_id");

            try {
                activeIsolates.get(isolateId).engine.destroy();
            } catch (Exception e) {
                e.printStackTrace();
            }

            activeIsolates.remove(isolateId);

            result.success(true);

        } else {
            result.notImplemented();
        }
    }

    @Override
    public void onListen(Object o, EventChannel.EventSink sink) {
        if (queuedIsolates.size() != 0) {
            IsolateHolder isolate = queuedIsolates.remove();

            sink.success(isolate.isolateId);
            sink.endOfStream();
            activeIsolates.put(isolate.isolateId, isolate);

            isolate.result.success(null);
            isolate.startupChannel = null;
            isolate.result = null;
        }

        if (queuedIsolates.size() != 0) {
            startNextIsolate();
        }
    }

    @Override
    public void onCancel(Object o) {
    }
}
