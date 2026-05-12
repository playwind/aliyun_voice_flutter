package com.p1aywind.aliyun_voice.nui

import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.alibaba.idst.nui.AsrResult
import com.alibaba.idst.nui.CommonUtils
import com.alibaba.idst.nui.Constants
import com.alibaba.idst.nui.INativeNuiCallback
import com.alibaba.idst.nui.KwsResult
import com.alibaba.idst.nui.NativeNui
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

class NativeNuiWrapper(
    private val context: Context,
    private val onEvent: (String, Bundle?) -> Unit
) : INativeNuiCallback {

    companion object {
        private const val TAG = "NativeNuiWrapper"
        private const val WORK_DIR_NAME = "nui_workspace"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val nui = NativeNui()
    private var audioRecorder = AudioRecorder()
    private var initialized = false

    fun initialize(appKey: String, token: String, deviceId: String): Int {
        val workPath = CommonUtils.getModelPath(context)
        if (!CommonUtils.copyAssetsData(context)) {
            Log.e(TAG, "copyAssetsData failed")
            return -1
        }
        val debugPath = context.externalCacheDir?.absolutePath + "/nui_debug_${System.currentTimeMillis()}"
        File(debugPath).mkdirs()

        val params = buildInitParams(appKey, token, deviceId, workPath, debugPath)
        val ret = nui.initialize(this, params, Constants.LogLevel.LOG_LEVEL_VERBOSE, true)
        if (ret == 0) {
            initialized = true
            Log.i(TAG, "NUI SDK initialized successfully")
        } else {
            Log.e(TAG, "NUI SDK initialize failed: $ret")
        }
        return ret
    }

    fun setParams(enableVad: Boolean, maxStartSilence: Int, maxEndSilence: Int): Int {
        val nlsConfig = JSONObject().apply {
            put("enable_intermediate_result", true)
            put("enable_punctuation_prediction", true)
            put("enable_inverse_text_normalization", true)
            if (enableVad) {
                put("enable_voice_detection", true)
                put("max_start_silence", maxStartSilence)
                put("max_end_silence", maxEndSilence)
            }
        }
        val params = JSONObject().apply {
            put("nls_config", nlsConfig)
            put("service_type", Constants.kServiceTypeASR)
        }
        return nui.setParams(params.toString())
    }

    fun startDialog(enableVad: Boolean): Int {
        val vadMode = if (enableVad) Constants.VadMode.TYPE_P2T else Constants.VadMode.TYPE_P2T
        return nui.startDialog(vadMode, JSONObject().toString())
    }

    fun stopDialog(): Int = nui.stopDialog()

    fun cancelDialog(): Int = nui.cancelDialog()

    fun release(): Int {
        val ret = nui.release()
        if (ret == 0) {
            initialized = false
        }
        return ret
    }

    // INativeNuiCallback

    override fun onNuiAudioStateChanged(state: Constants.AudioState?) {
        Log.i(TAG, "onNuiAudioStateChanged: $state")
        when (state) {
            Constants.AudioState.STATE_OPEN -> {
                audioRecorder = AudioRecorder()
                if (audioRecorder.create()) {
                    audioRecorder.start()
                }
            }
            Constants.AudioState.STATE_CLOSE -> {
                audioRecorder.release()
            }
            Constants.AudioState.STATE_PAUSE -> {
                audioRecorder.stop()
            }
            else -> {}
        }
    }

    override fun onNuiNeedAudioData(buffer: ByteArray?, len: Int): Int {
        if (buffer == null) return -1
        return audioRecorder.read(buffer, 0, len)
    }

    override fun onNuiEventCallback(
        event: Constants.NuiEvent?,
        resultCode: Int,
        arg2: Int,
        kwsResult: KwsResult?,
        asrResult: AsrResult?
    ) {
        Log.i(TAG, "onNuiEventCallback: event=$event resultCode=$resultCode")
        when (event) {
            Constants.NuiEvent.EVENT_VAD_START -> {
                sendEvent("vadStart", null)
            }
            Constants.NuiEvent.EVENT_VAD_END -> {
                sendEvent("vadEnd", null)
            }
            Constants.NuiEvent.EVENT_ASR_PARTIAL_RESULT -> {
                sendEvent("partialResult", Bundle().apply {
                    putString("text", asrResult?.asrResult ?: "")
                })
            }
            Constants.NuiEvent.EVENT_ASR_RESULT -> {
                sendEvent("finalResult", Bundle().apply {
                    putString("text", asrResult?.asrResult ?: "")
                })
            }
            Constants.NuiEvent.EVENT_ASR_ERROR -> {
                sendEvent("error", Bundle().apply {
                    putInt("code", resultCode)
                    putString("message", asrResult?.asrResult ?: "ASR error")
                })
            }
            Constants.NuiEvent.EVENT_MIC_ERROR -> {
                sendEvent("micError", null)
            }
            else -> {}
        }
    }

    override fun onNuiAudioRMSChanged(rms: Float) {
        sendEvent("audioRms", Bundle().apply {
            putFloat("value", rms)
        })
    }

    override fun onNuiVprEventCallback(p0: Constants.NuiVprEvent?) {
        // voiceprint not used
    }

    private fun sendEvent(type: String, data: Bundle?) {
        mainHandler.post {
            onEvent(type, data)
        }
    }

    private fun buildInitParams(
        appKey: String, token: String, deviceId: String,
        workPath: String, debugPath: String
    ): String {
        return JSONObject().apply {
            put("app_key", appKey)
            put("token", token)
            put("device_id", deviceId)
            put("url", "wss://nls-gateway.cn-shanghai.aliyuncs.com:443/ws/v1")
            put("workspace", workPath)
            put("sample_rate", "16000")
            put("format", "opus")
            put("debug_path", debugPath)
            put("service_mode", Constants.ModeAsrCloud)
        }.toString()
    }
}
