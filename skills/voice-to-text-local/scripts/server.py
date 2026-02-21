#!/usr/bin/env python3
import json
import os
import subprocess
import tempfile
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = os.environ.get("WHISPER_HOST", "127.0.0.1")
PORT = int(os.environ.get("WHISPER_PORT", "8111"))
DEFAULT_MODEL = os.environ.get("WHISPER_MODEL", "medium")
DEVICE_PREF = os.environ.get("WHISPER_DEVICE", "directml").lower()
ENGINE_PREF = os.environ.get("WHISPER_ENGINE", "auto").lower()

MODEL_CACHE = {}
ENGINE_STATE = {
    "engine": "unknown",
    "device": "cpu",
    "onnx_providers": [],
    "model_id": "",
}


def log(msg: str) -> None:
    print(f"[whisper-server] {msg}", flush=True)


def resolve_onnx_model(name: str | None) -> str | None:
    override = os.environ.get("WHISPER_ONNX_MODEL")
    if override:
        return override
    if not name:
        return "onnx-community/whisper-base"
    lower = name.lower()
    if lower in ("tiny", "tiny.en", "whisper-tiny"):
        return "onnx-community/whisper-tiny"
    if lower in ("base", "base.en", "whisper-base"):
        return "onnx-community/whisper-base"
    if lower in ("small", "small.en", "whisper-small"):
        return "onnx-community/whisper-small"
    if lower in ("medium", "medium.en", "whisper-medium"):
        return "onnx-community/whisper-small"
    if lower in ("large", "large-v2", "large-v3", "turbo"):
        return "onnx-community/whisper-small"
    if lower.startswith("onnx:"):
        return name.split(":", 1)[1]
    if "/" in name:
        return name
    return None


def _resolve_onnx_providers() -> list[str]:
    try:
        import onnxruntime as ort
        return ort.get_available_providers()
    except Exception:
        return []


def _choose_engine() -> tuple[str, list[str]]:
    providers = _resolve_onnx_providers()
    has_dml = "DmlExecutionProvider" in providers
    can_onnx = False
    try:
        import onnx_asr  # noqa: F401
        can_onnx = True
    except Exception:
        can_onnx = False

    if ENGINE_PREF in ("onnx", "onnx_asr") and can_onnx:
        return "onnx", providers
    if ENGINE_PREF == "whisper":
        return "whisper", providers
    if can_onnx and (has_dml or DEVICE_PREF == "cpu"):
        return "onnx", providers
    return "whisper", providers


ENGINE_STATE["engine"], ENGINE_STATE["onnx_providers"] = _choose_engine()


def _ensure_wav(path: str) -> tuple[str, str | None]:
    path = os.path.abspath(path)
    if not os.path.exists(path):
        raise FileNotFoundError(path)
    if path.lower().endswith(".wav"):
        try:
            with wave.open(path, "rb"):
                return path, None
        except Exception:
            pass
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    tmp.close()
    cmd = [
        "ffmpeg", "-y", "-i", path,
        "-ac", "1", "-ar", "16000", "-acodec", "pcm_s16le", tmp.name
    ]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return tmp.name, tmp.name


def _load_onnx_model(model_name: str):
    try:
        import onnx_asr
    except Exception as exc:
        raise RuntimeError(f"onnx_asr unavailable: {exc}") from exc

    model_id = resolve_onnx_model(model_name)
    if not model_id:
        raise RuntimeError(f"Unsupported ONNX model mapping for '{model_name}'")
    cache_key = ("onnx", model_id)
    if cache_key in MODEL_CACHE:
        return MODEL_CACHE[cache_key], model_id

    providers = ["CPUExecutionProvider"]
    if DEVICE_PREF != "cpu" and "DmlExecutionProvider" in ENGINE_STATE["onnx_providers"]:
        providers = ["DmlExecutionProvider", "CPUExecutionProvider"]
        ENGINE_STATE["device"] = "directml"
    else:
        ENGINE_STATE["device"] = "cpu"

    model = onnx_asr.load_model(model_id, providers=providers)
    MODEL_CACHE[cache_key] = model
    ENGINE_STATE["model_id"] = model_id
    log(f"Loaded ONNX model {model_id} on {ENGINE_STATE['device']}")
    return model, model_id


