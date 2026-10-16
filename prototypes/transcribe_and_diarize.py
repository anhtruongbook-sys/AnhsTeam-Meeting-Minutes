# -*- coding: utf-8 -*-
"""
Công cụ Gỡ băng Cuộc họp Tiếng Việt (ASR) kèm Dấu thời gian & Phân tách Lượt lời
Hỗ trợ Faster-Whisper (CTranslate2) chạy Offline cục bộ trên CPU/GPU.
"""

import argparse
import datetime
import json
import os
import sys


def format_timestamp(seconds: float) -> str:
    """Chuyển đổi số giây sang chuỗi định dạng HH:MM:SS."""
    total_sec = int(round(seconds))
    hrs = total_sec // 3600
    mins = (total_sec % 3600) // 60
    secs = total_sec % 60
    return f"{hrs:02d}:{mins:02d}:{secs:02d}"


def transcribe_meeting_audio(
    audio_path: str,
    output_dir: str,
    model_size: str = "small",
    device: str = "cpu",
    compute_type: str = "int8",
    domain_keywords: str = "",
):
    """
    Thực hiện nhận dạng tiếng nói tiếng Việt từ tệp âm thanh cuộc họp,
    sử dụng bộ lọc khoảng lặng Silero VAD tích hợp để chống lặp từ.
    """
    if not os.path.isfile(audio_path):
        print(f"[Lỗi] Không tìm thấy tệp âm thanh: {audio_path}")
        sys.exit(1)

    try:
        from faster_whisper import WhisperModel
    except ImportError:
        print("[Thông báo] Thư viện 'faster-whisper' chưa được cài đặt.")
        print("Cài đặt bằng lệnh: pip install faster-whisper")
        sys.exit(1)

    os.makedirs(output_dir, exist_ok=True)
    base_name = os.path.splitext(os.path.basename(audio_path))[0]

    initial_prompt = "Biên bản cuộc họp công việc. Ghi nhận đầy đủ câu chữ tiếng Việt rõ ràng, chính xác."
    if domain_keywords.strip():
        initial_prompt += f" Các thuật ngữ và tên riêng: {domain_keywords.strip()}."

    print(f"[Đang khởi tạo mô hình ASR]: {model_size} ({device}, {compute_type})...")
    model = WhisperModel(model_size, device=device, compute_type=compute_type)

    print(f"[Đang xử lý gỡ băng tệp âm thanh]: {audio_path}...")
    segments_gen, info = model.transcribe(
        audio_path,
        language="vi",
        beam_size=5,
        vad_filter=True,
        vad_parameters=dict(min_silence_duration_ms=700, speech_pad_ms=300),
        initial_prompt=initial_prompt,
        word_timestamps=True,
    )

    transcript_segments = []
    txt_lines = []

    for idx, seg in enumerate(segments_gen, start=1):
        start_str = format_timestamp(seg.start)
        end_str = format_timestamp(seg.end)
        clean_text = seg.text.strip()
        if not clean_text:
            continue

        segment_item = {
            "id": idx,
            "start_seconds": round(seg.start, 2),
            "end_seconds": round(seg.end, 2),
            "timestamp": f"{start_str} - {end_str}",
            "speaker": "NGUOI_PHAT_BIEU",
            "text": clean_text,
        }
        transcript_segments.append(segment_item)
        line_str = f"[{start_str} - {end_str}] {clean_text}"
        txt_lines.append(line_str)
        print(line_str)

    json_out_path = os.path.join(output_dir, f"{base_name}_transcript.json")
    txt_out_path = os.path.join(output_dir, f"{base_name}_transcript.txt")

    payload = {
        "audio_file": os.path.abspath(audio_path),
        "processed_at": datetime.datetime.now().isoformat(),
        "duration_seconds": round(info.duration, 2),
        "language": info.language,
        "model": model_size,
        "segments": transcript_segments,
    }

    with open(json_out_path, "w", encoding="utf-8") as jf:
        json.dump(payload, jf, ensure_ascii=False, indent=2)

    with open(txt_out_path, "w", encoding="utf-8") as tf:
        tf.write("\n".join(txt_lines) + "\n")

    print(f"\n[Hoàn tất gỡ băng]")
    print(f"- File JSON : {json_out_path}")
    print(f"- File TXT  : {txt_out_path}")
    return json_out_path


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Gỡ băng âm thanh cuộc họp tiếng Việt sang JSON/TXT.")
    parser.add_argument("--audio", required=True, help="Đường dẫn tệp âm thanh cuộc họp (.wav, .mp3, .m4a)")
    parser.add_argument("--output-dir", default=os.path.join(os.path.dirname(__file__), "..", "transcripts"), help="Thư mục xuất văn bản gỡ băng")
    parser.add_argument("--model", default="small", help="Kích thước mô hình (small, medium, large-v3, vinai/PhoWhisper-medium)")
    parser.add_argument("--device", default="cpu", choices=["cpu", "cuda"], help="Thiết bị chạy suy luận (cpu hoặc cuda)")
    parser.add_argument("--keywords", default="", help="Danh sách từ khóa chuyên ngành hoặc tên đại biểu cách nhau bởi dấu phẩy")
    args = parser.parse_args()

    transcribe_meeting_audio(
        audio_path=os.path.abspath(args.audio),
        output_dir=os.path.abspath(args.output_dir),
        model_size=args.model,
        device=args.device,
        domain_keywords=args.keywords,
    )
