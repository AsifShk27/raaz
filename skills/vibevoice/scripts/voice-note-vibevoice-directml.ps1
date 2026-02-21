Param(
    [string]$Text = "",
    [string]$TextFile = "",
    [string]$Out = "",
    [string]$Voice = "Samuel",
    [string]$Checkpoint = "",
    [string]$RepoRoot = "",
    [double]$CfgScale = 1.5,
    [int]$MaxChars = 6000,
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

if (-not $Text -and -not $TextFile) {
    throw "Provide -Text or -TextFile."
}

if (-not $Checkpoint -or -not (Test-Path $Checkpoint)) {
    throw "Checkpoint path not found: $Checkpoint"
}

if (-not $RepoRoot -or -not (Test-Path $RepoRoot)) {
    throw "Repo root not found: $RepoRoot"
}

$PythonPath = Resolve-PythonPath -Py $PythonPath -Modules @("torch_directml", "transformers", "soundfile", "torch")

$outDir = Split-Path -Parent $Out
if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

$tempDir = Join-Path $env:TEMP ("vibevoice-" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempDir | Out-Null

try {
    if ($TextFile) {
        if (-not (Test-Path $TextFile)) {
            throw "Text file not found: $TextFile"
        }
        $Text = Get-Content -Raw -Path $TextFile
    }

    if (-not $Text) {
        throw "Text is empty"
    }

    if ($Text.Length -gt $MaxChars) {
        $Text = $Text.Substring(0, $MaxChars)
    }

    $txtPath = Join-Path $tempDir "input.txt"
    Set-Content -Path $txtPath -Value $Text -NoNewline

    $demoScript = Join-Path $RepoRoot "demo\realtime_model_inference_from_file.py"
    if (-not (Test-Path $demoScript)) {
        throw "Demo script not found: $demoScript"
    }

    $env:PYTHONPATH = "$RepoRoot;$($env:PYTHONPATH)"
    Push-Location $RepoRoot
    $pythonArgs = @(
        $demoScript,
        "--model_path", $Checkpoint,
        "--txt_path", $txtPath,
        "--speaker_name", $Voice,
        "--output_dir", $tempDir,
        "--device", "directml",
        "--cfg_scale", $CfgScale
    )
    & $PythonPath @pythonArgs
    $exitCode = $LASTEXITCODE
    Pop-Location

    if ($exitCode -ne 0) {
        throw "VibeVoice inference failed (exit $exitCode)"
    }

    $generatedWav = Join-Path $tempDir "input_generated.wav"
    if (-not (Test-Path $generatedWav)) {
        throw "Generated WAV not found: $generatedWav"
    }

    $ext = [IO.Path]::GetExtension($Out).ToLowerInvariant()
    if ($ext -eq ".ogg") {
        & ffmpeg -y -i $generatedWav -c:a libopus -b:a 32k -ar 48000 -ac 1 -application voip $Out | Out-Null
    } elseif ($ext -eq ".mp3") {
        & ffmpeg -y -i $generatedWav -c:a libmp3lame -b:a 64k $Out | Out-Null
    } else {
        Copy-Item -Path $generatedWav -Destination $Out -Force
    }
} finally {
    if (Test-Path $tempDir) {
        Remove-Item -Recurse -Force $tempDir
    }
}
