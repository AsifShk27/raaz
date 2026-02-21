Param(
    [string]$Text = "",
    [string]$TextFile = "",
    [string]$Out = "",
    [string]$Model = "Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign",
    [string]$Language = "English",
    [string]$Instruct = "Speak with a cheerful American accent in a robotic, futuristic tone.",
    [int]$TopK = 50,
    [double]$TopP = 0.95,
    [double]$Temp = 1.0,
    [int]$MaxChars = 3000,
    [string]$PythonPath = ""
)

if (-not $PSBoundParameters.ContainsKey('Model')) {
    if ($env:QWEN3_TTS_MODEL) {
        $Model = $env:QWEN3_TTS_MODEL
    } elseif ($env:QWEN3_TTS_MODEL_DIR -and (Test-Path $env:QWEN3_TTS_MODEL_DIR)) {
        $Model = $env:QWEN3_TTS_MODEL_DIR
    }
}

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

if (-not $Out -or $Out -eq "") {
    throw "Output path is required (-Out)."
}

if (-not $Text -and -not $TextFile) {
    throw "Provide -Text or -TextFile."
}

if ($TextFile) {
    if (-not (Test-Path $TextFile)) {
        throw "Text file not found: $TextFile"
    }
    $Text = Get-Content -Raw -Path $TextFile
}

if ($Text.Length -gt $MaxChars) {
    $Text = $Text.Substring(0, $MaxChars)
}

$PythonPath = Resolve-PythonPath -Py $PythonPath -Modules @("torch_directml", "qwen_tts", "soundfile", "torch")

$code = @'
import os
import sys
import json
import torch
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

text = sys.argv[1]
out_path = sys.argv[2]
model_id = sys.argv[3]
language = sys.argv[4]
instruct = sys.argv[5]
top_k = int(sys.argv[6])
top_p = float(sys.argv[7])
temp = float(sys.argv[8])

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
language = language_map.get(language.strip().lower(), language)

local_only = os.environ.get("QWEN3_TTS_LOCAL_ONLY", "").lower() in ("1", "true", "yes")
if os.path.isdir(model_id):
    local_only = True
if local_only:
    os.environ.setdefault("HF_HUB_OFFLINE", "1")

try:
    import torch_directml
    if torch_directml.device_count() <= 0:
        raise RuntimeError("No DirectML devices found")
    device = torch_directml.device(0)
    device_kind = "directml"
except Exception as e:
    device = torch.device("cpu")
    device_kind = "cpu"
    print(f"torch_directml not available, using CPU: {e}", file=sys.stderr)

from qwen_tts import Qwen3TTSModel

print(f"Loading model {model_id} on {device_kind}...", file=sys.stderr)
dtype = torch.float32 if device_kind == "directml" else torch.float32
attn_impl = "eager" if device_kind == "directml" else "auto"
try:
    load_kwargs = {
        "dtype": dtype,
        "local_files_only": local_only,
    }
    if attn_impl and attn_impl != "auto":
        load_kwargs["attn_implementation"] = attn_impl
    model = Qwen3TTSModel.from_pretrained(model_id, **load_kwargs)
except Exception as e:
    if dtype == torch.float16:
        print(f"Retrying model load in fp32: {e}", file=sys.stderr)
        load_kwargs = {
            "dtype": torch.float32,
            "local_files_only": local_only,
        }
        if attn_impl and attn_impl != "auto":
            load_kwargs["attn_implementation"] = attn_impl
        model = Qwen3TTSModel.from_pretrained(model_id, **load_kwargs)
    else:
        raise

if device_kind != "cpu":
    try:
        model.model.to(device)
        model.device = device
    except Exception as e:
        print(f"Failed to move model to {device_kind}, using CPU: {e}", file=sys.stderr)
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

print("Generating audio...", file=sys.stderr)
wavs, sr = model.generate_voice_design(
    text=text,
    instruct=instruct,
    language=language,
    do_sample=True,
    top_k=top_k,
    top_p=top_p,
    temperature=temp,
    max_new_tokens=2048,
    use_cache=(device_kind != "directml"),
    repetition_penalty=(1.0 if device_kind == "directml" else 1.05)
)

wav_path = out_path.replace(".ogg", ".wav")
sf.write(wav_path, wavs[0], sr)

subprocess.run([
    "ffmpeg", "-y", "-i", wav_path,
    "-c:a", "libopus", "-b:a", "32k",
    "-vbr", "on", "-ac", "1",
    out_path
], check=True, capture_output=True)

os.remove(wav_path)
print(json.dumps({"success": True, "output": out_path}), file=sys.stdout)
'@

$tmpFile = [System.IO.Path]::GetTempFileName()
Set-Content -Path $tmpFile -Value $code -Encoding UTF8
try {
    & $PythonPath $tmpFile $Text $Out $Model $Language $Instruct $TopK $TopP $Temp
} finally {
    Remove-Item $tmpFile -ErrorAction SilentlyContinue
}
