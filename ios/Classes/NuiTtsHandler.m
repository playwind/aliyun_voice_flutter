#import "NuiTtsHandler.h"
#import <nuisdk/NeoNuiTts.h>
#import <nuisdk/NeoNuiCode.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

#pragma mark - Audio Player (AudioUnit-based, following Aliyun demo pattern)

typedef enum {
    PLAYER_STATE_IDLE = 0,
    PLAYER_STATE_INIT,
    PLAYER_STATE_PLAYING,
    PLAYER_STATE_STOPPED,
    PLAYER_STATE_DRAINING,
} AudioPlayerState;

@interface NuiAudioPlayer : NSObject {
    AudioUnit _playUnit;
    NSMutableData *_buffer;
    int _writeOffset;
    int _readOffset;
    int _dataSize;
    int _capacity;
    AudioPlayerState _state;
    AudioStreamBasicDescription _format;
}
@property (nonatomic, assign) BOOL draining;
@end

@implementation NuiAudioPlayer

- (instancetype)init {
    self = [super init];
    if (self) {
        _capacity = 1024 * 1024; // 1MB ring buffer
        _buffer = [NSMutableData dataWithLength:_capacity];
        _writeOffset = 0;
        _readOffset = 0;
        _dataSize = 0;
        _state = PLAYER_STATE_IDLE;
        _draining = NO;
    }
    return self;
}

- (BOOL)createWithSampleRate:(int)sampleRate {
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if (![session setCategory:AVAudioSessionCategoryPlayback
                      mode:AVAudioSessionModeDefault
                   options:AVAudioSessionCategoryOptionMixWithOthers
                     error:&error]) {
        NSLog(@"TTSPlayer: set AVAudioSession category failed: %@", error);
        return NO;
    }
    if (![session setActive:YES error:&error]) {
        NSLog(@"TTSPlayer: activate AVAudioSession failed: %@", error);
        return NO;
    }

    memset(&_format, 0, sizeof(_format));
    _format.mSampleRate = sampleRate;
    _format.mFormatID = kAudioFormatLinearPCM;
    _format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    _format.mBytesPerPacket = 2;
    _format.mFramesPerPacket = 1;
    _format.mBytesPerFrame = 2;
    _format.mChannelsPerFrame = 1;
    _format.mBitsPerChannel = 16;

    AudioComponentDescription desc;
    memset(&desc, 0, sizeof(desc));
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;

    AudioComponent comp = AudioComponentFindNext(NULL, &desc);
    OSStatus status = AudioComponentInstanceNew(comp, &_playUnit);
    if (status != noErr) {
        NSLog(@"TTSPlayer: AudioComponentInstanceNew failed: %d", (int)status);
        return NO;
    }

    status = AudioUnitSetProperty(_playUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  0,
                                  &_format,
                                  sizeof(_format));
    if (status != noErr) {
        NSLog(@"TTSPlayer: set StreamFormat failed: %d", (int)status);
        return NO;
    }

    UInt32 playFlag = 1;
    AudioUnitSetProperty(_playUnit,
                         kAudioOutputUnitProperty_EnableIO,
                         kAudioUnitScope_Output,
                         0,
                         &playFlag,
                         sizeof(playFlag));

    AURenderCallbackStruct callback;
    callback.inputProc = PlayCallback;
    callback.inputProcRefCon = (__bridge void *)self;
    status = AudioUnitSetProperty(_playUnit,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Global,
                                  0,
                                  &callback,
                                  sizeof(callback));
    if (status != noErr) {
        NSLog(@"TTSPlayer: set RenderCallback failed: %d", (int)status);
        return NO;
    }

    status = AudioUnitInitialize(_playUnit);
    if (status != noErr) {
        NSLog(@"TTSPlayer: AudioUnitInitialize failed: %d", (int)status);
        return NO;
    }

    _state = PLAYER_STATE_INIT;
    NSLog(@"TTSPlayer: created with sampleRate=%d", sampleRate);
    return YES;
}

static OSStatus PlayCallback(void *inRefCon,
                             AudioUnitRenderActionFlags *ioActionFlags,
                             const AudioTimeStamp *inTimeStamp,
                             UInt32 inBusNumber,
                             UInt32 inNumberFrames,
                             AudioBufferList *ioData) {
    NuiAudioPlayer *player = (__bridge NuiAudioPlayer *)inRefCon;
    UInt32 requestedBytes = ioData->mBuffers[0].mDataByteSize;
    char *output = (char *)ioData->mBuffers[0].mData;

    @synchronized (player) {
        int available = [player availableBytes];
        if (available > 0) {
            int toRead = (int)requestedBytes < available ? (int)requestedBytes : available;
            [player readBytes:output length:toRead];
            if (toRead < (int)requestedBytes) {
                memset(output + toRead, 0, requestedBytes - toRead);
            }
        } else {
            memset(output, 0, requestedBytes);
            if (player.draining && player->_state == PLAYER_STATE_DRAINING) {
                player->_state = PLAYER_STATE_STOPPED;
                dispatch_async(dispatch_get_main_queue(), ^{
                    AudioOutputUnitStop(player->_playUnit);
                });
            }
        }
    }
    return noErr;
}

- (void)start {
    if (_state == PLAYER_STATE_PLAYING) return;
    _state = PLAYER_STATE_PLAYING;
    _draining = NO;
    _writeOffset = 0;
    _readOffset = 0;
    _dataSize = 0;
    OSStatus status = AudioOutputUnitStart(_playUnit);
    if (status != noErr) {
        NSLog(@"TTSPlayer: AudioOutputUnitStart failed: %d", (int)status);
    } else {
        NSLog(@"TTSPlayer: started");
    }
}

