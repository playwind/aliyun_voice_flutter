import { NativeNui, Constants, NuiSdkTtsEvent, NuiTtsSdkListener } from 'neonui';
import { audio } from '@kit.AudioKit';
import { Uint8ArrayFIFOQueue, AudioRendererWrapper, IAudioRendererCallback } from './NuiAudioHelper';
import { ErrorResult, TaskIdData, ErrorWithTaskIdData, ErrorCodeData, createError, mergeEventData } from './types';

export type TtsEventSink = (event: Record<string, Object>) => void;

export class NuiTtsHandler implements NuiTtsSdkListener, IAudioRendererCallback {
  private nuiTts: NativeNui | undefined;
  private audioQueue: Uint8ArrayFIFOQueue;
  private audioRenderer: AudioRendererWrapper;
  private eventSink: TtsEventSink;
  private initialized: boolean = false;
  private context: Context;

  constructor(eventSink: TtsEventSink, context: Context) {
    this.eventSink = eventSink;
    this.context = context;
    this.audioQueue = new Uint8ArrayFIFOQueue();
    this.audioRenderer = new AudioRendererWrapper(this);
  }

  handleMethodCall(method: string, args: Record<string, Object>): Object | null {
    switch (method) {
      case 'tts_initialize':
        return this.handleInitialize(args);
      case 'tts_start':
        return this.handleStart(args);
      case 'tts_cancel':
        return this.handleCancel();
      case 'tts_pause':
        return this.handlePause();
      case 'tts_resume':
        return this.handleResume();
      case 'tts_release':
        return this.handleRelease();
      default:
        return null;
    }
  }

  private handleInitialize(args: Record<string, Object>): Object {
    const appKey = args['appKey'] as string;
    const token = args['token'] as string;
    if (!appKey || !token) {
      return createError('INVALID_PARAMS', 'appKey and token are required');
    }

    this.nuiTts = new NativeNui(Constants.ModeType.MODE_TTS, 'tts_flutter');
    const workspace = this.context.resourceDir + '/resources_cloud';
    const deviceId = 'flutter_ohos_device';

    const ticket = JSON.stringify({
      'app_key': appKey,
      'token': token,
      'url': 'wss://nls-gateway.cn-shanghai.aliyuncs.com/ws/v1',
      'device_id': deviceId,
      'mode_type': '2',
      'workspace': workspace
    });

    const ret = this.nuiTts.tts_initialize(this, ticket, 1, false);
    if (ret === 0) {
      this.initialized = true;
      return true;
    } else {
      return createError('TTS_INIT_FAILED', `tts_initialize returned ${ret}`);
    }
  }

  private handleStart(args: Record<string, Object>): Object {
    if (!this.initialized || !this.nuiTts) {
      return createError('NOT_INITIALIZED', 'TTS not initialized');
    }
    const text = args['text'] as string;
    const voice = (args['voice'] as string) || 'xiaoyun';
    const sampleRate = (args['sampleRate'] as number) || 16000;
    const speed = (args['speed'] as number) || 1.0;
    const volume = (args['volume'] as number) || 1.0;

    if (!text) {
      return createError('INVALID_PARAMS', 'text is required');
    }

    this.audioQueue.clear();
    this.audioRenderer = new AudioRendererWrapper(this);
    this.audioRenderer.create(sampleRate);

    this.nuiTts.setParamTts('font_name', voice);
    this.nuiTts.setParamTts('encode_type', 'pcm');
    this.nuiTts.setParamTts('sample_rate', String(sampleRate));
    this.nuiTts.setParamTts('speed_level', String(speed));
    this.nuiTts.setParamTts('volume', String(volume));

    const charNum = this.nuiTts.getUtf8CharsNum(text);
    this.nuiTts.setParamTts('tts_version', charNum > 300 ? '1' : '0');

    // Start renderer and TTS
    this.audioRenderer.start();
    this.nuiTts.startTts('1', '', text);
    return true;
  }

