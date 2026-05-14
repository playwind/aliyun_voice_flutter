import 'dart:async';

import 'package:aliyun_voice/aliyun_voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

// TODO: Replace with your Aliyun appKey and token
// Obtain from https://nls-portal.console.aliyun.com/
const _appKey = '';
const _token = '';

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: _EntryPage());
  }
}

class _EntryPage extends StatelessWidget {
  const _EntryPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aliyun Voice SDK')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _AsrPage()),
              ),
              child: const Text('语音识别 (ASR)'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _TtsPage()),
              ),
              child: const Text('语音合成 (TTS)'),
            ),
          ],
        ),
      ),
    );
  }
}

// ========== ASR ==========

class _AsrPage extends StatefulWidget {
  const _AsrPage();

  @override
  State<_AsrPage> createState() => _AsrPageState();
}

class _AsrPageState extends State<_AsrPage> with WidgetsBindingObserver {
  final _asr = AliyunAsrService();
  StreamSubscription<AsrEvent>? _sub;

  String _status = 'idle';
  String _partial = '';
  String _result = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _asr.release();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused) {
      _asr.cancelDialog();
    }
  }

  Future<void> _init() async {
    if (_appKey.isEmpty || _token.isEmpty) {
      _setStatus('请先配置 appKey 和 token');
      return;
    }
    _setStatus('initializing...');
    try {
      await _asr.initialize(appKey: _appKey, token: _token);
      _sub = _asr.eventStream.listen(_onEvent);
      _setStatus('initialized');
    } on PlatformException catch (e) {
      _setStatus('init failed: ${e.message}');
    }
  }

  void _onEvent(AsrEvent event) {
    switch (event.type) {
      case AsrEventType.vadStart:
        _setStatus('listening...');
      case AsrEventType.vadEnd:
        _setStatus('processing...');
      case AsrEventType.partialResult:
        setState(() => _partial = event.text ?? '');
      case AsrEventType.finalResult:
        setState(() {
          _result = event.text ?? '';
          _partial = '';
          _status = 'result';
        });
      case AsrEventType.error:
        _setStatus('error: ${event.errorCode} ${event.errorMessage}');
      case AsrEventType.micError:
        _setStatus('mic error: 请检查录音权限');
      case AsrEventType.audioRms:
        break;
      case AsrEventType.unknown:
        break;
    }
  }

  // 申请录音/麦克风权限
  Future<bool> requestAudioPermission() async {
    var status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> _start() async {
    try {
      await requestAudioPermission();
      await _asr.startDialog(enableVad: true);
      _setStatus('waiting for speech...');
    } on PlatformException catch (e) {
      _setStatus('start failed: ${e.message}');
    }
  }

  Future<void> _stop() async {
    try {
      await _asr.stopDialog();
    } on PlatformException catch (e) {
      _setStatus('stop failed: ${e.message}');
    }
  }

  Future<void> _release() async {
    _sub?.cancel();
    _sub = null;
    try {
      await _asr.release();
      _setStatus('released');
    } on PlatformException catch (e) {
      _setStatus('release failed: ${e.message}');
    }
  }

  void _setStatus(String s) => setState(() => _status = s);

  @override
  Widget build(BuildContext context) {
    final listening =
        _status == 'listening...' ||
        _status == 'waiting for speech...' ||
        _status == 'processing...';

    return Scaffold(
      appBar: AppBar(title: const Text('语音识别')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Status: $_status', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            Text(
              'Partial: $_partial',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'Result: $_result',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            _Btn('Init', _init, !listening && _status == 'idle'),
            _Btn('Start', _start, !listening),
            _Btn('Stop', _stop, listening),
            _Btn(
              'Release',
              _release,
              !listening && _status != 'idle' && _status != 'released',
            ),
          ],
        ),
      ),
    );
  }
}

// ========== TTS ==========

class _TtsPage extends StatefulWidget {
  const _TtsPage();

  @override
  State<_TtsPage> createState() => _TtsPageState();
}

