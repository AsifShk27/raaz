#!/usr/bin/env python3
import argparse
import io
import logging
import os
from pathlib import Path
from typing import Optional

import soundfile as sf
import torch
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse, Response
from huggingface_hub import snapshot_download
from pydantic import BaseModel, Field

from chatterbox.tts import ChatterboxTTS
from chatterbox.tts_turbo import ChatterboxTurboTTS

LOGGER = logging.getLogger("chatterbox-tts")
DEFAULT_MODEL = "turbo"
MODEL_ALIASES = {
    "turbo": "turbo",
    "chatterbox-turbo": "turbo",
    "classic": "classic",
    "base": "classic",
    "chatterbox": "classic",
}
MODEL_REPOS = {
    "turbo": "ResembleAI/chatterbox-turbo",
    "classic": "ResembleAI/chatterbox",
}
MODEL_ALLOW_PATTERNS = ["*.safetensors", "*.json", "*.txt", "*.pt", "*.model"]
MODEL_REQUIRED_FILES = {
    "turbo": [
        "ve.safetensors",
        "t3_turbo_v1.safetensors",
        "s3gen_meanflow.safetensors",
        "s3gen.safetensors",
        "conds.pt",
    ],
    "classic": [
        "ve.safetensors",
        "t3_cfg.safetensors",
        "s3gen.safetensors",
        "tokenizer.json",
        "conds.pt",
    ],
}


def resolve_device(requested: str) -> str:
    val = (requested or "cpu").strip().lower()
    if val in {"cpu", ""}:
        return "cpu"
    if val in {"mps"}:
        if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            return "mps"
        LOGGER.warning("MPS requested but unavailable; falling back to CPU.")
        return "cpu"
    if val in {"cuda", "gpu"}:
        if torch.cuda.is_available():
            return "cuda"
        LOGGER.warning("CUDA requested but unavailable; falling back to CPU.")
        return "cpu"
    if val in {"directml", "dml"}:
        # Current Chatterbox + DirectML path fails at runtime in this environment.
        LOGGER.warning("DirectML requested, but runtime is unstable for Chatterbox here; using CPU fallback.")
        return "cpu"
    LOGGER.warning("Unknown device '%s'; falling back to CPU.", requested)
    return "cpu"


def resolve_model(requested: str) -> str:
    val = (requested or DEFAULT_MODEL).strip().lower()
    if val in MODEL_ALIASES:
        return MODEL_ALIASES[val]
    LOGGER.warning("Unknown model '%s'; falling back to '%s'.", requested, DEFAULT_MODEL)
    return DEFAULT_MODEL


def is_true(value: Optional[str]) -> bool:
    return str(value or "").strip().lower() in {"1", "true", "yes", "y", "on"}


class TTSRequest(BaseModel):
    text: str = Field(min_length=1, max_length=1200)
    repetition_penalty: float = 1.2
    min_p: float = 0.05
    top_p: float = 1.0
    exaggeration: float = 0.5
    cfg_weight: float = 0.5
    temperature: float = 0.8
    top_k: int = 1000
    norm_loudness: bool = True
    audio_prompt_path: Optional[str] = None


class ChatterboxServer:
    def __init__(self, requested_device: str, requested_model: str):
        self.requested_device = requested_device
        self.requested_model = requested_model
        self.device = resolve_device(requested_device)
        self.model_variant = resolve_model(requested_model)
        self.model_repo = MODEL_REPOS[self.model_variant]
        runtime_root = os.environ.get("CHATTERBOX_TTS_RUNTIME", "/home/shkas/projects/raaz/.runtime/chatterbox-tts")
        self.model_root = Path(os.environ.get("CHATTERBOX_TTS_MODEL_ROOT", str(Path(runtime_root) / "models")))
        requested_model_dir = os.environ.get("CHATTERBOX_TTS_MODEL_DIR", "").strip()
        self.model_dir = Path(requested_model_dir) if requested_model_dir else self.model_root / self.model_variant
        local_only_raw = os.environ.get("CHATTERBOX_TTS_LOCAL_ONLY", "").strip()
        self.local_files_mode = "explicit" if local_only_raw else "auto"
        self.local_files_only = is_true(local_only_raw) if local_only_raw else False
        self.model = None

    def load(self) -> None:
        model_cls = ChatterboxTurboTTS if self.model_variant == "turbo" else ChatterboxTTS
        self.model_dir.mkdir(parents=True, exist_ok=True)
        if self.local_files_mode == "auto":
            self.local_files_only = self.has_local_snapshot()
        LOGGER.info(
            "Loading Chatterbox model variant=%s repo=%s device=%s localFilesOnly=%s localFilesMode=%s modelDir=%s (requestedDevice=%s requestedModel=%s)",
            self.model_variant,
            self.model_repo,
            self.device,
            self.local_files_only,
            self.local_files_mode,
            self.model_dir,
            self.requested_device,
            self.requested_model,
        )
        snapshot_download(
            repo_id=self.model_repo,
            local_dir=str(self.model_dir),
            allow_patterns=MODEL_ALLOW_PATTERNS,
            local_files_only=self.local_files_only,
            token=os.getenv("HF_TOKEN") or True,
        )
        self.model = model_cls.from_local(str(self.model_dir), device=self.device)
        LOGGER.info("Chatterbox model ready. variant=%s sample_rate=%s", self.model_variant, self.model.sr)

    def has_local_snapshot(self) -> bool:
        required = MODEL_REQUIRED_FILES.get(self.model_variant, [])
        return all((self.model_dir / name).exists() for name in required)


