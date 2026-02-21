#!/usr/bin/env python3
"""
Universal TTS Server with DirectML Support
Supports multiple TTS models with GPU acceleration on Windows

Models supported:
- Piper (ONNX, very fast)
- Kokoro (ONNX, high quality)
- Edge TTS (Microsoft API, instant)
- Qwen3-TTS (Transformers, best quality)
- XTTS v2 (Coqui, voice cloning)
"""

import os
import io
import json
import asyncio
import tempfile
import logging
import threading
from pathlib import Path
from typing import Optional, Dict, Any, List
from enum import Enum
from contextlib import asynccontextmanager
from functools import lru_cache

import uvicorn
from fastapi import FastAPI, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import soundfile as sf
import numpy as np

# Configure logging
LOG_DIR = Path.home() / ".cache" / "tts-server"
LOG_DIR.mkdir(parents=True, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(LOG_DIR / "server.log")
    ]
)
logger = logging.getLogger(__name__)

# Environment configuration
HOST = os.environ.get("TTS_HOST", "0.0.0.0")
PORT = int(os.environ.get("TTS_PORT", "8099"))
DEFAULT_MODEL = os.environ.get("TTS_DEFAULT_MODEL", "piper")
MODELS_DIR = Path(os.environ.get("TTS_MODELS_DIR", Path.home() / ".cache" / "tts-models"))
DEVICE = os.environ.get("TTS_DEVICE", os.environ.get("OPENCLAW_DEVICE", "directml")).lower()  # directml, cuda, cpu, auto

# Ensure directories exist
MODELS_DIR.mkdir(parents=True, exist_ok=True)

def env_flag(name: str, default: bool = False) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in ("1", "true", "yes", "on")


def env_int(name: str, default: int) -> int:
    value = os.environ.get(name)
    if value is None:
        return default
    try:
        return int(value)
    except ValueError:
        return default


def env_float(name: str, default: float) -> float:
    value = os.environ.get(name)
    if value is None:
        return default
    try:
        return float(value)
    except ValueError:
        return default


class AudioFormat(str, Enum):
    WAV = "wav"
    MP3 = "mp3"
    OGG = "ogg"


class TTSRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=10000)
    model: str = Field(default=DEFAULT_MODEL)
    voice: Optional[str] = None
    language: Optional[str] = "en"
    speed: float = Field(default=1.0, ge=0.5, le=2.0)
    format: AudioFormat = AudioFormat.OGG
    # Model-specific options
    instruct: Optional[str] = None  # For Qwen3
    fast: Optional[bool] = None  # For Qwen3 (per-request fast mode)
    rate: Optional[str] = None  # For Edge TTS
    pitch: Optional[str] = None  # For Edge TTS


class ModelInfo(BaseModel):
    name: str
    loaded: bool
    device: str
    voices: List[str]


# Global model registry
loaded_models: Dict[str, Any] = {}


@lru_cache(maxsize=1)
def resolve_onnx_providers() -> List[str]:
    """Resolve ONNX Runtime providers based on TTS_DEVICE."""
    try:
        import onnxruntime as ort
    except Exception as e:
        logger.warning(f"ONNX Runtime not available: {e}")
        return ["CPUExecutionProvider"]

    available = ort.get_available_providers()
    if DEVICE in ("directml", "auto") and "DmlExecutionProvider" in available:
        logger.info("ONNX Runtime: DmlExecutionProvider available")
        return ["DmlExecutionProvider", "CPUExecutionProvider"]
    if DEVICE in ("cuda", "auto") and "CUDAExecutionProvider" in available:
        logger.info("ONNX Runtime: CUDAExecutionProvider available")
        return ["CUDAExecutionProvider", "CPUExecutionProvider"]
    logger.info("ONNX Runtime: CPUExecutionProvider only")
    return ["CPUExecutionProvider"]


