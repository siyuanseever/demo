from __future__ import annotations

import hashlib
import json
import logging
import os
import re
import struct
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


HOST = os.getenv("TTS_HOST", "127.0.0.1")
PORT = int(os.getenv("TTS_PORT", "8768"))
MODEL_ID = os.getenv(
    "TTS_MODEL",
    "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit",
)
DEFAULT_VOICE = "Serena"
DEFAULT_INSTRUCT = (
    "温柔、自然、安静地说，像一位年轻女孩在夜晚陪伴亲近的朋友。"
    "语速稍慢，不要播音腔，不要夸张卖萌。"
)
CACHE_DIR = Path(os.getenv("TTS_CACHE_DIR", "data/tts_cache"))
GENERATION_TIMEOUT = int(os.getenv("TTS_TIMEOUT", "45"))
MAX_TOKENS_PER_CHAR = int(os.getenv("TTS_MAX_TOKENS_PER_CHAR", "8"))
MIN_MAX_TOKENS = int(os.getenv("TTS_MIN_MAX_TOKENS", "500"))
HARD_MAX_TOKENS = int(os.getenv("TTS_HARD_MAX_TOKENS", "4096"))
TEMPERATURE = float(os.getenv("TTS_TEMPERATURE", "0.9"))
REPETITION_PENALTY = float(os.getenv("TTS_REPETITION_PENALTY", "1.05"))
TOP_P = float(os.getenv("TTS_TOP_P", "1.0"))
MAX_SEGMENT_CHARS = int(os.getenv("TTS_MAX_SEGMENT_CHARS", "150"))
MAX_RETRIES = int(os.getenv("TTS_MAX_RETRIES", "2"))
MIN_RMS = float(os.getenv("TTS_MIN_RMS", "0.01"))
EXPECTED_SECONDS_PER_CHAR = float(os.getenv("TTS_SECONDS_PER_CHAR", "0.2"))
MAX_DURATION_RATIO = float(os.getenv("TTS_MAX_DURATION_RATIO", "2.5"))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)
logger = logging.getLogger("app.tts_server")


