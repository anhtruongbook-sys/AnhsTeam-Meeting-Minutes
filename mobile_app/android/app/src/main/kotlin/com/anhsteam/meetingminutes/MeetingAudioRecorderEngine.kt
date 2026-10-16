package com.anhsteam.meetingminutes

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.sign

/**
 * Động cơ Thu âm Phòng họp Độ nét cao (16kHz 16-bit PCM WAV) kết hợp DSP Khuếch đại Khoảng cách xa (Far-Field Room Gain).
 * - Tối ưu hóa cho phòng họp có người ngồi xa điện thoại (1.5m - 4.5m).
 * - Khuếch đại thích ứng (Adaptive Far-Field Boost) cho người phát biểu ở xa và giới hạn mềm (Soft Limiter) cho người ngồi gần.
 */
class MeetingAudioRecorderEngine(private val context: Context) {

    @Volatile
    var isRecording: Boolean = false
        private set

    var currentFilePath: String? = null
        private set

    var currentMeetingTitle: String = "Cuoc_Hop"
        private set

    var currentPeakAmplitude: Int = 0
        private set

    var roomGainBoost: Float = 2.5f

    private var recordingThread: Thread? = null
    private var startTimeMs: Long = 0L

    fun getRecordingsDir(): File {
        val dir = File(context.getExternalFilesDir(null), "Meeting_Recordings")
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir
    }

    fun getMinutesDir(): File {
        val dir = File(context.getExternalFilesDir(null), "Exported_Minutes")
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir
    }

    fun getElapsedSeconds(): Long {
        if (!isRecording || startTimeMs == 0L) return 0L
        return ((System.currentTimeMillis() - startTimeMs) / 1000L).coerceAtLeast(0L)
    }

    @Synchronized
    fun startRecording(meetingTitle: String, gainBoost: Float = 2.5f): String? {
        if (isRecording) return currentFilePath

        roomGainBoost = gainBoost.coerceIn(1.0f, 6.0f)
        val sampleRate = 16000
        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        val minBufSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        if (minBufSize <= 0) return null

        val bufferSize = minBufSize * 4

        val sources = intArrayOf(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            MediaRecorder.AudioSource.MIC,
            MediaRecorder.AudioSource.CAMCORDER
        )

        var recorder: AudioRecord? = null
        for (src in sources) {
            try {
                val candidate = AudioRecord(src, sampleRate, channelConfig, audioFormat, bufferSize)
                if (candidate.state == AudioRecord.STATE_INITIALIZED) {
                    recorder = candidate
                    break
                } else {
                    candidate.release()
                }
            } catch (_: Exception) {
            }
        }

        if (recorder == null) return null

        try {
            val sessionId = recorder.audioSessionId
            if (AutomaticGainControl.isAvailable()) {
                AutomaticGainControl.create(sessionId)?.enabled = true
            }
            if (NoiseSuppressor.isAvailable()) {
                NoiseSuppressor.create(sessionId)?.enabled = true
            }
        } catch (_: Exception) {
        }

        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val safeTitle = meetingTitle.replace(Regex("[^a-zA-Z0-9_-]"), "_").take(32).ifEmpty { "Hop" }
        val outFile = File(getRecordingsDir(), "Hop_${safeTitle}_${timestamp}.wav")

        currentFilePath = outFile.absolutePath
        currentMeetingTitle = meetingTitle
        startTimeMs = System.currentTimeMillis()
        isRecording = true

        val activeRecorder = recorder
        recordingThread = Thread {
            writeWavWithFarFieldDsp(activeRecorder, outFile, sampleRate)
        }.apply {
            priority = Thread.MAX_PRIORITY
            start()
        }

        return outFile.absolutePath
    }

    @Synchronized
    fun stopRecording(): Map<String, Any?>? {
        if (!isRecording) return null
        val elapsed = getElapsedSeconds().coerceAtLeast(1L)
        isRecording = false
        try {
            recordingThread?.join(2500)
        } catch (_: InterruptedException) {
        }
        recordingThread = null
        currentPeakAmplitude = 0
        startTimeMs = 0L

        val path = currentFilePath ?: return null
        val file = File(path)
        if (!file.exists()) return null

        val sha256 = computeSha256(file)
        return mapOf(
            "path" to file.absolutePath,
            "name" to file.name,
            "title" to currentMeetingTitle,
            "sizeBytes" to file.length(),
            "durationSec" to elapsed,
            "sha256" to sha256
        )
    }