@lru_cache(maxsize=1)
def resolve_torch_device() -> tuple[str, Optional[Any], bool]:
    """Resolve torch device (directml/cuda/cpu)."""
    try:
        import torch
    except Exception as e:
        logger.warning(f"PyTorch not available: {e}")
        return "cpu", None, False

    if DEVICE in ("directml", "auto"):
        try:
            import torch_directml
            device_count = torch_directml.device_count()
            if device_count > 0:
                logger.info(f"DirectML: {device_count} device(s) available")
                return "directml", torch_directml.device(0), True
        except Exception as e:
            logger.warning(f"DirectML init failed: {e}")

    if DEVICE in ("cuda", "auto") and torch.cuda.is_available():
        try:
            logger.info(f"CUDA: {torch.cuda.get_device_name(0)}")
        except Exception:
            logger.info("CUDA: device available")
        return "cuda", torch.device("cuda:0"), True

    logger.info("Using CPU")
    return "cpu", torch.device("cpu"), True


def torch_device_label(device_kind: str, device: Optional[Any]) -> str:
    if device is None:
        return device_kind
    return f"{device_kind}:{device}"


# ============================================================================
# PIPER TTS
# ============================================================================
class PiperTTS:
    def __init__(self):
        self.voices_dir = MODELS_DIR / "piper"
        self.voices_dir.mkdir(parents=True, exist_ok=True)
        self.voice_cache = {}
        self._session_lock = threading.Lock()
        self.providers = resolve_onnx_providers()
        self.device = "directml" if "DmlExecutionProvider" in self.providers else (
            "cuda" if "CUDAExecutionProvider" in self.providers else "cpu"
        )
        self._scan_voices()

    def _scan_voices(self):
        """Scan for available voice models"""
        self.available_voices = []
        for f in self.voices_dir.glob("*.onnx"):
            voice_name = f.stem
            config_path = self.voices_dir / f"{voice_name}.onnx.json"
            if not voice_name.endswith(".onnx") and config_path.exists():
                self.available_voices.append(voice_name)
        logger.info(f"Piper: {len(self.available_voices)} voices available")

    def get_voice_paths(self, voice: str) -> tuple[Path, Path]:
        """Get paths to voice model and config, download if needed"""
        voice_path = self.voices_dir / f"{voice}.onnx"
        config_path = self.voices_dir / f"{voice}.onnx.json"
        if voice_path.exists() and config_path.exists():
            return voice_path, config_path

        # Try to download from HuggingFace
        # Voice format: lang_REGION-name-quality (e.g., en_US-amy-medium)
        parts = voice.split("-")
        if len(parts) >= 3:
            lang_region = parts[0]  # en_US
            name = parts[1]  # amy
            quality = parts[2]  # medium
            lang = lang_region.split("_")[0]  # en

            base_url = f"https://huggingface.co/rhasspy/piper-voices/resolve/main/{lang}/{lang_region}/{name}/{quality}"

            try:
                import httpx
                logger.info(f"Downloading Piper voice: {voice}")

                # Download ONNX model
                r = httpx.get(f"{base_url}/{voice}.onnx", follow_redirects=True, timeout=120)
                r.raise_for_status()
                voice_path.write_bytes(r.content)

                # Download config
                r = httpx.get(f"{base_url}/{voice}.onnx.json", follow_redirects=True, timeout=30)
                r.raise_for_status()
                config_path.write_bytes(r.content)

                logger.info(f"Downloaded: {voice}")
                self._scan_voices()
                return voice_path, config_path
            except Exception as e:
                logger.error(f"Failed to download voice {voice}: {e}")
                raise HTTPException(status_code=404, detail=f"Voice not found: {voice}")

        if voice_path.exists() and not config_path.exists():
            raise HTTPException(
                status_code=500,
                detail=f"Piper config missing for {voice}.onnx (expected {config_path})"
            )

        raise HTTPException(status_code=404, detail=f"Voice not found: {voice}")

    def _load_voice(self, voice_path: Path, config_path: Path):
        """Load Piper voice using the preferred ONNX Runtime provider."""
        import onnxruntime as ort
        from piper.voice import PiperVoice
        from piper.config import PiperConfig

        with open(config_path, "r", encoding="utf-8") as config_file:
            config_dict = json.load(config_file)

        sess_options = ort.SessionOptions()
        if "DmlExecutionProvider" in self.providers:
            # DirectML requires sequential execution and no memory pattern.
            sess_options.enable_mem_pattern = False
            sess_options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
        session = ort.InferenceSession(
            str(voice_path),
            sess_options=sess_options,
            providers=self.providers
        )
        return PiperVoice(session=session, config=PiperConfig.from_dict(config_dict))

    async def synthesize(self, text: str, voice: str = "en_US-amy-medium", speed: float = 1.0) -> tuple[np.ndarray, int]:
        """Synthesize speech using Piper"""
        voice_path, config_path = self.get_voice_paths(voice)

        # Load voice (cached)
        cache_key = str(voice_path)
        if cache_key not in self.voice_cache:
            logger.info(f"Loading Piper voice: {voice}")
            self.voice_cache[cache_key] = self._load_voice(voice_path, config_path)

        piper_voice = self.voice_cache[cache_key]

        # Synthesize
        audio_buffer = io.BytesIO()
        with self._session_lock:
            with sf.SoundFile(audio_buffer, mode='w', samplerate=piper_voice.config.sample_rate,
                              channels=1, format='WAV') as wav_file:
                try:
                    from piper.config import SynthesisConfig
                    syn_config = SynthesisConfig(length_scale=1.0 / speed)
                    for chunk in piper_voice.synthesize(text, syn_config=syn_config):
                        wav_file.write(chunk.audio_int16_array)
                except Exception:
                    # Fallback for older Piper APIs
                    for audio_bytes in piper_voice.synthesize_stream_raw(text, length_scale=1.0 / speed):
                        wav_file.write(np.frombuffer(audio_bytes, dtype=np.int16))

        audio_buffer.seek(0)
        audio, sr = sf.read(audio_buffer)
        return audio, sr

    def list_voices(self) -> List[str]:
        return self.available_voices if self.available_voices else ["en_US-amy-medium"]


