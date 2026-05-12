package com.p1aywind.aliyun_voice.nui

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.util.Log
import java.util.concurrent.ConcurrentLinkedQueue

class AudioPlayer {

    companion object {
        private const val TAG = "AudioPlayer"
        private const val SAMPLE_RATE = 16000
    }

    private var audioTrack: AudioTrack? = null
    private var isPlaying = false
    private var playThread: Thread? = null
    private val audioQueue = ConcurrentLinkedQueue<ByteArray>()
    private var finishSending = false

    fun create(sampleRate: Int = SAMPLE_RATE): Boolean {
        val bufferSize = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        if (bufferSize == AudioTrack.ERROR || bufferSize == AudioTrack.ERROR_BAD_VALUE) {
            Log.e(TAG, "Failed to get minimum buffer size")
            return false
        }

        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(bufferSize)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()

        return true
    }

    fun play() {
        if (isPlaying) return
        isPlaying = true
        finishSending = false
        audioQueue.clear()

        playThread = Thread {
            audioTrack?.play()
            Log.i(TAG, "AudioTrack playing")

            while (isPlaying || audioQueue.isNotEmpty()) {
                val data = audioQueue.poll()
                if (data != null) {
                    audioTrack?.write(data, 0, data.size)
                } else if (finishSending) {
                    break
                } else {
                    Thread.sleep(10)
                }
            }

            audioTrack?.stop()
            Log.i(TAG, "AudioTrack stopped")
            isPlaying = false
        }.also { it.start() }
    }

    fun pause() {
        try {
            audioTrack?.pause()
        } catch (e: IllegalStateException) {
            Log.w(TAG, "pause failed: ${e.message}")
        }
    }

    fun resume() {
        try {
            audioTrack?.play()
        } catch (e: IllegalStateException) {
            Log.w(TAG, "resume failed: ${e.message}")
        }
    }

    fun setAudioData(data: ByteArray) {
        audioQueue.add(data)
    }

    fun setFinish(finish: Boolean) {
        finishSending = finish
    }

    fun release() {
        isPlaying = false
        finishSending = true
        try {
            playThread?.join(1000)
        } catch (_: InterruptedException) {}
        audioTrack?.stop()
        audioTrack?.release()
        audioTrack = null
        audioQueue.clear()
        Log.i(TAG, "AudioTrack released")
    }
}
