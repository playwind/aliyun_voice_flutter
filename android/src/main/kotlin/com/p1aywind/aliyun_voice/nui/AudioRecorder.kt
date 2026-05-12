package com.p1aywind.aliyun_voice.nui

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log

class AudioRecorder {

    companion object {
        private const val TAG = "AudioRecorder"
        private const val SAMPLE_RATE = 16000
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
    }

    private var audioRecord: AudioRecord? = null

    fun create(): Boolean {
        val bufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        if (bufferSize == AudioRecord.ERROR || bufferSize == AudioRecord.ERROR_BAD_VALUE) {
            Log.e(TAG, "Failed to get minimum buffer size")
            return false
        }

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            CHANNEL_CONFIG,
            AUDIO_FORMAT,
            bufferSize
        )

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            Log.e(TAG, "AudioRecord not initialized")
            release()
            return false
        }
        return true
    }

    fun start() {
        audioRecord?.startRecording()
        Log.i(TAG, "AudioRecord started")
    }

    fun stop() {
        audioRecord?.stop()
        Log.i(TAG, "AudioRecord stopped")
    }

    fun release() {
        audioRecord?.release()
        audioRecord = null
        Log.i(TAG, "AudioRecord released")
    }

    fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        val recorder = audioRecord ?: return -1
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            return -1
        }
        return recorder.read(buffer, offset, length)
    }
}