# ============================================================================
# KOKORO TTS
# ============================================================================
class KokoroTTS:
    def __init__(self):
        self.pipeline = None
        self.device = "cpu"
        self.torch_device = None
        self._init_model()

    def _init_model(self):
        """Initialize Kokoro model"""
        try:
            from kokoro import KPipeline
            logger.info("Loading Kokoro TTS...")
            # Use American English by default
            device_kind, torch_device, torch_available = resolve_torch_device()
            if not torch_available:
                raise RuntimeError("PyTorch not available for Kokoro")
            self.device = device_kind
            self.torch_device = torch_device
            device_arg = torch_device if device_kind != "cpu" else "cpu"
            self.pipeline = KPipeline(lang_code="a", device=device_arg)  # 'a' for American English
            logger.info("Kokoro TTS loaded")
        except ImportError:
            logger.warning("Kokoro not installed")
            self.pipeline = None
        except Exception as e:
            logger.error(f"Kokoro init failed: {e}")
            self.pipeline = None

    async def synthesize(self, text: str, voice: str = "af_bella", speed: float = 1.0) -> tuple[np.ndarray, int]:
        """Synthesize speech using Kokoro"""
        if not self.pipeline:
            raise HTTPException(status_code=503, detail="Kokoro not available")

        # Generate audio
        generator = self.pipeline(text, voice=voice, speed=speed)

        # Collect all audio chunks
        audio_chunks = []
        for _, _, audio_chunk in generator:
            audio_chunks.append(audio_chunk)

        if not audio_chunks:
            raise HTTPException(status_code=500, detail="No audio generated")

        audio = np.concatenate(audio_chunks)
        return audio, 24000  # Kokoro outputs at 24kHz

    def list_voices(self) -> List[str]:
        # Kokoro voice naming: {lang}{gender}_{name}
        # a = American, b = British, j = Japanese, etc.
        # f = female, m = male
        return [
            "af_bella", "af_nicole", "af_sarah", "af_sky",
            "am_adam", "am_michael",
            "bf_emma", "bf_isabella",
            "bm_george", "bm_lewis"
        ]


