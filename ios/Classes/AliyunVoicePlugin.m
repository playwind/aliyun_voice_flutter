#import <Flutter/Flutter.h>
#import "NuiAsrHandler.h"
#import "NuiTtsHandler.h"

@interface AliyunVoicePlugin : NSObject <FlutterPlugin, FlutterStreamHandler>
@property (nonatomic, strong) NuiAsrHandler *asrHandler;
@property (nonatomic, strong) NuiTtsHandler *ttsHandler;
@property (nonatomic, copy) FlutterEventSink asrEventSink;
@property (nonatomic, copy) FlutterEventSink ttsEventSink;
@end

@implementation AliyunVoicePlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    AliyunVoicePlugin *instance = [[AliyunVoicePlugin alloc] init];

    FlutterMethodChannel *asrChannel = [FlutterMethodChannel
        methodChannelWithName:@"com.p1aywind.aliyun_voice/asr"
              binaryMessenger:registrar.messenger];
    [registrar addMethodCallDelegate:instance channel:asrChannel];

    FlutterEventChannel *asrEventChannel = [FlutterEventChannel
        eventChannelWithName:@"com.p1aywind.aliyun_voice/asr_events"
             binaryMessenger:registrar.messenger];
    [asrEventChannel setStreamHandler:instance];

    FlutterMethodChannel *ttsChannel = [FlutterMethodChannel
        methodChannelWithName:@"com.p1aywind.aliyun_voice/tts"
              binaryMessenger:registrar.messenger];
    [registrar addMethodCallDelegate:instance channel:ttsChannel];

    FlutterEventChannel *ttsEventChannel = [FlutterEventChannel
        eventChannelWithName:@"com.p1aywind.aliyun_voice/tts_events"
             binaryMessenger:registrar.messenger];
    [ttsEventChannel setStreamHandler:instance];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([call.method hasPrefix:@"asr_"]) {
        if (!_asrHandler) {
            _asrHandler = [[NuiAsrHandler alloc] initWithEventSink:self.asrEventSink];
        }
        [_asrHandler handleMethodCall:call result:result];
    } else if ([call.method hasPrefix:@"tts_"]) {
        if (!_ttsHandler) {
            _ttsHandler = [[NuiTtsHandler alloc] initWithEventSink:self.ttsEventSink];
        }
        [_ttsHandler handleMethodCall:call result:result];
    } else {
        result(FlutterMethodNotImplemented);
    }
}

#pragma mark - FlutterStreamHandler

- (FlutterError *)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {
    // Determine which event channel by checking arguments
    // Both channels use this handler, differentiate by the channel name
    // We set both sinks; each handler only sends to its own
    if (!self.asrEventSink) {
        self.asrEventSink = events;
        _asrHandler.eventSink = events;
    } else if (!self.ttsEventSink) {
        self.ttsEventSink = events;
        _ttsHandler.eventSink = events;
    }
    return nil;
}

- (FlutterError *)onCancelWithArguments:(id)arguments {
    if (self.asrEventSink) {
        self.asrEventSink = nil;
        _asrHandler.eventSink = nil;
    } else if (self.ttsEventSink) {
        self.ttsEventSink = nil;
        _ttsHandler.eventSink = nil;
    }
    return nil;
}

@end
