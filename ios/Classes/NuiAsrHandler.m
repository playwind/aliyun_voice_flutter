#import "NuiAsrHandler.h"
#import <nuisdk/NeoNui.h>
#import <nuisdk/NeoNuiCode.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

static const int kSampleRate = 16000;
static const int kBufferSize = 6400;

#pragma mark - Audio Queue

@interface NuiAudioQueue : NSObject
@property (nonatomic, assign) AudioQueueRef queue;
@property (nonatomic, assign) AudioQueueBufferRef *buffers;
@property (nonatomic, strong) NSMutableData *audioData;
@property (nonatomic, assign) BOOL isRecording;
@end

@implementation NuiAudioQueue

- (instancetype)init {
    self = [super init];
    if (self) {
        _audioData = [NSMutableData data];
        _isRecording = NO;
        _buffers = malloc(sizeof(AudioQueueBufferRef) * 3);
        if (!_buffers) {
            return nil;
        }
    }
    return self;
}

static void AudioInputCallback(void *inUserData,
                                AudioQueueRef inAQ,
                                AudioQueueBufferRef inBuffer,
                                const AudioTimeStamp *inStartTime,
                                UInt32 inNumPackets,
                                const AudioStreamPacketDescription *inPacketDesc) {
    NuiAudioQueue *recorder = (__bridge NuiAudioQueue *)inUserData;
    if (!recorder.isRecording) return;

    [recorder.audioData appendBytes:inBuffer->mAudioData length:inBuffer->mAudioDataByteSize];

    AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
}

- (BOOL)start {
    if (_isRecording) return YES;
    [_audioData setLength:0];

    AudioStreamBasicDescription format = {0};
    format.mSampleRate = kSampleRate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = 2;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = 2;
    format.mChannelsPerFrame = 1;
    format.mBitsPerChannel = 16;

    OSStatus status = AudioQueueNewInput(&format, AudioInputCallback, (__bridge void *)self, NULL, NULL, 0, &_queue);
    if (status != noErr) return NO;

    for (int i = 0; i < 3; i++) {
        AudioQueueAllocateBuffer(_queue, kBufferSize, &_buffers[i]);
        AudioQueueEnqueueBuffer(_queue, _buffers[i], 0, NULL);
    }

    _isRecording = YES;
    AudioQueueStart(_queue, NULL);
    return YES;
}

- (void)stop {
    if (!_isRecording) return;
    _isRecording = NO;
    AudioQueueStop(_queue, YES);
    AudioQueueDispose(_queue, YES);
    _queue = NULL;
}

- (void)dealloc {
    if (_buffers) {
        free(_buffers);
        _buffers = NULL;
    }
}

- (void)releaseQueue {
    [self stop];
    [_audioData setLength:0];
}

- (int)readData:(char *)buffer length:(int)len {
    @synchronized (self) {
        if ((int)_audioData.length >= len) {
            memcpy(buffer, _audioData.bytes, len);
            [_audioData replaceBytesInRange:NSMakeRange(0, len) withBytes:NULL length:0];
            return len;
        }
        return 0;
    }
}

@end

#pragma mark - NuiAsrHandler

@interface NuiAsrHandler ()
@property (nonatomic, strong) NeoNui *nui;
@property (nonatomic, strong) NuiAudioQueue *audioQueue;
@property (nonatomic, assign) BOOL initialized;
@end

@implementation NuiAsrHandler

