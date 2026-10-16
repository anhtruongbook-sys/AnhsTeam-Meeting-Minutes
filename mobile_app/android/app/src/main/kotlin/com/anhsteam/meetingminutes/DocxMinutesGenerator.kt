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
 * Bộ Kết xuất Tệp Word OpenXML (.docx) Chuẩn Nghị định 30/2020/NĐ-CP & Rule 11:
 * - Khổ giấy A4 (11906 x 16838 dxa), Lề: Trên 20mm (1134), Dưới 20mm (1134), Trái 30mm (1701), Phải 15mm (850).
 * - Phông chữ Times New Roman 100%, màu chữ Đen tuyền (#000000) 100%.
 * - Bảng Quốc hiệu & Tiêu ngữ 2 cột ẩn viền.
 * - Tuyệt đối KHÔNG dùng ký tự xuống dòng mềm (<w:br/>) trong đoạn văn căn đều hai bên (<w:jc w:val="both"/>).
 * - Bảng phân công nhiệm vụ nền trắng tự nhiên, kẻ viền đơn màu đen 0.5pt (w:sz="4"), lặp lại tiêu đề khi sang trang (<w:tblHeader/>) và chống cắt ngang dòng (<w:cantSplit/>).
 * - Bảo toàn đầy đủ khai báo schema ECMA-376 (mc:Ignorable="w14 w15") chống lỗi Unreadable Content trên Word Mobile & Google Docs.
 */
object DocxMinutesGenerator {

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
        halfPtSize: Int = 26, // 26 half-points = 13pt
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
        jc: String = "both", // "left", "center", "right", "both"
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
        val orgName = root.optString("organizationName", "ANH'S TEAM").ifBlank { "ANH'S TEAM" }
        val govBody = root.optString("governingBody", "")
        val docNumber = root.optString("documentNumber", "Số: 01/BB-AT")
        val locationDate = root.optString("locationDate", "Hà Nội, ngày 16 tháng 10 năm 2026")
        val meetingTitle = root.optString("meetingTitle", "BIÊN BẢN CUỘC HỌP")
        val meetingSubject = root.optString("meetingSubject", "Về việc rà soát tiến độ và triển khai kế hoạch công tác")
        val startTime = root.optString("startTime", "08 giờ 30 phút ngày 16/10/2026")
        val endTime = root.optString("endTime", "11 giờ 00 phút cùng ngày")
        val venue = root.optString("venue", "Phòng họp trung tâm (Kết hợp trực tuyến)")
        val chairName = root.optString("chairName", "Ông Nguyễn Văn A")
        val chairTitle = root.optString("chairTitle", "Chủ trì cuộc họp")
        val secName = root.optString("secretaryName", "Bà Lê Thị B")
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
        bodyXml.append(buildParagraphXml(meetingTitle.uppercase(Locale.getDefault()), halfPtSize = 28, bold = true, jc = "center", spaceBeforeDxa = 240, spaceAfterDxa = 40))
        bodyXml.append(buildParagraphXml(meetingSubject, halfPtSize = 26, bold = true, jc = "center", spaceBeforeDxa = 0, spaceAfterDxa = 180))

        // 3. Mục I: Thời gian, địa điểm và thành phần tham dự
        bodyXml.append(buildParagraphXml("I. THỜI GIAN, ĐỊA ĐIỂM VÀ THÀNH PHẦN THAM DỰ", halfPtSize = 26, bold = true, jc = "left", spaceBeforeDxa = 120, spaceAfterDxa = 60))
        bodyXml.append(buildParagraphXml("1. Thời gian bắt đầu: $startTime.", halfPtSize = 26, bold = false, jc = "left"))
        bodyXml.append(buildParagraphXml("2. Địa điểm / Hình thức họp: $venue.", halfPtSize = 26, bold = false, jc = "left"))
        bodyXml.append(buildParagraphXml("3. Thành phần tham dự:", halfPtSize = 26, bold = false, jc = "left"))
        bodyXml.append(buildParagraphXml("- Chủ trì cuộc họp: $chairName ($chairTitle).", halfPtSize = 26, bold = false, jc = "left"))
        bodyXml.append(buildParagraphXml("- Thư ký cuộc họp: $secName ($secTitle).", halfPtSize = 26, bold = false, jc = "left"))

        if (attendeesRaw.isNotBlank()) {
            val attLines = attendeesRaw.split("\n", ";").map { it.trim() }.filter { it.isNotEmpty() }
            for (att in attLines) {
                val cleanAtt = if (att.startsWith("-")) att.substring(1).trim() else att
                bodyXml.append(buildParagraphXml("- Thành viên tham dự: $cleanAtt.", halfPtSize = 26, bold = false, jc = "left"))
            }
        }

        // 4. Mục II: Nội dung cuộc họp
        bodyXml.append(buildParagraphXml("II. NỘI DUNG DIỄN BIẾN CUỘC HỌP", halfPtSize = 26, bold = true, jc = "left", spaceBeforeDxa = 160, spaceAfterDxa = 60))

        if (turnsArray.length() == 0) {
            bodyXml.append(buildParagraphXml("- (Chưa ghi nhận lượt phát biểu chi tiết).", halfPtSize = 26, italic = true, jc = "left"))
        } else {
            for (i in 0 until turnsArray.length()) {
                val turn = turnsArray.optJSONObject(i) ?: continue
                val speaker = turn.optString("speaker", "Đại biểu")
                val timestamp = turn.optString("timestamp", "")
                val content = turn.optString("content", "")

                val headerText = if (timestamp.isNotBlank()) {
                    "${i + 1}. Ý kiến phát biểu của $speaker (Mốc thời gian: $timestamp):"
                } else {
                    "${i + 1}. Ý kiến phát biểu của $speaker:"
                }
                bodyXml.append(buildParagraphXml(headerText, halfPtSize = 26, bold = true, jc = "left", spaceBeforeDxa = 80, spaceAfterDxa = 40))

                // Tách từng câu/ý thành các đoạn văn độc lập (Hard Return), tuyệt đối không dùng <w:br/>
                val sentences = content.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
                for (line in sentences) {
                    val cleanLine = if (line.startsWith("-")) line.substring(1).trim() else line
                    bodyXml.append(buildParagraphXml("- $cleanLine", halfPtSize = 26, bold = false, jc = "both", firstLineIndentDxa = 425))
                }
            }
        }

        // 5. Mục III: Kết luận và phân công nhiệm vụ
        bodyXml.append(buildParagraphXml("III. KẾT LUẬN CUỘC HỌP VÀ PHÂN CÔNG NHIỆM VỤ", halfPtSize = 26, bold = true, jc = "left", spaceBeforeDxa = 160, spaceAfterDxa = 60))

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
            bodyXml.append(buildParagraphXml("Bảng phân công nhiệm vụ triển khai:", halfPtSize = 26, bold = true, jc = "left", spaceBeforeDxa = 100, spaceAfterDxa = 60))

            // Bảng nền trắng tự nhiên, viền đơn màu đen mảnh 0.5pt (sz=4)
            bodyXml.append("<w:tbl><w:tblPr>")
            bodyXml.append("<w:tblW w:w=\"9355\" w:type=\"dxa\"/>")
            bodyXml.append("<w:jc w:val=\"center\"/>")
            bodyXml.append("<w:tblBorders>")
            for (b in listOf("top", "left", "bottom", "right", "insideH", "insideV")) {
                bodyXml.append("<w:$b w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"000000\"/>")
            }
            bodyXml.append("</w:tblBorders></w:tblPr>")
            bodyXml.append("<w:tblGrid><w:gridCol w:w=\"680\"/><w:gridCol w:w=\"3855\"/><w:gridCol w:w=\"2000\"/><w:gridCol w:w=\"1410\"/><w:gridCol w:w=\"1410\"/></w:tblGrid>")

            // Dòng tiêu đề bảng (tblHeader + cantSplit)
            val headers = listOf("TT", "Nội dung công việc", "Chủ trì thực hiện", "Phối hợp", "Thời hạn")
            val widths = listOf(680, 3855, 2000, 1410, 1410)
            bodyXml.append("<w:tr><w:trPr><w:cantSplit/><w:tblHeader/></w:trPr>")
            for (idx in headers.indices) {
                bodyXml.append("<w:tc><w:tcPr><w:tcW w:w=\"${widths[idx]}\" w:type=\"dxa\"/><w:vAlign w:val=\"center\"/></w:tcPr>")
                bodyXml.append(buildParagraphXml(headers[idx], halfPtSize = 23, bold = true, jc = "center", spaceBeforeDxa = 60, spaceAfterDxa = 60))
                bodyXml.append("</w:tc>")
            }
            bodyXml.append("</w:tr>")

            // Các dòng dữ liệu nhiệm vụ
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
                "Cuộc họp kết thúc vào lúc $endTime. Biên bản này đã được thông qua trước toàn thể thành viên dự họp và lập thành văn bản lưu hồ sơ./.",
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
        bodyXml.append(buildParagraphXml("THƯ KÝ CUỘC HỌP", halfPtSize = 25, bold = true, jc = "center", spaceBeforeDxa = 0, spaceAfterDxa = 20))
        bodyXml.append(buildParagraphXml("(Ký và ghi rõ họ tên)", halfPtSize = 23, italic = true, jc = "center", spaceBeforeDxa = 0, spaceAfterDxa = 960))
        bodyXml.append(buildParagraphXml(secName, halfPtSize = 25, bold = true, jc = "center", spaceBeforeDxa = 0, spaceAfterDxa = 0))
        bodyXml.append("</w:tc>")

        // Chữ ký Chủ trì
        bodyXml.append("<w:tc><w:tcPr><w:tcW w:w=\"4678\" w:type=\"dxa\"/></w:tcPr>")
        bodyXml.append(buildParagraphXml("CHỦ TRÌ CUỘC HỌP", halfPtSize = 25, bold = true, jc = "center", spaceBeforeDxa = 0, spaceAfterDxa = 20))
        bodyXml.append(buildParagraphXml("(Ký, ghi rõ họ tên và đóng dấu nếu có)", halfPtSize = 23, italic = true, jc = "center", spaceBeforeDxa = 0, spaceAfterDxa = 960))
        bodyXml.append(buildParagraphXml(chairName, halfPtSize = 25, bold = true, jc = "center", spaceBeforeDxa = 0, spaceAfterDxa = 0))
        bodyXml.append("</w:tc></w:tr></w:tbl>")

        // Thiết lập khổ giấy A4 (11906 x 16838 dxa) và lề chuẩn Nghị định 30/2020/NĐ-CP
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
        val fileName = "BienBanCuocHop_AnhsTeam_$ts.docx"
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
