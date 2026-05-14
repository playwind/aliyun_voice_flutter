import { FlutterEngine, MethodChannel, EventChannel, MethodCall, MethodResult, FlutterPlugin, FlutterPluginBinding, MethodCallHandler, AbilityAware, AbilityPluginBinding } from '@ohos/flutter_ohos';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { NuiTtsHandler, TtsEventSink } from './NuiTtsHandler';
import { NuiAsrHandler, AsrEventSink } from './NuiAsrHandler';

const ASR_METHOD = 'com.p1aywind.aliyun_voice/asr';
const ASR_EVENT = 'com.p1aywind.aliyun_voice/asr_events';
const TTS_METHOD = 'com.p1aywind.aliyun_voice/tts';
const TTS_EVENT = 'com.p1aywind.aliyun_voice/tts_events';

interface EventSink {
  success(data: Object): void;
}

interface ErrorResult {
  error: string;
  message: string;
}

function isErrorResult(obj: Object): boolean {
  try {
    const record = obj as Record<string, Object>;
    return record['error'] !== undefined && record['message'] !== undefined;
  } catch {
    return false;
  }
}

export default class AliyunVoicePlugin implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private asrHandler: NuiAsrHandler | undefined;
  private ttsHandler: NuiTtsHandler | undefined;
  private asrEventSink: AsrEventSink | undefined;
  private ttsEventSink: TtsEventSink | undefined;
  private asrMethodChannel: MethodChannel | undefined;
  private ttsMethodChannel: MethodChannel | undefined;
  private asrEventChannel: EventChannel | undefined;
  private ttsEventChannel: EventChannel | undefined;
  private abilityContext: common.UIAbilityContext | undefined;

  getUniqueClassName(): string {
    return 'AliyunVoicePlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    const messenger = binding.getBinaryMessenger();

    this.asrMethodChannel = new MethodChannel(messenger, ASR_METHOD);
    this.asrMethodChannel.setMethodCallHandler(this);

    this.ttsMethodChannel = new MethodChannel(messenger, TTS_METHOD);
    this.ttsMethodChannel.setMethodCallHandler(this);

    this.asrEventChannel = new EventChannel(messenger, ASR_EVENT);
    this.asrEventChannel.setStreamHandler({
      onListen: (args: Object, sink: Object) => {
        this.asrEventSink = (event: Record<string, Object>) => {
          (sink as EventSink).success(event);
        };
      },
      onCancel: (args: Object) => {
        this.asrEventSink = undefined;
      }
    });

    this.ttsEventChannel = new EventChannel(messenger, TTS_EVENT);
    this.ttsEventChannel.setStreamHandler({
      onListen: (args: Object, sink: Object) => {
        this.ttsEventSink = (event: Record<string, Object>) => {
          (sink as EventSink).success(event);
        };
      },
      onCancel: (args: Object) => {
        this.ttsEventSink = undefined;
      }
    });
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.asrMethodChannel?.setMethodCallHandler(null);
    this.ttsMethodChannel?.setMethodCallHandler(null);
    this.asrMethodChannel = undefined;
    this.ttsMethodChannel = undefined;
    this.asrEventChannel = undefined;
    this.ttsEventChannel = undefined;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.abilityContext = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {
    this.abilityContext = undefined;
  }

  private extractArgs(call: MethodCall, keys: string[]): Record<string, Object> {
    const args: Record<string, Object> = {};
    for (const key of keys) {
      const val: Object | null = call.argument(key) as Object | null;
      if (val !== null && val !== undefined) {
        args[key] = val;
      }
    }
    return args;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    const ctx = this.abilityContext;
    if (!ctx) {
      result.error('NO_CONTEXT', 'UIAbilityContext not available', null);
      return;
    }

    if (call.method.startsWith('asr_')) {
      if (!this.asrHandler) {
        this.asrHandler = new NuiAsrHandler(
          (event) => { if (this.asrEventSink) this.asrEventSink(event); },
          ctx
        );
      }
      const asrArgKeys = ['appKey', 'token', 'enableVad', 'maxStartSilence', 'maxEndSilence'];
      const args = this.extractArgs(call, asrArgKeys);
      const ret = this.asrHandler?.handleMethodCall(call.method, args);
      if (ret === null || ret === undefined) {
        result.notImplemented();
      } else if (ret instanceof Object && isErrorResult(ret)) {
        const err = ret as Record<string, Object>;
        result.error(err['error'] as string, err['message'] as string, null);
      } else {
        result.success(ret);
      }
    } else if (call.method.startsWith('tts_')) {
      if (!this.ttsHandler) {
        this.ttsHandler = new NuiTtsHandler(
          (event) => { if (this.ttsEventSink) this.ttsEventSink(event); },
          ctx
        );
      }
      const ttsArgKeys = ['appKey', 'token', 'text', 'voice', 'sampleRate', 'speed', 'volume'];
      const args = this.extractArgs(call, ttsArgKeys);
      const ret = this.ttsHandler?.handleMethodCall(call.method, args);
      if (ret === null || ret === undefined) {
        result.notImplemented();
      } else if (ret instanceof Object && isErrorResult(ret)) {
        const err = ret as Record<string, Object>;
        result.error(err['error'] as string, err['message'] as string, null);
      } else {
        result.success(ret);
      }
    } else {
      result.notImplemented();
    }
  }
}
