Param(
    [string]$BindHost = "0.0.0.0",
    [int]$Port = 7860,
    [string]$Device = "directml",
    [string]$Checkpoint = "",
    [string]$RepoRoot = "",
    [string]$Voice = "",
    [string]$PythonPath = ""
)

$StateDir = Join-Path $env:USERPROFILE ".openclaw\\vibevoice"
$PidFile = Join-Path $StateDir "server.pid"
$LogFile = Join-Path $StateDir "server.log"
$ErrFile = Join-Path $StateDir "server.err.log"

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
            throw "PythonPath points to a WSL filesystem. Install Windows Python + DirectML requirements."
        }
        if (Test-Path $Py) {
            if (Test-PythonModules -Py $Py -Modules $Modules) {
                return $Py
            }
            throw "Python at $Py missing required modules: $($Modules -join ', ')"
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
    throw "No Python found with required modules: $($Modules -join ', '). Install torch-directml + transformers + soundfile."
}

$required = @("torch_directml", "transformers", "soundfile", "torch", "diffusers")
$PythonPath = Resolve-PythonPath -Py $PythonPath -Modules $required

if (-not $RepoRoot) {
    $RepoRoot = $env:VIBEVOICE_REPO
}
if (-not $RepoRoot) {
    throw "RepoRoot is required (set VIBEVOICE_REPO or pass -RepoRoot)."
}

if (-not $Checkpoint) {
    $Checkpoint = $env:VIBEVOICE_CHECKPOINT
}
if (-not $Checkpoint) {
    throw "Checkpoint is required (set VIBEVOICE_CHECKPOINT or pass -Checkpoint)."
}

$ServerScript = Join-Path $PSScriptRoot "vibevoice-server.py"
if (-not (Test-Path $ServerScript)) {
    throw "Server script not found: $ServerScript"
}

$probeHost = $BindHost
if ($probeHost -eq "0.0.0.0") {
    $probeHost = "127.0.0.1"
}

if (Test-Path $PidFile) {
    $oldPid = Get-Content $PidFile -ErrorAction SilentlyContinue
    if ($oldPid) {
        try {
            $proc = Get-Process -Id $oldPid -ErrorAction Stop
            try {
                $resp = Invoke-RestMethod -Uri "http://$probeHost`:$Port/health" -TimeoutSec 2
                if ($resp.status -eq "ok") {
                    Write-Host "VibeVoice server already running (PID: $oldPid)"
                    exit 0
                }
            } catch {}
            Write-Host "VibeVoice server process exists but not healthy. Restarting..."
            try { Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue } catch {}
        } catch {
            # stale pid file
        }
        Remove-Item $PidFile -ErrorAction SilentlyContinue
    }
}

$env:VIBEVOICE_REPO = $RepoRoot
$env:VIBEVOICE_CHECKPOINT = $Checkpoint
$env:VIBEVOICE_DEVICE = $Device
$env:VIBEVOICE_SERVER_PORT = $Port
if ($Voice) {
    $env:VIBEVOICE_VOICE = $Voice
}

$proc = Start-Process -FilePath $PythonPath -ArgumentList @(
    "`"$ServerScript`"",
    "--host", $BindHost,
    "--port", $Port
) -WorkingDirectory $StateDir -WindowStyle Hidden -PassThru `
  -RedirectStandardOutput $LogFile -RedirectStandardError $ErrFile

$healthUrl = "http://$probeHost`:$Port/health"
$deadline = (Get-Date).AddSeconds(180)
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
    Start-Sleep -Seconds 2
}

if (-not $healthy) {
    try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
    throw "VibeVoice failed health check at $healthUrl. See log: $LogFile"
}

Set-Content -Path $PidFile -Value $proc.Id
Write-Host "Started VibeVoice server (PID: $($proc.Id))"
Write-Host "Log: $LogFile"
exit 0
