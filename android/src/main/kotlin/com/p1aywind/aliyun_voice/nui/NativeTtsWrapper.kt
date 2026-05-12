package com.p1aywind.aliyun_voice.nui

import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.alibaba.idst.nui.CommonUtils
import com.alibaba.idst.nui.Constants
import com.alibaba.idst.nui.INativeTtsCallback
import com.alibaba.idst.nui.NativeNui
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

class NativeTtsWrapper(
    private val context: Context,
    private val onEvent: (String, Bundle?) -> Unit
) : INativeTtsCallback {

    companion object {
        private const val TAG = "NativeTtsWrapper"
        private const val WORK_DIR_NAME = "nui_tts_workspace"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val nui = NativeNui(Constants.ModeType.MODE_TTS)
    private var audioPlayer = AudioPlayer()
    private var initialized = false

    fun initialize(appKey: String, token: String, deviceId: String): Int {
        val workPath = CommonUtils.getModelPath(context)
        if (!CommonUtils.copyAssetsData(context)) {
            Log.e(TAG, "copyAssetsData failed")
            return -1
        }

        val ticket = buildTicket(appKey, token, deviceId, workPath)
        val ret = nui.tts_initialize(this, ticket, Constants.LogLevel.LOG_LEVEL_VERBOSE, true)
        if (ret == 0) {
            initialized = true
            Log.i(TAG, "TTS SDK initialized successfully")
        } else {
            Log.e(TAG, "TTS SDK initialize failed: $ret")
        }
        return ret
    }

    fun setParam(param: String, value: String): Int {
        return nui.setparamTts(param, value)
    }

    fun startTts(text: String, voice: String, sampleRate: Int, speed: Float, volume: Float): Int {
        audioPlayer = AudioPlayer()
        if (!audioPlayer.create(sampleRate)) {
            return -1
        }

        nui.setparamTts("font_name", voice)
        nui.setparamTts("sample_rate", sampleRate.toString())
        nui.setparamTts("speed_level", speed.toString())
        nui.setparamTts("volume", volume.toString())

        val charNum = nui.getUtf8CharsNum(text)
        nui.setparamTts("tts_version", if (charNum > 300) "1" else "0")

        return nui.startTts("1", "", text)
    }

    fun cancelTts(): Int = nui.cancelTts("")

    fun pauseTts(): Int {
        audioPlayer.pause()
        return nui.pauseTts()
    }

    fun resumeTts(): Int {
        audioPlayer.resume()
        return nui.resumeTts()
    }

    fun release(): Int {
        audioPlayer.release()
        val ret = nui.tts_release()
        if (ret == 0) {
            initialized = false
        }
        return ret
    }

    // INativeTtsCallback

    override fun onTtsEventCallback(event: INativeTtsCallback.TtsEvent?, taskId: String?, retCode: Int) {
        Log.i(TAG, "onTtsEventCallback: event=$event taskId=$taskId retCode=$retCode")
        when (event) {
            INativeTtsCallback.TtsEvent.TTS_EVENT_START -> {
                audioPlayer.play()
                sendEvent("ttsStart", Bundle().apply { putString("taskId", taskId ?: "") })
            }
            INativeTtsCallback.TtsEvent.TTS_EVENT_END -> {
                audioPlayer.setFinish(true)
                sendEvent("ttsEnd", Bundle().apply { putString("taskId", taskId ?: "") })
            }
            INativeTtsCallback.TtsEvent.TTS_EVENT_CANCEL -> {
                audioPlayer.release()
                sendEvent("ttsCancel", null)
            }
            INativeTtsCallback.TtsEvent.TTS_EVENT_PAUSE -> {
                sendEvent("ttsPause", null)
            }
            INativeTtsCallback.TtsEvent.TTS_EVENT_RESUME -> {
                sendEvent("ttsResume", null)
            }
            INativeTtsCallback.TtsEvent.TTS_EVENT_ERROR -> {
                val errorMsg = nui.getparamTts("error_msg")
                audioPlayer.release()
                sendEvent("ttsError", Bundle().apply {
                    putInt("code", retCode)
                    putString("message", errorMsg ?: "TTS error")
                    putString("taskId", taskId ?: "")
                })
            }
            else -> {}
        }
    }

    override fun onTtsDataCallback(info: String?, infoLen: Int, data: ByteArray?) {
        if (!info.isNullOrEmpty()) {
            Log.d(TAG, "tts info: $info")
        }
        if (data != null && data.isNotEmpty()) {
            audioPlayer.setAudioData(data)
        }
    }

    override fun onTtsVolCallback(p0: Int) {
        // volume callback not used
    }

    private fun sendEvent(type: String, data: Bundle?) {
        mainHandler.post {
            onEvent(type, data)
        }
    }

    private fun buildTicket(appKey: String, token: String, deviceId: String, workPath: String): String {
        return JSONObject().apply {
            put("app_key", appKey)
            put("token", token)
            put("device_id", deviceId)
            put("url", "wss://nls-gateway.cn-shanghai.aliyuncs.com:443/ws/v1")
            put("workspace", workPath)
            put("mode_type", Constants.TtsModeTypeCloud)
        }.toString()
    }
}
