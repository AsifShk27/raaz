Param(
    [string]$BindHost = "0.0.0.0",
    [int]$Port = 8099,
    [string]$DefaultModel = "piper",
    [string]$Device = "directml",
    [string]$PythonPath = "",
    [string]$Qwen3Model = "",
    [switch]$Qwen3LocalOnly,
    [switch]$FastMode,
    [string]$Qwen3Dtype = "",
    [int]$Qwen3FastMaxNewTokens = 0
)

$ScriptRoot = $PSScriptRoot
$SkillRoot = Split-Path -Parent $ScriptRoot
$StateDir = Join-Path $env:USERPROFILE ".openclaw\tts-server-directml"
$PidFile = Join-Path $StateDir "server.pid"
$LogFile = Join-Path $StateDir "server.log"
$ErrFile = Join-Path $StateDir "server.err.log"
$ServerScript = Join-Path $SkillRoot "scripts\server.py"

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

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

    $venvPy = Join-Path $SkillRoot ".venv\Scripts\python.exe"
    if (Test-Path $venvPy -and (Test-PythonModules -Py $venvPy -Modules $Modules)) {
        return $venvPy
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
    throw "No Python found with required modules: $($Modules -join ', '). Install Python 3.12 + requirements.txt for tts-server-directml."
}

$PythonPath = Resolve-PythonPath -Py $PythonPath -Modules @(
    "fastapi",
    "uvicorn",
    "soundfile",
    "numpy",
    "onnxruntime",
    "torch"
)

if (-not (Test-Path $ServerScript)) {
    throw "Server script not found: $ServerScript"
}

if (Test-Path $PidFile) {
    $oldPid = Get-Content $PidFile -ErrorAction SilentlyContinue
    if ($oldPid) {
        try {
            $proc = Get-Process -Id $oldPid -ErrorAction Stop
            Write-Host "TTS server already running (PID: $oldPid)"
            exit 0
        } catch {
            Remove-Item $PidFile -ErrorAction SilentlyContinue
        }
    }
}

$env:TTS_HOST = $BindHost
$env:TTS_PORT = $Port
$env:TTS_DEFAULT_MODEL = $DefaultModel
$env:TTS_DEVICE = $Device
if ($Qwen3Model -and $Qwen3Model -ne "") {
    $env:QWEN3_TTS_MODEL = $Qwen3Model
}
if ($Qwen3LocalOnly) {
    $env:QWEN3_TTS_LOCAL_ONLY = "1"
}
if ($FastMode) {
    $env:QWEN3_TTS_FAST = "1"
}
if ($Qwen3Dtype -and $Qwen3Dtype -ne "") {
    $env:QWEN3_TTS_DTYPE = $Qwen3Dtype
}
if ($Qwen3FastMaxNewTokens -gt 0) {
    $env:QWEN3_TTS_FAST_MAX_NEW_TOKENS = "$Qwen3FastMaxNewTokens"
}

$proc = Start-Process -FilePath $PythonPath -ArgumentList "`"$ServerScript`"" -WorkingDirectory $SkillRoot -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $LogFile -RedirectStandardError $ErrFile

Set-Content -Path $PidFile -Value $proc.Id
Write-Host "Started TTS server (PID: $($proc.Id))"
Write-Host "Log: $LogFile"
exit 0