- (instancetype)initWithEventSink:(FlutterEventSink)eventSink {
    self = [super init];
    if (self) {
        _eventSink = eventSink;
        _nui = [[NeoNui alloc] init];
        _nui.delegate = self;
        _audioQueue = [[NuiAudioQueue alloc] init];
        _initialized = NO;
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([call.method isEqualToString:@"asr_initialize"]) {
        [self handleInitialize:call result:result];
    } else if ([call.method isEqualToString:@"asr_startDialog"]) {
        [self handleStartDialog:call result:result];
    } else if ([call.method isEqualToString:@"asr_stopDialog"]) {
        [self handleStopDialog:result];
    } else if ([call.method isEqualToString:@"asr_cancelDialog"]) {
        [self handleCancelDialog:result];
    } else if ([call.method isEqualToString:@"asr_release"]) {
        [self handleRelease:result];
    } else {
        result(FlutterMethodNotImplemented);
    }
}

#pragma mark - Methods

- (void)handleInitialize:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSString *appKey = call.arguments[@"appKey"];
    NSString *token = call.arguments[@"token"];

    if (!appKey.length || !token.length) {
        result([FlutterError errorWithCode:@"INVALID_PARAMS" message:@"appKey and token are required" details:nil]);
        return;
    }

    NSString *deviceId = [[[UIDevice currentDevice] identifierForVendor] UUIDString] ?: @"unknown";
    NSString *workPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    workPath = [workPath stringByAppendingPathComponent:@"nui_workspace"];

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:workPath withIntermediateDirectories:YES attributes:nil error:nil];

    // Copy SDK resources
    [self copySDKResources:workPath];

    NSString *debugPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"nui_debug_%lld", (long long)([[NSDate date] timeIntervalSince1970] * 1000)]];
    [fm createDirectoryAtPath:debugPath withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *params = [NSString stringWithFormat:
        @"{\"app_key\":\"%@\",\"token\":\"%@\",\"device_id\":\"%@\","
        "\"url\":\"wss://nls-gateway.cn-shanghai.aliyuncs.com:443/ws/v1\","
        "\"workspace\":\"%@\",\"sample_rate\":\"16000\",\"format\":\"opus\","
        "\"debug_path\":\"%@\",\"service_mode\":4}",
        appKey, token, deviceId, workPath, debugPath];

    int ret = [_nui nui_initialize:[params UTF8String]
                           logLevel:NUI_LOG_LEVEL_VERBOSE
                            saveLog:YES];
    if (ret == 0) {
        _initialized = YES;
        result(@(YES));
    } else {
        result([FlutterError errorWithCode:@"ASR_INIT_FAILED"
                                   message:[NSString stringWithFormat:@"initialize returned %d", ret]
                                   details:nil]);
    }
}

- (void)handleStartDialog:(FlutterMethodCall *)call result:(FlutterResult)result {
    if (!_initialized) {
        result([FlutterError errorWithCode:@"NOT_INITIALIZED" message:@"ASR not initialized" details:nil]);
        return;
    }

    BOOL enableVad = [call.arguments[@"enableVad"] boolValue];
    int maxStartSilence = [call.arguments[@"maxStartSilence"] intValue] ?: 10000;
    int maxEndSilence = [call.arguments[@"maxEndSilence"] intValue] ?: 800;

    NSMutableDictionary *nlsConfig = [NSMutableDictionary dictionary];
    nlsConfig[@"enable_intermediate_result"] = @(YES);
    nlsConfig[@"enable_punctuation_prediction"] = @(YES);
    nlsConfig[@"enable_inverse_text_normalization"] = @(YES);
    if (enableVad) {
        nlsConfig[@"enable_voice_detection"] = @(YES);
        nlsConfig[@"max_start_silence"] = @(maxStartSilence);
        nlsConfig[@"max_end_silence"] = @(maxEndSilence);
    }

    NSDictionary *params = @{
        @"nls_config": nlsConfig,
        @"service_type": @(0)
    };
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:params options:0 error:nil];
    NSString *paramsStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    [_nui nui_set_params:[paramsStr UTF8String]];

    int ret = [_nui nui_dialog_start:MODE_P2T dialogParam:"{}"];
    if (ret == 0) {
        result(@(YES));
    } else {
        result([FlutterError errorWithCode:@"ASR_START_FAILED"
                                   message:[NSString stringWithFormat:@"startDialog returned %d", ret]
                                   details:nil]);
    }
}

- (void)handleStopDialog:(FlutterResult)result {
    if (!_initialized) {
        result([FlutterError errorWithCode:@"NOT_INITIALIZED" message:@"ASR not initialized" details:nil]);
        return;
    }
    int ret = [_nui nui_dialog_cancel:NO];
    if (ret == 0) result(@(YES));
    else result([FlutterError errorWithCode:@"ASR_STOP_FAILED"
                                     message:[NSString stringWithFormat:@"stopDialog returned %d", ret]
                                     details:nil]);
}

