Param(
    [string]$Audio = "",
    [string]$Text = "",
    [string]$VoiceRef = "",
    [string]$VoiceText = "",
    [string]$Out = "",
    [string]$Model = "FlashLabs/Chroma-4B",
    [string]$SystemPrompt = "You are Chroma, a helpful voice assistant. Respond naturally and conversationally.",
    [string]$PythonPath = ""
)

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
    throw "No Python found with required modules: $($Modules -join ', '). Install Python 3.12 + torch-directml + transformers."
}

if (-not $Out -or $Out -eq "") {
    throw "Output path is required (-Out)."
}

if (-not $Text -and -not $Audio) {
    throw "Provide -Text or -Audio."
}

if ($Audio -and -not (Test-Path $Audio)) {
    throw "Audio file not found: $Audio"
}

if ($VoiceRef -and -not (Test-Path $VoiceRef)) {
    throw "Voice reference file not found: $VoiceRef"
}

$PythonPath = Resolve-PythonPath -Py $PythonPath -Modules @("torch_directml", "transformers", "soundfile", "torch")

$outDir = Split-Path -Parent $Out
if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

$env:CHROMA_AUDIO = $Audio
$env:CHROMA_TEXT = $Text
$env:CHROMA_VOICE_REF = $VoiceRef
$env:CHROMA_VOICE_TEXT = $VoiceText
$env:CHROMA_OUT = $Out
$env:CHROMA_MODEL = $Model
$env:CHROMA_SYSTEM_PROMPT = $SystemPrompt

$code = @'
import os
import sys
import torch
import soundfile as sf
import subprocess

model_id = os.environ.get("CHROMA_MODEL", "")
audio_input = os.environ.get("CHROMA_AUDIO", "").strip() or None
text_input = os.environ.get("CHROMA_TEXT", "").strip() or None
voice_ref = os.environ.get("CHROMA_VOICE_REF", "").strip() or None
voice_text = os.environ.get("CHROMA_VOICE_TEXT", "").strip() or None
output_file = os.environ.get("CHROMA_OUT", "")
system_prompt = os.environ.get("CHROMA_SYSTEM_PROMPT", "")

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

print(f"Loading Chroma model: {model_id} on {device_kind}", file=sys.stderr)

try:
    from transformers import AutoModelForCausalLM, AutoProcessor

    dtype = torch.float16 if device_kind == "directml" else torch.float32
    try:
        model = AutoModelForCausalLM.from_pretrained(
            model_id,
            trust_remote_code=True,
            device_map="cpu",
            torch_dtype=dtype,
        )
    except Exception as e:
        if dtype == torch.float16:
            print(f"Retrying model load in fp32: {e}", file=sys.stderr)
            model = AutoModelForCausalLM.from_pretrained(
                model_id,
                trust_remote_code=True,
                device_map="cpu",
                torch_dtype=torch.float32,
            )
        else:
            raise

    if device_kind != "cpu":
        try:
            model = model.to(device)
        except Exception as e:
            print(f"Failed to move model to {device_kind}, using CPU: {e}", file=sys.stderr)
            device = torch.device("cpu")
            device_kind = "cpu"
            model = model.to(device)

    processor = AutoProcessor.from_pretrained(model_id, trust_remote_code=True)
except Exception as e:
    print(f"Error loading model: {e}", file=sys.stderr)
    sys.exit(1)

conversation = [[
    {
        "role": "system",
        "content": [{"type": "text", "text": system_prompt}],
    },
    {
        "role": "user",
        "content": [],
    },
]]

if audio_input:
    conversation[0][1]["content"].append({"type": "audio", "audio": audio_input})
elif text_input:
    conversation[0][1]["content"].append({"type": "text", "text": text_input})

prompt_audio = [voice_ref] if voice_ref else None
prompt_text = [voice_text] if voice_text else None

inputs = processor(
    conversation,
    add_generation_prompt=True,
    tokenize=False,
    prompt_audio=prompt_audio,
    prompt_text=prompt_text,
)

inputs = {k: v.to(device) if hasattr(v, "to") else v for k, v in inputs.items()}

with torch.no_grad():
    output = model.generate(
        **inputs,
        max_new_tokens=200,
        do_sample=True,
        temperature=0.7,
        top_p=0.9,
        use_cache=True,
    )

# Decode audio
print("Decoding audio...", file=sys.stderr)
audio_values = model.codec_model.decode(output.permute(0, 2, 1)).audio_values
audio_np = audio_values[0].cpu().detach().numpy()

wav_path = output_file.replace(".ogg", ".wav")
sf.write(wav_path, audio_np, 24000)

subprocess.run([
    "ffmpeg", "-y", "-i", wav_path,
    "-c:a", "libopus", "-b:a", "48k",
    "-vbr", "on", "-ac", "1",
    output_file,
], check=True, capture_output=True)

os.remove(wav_path)
print(output_file, file=sys.stdout)
'@

& $PythonPath -c $code
