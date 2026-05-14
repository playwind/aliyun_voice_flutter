import { NativeNui, Constants, INativeNuiCallback, KwsResult, AsrResult } from 'neonui';
import { Uint8ArrayFIFOQueue, AudioCapturerWrapper, IAudioCapturerCallback } from './NuiAudioHelper';
import { ErrorResult, TextData, ErrorCodeData, ValueData, createError, mergeEventData } from './types';

export type AsrEventSink = (event: Record<string, Object>) => void;

export class NuiAsrHandler implements INativeNuiCallback, IAudioCapturerCallback {
  private nui: NativeNui | undefined;
  private audioQueue: Uint8ArrayFIFOQueue;
  private audioCapturer: AudioCapturerWrapper;
  private eventSink: AsrEventSink;
  private initialized: boolean = false;
  private context: Context;

  constructor(eventSink: AsrEventSink, context: Context) {
    this.eventSink = eventSink;
    this.context = context;
    this.audioQueue = new Uint8ArrayFIFOQueue();
    this.audioCapturer = new AudioCapturerWrapper(this);
  }

  handleMethodCall(method: string, args: Record<string, Object>): Object | null {
    switch (method) {
      case 'asr_initialize':
        return this.handleInitialize(args);
      case 'asr_startDialog':
        return this.handleStartDialog(args);
      case 'asr_stopDialog':
        return this.handleStopDialog();
      case 'asr_cancelDialog':
        return this.handleCancelDialog();
      case 'asr_release':
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

    this.nui = new NativeNui(Constants.ModeType.MODE_DIALOG, 'asr_flutter');
    const workspace = this.context.resourceDir + '/resources_cloud';
    const deviceId = 'flutter_ohos_device';

    const ticket = JSON.stringify({
      'app_key': appKey,
      'token': token,
      'url': 'wss://nls-gateway.cn-shanghai.aliyuncs.com/ws/v1',
      'device_id': deviceId,
      'workspace': workspace,
      'service_mode': 4,
      'audio_update_manually': 'false'
    });

    const ret = this.nui.initialize(this, ticket, 1, false);
    if (ret === 0) {
      this.initialized = true;
      return true;
    } else {
      return createError('ASR_INIT_FAILED', `initialize returned ${ret}`);
    }
  }

  private handleStartDialog(args: Record<string, Object>): Object {
    if (!this.initialized || !this.nui) {
      return createError('NOT_INITIALIZED', 'ASR not initialized');
    }

    const enableVad = (args['enableVad'] as boolean) || false;
    const maxStartSilence = (args['maxStartSilence'] as number) || 10000;
    const maxEndSilence = (args['maxEndSilence'] as number) || 800;

    const nlsConfig: Record<string, Object> = {
      'enable_intermediate_result': true,
      'enable_punctuation_prediction': true,
      'enable_inverse_text_normalization': true
    };
    if (enableVad) {
      nlsConfig['enable_voice_detection'] = true;
      nlsConfig['max_start_silence'] = maxStartSilence;
      nlsConfig['max_end_silence'] = maxEndSilence;
    }

    const nuiConfig: Record<string, Object> = {
      'enable_recorder_by_user': true,
      'enable_callback_recording': false
    };
    const params = JSON.stringify({
      'nui_config': nuiConfig,
      'nls_config': nlsConfig,
      'service_type': 0
    });

    this.audioQueue.clear();
    this.nui.setParams(params);
    const ret = this.nui.startDialog(Constants.VadMode.TYPE_P2T, '{}');
    return ret === 0 ? true : createError('ASR_START_FAILED', `startDialog returned ${ret}`);
  }

  private handleStopDialog(): Object {
    if (!this.nui) {
      return createError('NOT_INITIALIZED', 'ASR not initialized');
    }
    const ret = this.nui.stopDialog();
    return ret === 0 ? true : createError('ASR_STOP_FAILED', `stopDialog returned ${ret}`);
  }

  private handleCancelDialog(): Object {
    if (!this.nui) {
      return createError('NOT_INITIALIZED', 'ASR not initialized');
    }
    const ret = this.nui.cancelDialog();
    return ret === 0 ? true : createError('ASR_CANCEL_FAILED', `cancelDialog returned ${ret}`);
  }

  private handleRelease(): Object {
    if (!this.nui) {
      return true;
    }
    this.audioCapturer.stop();
    this.audioCapturer.release();
    const ret = this.nui.release();
    this.initialized = false;
    return ret === 0 ? true : createError('ASR_RELEASE_FAILED', `release returned ${ret}`);
  }

  // INativeNuiCallback
  onNuiEventCallback(event: Constants.NuiEvent, resultCode: number, arg2: number,
    kwsResult: KwsResult, asrResult: AsrResult): void {
    if (event === Constants.NuiEvent.EVENT_VAD_START) {
      this.sendEvent('vadStart', {});
    } else if (event === Constants.NuiEvent.EVENT_VAD_END) {
      this.sendEvent('vadEnd', {});
    } else if (event === Constants.NuiEvent.EVENT_ASR_PARTIAL_RESULT) {
      const text = this.extractAsrText(asrResult);
      const data: Record<string, Object> = {};
      data['text'] = text;
      this.sendEvent('partialResult', data);
    } else if (event === Constants.NuiEvent.EVENT_ASR_RESULT) {
      const text = this.extractAsrText(asrResult);
      const data: Record<string, Object> = {};
      data['text'] = text;
      this.sendEvent('finalResult', data);
    } else if (event === Constants.NuiEvent.EVENT_ASR_ERROR) {
      const msg = asrResult ? asrResult.asrResult : 'ASR error';
      const data: Record<string, Object> = {};
      data['code'] = resultCode;
      data['message'] = msg || 'ASR error';
      this.sendEvent('error', data);
    } else if (event === Constants.NuiEvent.EVENT_MIC_ERROR) {
      this.sendEvent('micError', {});
    }
  }

  onNuiNeedAudioData(buffer: ArrayBuffer): number {
    const chunk = this.audioQueue.dequeue(buffer.byteLength);
    if (chunk) {
      const target = new Uint8Array(buffer);
      target.set(chunk);
      return chunk.byteLength;
    }
    return 0;
  }

  onNuiAudioStateChanged(state: Constants.AudioState): void {
    if (state === Constants.AudioState.STATE_OPEN) {
      this.audioCapturer.create();
      this.audioCapturer.start();
    } else if (state === Constants.AudioState.STATE_CLOSE) {
      this.audioCapturer.stop();
      this.audioCapturer.release();
    } else if (state === Constants.AudioState.STATE_PAUSE) {
      this.audioCapturer.stop();
    }
  }

  onNuiAudioRMSChanged(val: number): number {
    const data: Record<string, Object> = {};
    data['value'] = val;
    this.sendEvent('audioRms', data);
    return 0;
  }

  onNuiLogTrackCallback(level: Constants.LogLevel, log: string): void {
    // not used
  }

  // IAudioCapturerCallback
  onRecorderData(buffer: ArrayBuffer): void {
    this.audioQueue.enqueue(new Uint8Array(buffer));
  }

  onStateChanged(state: number): void {
    console.info(`ASR AudioCapturer state: ${state}`);
  }

  private extractAsrText(asrResult: AsrResult | undefined): string {
    if (!asrResult || !asrResult.asrResult) return '';
    try {
      const json = JSON.parse(asrResult.asrResult) as Record<string, Object>;
      const payload = json['payload'] as Record<string, Object>;
      return payload ? (payload['result'] as string) || '' : '';
    } catch (e) {
      return asrResult.asrResult || '';
    }
  }

  private sendEvent(type: string, data: Record<string, Object>) {
    const event = mergeEventData(type, data);
    this.eventSink(event);
  }
}
