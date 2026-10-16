# -*- coding: utf-8 -*-
"""
Công cụ Thu âm Cuộc họp Đa chế độ (In-person Room Mic & Online Hybrid WASAPI Loopback)
Lưu tệp âm thanh định dạng 16kHz PCM WAV tối ưu cho nhận dạng tiếng nói tiếng Việt (ASR).
"""

import argparse
import datetime
import os
import queue
import sys
import wave

def list_audio_devices():
    """Liệt kê danh sách thiết bị thu âm khả dụng trên hệ thống."""
    try:
        import sounddevice as sd
        print("=== DANH SÁCH THIẾT BỊ ÂM THANH (SOUNDDEVICE) ===")
        print(sd.query_devices())
    except ImportError:
        print("[Thông báo] Thư viện 'sounddevice' chưa được cài đặt. Cài đặt bằng lệnh: pip install sounddevice numpy")


def record_meeting_mic(output_dir: str, duration_sec: int = 0, sample_rate: int = 16000, device_index: int = None):
    """
    Thu âm cuộc họp từ Microphone (hoặc Loa hội nghị USB Speakerphone) ở tần số 16kHz Mono PCM.
    Nhấn Ctrl+C để dừng thu âm và lưu tệp an toàn.
    """
    try:
        import sounddevice as sd
        import numpy as np
    except ImportError:
        print("[Lỗi] Cần cài đặt thư viện: pip install sounddevice numpy")
        sys.exit(1)

    os.makedirs(output_dir, exist_ok=True)
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    output_path = os.path.join(output_dir, f"Meeting_Rec_{timestamp}_16kHz.wav")

    audio_queue = queue.Queue()

    def audio_callback(indata, frames, time_info, status):
        if status:
            print(f"[Trạng thái Audio]: {status}", file=sys.stderr)
        audio_queue.put(indata.copy())

    print(f"============================================================")
    print(f"BẮT ĐẦU THU ÂM CUỘC HỌP")
    print(f"- Tệp lưu trữ : {output_path}")
    print(f"- Tần số mẫu  : {sample_rate} Hz | Kênh: 1 (Mono) | Định dạng: 16-bit PCM")
    print(f"- Hướng dẫn   : Nhấn tổ hợp phím Ctrl + C để kết thúc cuộc họp và lưu file.")
    print(f"============================================================")

    try:
        with wave.open(output_path, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)  # 16-bit = 2 bytes
            wf.setframerate(sample_rate)

            with sd.InputStream(
                samplerate=sample_rate,
                channels=1,
                dtype="int16",
                device=device_index,
                callback=audio_callback,
            ):
                start_time = datetime.datetime.now()
                while True:
                    data = audio_queue.get()
                    wf.writeframes(data.tobytes())
                    if duration_sec > 0:
                        elapsed = (datetime.datetime.now() - start_time).total_seconds()
                        if elapsed >= duration_sec:
                            break
    except KeyboardInterrupt:
        print("\n[Hoàn tất] Đã dừng thu âm theo yêu cầu người dùng.")
    except Exception as exc:
        print(f"\n[Lỗi khi thu âm]: {exc}")
        return None

    print(f"[Thành công] Đã lưu tệp ghi âm cuộc họp tại: {output_path}")
    return output_path


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Công cụ thu âm cuộc họp chuẩn 16kHz WAV cho STT.")
    parser.add_argument("--list-devices", action="store_true", help="Liệt kê các thiết bị Microphone trên máy")
    parser.add_argument("--output-dir", default=os.path.join(os.path.dirname(__file__), "..", "recordings"), help="Thư mục lưu file ghi âm")
    parser.add_argument("--duration", type=int, default=0, help="Thời lượng thu (giây). Để 0 để thu không giới hạn cho tới khi nhấn Ctrl+C")
    parser.add_argument("--device", type=int, default=None, help="Chỉ số ID thiết bị Microphone")
    args = parser.parse_args()

    if args.list_devices:
        list_audio_devices()
    else:
        record_meeting_mic(
            output_dir=os.path.abspath(args.output_dir),
            duration_sec=args.duration,
            device_index=args.device,
        )