  private handleCancel(): Object {
    if (!this.nuiTts) {
      return createError('NOT_INITIALIZED', 'TTS not initialized');
    }
    this.audioRenderer.stop();
    this.audioQueue.clear();
    const ret = this.nuiTts.cancelTts('');
    return ret === 0 ? true : createError('TTS_CANCEL_FAILED', `cancelTts returned ${ret}`);
  }

  private handlePause(): Object {
    if (!this.nuiTts) {
      return createError('NOT_INITIALIZED', 'TTS not initialized');
    }
    this.audioRenderer.stop();
    const ret = this.nuiTts.pauseTts();
    return ret === 0 ? true : createError('TTS_PAUSE_FAILED', `pauseTts returned ${ret}`);
  }

  private handleResume(): Object {
    if (!this.nuiTts) {
      return createError('NOT_INITIALIZED', 'TTS not initialized');
    }
    this.audioRenderer.start();
    const ret = this.nuiTts.resumeTts();
    return ret === 0 ? true : createError('TTS_RESUME_FAILED', `resumeTts returned ${ret}`);
  }

  private handleRelease(): Object {
    if (!this.nuiTts) {
      return true;
    }
    this.audioRenderer.stop();
    this.audioRenderer.release();
    const ret = this.nuiTts.tts_release();
    this.initialized = false;
    return ret === 0 ? true : createError('TTS_RELEASE_FAILED', `tts_release returned ${ret}`);
  }

  // NuiTtsSdkListener
  onTtsEventCallback(event: NuiSdkTtsEvent, taskId: string, code: number): void {
    if (event === NuiSdkTtsEvent.TTS_EVENT_START) {
      const data: Record<string, Object> = {};
      data['taskId'] = taskId || '';
      this.sendEvent('ttsStart', data);
    } else if (event === NuiSdkTtsEvent.TTS_EVENT_END) {
      this.audioRenderer.setFinishSend(true);
      const data: Record<string, Object> = {};
      data['taskId'] = taskId || '';
      this.sendEvent('ttsEnd', data);
    } else if (event === NuiSdkTtsEvent.TTS_EVENT_CANCEL) {
      this.audioRenderer.stop();
      this.audioQueue.clear();
      this.sendEvent('ttsCancel', {});
    } else if (event === NuiSdkTtsEvent.TTS_EVENT_PAUSE) {
      this.sendEvent('ttsPause', {});
    } else if (event === NuiSdkTtsEvent.TTS_EVENT_RESUME) {
      this.sendEvent('ttsResume', {});
    } else if (event === NuiSdkTtsEvent.TTS_EVENT_ERROR) {
      const errMsg = this.nuiTts ? '' : 'TTS error';
      this.audioRenderer.stop();
      this.audioQueue.clear();
      const data: Record<string, Object> = {};
      data['code'] = code;
      data['message'] = errMsg;
      data['taskId'] = taskId || '';
      this.sendEvent('ttsError', data);
    }
  }

  onTtsDataCallback(info: string, infoLen: number, buffer: ArrayBuffer | null): void {
    if (buffer && buffer.byteLength > 0) {
      this.audioQueue.enqueue(new Uint8Array(buffer));
    }
  }

  onTtsVolCallback(vol: number): void {
    // not used
  }

  // IAudioRendererCallback
  onPlayerData(data: ArrayBuffer): audio.AudioDataCallbackResult {
    const chunk = this.audioQueue.dequeue(data.byteLength);
    if (chunk) {
      const target = new Uint8Array(data);
      target.set(chunk);
      return audio.AudioDataCallbackResult.VALID;
    } else {
      if (this.audioRenderer.checkFinish()) {
        this.audioRenderer.stop();
        this.audioRenderer.setFinishSend(false);
      }
      return audio.AudioDataCallbackResult.INVALID;
    }
  }

  onStateChanged(state: audio.AudioState): void {
    console.info(`TTS AudioRenderer state: ${state}`);
  }

  private sendEvent(type: string, data: Record<string, Object>) {
    const event = mergeEventData(type, data);
    this.eventSink(event);
  }
}
