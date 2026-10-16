package com.anhsteam.meetingminutes

import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.FileOutputStream
import java.io.InputStreamReader
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.ZipInputStream

/**
 * Bộ Nhập & Phân Tích Tệp Có Sẵn Trong Máy (Audio / TXT / SRT / VTT / JSON / DOCX)
 * để tự động chuyển đổi thành dữ liệu Biên bản cuộc họp đa ngôn ngữ (Việt - Anh - Đức).
 */
object ExistingFileImporter {

    private val AUDIO_EXTENSIONS = setOf("wav", "m4a", "mp3", "aac", "ogg", "flac", "amr", "3gp", "opus")

    fun importFromUri(
        context: Context,
        uri: Uri,
        recorderEngine: MeetingAudioRecorderEngine
    ): Map<String, Any> {
        val displayName = queryDisplayName(context, uri) ?: "Tap_Tin_Nhap_${System.currentTimeMillis()}"
        val ext = displayName.substringAfterLast('.', "").lowercase(Locale.US)
        val baseTitle = displayName.substringBeforeLast('.').replace("_", " ").trim()

        return if (AUDIO_EXTENSIONS.contains(ext)) {
            importAudioUri(context, uri, displayName, baseTitle, recorderEngine)
        } else if (ext == "docx") {
            val paragraphs = extractParagraphsFromDocxUri(context, uri)
            parseLinesIntoMeetingStructure(displayName, baseTitle, paragraphs)
        } else if (ext == "json") {
            val rawJson = readTextFromUri(context, uri)
            parseJsonIntoMeetingStructure(displayName, baseTitle, rawJson)
        } else {
            val rawText = readTextFromUri(context, uri)
            val lines = rawText.lines()
            parseLinesIntoMeetingStructure(displayName, baseTitle, lines)
        }
    }

    private fun importAudioUri(
        context: Context,
        uri: Uri,
        displayName: String,
        baseTitle: String,
        recorderEngine: MeetingAudioRecorderEngine
    ): Map<String, Any> {
        val normalizedName = java.text.Normalizer.normalize(displayName, java.text.Normalizer.Form.NFC)
        val safeName = normalizedName.replace(Regex("[^\\p{L}\\p{M}\\p{N}._-]"), "_")
        val destFile = File(recorderEngine.getRecordingsDir(), safeName)

        context.contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(destFile).use { output ->
                input.copyTo(output)
            }
        }

