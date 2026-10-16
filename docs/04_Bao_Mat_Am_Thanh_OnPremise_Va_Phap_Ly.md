# 04. Giải Pháp Xử Lý Bảo Mật Nội Bộ (On-Premise Offline) & Khía Cạnh Pháp Lý

Tài liệu này phân tích các yêu cầu về bảo mật thông tin đối với dữ liệu ghi âm cuộc họp nội bộ và quy định pháp luật hiện hành về ghi âm, lưu trữ và xử lý biên bản cuộc họp.

---

## 1. Tại Sao Cần Kiến Trúc Xử Lý Offline (On-Premise) Cho Cuộc Họp Nội Bộ?

Nội dung các cuộc họp giao ban điều hành, họp hội đồng quản trị, họp thẩm tra kỹ thuật hoặc đàm phán hợp đồng thường chứa:
- Số liệu dự toán, giá chào thầu, chiến lược kinh doanh chưa công bố.
- Thông tin kỹ thuật của công trình, dự án hoặc dữ liệu cá nhân của nhân sự/đối tác.

Nếu tải tệp âm thanh lên các dịch vụ chuyển giọng nói thành văn bản trực tuyến miễn phí của bên thứ ba (Public Cloud SaaS), dữ liệu âm thanh có nguy cơ bị lưu trữ trên máy chủ nước ngoài hoặc được sử dụng để huấn luyện mô hình. Do đó, đối với các cuộc họp quan trọng, hệ thống cần hỗ trợ **Chế độ vận hành Độc lập 100% Không cần Internet (Air-Gapped / Local On-Premise)**.

---

## 2. Cấu Hình Phần Cứng Đề Xuất Cho Hệ Thống On-Premise

| Cấu hình | Thành phần phần cứng | Mô hình chạy cục bộ (Offline) | Tốc độ xử lý trung bình (Cho 60 phút ghi âm) |
| :--- | :--- | :--- | :--- |
| **Cấu hình Tiêu chuẩn (Laptop / PC Văn phòng)** | CPU Intel Core i5/i7 hoặc AMD Ryzen 5/7, RAM 16GB (Không có GPU rời) | `Faster-Whisper Small/Medium (INT8)` + `Silero VAD` | Khoảng 8 – 12 phút xử lý |
| **Cấu hình Trạm làm việc (Workstation GPU)** | GPU NVIDIA RTX 3060 / 4060 trở lên ($\ge$ 8GB VRAM), RAM 32GB | `Faster-Whisper Large-v3` hoặc `PhoWhisper-Large` + `Pyannote.audio 3.1` + Local LLM (`Qwen2.5-14B-Instruct` / `Llama-3.1-8B` qua Ollama/vLLM) | Khoảng 1.5 – 2.5 phút xử lý toàn trình |

---

## 3. Quy Trình Bảo Vệ Dữ Liệu Âm Thanh & Văn Bản Gỡ Băng

1. **Thông báo và Sự đồng thuận trong Cuộc họp**:
   - Theo nguyên tắc minh bạch hành chính và quy định tại **Nghị định số 13/2023/NĐ-CP** về bảo vệ dữ liệu cá nhân, khi ghi âm cuộc họp chính thức để phục vụ công tác lập biên bản của Thư ký, Chủ trì hoặc Thư ký cuộc họp thông báo rõ việc ghi âm phục vụ lập biên bản nội bộ.
2. **Liên kết Kiểm chứng Ngược (Audio-to-Text Traceability)**:
   - Mỗi mục nội dung phát biểu trong bản nháp biên bản đều lưu giữ mốc thời gian `[HH:MM:SS]` tương ứng trong tệp âm thanh gốc. Khi có ý kiến thắc mắc về câu chữ trong dự thảo biên bản, Thư ký có thể mở lại đúng giây phát biểu đó để đối chứng trước khi các bên ký xác nhận.
3. **Chính sách Lưu trữ và Hủy tệp Âm thanh Tạm (Retention Policy)**:
   - Sau khi Biên bản cuộc họp chính thức đã được Chủ trì và Thư ký ký ban hành (hoặc đóng dấu lưu văn thư), tệp ghi âm gốc có thể được mã hóa lưu trữ (`AES-256`) theo thời hạn quy chế nội bộ của đơn vị hoặc xóa an toàn khỏi thiết bị thu âm cá nhân.
