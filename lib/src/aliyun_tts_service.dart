import 'dart:async';

import 'package:flutter/services.dart';

import 'models/tts_event.dart';

export 'models/tts_event.dart';

class AliyunTtsService {
  static const _method = MethodChannel('com.p1aywind.aliyun_voice/tts');
  static const _event = EventChannel('com.p1aywind.aliyun_voice/tts_events');

  Stream<TtsEvent>? _stream;

  /// 事件流，监听 TTS 所有回调事件
  Stream<TtsEvent> get eventStream {
    return _stream ??= _event.receiveBroadcastStream().map(
          (e) => TtsEvent.fromMap(e as Map<dynamic, dynamic>),
        );
  }

  /// 初始化 TTS SDK
  ///
  /// [appKey] 阿里云项目 AppKey
  /// [token] 访问 Token
  Future<void> initialize({
    required String appKey,
    required String token,
  }) async {
    await _method.invokeMethod<bool>('tts_initialize', {
      'appKey': appKey,
      'token': token,
    });
  }

  /// 开始语音合成
  ///
  /// [text] 合成文本
  /// [voice] 发音人，默认 xiaoyun，可选值参见 https://help.aliyun.com/document_detail/84435.html
  /// [sampleRate] 采样率，默认 16000
  /// [speed] 语速，默认 1.0
  /// [volume] 音量，默认 1.0
  Future<void> start({
    required String text,
    String voice = 'xiaoyun',
    int sampleRate = 16000,
    double speed = 1.0,
    double volume = 1.0,
  }) async {
    await _method.invokeMethod<bool>('tts_start', {
      'text': text,
      'voice': voice,
      'sampleRate': sampleRate,
      'speed': speed,
      'volume': volume,
    });
  }

  /// 取消语音合成
  Future<void> cancel() async {
    await _method.invokeMethod<bool>('tts_cancel');
  }

  /// 暂停语音合成
  Future<void> pause() async {
    await _method.invokeMethod<bool>('tts_pause');
  }

  /// 恢复语音合成
  Future<void> resume() async {
    await _method.invokeMethod<bool>('tts_resume');
  }

  /// 释放 TTS SDK 资源
  Future<void> release() async {
    await _method.invokeMethod<bool>('tts_release');
    _stream = null;
  }
}
