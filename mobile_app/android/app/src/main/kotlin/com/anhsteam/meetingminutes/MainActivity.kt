package com.anhsteam.meetingminutes

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.anhsteam.meetingminutes/native"
    private lateinit var recorderEngine: MeetingAudioRecorderEngine
    private var mediaPlayer: MediaPlayer? = null
    private var currentlyPlayingPath: String? = null

    private var speechRecognizer: SpeechRecognizer? = null
    private var isListeningSpeech: Boolean = false
    private var currentSpeechLocale: String = "vi-VN"
    private var latestPartialSpeech: String = ""
    private var latestFinalSpeech: String = ""
    private var speechErrorText: String = ""

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        recorderEngine = MeetingAudioRecorderEngine(applicationContext)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSystemStatus" -> {
                        val status = mapOf(
                            "micPermissionGranted" to hasMicPermission(),
                            "isRecording" to recorderEngine.isRecording,
                            "elapsedSeconds" to recorderEngine.getElapsedSeconds(),
                            "peakAmplitude" to recorderEngine.currentPeakAmplitude,
                            "roomGainBoost" to recorderEngine.roomGainBoost.toDouble(),
                            "currentRecordingPath" to (recorderEngine.currentFilePath ?: ""),
                            "currentlyPlayingPath" to (currentlyPlayingPath ?: ""),
                            "isListeningSpeech" to isListeningSpeech,
                            "currentSpeechLocale" to currentSpeechLocale,
                            "latestPartialSpeech" to latestPartialSpeech,
                            "latestFinalSpeech" to latestFinalSpeech,
                            "speechErrorText" to speechErrorText,
                            "deviceModel" to "${Build.MANUFACTURER} ${Build.MODEL}"
                        )
                        result.success(status)
                    }

                    "requestPermissions" -> {
                        requestRuntimePermissions()
                        result.success(true)
                    }

                    "updateRoomGain" -> {
                        val gain = call.argument<Double>("roomGainBoost")?.toFloat() ?: 2.5f
                        recorderEngine.roomGainBoost = gain.coerceIn(1.0f, 6.0f)
                        result.success(true)
                    }

                    "startMeetingRecording" -> {
                        if (!hasMicPermission()) {
                            requestRuntimePermissions()
                            result.error("NO_MIC_PERM", "Vui lòng cấp quyền Microphone để thu âm cuộc họp", null)
                            return@setMethodCallHandler
                        }
                        val title = call.argument<String>("meetingTitle") ?: "Hop_Giao_Ban"
                        val gain = call.argument<Double>("roomGainBoost")?.toFloat() ?: 2.5f
                        val path = recorderEngine.startRecording(title, gain)
                        result.success(path ?: "")
                    }

                    "stopMeetingRecording" -> {
                        val info = recorderEngine.stopRecording()
                        result.success(info)
                    }

                    "startVoiceDictation" -> {
                        if (!hasMicPermission()) {
                            requestRuntimePermissions()
                            result.error("NO_MIC_PERM", "Vui lòng cấp quyền Microphone", null)
                            return@setMethodCallHandler
                        }
                        if (recorderEngine.isRecording) {
                            result.error("BUSY_REC", "Đang thu âm WAV toàn cục. Hãy dùng nút Thêm Lượt Phát Biểu hoặc dừng thu WAV trước khi bật đọc chính tả trực tiếp.", null)
                            return@setMethodCallHandler
                        }
                        val locale = call.argument<String>("locale") ?: "vi-VN"
                        startMultilingualSpeechRecognition(locale)
                        result.success(true)
                    }

                    "stopVoiceDictation" -> {
                        stopMultilingualSpeechRecognition()
                        result.success(latestFinalSpeech)
                    }

                    "clearSpeechBuffer" -> {
                        latestPartialSpeech = ""
                        latestFinalSpeech = ""
                        speechErrorText = ""
                        result.success(true)
                    }

                    "listRecordings" -> {
                        result.success(recorderEngine.listSavedRecordings())
                    }

                    "listExportedDocx" -> {
                        result.success(recorderEngine.listExportedDocx())
                    }

                    "playRecording" -> {
                        val path = call.argument<String>("path") ?: ""
                        result.success(playAudioFile(path))
                    }

                    "stopPlayback" -> {
                        stopAudioPlayback()
                        result.success(true)
                    }

                    "deleteFile" -> {
                        val path = call.argument<String>("path") ?: ""
                        if (currentlyPlayingPath == path) {
                            stopAudioPlayback()
                        }
                        val f = File(path)
                        val deleted = if (f.exists()) f.delete() else false
                        result.success(deleted)
                    }

                    "generateMeetingDocx" -> {
                        try {
                            val jsonPayload = call.argument<String>("jsonPayload") ?: "{}"
                            val outInfo = DocxMinutesGenerator.generateDocxFile(
                                context = applicationContext,
                                outputDir = recorderEngine.getMinutesDir(),
                                jsonString = jsonPayload
                            )
                            result.success(outInfo)
                        } catch (e: Exception) {
                            result.error("ERR_DOCX", e.message ?: "Lỗi khi xuất tệp .docx", null)
                        }
                    }

                    "shareFile" -> {
                        val path = call.argument<String>("path") ?: ""
                        val mimeType = call.argument<String>("mimeType")
                            ?: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
                        val shared = shareFileViaProvider(path, mimeType)
                        result.success(shared)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Nhận diện giọng nói Đa ngôn ngữ:
     * - "vi-VN" (Tiếng Việt)
     * - "en-US" (Tiếng Anh - English)
     * - "de-DE" (Tiếng Đức - Deutsch)
     */
    private fun startMultilingualSpeechRecognition(localeCode: String) {
        runOnUiThread {
            try {
                stopMultilingualSpeechRecognition()
                currentSpeechLocale = localeCode
                latestPartialSpeech = ""
                speechErrorText = ""
                speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this).apply {
                    setRecognitionListener(object : RecognitionListener {
                        override fun onReadyForSpeech(params: Bundle?) {
                            isListeningSpeech = true
                        }

                        override fun onBeginningOfSpeech() {
                            isListeningSpeech = true
                        }

                        override fun onRmsChanged(rmsdB: Float) {}
                        override fun onBufferReceived(buffer: ByteArray?) {}

                        override fun onEndOfSpeech() {
                            isListeningSpeech = false
                        }

                        override fun onError(error: Int) {
                            isListeningSpeech = false
                            speechErrorText = "Mã trạng thái nhận diện ($localeCode): $error"
                        }

                        override fun onResults(results: Bundle?) {
                            isListeningSpeech = false
                            val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            if (!matches.isNullOrEmpty()) {
                                val recognized = matches[0].trim()
                                if (recognized.isNotEmpty()) {
                                    latestFinalSpeech = if (latestFinalSpeech.isEmpty()) {
                                        recognized
                                    } else {
                                        "$latestFinalSpeech. $recognized"
                                    }
                                }
                            }
                            latestPartialSpeech = ""
                        }

                        override fun onPartialResults(partialResults: Bundle?) {
                            val partial = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            if (!partial.isNullOrEmpty()) {
                                latestPartialSpeech = partial[0]
                            }
                        }

                        override fun onEvent(eventType: Int, params: Bundle?) {}
                    })
                }

                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeCode)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, localeCode)
                    putExtra(RecognizerIntent.EXTRA_ONLY_RETURN_LANGUAGE_PREFERENCE, localeCode)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                }
                speechRecognizer?.startListening(intent)
                isListeningSpeech = true
            } catch (e: Exception) {
                isListeningSpeech = false
                speechErrorText = e.message ?: "Thiết bị không hỗ trợ SpeechRecognizer"
            }
        }
    }

    private fun stopMultilingualSpeechRecognition() {
        runOnUiThread {
            try {
                speechRecognizer?.stopListening()
                speechRecognizer?.destroy()
            } catch (_: Exception) {
            }
            speechRecognizer = null
            isListeningSpeech = false
        }
    }

    private fun shareFileViaProvider(path: String, mimeType: String): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) return false
            val uri = FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.fileprovider",
                file
            )
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_SUBJECT, file.name)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val chooser = Intent.createChooser(shareIntent, "Chia sẻ Biên bản cuộc họp qua").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(chooser)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun playAudioFile(path: String): Boolean {
        return try {
            stopAudioPlayback()
            val file = File(path)
            if (!file.exists()) return false
            mediaPlayer = MediaPlayer().apply {
                setDataSource(file.absolutePath)
                setOnCompletionListener {
                    currentlyPlayingPath = null
                }
                prepare()
                start()
            }
            currentlyPlayingPath = path
            true
        } catch (_: Exception) {
            currentlyPlayingPath = null
            false
        }
    }

    private fun stopAudioPlayback() {
        try {
            mediaPlayer?.stop()
        } catch (_: Exception) {
        }
        try {
            mediaPlayer?.release()
        } catch (_: Exception) {
        }
        mediaPlayer = null
        currentlyPlayingPath = null
    }

    private fun hasMicPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestRuntimePermissions() {
        val perms = mutableListOf(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            perms.add(Manifest.permission.READ_MEDIA_AUDIO)
            perms.add(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            perms.add(Manifest.permission.READ_EXTERNAL_STORAGE)
            if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P) {
                perms.add(Manifest.permission.WRITE_EXTERNAL_STORAGE)
            }
        }
        ActivityCompat.requestPermissions(this, perms.toTypedArray(), 2001)
    }

    override fun onDestroy() {
        stopAudioPlayback()
        stopMultilingualSpeechRecognition()
        super.onDestroy()
    }
}