def _load_whisper_model(model_name: str):
    try:
        import torch
        import whisper
    except Exception as exc:
        raise RuntimeError(f"whisper unavailable: {exc}") from exc

    cache_key = ("whisper", model_name)
    if cache_key in MODEL_CACHE:
        return MODEL_CACHE[cache_key], model_name

    device_kind = "cpu"
    device = "cpu"
    if DEVICE_PREF != "cpu":
        try:
            import torch_directml
            if torch_directml.device_count() > 0:
                device_kind = "directml"
                device = torch_directml.device(0)
        except Exception:
            device_kind = "cpu"
            device = "cpu"

    model = whisper.load_model(model_name, device="cpu")
    if device_kind == "directml":
        try:
            model = model.to(device)
        except Exception:
            device_kind = "cpu"
            device = "cpu"
    ENGINE_STATE["device"] = device_kind
    MODEL_CACHE[cache_key] = model
    ENGINE_STATE["model_id"] = model_name
    log(f"Loaded Whisper model {model_name} on {device_kind}")
    return model, model_name


def _get_model(model_name: str):
    if ENGINE_STATE["engine"] == "onnx":
        return _load_onnx_model(model_name)
    return _load_whisper_model(model_name)


def _normalize_text(result) -> str:
    if isinstance(result, list):
        result = result[0] if result else ""
    if isinstance(result, str):
        return result.strip()
    if hasattr(result, "text"):
        return str(result.text).strip()
    return str(result).strip()


def transcribe(path: str, model_name: str, language: str, task: str) -> tuple[str, str]:
    model, model_id = _get_model(model_name)
    if ENGINE_STATE["engine"] == "onnx":
        wav_path = None
        tmp_path = None
        try:
            wav_path, tmp_path = _ensure_wav(path)
            kwargs = {}
            if language:
                kwargs["language"] = language
            if task:
                kwargs["task"] = task
            try:
                result = model.recognize(wav_path, **kwargs)
            except TypeError:
                result = model.recognize(wav_path)
        finally:
            if tmp_path:
                try:
                    os.unlink(tmp_path)
                except Exception:
                    pass
        return _normalize_text(result), model_id

    kwargs = {}
    if language:
        kwargs["language"] = language
    if task:
        kwargs["task"] = task
    result = model.transcribe(path, **kwargs)
    return _normalize_text(result.get("text", "")), model_id


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        if self.path.rstrip("/") == "/health":
            self._send_json(200, {
                "status": "ok",
                "engine": ENGINE_STATE["engine"],
                "device": ENGINE_STATE["device"],
                "model": ENGINE_STATE.get("model_id") or DEFAULT_MODEL,
                "onnx_providers": ENGINE_STATE["onnx_providers"],
            })
            return
        self._send_json(404, {"error": "not found"})

    def do_POST(self):  # noqa: N802
        if self.path.rstrip("/") != "/transcribe":
            self._send_json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length) or b"{}")
            path = payload.get("path")
            model_name = payload.get("model") or DEFAULT_MODEL
            language = payload.get("language", "") or ""
            task = payload.get("task", "transcribe") or "transcribe"
            if not path:
                self._send_json(400, {"error": "path is required"})
                return
            text, model_id = transcribe(path, model_name, language, task)
            if not text:
                self._send_json(500, {"error": "empty transcription"})
                return
            self._send_json(200, {
                "text": text,
                "engine": ENGINE_STATE["engine"],
                "device": ENGINE_STATE["device"],
                "model": model_id,
            })
        except Exception as exc:
            self._send_json(500, {"error": str(exc)})

    def log_message(self, format, *args):  # noqa: A002
        return


def main() -> None:
    log(f"Starting server on {HOST}:{PORT} (engine={ENGINE_STATE['engine']})")
    _get_model(DEFAULT_MODEL)
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
