/*
Copyright 2025 [BOOKBOT](https://bookbotkids.com/)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

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