    private fun writeWavWithFarFieldDsp(
        recorder: AudioRecord,
        outFile: File,
        sampleRate: Int
    ) {
        val pcmBuffer = ShortArray(2048)
        val byteBuffer = ByteArray(pcmBuffer.size * 2)
        var totalAudioBytes = 0L

        try {
            FileOutputStream(outFile).use { fos ->
                fos.write(ByteArray(44))
                recorder.startRecording()

                while (isRecording) {
                    val readCount = recorder.read(pcmBuffer, 0, pcmBuffer.size)
                    if (readCount > 0) {
                        var maxAmp = 0
                        val gain = roomGainBoost
                        for (i in 0 until readCount) {
                            val rawSample = pcmBuffer[i].toInt()
                            val absVal = abs(rawSample)
                            if (absVal > maxAmp) maxAmp = absVal

                            val processedSample: Int = when {
                                absVal < 65 -> rawSample
                                absVal <= 5500 -> {
                                    (rawSample * gain).toInt().coerceIn(-28000, 28000)
                                }
                                else -> {
                                    val base = 5500f * gain
                                    val excess = (absVal - 5500).toFloat()
                                    val compressed = base + excess * 0.45f
                                    (sign(rawSample.toFloat()) * min(32000f, compressed)).toInt()
                                }
                            }

                            val clamped = processedSample.coerceIn(-32767, 32767).toShort()
                            byteBuffer[i * 2] = (clamped.toInt() and 0x00FF).toByte()
                            byteBuffer[i * 2 + 1] = ((clamped.toInt() shr 8) and 0x00FF).toByte()
                        }
                        currentPeakAmplitude = maxAmp
                        val bytesToWrite = readCount * 2
                        fos.write(byteBuffer, 0, bytesToWrite)
                        totalAudioBytes += bytesToWrite
                    }
                }
            }
        } catch (_: Exception) {
        } finally {
            try {
                recorder.stop()
            } catch (_: Exception) {
            }
            try {
                recorder.release()
            } catch (_: Exception) {
            }
            if (outFile.exists() && totalAudioBytes > 0) {
                updateWavHeader(outFile, totalAudioBytes, sampleRate, 1, 16)
            }
        }
    }

    private fun updateWavHeader(
        wavFile: File,
        totalAudioLen: Long,
        sampleRate: Int,
        channels: Int,
        bitsPerSample: Int
    ) {
        val totalDataLen = totalAudioLen + 36
        val byteRate = (sampleRate * channels * bitsPerSample / 8).toLong()
        val header = ByteArray(44)

        header[0] = 'R'.code.toByte()
        header[1] = 'I'.code.toByte()
        header[2] = 'F'.code.toByte()
        header[3] = 'F'.code.toByte()
        writeIntLE(header, 4, totalDataLen.toInt())
        header[8] = 'W'.code.toByte()
        header[9] = 'A'.code.toByte()
        header[10] = 'V'.code.toByte()
        header[11] = 'E'.code.toByte()
        header[12] = 'f'.code.toByte()
        header[13] = 'm'.code.toByte()
        header[14] = 't'.code.toByte()
        header[15] = ' '.code.toByte()
        writeIntLE(header, 16, 16)
        header[20] = 1
        header[21] = 0
        header[22] = channels.toByte()
        header[23] = 0
        writeIntLE(header, 24, sampleRate)
        writeIntLE(header, 28, byteRate.toInt())
        header[32] = (channels * bitsPerSample / 8).toByte()
        header[33] = 0
        header[34] = bitsPerSample.toByte()
        header[35] = 0
        header[36] = 'd'.code.toByte()
        header[37] = 'a'.code.toByte()
        header[38] = 't'.code.toByte()
        header[39] = 'a'.code.toByte()
        writeIntLE(header, 40, totalAudioLen.toInt())

        RandomAccessFile(wavFile, "rw").use { raf ->
            raf.seek(0)
            raf.write(header)
        }
    }

    private fun writeIntLE(buffer: ByteArray, offset: Int, value: Int) {
        buffer[offset] = (value and 0xFF).toByte()
        buffer[offset + 1] = ((value shr 8) and 0xFF).toByte()
        buffer[offset + 2] = ((value shr 16) and 0xFF).toByte()
        buffer[offset + 3] = ((value shr 24) and 0xFF).toByte()
    }

    fun listSavedRecordings(): List<Map<String, Any>> {
        val files = getRecordingsDir().listFiles { f -> f.isFile && f.name.endsWith(".wav", true) }
            ?.sortedByDescending { it.lastModified() }
            ?: emptyList()

        val fmt = SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.getDefault())
        return files.map { f ->
            val sha = computeSha256(f)
            val durationEstSec = ((f.length() - 44L).coerceAtLeast(0L) / 32000L).coerceAtLeast(1L)
            mapOf(
                "path" to f.absolutePath,
                "name" to f.name,
                "sizeKB" to (f.length() / 1024L),
                "durationSec" to durationEstSec,
                "dateFormatted" to fmt.format(Date(f.lastModified())),
                "sha256Short" to sha.take(12)
            )
        }
    }

    fun listExportedDocx(): List<Map<String, Any>> {
        val files = getMinutesDir().listFiles { f -> f.isFile && f.name.endsWith(".docx", true) }
            ?.sortedByDescending { it.lastModified() }
            ?: emptyList()

        val fmt = SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.getDefault())
        return files.map { f ->
            mapOf(
                "path" to f.absolutePath,
                "name" to f.name,
                "sizeKB" to (f.length() / 1024L).coerceAtLeast(1L),
                "dateFormatted" to fmt.format(Date(f.lastModified()))
            )
        }
    }

    fun computeSha256(file: File): String {
        return try {
            val digest = MessageDigest.getInstance("SHA-256")
            FileInputStream(file).use { fis ->
                val buf = ByteArray(16384)
                var n: Int
                while (fis.read(buf).also { n = it } != -1) {
                    digest.update(buf, 0, n)
                }
            }
            digest.digest().joinToString("") { "%02x".format(it) }
        } catch (_: Exception) {
            ""
        }
    }
}
