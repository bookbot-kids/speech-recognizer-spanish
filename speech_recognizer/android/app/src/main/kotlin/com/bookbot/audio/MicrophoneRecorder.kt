package com.bookbot.audio

import com.bookbot.utils.DispatchQueue
import com.google.gson.Gson
import timber.log.Timber
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/// Encoding acc task
class EncoderRunnable(val input:File, val output: File, val encoder:AudioEncoder) : Runnable {
    override fun run() {
        if(input.exists()) {
            Timber.d("MicrophoneRecorder start encode ${input.path} to ${output.path}")
            encoder.encode(input, output.path)
            Timber.d("MicrophoneRecorder encode file ${output.path} done. File exist = ${output.exists()}")
            input.delete()
        }
    }
}

data class RecordingTask(private val gson: Gson, private val encoder: AudioEncoder, val pathName: String, val text: String) {
    private var audioFos: FileOutputStream? = null
    private val rawFile: File
    private var asrRawFile: File? = null
    private var asrAudioFos: FileOutputStream? = null
    private var transcripts = mutableListOf<String>()
    private val lock = Any()

    init {
        rawFile = File(rawPath)
        audioFos = FileOutputStream(rawFile, true)
        if(AudioConfig.RECORD_ASR_AUDIO) {
            asrRawFile = File("${pathName}_asr.raw")
            asrAudioFos =  FileOutputStream(asrRawFile, true)
        }
    }

    private val rawPath: String
        get() = "${pathName}.raw"

    private val transcriptPath: String
        get() = "${pathName}.json"

    private val targetPath: String
        get() = "${pathName}.aac"

    fun cleanUp() {
        stop()
        if(rawFile.exists()) {
            rawFile.delete()
        }

        if(AudioConfig.RECORD_ASR_AUDIO) {
            if(asrRawFile?.exists() == true) {
                asrRawFile?.delete()
            }
        }
    }

    private val transcriptJson: Map<String, String>
        get() {
            val map = mutableMapOf(
                "text" to text,
                "ipa" to transcripts.filter { it.isNotBlank() }.joinToString(",")
            )

            return map
        }

    fun stop() {
        try{
            audioFos?.close()
        }catch (e: IOException) {
            Timber.d(e)
        } finally {
            audioFos = null
        }
    }

    fun isComplete(): Boolean {
        return File(targetPath).exists()
    }

    fun export(){
        val outputFile = File(targetPath)
        Timber.d("MicrophoneRecorder flushSpeech exist ${rawFile.exists()}, ${outputFile.exists()}, ${rawFile.path}")
        if(outputFile.exists()) {
            // completed
            return
        }

        if(rawFile.exists()) {
            DispatchQueue.recordingQueue.execute {
                stop()
                val jsonData = transcriptJson
                val ipa = jsonData["ipa"] ?: ""
                if(ipa.isBlank()) {
                    // ignore recording if no transcript
                    rawFile.delete()
                    Timber.d("MicrophoneRecorder flushSpeech ignore no transcript recording ${jsonData["text"]} ${rawFile.path}")
                } else if(rawFile.path.contains("prompt") || rawFile.length() > 7000) {
                    val transcriptOutfile = File(transcriptPath)
                    transcriptOutfile.writeText(gson.toJson(jsonData))
                    Timber.d("MicrophoneRecorder flushSpeech write text file ${transcriptOutfile.path} [$text]")
                    val encoderJob = EncoderRunnable(rawFile, outputFile, encoder)
                    DispatchQueue.encodeQueue.execute(encoderJob)
                } else {
                    rawFile.delete()
                    Timber.d("MicrophoneRecorder flushSpeech Delete small file ${rawFile.length()} ${rawFile.path}")
                }
            }
        } else {
            Timber.d("MicrophoneRecorder flushSpeech Raw file ${rawFile.path} not exist")
        }
    }

    fun recordMic(buffer: ShortArray, readSize: Int) {
        DispatchQueue.recordingQueue.execute {
            audioFos?.let {
                try {
                    for (i in buffer.indices) {
                        it.write(byteArrayOf((buffer[i].toInt() and 0x00FF).toByte(), ((buffer[i].toInt() and 0xFF00) shr (8)).toByte()))
                    }
                } catch (e: IOException) {
                    Timber.e(e,"Can not write buffer $text $readSize into $rawPath")
                }
            }
        }
    }

