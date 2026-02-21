#!/usr/bin/env python3
"""
Piper TTS Warm Server for Clawdbot

Keeps piper subprocess warm with model loaded, accepts HTTP requests for synthesis.
This avoids the ~1-3s model load time on each request.

Usage:
    python piper_server.py --port 8098 --model /path/to/model.onnx

The server exposes:
    GET  /health         - Health check
    POST /tts            - Synthesize text to WAV (returns audio/wav)
    POST /tts/file       - Synthesize text, save to file, return path
"""

import argparse
import io
import logging
import os
import re
import subprocess
import tempfile
import threading
import time
from pathlib import Path
from typing import Optional

import uvicorn
from fastapi import FastAPI, Form, HTTPException, Response
from fastapi.responses import FileResponse, JSONResponse

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("piper-server")

app = FastAPI(title="Piper TTS Warm Server", version="1.0.0")


class PiperWarmProcess:
    """
    Manages a warm piper subprocess that reads JSON lines from stdin.
    Model stays loaded between requests.
    """

    def __init__(
        self,
        piper_bin: str,
        model_path: str,
        config_path: Optional[str] = None,
        speaker: Optional[str] = None,
        length_scale: float = 1.0,
        noise_scale: float = 0.667,
        noise_w: float = 0.8,
    ):
        self.piper_bin = piper_bin
        self.model_path = model_path
        self.config_path = config_path
        self.speaker = speaker
        self.length_scale = length_scale
        self.noise_scale = noise_scale
        self.noise_w = noise_w

        self._process: Optional[subprocess.Popen] = None
        self._lock = threading.Lock()
        self._output_dir = tempfile.mkdtemp(prefix="piper-warm-")
        self._request_counter = 0

    def _build_args(self) -> list[str]:
        args = [
            self.piper_bin,
            "--model", self.model_path,
            "--output_dir", self._output_dir,
            "--json-input",
            "--length_scale", str(self.length_scale),
            "--noise_scale", str(self.noise_scale),
            "--noise_w", str(self.noise_w),
            "--quiet",
        ]
        if self.config_path:
            args.extend(["--config", self.config_path])
        if self.speaker:
            args.extend(["--speaker", self.speaker])
        return args

    def start(self) -> None:
        with self._lock:
            if self._process is not None and self._process.poll() is None:
                return  # Already running

            args = self._build_args()
            logger.info(f"Starting piper: {' '.join(args)}")

            self._process = subprocess.Popen(
                args,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,
            )
            # Give it a moment to load the model
            time.sleep(0.5)
            if self._process.poll() is not None:
                stderr = self._process.stderr.read() if self._process.stderr else ""
                raise RuntimeError(f"Piper failed to start: {stderr}")
            logger.info("Piper process started and model loaded")

    def stop(self) -> None:
        with self._lock:
            if self._process is not None:
                self._process.terminate()
                try:
                    self._process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self._process.kill()
                self._process = None
                logger.info("Piper process stopped")

    def is_alive(self) -> bool:
        with self._lock:
            return self._process is not None and self._process.poll() is None

    def synthesize(self, text: str, output_path: Optional[str] = None) -> str:
        """
        Synthesize text to WAV. Returns path to output file.

        Piper with --json-input expects: {"text": "...", "output_file": "..."}
        """
        import json

        with self._lock:
            if self._process is None or self._process.poll() is not None:
                raise RuntimeError("Piper process not running")

            self._request_counter += 1
            if output_path is None:
                output_path = os.path.join(
                    self._output_dir, f"piper-{self._request_counter}.wav"
                )

            # Send JSON line to piper stdin
            request = json.dumps({"text": text, "output_file": output_path})
            self._process.stdin.write(request + "\n")
            self._process.stdin.flush()

            # Wait for output file to appear (with timeout)
            timeout = 60
            start = time.time()
            while not os.path.exists(output_path) or os.path.getsize(output_path) == 0:
                if time.time() - start > timeout:
                    raise TimeoutError(f"Piper did not produce output within {timeout}s")
                if self._process.poll() is not None:
                    raise RuntimeError("Piper process died during synthesis")
                time.sleep(0.1)

            # Small delay to ensure file is fully written
            time.sleep(0.05)
            return output_path


# Global piper instance
piper: Optional[PiperWarmProcess] = None


def detect_script_lang(text: str) -> str:
    """Detect language from Unicode script (hi, te, ml, kn, or none)."""
    for ch in text:
        cp = ord(ch)
        if 0x0900 <= cp <= 0x097F:
            return "hi"  # Devanagari
        if 0x0C00 <= cp <= 0x0C7F:
            return "te"  # Telugu
        if 0x0D00 <= cp <= 0x0D7F:
            return "ml"  # Malayalam
        if 0x0C80 <= cp <= 0x0CFF:
            return "kn"  # Kannada
    return "none"


@app.on_event("startup")
async def startup_event():
    global piper
    if piper is not None:
        piper.start()
        logger.info("Piper warm server ready")


@app.on_event("shutdown")
async def shutdown_event():
    global piper
    if piper is not None:
        piper.stop()


@app.get("/health")
async def health():
    if piper is None:
        return JSONResponse({"status": "not_configured"}, status_code=503)
    if not piper.is_alive():
        return JSONResponse({"status": "dead"}, status_code=503)
    return {"status": "healthy"}


@app.post("/tts")
async def tts(text: str = Form(...)):
    """Synthesize text to WAV, return audio bytes."""
    if piper is None or not piper.is_alive():
        raise HTTPException(503, "Piper not running")

    text = text.strip()
    if not text:
        raise HTTPException(400, "Empty text")

    try:
        wav_path = piper.synthesize(text)
        with open(wav_path, "rb") as f:
            audio_bytes = f.read()
        # Clean up temp file
        os.unlink(wav_path)
        return Response(content=audio_bytes, media_type="audio/wav")
    except Exception as e:
        logger.error(f"Synthesis failed: {e}")
        raise HTTPException(500, str(e))


@app.post("/tts/file")
async def tts_file(text: str = Form(...), output_path: str = Form(None)):
    """Synthesize text to WAV file, return file path."""
    if piper is None or not piper.is_alive():
        raise HTTPException(503, "Piper not running")

    text = text.strip()
    if not text:
        raise HTTPException(400, "Empty text")

    try:
        wav_path = piper.synthesize(text, output_path)
        return {"path": wav_path}
    except Exception as e:
        logger.error(f"Synthesis failed: {e}")
        raise HTTPException(500, str(e))


def main():
    parser = argparse.ArgumentParser(description="Piper TTS Warm Server")
    parser.add_argument("--host", default="127.0.0.1", help="Bind host")
    parser.add_argument("--port", type=int, default=8098, help="Bind port")
    parser.add_argument("--model", required=True, help="Path to piper .onnx model")
    parser.add_argument("--config", help="Path to model config JSON")
    parser.add_argument("--speaker", help="Speaker ID for multi-speaker models")
    parser.add_argument("--length-scale", type=float, default=1.0)
    parser.add_argument("--noise-scale", type=float, default=0.667)
    parser.add_argument("--noise-w", type=float, default=0.8)
    parser.add_argument("--piper-bin", default="piper", help="Path to piper binary")
    args = parser.parse_args()

    global piper
    piper = PiperWarmProcess(
        piper_bin=args.piper_bin,
        model_path=args.model,
        config_path=args.config,
        speaker=args.speaker,
        length_scale=args.length_scale,
        noise_scale=args.noise_scale,
        noise_w=args.noise_w,
    )

    logger.info(f"Starting Piper TTS server on {args.host}:{args.port}")
    logger.info(f"Model: {args.model}")

    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()
