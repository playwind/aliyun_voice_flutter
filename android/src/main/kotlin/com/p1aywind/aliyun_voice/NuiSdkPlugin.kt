package com.p1aywind.aliyun_voice

import android.content.Context
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import com.p1aywind.aliyun_voice.nui.NativeNuiWrapper
import com.p1aywind.aliyun_voice.nui.NativeTtsWrapper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class NuiSdkPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "NuiSdkPlugin"

        // ASR
        private const val ASR_METHOD = "com.p1aywind.aliyun_voice/asr"
        private const val ASR_EVENT = "com.p1aywind.aliyun_voice/asr_events"

        // TTS
        private const val TTS_METHOD = "com.p1aywind.aliyun_voice/tts"
        private const val TTS_EVENT = "com.p1aywind.aliyun_voice/tts_events"
    }

    private var asrMethodChannel: MethodChannel? = null
    private var asrEventChannel: EventChannel? = null
    private var asrEventSink: EventChannel.EventSink? = null

    private var ttsMethodChannel: MethodChannel? = null
    private var ttsEventChannel: EventChannel? = null
    private var ttsEventSink: EventChannel.EventSink? = null

    private var context: Context? = null
    private var asrWrapper: NativeNuiWrapper? = null
    private var ttsWrapper: NativeTtsWrapper? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        val messenger = binding.binaryMessenger

        // ASR channels
        asrMethodChannel = MethodChannel(messenger, ASR_METHOD).also {
            it.setMethodCallHandler(this)
        }
        asrEventChannel = EventChannel(messenger, ASR_EVENT).also {
            it.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    asrEventSink = sink
                }
                override fun onCancel(arguments: Any?) { asrEventSink = null }
            })
        }

        // TTS channels
        ttsMethodChannel = MethodChannel(messenger, TTS_METHOD).also {
            it.setMethodCallHandler(this)
        }
        ttsEventChannel = EventChannel(messenger, TTS_EVENT).also {
            it.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    ttsEventSink = sink
                }
                override fun onCancel(arguments: Any?) { ttsEventSink = null }
            })
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        asrMethodChannel?.setMethodCallHandler(null)
        asrEventChannel?.setStreamHandler(null)
        ttsMethodChannel?.setMethodCallHandler(null)
        ttsEventChannel?.setStreamHandler(null)
        asrMethodChannel = null
        asrEventChannel = null
        ttsMethodChannel = null
        ttsEventChannel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // ASR
            "asr_initialize" -> handleAsrInit(call, result)
            "asr_startDialog" -> handleAsrStart(call, result)
            "asr_stopDialog" -> handleAsrStop(result)
            "asr_cancelDialog" -> handleAsrCancel(result)
            "asr_release" -> handleAsrRelease(result)

            // TTS
            "tts_initialize" -> handleTtsInit(call, result)
            "tts_start" -> handleTtsStart(call, result)
            "tts_cancel" -> handleTtsCancel(result)
            "tts_pause" -> handleTtsPause(result)
            "tts_resume" -> handleTtsResume(result)
            "tts_release" -> handleTtsRelease(result)

            else -> result.notImplemented()
        }
    }

    // ---- ASR ----

    private fun handleAsrInit(call: MethodCall, result: MethodChannel.Result) {
        val appKey = call.argument<String>("appKey") ?: ""
        val token = call.argument<String>("token") ?: ""
        val ctx = context ?: run { result.error("ERROR", "Context is null", null); return }

        if (appKey.isEmpty() || token.isEmpty()) {
            result.error("INVALID_PARAMS", "appKey and token are required", null)
            return
        }

        val deviceId = getDeviceId(ctx)
        asrWrapper = NativeNuiWrapper(ctx) { type, data ->
            sendEvent(asrEventSink, type, data)
        }

        Thread {
            val ret = asrWrapper?.initialize(appKey, token, deviceId) ?: -1
            if (ret == 0) result.success(true)
            else result.error("ASR_INIT_FAILED", "initialize returned $ret", null)
        }.start()
    }

    private fun handleAsrStart(call: MethodCall, result: MethodChannel.Result) {
        val w = asrWrapper ?: run { result.error("NOT_INITIALIZED", "ASR not initialized", null); return }
        val enableVad = call.argument<Boolean>("enableVad") ?: false
        val maxStartSilence = call.argument<Int>("maxStartSilence") ?: 10000
        val maxEndSilence = call.argument<Int>("maxEndSilence") ?: 800
        w.setParams(enableVad, maxStartSilence, maxEndSilence)
        val ret = w.startDialog(enableVad)
        if (ret == 0) result.success(true) else result.error("ASR_START_FAILED", "startDialog returned $ret", null)
    }

    private fun handleAsrStop(result: MethodChannel.Result) {
        val w = asrWrapper ?: run { result.error("NOT_INITIALIZED", "ASR not initialized", null); return }
        val ret = w.stopDialog()
        if (ret == 0) result.success(true) else result.error("ASR_STOP_FAILED", "stopDialog returned $ret", null)
    }

    private fun handleAsrCancel(result: MethodChannel.Result) {
        val w = asrWrapper ?: run { result.error("NOT_INITIALIZED", "ASR not initialized", null); return }
        val ret = w.cancelDialog()
        if (ret == 0) result.success(true) else result.error("ASR_CANCEL_FAILED", "cancelDialog returned $ret", null)
    }

    private fun handleAsrRelease(result: MethodChannel.Result) {
        val w = asrWrapper ?: run { result.success(true); return }
        val ret = w.release()
        asrWrapper = null
        if (ret == 0) result.success(true) else result.error("ASR_RELEASE_FAILED", "release returned $ret", null)
    }

    // ---- TTS ----

    private fun handleTtsInit(call: MethodCall, result: MethodChannel.Result) {
        val appKey = call.argument<String>("appKey") ?: ""
        val token = call.argument<String>("token") ?: ""
        val ctx = context ?: run { result.error("ERROR", "Context is null", null); return }

        if (appKey.isEmpty() || token.isEmpty()) {
            result.error("INVALID_PARAMS", "appKey and token are required", null)
            return
        }

        val deviceId = getDeviceId(ctx)
        ttsWrapper = NativeTtsWrapper(ctx) { type, data ->
            sendEvent(ttsEventSink, type, data)
        }

        Thread {
            val ret = ttsWrapper?.initialize(appKey, token, deviceId) ?: -1
            if (ret == 0) result.success(true)
            else result.error("TTS_INIT_FAILED", "tts_initialize returned $ret", null)
        }.start()
    }

    private fun handleTtsStart(call: MethodCall, result: MethodChannel.Result) {
        val w = ttsWrapper ?: run { result.error("NOT_INITIALIZED", "TTS not initialized", null); return }
        val text = call.argument<String>("text") ?: ""
        val voice = call.argument<String>("voice") ?: "xiaoyun"
        val sampleRate = call.argument<Int>("sampleRate") ?: 16000
        val speed = (call.argument<Double>("speed") ?: 1.0).toFloat()
        val volume = (call.argument<Double>("volume") ?: 1.0).toFloat()

        if (text.isEmpty()) {
            result.error("INVALID_PARAMS", "text is required", null)
            return
        }

        val ret = w.startTts(text, voice, sampleRate, speed, volume)
        if (ret == 0) result.success(true) else result.error("TTS_START_FAILED", "startTts returned $ret", null)
    }

    private fun handleTtsCancel(result: MethodChannel.Result) {
        val w = ttsWrapper ?: run { result.error("NOT_INITIALIZED", "TTS not initialized", null); return }
        val ret = w.cancelTts()
        if (ret == 0) result.success(true) else result.error("TTS_CANCEL_FAILED", "cancelTts returned $ret", null)
    }

    private fun handleTtsPause(result: MethodChannel.Result) {
        val w = ttsWrapper ?: run { result.error("NOT_INITIALIZED", "TTS not initialized", null); return }
        val ret = w.pauseTts()
        if (ret == 0) result.success(true) else result.error("TTS_PAUSE_FAILED", "pauseTts returned $ret", null)
    }

    private fun handleTtsResume(result: MethodChannel.Result) {
        val w = ttsWrapper ?: run { result.error("NOT_INITIALIZED", "TTS not initialized", null); return }
        val ret = w.resumeTts()
        if (ret == 0) result.success(true) else result.error("TTS_RESUME_FAILED", "resumeTts returned $ret", null)
    }

    private fun handleTtsRelease(result: MethodChannel.Result) {
        val w = ttsWrapper ?: run { result.success(true); return }
        val ret = w.release()
        ttsWrapper = null
        if (ret == 0) result.success(true) else result.error("TTS_RELEASE_FAILED", "tts_release returned $ret", null)
    }

    // ---- Common ----

    private fun sendEvent(sink: EventChannel.EventSink?, type: String, data: Bundle?) {
        val map = mutableMapOf<String, Any?>("type" to type)
        data?.let { bundle ->
            for (key in bundle.keySet()) {
                map[key] = bundle.get(key)
            }
        }
        sink?.success(map)
    }

    private fun getDeviceId(ctx: Context): String {
        return try {
            Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ANDROID_ID)
        } catch (e: Exception) {
            "unknown_device"
        }
    }
}