- (void)writeData:(const char *)data length:(int)len {
    @synchronized (self) {
        int remaining = _capacity - _dataSize;
        if (len > remaining) {
            NSLog(@"TTSPlayer: buffer overflow, dropping %d bytes", len - remaining);
            len = remaining;
        }
        if (len <= 0) return;

        // Wrap-around write to circular buffer
        char *buf = (char *)_buffer.mutableBytes;
        int firstWrite = _writeOffset + len <= _capacity ? len : _capacity - _writeOffset;
        memcpy(buf + _writeOffset, data, firstWrite);
        if (firstWrite < len) {
            memcpy(buf, data + firstWrite, len - firstWrite);
        }
        _writeOffset = (_writeOffset + len) % _capacity;
        _dataSize += len;
    }
}

- (int)readBytes:(char *)out length:(int)len {
    int toRead = _dataSize < len ? _dataSize : len;
    if (toRead <= 0) return 0;

    char *buf = (char *)_buffer.mutableBytes;
    int firstRead = _readOffset + toRead <= _capacity ? toRead : _capacity - _readOffset;
    memcpy(out, buf + _readOffset, firstRead);
    if (firstRead < toRead) {
        memcpy(out + firstRead, buf, toRead - firstRead);
    }
    _readOffset = (_readOffset + toRead) % _capacity;
    _dataSize -= toRead;
    return toRead;
}

- (int)availableBytes {
    return _dataSize;
}

- (void)drain {
    @synchronized (self) {
        _draining = YES;
        if (_dataSize == 0) {
            _state = PLAYER_STATE_STOPPED;
            dispatch_async(dispatch_get_main_queue(), ^{
                AudioOutputUnitStop(self->_playUnit);
            });
        } else {
            _state = PLAYER_STATE_DRAINING;
        }
    }
    NSLog(@"TTSPlayer: draining, remaining=%d bytes", _dataSize);
}

- (void)stop {
    @synchronized (self) {
        _state = PLAYER_STATE_STOPPED;
        _draining = NO;
        _dataSize = 0;
        _writeOffset = 0;
        _readOffset = 0;
    }
    AudioOutputUnitStop(_playUnit);
    NSLog(@"TTSPlayer: stopped");
}

- (void)pausePlayback {
    if (_state == PLAYER_STATE_PLAYING || _state == PLAYER_STATE_DRAINING) {
        AudioOutputUnitStop(_playUnit);
    }
}

- (void)resumePlayback {
    if (_state == PLAYER_STATE_PLAYING || _state == PLAYER_STATE_DRAINING) {
        AudioOutputUnitStart(_playUnit);
    }
}

- (void)releasePlayer {
    [self stop];
    if (_playUnit) {
        AudioOutputUnitStop(_playUnit);
        AudioUnitUninitialize(_playUnit);
        AudioComponentInstanceDispose(_playUnit);
        _playUnit = NULL;
    }
    _state = PLAYER_STATE_IDLE;
    NSLog(@"TTSPlayer: released");
}

- (void)dealloc {
    [self releasePlayer];
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
    [self copySDKResources:workPath];

    NSString *params = [NSString stringWithFormat:
        @"{\"app_key\":\"%@\",\"token\":\"%@\",\"device_id\":\"%@\","
        "\"url\":\"wss://nls-gateway.cn-shanghai.aliyuncs.com:443/ws/v1\","
        "\"workspace\":\"%@\",\"mode_type\":\"2\",\"service_protocol\":\"0\"}",
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

    [_audioPlayer releasePlayer];
    _audioPlayer = [[NuiAudioPlayer alloc] init];
    if (![_audioPlayer createWithSampleRate:sampleRate]) {
        result([FlutterError errorWithCode:@"TTS_PLAYER_ERROR" message:@"Failed to create audio player" details:nil]);
        return;
    }

    [_nuiTts nui_tts_set_param:"font_name" value:[voice UTF8String]];
    [_nuiTts nui_tts_set_param:"sample_rate" value:[[NSString stringWithFormat:@"%d", sampleRate] UTF8String]];
    [_nuiTts nui_tts_set_param:"speed_level" value:[[NSString stringWithFormat:@"%f", speed] UTF8String]];
    [_nuiTts nui_tts_set_param:"volume" value:[[NSString stringWithFormat:@"%f", volume] UTF8String]];
    // KEY FIX: play_audio=0 means SDK returns PCM data via callback, we handle playback ourselves
    [_nuiTts nui_tts_set_param:"play_audio" value:"0"];

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
    [_audioPlayer stop];
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
            // Start player when TTS stream begins (matching demo pattern)
            [_audioPlayer start];
            [self sendEvent:@"ttsStart" data:@{@"taskId": taskid ? @(taskid) : @""}];
            break;
        case TTS_EVENT_END:
            // Drain: let remaining buffered audio finish playing
            [_audioPlayer drain];
            [self sendEvent:@"ttsEnd" data:@{@"taskId": taskid ? @(taskid) : @""}];
            break;
        case TTS_EVENT_CANCEL:
            [_audioPlayer stop];
            [self sendEvent:@"ttsCancel" data:nil];
            break;
        case TTS_EVENT_PAUSE:
            [_audioPlayer pausePlayback];
            [self sendEvent:@"ttsPause" data:nil];
            break;
        case TTS_EVENT_RESUME:
            [_audioPlayer resumePlayback];
            [self sendEvent:@"ttsResume" data:nil];
            break;
        case TTS_EVENT_ERROR: {
            const char *errMsg = [_nuiTts nui_tts_get_param:"error_msg"];
            [_audioPlayer stop];
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
        [_audioPlayer writeData:buffer length:len];
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

- (void)copySDKResources:(NSString *)workPath {
    NSBundle *sdkBundle = [NSBundle bundleForClass:[NeoNuiTts class]];
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