class _TtsPageState extends State<_TtsPage> {
  final _tts = AliyunTtsService();
  final _textCtrl = TextEditingController(
    text:
        '没人喜欢被 “教育”，人人都反感被说教成年人都有自尊和执念，骨子里都觉得自己是对的。你越是想纠正他、指点他、改造他，他越抵触、越反驳，甚至心生怨恨。好为人师，本身就是人际关系里的大忌。不轻易点评、不强行说教、不试图改变，是最高级的社交修养。',
  );
  StreamSubscription<TtsEvent>? _sub;

  String _status = 'idle';
  bool _playing = false;

  @override
  void dispose() {
    _sub?.cancel();
    _tts.release();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (_appKey.isEmpty || _token.isEmpty) {
      _setStatus('请先配置 appKey 和 token');
      return;
    }
    _setStatus('initializing...');
    try {
      await _tts.initialize(appKey: _appKey, token: _token);
      _sub = _tts.eventStream.listen(_onEvent);
      _setStatus('initialized');
    } on PlatformException catch (e) {
      _setStatus('init failed: ${e.message}');
    }
  }

  void _onEvent(TtsEvent event) {
    switch (event.type) {
      case TtsEventType.ttsStart:
        setState(() {
          _status = 'playing';
          _playing = true;
        });
      case TtsEventType.ttsEnd:
        setState(() {
          _status = 'finished';
          _playing = false;
        });
      case TtsEventType.ttsCancel:
        setState(() {
          _status = 'cancelled';
          _playing = false;
        });
      case TtsEventType.ttsPause:
        setState(() {
          _status = 'paused';
          _playing = false;
        });
      case TtsEventType.ttsResume:
        setState(() {
          _status = 'playing';
          _playing = true;
        });
      case TtsEventType.ttsError:
        setState(() {
          _status = 'error: ${event.errorCode} ${event.errorMessage}';
          _playing = false;
        });
      case TtsEventType.unknown:
        break;
    }
  }

  Future<void> _speak() async {
    try {
      await _tts.start(text: _textCtrl.text, voice: 'zhitian_emo', speed: 1.2);
    } on PlatformException catch (e) {
      _setStatus('speak failed: ${e.message}');
    }
  }

  Future<void> _pause() async {
    try {
      await _tts.pause();
    } on PlatformException catch (e) {
      _setStatus('pause failed: ${e.message}');
    }
  }

  Future<void> _resume() async {
    try {
      await _tts.resume();
    } on PlatformException catch (e) {
      _setStatus('resume failed: ${e.message}');
    }
  }

  Future<void> _cancel() async {
    try {
      await _tts.cancel();
    } on PlatformException catch (e) {
      _setStatus('cancel failed: ${e.message}');
    }
  }

  Future<void> _release() async {
    _sub?.cancel();
    _sub = null;
    try {
      await _tts.release();
      _setStatus('released');
    } on PlatformException catch (e) {
      _setStatus('release failed: ${e.message}');
    }
  }

  void _setStatus(String s) => setState(() => _status = s);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('语音合成')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Status: $_status', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            TextField(
              controller: _textCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '合成文本',
              ),
            ),
            const SizedBox(height: 16),
            _Btn('Init', _init, _status == 'idle'),
            _Btn(
              'Speak',
              _speak,
              !_playing &&
                  (_status == 'initialized' ||
                      _status == 'finished' ||
                      _status == 'cancelled'),
            ),
            _Btn('Pause', _pause, _playing),
            _Btn('Resume', _resume, _status == 'paused'),
            _Btn('Cancel', _cancel, _playing || _status == 'paused'),
            _Btn(
              'Release',
              _release,
              !_playing && _status != 'idle' && _status != 'released',
            ),
          ],
        ),
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  const _Btn(this.label, this.onTap, this.enabled);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ElevatedButton(
        onPressed: enabled ? onTap : null,
        child: Text(label),
      ),
    );
  }
}