class LocalTTS:
    def __init__(self) -> None:
        self._model = None
        self._load_lock = threading.Lock()
        self._generation_lock = threading.Lock()
        self._cancel_count = 0
        self._cancel_lock = threading.Lock()

    @property
    def loaded(self) -> bool:
        return self._model is not None

    def cancel_current(self) -> None:
        """Signal the currently running generation to abort."""
        with self._cancel_lock:
            self._cancel_count += 1
            count = self._cancel_count
        logger.info("cancel signal sent (count=%d)", count)

    def _is_cancelled(self, my_count: int) -> bool:
        with self._cancel_lock:
            return self._cancel_count > my_count

    def _load_model(self):
        if self._model is not None:
            return self._model
        with self._load_lock:
            if self._model is None:
                from mlx_audio.tts.utils import load_model

                logger.info("loading model=%s", MODEL_ID)
                self._model = load_model(MODEL_ID)
                logger.info("model ready=%s", MODEL_ID)
        return self._model

    # ------------------------------------------------------------------
    # Cache key
    # ------------------------------------------------------------------

    @staticmethod
    def _cache_key(text: str, voice: str, instruct: str) -> str:
        return hashlib.sha256(
            json.dumps(
                {
                    "model": MODEL_ID,
                    "text": text,
                    "voice": voice,
                    "instruct": instruct,
                },
                ensure_ascii=False,
                sort_keys=True,
            ).encode("utf-8")
        ).hexdigest()

    # ------------------------------------------------------------------
    # Non-streaming synthesis (returns complete WAV bytes)
    # ------------------------------------------------------------------

    def synthesize(self, text: str, voice: str, instruct: str) -> bytes:
        cache_key = self._cache_key(text, voice, instruct)
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        cache_path = CACHE_DIR / f"{cache_key}.wav"
        if cache_path.exists():
            logger.info("cache hit chars=%d", len(text))
            return cache_path.read_bytes()

        with self._generation_lock:
            if cache_path.exists():
                return cache_path.read_bytes()

            import mlx.core as mx
            import numpy as np
            from mlx_audio.audio_io import write as audio_write

            model = self._load_model()
            segments = self._split_text(text)
            logger.info(
                "generation start chars=%d segments=%d voice=%s",
                len(text), len(segments), voice,
            )

            all_audio = []
            result_sample_rate = None

            for i, seg in enumerate(segments):
                seg_audio, seg_sr = self._generate_segment(
                    model, seg, voice, instruct, i + 1, len(segments),
                )
                if seg_audio is not None:
                    if result_sample_rate is None:
                        result_sample_rate = seg_sr
                    all_audio.append(seg_audio)
                self._clear_metal_cache()

            if not all_audio:
                raise RuntimeError("TTS model returned no audio for any segment")

            full_audio = (
                np.concatenate(all_audio, axis=0)
                if len(all_audio) > 1
                else all_audio[0]
            )
            trimmed = self._trim_tail_silence(full_audio, result_sample_rate)
            if len(trimmed) < len(full_audio):
                logger.info(
                    "trimmed silence: %d -> %d samples (%.1f%%)",
                    len(full_audio), len(trimmed),
                    (1 - len(trimmed) / len(full_audio)) * 100,
                )
            if len(trimmed) == 0:
                raise RuntimeError("TTS audio is empty after trimming")

            result_audio = mx.array(trimmed)
            temporary_path = cache_path.with_suffix(".tmp.wav")
            audio_write(str(temporary_path), result_audio, result_sample_rate, format="wav")
            temporary_path.replace(cache_path)
            file_size = cache_path.stat().st_size
            duration = len(trimmed) / result_sample_rate
            logger.info(
                "generation done chars=%d bytes=%d duration=%.1fs segments=%d",
                len(text), file_size, duration, len(segments),
            )

            try:
                import gc
                gc.collect()
            except Exception:
                pass

            return cache_path.read_bytes()

    # ------------------------------------------------------------------
    # Streaming synthesis (calls send_chunk for each piece of audio)
    # ------------------------------------------------------------------

    def synthesize_streaming(
        self,
        text: str,
        voice: str,
        instruct: str,
        send_chunk,
    ) -> None:
        """Generate audio segment by segment.

        send_chunk(bytes) is called with:
          1. A 44-byte WAV header (once, before any audio data)
          2. Raw int16 PCM data for each segment (immediately after generation)
        """
        cache_key = self._cache_key(text, voice, instruct)
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        cache_path = CACHE_DIR / f"{cache_key}.wav"

        # Cache hit: send the entire file as two chunks (header + data)
        if cache_path.exists():
            logger.info("cache hit (streaming) chars=%d", len(text))
            wav_bytes = cache_path.read_bytes()
            send_chunk(wav_bytes[:44])
            if len(wav_bytes) > 44:
                send_chunk(wav_bytes[44:])
            return

        with self._generation_lock:
            if cache_path.exists():
                wav_bytes = cache_path.read_bytes()
                send_chunk(wav_bytes[:44])
                if len(wav_bytes) > 44:
                    send_chunk(wav_bytes[44:])
                return

            import mlx.core as mx
            import numpy as np
            from mlx_audio.audio_io import write as audio_write

            # Record cancel count at start; abort if a newer request arrives
            with self._cancel_lock:
                my_count = self._cancel_count

            model = self._load_model()
            segments = self._split_text(text)
            logger.info(
                "streaming start chars=%d segments=%d voice=%s cancel_count=%d",
                len(text), len(segments), voice, my_count,
            )

            all_audio = []
            sample_rate = None
            header_sent = False
            client_gone = False

            for i, seg in enumerate(segments):
                if client_gone:
                    break
                if self._is_cancelled(my_count):
                    logger.info(
                        "superseded by newer request, aborting at segment %d/%d",
                        i + 1, len(segments),
                    )
                    return

                seg_audio, seg_sr = self._generate_segment(
                    model, seg, voice, instruct, i + 1, len(segments), my_count,
                )

                if seg_audio is None:
                    self._clear_metal_cache()
                    continue

                if not header_sent:
                    sample_rate = seg_sr
                    header = self._make_wav_header(sample_rate)
                    try:
                        send_chunk(header)
                    except (BrokenPipeError, ConnectionResetError):
                        client_gone = True
                        break
                    header_sent = True

                # Trim tail silence per segment
                trimmed = self._trim_tail_silence(seg_audio, sample_rate)
                pcm_bytes = self._float_to_int16_bytes(trimmed)
                try:
                    send_chunk(pcm_bytes)
                except (BrokenPipeError, ConnectionResetError):
                    client_gone = True
                    break

                all_audio.append(trimmed)
                self._clear_metal_cache()

            if all_audio and not client_gone:
                # Save to cache for future requests
                full_audio = (
                    np.concatenate(all_audio, axis=0)
                    if len(all_audio) > 1
                    else all_audio[0]
                )
                result_audio = mx.array(full_audio)
                temporary_path = cache_path.with_suffix(".tmp.wav")
                audio_write(str(temporary_path), result_audio, sample_rate, format="wav")
                temporary_path.replace(cache_path)
                file_size = cache_path.stat().st_size
                duration = len(full_audio) / sample_rate
                logger.info(
                    "streaming done chars=%d bytes=%d duration=%.1fs segments=%d",
                    len(text), file_size, duration, len(segments),
                )

            try:
                import gc
                gc.collect()
            except Exception:
                pass

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _clear_metal_cache() -> None:
        try:
            import mlx.core as mx
            mx.clear_cache()
        except Exception:
            pass
        try:
            import mlx.metal as mx_metal
            mx_metal.clear_cache()
        except Exception:
            pass

    @staticmethod
    def _make_wav_header(
        sample_rate: int,
        num_channels: int = 1,
        bits_per_sample: int = 16,
    ) -> bytes:
        """Create a streaming WAV header (data size = 0xFFFFFFFF)."""
        byte_rate = sample_rate * num_channels * bits_per_sample // 8
        block_align = num_channels * bits_per_sample // 8
        return struct.pack(
            "<4sI4s4sIHHIIHH4sI",
            b"RIFF",
            0xFFFFFFFF,
            b"WAVE",
            b"fmt ",
            16,
            1,
            num_channels,
            sample_rate,
            byte_rate,
            block_align,
            bits_per_sample,
            b"data",
            0xFFFFFFFF,
        )

    @staticmethod
    def _float_to_int16_bytes(audio_np) -> bytes:
        """Convert float32 audio [-1, 1] to int16 PCM bytes."""
        import numpy as np

        clipped = np.clip(audio_np, -1.0, 1.0)
        return (clipped * 32767).astype(np.int16).tobytes()

    def _split_text(self, text: str) -> list[str]:
        """Split text into segments by sentence-ending punctuation."""
        sentences = re.split(r"(?<=[。！？；\n])", text)
        sentences = [s.strip() for s in sentences if s.strip()]

        merged: list[str] = []
        buffer = ""
        for s in sentences:
            if len(buffer) + len(s) <= MAX_SEGMENT_CHARS:
                buffer += s
            else:
                if buffer:
                    merged.append(buffer)
                    buffer = ""
                if len(s) > MAX_SEGMENT_CHARS:
                    sub_parts = re.split(r"(?<=[，,、：:])", s)
                    sub_parts = [p for p in sub_parts if p.strip()]
                    sub_buf = ""
                    for p in sub_parts:
                        if len(sub_buf) + len(p) <= MAX_SEGMENT_CHARS:
                            sub_buf += p
                        else:
                            if sub_buf:
                                merged.append(sub_buf)
                            sub_buf = p
                    if sub_buf:
                        merged.append(sub_buf)
                else:
                    buffer = s
        if buffer:
            merged.append(buffer)

        # Force-split any remaining over-long segments
        final: list[str] = []
        for seg in merged:
            while len(seg) > MAX_SEGMENT_CHARS:
                final.append(seg[:MAX_SEGMENT_CHARS])
                seg = seg[MAX_SEGMENT_CHARS:]
            if seg:
                final.append(seg)

        return final if final else [text]

    def _generate_segment(
        self,
        model,
        text: str,
        voice: str,
        instruct: str,
        idx: int,
        total: int,
        my_count: int = -1,
    ):
        """Generate audio for one segment. Returns (np.array, sample_rate) or (None, None).

        Uses non-streaming generation for stability. Includes quality check and retry.
        Aborts early if a newer request arrives (cancel_count > my_count).
        """
        import numpy as np

        calculated_max = max(MIN_MAX_TOKENS, len(text) * MAX_TOKENS_PER_CHAR)
        effective_max = min(calculated_max, HARD_MAX_TOKENS)
        expected_duration = len(text) * EXPECTED_SECONDS_PER_CHAR
        max_allowed_duration = expected_duration * MAX_DURATION_RATIO

        for attempt in range(MAX_RETRIES + 1):
            if my_count >= 0 and self._is_cancelled(my_count):
                logger.info(
                    "segment %d/%d cancelled by newer request",
                    idx, total,
                )
                return None, None

            logger.info(
                "segment %d/%d attempt %d/%d chars=%d max_tokens=%d",
                idx, total, attempt + 1, MAX_RETRIES + 1, len(text), effective_max,
            )

            result_audio = None
            result_sample_rate = None
            start_time = time.time()
            timed_out = False

            try:
                generator = model.generate(
                    text=text,
                    voice=voice,
                    instruct=instruct,
                    lang_code="Chinese",
                    speed=1.0,
                    split_pattern="\n",
                    max_tokens=effective_max,
                    verbose=False,
                    temperature=TEMPERATURE,
                    repetition_penalty=REPETITION_PENALTY,
                    top_p=TOP_P,
                    stream=False,
                )
                for result in generator:
                    elapsed = time.time() - start_time
                    if elapsed > GENERATION_TIMEOUT:
                        timed_out = True
                        break
                    result_audio = np.array(result.audio)
                    result_sample_rate = result.sample_rate
                if timed_out:
                    logger.warning(
                        "segment %d/%d timed out after %.1fs (attempt %d)",
                        idx, total, time.time() - start_time, attempt + 1,
                    )

            except Exception:
                logger.exception("segment %d/%d generation error (attempt %d)", idx, total, attempt + 1)
                self._clear_metal_cache()
                continue

            if result_audio is None or len(result_audio) == 0:
                logger.warning(
                    "segment %d/%d empty audio (attempt %d)",
                    idx, total, attempt + 1,
                )
                self._clear_metal_cache()
                continue

            duration = len(result_audio) / result_sample_rate
            rms = float(np.sqrt(np.mean(result_audio ** 2)))

            is_too_long = duration > max_allowed_duration
            is_too_quiet = rms < MIN_RMS

            if not is_too_long and not is_too_quiet:
                elapsed = time.time() - start_time
                logger.info(
                    "segment %d/%d ok chars=%d samples=%d duration=%.1fs rms=%.4f %.1fs",
                    idx, total, len(text), len(result_audio), duration, rms, elapsed,
                )
                return result_audio, result_sample_rate

            logger.warning(
                "segment %d/%d quality issue: %s%s duration=%.1fs (expected ~%.1fs, max %.1fs) rms=%.4f (attempt %d)",
                idx, total,
                "too_long " if is_too_long else "",
                "too_quiet " if is_too_quiet else "",
                duration, expected_duration, max_allowed_duration, rms,
                attempt + 1,
            )
            self._clear_metal_cache()

        logger.error(
            "segment %d/%d failed after %d attempts chars=%d",
            idx, total, MAX_RETRIES + 1, len(text),
        )
        return None, None

    def _trim_tail_silence(
        self,
        audio,
        sample_rate: int,
        threshold: float = 0.005,
        min_silence_duration: float = 0.15,
    ):
        import numpy as np

        if len(audio) == 0:
            return audio

        window_size = int(sample_rate * 0.02)
        hop = window_size // 2
        min_silence_samples = int(sample_rate * min_silence_duration)

        tail_silence_start = len(audio)
        pos = len(audio) - window_size

        while pos > 0:
            window = audio[pos:pos + window_size]
            rms = np.sqrt(np.mean(window ** 2))
            if rms > threshold:
                break
            tail_silence_start = pos
            pos -= hop

        silence_length = len(audio) - tail_silence_start
        if silence_length > min_silence_samples:
            return audio[:tail_silence_start + min_silence_samples]
        return audio


