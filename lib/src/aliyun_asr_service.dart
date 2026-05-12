import 'dart:async';

import 'package:flutter/services.dart';

import 'models/asr_event.dart';

export 'models/asr_event.dart';

class AliyunAsrService {
  static const _method = MethodChannel('com.p1aywind.aliyun_voice/asr');
  static const _event = EventChannel('com.p1aywind.aliyun_voice/asr_events');

  Stream<AsrEvent>? _stream;

  /// 事件流，监听 ASR 所有回调事件
  Stream<AsrEvent> get eventStream {
    return _stream ??= _event.receiveBroadcastStream().map(
          (e) => AsrEvent.fromMap(e as Map<dynamic, dynamic>),
        );
  }

  /// 初始化 ASR SDK
  ///
  /// [appKey] 阿里云项目 AppKey
  /// [token] 访问 Token
  Future<void> initialize({
    required String appKey,
    required String token,
  }) async {
    await _method.invokeMethod<bool>('asr_initialize', {
      'appKey': appKey,
      'token': token,
    });
  }

  /// 开始识别对话
  ///
  /// [enableVad] 是否启用语音检测（自动判断说话结束）
  /// [maxStartSilence] 最大开始静音时间（毫秒），默认 10000
  /// [maxEndSilence] 最大结尾静音时间（毫秒），默认 800
  Future<void> startDialog({
    bool enableVad = false,
    int maxStartSilence = 10000,
    int maxEndSilence = 800,
  }) async {
    await _method.invokeMethod<bool>('asr_startDialog', {
      'enableVad': enableVad,
      'maxStartSilence': maxStartSilence,
      'maxEndSilence': maxEndSilence,
    });
  }

  /// 结束识别，等待服务端返回最终结果
  Future<void> stopDialog() async {
    await _method.invokeMethod<bool>('asr_stopDialog');
  }

  /// 立即取消识别，不等待最终结果
  Future<void> cancelDialog() async {
    await _method.invokeMethod<bool>('asr_cancelDialog');
  }

  /// 释放 ASR SDK 资源
  Future<void> release() async {
    await _method.invokeMethod<bool>('asr_release');
    _stream = null;
  }
}
