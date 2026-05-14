/// Flutter plugin for Aliyun NUI SDK — speech recognition and text-to-speech.
///
/// Supports Android, iOS, and HarmonyOS (OHOS).
///
/// ```dart
/// import 'package:aliyun_voice/aliyun_voice.dart';
///
/// final asr = AliyunAsrService();
/// await asr.initialize(appKey: '...', token: '...');
/// asr.eventStream.listen((event) => print(event));
/// await asr.startDialog(enableVad: true);
/// ```
library;

export 'src/aliyun_asr_service.dart';
export 'src/aliyun_tts_service.dart';
export 'src/models/asr_event.dart';
export 'src/models/tts_event.dart';