tts = LocalTTS()


class TTSRequestHandler(BaseHTTPRequestHandler):
    server_version = "SensenLocalTTS/1.0"
    protocol_version = "HTTP/1.1"

    def do_GET(self) -> None:
        if self.path != "/health":
            self._json_response(404, {"error": "not_found"})
            return
        self._json_response(
            200,
            {
                "status": "ok",
                "model": MODEL_ID,
                "voice": DEFAULT_VOICE,
                "loaded": tts.loaded,
            },
        )

    def do_POST(self) -> None:
        if self.path == "/v1/audio/speech/stream":
            self._handle_streaming()
            return
        if self.path != "/v1/audio/speech":
            self._json_response(404, {"error": "not_found"})
            return

        # Non-streaming endpoint (backward compatible)
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            if content_length <= 0 or content_length > 64_000:
                raise ValueError("invalid request size")
            payload = json.loads(self.rfile.read(content_length).decode("utf-8"))
            text = str(payload.get("input", "")).strip()
            if not text or len(text) > 6_000:
                raise ValueError("input must contain 1-6000 characters")
            voice = str(payload.get("voice", DEFAULT_VOICE)).strip() or DEFAULT_VOICE
            instruct = str(payload.get("instruct", DEFAULT_INSTRUCT)).strip() or DEFAULT_INSTRUCT
            audio = tts.synthesize(text, voice, instruct)
            self.send_response(200)
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(len(audio)))
            self.send_header("Cache-Control", "private, max-age=86400")
            self.end_headers()
            self.wfile.write(audio)
        except (BrokenPipeError, ConnectionResetError) as error:
            logger.info("client disconnected: %s", type(error).__name__)
        except ValueError as error:
            self._json_response(400, {"error": str(error)})
        except Exception as error:
            logger.exception("generation failed")
            try:
                self._json_response(500, {"error": type(error).__name__})
            except (BrokenPipeError, ConnectionResetError):
                pass

    # ------------------------------------------------------------------
    # Streaming endpoint
    # ------------------------------------------------------------------

    def _handle_streaming(self) -> None:
        # Parse request first (before sending any headers)
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            if content_length <= 0 or content_length > 64_000:
                raise ValueError("invalid request size")
            payload = json.loads(self.rfile.read(content_length).decode("utf-8"))
            text = str(payload.get("input", "")).strip()
            if not text or len(text) > 6_000:
                raise ValueError("input must contain 1-6000 characters")
            voice = str(payload.get("voice", DEFAULT_VOICE)).strip() or DEFAULT_VOICE
            instruct = str(payload.get("instruct", DEFAULT_INSTRUCT)).strip() or DEFAULT_INSTRUCT
        except ValueError as error:
            self._json_response(400, {"error": str(error)})
            return
        except Exception:
            self._json_response(500, {"error": "parse_error"})
            return

        # Start chunked response
        try:
            self.send_response(200)
            self.send_header("Content-Type", "audio/x-streaming-wav")
            self.send_header("Transfer-Encoding", "chunked")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
        except Exception:
            return

        def send_chunk(data: bytes) -> None:
            """Write one HTTP chunk: <hex-size>\\r\\n<data>\\r\\n"""
            self.wfile.write(f"{len(data):x}\r\n".encode("ascii"))
            self.wfile.write(data)
            self.wfile.write(b"\r\n")
            self.wfile.flush()

        # Cancel any currently running generation so this request can start ASAP
        tts.cancel_current()

        try:
            tts.synthesize_streaming(text, voice, instruct, send_chunk)
            # End chunked transfer
            self.wfile.write(b"0\r\n\r\n")
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            logger.info("client disconnected during streaming")
        except Exception:
            logger.exception("streaming generation failed")

    def log_message(self, format: str, *args) -> None:
        logger.info("http %s", format % args)

    def _json_response(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), TTSRequestHandler)
    logger.info("local TTS listening http://%s:%d model=%s", HOST, PORT, MODEL_ID)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
