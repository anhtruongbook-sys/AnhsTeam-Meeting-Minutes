package com.anhsteam.meetingminutes

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * Bộ Kết xuất Tệp Word OpenXML (.docx) Đa Ngôn Ngữ (Tiếng Việt - Tiếng Anh - Tiếng Đức)
 * Chuẩn Nghị định 30/2020/NĐ-CP, Rule 9 (Full Bilingual/Multilingual Parity) & Rule 11:
 * - Hỗ trợ 4 chế độ ngôn ngữ biên bản:
 *   1. "VI": Chuẩn Hành chính Tiếng Việt (Nghị định 30/2020/NĐ-CP)
 *   2. "VI_EN": Song ngữ đối sánh Việt - Anh (Vietnamese - English)
 *   3. "VI_DE": Song ngữ đối sánh Việt - Đức (Vietnamesisch - Deutsch)
 *   4. "VI_EN_DE": Đa ngữ đối sánh Việt - Anh - Đức (Vietnamese - English - German)
 * - Khổ giấy A4 (11906 x 16838 dxa), Lề: Trên 20mm (1134), Dưới 20mm (1134), Trái 30mm (1701), Phải 15mm (850).
 * - Phông chữ Times New Roman 100%, màu chữ Đen tuyền (#000000) 100%.
 * - Tuyệt đối KHÔNG dùng ký tự xuống dòng mềm (<w:br/>) trong đoạn văn căn đều hai bên (<w:jc w:val="both"/>).
 */
object DocxMinutesGenerator {

    private data class LocalizedLabels(
        val defaultDocTitle: String,
        val section1Title: String,
        val startTimeLabel: String,
        val venueLabel: String,
        val participantsLabel: String,
        val chairLabel: String,
        val secLabel: String,
        val memberLabel: String,
        val section2Title: String,
        val speakerPrefix: String,
        val timeMarkerLabel: String,
        val translationPrefix: String,
        val section3Title: String,
        val actionTableIntro: String,
        val colStt: String,
        val colTask: String,
        val colAssignee: String,
        val colCoord: String,
        val colDeadline: String,
        val closingSentencePrefix: String,
        val closingSentenceSuffix: String,
        val sigSecretaryTitle: String,
        val sigSecretaryHint: String,
        val sigChairTitle: String,
        val sigChairHint: String
    )

    private fun getLabelsForMode(mode: String): LocalizedLabels {
        return when (mode) {
            "VI_EN" -> LocalizedLabels(
                defaultDocTitle = "BIÊN BẢN CUỘC HỌP / MEETING MINUTES",
                section1Title = "I. THỜI GIAN, ĐỊA ĐIỂM VÀ THÀNH PHẦN THAM DỰ / TIME, VENUE AND PARTICIPANTS",
                startTimeLabel = "1. Thời gian bắt đầu (Start Time)",
                venueLabel = "2. Địa điểm / Hình thức họp (Venue / Format)",
                participantsLabel = "3. Thành phần tham dự (Participants):",
                chairLabel = "Chủ trì cuộc họp (Chairperson)",
                secLabel = "Thư ký cuộc họp (Secretary)",
                memberLabel = "Thành viên tham dự (Attendee)",
                section2Title = "II. NỘI DUNG DIỄN BIẾN CUỘC HỌP / MEETING PROCEEDINGS & DISCUSSIONS",
                speakerPrefix = "Ý kiến phát biểu của (Statement by)",
                timeMarkerLabel = "Mốc thời gian / Timestamp",
                translationPrefix = "Bản dịch / Translation",
                section3Title = "III. KẾT LUẬN VÀ PHÂN CÔNG NHIỆM VỤ / CONCLUSIONS AND ACTION ITEMS",
                actionTableIntro = "Bảng phân công nhiệm vụ triển khai / Action Items Assignment Table:",
                colStt = "TT / No.",
                colTask = "Nội dung công việc / Task Description",
                colAssignee = "Chủ trì / Assignee",
                colCoord = "Phối hợp / Support",
                colDeadline = "Thời hạn / Deadline",
                closingSentencePrefix = "Cuộc họp kết thúc vào lúc (The meeting adjourned at) ",
                closingSentenceSuffix = ". Biên bản này đã được thông qua trước toàn thể thành viên dự họp và lập thành văn bản lưu hồ sơ / These minutes have been reviewed and approved by the participants for official record./.",
                sigSecretaryTitle = "THƯ KÝ CUỘC HỌP / SECRETARY",
                sigSecretaryHint = "(Ký và ghi rõ họ tên / Sign and print full name)",
                sigChairTitle = "CHỦ TRÌ CUỘC HỌP / CHAIRPERSON",
                sigChairHint = "(Ký, ghi rõ họ tên và đóng dấu / Sign, print full name and seal)"
            )
            "VI_DE" -> LocalizedLabels(
                defaultDocTitle = "BIÊN BẢN CUỘC HỌP / SITZUNGSPROTOKOLL",
                section1Title = "I. THỜI GIAN, ĐỊA ĐIỂM VÀ THÀNH PHẦN THAM DỰ / ZEIT, ORT UND TEILNEHMER",
                startTimeLabel = "1. Thời gian bắt đầu (Beginn)",
                venueLabel = "2. Địa điểm / Hình thức họp (Ort / Format)",
                participantsLabel = "3. Thành phần tham dự (Teilnehmer):",
                chairLabel = "Chủ trì cuộc họp (Sitzungsleitung)",
                secLabel = "Thư ký cuộc họp (Protokollführung)",
                memberLabel = "Thành viên tham dự (Teilnehmer/in)",
                section2Title = "II. NỘI DUNG DIỄN BIẾN CUỘC HỌP / BESPRECHUNGSINHALT UND DISKUSSION",
                speakerPrefix = "Ý kiến phát biểu của (Wortbeitrag von)",
                timeMarkerLabel = "Mốc thời gian / Zeitstempel",
                translationPrefix = "Bản dịch / Übersetzung",
                section3Title = "III. KẾT LUẬN VÀ PHÂN CÔNG NHIỆM VỤ / BESCHLÜSSE UND AUFGABENVERTEILUNG",
                actionTableIntro = "Bảng phân công nhiệm vụ triển khai / Aufgabenverteilungsplan:",
                colStt = "TT / Nr.",
                colTask = "Nội dung công việc / Aufgabenbeschreibung",
                colAssignee = "Chủ trì / Verantwortlich",
                colCoord = "Phối hợp / Koordination",
                colDeadline = "Thời hạn / Frist",
                closingSentencePrefix = "Cuộc họp kết thúc vào lúc (Ende der Sitzung um) ",
                closingSentenceSuffix = ". Biên bản này đã được thông qua trước toàn thể thành viên dự họp và lập thành văn bản lưu hồ sơ / Dieses Protokoll wurde von den Teilnehmern genehmigt und zu den Akten genommen./.",
                sigSecretaryTitle = "THƯ KÝ CUỘC HỌP / PROTOKOLLFÜHRER(IN)",
                sigSecretaryHint = "(Ký và ghi rõ họ tên / Unterschrift und vollständiger Name)",
                sigChairTitle = "CHỦ TRÌ CUỘC HỌP / SITZUNGSLEITER(IN)",
                sigChairHint = "(Ký, ghi rõ họ tên và đóng dấu / Unterschrift, Name und Stempel)"
            )
            "VI_EN_DE" -> LocalizedLabels(
                defaultDocTitle = "BIÊN BẢN CUỘC HỌP / MEETING MINUTES / SITZUNGSPROTOKOLL",
                section1Title = "I. THỜI GIAN, ĐỊA ĐIỂM & THÀNH PHẦN / TIME, VENUE & PARTICIPANTS / ZEIT, ORT & TEILNEHMER",
                startTimeLabel = "1. Thời gian bắt đầu (Start Time / Beginn)",
                venueLabel = "2. Địa điểm / Hình thức (Venue / Ort & Format)",
                participantsLabel = "3. Thành phần tham dự (Participants / Teilnehmer):",
                chairLabel = "Chủ trì (Chairperson / Sitzungsleitung)",
                secLabel = "Thư ký (Secretary / Protokollführung)",
                memberLabel = "Thành viên (Attendee / Teilnehmer/in)",
                section2Title = "II. NỘI DUNG CUỘC HỌP / MEETING PROCEEDINGS / BESPRECHUNGSINHALT",
                speakerPrefix = "Ý kiến phát biểu của (Statement by / Wortbeitrag von)",
                timeMarkerLabel = "Mốc thời gian / Time / Zeit",
                translationPrefix = "Đối sánh ngôn ngữ / Translation / Übersetzung",
                section3Title = "III. KẾT LUẬN & PHÂN CÔNG NHIỆM VỤ / CONCLUSIONS & ACTIONS / BESCHLÜSSE & AUFGABEN",
                actionTableIntro = "Bảng phân công nhiệm vụ / Action Items / Aufgabenverteilung:",
                colStt = "TT / No. / Nr.",
                colTask = "Nội dung công việc / Task / Aufgabe",
                colAssignee = "Chủ trì / Assignee / Verantwortlich",
                colCoord = "Phối hợp / Support / Koordination",
                colDeadline = "Thời hạn / Deadline / Frist",
                closingSentencePrefix = "Cuộc họp kết thúc vào lúc (Adjourned at / Ende um) ",
                closingSentenceSuffix = ". Biên bản này đã được thông qua và lưu hồ sơ / Approved by all participants / Von allen Teilnehmern genehmigt./.",
                sigSecretaryTitle = "THƯ KÝ / SECRETARY / PROTOKOLLFÜHRUNG",
                sigSecretaryHint = "(Ký, ghi rõ họ tên / Sign & Full Name / Unterschrift & Name)",
                sigChairTitle = "CHỦ TRÌ / CHAIRPERSON / SITZUNGSLEITUNG",
                sigChairHint = "(Ký, ghi rõ họ tên & đóng dấu / Sign & Seal / Unterschrift & Stempel)"
            )
            else -> LocalizedLabels(
                defaultDocTitle = "BIÊN BẢN CUỘC HỌP",
                section1Title = "I. THỜI GIAN, ĐỊA ĐIỂM VÀ THÀNH PHẦN THAM DỰ",
                startTimeLabel = "1. Thời gian bắt đầu",
                venueLabel = "2. Địa điểm / Hình thức họp",
                participantsLabel = "3. Thành phần tham dự:",
                chairLabel = "Chủ trì cuộc họp",
                secLabel = "Thư ký cuộc họp",
                memberLabel = "Thành viên tham dự",
                section2Title = "II. NỘI DUNG DIỄN BIẾN CUỘC HỌP",
                speakerPrefix = "Ý kiến phát biểu của",
                timeMarkerLabel = "Mốc thời gian",
                translationPrefix = "Dịch nghĩa / Ghi chú song ngữ",
                section3Title = "III. KẾT LUẬN CUỘC HỌP VÀ PHÂN CÔNG NHIỆM VỤ",
                actionTableIntro = "Bảng phân công nhiệm vụ triển khai:",
                colStt = "TT",
                colTask = "Nội dung công việc",
                colAssignee = "Chủ trì thực hiện",
                colCoord = "Phối hợp",
                colDeadline = "Thời hạn",
                closingSentencePrefix = "Cuộc họp kết thúc vào lúc ",
                closingSentenceSuffix = ". Biên bản này đã được thông qua trước toàn thể thành viên dự họp và lập thành văn bản lưu hồ sơ./.",
                sigSecretaryTitle = "THƯ KÝ CUỘC HỌP",
                sigSecretaryHint = "(Ký và ghi rõ họ tên)",
                sigChairTitle = "CHỦ TRÌ CUỘC HỌP",
                sigChairHint = "(Ký, ghi rõ họ tên và đóng dấu nếu có)"
            )
        }
    }

    private fun xmlEscape(input: String): String {
        val clean = input.replace("\r", " ").replace("\n", " ").trim()
        return clean
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;")
            .replace("'", "&apos;")
    }

    private fun buildRunXml(
        text: String,
        halfPtSize: Int = 26,
        bold: Boolean = false,
        italic: Boolean = false,
        underline: Boolean = false
    ): String {
        val sb = StringBuilder()
        sb.append("<w:r><w:rPr>")
        sb.append("<w:rFonts w:ascii=\"Times New Roman\" w:hAnsi=\"Times New Roman\" w:cs=\"Times New Roman\" w:eastAsia=\"Times New Roman\"/>")
        if (bold) sb.append("<w:b/><w:bCs/>")
        if (italic) sb.append("<w:i/><w:iCs/>")
        if (underline) sb.append("<w:u w:val=\"single\"/>")
        sb.append("<w:color w:val=\"000000\"/>")
        sb.append("<w:sz w:val=\"$halfPtSize\"/><w:szCs w:val=\"$halfPtSize\"/>")
        sb.append("</w:rPr>")
        sb.append("<w:t xml:space=\"preserve\">${xmlEscape(text)}</w:t></w:r>")
        return sb.toString()
    }

    private fun buildParagraphXml(
        text: String,
        halfPtSize: Int = 26,
        bold: Boolean = false,
        italic: Boolean = false,
        underline: Boolean = false,
        jc: String = "both",
        spaceBeforeDxa: Int = 60,
        spaceAfterDxa: Int = 60,
        firstLineIndentDxa: Int = 0
    ): String {
        val sb = StringBuilder()
        sb.append("<w:p><w:pPr>")
        sb.append("<w:spacing w:before=\"$spaceBeforeDxa\" w:after=\"$spaceAfterDxa\" w:line=\"276\" w:lineRule=\"auto\"/>")
        if (firstLineIndentDxa > 0) {
            sb.append("<w:ind w:firstLine=\"$firstLineIndentDxa\"/>")
        }
        sb.append("<w:jc w:val=\"$jc\"/>")
        sb.append("</w:pPr>")
        if (text.isNotEmpty()) {
            sb.append(buildRunXml(text, halfPtSize, bold, italic, underline))
        }
        sb.append("</w:p>")
        return sb.toString()
    }

    fun generateDocxFile(
        context: Context,
        outputDir: File,
        jsonString: String
    ): Map<String, Any> {
        val root = JSONObject(jsonString)
        val docLanguageMode = root.optString("docLanguageMode", "VI_EN_DE").ifBlank { "VI" }
        val labels = getLabelsForMode(docLanguageMode)

        val documentType = root.optString("documentType", "MEETING").uppercase(Locale.US)
        val isMonologue = documentType == "MONOLOGUE"
        val detectedSpeakerCount = root.optInt("detectedSpeakerCount", if (isMonologue) 1 else 2)
        val diarizationReport = root.optString("diarizationReport", "").trim()

        val orgName = root.optString("organizationName", "ANH'S TEAM").ifBlank { "ANH'S TEAM" }
        val govBody = root.optString("governingBody", "")
        val docNumber = root.optString("documentNumber", if (isMonologue) "Số: 01/2026/GB-AT" else "Số: 01/2026/BB-AT")
        val locationDate = root.optString("locationDate", "Hà Nội, ngày 16 tháng 10 năm 2026")
        val customTitle = root.optString("meetingTitle", "").trim()
        val meetingTitle = if (isMonologue) {
            if (customTitle.isNotEmpty() && customTitle != "BIÊN BẢN CUỘC HỌP" && customTitle != "BẢN GỠ BĂNG & TÓM TẮT NỘI DUNG GHI ÂM") customTitle
            else "BẢN GỠ BĂNG NGUYÊN VĂN NỘI DUNG GHI ÂM (01 NGƯỜI NÓI)"
        } else {
            if (customTitle.isEmpty() || customTitle == "BIÊN BẢN CUỘC HỌP") labels.defaultDocTitle
            else customTitle
        }
        val meetingSubject = root.optString("meetingSubject", "Về việc rà soát tiến độ và triển khai kế hoạch công tác")
        val startTime = root.optString("startTime", "08 giờ 30 phút ngày 16/10/2026")
        val endTime = root.optString("endTime", "11 giờ 00 phút cùng ngày")
        val venue = root.optString("venue", "Phòng họp trung tâm (Kết hợp trực tuyến)")
        val chairName = root.optString("chairName", "Ông Trương Đức Anh")
        val chairTitle = root.optString("chairTitle", "Chủ trì cuộc họp")
        val secName = root.optString("secretaryName", "Thư ký chuyên trách")
        val secTitle = root.optString("secretaryTitle", "Thư ký cuộc họp")
        val attendeesRaw = root.optString("attendeesList", "")
        val turnsArray = root.optJSONArray("speakerTurns") ?: JSONArray()
        val conclusionsArray = root.optJSONArray("conclusions") ?: JSONArray()
        val actionItemsArray = root.optJSONArray("actionItems") ?: JSONArray()

        val bodyXml = StringBuilder()

        // 1. Bảng Header Quốc hiệu & Tiêu ngữ (2 cột ẩn viền)
        bodyXml.append("<w:tbl><w:tblPr>")
        bodyXml.append("<w:tblW w:w=\"9355\" w:type=\"dxa\"/>")
        bodyXml.append("<w:jc w:val=\"center\"/>")
        bodyXml.append("<w:tblBorders>")
        for (b in listOf("top", "left", "bottom", "right", "insideH", "insideV")) {
            bodyXml.append("<w:$b w:val=\"none\" w:sz=\"0\" w:space=\"0\" w:color=\"auto\"/>")
        }
        bodyXml.append("</w:tblBorders></w:tblPr>")
        bodyXml.append("<w:tblGrid><w:gridCol w:w=\"3800\"/><w:gridCol w:w=\"5555\"/></w:tblGrid>")
        bodyXml.append("<w:tr><w:trPr><w:cantSplit/></w:trPr>")

        // Ô Trái: Tên cơ quan / Đơn vị
        bodyXml.append("<w:tc><w:tcPr><w:tcW w:w=\"3800\" w:type=\"dxa\"/></w:tcPr>")
        if (govBody.isNotBlank()) {
            bodyXml.append(buildParagraphXml(govBody.uppercase(Locale.getDefault()), halfPtSize = 24, bold = false, jc = "center", spaceBeforeDxa = 0, spaceAfterDxa = 20))
        }
        bodyXml.append(buildParagraphXml(orgName.uppercase(Locale.getDefault()), halfPtSize = 24, bold = true, underline = true, jc = "center", spaceBeforeDxa = 0, spaceAfterDxa = 40))
        bodyXml.append(buildParagraphXml(docNumber, halfPtSize = 24, bold = false, jc = "center", spaceBeforeDxa = 20, spaceAfterDxa = 0))
        bodyXml.append("</w:tc>")

        // Ô Phải: Quốc hiệu & Tiêu ngữ
        bodyXml.append("<w:tc><w:tcPr><w:tcW w:w=\"5555\" w:type=\"dxa\"/></w:tcPr>")
        bodyXml.append(buildParagraphXml("CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM", halfPtSize = 24, bold = true, jc = "center", spaceBeforeDxa = 0, spaceAfterDxa = 20))
        bodyXml.append(buildParagraphXml("Độc lập - Tự do - Hạnh phúc", halfPtSize = 26, bold = true, underline = true, jc = "center", spaceBeforeDxa = 0, spaceAfterDxa = 60))
        bodyXml.append(buildParagraphXml(locationDate, halfPtSize = 25, italic = true, jc = "center", spaceBeforeDxa = 40, spaceAfterDxa = 0))
        bodyXml.append("</w:tc></w:tr></w:tbl>")

        // 2. Tên loại văn bản & Trích yếu
        bodyXml.append(buildParagraphXml(meetingTitle.uppercase(Locale.getDefault()), halfPtSize = 27, bold = true, jc = "center", spaceBeforeDxa = 240, spaceAfterDxa = 40))
        bodyXml.append(buildParagraphXml(meetingSubject, halfPtSize = 26, bold = true, jc = "center", spaceBeforeDxa = 0, spaceAfterDxa = 180))

        if (isMonologue) {
            // =========================================================================
            // CHẾ ĐỘ 1: BẢN GỠ BĂNG NGUYÊN VĂN 100% (CHỈ 01 NGƯỜI NÓI - KHÔNG TÓM TẮT)
            // =========================================================================
            bodyXml.append(buildParagraphXml("I. THÔNG TIN TỆP GHI ÂM & NHẬN DIỆN GIỌNG NÓI (SPEAKER DIARIZATION)", halfPtSize = 26, bold = true, jc = "left", spaceBeforeDxa = 120, spaceAfterDxa = 60))
            bodyXml.append(buildParagraphXml("1. Thời điểm ghi nhận tệp âm thanh: $startTime.", halfPtSize = 26, bold = false, jc = "left"))
            bodyXml.append(buildParagraphXml("2. Nguồn tệp âm thanh: $venue.", halfPtSize = 26, bold = false, jc = "left"))
            bodyXml.append(buildParagraphXml("3. Kết quả phân biệt giọng nói âm học: Phát hiện duy nhất 01 người nói (Không phải cuộc họp nhiều người).", halfPtSize = 26, bold = true, jc = "left"))
            if (diarizationReport.isNotEmpty()) {
                bodyXml.append(buildParagraphXml("- Chi tiết sinh trắc giọng nói: $diarizationReport", halfPtSize = 26, bold = false, jc = "both", firstLineIndentDxa = 425))
            }
            bodyXml.append(buildParagraphXml("4. Chế độ xuất văn bản: Gỡ băng nguyên văn 100% lời nói từ đầu đến cuối tệp âm thanh (Không cắt bớt, không tóm tắt, không áp dụng mẫu Biên bản cuộc họp).", halfPtSize = 26, italic = true, jc = "left"))

            // Mục II: Văn bản nguyên văn liền mạch 100% (Full Continuous Verbatim Text)
            bodyXml.append(buildParagraphXml("II. TOÀN VĂN NỘI DUNG GỠ BĂNG NGUYÊN VĂN LIỀN MẠCH (100% VERBATIM - KHÔNG TÓM TẮT)", halfPtSize = 26, bold = true, jc = "left", spaceBeforeDxa = 160, spaceAfterDxa = 60))

            if (turnsArray.length() == 0) {
                bodyXml.append(buildParagraphXml("- (Chưa ghi nhận nội dung văn bản).", halfPtSize = 26, italic = true, jc = "left"))
            } else {
                val fullVerbatimParts = mutableListOf<String>()
                for (i in 0 until turnsArray.length()) {
                    val turn = turnsArray.optJSONObject(i) ?: continue
                    val content = turn.optString("content", "").trim()
                    if (content.isNotEmpty()) {
                        val cleaned = content.split("\n").map { it.trim().removePrefix("-").trim() }.filter { it.isNotEmpty() }.joinToString(" ")
                        if (cleaned.isNotEmpty()) {
                            val withPunct = if (cleaned.endsWith(".") || cleaned.endsWith("!") || cleaned.endsWith("?")) cleaned else "$cleaned."
                            fullVerbatimParts.add(withPunct)
                        }
                    }
                }
                if (fullVerbatimParts.isNotEmpty()) {
                    // Ghép thành các đoạn văn nguyên văn hoàn chỉnh (mỗi đoạn ~4 phân đoạn để dễ đọc, giữ nguyên 100% từng chữ)
                    val groupSize = 4
                    for (g in fullVerbatimParts.indices step groupSize) {
                        val slice = fullVerbatimParts.subList(g, (g + groupSize).coerceAtMost(fullVerbatimParts.size))
                        val paragraphText = slice.joinToString(" ")
                        bodyXml.append(buildParagraphXml(paragraphText, halfPtSize = 26, bold = false, jc = "both", spaceBeforeDxa = 60, spaceAfterDxa = 80, firstLineIndentDxa = 425))
                    }
                }

                // Mục III: Chi tiết nguyên văn theo từng mốc thời gian
                bodyXml.append(buildParagraphXml("III. CHI TIẾT NGUYÊN VĂN THEO TỪNG MỐC THỜI GIAN (01 NGƯỜI NÓI)", halfPtSize = 26, bold = true, jc = "left", spaceBeforeDxa = 160, spaceAfterDxa = 60))

                for (i in 0 until turnsArray.length()) {
                    val turn = turnsArray.optJSONObject(i) ?: continue
                    val speaker = turn.optString("speaker", "Người nói duy nhất")
                    val langTag = turn.optString("lang", "VI").uppercase(Locale.getDefault())
                    val timestamp = turn.optString("timestamp", "")
                    val content = turn.optString("content", "")
                    val translation = turn.optString("translation", "").trim()

                    val headerText = if (timestamp.isNotBlank()) {
                        "Đoạn ${i + 1} [$timestamp] • [$langTag] $speaker:"
                    } else {
                        "Đoạn ${i + 1} • [$langTag] $speaker:"
                    }
                    bodyXml.append(buildParagraphXml(headerText, halfPtSize = 26, bold = true, jc = "left", spaceBeforeDxa = 80, spaceAfterDxa = 40))

                    val sentences = content.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
                    for (line in sentences) {
                        val cleanLine = if (line.startsWith("-")) line.substring(1).trim() else line
                        bodyXml.append(buildParagraphXml(cleanLine, halfPtSize = 26, bold = false, jc = "both", firstLineIndentDxa = 425))
                    }

                    if (translation.isNotEmpty()) {
                        val transLines = translation.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
                        for (tLine in transLines) {
                            val cleanTrans = if (tLine.startsWith("-")) tLine.substring(1).trim() else tLine
                            bodyXml.append(
                                buildParagraphXml(
                                    "[${labels.translationPrefix}]: $cleanTrans",
                                    halfPtSize = 25,
                                    italic = true,
                                    jc = "both",
                                    firstLineIndentDxa = 425
                                )
                            )
                        }
                    }
                }
            }

            bodyXml.append(
                buildParagraphXml(
                    "Bản gỡ băng nguyên văn 100% nội dung ghi âm độc thoại (01 người nói - không tóm tắt) hoàn tất lúc $endTime./.",
                    halfPtSize = 26,
                    italic = true,
                    jc = "both",
                    spaceBeforeDxa = 160,
                    spaceAfterDxa = 120,
                    firstLineIndentDxa = 425
                )
            )
        } else {
            // =========================================================================
            // CHẾ ĐỘ 2: BIÊN BẢN CUỘC HỌP NHIỀU NGƯỜI NÓI (PHÂN BIỆT CÁC GIỌNG NÓI #1, #2, #3...)
            // =========================================================================
            bodyXml.append(buildParagraphXml(labels.section1Title, halfPtSize = 26, bold = true, jc = "left", spaceBeforeDxa = 120, spaceAfterDxa = 60))
            bodyXml.append(buildParagraphXml("${labels.startTimeLabel}: $startTime.", halfPtSize = 26, bold = false, jc = "left"))
            bodyXml.append(buildParagraphXml("${labels.venueLabel}: $venue.", halfPtSize = 26, bold = false, jc = "left"))
            if (diarizationReport.isNotEmpty()) {
                bodyXml.append(buildParagraphXml("Phân tích & Phân biệt giọng nói tự động ($detectedSpeakerCount người nói): $diarizationReport", halfPtSize = 26, bold = true, jc = "left"))
            }
            bodyXml.append(buildParagraphXml(labels.participantsLabel, halfPtSize = 26, bold = false, jc = "left"))
            bodyXml.append(buildParagraphXml("- ${labels.chairLabel}: $chairName ($chairTitle).", halfPtSize = 26, bold = false, jc = "left"))
            bodyXml.append(buildParagraphXml("- ${labels.secLabel}: $secName ($secTitle).", halfPtSize = 26, bold = false, jc = "left"))

            if (attendeesRaw.isNotBlank()) {
                val attLines = attendeesRaw.split("\n", ";").map { it.trim() }.filter { it.isNotEmpty() }
                for (att in attLines) {
                    val cleanAtt = if (att.startsWith("-")) att.substring(1).trim() else att
                    bodyXml.append(buildParagraphXml("- ${labels.memberLabel}: $cleanAtt.", halfPtSize = 26, bold = false, jc = "left"))
                }
            }

            // 4. Mục II: Nội dung diễn biến cuộc họp (Đa ngôn ngữ VI / EN / DE)
            bodyXml.append(buildParagraphXml(labels.section2Title, halfPtSize = 26, bold = true, jc = "left", spaceBeforeDxa = 160, spaceAfterDxa = 60))

            if (turnsArray.length() == 0) {
                bodyXml.append(buildParagraphXml("- (Chưa ghi nhận lượt phát biểu chi tiết).", halfPtSize = 26, italic = true, jc = "left"))
            } else {
                for (i in 0 until turnsArray.length()) {
                    val turn = turnsArray.optJSONObject(i) ?: continue
                    val speaker = turn.optString("speaker", "Người nói #1")
                    val langTag = turn.optString("lang", "VI").uppercase(Locale.getDefault())
                    val timestamp = turn.optString("timestamp", "")
                    val content = turn.optString("content", "")
                    val translation = turn.optString("translation", "").trim()

                    val headerText = if (timestamp.isNotBlank()) {
                        "${i + 1}. [$langTag] ${labels.speakerPrefix} $speaker (${labels.timeMarkerLabel}: $timestamp):"
                    } else {
                        "${i + 1}. [$langTag] ${labels.speakerPrefix} $speaker:"
                    }
                    bodyXml.append(buildParagraphXml(headerText, halfPtSize = 26, bold = true, jc = "left", spaceBeforeDxa = 80, spaceAfterDxa = 40))

                    val sentences = content.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
                    for (line in sentences) {
                        val cleanLine = if (line.startsWith("-")) line.substring(1).trim() else line
                        bodyXml.append(buildParagraphXml("- $cleanLine", halfPtSize = 26, bold = false, jc = "both", firstLineIndentDxa = 425))
                    }

                    if (translation.isNotEmpty()) {
                        val transLines = translation.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
                        for (tLine in transLines) {
                            val cleanTrans = if (tLine.startsWith("-")) tLine.substring(1).trim() else tLine
                            bodyXml.append(
                                buildParagraphXml(
                                    "- [${labels.translationPrefix}]: $cleanTrans",
                                    halfPtSize = 25,
                                    italic = true,
                                    jc = "both",
                                    firstLineIndentDxa = 425
                                )
                            )
                        }
                    }
                }
            }

            // 5. Mục III: Kết luận và phân công nhiệm vụ
            bodyXml.append(buildParagraphXml(labels.section3Title, halfPtSize = 26, bold = true, jc = "left", spaceBeforeDxa = 160, spaceAfterDxa = 60))

            if (conclusionsArray.length() > 0) {
                for (i in 0 until conclusionsArray.length()) {
                    val c = conclusionsArray.optString(i, "").trim()
                    if (c.isNotEmpty()) {
                        val cleanC = if (c.startsWith("-")) c.substring(1).trim() else c
                        bodyXml.append(buildParagraphXml("- $cleanC", halfPtSize = 26, bold = false, jc = "both", firstLineIndentDxa = 425))
                    }
                }
            }

            if (actionItemsArray.length() > 0) {
                bodyXml.append(buildParagraphXml(labels.actionTableIntro, halfPtSize = 26, bold = true, jc = "left", spaceBeforeDxa = 100, spaceAfterDxa = 60))

                bodyXml.append("<w:tbl><w:tblPr>")
                bodyXml.append("<w:tblW w:w=\"9355\" w:type=\"dxa\"/>")
                bodyXml.append("<w:jc w:val=\"center\"/>")
                bodyXml.append("<w:tblBorders>")
                for (b in listOf("top", "left", "bottom", "right", "insideH", "insideV")) {
                    bodyXml.append("<w:$b w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"000000\"/>")
                }
                bodyXml.append("</w:tblBorders></w:tblPr>")
                bodyXml.append("<w:tblGrid><w:gridCol w:w=\"680\"/><w:gridCol w:w=\"3855\"/><w:gridCol w:w=\"2000\"/><w:gridCol w:w=\"1410\"/><w:gridCol w:w=\"1410\"/></w:tblGrid>")

                val headers = listOf(labels.colStt, labels.colTask, labels.colAssignee, labels.colCoord, labels.colDeadline)
                val widths = listOf(680, 3855, 2000, 1410, 1410)
                bodyXml.append("<w:tr><w:trPr><w:cantSplit/><w:tblHeader/></w:trPr>")
                for (idx in headers.indices) {
                    bodyXml.append("<w:tc><w:tcPr><w:tcW w:w=\"${widths[idx]}\" w:type=\"dxa\"/><w:vAlign w:val=\"center\"/></w:tcPr>")
                    bodyXml.append(buildParagraphXml(headers[idx], halfPtSize = 23, bold = true, jc = "center", spaceBeforeDxa = 60, spaceAfterDxa = 60))
                    bodyXml.append("</w:tc>")
                }
                bodyXml.append("</w:tr>")

                for (i in 0 until actionItemsArray.length()) {
                    val item = actionItemsArray.optJSONObject(i) ?: continue
                    val stt = (i + 1).toString()
                    val task = item.optString("task", "")
                    val assignee = item.optString("assignee", "")
                    val coord = item.optString("coordinator", "")
                    val deadline = item.optString("deadline", "")

                    val rowVals = listOf(stt, task, assignee, coord, deadline)
                    val rowAligns = listOf("center", "both", "left", "left", "center")
                    val rowBolds = listOf(true, false, false, false, true)

                    bodyXml.append("<w:tr><w:trPr><w:cantSplit/></w:trPr>")
                    for (cIdx in rowVals.indices) {
                        bodyXml.append("<w:tc><w:tcPr><w:tcW w:w=\"${widths[cIdx]}\" w:type=\"dxa\"/><w:vAlign w:val=\"center\"/></w:tcPr>")
                        bodyXml.append(buildParagraphXml(rowVals[cIdx], halfPtSize = 23, bold = rowBolds[cIdx], jc = rowAligns[cIdx], spaceBeforeDxa = 60, spaceAfterDxa = 60))
                        bodyXml.append("</w:tc>")
                    }
                    bodyXml.append("</w:tr>")
                }
                bodyXml.append("</w:tbl>")
            }

            // 6. Thời gian kết thúc & Bảng chữ ký xác nhận
            bodyXml.append(
                buildParagraphXml(
                    "${labels.closingSentencePrefix}$endTime${labels.closingSentenceSuffix}",
                    halfPtSize = 26,
                    bold = false,
                    jc = "both",
                    spaceBeforeDxa = 160,
                    spaceAfterDxa = 200,
                    firstLineIndentDxa = 425
                )
            )

            bodyXml.append("<w:tbl><w:tblPr>")
            bodyXml.append("<w:tblW w:w=\"9355\" w:type=\"dxa\"/>")
            bodyXml.append("<w:jc w:val=\"center\"/>")
            bodyXml.append("<w:tblBorders>")
            for (b in listOf("top", "left", "bottom", "right", "insideH", "insideV")) {
                bodyXml.append("<w:$b w:val=\"none\" w:sz=\"0\" w:space=\"0\" w:color=\"auto\"/>")
            }
            bodyXml.append("</w:tblBorders></w:tblPr>")
            bodyXml.append("<w:tblGrid><w:gridCol w:w=\"4677\"/><w:gridCol w:w=\"4678\"/></w:tblGrid>")
            bodyXml.append("<w:tr><w:trPr><w:cantSplit/></w:trPr>")

            // Chữ ký Thư ký
            bodyXml.append("<w:tc><w:tcPr><w:tcW w:w=\"4677\" w:type=\"dxa\"/></w:tcPr>")
            bodyXml.append(buildParagraphXml(labels.sigSecretaryTitle, halfPtSize = 24, bold = true, jc = "center", spaceBeforeDxa = 0, spaceAfterDxa = 20))
            bodyXml.append(buildParagraphXml(labels.sigSecretaryHint, halfPtSize = 22, italic = true, jc = "center", spaceBeforeDxa = 0, spaceAfterDxa = 960))
            bodyXml.append(buildParagraphXml(secName, halfPtSize = 25, bold = true, jc = "center", spaceBeforeDxa = 0, spaceAfterDxa = 0))
            bodyXml.append("</w:tc>")

            // Chữ ký Chủ trì
            bodyXml.append("<w:tc><w:tcPr><w:tcW w:w=\"4678\" w:type=\"dxa\"/></w:tcPr>")
            bodyXml.append(buildParagraphXml(labels.sigChairTitle, halfPtSize = 24, bold = true, jc = "center", spaceBeforeDxa = 0, spaceAfterDxa = 20))
            bodyXml.append(buildParagraphXml(labels.sigChairHint, halfPtSize = 22, italic = true, jc = "center", spaceBeforeDxa = 0, spaceAfterDxa = 960))
            bodyXml.append(buildParagraphXml(chairName, halfPtSize = 25, bold = true, jc = "center", spaceBeforeDxa = 0, spaceAfterDxa = 0))
            bodyXml.append("</w:tc></w:tr></w:tbl>")
        }

        bodyXml.append("<w:sectPr>")
        bodyXml.append("<w:pgSz w:w=\"11906\" w:h=\"16838\"/>")
        bodyXml.append("<w:pgMar w:top=\"1134\" w:right=\"850\" w:bottom=\"1134\" w:left=\"1701\" w:header=\"708\" w:footer=\"708\" w:gutter=\"0\"/>")
        bodyXml.append("</w:sectPr>")

        val documentXml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
            xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml"
            xmlns:w15="http://schemas.microsoft.com/office/word/2012/wordml"
            mc:Ignorable="w14 w15">
  <w:body>
    $bodyXml
  </w:body>
</w:document>"""

        val contentTypesXml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>"""

        val relsXml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>"""

        val docRelsXml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>"""

        val stylesXml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        <w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:cs="Times New Roman" w:eastAsia="Times New Roman"/>
        <w:color w:val="000000"/>
        <w:sz w:val="26"/>
        <w:szCs w:val="26"/>
      </w:rPr>
    </w:rPrDefault>
  </w:docDefaults>
</w:styles>"""

        if (!outputDir.exists()) outputDir.mkdirs()
        val ts = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val fileName = "BienBanHop_AnhsTeam_${docLanguageMode}_$ts.docx"
        val outFile = File(outputDir, fileName)

        ZipOutputStream(FileOutputStream(outFile)).use { zos ->
            fun addEntry(entryPath: String, content: String) {
                zos.putNextEntry(ZipEntry(entryPath))
                zos.write(content.toByteArray(Charsets.UTF_8))
                zos.closeEntry()
            }
            addEntry("[Content_Types].xml", contentTypesXml)
            addEntry("_rels/.rels", relsXml)
            addEntry("word/_rels/document.xml.rels", docRelsXml)
            addEntry("word/styles.xml", stylesXml)
            addEntry("word/document.xml", documentXml)
        }

        val publicDownloadPath = copyToPublicDownloads(context, outFile)

        return mapOf(
            "path" to outFile.absolutePath,
            "name" to outFile.name,
            "publicDownloadPath" to (publicDownloadPath ?: outFile.absolutePath),
            "sizeKB" to (outFile.length() / 1024L).coerceAtLeast(1L)
        )
    }

    private fun copyToPublicDownloads(context: Context, srcFile: File): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, srcFile.name)
                    put(MediaStore.Downloads.MIME_TYPE, "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/AnhsTeam_BienBanHop")
                }
                val resolver = context.contentResolver
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                if (uri != null) {
                    resolver.openOutputStream(uri)?.use { out ->
                        FileInputStream(srcFile).use { input ->
                            input.copyTo(out)
                        }
                    }
                    "/Download/AnhsTeam_BienBanHop/${srcFile.name}"
                } else null
            } else {
                @Suppress("DEPRECATION")
                val dlDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "AnhsTeam_BienBanHop")
                if (!dlDir.exists()) dlDir.mkdirs()
                val dest = File(dlDir, srcFile.name)
                srcFile.copyTo(dest, overwrite = true)
                dest.absolutePath
            }
        } catch (_: Exception) {
            null
        }
    }
}