        val durationSec = recorderEngine.getAudioDurationSeconds(destFile)
        val sha = recorderEngine.computeSha256(destFile)
        val fmt = SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.getDefault())
        val dateStr = fmt.format(Date(destFile.lastModified()))

        return mapOf(
            "fileCategory" to "AUDIO",
            "name" to destFile.name,
            "originalName" to displayName,
            "path" to destFile.absolutePath,
            "sizeKB" to (destFile.length() / 1024L).coerceAtLeast(1L),
            "durationSec" to durationSec,
            "dateFormatted" to dateStr,
            "sha256Short" to sha.take(12),
            "suggestedSubject" to "Biên bản cuộc họp (Trích xuất từ tệp âm thanh: $baseTitle)"
        )
    }

    private fun extractParagraphsFromDocxUri(context: Context, uri: Uri): List<String> {
        val result = mutableListOf<String>()
        try {
            context.contentResolver.openInputStream(uri)?.use { fis ->
                ZipInputStream(fis).use { zis ->
                    var entry = zis.nextEntry
                    while (entry != null) {
                        if (entry.name == "word/document.xml") {
                            val xml = zis.bufferedReader(Charsets.UTF_8).readText()
                            // Tách theo từng thẻ <w:p ...>...</w:p>
                            val pBlocks = xml.split("</w:p>")
                            val tRegex = Regex("<w:t[^>]*>([^<]*)</w:t>")
                            for (block in pBlocks) {
                                val sb = StringBuilder()
                                for (m in tRegex.findAll(block)) {
                                    sb.append(m.groupValues[1])
                                }
                                val line = decodeXmlEntities(sb.toString()).trim()
                                if (line.isNotEmpty()) {
                                    result.add(line)
                                }
                            }
                            break
                        }
                        entry = zis.nextEntry
                    }
                }
            }
        } catch (_: Exception) {
        }
        return result
    }

    private fun decodeXmlEntities(s: String): String {
        return s
            .replace("&amp;", "&")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&quot;", "\"")
            .replace("&apos;", "'")
    }

    private fun readTextFromUri(context: Context, uri: Uri): String {
        return try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                BufferedReader(InputStreamReader(input, Charsets.UTF_8)).readText()
            } ?: ""
        } catch (_: Exception) {
            ""
        }
    }

    private fun parseJsonIntoMeetingStructure(
        displayName: String,
        baseTitle: String,
        rawJson: String
    ): Map<String, Any> {
        val turns = mutableListOf<Map<String, String>>()
        val conclusions = mutableListOf<String>()
        val actions = mutableListOf<Map<String, String>>()
        var subject = "Biên bản cuộc họp (Nhập từ tệp: $baseTitle)"

        try {
            val obj = JSONObject(rawJson)
            if (obj.has("meetingSubject")) {
                subject = obj.optString("meetingSubject", subject)
            }
            // Trường hợp 1: File JSON gỡ băng từ transcribe_and_diarize.py (có mảng "segments")
            val segs = obj.optJSONArray("segments")
            if (segs != null) {
                for (i in 0 until segs.length()) {
                    val s = segs.optJSONObject(i) ?: continue
                    val text = s.optString("text", "").trim()
                    if (text.isEmpty()) continue
                    val ts = s.optString("timestamp", "00:00:00")
                    val speaker = s.optString("speaker", "Đại biểu #${i + 1}")
                    val lang = s.optString("lang", detectLanguageTag(text))
                    turns.add(
                        mapOf(
                            "speaker" to speaker,
                            "lang" to lang,
                            "timestamp" to ts,
                            "content" to text,
                            "translation" to ""
                        )
                    )
                }
            }
            // Trường hợp 2: File JSON cấu trúc biên bản (có mảng "speakerTurns")
            val spTurns = obj.optJSONArray("speakerTurns")
            if (spTurns != null) {
                for (i in 0 until spTurns.length()) {
                    val t = spTurns.optJSONObject(i) ?: continue
                    val content = t.optString("content", "").trim()
                    if (content.isEmpty()) continue
                    turns.add(
                        mapOf(
                            "speaker" to t.optString("speaker", "Đại biểu"),
                            "lang" to t.optString("lang", detectLanguageTag(content)),
                            "timestamp" to t.optString("timestamp", "00:00:00"),
                            "content" to content,
                            "translation" to t.optString("translation", "")
                        )
                    )
                }
            }
            val concArr = obj.optJSONArray("conclusions")
            if (concArr != null) {
                for (i in 0 until concArr.length()) {
                    val c = concArr.optString(i, "").trim()
                    if (c.isNotEmpty()) conclusions.add(c)
                }
            }
            val actArr = obj.optJSONArray("actionItems")
            if (actArr != null) {
                for (i in 0 until actArr.length()) {
                    val a = actArr.optJSONObject(i) ?: continue
                    actions.add(
                        mapOf(
                            "task" to a.optString("task", ""),
                            "assignee" to a.optString("assignee", "Bộ phận chuyên môn"),
                            "coordinator" to a.optString("coordinator", "Các đơn vị"),
                            "deadline" to a.optString("deadline", "Theo kế hoạch")
                        )
                    )
                }
            }
        } catch (_: Exception) {
            return parseLinesIntoMeetingStructure(displayName, baseTitle, rawJson.lines())
        }

        return mapOf(
            "fileCategory" to "DOCUMENT",
            "name" to displayName,
            "suggestedSubject" to subject,
            "turns" to turns,
            "conclusions" to conclusions,
            "actionItems" to actions
        )
    }

    /**
     * Phân tích tệp văn bản (.txt, .srt, .vtt, .md, .docx) thành các Lượt phát biểu, Kết luận và Nhiệm vụ.
     */
    private fun parseLinesIntoMeetingStructure(
        displayName: String,
        baseTitle: String,
        rawLines: List<String>
    ): Map<String, Any> {
        val turns = mutableListOf<Map<String, String>>()
        val conclusions = mutableListOf<String>()
        val actions = mutableListOf<Map<String, String>>()

        var currentTime = "00:00:00"
        val srtTimeRegex = Regex("(\\d{2}:\\d{2}:\\d{2})[,\\.]?\\d*\\s*-->\\s*(\\d{2}:\\d{2}:\\d{2})")
        val bracketTimeSpeakerRegex = Regex("^\\[?(\\d{1,2}:\\d{2}(?::\\d{2})?)\\]?\\s*(?:\\[([A-Z]{2})\\])?\\s*([^:]{2,40}):\\s*(.+)$")
        val speakerColonRegex = Regex("^([^:]{2,45}):\\s*(.+)$")

        var inConclusionSection = false

        for (raw in rawLines) {
            val line = raw.trim()
            if (line.isEmpty() || line == "WEBVTT" || line.matches(Regex("^\\d+$"))) {
                continue
            }

            // Kiểm tra dòng thời gian của file phụ đề .SRT / .VTT
            val srtMatch = srtTimeRegex.find(line)
            if (srtMatch != null) {
                currentTime = srtMatch.groupValues[1]
                continue
            }

            // Kiểm tra tiêu đề mục Kết luận
            if (line.uppercase(Locale.getDefault()).contains("KẾT LUẬN") ||
                line.uppercase(Locale.getDefault()).contains("CONCLUSIONS") ||
                line.uppercase(Locale.getDefault()).contains("BESCHLÜSSE")
            ) {
                inConclusionSection = true
                continue
            }

            if (inConclusionSection && (line.startsWith("-") || line.startsWith("•") || line.length > 15)) {
                val cleanConc = line.removePrefix("-").removePrefix("•").trim()
                if (cleanConc.isNotEmpty()) {
                    conclusions.add(cleanConc)
                    continue
                }
            }

            // Kiểm tra mẫu: [00:02:15] [EN] Speaker Name: Content
            val bm = bracketTimeSpeakerRegex.find(line)
            if (bm != null) {
                val ts = bm.groupValues[1]
                val explicitLang = bm.groupValues[2]
                val spk = bm.groupValues[3].trim()
                val content = bm.groupValues[4].trim()
                val lang = explicitLang.ifEmpty { detectLanguageTag(content) }
                turns.add(
                    mapOf(
                        "speaker" to spk,
                        "lang" to lang,
                        "timestamp" to ts,
                        "content" to content,
                        "translation" to ""
                    )
                )
                continue
            }

            // Kiểm tra mẫu: Speaker Name: Content
            val sm = speakerColonRegex.find(line)
            if (sm != null && !line.startsWith("http", true) && !line.startsWith("Số:", true)) {
                val spk = sm.groupValues[1].removePrefix("-").trim()
                val content = sm.groupValues[2].trim()
                val lang = detectLanguageTag(content)
                turns.add(
                    mapOf(
                        "speaker" to spk,
                        "lang" to lang,
                        "timestamp" to currentTime,
                        "content" to content,
                        "translation" to ""
                    )
                )
                continue
            }

            // Dòng văn bản thông thường (gỡ băng liên tục hoặc SRT)
            val cleanLine = line.removePrefix("-").removePrefix("•").trim()
            if (cleanLine.length >= 4) {
                val lang = detectLanguageTag(cleanLine)
                turns.add(
                    mapOf(
                        "speaker" to "Nội dung trích xuất (${turns.size + 1})",
                        "lang" to lang,
                        "timestamp" to currentTime,
                        "content" to cleanLine,
                        "translation" to ""
                    )
                )
            }
        }

        if (conclusions.isEmpty() && turns.isNotEmpty()) {
            conclusions.add("Thống nhất ghi nhận toàn bộ nội dung từ tệp dữ liệu đầu vào ($displayName) làm cơ sở lập biên bản cuộc họp.")
        }

        return mapOf(
            "fileCategory" to "DOCUMENT",
            "name" to displayName,
            "suggestedSubject" to "Về việc tổng hợp nội dung cuộc họp từ tệp: $baseTitle",
            "turns" to turns,
            "conclusions" to conclusions,
            "actionItems" to actions
        )
    }

    /**
     * Tự động nhận diện ngôn ngữ câu phát biểu: VI (Tiếng Việt), DE (Tiếng Đức), hoặc EN (Tiếng Anh).
     */
    fun detectLanguageTag(text: String): String {
        val lower = text.lowercase(Locale.getDefault())
        // Dấu thanh đặc trưng của Tiếng Việt
        val viChars = "ăâđêôơưáàảãạắằẳẵặấầẩẫậéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ"
        if (lower.any { viChars.contains(it) }) {
            return "VI"
        }
        // Ký tự Umlaut / Eszett hoặc từ khóa phổ biến trong Tiếng Đức
        val deChars = "äöüß"
        if (lower.any { deChars.contains(it) } ||
            Regex("\\b(und|der|die|das|wir|ist|für|nicht|mit|auf|besprechung|projekt)\\b").containsMatchIn(lower)
        ) {
            return "DE"
        }
        return "EN"
    }

    private fun queryDisplayName(context: Context, uri: Uri): String? {
        var cursor: Cursor? = null
        return try {
            cursor = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            if (cursor != null && cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) cursor.getString(idx) else null
            } else null
        } catch (_: Exception) {
            null
        } finally {
            cursor?.close()
        }
    }
}
