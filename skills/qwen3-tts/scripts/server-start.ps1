Param(
    [string]$BindHost = "127.0.0.1",
    [int]$Port = 8099,
    [string]$Model = "Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign",
    [string]$Device = "directml",
    [string]$PythonPath = ""
)

if (-not $PSBoundParameters.ContainsKey('Model')) {
    if ($env:QWEN3_TTS_MODEL) {
        $Model = $env:QWEN3_TTS_MODEL
    } elseif ($env:QWEN3_TTS_MODEL_DIR -and (Test-Path $env:QWEN3_TTS_MODEL_DIR)) {
        $Model = $env:QWEN3_TTS_MODEL_DIR
    }
}

$ScriptRoot = $PSScriptRoot
$SkillRoot = Split-Path -Parent $ScriptRoot
$StateDir = Join-Path $env:USERPROFILE ".openclaw\\qwen3-tts"
$PidFile = Join-Path $StateDir "server.pid"
$LogFile = Join-Path $StateDir "server.log"
$ErrLogFile = Join-Path $StateDir "server.err.log"
$ServerScript = Join-Path $StateDir "qwen3_warm_server.py"

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

function Ensure-FfmpegPath {
    if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
        return
    }

    $root = Join-Path $env:USERPROFILE ".openclaw\\tools\\ffmpeg"
    if (-not (Test-Path $root)) {
        return
    }

    $ffmpeg = Get-ChildItem -Path $root -Recurse -Filter ffmpeg.exe -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $ffmpeg) {
        return
    }

    $env:Path = $ffmpeg.Directory.FullName + ";" + $env:Path
}

Ensure-FfmpegPath
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    throw "ffmpeg not found in PATH. Install ffmpeg on Windows."
}

function Test-PythonModules {
    param([string]$Py, [string[]]$Modules)
    $importLine = ($Modules | ForEach-Object { "import $($_)" }) -join "; "
    & $Py -c $importLine *> $null
    return ($LASTEXITCODE -eq 0)
}

function Resolve-PythonPath {
    param([string]$Py, [string[]]$Modules)
    if ($Py -and (Test-Path $Py)) {
        if (Test-PythonModules -Py $Py -Modules $Modules) {
            return $Py
        }
        throw "Python at $Py missing required modules: $($Modules -join ', ')"
    }

    $candidates = @()
    try {
        $candidates += (& py -3.12 -c "import sys; print(sys.executable)" 2>$null)
    } catch {}
    try {
        $candidates += (Get-Command python).Source
    } catch {}

    foreach ($cand in $candidates | Where-Object { $_ } | Select-Object -Unique) {
        if ((Test-Path $cand) -and (Test-PythonModules -Py $cand -Modules $Modules)) {
            return $cand
        }
    }
    throw "No Python found with required modules: $($Modules -join ', '). Install Python 3.12 + qwen-tts + torch-directml."
}

$PythonPath = Resolve-PythonPath -Py $PythonPath -Modules @("torch_directml", "qwen_tts", "fastapi", "uvicorn", "soundfile", "torch")

if (Test-Path $PidFile) {
    $oldPid = Get-Content $PidFile -ErrorAction SilentlyContinue
    if ($oldPid) {
        try {
            $proc = Get-Process -Id $oldPid -ErrorAction Stop
            Write-Host "Server already running (PID: $oldPid)"
            exit 0
        } catch {
            Remove-Item $PidFile -ErrorAction SilentlyContinue
        }
    }
}

$py = @'
import os
import sys
import torch
import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import soundfile as sf
import subprocess
import tempfile

os.environ.setdefault("TORCHAUDIO_USE_SOUNDFILE", "1")
os.environ.setdefault("TORCHAUDIO_BACKEND", "soundfile")
cache_root = os.path.join(os.path.expanduser("~"), ".cache", "huggingface")
os.environ.setdefault("HF_HOME", cache_root)
os.environ.setdefault("HUGGINGFACE_HUB_CACHE", os.path.join(cache_root, "hub"))
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
os.environ.setdefault("HF_HUB_DISABLE_XET", "1")
os.environ.setdefault("HF_HUB_DOWNLOAD_TIMEOUT", "300")
os.environ.setdefault("HF_HUB_DOWNLOAD_RETRY", "5")

app = FastAPI()

MODEL_ID = os.environ.get("QWEN3_TTS_MODEL", "Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign")
DEVICE_REQ = os.environ.get("QWEN3_TTS_DEVICE", "auto").lower()
local_only = os.environ.get("QWEN3_TTS_LOCAL_ONLY", "").lower() in ("1", "true", "yes")
if os.path.isdir(MODEL_ID):
    local_only = True
if local_only:
    os.environ.setdefault("HF_HUB_OFFLINE", "1")

language_map = {
    "en": "English",
    "zh": "Chinese",
    "es": "Spanish",
    "fr": "French",
    "de": "German",
    "pt": "Portuguese",
    "vi": "Vietnamese",
    "ml": "Malayalam",
    "bn": "Bengali",
    "ta": "Tamil",
}

def resolve_device():
    if DEVICE_REQ in ("directml", "dml", "auto"):
        try:
            import torch_directml
            if torch_directml.device_count() > 0:
                return "directml", torch_directml.device(0)
        except Exception as e:
            print(f"DirectML not available: {e}", flush=True)
    if DEVICE_REQ in ("cuda", "auto") and torch.cuda.is_available():
        return "cuda", torch.device("cuda:0")
    return "cpu", torch.device("cpu")

