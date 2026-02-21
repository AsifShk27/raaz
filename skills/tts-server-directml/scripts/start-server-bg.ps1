Param(
    [string]$BindHost = "127.0.0.1",
    [int]$Port = 8099,
    [string]$DefaultModel = "piper",
    [string]$Device = "directml",
    [string]$PythonPath = ""
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

function Is-WslUncPath {
    param([string]$Path)
    if (-not $Path) {
        return $false
    }
    $lower = $Path.ToLowerInvariant()
    return $lower.StartsWith("\\wsl.localhost\\") -or $lower.StartsWith("\\wsl$\\")
}

function Resolve-PythonPath {
    param([string]$Py, [string[]]$Modules)
    if ($Py) {
        if (Is-WslUncPath -Path $Py) {
            throw "PythonPath points to a WSL filesystem. Install Windows Python + requirements.txt or set OPENCLAW_WIN_PYTHON to a Windows path."
        }
        if (Test-Path $Py) {
            if (Test-PythonModules -Py $Py -Modules $Modules) {
                return $Py
            }
            throw "Python at $Py missing required modules: $($Modules -join ', ')"
        }
    }

    $venvPy = Join-Path $SkillRoot ".venv\Scripts\python.exe"
    if (-not (Is-WslUncPath -Path $venvPy)) {
        if ((Test-Path $venvPy) -and (Test-PythonModules -Py $venvPy -Modules $Modules)) {
            return $venvPy
        }
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

$probeHost = $BindHost
if ($probeHost -eq "0.0.0.0") {
    $probeHost = "127.0.0.1"
}

if (Test-Path $PidFile) {
    $oldPid = Get-Content $PidFile -ErrorAction SilentlyContinue
    if ($oldPid) {
        try {
            $proc = Get-Process -Id $oldPid -ErrorAction Stop
            # Quick health check
            try {
                $resp = Invoke-RestMethod -Uri "http://$probeHost`:$Port/health" -TimeoutSec 2
                if ($resp.status -eq "ok") {
                    Write-Host "TTS server already running (PID: $oldPid)"
                    exit 0
                }
            } catch {}
            Write-Host "TTS server process exists but not healthy. Restarting..."
            try { Stop-Process -Id $oldPid -Force } catch {}
        } catch {
            # stale pid file
        }
        Remove-Item $PidFile -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path $ServerScript)) {
    throw "Server script not found: $ServerScript"
}

$env:TTS_HOST = $BindHost
$env:TTS_PORT = $Port
$env:TTS_DEFAULT_MODEL = $DefaultModel
$env:TTS_DEVICE = $Device

$proc = Start-Process -FilePath $PythonPath -ArgumentList "`"$ServerScript`"" -WorkingDirectory $SkillRoot -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $LogFile -RedirectStandardError $ErrFile

$healthHost = $BindHost
if ($healthHost -eq "0.0.0.0") {
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
    throw "TTS server failed health check at $healthUrl. See log: $LogFile"
}

Set-Content -Path $PidFile -Value $proc.Id
Write-Host "Started TTS server (PID: $($proc.Id))"
Write-Host "Log: $LogFile"
exit 0
