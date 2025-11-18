package com.bookbot.audio

import android.media.AudioFormat
import android.media.MediaRecorder

class AudioConfig {
    companion object {
        const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        var audioSource: Int = MediaRecorder.AudioSource.VOICE_COMMUNICATION
        const val RECORDING_SAMPLE_RATE = 44100
        const val MODEL_SAMPLE_RATE = 16000
        const val RECORD_ASR_AUDIO = false
        private const val BUFFER_SIZE_SECONDS = 0.1f
        const val AUDIO_BUFFER_SIZE = BUFFER_SIZE_SECONDS * MODEL_SAMPLE_RATE
        const val CODEC_TIMEOUT_IN_MS:Long = 5000
        const val ENCODE_BUFFER_SIZE = RECORDING_SAMPLE_RATE
        const val VAD_PATIENCE = 6
        // vadRule1ResetPatience * 100ms audio buffers of silence (no speech since start)
        const val vadRule1ResetPatience = 6
        // vadRule2ResetPatience * 100ms audio buffers of silence (after speech)
        const val vadRule2ResetPatience = 6
        const val VAD_WINDOWS_SIZE = 512
    }
}