# ============================================================================
# EDGE TTS (Microsoft)
# ============================================================================
class EdgeTTS:
    def __init__(self):
        self.voices = []
        self._init_voices()

    def _init_voices(self):
        """Get available Edge TTS voices"""
        try:
            import edge_tts
            import asyncio

            async def get_voices():
                return await edge_tts.list_voices()

            # Run in new event loop if needed
            try:
                loop = asyncio.get_event_loop()
                if loop.is_running():
                    self.voices = []  # Will fetch on first use
                else:
                    self.voices = loop.run_until_complete(get_voices())
            except RuntimeError:
                self.voices = []

            logger.info(f"Edge TTS: {len(self.voices)} voices available")
        except ImportError:
            logger.warning("edge-tts not installed")

    async def synthesize(self, text: str, voice: str = "en-US-AriaNeural",
                        rate: str = "+0%", pitch: str = "+0Hz") -> tuple[np.ndarray, int]:
        """Synthesize speech using Edge TTS"""
        import edge_tts

        communicate = edge_tts.Communicate(text, voice, rate=rate, pitch=pitch)

        # Collect audio data
        audio_buffer = io.BytesIO()
        async for chunk in communicate.stream():
            if chunk["type"] == "audio":
                audio_buffer.write(chunk["data"])

        if audio_buffer.tell() == 0:
            raise HTTPException(status_code=500, detail="No audio generated")

        # Edge TTS outputs MP3, convert to numpy
        audio_buffer.seek(0)

        # Save to temp file and read with soundfile
        with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as tmp:
            tmp.write(audio_buffer.read())
            tmp_path = tmp.name

        try:
            audio, sr = sf.read(tmp_path)
        finally:
            os.unlink(tmp_path)

        return audio, sr

    def list_voices(self) -> List[str]:
        if self.voices:
            return [v["ShortName"] for v in self.voices]
        return ["en-US-AriaNeural", "en-US-GuyNeural", "en-GB-SoniaNeural"]


