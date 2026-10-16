# 03. Quy Trình Xử Lý Ngôn Ngữ Tự Nhiên (NLP) Trích Xuất & Lập Biên Bản Cuộc Họp Hành Chính

Tài liệu này mô tả quy trình chuyển đổi từ **Bản gỡ băng thô có gán nhãn người nói (Raw Diarized Transcript)** sang **Biên bản cuộc họp hoàn chỉnh** theo đúng thể thức văn bản hành chính tại **Nghị định số 30/2020/NĐ-CP**.

---

## 1. Nguyên Tắc Bảo Toàn Sự Thật Khách Quan (Ground-Truth Fidelity)

Trong công tác lập biên bản cuộc họp kỹ thuật, pháp lý và quản trị dự án, hệ thống NLP/LLM tuân thủ nghiêm ngặt 3 nguyên tắc:
1. **Không tự ý suy diễn hoặc thêm ý kiến**: Mọi ý kiến phát biểu, số liệu tài chính, mốc thời gian và kết luận đưa vào biên bản phải có nguồn gốc đối chiếu trực tiếp từ văn bản gỡ băng kèm dấu thời gian (`[HH:MM:SS]`).
2. **Chuẩn hóa văn phong từ Ngôn ngữ Nói sang Ngôn ngữ Hành chính**:
   - Loại bỏ các từ đệm khẩu ngữ (*"ờ", "à", "kiểu như là", "nói chung là"*), các từ lặp do ngập ngừng khi nói.
   - Chuyển đổi đại từ nhân xưng khẩu ngữ (*"tôi", "anh em mình", "bên cậu"*) sang danh xưng hành chính chuẩn mực (*"Ông/Bà [Họ tên]", "Đơn vị tư vấn", "Ban Quản lý dự án", "Chủ đầu tư"*).
3. **Để trống hoặc đánh dấu `[Cần xác nhận lại tại HH:MM:SS]`** đối với các vị trí âm thanh bị nhiễu nặng, nói chồng lấp không nghe rõ số liệu, tuyệt đối không để mô hình tự điền số liệu giả định.

---

## 2. Cấu Trúc Dữ Liệu Trung Gian (Structured Meeting JSON Schema)

Trước khi xuất sang tệp Word (`.docx`), toàn bộ thông tin cuộc họp được bóc tách và chuẩn hóa về cấu trúc JSON thống nhất:

```json
{
  "metadata": {
    "governing_body": "TÊN CƠ QUAN CHỦ QUẢN",
    "organization_name": "TÊN CƠ QUAN / ĐƠN VỊ LẬP BIÊN BẢN",
    "document_number": "Số: .../BB-...",
    "location": "Hà Nội",
    "date": "2026-10-16",
    "start_time": "08 giờ 30 phút",
    "end_time": "11 giờ 00 phút",
    "venue": "Phòng họp số 1 (Kết hợp trực tuyến)",
    "meeting_title": "BIÊN BẢN CUỘC HỌP",
    "meeting_subject": "Về việc rà soát tiến độ và hồ sơ kỹ thuật dự án..."
  },
  "participants": {
    "chairperson": {
      "name": "Ông Nguyễn Văn A",
      "title": "Giám đốc / Chủ trì cuộc họp"
    },
    "secretary": {
      "name": "Bà Lê Thị B",
      "title": "Chuyên viên / Thư ký cuộc họp"
    },
    "attendees": [
      {"name": "Ông Trần Văn C", "title": "Trưởng phòng Kỹ thuật"},
      {"name": "Ông Phạm Văn D", "title": "Đại diện Đơn vị Tư vấn thiết kế"}
    ],
    "absentees": []
  },
  "agenda_and_presentations": [
    {
      "order": 1,
      "speaker": "Ông Trần Văn C (Trưởng phòng Kỹ thuật)",
      "timestamp_range": "00:02:15 - 00:18:40",
      "summary_points": [
        "Báo cáo hiện trạng hồ sơ thiết kế bản vẽ thi công hạng mục kết cấu và cơ điện.",
        "Nêu vướng mắc về việc đồng bộ thông số tải trọng thiết bị giữa các bộ môn."
      ]
    }
  ],
  "discussions": [
    {
      "speaker": "Ông Phạm Văn D (Đại diện Đơn vị Tư vấn thiết kế)",
      "timestamp_range": "00:19:00 - 00:27:30",
      "opinions": [
        "Giải trình nguyên nhân chênh lệch thông số và cam kết cập nhật lại mô hình trước ngày 20/10/2026."
      ]
    }
  ],
  "conclusions": [
    "Thống nhất phương án hiệu chỉnh hồ sơ kỹ thuật theo báo cáo của Phòng Kỹ thuật.",
    "Yêu cầu các đơn vị hoàn thành bàn giao hồ sơ đúng mốc thời gian trong bảng phân công nhiệm vụ."
  ],
  "action_items": [
    {
      "stt": 1,
      "task": "Hoàn thiện và nộp lại bản vẽ điều chỉnh kết cấu & MEPF",
      "assignee": "Đơn vị Tư vấn thiết kế",
      "coordinator": "Phòng Kỹ thuật",
      "deadline": "20/10/2026",
      "notes": "Nộp bản cứng và tệp nguồn trên hệ thống"
    }
  ]
}
```

---

## 3. Quy Chuẩn Kỹ Thuật Khi Chế Bản Tệp Word (.docx) Theo Nghị Định 30/2020/NĐ-CP

Khi chuyển từ dữ liệu JSON sang tệp `.docx` bằng `python-docx`, bộ xuất bản (`export_meeting_minutes_docx.py`) thực thi các quy tắc kỹ thuật sau:

1. **Khổ giấy & Căn lề trang (Page Setup)**:
   - Khổ giấy A4 (`210 mm x 297 mm`).
   - Lề trên (`Top`): `20 mm` (2.0 cm); Lề dưới (`Bottom`): `20 mm` (2.0 cm).
   - Lề trái (`Left`): `30 mm` (3.0 cm); Lề phải (`Right`): `15 mm` (1.5 cm).
2. **Phông chữ & Màu chữ**:
   - Phông chữ `Times New Roman` đồng nhất toàn văn bản.
   - Màu chữ: **Đen tuyền (`RGB: 0, 0, 0` / `#000000`)** cho toàn bộ tiêu đề, nội dung và bảng biểu.
3. **Quy tắc Ngắt đoạn và Căn lề (Chống lỗi giãn chữ OpenXML)**:
   - Tuyệt đối không sử dụng ký tự xuống dòng mềm (`\n` / `<w:br/>`) bên trong đoạn văn có thuộc tính căn đều hai bên (`WD_ALIGN_PARAGRAPH.JUSTIFY`).
   - Mỗi ý phát biểu, mỗi gạch đầu dòng (`- `) được khởi tạo bằng một đoạn văn độc lập (`doc.add_paragraph()`).
4. **Bảng Phân Công Nhiệm Vụ (Action Items Table)**:
   - Nền trắng tự nhiên (`No Shading`), đường viền đơn màu đen mảnh `0.5pt` (`sz="4"`, `color="000000"`).
   - Dòng tiêu đề bảng được gắn thuộc tính lặp lại khi sang trang mới (`w:tblHeader`) và chống ngắt dòng giữa chừng (`w:cantSplit`).
