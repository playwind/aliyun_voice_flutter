#import "NuiTtsHandler.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

#pragma mark - Audio Player

@interface NuiAudioPlayer : NSObject
@property (nonatomic, assign) AudioQueueRef queue;
@property (nonatomic, strong) NSMutableArray<NSData *> *audioQueue;
@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, assign) BOOL finishSending;
@end

@implementation NuiAudioPlayer

- (instancetype)init {
    self = [super init];
    if (self) {
        _audioQueue = [NSMutableArray array];
        _isPlaying = NO;
        _finishSending = NO;
    }
    return self;
}

- (BOOL)createWithSampleRate:(int)sampleRate {
    AudioStreamBasicDescription format = {0};
    format.mSampleRate = sampleRate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    format.mBytesPerPacket = 2;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = 2;
    format.mChannelsPerFrame = 1;
    format.mBitsPerChannel = 16;

    OSStatus status = AudioQueueNewOutput(&format, AudioOutputCallback, (__bridge void *)self, NULL, NULL, 0, &_queue);
    if (status != noErr) return NO;

    for (int i = 0; i < 3; i++) {
        AudioQueueBufferRef buffer;
        AudioQueueAllocateBuffer(_queue, 8192, &buffer);
        buffer->mAudioDataByteSize = 0;
        AudioQueueEnqueueBuffer(_queue, buffer, 0, NULL);
    }
    return YES;
}

static void AudioOutputCallback(void *inUserData,
                                AudioQueueRef inAQ,
                                AudioQueueBufferRef inBuffer) {
    NuiAudioPlayer *player = (__bridge NuiAudioPlayer *)inUserData;

    @synchronized (player.audioQueue) {
        if (player.audioQueue.count > 0) {
            NSData *data = player.audioQueue.firstObject;
            NSUInteger copyLen = MIN(data.length, inBuffer->mAudioDataBytesCapacity);
            memcpy(inBuffer->mAudioData, data.bytes, copyLen);
            inBuffer->mAudioDataByteSize = (UInt32)copyLen;

            if (copyLen < data.length) {
                [player.audioQueue replaceObjectAtIndex:0 withObject:[data subdataWithRange:NSMakeRange(copyLen, data.length - copyLen)]];
            } else {
                [player.audioQueue removeObjectAtIndex:0];
            }
            AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
        } else if (player.finishSending) {
            player.isPlaying = NO;
        } else {
            inBuffer->mAudioDataByteSize = 0;
            AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
        }
    }
}

- (void)play {
    if (_isPlaying) return;
    _isPlaying = YES;
    _finishSending = NO;
    AudioQueueStart(_queue, NULL);
}

- (void)enqueueData:(NSData *)data {
    @synchronized (_audioQueue) {
        [_audioQueue addObject:data];
    }
}

- (void)setFinish:(BOOL)finish {
    _finishSending = finish;
}

- (void)stop {
    _isPlaying = NO;
    _finishSending = YES;
    @synchronized (_audioQueue) {
        [_audioQueue removeAllObjects];
    }
}

- (void)pausePlayback {
    if (_queue) AudioQueuePause(_queue);
}

- (void)resumePlayback {
    if (_queue) AudioQueueStart(_queue, NULL);
}

- (void)releasePlayer {
    [self stop];
    if (_queue) {
        AudioQueueDispose(_queue, YES);
        _queue = NULL;
    }
}

@end

#pragma mark - NuiTtsHandler

@interface NuiTtsHandler ()
@property (nonatomic, strong) NeoNuiTts *nuiTts;
@property (nonatomic, strong) NuiAudioPlayer *audioPlayer;
@property (nonatomic, assign) BOOL initialized;
@end

@implementation NuiTtsHandler

