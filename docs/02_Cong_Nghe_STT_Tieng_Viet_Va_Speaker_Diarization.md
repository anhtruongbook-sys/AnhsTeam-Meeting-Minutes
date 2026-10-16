# 02. Công Nghệ Nhận Dạng Tiếng Nói Tiếng Việt (ASR) & Phân Tách Người Phát Biểu (Speaker Diarization)

Tài liệu này phân tích kiến trúc mô hình nhận dạng giọng nói tiếng Việt (Automatic Speech Recognition - ASR) và bài toán xác định "Ai nói lúc nào" (Speaker Diarization) trong bối cảnh cuộc họp có nhiều đại biểu tham gia.

---

## 1. Đặc Thù Của Tiếng Việt Trong Bài Toán Gỡ Băng Cuộc Họp

Khác với văn bản đọc sẵn (Read Speech), ngôn ngữ nói trong cuộc họp (Spontaneous Conversational Speech) tại Việt Nam có các đặc trưng kỹ thuật cần xử lý:
1. **Đa phương ngữ và âm sắc vùng miền**: Sự khác biệt về thanh điệu và phụ âm đầu/cuối giữa giọng Bắc, Trung, Nam trong cùng một phòng họp.
2. **Hiện tượng trộn mã ngôn ngữ (Code-Switching Việt - Anh)**: Trong các cuộc họp kỹ thuật, xây dựng, công nghệ thông tin hoặc quản trị dự án, người nói thường xuyên chèn thuật ngữ chuyên ngành tiếng Anh hoặc từ viết tắt (ví dụ: *BIM, CDE, MEPF, PCCC, QCVN, TCVN, tiến độ WBS, nghiệm thu hoàn thành*).
3. **Từ đệm và câu tỉnh lược (Disfluencies & Filler Words)**: Các từ như *"ờ", "à", "thì là mà", "như đã trao đổi"* xuất hiện dày đặc cần được nhận diện chính xác ở bước gỡ băng nhưng phải được biên tập gọn ở bước lập biên bản.

---

## 2. Phân Tích Các Mô Hình ASR Tiếng Việt Hiện Hành

### 2.1. Faster-Whisper (Large-v3 / Large-v3-Turbo) với CTranslate2
- **Kiến trúc**: Biến thể tối ưu hóa của OpenAI Whisper sử dụng engine suy luận `CTranslate2`, hỗ trợ lượng tử hóa `INT8` và `FP16`.
- **Ưu điểm**:
  - Xử lý tốt hiện tượng trộn mã Việt - Anh (Code-switching) nhờ tập dữ liệu huấn luyện đa ngôn ngữ quy mô lớn.
  - Hỗ trợ tham số `initial_prompt` và `hotwords`: Cho phép truyền trước danh sách tên riêng đại biểu, tên cơ quan, mã hiệu tiêu chuẩn kỹ thuật để định hướng bộ giải mã (Beam Search Decoder), giảm tỷ lệ sai chính tả tên riêng.
  - Trả về dấu thời gian chi tiết đến từng từ (`word_timestamps=True`), phục vụ ghép nối chính xác với kết quả phân tách người nói.

### 2.2. PhoWhisper (VinAI Research)
- **Kiến trúc**: Mô hình Whisper được tinh chỉnh chuyên sâu (Fine-tuned) trên hàng chục nghìn giờ dữ liệu tiếng Việt đa phương ngữ.
- **Ưu điểm**:
  - Độ lỗi từ (WER - Word Error Rate) trên tiếng Việt thuần túy thấp hơn so với Whisper gốc ở cùng kích thước mô hình (`base`, `small`, `medium`).
  - Khả năng nhận diện chính xác các từ ghép Hán - Việt hành chính, pháp lý.
- **Lưu ý**: Khi cuộc họp có nhiều thuật ngữ tiếng Anh chuyên ngành phát âm chuẩn quốc tế, cần kết hợp từ điển hậu xử lý vì PhoWhisper có xu hướng phiên âm từ tiếng Anh sang âm tiết tiếng Việt.

