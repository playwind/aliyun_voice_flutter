enum TtsEventType {
  ttsStart,
  ttsEnd,
  ttsCancel,
  ttsPause,
  ttsResume,
  ttsError,
  unknown,
}

class TtsEvent {
  final TtsEventType type;
  final int? errorCode;
  final String? errorMessage;
  final String? taskId;

  const TtsEvent({
    required this.type,
    this.errorCode,
    this.errorMessage,
    this.taskId,
  });

  factory TtsEvent.fromMap(Map<dynamic, dynamic> map) {
    final typeStr = map['type'] as String? ?? '';
    return TtsEvent(
      type: switch (typeStr) {
        'ttsStart' => TtsEventType.ttsStart,
        'ttsEnd' => TtsEventType.ttsEnd,
        'ttsCancel' => TtsEventType.ttsCancel,
        'ttsPause' => TtsEventType.ttsPause,
        'ttsResume' => TtsEventType.ttsResume,
        'ttsError' => TtsEventType.ttsError,
        _ => TtsEventType.unknown,
      },
      errorCode: map['code'] as int?,
      errorMessage: map['message'] as String?,
      taskId: map['taskId'] as String?,
    );
  }

  @override
  String toString() => 'TtsEvent(type: $type, errorCode: $errorCode, '
      'errorMessage: $errorMessage, taskId: $taskId)';
}
