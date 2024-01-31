#import "DartUiIsolatePlugin.h"
#import <objc/message.h>

@interface IsolateHolder : NSObject
@property(nonatomic) FlutterEngine* engine;
@property(nonatomic) NSString* isolateId;
@property(nonatomic) long long entryPoint;
@property(nonatomic) FlutterResult result;
@property(nonatomic) FlutterEventChannel* startupChannel;
@property(nonatomic) FlutterMethodChannel* controlChannel;
@end

@implementation IsolateHolder
@end

static dispatch_once_t _initializeStaticPlugin = 0;
static NSMutableArray<IsolateHolder*>* _queuedIsolates;
static NSMutableDictionary<NSString*,IsolateHolder*>* _activeIsolates;


@interface DartUiIsolatePlugin()
@property(nonatomic) NSObject<FlutterPluginRegistrar> * registrar;
@property(nonatomic) FlutterEngineGroup* engineGroup; 
@property(nonatomic) FlutterMethodChannel* controlChannel;
@property FlutterEventSink sink;
@end

@implementation DartUiIsolatePlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    dispatch_once(&_initializeStaticPlugin, ^{
        _queuedIsolates = [NSMutableArray<IsolateHolder*> new];
        _activeIsolates = [NSMutableDictionary<NSString*,IsolateHolder*> new];
    });
    
    DartUiIsolatePlugin *plugin = [[DartUiIsolatePlugin alloc] init];
    
    plugin.registrar = registrar;

    plugin.engineGroup = [[FlutterEngineGroup alloc] initWithName:@"dart_ui_isolate" project:nil];
    
    plugin.controlChannel = [FlutterMethodChannel methodChannelWithName:@"com.lib.dart_ui_isolate/control"
                                                        binaryMessenger:[registrar messenger]];

    [registrar addMethodCallDelegate:plugin channel:plugin.controlChannel];
}

- (void)startNextIsolate {
    IsolateHolder *isolate = _queuedIsolates.firstObject;

    FlutterCallbackInformation *info = [FlutterCallbackCache lookupCallbackInformation:isolate.entryPoint];

    isolate.engine = [[self.engineGroup makeEngineWithEntrypoint:info.callbackName libraryURI:info.callbackLibraryPath]
        initWithName:isolate.isolateId project:nil allowHeadlessExecution:YES];

    // not entire sure if a listen on an event channel will be queued
    // as we cannot register the event channel until after runWithEntryPoint has been called. If it is not queued
    // then this will be a race on the FlutterEventChannels initialization, and could deadlock.
    [isolate.engine runWithEntrypoint:info.callbackName libraryURI:info.callbackLibraryPath];

    isolate.controlChannel = [FlutterMethodChannel methodChannelWithName:@"com.lib.dart_ui_isolate/control"
                                                         binaryMessenger:isolate.engine.binaryMessenger];

    isolate.startupChannel = [FlutterEventChannel eventChannelWithName:@"com.lib.dart_ui_isolate/event"
                                                       binaryMessenger:isolate.engine.binaryMessenger];

    [isolate.startupChannel setStreamHandler:self];
    
    [_registrar addMethodCallDelegate:self channel:isolate.controlChannel];
}


- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"spawn_isolate" isEqualToString:call.method]) {

      IsolateHolder* isolate = [IsolateHolder new];

      isolate.entryPoint = [[call.arguments objectForKey:@"entry_point"] longLongValue];
      isolate.isolateId = [call.arguments objectForKey:@"isolate_id"];
      isolate.result = result;

      [_queuedIsolates addObject:isolate];

      if (_queuedIsolates.count == 1) {
          [self startNextIsolate];
      }

  } else if ([@"kill_isolate" isEqualToString:call.method]) {

      NSString *isolateId = [call.arguments objectForKey:@"isolate_id"];

      if ([_activeIsolates[isolateId].engine respondsToSelector:@selector(destroyContext)]) {
          ((void(*)(id,SEL))objc_msgSend)(_activeIsolates[isolateId].engine, @selector(destroyContext));
      }

      [_activeIsolates removeObjectForKey:isolateId];

      result(nil);

  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (FlutterError*)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)sink {

    IsolateHolder* isolate = _queuedIsolates.firstObject;

    if (isolate != nil) {
        sink(isolate.isolateId);
        sink(FlutterEndOfEventStream);
        _activeIsolates[isolate.isolateId] = isolate;
        [_queuedIsolates removeObject:isolate];

        isolate.result(@(YES));
        isolate.startupChannel = nil;
        isolate.result = nil;
    }

    if (_queuedIsolates.count != 0) {
        [self startNextIsolate];
    }

    return nil;

}

- (FlutterError*)onCancelWithArguments:(id)arguments {
    return nil;
}

@end