- (void)handleCancelDialog:(FlutterResult)result {
    if (!_initialized) {
        result([FlutterError errorWithCode:@"NOT_INITIALIZED" message:@"ASR not initialized" details:nil]);
        return;
    }
    int ret = [_nui nui_dialog_cancel:YES];
    if (ret == 0) result(@(YES));
    else result([FlutterError errorWithCode:@"ASR_CANCEL_FAILED"
                                     message:[NSString stringWithFormat:@"cancelDialog returned %d", ret]
                                     details:nil]);
}

- (void)handleRelease:(FlutterResult)result {
    if (!_initialized) {
        result(@(YES));
        return;
    }
    int ret = [_nui nui_release];
    _initialized = NO;
    if (ret == 0) result(@(YES));
    else result([FlutterError errorWithCode:@"ASR_RELEASE_FAILED"
                                     message:[NSString stringWithFormat:@"release returned %d", ret]
                                     details:nil]);
}

#pragma mark - NeoNuiSdkDelegate

-(int) onNuiNeedAudioData:(char *)audioData length:(int)len {
    return [_audioQueue readData:audioData length:len];
}

-(void) onNuiAudioStateChanged:(NuiAudioState)state {
    if (state == STATE_OPEN) {
        [_audioQueue start];
    } else if (state == STATE_CLOSE) {
        [_audioQueue releaseQueue];
    } else if (state == STATE_PAUSE) {
        [_audioQueue stop];
    }
}

-(void) onNuiEventCallback:(NuiCallbackEvent)nuiEvent
                      dialog:(long)dialog
                  kwsResult:(const char *)wuw
                  asrResult:(const char *)asr_result
                   ifFinish:(BOOL)finish
                    retCode:(int)code {
    switch (nuiEvent) {
        case EVENT_VAD_START:
            [self sendEvent:@"vadStart" data:nil];
            break;
        case EVENT_VAD_END:
            [self sendEvent:@"vadEnd" data:nil];
            break;
        case EVENT_ASR_PARTIAL_RESULT:
            [self sendEvent:@"partialResult" data:@{@"text": asr_result ? @(asr_result) : @""}];
            break;
        case EVENT_ASR_RESULT:
            [self sendEvent:@"finalResult" data:@{@"text": asr_result ? @(asr_result) : @""}];
            break;
        case EVENT_ASR_ERROR:
            [self sendEvent:@"error" data:@{@"code": @(code), @"message": asr_result ? @(asr_result) : @"ASR error"}];
            break;
        case EVENT_MIC_ERROR:
            [self sendEvent:@"micError" data:nil];
            break;
        default:
            break;
    }
}

-(void) onNuiRmsChanged:(float)rms {
    [self sendEvent:@"audioRms" data:@{@"value": @(rms)}];
}

#pragma mark - Helpers

- (void)sendEvent:(NSString *)type data:(NSDictionary *)data {
    NSMutableDictionary *event = [NSMutableDictionary dictionaryWithObject:type forKey:@"type"];
    if (data) [event addEntriesFromDictionary:data];
    if (_eventSink) _eventSink(event);
}

- (void)copySDKResources:(NSString *)workPath {
    NSBundle *sdkBundle = [NSBundle bundleForClass:[NeoNui class]];
    NSString *resourcePath = [sdkBundle pathForResource:@"Resources" ofType:@"bundle"];
    if (!resourcePath) return;

    NSBundle *resBundle = [NSBundle bundleWithPath:resourcePath];
    if (!resBundle) return;

    NSString *copylistPath = [resBundle pathForResource:@"copylist" ofType:@"txt"];
    if (!copylistPath) return;

    NSString *copylist = [NSString stringWithContentsOfFile:copylistPath encoding:NSUTF8StringEncoding error:nil];
    NSArray *items = [copylist componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *item in items) {
        NSString *trimmed = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) continue;

        NSString *srcPath = [resBundle.resourcePath stringByAppendingPathComponent:trimmed];
        NSString *dstPath = [workPath stringByAppendingPathComponent:trimmed];

        if ([fm fileExistsAtPath:dstPath]) continue;

        NSString *dstDir = [dstPath stringByDeletingLastPathComponent];
        [fm createDirectoryAtPath:dstDir withIntermediateDirectories:YES attributes:nil error:nil];
        [fm copyItemAtPath:srcPath toPath:dstPath error:nil];
    }
}

@end