### 2.3. Kỹ thuật Gợi ý Ngữ cảnh Đầu vào (Domain Prompting trong ASR)
Khi gọi bộ giải mã ASR cho một cuộc họp cụ thể, việc truyền một chuỗi `initial_prompt` chứa ngữ cảnh cuộc họp giúp cải thiện rõ rệt độ chính xác của các danh từ riêng:
```python
initial_prompt = (
    "Biên bản cuộc họp giao ban kỹ thuật. "
    "Các thuật ngữ: Nghị định 217/2026/NĐ-CP, Nghị định 207/2026/NĐ-CP, "
    "Luật Xây dựng 135/2025/QH15, QCVN 06:2022/BXD, TCVN 2737:2023, "
    "thiết kế cơ sở, thiết kế bản vẽ thi công, BIM, CDE, PCCC."
)
```

---

## 3. Kỹ Thuật Phân Tách Người Phát Biểu (Speaker Diarization)

Một bản gỡ băng thuần túy chỉ cho ra đoạn văn bản nối tiếp nhau mà không biết ai đang phát biểu. Hệ thống kết hợp hai tầng xử lý để gán nhãn người nói:

### 3.1. Phân tách theo Đặc trưng Âm học (Acoustic Diarization - Pyannote.audio)
Quy trình gồm 3 bước:
1. **Segmentation**: Chia luồng âm thanh thành các phân đoạn có tiếng người nói và phát hiện điểm chuyển giao lượt lời (Speaker Change Detection).
2. **Speaker Embedding Extraction**: Trích xuất vector đặc trưng giọng nói (thường dùng kiến trúc `ECAPA-TDNN` hoặc `WeSpeaker`, chiều dài 192 hoặc 256 chiều) cho từng đoạn ngắn 1.5 – 3 giây.
3. **Clustering (Agglomerative Hierarchical Clustering / Spectral Clustering)**: Gom nhóm các đoạn có cùng đặc trưng giọng nói vào các nhãn định danh tạm thời: `SPEAKER_00`, `SPEAKER_01`, `SPEAKER_02`...

### 3.2. Thuật toán Hợp nhất Dấu thời gian (Word-Level Timestamp Alignment)
Sau khi có kết quả từ **ASR** (danh sách các từ kèm `[start_time, end_time]`) và **Diarization** (danh sách các khoảng thời gian của từng `SPEAKER_XX`), hệ thống thực hiện phép giao thời gian (Temporal Intersection over Union):
- Mỗi câu hoặc cụm từ được gán cho `SPEAKER_XX` có tổng thời gian chồng lấp lớn nhất trong khoảng thời gian phát âm câu đó.
- Các câu liên tiếp của cùng một `SPEAKER_XX` (cách nhau dưới 2.0 giây) được gộp lại thành một **Lượt phát biểu hoàn chỉnh (Speaker Turn)**.

### 3.3. Định danh Tên Thật của Đại Biểu (Speaker Identification)
Có 2 cơ chế chuyển đổi từ nhãn vô danh (`SPEAKER_00`) sang tên thật và chức vụ (`Ông Nguyễn Văn A - Chủ trì`):
1. **Đối chiếu Ngữ cảnh Điều hành (Contextual Name Resolution)**:
   - Trong các cuộc họp hành chính, người chủ trì luôn giới thiệu trước khi chuyển lượt lời (ví dụ: `[SPEAKER_00]: "Xin mời đồng chí Trần Văn Bình, Trưởng phòng Kỹ thuật báo cáo..."` $\rightarrow$ Lượt lời ngay tiếp theo của `[SPEAKER_01]` được suy luận là `Ông Trần Văn Bình - Trưởng phòng Kỹ thuật`).
2. **Đăng ký Mẫu giọng (Voiceprint Enrollment / Reference Audio)**:
   - Lưu trữ một đoạn mẫu giọng dài 10–15 giây của các thành viên thường trực trong đơn vị dưới dạng vector nhúng (`.npy`). Khi họp, hệ thống tính độ tương đồng Cosine (`Cosine Similarity > 0.75`) để gán tên tự động ngay từ đầu cuộc họp.
