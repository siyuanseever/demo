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
from typing import Any


HOST = os.getenv("TTS_HOST", "127.0.0.1")
PORT = int(os.getenv("TTS_PORT", "8768"))
MODEL_ID = os.getenv(
    "TTS_MODEL",
    "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit",
)
DEFAULT_VOICE = "Serena"
DEFAULT_INSTRUCT = (
    "平静、克制、自然地说，像一位年轻女孩在安静地陪伴朋友。"
    "保持稳定音量和清晰发音，情绪起伏小，不使用哭腔、气声、播音腔或撒娇语气。"
)
CACHE_DIR = Path(os.getenv("TTS_CACHE_DIR", "data/tts_cache"))
GENERATION_TIMEOUT = int(os.getenv("TTS_TIMEOUT", "45"))
MAX_TOKENS_PER_CHAR = int(os.getenv("TTS_MAX_TOKENS_PER_CHAR", "5"))
MIN_MAX_TOKENS = int(os.getenv("TTS_MIN_MAX_TOKENS", "120"))
HARD_MAX_TOKENS = int(os.getenv("TTS_HARD_MAX_TOKENS", "384"))
TEMPERATURE = float(os.getenv("TTS_TEMPERATURE", "0.65"))
REPETITION_PENALTY = float(os.getenv("TTS_REPETITION_PENALTY", "1.12"))
TOP_P = float(os.getenv("TTS_TOP_P", "0.92"))
MAX_SEGMENT_CHARS = int(os.getenv("TTS_MAX_SEGMENT_CHARS", "42"))
MAX_RETRIES = int(os.getenv("TTS_MAX_RETRIES", "2"))
MIN_RMS = float(os.getenv("TTS_MIN_RMS", "0.006"))
EXPECTED_SECONDS_PER_CHAR = float(os.getenv("TTS_SECONDS_PER_CHAR", "0.28"))
MAX_DURATION_RATIO = float(os.getenv("TTS_MAX_DURATION_RATIO", "2.4"))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)
logger = logging.getLogger("app.tts_server")


