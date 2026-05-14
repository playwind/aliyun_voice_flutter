# aliyun_voice

[![pub package](https://img.shields.io/pub/v/aliyun_voice.svg)](https://pub.dev/packages/aliyun_voice)

Flutter plugin for [Aliyun NUI SDK](https://help.aliyun.com/product/30413.html) — speech recognition (ASR) and text-to-speech (TTS).

## Platforms

| Platform | Supported |
|----------|-----------|
| Android  | ✅ arm64-v8a, armeabi-v7a, x86_64 |
| iOS      | ✅ arm64, x86_64 |
| HarmonyOS (OHOS) | ✅ |

## Features

- **ASR** — Real-time speech recognition with intermediate results, punctuation prediction, and voice activity detection (VAD).
- **TTS** — Text-to-speech synthesis with configurable voice, sample rate, speed, and volume. Supports pause/resume/cancel.

## Getting started

### Prerequisites

1. Register an [Aliyun Intelligent Speech](https://nls-portal.console.aliyun.com/) project to obtain `appKey` and `token`.
2. For Android, no extra setup is needed — native libraries are bundled.
3. For iOS, no extra setup is needed — the framework is bundled.
4. For HarmonyOS, the `neonui.har` SDK is bundled with the plugin.

### Install

Add to your `pubspec.yaml`:

```yaml
dependencies:
  aliyun_voice: ^0.0.1
```

### Android

Add microphone permission to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
```

### iOS

Add microphone permission to `ios/Runner/Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Microphone access is required for speech recognition</string>
```

### HarmonyOS

Add permissions to `entry/src/main/module.json5`:

```json5
"requestPermissions": [
  { "name": "ohos.permission.INTERNET" },
  {
    "name": "ohos.permission.MICROPHONE",
    "reason": "$string:mic_reason",
    "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
  }
]
```

## Usage

### Speech Recognition (ASR)

```dart
import 'package:aliyun_voice/aliyun_voice.dart';

final asr = AliyunAsrService();

// Initialize
await asr.initialize(appKey: 'YOUR_APP_KEY', token: 'YOUR_TOKEN');

// Listen for events
asr.eventStream.listen((event) {
  switch (event.type) {
    case AsrEventType.partialResult:
      print('Partial: ${event.text}');
    case AsrEventType.finalResult:
      print('Final: ${event.text}');
    case AsrEventType.vadStart:
      print('Speech detected');
    case AsrEventType.error:
      print('Error: ${event.errorCode} ${event.errorMessage}');
    default:
      break;
  }
});

// Start recognition with VAD
await asr.startDialog(enableVad: true, maxEndSilence: 800);

// Stop or cancel
await asr.stopDialog();

// Release when done
await asr.release();
```

### Text-to-Speech (TTS)

```dart
import 'package:aliyun_voice/aliyun_voice.dart';

final tts = AliyunTtsService();

// Initialize
await tts.initialize(appKey: 'YOUR_APP_KEY', token: 'YOUR_TOKEN');

// Listen for events
tts.eventStream.listen((event) {
  switch (event.type) {
    case TtsEventType.ttsStart:
      print('Playback started');
    case TtsEventType.ttsEnd:
      print('Playback finished');
    case TtsEventType.ttsError:
      print('Error: ${event.errorCode} ${event.errorMessage}');
    default:
      break;
  }
});

// Speak
await tts.start(
  text: 'Hello world',
  voice: 'xiaoyun',
  sampleRate: 16000,
  speed: 1.0,
  volume: 1.0,
);

// Control playback
await tts.pause();
await tts.resume();
await tts.cancel();

// Release when done
await tts.release();
```

## API Reference

### AliyunAsrService

| Method | Description |
|--------|-------------|
| `initialize(appKey, token)` | Initialize ASR SDK |
| `startDialog({enableVad, maxStartSilence, maxEndSilence})` | Start recognition session |
| `stopDialog()` | Stop and wait for final result |
| `cancelDialog()` | Cancel immediately |
| `release()` | Release SDK resources |
| `eventStream` | Stream of `AsrEvent` |

### AliyunTtsService

| Method | Description |
|--------|-------------|
| `initialize(appKey, token)` | Initialize TTS SDK |
| `start({text, voice, sampleRate, speed, volume})` | Start synthesis |
| `pause()` | Pause playback |
| `resume()` | Resume playback |
| `cancel()` | Cancel playback |
| `release()` | Release SDK resources |
| `eventStream` | Stream of `TtsEvent` |

## Voice Options

Common voices include: `xiaoyun`, `zhitian_emo`, `zhiyan_emo`, `zhimi_emo`. See the [Aliyun TTS documentation](https://help.aliyun.com/document_detail/84435.html) for the full list.

## License

BSD-3-Clause. The bundled Aliyun NUI SDK is subject to [Aliyun's terms of service](https://help.aliyun.com/document_detail/75510.html).