- (instancetype)initWithEventSink:(FlutterEventSink)eventSink {
    self = [super init];
    if (self) {
        _eventSink = eventSink;
        _nuiTts = [[NeoNuiTts alloc] init];
        _nuiTts.delegate = self;
        _audioPlayer = [[NuiAudioPlayer alloc] init];
        _initialized = NO;
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([call.method isEqualToString:@"tts_initialize"]) {
        [self handleInitialize:call result:result];
    } else if ([call.method isEqualToString:@"tts_start"]) {
        [self handleStart:call result:result];
    } else if ([call.method isEqualToString:@"tts_cancel"]) {
        [self handleCancel:result];
    } else if ([call.method isEqualToString:@"tts_pause"]) {
        [self handlePause:result];
    } else if ([call.method isEqualToString:@"tts_resume"]) {
        [self handleResume:result];
    } else if ([call.method isEqualToString:@"tts_release"]) {
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
    workPath = [workPath stringByAppendingPathComponent:@"nui_tts_workspace"];

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:workPath withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *params = [NSString stringWithFormat:
        @"{\"app_key\":\"%@\",\"token\":\"%@\",\"device_id\":\"%@\","
        "\"url\":\"wss://nls-gateway.cn-shanghai.aliyuncs.com:443/ws/v1\","
        "\"workspace\":\"%@\",\"mode_type\":2}",
        appKey, token, deviceId, workPath];

    int ret = [_nuiTts nui_tts_initialize:[params UTF8String]
                                  logLevel:NUI_LOG_LEVEL_VERBOSE
                                   saveLog:YES];
    if (ret == 0) {
        _initialized = YES;
        result(@(YES));
    } else {
        result([FlutterError errorWithCode:@"TTS_INIT_FAILED"
                                   message:[NSString stringWithFormat:@"tts_initialize returned %d", ret]
                                   details:nil]);
    }
}

- (void)handleStart:(FlutterMethodCall *)call result:(FlutterResult)result {
    if (!_initialized) {
        result([FlutterError errorWithCode:@"NOT_INITIALIZED" message:@"TTS not initialized" details:nil]);
        return;
    }

    NSString *text = call.arguments[@"text"];
    NSString *voice = call.arguments[@"voice"] ?: @"xiaoyun";
    int sampleRate = [call.arguments[@"sampleRate"] intValue] ?: 16000;
    float speed = [call.arguments[@"speed"] floatValue] ?: 1.0;
    float volume = [call.arguments[@"volume"] floatValue] ?: 1.0;

    if (!text.length) {
        result([FlutterError errorWithCode:@"INVALID_PARAMS" message:@"text is required" details:nil]);
        return;
    }

    _audioPlayer = [[NuiAudioPlayer alloc] init];
    if (![_audioPlayer createWithSampleRate:sampleRate]) {
        result([FlutterError errorWithCode:@"TTS_PLAYER_ERROR" message:@"Failed to create audio player" details:nil]);
        return;
    }

    [_nuiTts nui_tts_set_param:"font_name" value:[voice UTF8String]];
    [_nuiTts nui_tts_set_param:"sample_rate" value:[[NSString stringWithFormat:@"%d", sampleRate] UTF8String]];
    [_nuiTts nui_tts_set_param:"speed_level" value:[[NSString stringWithFormat:@"%f", speed] UTF8String]];
    [_nuiTts nui_tts_set_param:"volume" value:[[NSString stringWithFormat:@"%f", volume] UTF8String]];

    int charNum = [_nuiTts nui_tts_get_num_of_chars:[text UTF8String]];
    [_nuiTts nui_tts_set_param:"tts_version" value:charNum > 300 ? "1" : "0"];

    int ret = [_nuiTts nui_tts_play:"1" taskId:"" text:[text UTF8String]];
    if (ret == 0) result(@(YES));
    else result([FlutterError errorWithCode:@"TTS_START_FAILED"
                                     message:[NSString stringWithFormat:@"startTts returned %d", ret]
                                     details:nil]);
}

- (void)handleCancel:(FlutterResult)result {
    if (!_initialized) {
        result([FlutterError errorWithCode:@"NOT_INITIALIZED" message:@"TTS not initialized" details:nil]);
        return;
    }
    [_audioPlayer releasePlayer];
    int ret = [_nuiTts nui_tts_cancel:""];
    if (ret == 0) result(@(YES));
    else result([FlutterError errorWithCode:@"TTS_CANCEL_FAILED"
                                     message:[NSString stringWithFormat:@"cancelTts returned %d", ret]
                                     details:nil]);
}

- (void)handlePause:(FlutterResult)result {
    if (!_initialized) {
        result([FlutterError errorWithCode:@"NOT_INITIALIZED" message:@"TTS not initialized" details:nil]);
        return;
    }
    [_audioPlayer pausePlayback];
    int ret = [_nuiTts nui_tts_pause];
    if (ret == 0) result(@(YES));
    else result([FlutterError errorWithCode:@"TTS_PAUSE_FAILED"
                                     message:[NSString stringWithFormat:@"pauseTts returned %d", ret]
                                     details:nil]);
}

- (void)handleResume:(FlutterResult)result {
    if (!_initialized) {
        result([FlutterError errorWithCode:@"NOT_INITIALIZED" message:@"TTS not initialized" details:nil]);
        return;
    }
    [_audioPlayer resumePlayback];
    int ret = [_nuiTts nui_tts_resume];
    if (ret == 0) result(@(YES));
    else result([FlutterError errorWithCode:@"TTS_RESUME_FAILED"
                                     message:[NSString stringWithFormat:@"resumeTts returned %d", ret]
                                     details:nil]);
}

- (void)handleRelease:(FlutterResult)result {
    if (!_initialized) {
        result(@(YES));
        return;
    }
    [_audioPlayer releasePlayer];
    int ret = [_nuiTts nui_tts_release];
    _initialized = NO;
    if (ret == 0) result(@(YES));
    else result([FlutterError errorWithCode:@"TTS_RELEASE_FAILED"
                                     message:[NSString stringWithFormat:@"tts_release returned %d", ret]
                                     details:nil]);
}

#pragma mark - NeoNuiTtsDelegate

- (void)onNuiTtsEventCallback:(NuiSdkTtsEvent)event taskId:(char *)taskid code:(int)code {
    switch (event) {
        case TTS_EVENT_START:
            [_audioPlayer play];
            [self sendEvent:@"ttsStart" data:@{@"taskId": taskid ? @(taskid) : @""}];
            break;
        case TTS_EVENT_END:
            [_audioPlayer setFinish:YES];
            [self sendEvent:@"ttsEnd" data:@{@"taskId": taskid ? @(taskid) : @""}];
            break;
        case TTS_EVENT_CANCEL:
            [_audioPlayer releasePlayer];
            [self sendEvent:@"ttsCancel" data:nil];
            break;
        case TTS_EVENT_PAUSE:
            [self sendEvent:@"ttsPause" data:nil];
            break;
        case TTS_EVENT_RESUME:
            [self sendEvent:@"ttsResume" data:nil];
            break;
        case TTS_EVENT_ERROR: {
            const char *errMsg = [_nuiTts nui_tts_get_param:"error_msg"];
            [_audioPlayer releasePlayer];
            [self sendEvent:@"ttsError" data:@{
                @"code": @(code),
                @"message": errMsg ? @(errMsg) : @"TTS error",
                @"taskId": taskid ? @(taskid) : @""
            }];
            break;
        }
        default:
            break;
    }
}

- (void)onNuiTtsUserdataCallback:(char *)info infoLen:(int)info_len buffer:(char *)buffer len:(int)len taskId:(char *)task_id {
    if (buffer && len > 0) {
        [_audioPlayer enqueueData:[NSData dataWithBytes:buffer length:len]];
    }
}

- (void)onNuiTtsVolumeCallback:(int)volume taskId:(char *)task_id {
    // not used
}

#pragma mark - Helpers

- (void)sendEvent:(NSString *)type data:(NSDictionary *)data {
    NSMutableDictionary *event = [NSMutableDictionary dictionaryWithObject:type forKey:@"type"];
    if (data) [event addEntriesFromDictionary:data];
    if (_eventSink) _eventSink(event);
}

@end