class TTSRequestCancelled(RuntimeError):
    pass


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
                from mlx_audio.tts.utils import load_model  # type: ignore[reportMissingImports]

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

        with self._cancel_lock:
            my_count = self._cancel_count

        with self._generation_lock:
            if self._is_cancelled(my_count):
                raise TTSRequestCancelled("superseded before generation started")
            if cache_path.exists():
                return cache_path.read_bytes()

            import mlx.core as mx  # type: ignore[reportMissingImports]
            import numpy as np
            from mlx_audio.audio_io import write as audio_write  # type: ignore[reportMissingImports]

            model = self._load_model()
            segments = self._split_text(text)
            logger.info(
                "generation start chars=%d segments=%d voice=%s",
                len(text), len(segments), voice,
            )
            self._log_segments(segments)

            all_audio = []
            result_sample_rate: int | None = None
            for i, seg in enumerate(segments):
                seg_audio, seg_sr = self._generate_segment(
                    model, seg, voice, instruct, i + 1, len(segments), my_count,
                )
                if seg_audio is None:
                    raise TTSRequestCancelled(
                        f"TTS segment {i + 1}/{len(segments)} was cancelled"
                    )
                if result_sample_rate is None:
                    result_sample_rate = seg_sr
                all_audio.append(seg_audio)
                self._clear_metal_cache()

            if not all_audio:
                raise RuntimeError("TTS model returned no audio for any segment")
            assert result_sample_rate is not None

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

            import mlx.core as mx  # type: ignore[reportMissingImports]
            import numpy as np
            from mlx_audio.audio_io import write as audio_write  # type: ignore[reportMissingImports]

            # Record cancel count at start; abort if a newer request arrives
            with self._cancel_lock:
                my_count = self._cancel_count

            model = self._load_model()
            segments = self._split_text(text)
            logger.info(
                "streaming start chars=%d segments=%d voice=%s cancel_count=%d",
                len(text), len(segments), voice, my_count,
            )
            self._log_segments(segments)

            all_audio = []
            sample_rate: int | None = None
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
                    raise TTSRequestCancelled("superseded by newer request")
                seg_audio, seg_sr = self._generate_segment(
                    model, seg, voice, instruct, i + 1, len(segments), my_count,
                )

                if seg_audio is None:
                    if self._is_cancelled(my_count):
                        raise TTSRequestCancelled("superseded by newer request")
                    raise RuntimeError(
                        f"TTS segment {i + 1}/{len(segments)} failed after retries"
                    )

                if not header_sent:
                    sample_rate = seg_sr
                    assert sample_rate is not None
                    header = self._make_wav_header(sample_rate)
                    try:
                        send_chunk(header)
                    except (BrokenPipeError, ConnectionResetError):
                        client_gone = True
                        break
                    header_sent = True

                assert sample_rate is not None
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
                assert sample_rate is not None
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

    def _clear_metal_cache(self) -> None:
        """Aggressively clear MLX Metal state to prevent degradation across calls."""
        # 1. Clear buffer cache
        try:
            import mlx.core as mx  # type: ignore[reportMissingImports]
            mx.clear_cache()
        except Exception:
            pass

        # 2. Force-release all cached Metal buffers by temporarily setting limit to 0
        try:
            import mlx.metal as mx_metal  # type: ignore[reportMissingImports]
            original_limit = mx_metal.get_cache_memory()
            mx_metal.set_cache_limit(0)
            mx_metal.clear_cache()
            # Restore a reasonable cache limit (200MB)
            mx_metal.set_cache_limit(200 * 1024 * 1024)
        except Exception:
            pass

        # 3. Reset decoder streaming state (cleans up residual buffers from interrupted generations)
        if self._model is not None:
            try:
                speech_tokenizer = getattr(self._model, 'speech_tokenizer', None)
                if speech_tokenizer is not None:
                    decoder = getattr(speech_tokenizer, 'decoder', None)
                    if decoder is not None and hasattr(decoder, 'reset_streaming_state'):
                        decoder.reset_streaming_state()
            except Exception:
                pass

        # 4. Reset peak memory counter for better diagnostics
        try:
            import mlx.metal as mx_metal  # type: ignore[reportMissingImports]
            mx_metal.reset_peak_memory()
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

    @staticmethod
    def _log_segments(segments: list[str]) -> None:
        for index, segment in enumerate(segments, start=1):
            preview = segment.replace("\n", "\\n")
            logger.info(
                "segment input %d/%d chars=%d text=%s",
                index,
                len(segments),
                len(segment),
                json.dumps(preview, ensure_ascii=False),
            )

    def _generate_segment(
        self,
        model,
        text: str,
        voice: str,
        instruct: str,
        idx: int,
        total: int,
        my_count: int = -1,
    ) -> tuple[Any, Any]:
        """Generate audio for one segment.

        Returns (np.array, sample_rate), or (None, None) when cancelled.
        """
        import numpy as np

        expected_duration = len(text) * EXPECTED_SECONDS_PER_CHAR
        max_allowed_duration = max(6.0, expected_duration * MAX_DURATION_RATIO)

        if my_count >= 0 and self._is_cancelled(my_count):
            logger.info("segment %d/%d cancelled by newer request", idx, total)
            return None, None

        base_max = min(
            max(MIN_MAX_TOKENS, len(text) * MAX_TOKENS_PER_CHAR),
            HARD_MAX_TOKENS,
        )
        attempt_settings = (
            (1.0, TEMPERATURE, TOP_P, instruct),
            (
                0.85,
                min(TEMPERATURE + 0.15, 0.85),
                min(TOP_P + 0.05, 1.0),
                instruct + " 请逐字完整朗读，音量稳定，不拖长尾音。",
            ),
            (
                0.7,
                max(TEMPERATURE - 0.1, 0.4),
                max(TOP_P - 0.08, 0.75),
                instruct + " 请清晰、平稳、简短地完整朗读，不添加额外情绪。",
            ),
        )

        for attempt in range(MAX_RETRIES + 1):
            if my_count >= 0 and self._is_cancelled(my_count):
                return None, None
            token_scale, temperature, top_p, attempt_instruct = attempt_settings[
                min(attempt, len(attempt_settings) - 1)
            ]
            effective_max = max(96, int(base_max * token_scale))
            logger.info(
                "segment %d/%d attempt=%d/%d chars=%d max_tokens=%d temp=%.2f top_p=%.2f",
                idx, total, attempt + 1, MAX_RETRIES + 1, len(text),
                effective_max, temperature, top_p,
            )
            result_audio = None
            result_sample_rate = None
            token_count = 0
            start_time = time.time()
            try:
                generator = model.generate(
                    text=text,
                    voice=voice,
                    instruct=attempt_instruct,
                    lang_code="Chinese",
                    speed=1.0,
                    split_pattern="\n",
                    max_tokens=effective_max,
                    verbose=False,
                    temperature=temperature,
                    repetition_penalty=REPETITION_PENALTY + attempt * 0.02,
                    top_p=top_p,
                    stream=False,
                )
                for result in generator:
                    result_audio = np.array(result.audio)
                    result_sample_rate = result.sample_rate
                    token_count = int(getattr(result, "token_count", 0) or 0)
            except Exception:
                logger.exception(
                    "segment %d/%d attempt=%d generation error",
                    idx, total, attempt + 1,
                )

            elapsed = time.time() - start_time
            reasons: list[str] = []
            if elapsed > GENERATION_TIMEOUT:
                reasons.append("timeout")
            if result_audio is None or len(result_audio) == 0 or not result_sample_rate:
                reasons.append("empty")
                duration = 0.0
                rms = 0.0
                peak = 0.0
            else:
                duration = len(result_audio) / result_sample_rate
                absolute = np.abs(result_audio)
                peak = float(np.max(absolute))
                active_audio = result_audio[absolute > 0.003]
                rms = (
                    float(np.sqrt(np.mean(active_audio ** 2)))
                    if len(active_audio) else 0.0
                )
                if duration > max_allowed_duration:
                    reasons.append("too_long")
                if peak < 0.02 or rms < MIN_RMS:
                    reasons.append("too_quiet")
                if token_count >= int(effective_max * 0.92):
                    reasons.append("token_limit")
                envelope_cv, zero_crossing_rate = self._speech_variation(
                    result_audio,
                    result_sample_rate,
                )
                if (
                    len(text) >= 15
                    and duration >= 4.0
                    and envelope_cv < 0.22
                    and zero_crossing_rate < 0.018
                ):
                    reasons.append("low_speech_variation")

            if not reasons:
                logger.info(
                    "segment %d/%d ok attempt=%d chars=%d duration=%.1fs "
                    "tokens=%d active_rms=%.4f peak=%.4f elapsed=%.1fs",
                    idx, total, attempt + 1, len(text), duration, token_count,
                    rms, peak, elapsed,
                )
                return result_audio, result_sample_rate

            logger.warning(
                "segment %d/%d attempt=%d quality issue=%s duration=%.1fs "
                "max=%.1fs tokens=%d/%d active_rms=%.4f peak=%.4f",
                idx, total, attempt + 1, ",".join(reasons), duration,
                max_allowed_duration, token_count, effective_max, rms, peak,
            )
            self._clear_metal_cache()

        raise RuntimeError(
            f"TTS segment {idx}/{total} failed after {MAX_RETRIES + 1} attempts"
        )

    @staticmethod
    def _speech_variation(audio, sample_rate: int) -> tuple[float, float]:
        import numpy as np

        if len(audio) < 2 or sample_rate <= 0:
            return 0.0, 0.0
        frame_size = max(1, int(sample_rate * 0.04))
        frame_count = len(audio) // frame_size
        if frame_count < 2:
            return 0.0, 0.0
        framed = audio[:frame_count * frame_size].reshape(frame_count, frame_size)
        envelope = np.sqrt(np.mean(framed ** 2, axis=1))
        active_envelope = envelope[envelope > 0.003]
        envelope_cv = (
            float(np.std(active_envelope) / max(np.mean(active_envelope), 1e-6))
            if len(active_envelope) > 1 else 0.0
        )
        zero_crossings = np.count_nonzero(np.diff(np.signbit(audio)))
        zero_crossing_rate = float(zero_crossings / max(len(audio) - 1, 1))
        return envelope_cv, zero_crossing_rate

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
        if self.path == "/v1/audio/speech/cancel":
            tts.cancel_current()
            self._json_response(200, {"status": "cancelled"})
            return
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
        except TTSRequestCancelled:
            logger.info("streaming request cancelled; closing incomplete transfer")
            self.close_connection = True
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