# ============================================================================
# QWEN3 TTS
# ============================================================================
class Qwen3TTS:
    def __init__(self):
        self.model = None
        self.device = "cpu"
        self.torch_device = None
        self.device_kind = "cpu"
        self.fast_mode = env_flag("QWEN3_TTS_FAST") or env_flag("TTS_FAST")
        self.model_dtype = None
        self.model_dtype_name = "auto"
        self._dtype_fallback_used = False
        self._init_model()

    def _resolve_qwen_dtype(self, device_kind: str):
        import torch

        dtype_pref = os.environ.get("QWEN3_TTS_DTYPE", "").strip().lower()
        if not dtype_pref and env_flag("QWEN3_TTS_FP16"):
            dtype_pref = "fp16"

        if dtype_pref in ("fp16", "float16", "half"):
            return torch.float16, "fp16"
        if dtype_pref in ("bf16", "bfloat16"):
            return torch.bfloat16, "bf16"
        if dtype_pref in ("fp32", "float32"):
            return torch.float32, "fp32"

        if device_kind == "cuda":
            return torch.float16, "fp16"
        return torch.float32, "fp32"

    def _generation_params(self, fast: bool) -> Dict[str, Any]:
        max_new_tokens = env_int("QWEN3_TTS_MAX_NEW_TOKENS", 2048)
        top_k = env_int("QWEN3_TTS_TOP_K", 50)
        top_p = env_float("QWEN3_TTS_TOP_P", 0.95)
        temperature = env_float("QWEN3_TTS_TEMPERATURE", 1.0)
        do_sample = not env_flag("QWEN3_TTS_NO_SAMPLE")

        params: Dict[str, Any] = {
            "do_sample": do_sample,
            "top_k": top_k,
            "top_p": top_p,
            "temperature": temperature,
            "max_new_tokens": max_new_tokens,
        }

        if fast:
            fast_max_default = min(max_new_tokens, 1024)
            params["max_new_tokens"] = env_int("QWEN3_TTS_FAST_MAX_NEW_TOKENS", fast_max_default)
            params["top_k"] = env_int("QWEN3_TTS_FAST_TOP_K", params["top_k"])
            params["top_p"] = env_float("QWEN3_TTS_FAST_TOP_P", params["top_p"])
            params["temperature"] = env_float("QWEN3_TTS_FAST_TEMPERATURE", params["temperature"])
            if env_flag("QWEN3_TTS_FAST_NO_SAMPLE"):
                params["do_sample"] = False

        return params

    def _generate_voice(self, text: str, instruct: str, language: str, params: Dict[str, Any]):
        return self.model.generate_voice_design(
            text=text,
            instruct=instruct,
            language=language,
            use_cache=(self.device_kind != "directml"),
            repetition_penalty=(1.0 if self.device_kind == "directml" else 1.05),
            **params
        )

    def _force_fp32(self) -> bool:
        if not self.model:
            return False
        try:
            import torch
            if self.model_dtype == torch.float32:
                return True
            device = self.torch_device or torch.device("cpu")
            self.model.model.to(device, dtype=torch.float32)
            self.model.device = device
            self.model_dtype = torch.float32
            self.model_dtype_name = "fp32"
            self._dtype_fallback_used = True
            logger.warning("Qwen3-TTS switched to fp32 after failure")
            return True
        except Exception as e:
            logger.warning(f"Qwen3-TTS fp32 fallback failed: {e}")
            return False

    def _init_model(self):
        """Initialize Qwen3-TTS model"""
        try:
            import torch
            device_kind, torch_device, torch_available = resolve_torch_device()
            if not torch_available:
                raise RuntimeError("PyTorch not available for Qwen3-TTS")
            self.device = device_kind
            self.device_kind = device_kind
            self.torch_device = torch_device
            dtype, dtype_name = self._resolve_qwen_dtype(device_kind)
            self.model_dtype = dtype
            self.model_dtype_name = dtype_name
            logger.info(
                f"Loading Qwen3-TTS on {torch_device_label(self.device, self.torch_device)} "
                f"(dtype={self.model_dtype_name}, fast_mode={'on' if self.fast_mode else 'off'})..."
            )

            # Try qwen_tts package first
            try:
                from qwen_tts import Qwen3TTSModel

                model_id = os.environ.get("QWEN3_TTS_MODEL") or os.environ.get("QWEN3_TTS_MODEL_DIR") \
                    or "Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign"
                local_only = os.environ.get("QWEN3_TTS_LOCAL_ONLY", "").lower() in ("1", "true", "yes")
                if os.path.isdir(model_id):
                    local_only = True

                attn_impl = os.environ.get("QWEN3_TTS_ATTN", "eager" if device_kind == "directml" else "auto")
                load_kwargs = {
                    "dtype": dtype,
                    "local_files_only": local_only,
                }
                if attn_impl and attn_impl != "auto":
                    load_kwargs["attn_implementation"] = attn_impl
                try:
                    self.model = Qwen3TTSModel.from_pretrained(model_id, **load_kwargs)
                except Exception as e:
                    if dtype != torch.float32:
                        logger.warning(
                            f"Qwen3-TTS load failed with dtype={dtype_name}; retrying fp32: {e}"
                        )
                        dtype = torch.float32
                        self.model_dtype = dtype
                        self.model_dtype_name = "fp32"
                        load_kwargs["dtype"] = dtype
                        self.model = Qwen3TTSModel.from_pretrained(model_id, **load_kwargs)
                        self._dtype_fallback_used = True
                    else:
                        raise

                if self.device != "cpu" and self.torch_device is not None:
                    try:
                        self.model.model.to(self.torch_device)
                        self.model.device = self.torch_device
                    except Exception as e:
                        logger.warning(f"Qwen3-TTS could not move to {self.device}: {e}")
                        self.device = "cpu"
                        self.device_kind = "cpu"
                        self.torch_device = torch.device("cpu")
                        self.model.model.to(self.torch_device)
                        self.model.device = self.torch_device

                if device_kind == "directml":
                    def _tokenize_texts_dml(texts):
                        input_ids = []
                        for text in texts:
                            input = self.model.processor(text=text, return_tensors="pt", padding=True)
                            input_id = input["input_ids"].to(self.model.device)
                            input_id = input_id.unsqueeze(0) if input_id.dim() == 1 else input_id
                            input_ids.append(input_id.contiguous())
                        return input_ids
                    self.model._tokenize_texts = _tokenize_texts_dml

                    _orig_cat = torch.cat
                    def _directml_safe_cat(tensors, dim=0, *args, **kwargs):
                        if not isinstance(tensors, (list, tuple)) or len(tensors) == 0:
                            return _orig_cat(tensors, dim=dim, *args, **kwargs)
                        try:
                            if any(getattr(t, "device", None) is not None and t.device.type == "privateuseone" for t in tensors):
                                # DirectML can error on int cat; make tensors contiguous and align dtypes.
                                tensors = [t.contiguous() for t in tensors]
                                dtypes = {t.dtype for t in tensors}
                                if len(dtypes) > 1:
                                    target_dtype = tensors[0].dtype
                                    tensors = [t.to(dtype=target_dtype) for t in tensors]
                                out = kwargs.pop("out", None)
                                try:
                                    if out is not None:
                                        return _orig_cat(tensors, dim=dim, out=out, *args, **kwargs)
                                    return _orig_cat(tensors, dim=dim, *args, **kwargs)
                                except RuntimeError as e:
                                    if "parameter is incorrect" in str(e).lower():
                                        cpu_tensors = [t.cpu() for t in tensors]
                                        result = _orig_cat(cpu_tensors, dim=dim, *args, **kwargs)
                                        return result.to(self.model.device)
                                    raise
                        except Exception:
                            raise
                        return _orig_cat(tensors, dim=dim, *args, **kwargs)
                    torch.cat = _directml_safe_cat

                logger.info("Qwen3-TTS loaded via qwen_tts")
            except ImportError:
                logger.warning("qwen_tts not installed, Qwen3-TTS unavailable")
                self.model = None
        except Exception as e:
            logger.error(f"Qwen3-TTS init failed: {e}")
            self.model = None

    async def synthesize(self, text: str, voice: str = "default",
                         instruct: str = "Speak naturally",
                         language: str = "English",
                         fast: Optional[bool] = None) -> tuple[np.ndarray, int]:
        """Synthesize speech using Qwen3-TTS"""
        if not self.model:
            raise HTTPException(status_code=503, detail="Qwen3-TTS not available")

        use_fast = self.fast_mode if fast is None else fast
        params = self._generation_params(use_fast)
        last_error: Optional[Exception] = None

        try:
            wavs, sr = self._generate_voice(text, instruct, language, params)
            return wavs[0], sr
        except Exception as e:
            last_error = e

        if not self._dtype_fallback_used and self._force_fp32():
            try:
                wavs, sr = self._generate_voice(text, instruct, language, params)
                return wavs[0], sr
            except Exception as e:
                last_error = e

        if use_fast:
            logger.warning(f"Qwen3-TTS fast mode failed, retrying standard settings: {last_error}")
            params = self._generation_params(False)
            try:
                wavs, sr = self._generate_voice(text, instruct, language, params)
                return wavs[0], sr
            except Exception as e:
                last_error = e

        if last_error:
            raise last_error

        raise HTTPException(status_code=500, detail="Qwen3-TTS synthesis failed unexpectedly")

    def list_voices(self) -> List[str]:
        return ["default"]