server_state = ChatterboxServer(
    requested_device=os.environ.get("CHATTERBOX_TTS_DEVICE", "cpu"),
    requested_model=os.environ.get("CHATTERBOX_TTS_MODEL", DEFAULT_MODEL),
)
app = FastAPI(title="Chatterbox TTS Server")


@app.on_event("startup")
def _startup() -> None:
    server_state.load()


@app.get("/health")
def health():
    return JSONResponse(
        {
            "status": "ok",
            "engine": "chatterbox",
            "device": server_state.device,
            "requestedDevice": server_state.requested_device,
            "modelVariant": server_state.model_variant,
            "requestedModel": server_state.requested_model,
            "modelRepo": server_state.model_repo,
            "modelDir": str(server_state.model_dir),
            "localFilesOnly": server_state.local_files_only,
            "localFilesMode": server_state.local_files_mode,
            "sampleRate": getattr(server_state.model, "sr", None),
        }
    )


@app.post("/tts")
def tts(req: TTSRequest):
    if server_state.model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    try:
        generate_kwargs = {
            "text": req.text,
            "repetition_penalty": req.repetition_penalty,
            "top_p": req.top_p,
            "temperature": req.temperature,
        }
        if req.audio_prompt_path:
            generate_kwargs["audio_prompt_path"] = req.audio_prompt_path
        if server_state.model_variant == "turbo":
            generate_kwargs["top_k"] = req.top_k
            generate_kwargs["norm_loudness"] = req.norm_loudness
        else:
            generate_kwargs["min_p"] = req.min_p
            generate_kwargs["exaggeration"] = req.exaggeration
            generate_kwargs["cfg_weight"] = req.cfg_weight

        wav = server_state.model.generate(**generate_kwargs)

        if getattr(wav, "ndim", 0) == 1:
            wav = wav.unsqueeze(0)
        wav = wav.detach().cpu()

        data = wav.squeeze(0).numpy()
        buf = io.BytesIO()
        sf.write(buf, data, server_state.model.sr, format="WAV", subtype="PCM_16")
        return Response(content=buf.getvalue(), media_type="audio/wav")
    except Exception as exc:  # noqa: BLE001
        LOGGER.exception("Chatterbox generation failed")
        raise HTTPException(status_code=500, detail=str(exc)) from exc


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Chatterbox warm TTS server")
    parser.add_argument("--host", default=os.environ.get("CHATTERBOX_TTS_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("CHATTERBOX_TTS_PORT", "8126")))
    parser.add_argument("--device", default=os.environ.get("CHATTERBOX_TTS_DEVICE", "cpu"))
    parser.add_argument("--model", default=os.environ.get("CHATTERBOX_TTS_MODEL", DEFAULT_MODEL))
    parser.add_argument("--log-level", default=os.environ.get("CHATTERBOX_TTS_LOG_LEVEL", "info"))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    logging.basicConfig(level=getattr(logging, args.log_level.upper(), logging.INFO))
    os.environ["CHATTERBOX_TTS_DEVICE"] = args.device
    os.environ["CHATTERBOX_TTS_MODEL"] = args.model

    import uvicorn

    uvicorn.run(
        "server:app",
        host=args.host,
        port=args.port,
        log_level=args.log_level,
        reload=False,
    )


if __name__ == "__main__":
    main()
