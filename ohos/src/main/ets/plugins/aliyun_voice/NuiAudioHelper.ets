import { audio } from '@kit.AudioKit';

// FIFO queue for PCM audio data (from demo Common.ets)
export class Uint8ArrayFIFOQueue {
  private queue: Uint8Array[] = [];
  private totalLength: number = 0;

  enqueue(data: Uint8Array) {
    this.queue.push(data);
    this.totalLength += data.length;
  }

  dequeue(length: number): Uint8Array | undefined {
    if (length <= 0 || this.totalLength === 0) {
      return undefined;
    }
    if (length >= this.totalLength) {
      const result = new Uint8Array(this.totalLength);
      let offset = 0;
      for (const chunk of this.queue) {
        result.set(chunk, offset);
        offset += chunk.length;
      }
      this.clear();
      return result;
    }
    const result = new Uint8Array(length);
    let bytesRead = 0;
    while (bytesRead < length && this.queue.length > 0) {
      const chunk = this.queue[0];
      const bytesToCopy = Math.min(chunk.length, length - bytesRead);
      result.set(chunk.subarray(0, bytesToCopy), bytesRead);
      bytesRead += bytesToCopy;
      if (bytesToCopy < chunk.length) {
        this.queue[0] = chunk.subarray(bytesToCopy);
      } else {
        this.queue.shift();
      }
    }
    this.totalLength -= bytesRead;
    return result;
  }

  getTotalLength(): number {
    return this.totalLength;
  }

  clear() {
    this.queue = [];
    this.totalLength = 0;
  }
}

// AudioRenderer callback interface
export interface IAudioRendererCallback {
  onPlayerData(data: ArrayBuffer): audio.AudioDataCallbackResult;
  onStateChanged(state: audio.AudioState): void;
}

// AudioCapturer callback interface
export interface IAudioCapturerCallback {
  onRecorderData(buffer: ArrayBuffer): void;
  onStateChanged(state: audio.AudioState): void;
}

// AudioRenderer wrapper for TTS playback
export class AudioRendererWrapper {
  private renderer: audio.AudioRenderer | undefined;
  private callback: IAudioRendererCallback;
  private finishSend: boolean = false;
  private pendingStart: boolean = false;

  constructor(callback: IAudioRendererCallback) {
    this.callback = callback;
  }

  create(sampleRate: number): boolean {
    const streamInfo: audio.AudioStreamInfo = {
      samplingRate: sampleRate as audio.AudioSamplingRate,
      channels: audio.AudioChannel.CHANNEL_1,
      sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
      encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
    };
    const rendererInfo: audio.AudioRendererInfo = {
      usage: audio.StreamUsage.STREAM_USAGE_VOICE_ASSISTANT,
      rendererFlags: 0
    };
    const options: audio.AudioRendererOptions = {
      streamInfo: streamInfo,
      rendererInfo: rendererInfo
    };
    try {
      audio.createAudioRenderer(options, (err, data) => {
        if (err) {
          console.error(`AudioRenderer Created Error: ${err}`);
          return;
        }
        this.renderer = data;
        this.renderer.on('writeData', (buffer: ArrayBuffer) => {
          return this.callback.onPlayerData(buffer);
        });
        this.renderer.on('stateChange', (state: audio.AudioState) => {
          this.callback.onStateChanged(state);
        });
        if (this.pendingStart) {
          this.pendingStart = false;
          this.doStart();
        }
      });
      return true;
    } catch (e) {
      console.error(`AudioRenderer create failed: ${e}`);
      return false;
    }
  }

  private doStart() {
    this.finishSend = false;
    this.renderer?.start();
  }

  start() {
    if (this.renderer) {
      this.doStart();
    } else {
      this.pendingStart = true;
    }
  }

  stop() {
    this.pendingStart = false;
    this.renderer?.stop();
  }

  release() {
    this.pendingStart = false;
    this.renderer?.release();
    this.renderer = undefined;
  }

  setFinishSend(finish: boolean) {
    this.finishSend = finish;
  }

  checkFinish(): boolean {
    return this.finishSend;
  }
}

// AudioCapturer wrapper for ASR recording
export class AudioCapturerWrapper {
  private capturer: audio.AudioCapturer | undefined;
  private callback: IAudioCapturerCallback;
  private pendingStart: boolean = false;

  constructor(callback: IAudioCapturerCallback) {
    this.callback = callback;
  }

  create(): boolean {
    const streamInfo: audio.AudioStreamInfo = {
      samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
      channels: audio.AudioChannel.CHANNEL_1,
      sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
      encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
    };
    const capturerInfo: audio.AudioCapturerInfo = {
      source: audio.SourceType.SOURCE_TYPE_MIC,
      capturerFlags: 0
    };
    const options: audio.AudioCapturerOptions = {
      streamInfo: streamInfo,
      capturerInfo: capturerInfo
    };
    try {
      audio.createAudioCapturer(options).then((data) => {
        this.capturer = data;
        this.capturer.on('readData', (buffer: ArrayBuffer) => {
          this.callback.onRecorderData(buffer);
        });
        this.capturer.on('stateChange', (state: audio.AudioState) => {
          this.callback.onStateChanged(state);
        });
        if (this.pendingStart) {
          this.pendingStart = false;
          this.capturer.start();
        }
      }).catch((err: Error) => {
        console.error(`AudioCapturer Created Error: ${err}`);
        this.capturer = undefined;
      });
      return true;
    } catch (e) {
      console.error(`AudioCapturer create failed: ${e}`);
      return false;
    }
  }

  start() {
    if (this.capturer) {
      this.capturer.start();
    } else {
      this.pendingStart = true;
    }
  }

  stop() {
    this.pendingStart = false;
    this.capturer?.stop();
  }

  release() {
    this.pendingStart = false;
    this.capturer?.release();
    this.capturer = undefined;
  }
}
