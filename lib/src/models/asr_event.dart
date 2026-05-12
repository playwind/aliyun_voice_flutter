enum AsrEventType {
  vadStart,
  vadEnd,
  partialResult,
  finalResult,
  error,
  micError,
  audioRms,
  unknown,
}

class AsrEvent {
  final AsrEventType type;
  final String? text;
  final int? errorCode;
  final String? errorMessage;
  final double? rmsValue;

  const AsrEvent({
    required this.type,
    this.text,
    this.errorCode,
    this.errorMessage,
    this.rmsValue,
  });

  factory AsrEvent.fromMap(Map<dynamic, dynamic> map) {
    final typeStr = map['type'] as String? ?? '';
    return AsrEvent(
      type: switch (typeStr) {
        'vadStart' => AsrEventType.vadStart,
        'vadEnd' => AsrEventType.vadEnd,
        'partialResult' => AsrEventType.partialResult,
        'finalResult' => AsrEventType.finalResult,
        'error' => AsrEventType.error,
        'micError' => AsrEventType.micError,
        'audioRms' => AsrEventType.audioRms,
        _ => AsrEventType.unknown,
      },
      text: map['text'] as String?,
      errorCode: map['code'] as int?,
      errorMessage: map['message'] as String?,
      rmsValue: (map['value'] as num?)?.toDouble(),
    );
  }

  @override
  String toString() => 'AsrEvent(type: $type, text: $text, '
      'errorCode: $errorCode, errorMessage: $errorMessage, rmsValue: $rmsValue)';
}