    fun recordASR(buffer: ShortArray) {
        DispatchQueue.recordingQueue.execute {
            asrAudioFos?.let {
                try{
                    for(i in buffer.indices) {
                        it.write(byteArrayOf((buffer[i].toInt() and 0x00FF).toByte(), ((buffer[i].toInt() and 0xFF00) shr (8)).toByte()))
                    }
                } catch (e: IOException) {
                    Timber.e(e, "Can not write buffer $text ${buffer.joinToString()} into $rawPath")
                }
            }
        }
    }

    fun recordTranscript(newTranscript: String) {
        if(newTranscript.isBlank()){
            return
        }

        DispatchQueue.recordingQueue.execute {
            synchronized(lock) {
                when {
                    transcripts.isEmpty() || transcripts.last() != newTranscript -> transcripts.add(newTranscript)
                    newTranscript.contains(transcripts.last()) -> transcripts[transcripts.lastIndex] = newTranscript
                }
            }
        }
    }
}

/// Microphone recording
class MicrophoneRecorder(val recordingId:String,
                         val saveDir:String,
                         cacheDir: File) {
    private var encoder:AudioEncoder
    private var currentId = 0L

    /// Each transcript is a key for task to handle its own recording into raw file
    private val tasks = mutableMapOf<Long, RecordingTask>()

    init {
        File(saveDir).mkdirs()
        Timber.d("MicrophoneRecorder Recordings will be saved to $saveDir")
        encoder = AudioEncoder(AudioConfig.RECORDING_SAMPLE_RATE.toInt(), cacheDir)
    }

    /// Append new buffer to recording file
    fun recordMicBuffer(buffer: ShortArray, readSize: Int) {
        tasks[currentId]?.also {
            //Timber.d("${it.pathName} add buffer")
            it.recordMic(buffer, readSize)
        } ?: run {
            Timber.d("MicrophoneRecorder There is no audio for transcript $currentId")
        }
    }

    /// Append new buffer to recording file
    fun recordASRBuffer(buffer: ShortArray) {
        tasks[currentId]?.also {
            //Timber.d("${it.pathName} add buffer")
            it.recordASR(buffer)
        } ?: run {
            Timber.d("MicrophoneRecorder There is no audio for transcript $currentId")
        }
    }

    fun recordTranscript(transcript: String) {
        tasks[currentId]?.also {
            //Timber.d("${it.pathName} add buffer")
            it.recordTranscript(transcript)
        } ?: run {
            Timber.d("MicrophoneRecorder There is no transcript for $currentId")
        }
    }

    fun stop() {
        Timber.d("MicrophoneRecorder stop")
        val taskEntries = tasks.entries.toList()
        for((_, value) in taskEntries) {
            value.export()
        }
        currentId = 0
    }
    fun release() {
        Timber.d("MicrophoneRecorder release")
        val taskEntries = tasks.entries.toList()
        for((_, value) in taskEntries) {
            value.export()
        }

        tasks.clear()
        currentId = 0
    }

    /// Flush speech by decode raw recording into acc
    fun flushSpeech(newTranscript: String) {
        Timber.d("MicrophoneRecorder ${tasks.size} flushSpeech $newTranscript")
        val taskEntries = tasks.entries.toList()
        for ((id, task) in taskEntries) {
            if (task.isComplete()) {
                task.cleanUp()
                tasks.remove(id)
                Timber.d("MicrophoneRecorder remove task [$id]")
            } else {
                task.export()
            }
        }

        if(newTranscript.isEmpty()) {
            Timber.d("MicrophoneRecorder new transcript is empty, ignore")
            return
        }

        currentId = System.currentTimeMillis()
        val newPath = saveDir + "/${recordingId}_$currentId"
        tasks[currentId] = RecordingTask(Gson(), encoder, newPath, newTranscript)
        Timber.d("MicrophoneRecorder add new task [$currentId] $newPath, $newTranscript")
    }

    fun currentPath(): String {
        return tasks[currentId]?.pathName ?: ""
    }
}
