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

import android.media.MediaCodec
import android.media.MediaCodec.BufferInfo
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import timber.log.Timber
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer

class AudioEncoder (private val outputSampleRate:Int, private val cacheDir: File) {
    private val BUFFER_SIZE = 48000
    val CODEC_TIMEOUT_IN_MS:Long = 5000

    fun encode(infile: File, outfile:String) {
        val tmpOutfile = File.createTempFile("tmp", ".tmp", cacheDir)
        Timber.i("create new temp file $tmpOutfile")

        val start = System.currentTimeMillis()
        val fis = FileInputStream(infile)

        val mux = MediaMuxer(tmpOutfile.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

        var outputFormat = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, outputSampleRate, 1)
        outputFormat.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
        outputFormat.setInteger(MediaFormat.KEY_BIT_RATE, 96000)
        outputFormat.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)

        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        codec.configure(outputFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()

        val codecInputBuffers = codec.inputBuffers // Note: Array of buffers

        val codecOutputBuffers = codec.outputBuffers

        val outBuffInfo = BufferInfo()
        val tempBuffer = ByteArray(BUFFER_SIZE)
        var hasMoreData = true
        var presentationTimeUs = 0.0
        var audioTrackIdx = 0
        var totalBytesRead = 0
        var percentComplete = 0
        do {
            var inputBufIndex = 0
            while (inputBufIndex != -1 && hasMoreData) {
                inputBufIndex = codec.dequeueInputBuffer(CODEC_TIMEOUT_IN_MS)
                if (inputBufIndex >= 0) {
                    val dstBuf: ByteBuffer = codecInputBuffers.get(inputBufIndex)
                    dstBuf.clear()
                    val bytesRead: Int = fis.read(tempBuffer, 0, dstBuf.limit())
                    Timber.i("Read $bytesRead")
                    if (bytesRead == -1) { // -1 implies EOS
                        hasMoreData = false
                        codec.queueInputBuffer(inputBufIndex, 0, 0, presentationTimeUs.toLong(), MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    } else {
                        totalBytesRead += bytesRead
                        dstBuf.put(tempBuffer, 0, bytesRead)
                        codec.queueInputBuffer(inputBufIndex, 0, bytesRead, presentationTimeUs.toLong(), 0)
                        presentationTimeUs = (1000000L * (totalBytesRead / 2) / outputSampleRate).toDouble()
                    }
                }
            }
            // Drain audio
            var outputBufIndex = 0
            while (outputBufIndex != MediaCodec.INFO_TRY_AGAIN_LATER) {
                outputBufIndex = codec.dequeueOutputBuffer(outBuffInfo, CODEC_TIMEOUT_IN_MS)
                if (outputBufIndex >= 0) {
                    val encodedData: ByteBuffer = codecOutputBuffers.get(outputBufIndex)
                    encodedData.position(outBuffInfo.offset)
                    encodedData.limit(outBuffInfo.offset + outBuffInfo.size)
                    if (outBuffInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0 && outBuffInfo.size != 0) {
                        codec.releaseOutputBuffer(outputBufIndex, false)
                    } else {
                        mux.writeSampleData(audioTrackIdx, codecOutputBuffers.get(outputBufIndex), outBuffInfo)
                        codec.releaseOutputBuffer(outputBufIndex, false)
                    }
                } else if (outputBufIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    outputFormat = codec.outputFormat
                    Timber.i("Output format changed - $outputFormat")
                    audioTrackIdx = mux.addTrack(outputFormat)
                    mux.start()
                } else if (outputBufIndex == MediaCodec.INFO_OUTPUT_BUFFERS_CHANGED) {
                    Timber.i("Output buffers changed during encode!")
                } else if (outputBufIndex == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    // NO OP
                } else {
                    Timber.i("Unknown return code from dequeueOutputBuffer - $outputBufIndex")
                }
            }
            percentComplete = Math.round(totalBytesRead.toFloat() / infile.length().toFloat() * 100.0).toInt()
            Timber.i("Conversion % - $percentComplete")
        } while (outBuffInfo.flags != MediaCodec.BUFFER_FLAG_END_OF_STREAM)

        fis.close()
        mux.stop()
        mux.release()
        if(tmpOutfile.exists()) {
            tmpOutfile.copyTo(File(outfile), overwrite = true)
            tmpOutfile.delete()
        }
        Timber.i("Encoded $infile to $outfile in ${System.currentTimeMillis() - start}ms")
        
    }
}