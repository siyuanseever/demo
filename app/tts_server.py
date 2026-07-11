from __future__ import annotations

import hashlib
import json
import logging
import os
import threading
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

    @property
    def loaded(self) -> bool:
        return self._model is not None

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

    def synthesize(self, text: str, voice: str, instruct: str) -> bytes:
        cache_key = hashlib.sha256(
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
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        cache_path = CACHE_DIR / f"{cache_key}.wav"
        if cache_path.exists():
            logger.info("cache hit chars=%d", len(text))
            return cache_path.read_bytes()

        with self._generation_lock:
            if cache_path.exists():
                return cache_path.read_bytes()

            import mlx.core as mx
            from mlx_audio.audio_io import write as audio_write

            model = self._load_model()
            logger.info("generation start chars=%d voice=%s", len(text), voice)
            results = list(
                model.generate(
                    text=text,
                    voice=voice,
                    instruct=instruct,
                    lang_code="Chinese",
                    speed=1.0,
                    split_pattern="\n",
                    verbose=False,
                )
            )
            if not results:
                raise RuntimeError("TTS model returned no audio")
            sample_rate = results[0].sample_rate
            audio = (
                mx.concatenate([result.audio for result in results], axis=0)
                if len(results) > 1
                else results[0].audio
            )
            temporary_path = cache_path.with_suffix(".tmp.wav")
            audio_write(str(temporary_path), audio, sample_rate, format="wav")
            temporary_path.replace(cache_path)
            logger.info("generation done chars=%d bytes=%d", len(text), cache_path.stat().st_size)
            return cache_path.read_bytes()


tts = LocalTTS()


class TTSRequestHandler(BaseHTTPRequestHandler):
    server_version = "SensenLocalTTS/1.0"

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
        if self.path != "/v1/audio/speech":
            self._json_response(404, {"error": "not_found"})
            return
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
        except ValueError as error:
            self._json_response(400, {"error": str(error)})
        except Exception as error:
            logger.exception("generation failed")
            self._json_response(500, {"error": type(error).__name__})

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