# ============================================================================
# FASTAPI APP
# ============================================================================

# Model instances (lazy loaded)
models: Dict[str, Any] = {}


def get_model(name: str):
    """Get or create model instance"""
    if name not in models:
        if name == "piper":
            models[name] = PiperTTS()
        elif name == "kokoro":
            models[name] = KokoroTTS()
        elif name == "edge":
            models[name] = EdgeTTS()
        elif name == "qwen3":
            models[name] = Qwen3TTS()
        else:
            raise HTTPException(status_code=400, detail=f"Unknown model: {name}")
    return models[name]


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup/shutdown events"""
    logger.info(f"TTS Server starting on {HOST}:{PORT}")
    logger.info(f"Default model: {DEFAULT_MODEL}")
    logger.info(f"Device: {DEVICE}")

    # Pre-load default model
    try:
        get_model(DEFAULT_MODEL)
    except Exception as e:
        logger.warning(f"Failed to pre-load {DEFAULT_MODEL}: {e}")

    yield

    logger.info("TTS Server shutting down")


app = FastAPI(
    title="Universal TTS Server",
    description="Text-to-Speech server with DirectML GPU acceleration",
    version="1.0.0",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def convert_audio(audio: np.ndarray, sr: int, format: AudioFormat) -> bytes:
    """Convert audio to requested format"""
    buffer = io.BytesIO()

    if format == AudioFormat.WAV:
        sf.write(buffer, audio, sr, format='WAV')
    elif format == AudioFormat.OGG:
        # Write to temp WAV, convert with ffmpeg
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp_wav:
            sf.write(tmp_wav.name, audio, sr)
            tmp_wav_path = tmp_wav.name

        tmp_ogg_path = tmp_wav_path.replace(".wav", ".ogg")
        try:
            import subprocess
            subprocess.run([
                "ffmpeg", "-y", "-i", tmp_wav_path,
                "-c:a", "libopus", "-b:a", "48k",
                "-vbr", "on", "-ac", "1",
                tmp_ogg_path
            ], check=True, capture_output=True)

            with open(tmp_ogg_path, "rb") as f:
                buffer.write(f.read())
        finally:
            os.unlink(tmp_wav_path)
            if os.path.exists(tmp_ogg_path):
                os.unlink(tmp_ogg_path)
    elif format == AudioFormat.MP3:
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp_wav:
            sf.write(tmp_wav.name, audio, sr)
            tmp_wav_path = tmp_wav.name

        tmp_mp3_path = tmp_wav_path.replace(".wav", ".mp3")
        try:
            import subprocess
            subprocess.run([
                "ffmpeg", "-y", "-i", tmp_wav_path,
                "-c:a", "libmp3lame", "-b:a", "128k",
                tmp_mp3_path
            ], check=True, capture_output=True)

            with open(tmp_mp3_path, "rb") as f:
                buffer.write(f.read())
        finally:
            os.unlink(tmp_wav_path)
            if os.path.exists(tmp_mp3_path):
                os.unlink(tmp_mp3_path)

    buffer.seek(0)
    return buffer.read()


@app.get("/health")
async def health():
    """Health check endpoint"""
    device_kind, torch_device, torch_available = resolve_torch_device()
    return {
        "status": "ok",
        "default_model": DEFAULT_MODEL,
        "device": DEVICE,
        "resolved_torch_device": torch_device_label(device_kind, torch_device),
        "torch_available": torch_available,
        "onnx_providers": resolve_onnx_providers(),
        "loaded_models": list(models.keys())
    }


@app.get("/models")
async def list_models():
    """List available models"""
    available = []
    for name in ["piper", "kokoro", "edge", "qwen3"]:
        try:
            model = get_model(name)
            available.append({
                "name": name,
                "loaded": name in models,
                "device": getattr(model, "device", "unknown"),
                "voices": model.list_voices()[:10]  # First 10 voices
            })
        except Exception as e:
            available.append({
                "name": name,
                "loaded": False,
                "error": str(e)
            })
    return available


@app.get("/voices/{model_name}")
async def list_voices(model_name: str):
    """List voices for a specific model"""
    model = get_model(model_name)
    return {"model": model_name, "voices": model.list_voices()}


@app.post("/tts")
async def synthesize(request: TTSRequest):
    """Generate speech from text"""
    logger.info(f"TTS request: model={request.model}, text={request.text[:50]}...")

    model = get_model(request.model)

    # Default voices per model
    voice = request.voice
    if not voice:
        voice = {
            "piper": "en_US-amy-medium",
            "kokoro": "af_bella",
            "edge": "en-US-AriaNeural",
            "qwen3": "default"
        }.get(request.model, "default")

    # Synthesize
    try:
        if request.model == "piper":
            audio, sr = await model.synthesize(request.text, voice, request.speed)
        elif request.model == "kokoro":
            audio, sr = await model.synthesize(request.text, voice, request.speed)
        elif request.model == "edge":
            audio, sr = await model.synthesize(
                request.text, voice,
                rate=request.rate or "+0%",
                pitch=request.pitch or "+0Hz"
            )
        elif request.model == "qwen3":
            audio, sr = await model.synthesize(
                request.text, voice,
                instruct=request.instruct or "Speak naturally",
                language=request.language or "English",
                fast=request.fast
            )
        else:
            raise HTTPException(status_code=400, detail=f"Unknown model: {request.model}")
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Synthesis failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

    # Convert to requested format
    content_types = {
        AudioFormat.WAV: "audio/wav",
        AudioFormat.MP3: "audio/mpeg",
        AudioFormat.OGG: "audio/ogg"
    }

    audio_bytes = convert_audio(audio, sr, request.format)

    return Response(
        content=audio_bytes,
        media_type=content_types[request.format],
        headers={
            "Content-Disposition": f"attachment; filename=speech.{request.format.value}"
        }
    )


@app.post("/tts/stream")
async def synthesize_stream(request: TTSRequest):
    """Stream synthesized speech (for supported models)"""
    # TODO: Implement streaming for models that support it
    raise HTTPException(status_code=501, detail="Streaming not yet implemented")


if __name__ == "__main__":
    uvicorn.run(
        "server:app",
        host=HOST,
        port=PORT,
        reload=False,
        log_level="info"
    )
