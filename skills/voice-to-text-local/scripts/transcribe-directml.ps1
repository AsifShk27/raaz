Param(
    [Parameter(Mandatory = $true)]
    [string]$AudioPath,
    [string]$Model = "base",
    [string]$Language = "",
    [string]$Task = "transcribe",
    [string]$Engine = "auto",
    [string]$Out = "",
    [string]$PythonPath = ""
)

if (-not (Test-Path $AudioPath)) {
    throw "Audio file not found: $AudioPath"
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

function Test-PythonModules {
    param([string]$Py, [string[]]$Modules)
    $importLine = ($Modules | ForEach-Object { "import $($_)" }) -join "; "
    & $Py -c $importLine *> $null
    return ($LASTEXITCODE -eq 0)
}

function Resolve-PythonPath {
    param([string]$Py, [object[]]$ModuleGroups)
    if ($Py -and (Test-Path $Py)) {
        foreach ($group in $ModuleGroups) {
            if (Test-PythonModules -Py $Py -Modules $group) {
                return $Py
            }
        }
        $groupsText = ($ModuleGroups | ForEach-Object { $_ -join ", " }) -join " OR "
        throw "Python at $Py missing required modules: $groupsText"
    }

    $candidates = @()
    try {
        $candidates += (& py -3.12 -c "import sys; print(sys.executable)" 2>$null)
    } catch {}
    try {
        $candidates += (Get-Command python).Source
    } catch {}

    foreach ($cand in $candidates | Where-Object { $_ } | Select-Object -Unique) {
        if (Test-Path $cand) {
            foreach ($group in $ModuleGroups) {
                if (Test-PythonModules -Py $cand -Modules $group) {
                    return $cand
                }
            }
        }
    }
    $groupsText = ($ModuleGroups | ForEach-Object { $_ -join ", " }) -join " OR "
    throw "No Python found with required modules: $groupsText. Install Python 3.12 + onnx-asr + onnxruntime-directml OR openai-whisper + torch-directml."
}

Ensure-FfmpegPath
$PythonPath = Resolve-PythonPath -Py $PythonPath -ModuleGroups @(
    @("onnx_asr", "onnxruntime"),
    @("torch_directml", "whisper")
)

$code = @'
import sys
import os
import json
import tempfile
import subprocess
import wave

SENTINEL = "__OPENCLAW_EMPTY__"

audio_path = sys.argv[1]
model_name = sys.argv[2]
language = sys.argv[3] if len(sys.argv) > 3 else ""
task = sys.argv[4] if len(sys.argv) > 4 else "transcribe"
out_path = sys.argv[5] if len(sys.argv) > 5 else ""
engine_pref = sys.argv[6] if len(sys.argv) > 6 else ""

if language == SENTINEL:
    language = ""
if task == SENTINEL:
    task = "transcribe"
if out_path == SENTINEL:
    out_path = ""
if engine_pref == SENTINEL:
    engine_pref = ""
if not engine_pref:
    engine_pref = os.environ.get("WHISPER_ENGINE", "")
engine_pref = engine_pref.strip().lower()

prefer_onnx = True
force_onnx = False
if engine_pref in ("onnx", "onnx_asr"):
    prefer_onnx = True
    force_onnx = True
elif engine_pref in ("whisper", "openai"):
    prefer_onnx = False

def resolve_onnx_model(name):
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

def ensure_wav(path):
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
    cmd = ["ffmpeg", "-y", "-i", path, "-ac", "1", "-ar", "16000", "-acodec", "pcm_s16le", tmp.name]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return tmp.name, tmp.name

def try_onnx_asr():
    try:
        import onnxruntime as ort
        if "DmlExecutionProvider" not in ort.get_available_providers():
            return None, "DirectML provider not available"
        import onnx_asr
    except Exception as e:
        return None, f"onnx_asr unavailable: {e}"

    model_id = resolve_onnx_model(model_name)
    if not model_id:
        return None, f"Unsupported ONNX model mapping for '{model_name}'."
    if model_id != model_name:
        print(f"Mapping Whisper model '{model_name}' -> ONNX '{model_id}' for DirectML.", file=sys.stderr)
    try:
        model = onnx_asr.load_model(model_id, providers=["DmlExecutionProvider", "CPUExecutionProvider"])
    except Exception as e:
        return None, f"onnx_asr load failed: {e}"
    print(f"Using onnx_asr model '{model_id}' with DirectML provider.", file=sys.stderr)

    wav_path = None
    tmp_path = None
    try:
        wav_path, tmp_path = ensure_wav(audio_path)
        kwargs = {}
        if language:
            kwargs["language"] = language
        if task:
            kwargs["task"] = task
        try:
            result = model.recognize(wav_path, **kwargs)
        except TypeError:
            result = model.recognize(wav_path)
    except Exception as e:
        return None, f"onnx_asr run failed: {e}"
    finally:
        if tmp_path:
            try:
                os.unlink(tmp_path)
            except Exception:
                pass

    if isinstance(result, list):
        result = result[0] if result else ""
    if isinstance(result, str):
        return result.strip(), None
    if hasattr(result, "text"):
        return str(result.text).strip(), None
    return str(result).strip(), None

directml_available = False
try:
    import onnxruntime as ort
    directml_available = "DmlExecutionProvider" in ort.get_available_providers()
except Exception:
    directml_available = False

text = None
onnx_error = None
if directml_available and prefer_onnx:
    text, onnx_error = try_onnx_asr()
    if force_onnx and not text:
        print(f"DirectML ONNX failed and WHISPER_ENGINE=onnx set: {onnx_error}", file=sys.stderr)
        sys.exit(1)
elif force_onnx:
    print("DirectML ONNX requested but provider unavailable", file=sys.stderr)
    sys.exit(1)

if not text:
    if onnx_error:
        print(f"onnx_asr directml failed, falling back to whisper: {onnx_error}", file=sys.stderr)
    try:
        import torch
        import torch_directml
        if torch_directml.device_count() <= 0:
            raise RuntimeError("No DirectML devices found")
        device = torch_directml.device(0)
        device_kind = "directml"
    except Exception as e:
        device = "cpu"
        device_kind = "cpu"
        print(f"torch_directml not available, using CPU: {e}", file=sys.stderr)

    try:
        import whisper
    except Exception as e:
        print(f"Failed to import whisper: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Loading Whisper model '{model_name}' on {device_kind}...", file=sys.stderr)
    model = whisper.load_model(model_name, device="cpu")
    if device_kind == "directml":
        try:
            model = model.to(device)
        except Exception as e:
            print(f"Failed to move model to DirectML, using CPU: {e}", file=sys.stderr)
            device_kind = "cpu"

    kwargs = {}
    if language:
        kwargs["language"] = language
    if task:
        kwargs["task"] = task

    result = model.transcribe(audio_path, **kwargs)
    text = result.get("text", "").strip()

if not text:
    print("Transcription is empty", file=sys.stderr)
    sys.exit(2)

if out_path:
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(text)
    print(out_path)
else:
    print(text)
'@

$tmpFile = [System.IO.Path]::GetTempFileName()
Set-Content -Path $tmpFile -Value $code -Encoding UTF8
try {
    $sentinel = "__OPENCLAW_EMPTY__"
    $pyLanguage = if ($Language) { $Language } else { $sentinel }
    $pyTask = if ($Task) { $Task } else { $sentinel }
    $pyOut = if ($Out) { $Out } else { $sentinel }
    $pyEngine = if ($Engine) { $Engine } else { $sentinel }
    & $PythonPath $tmpFile $AudioPath $Model $pyLanguage $pyTask $pyOut $pyEngine
} finally {
    Remove-Item $tmpFile -ErrorAction SilentlyContinue
}