device_kind, device = resolve_device()

print(f"Loading model: {MODEL_ID} on {device_kind}", flush=True)
from qwen_tts import Qwen3TTSModel
dtype = torch.float32 if device_kind == "directml" else (torch.float16 if device_kind == "cuda" else torch.float32)
attn_impl = os.environ.get("QWEN3_TTS_ATTN", "eager" if device_kind == "directml" else "auto")
try:
    load_kwargs = {
        "dtype": dtype,
        "local_files_only": local_only,
    }
    if attn_impl and attn_impl != "auto":
        load_kwargs["attn_implementation"] = attn_impl
    model = Qwen3TTSModel.from_pretrained(MODEL_ID, **load_kwargs)
except Exception as e:
    if dtype == torch.float16:
        print(f"Retrying model load in fp32: {e}", flush=True)
        load_kwargs = {
            "dtype": torch.float32,
            "local_files_only": local_only,
        }
        if attn_impl and attn_impl != "auto":
            load_kwargs["attn_implementation"] = attn_impl
        model = Qwen3TTSModel.from_pretrained(MODEL_ID, **load_kwargs)
    else:
        raise

if device_kind != "cpu":
    try:
        model.model.to(device)
        model.device = device
    except Exception as e:
        print(f"Failed to move model to {device_kind}, using CPU: {e}", flush=True)
        device_kind = "cpu"
        model.model.to(torch.device("cpu"))
        model.device = torch.device("cpu")

if device_kind == "directml":
    def _tokenize_texts_dml(texts):
        input_ids = []
        for text in texts:
            input = model.processor(text=text, return_tensors="pt", padding=True)
            input_id = input["input_ids"].to(model.device)
            input_id = input_id.unsqueeze(0) if input_id.dim() == 1 else input_id
            input_ids.append(input_id.contiguous())
        return input_ids
    model._tokenize_texts = _tokenize_texts_dml

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
                        return result.to(device)
                    raise
        except Exception:
            raise
        return _orig_cat(tensors, dim=dim, *args, **kwargs)
    torch.cat = _directml_safe_cat

class TTSRequest(BaseModel):
    text: str
    instruct: str = "Speak with a cheerful American accent in a robotic, futuristic tone."
    language: str = "English"
    speed: float = 1.0
    top_k: int = 50
    top_p: float = 0.95
    temperature: float = 1.0

@app.get("/health")
async def health():
    return {
        "status": "ok",
        "model": MODEL_ID,
        "device": device_kind
    }

@app.post("/tts")
async def tts(request: TTSRequest):
    try:
        language = language_map.get(request.language.strip().lower(), request.language)
        use_cache = device_kind != "directml"
        repetition_penalty = 1.0 if device_kind == "directml" else 1.05
        wavs, sr = model.generate_voice_design(
            text=request.text,
            instruct=request.instruct,
            language=language,
            do_sample=True,
            top_k=request.top_k,
            top_p=request.top_p,
            temperature=request.temperature,
            max_new_tokens=2048,
            use_cache=use_cache,
            repetition_penalty=repetition_penalty
        )

        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as wav_file:
            sf.write(wav_file.name, wavs[0], sr)
            wav_path = wav_file.name

        ogg_path = wav_path.replace(".wav", ".ogg")
        subprocess.run([
            "ffmpeg", "-y", "-i", wav_path,
            "-c:a", "libopus", "-b:a", "32k",
            "-vbr", "on", "-ac", "1",
            ogg_path
        ], check=True, capture_output=True)

        with open(ogg_path, "rb") as f:
            audio_data = f.read()

        os.remove(wav_path)
        os.remove(ogg_path)

        return {"audio": audio_data.hex(), "sample_rate": sr}
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    host = os.environ.get("QWEN3_TTS_HOST", "127.0.0.1")
    port = int(os.environ.get("QWEN3_TTS_PORT", "8099"))
    uvicorn.run(app, host=host, port=port)
'@

Set-Content -Path $ServerScript -Value $py -Encoding UTF8

$env:QWEN3_TTS_MODEL = $Model
$env:QWEN3_TTS_DEVICE = $Device
$env:QWEN3_TTS_HOST = $BindHost
$env:QWEN3_TTS_PORT = "$Port"

# Avoid UNC working directories when invoked from WSL; use local state dir instead.
$proc = Start-Process -FilePath $PythonPath -ArgumentList "`"$ServerScript`"" -WorkingDirectory $StateDir -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $LogFile -RedirectStandardError $ErrLogFile

$healthHost = $BindHost
if ($healthHost -eq "0.0.0.0" -or $healthHost -eq "::") {
    $healthHost = "127.0.0.1"
}
$healthUrl = "http://$healthHost`:$Port/health"
$deadline = (Get-Date).AddSeconds(60)
$healthy = $false
while ((Get-Date) -lt $deadline) {
    try {
        $resp = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2
        if ($resp.status -eq "ok") {
            $healthy = $true
            break
        }
    } catch {
        # ignore until timeout
    }
    Start-Sleep -Seconds 1
}

if (-not $healthy) {
    try { Stop-Process -Id $proc.Id -Force } catch {}
    throw "Qwen3-TTS warm server failed health check at $healthUrl. See logs: $LogFile, $ErrLogFile"
}

Set-Content -Path $PidFile -Value $proc.Id
Write-Host "Started Qwen3-TTS warm server (PID: $($proc.Id))"
Write-Host "Log: $LogFile"
exit 0
