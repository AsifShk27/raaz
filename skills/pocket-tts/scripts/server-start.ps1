Param(
    [string]$BindHost = "127.0.0.1",
    [int]$Port = 8099,
    [string]$Device = "auto",
    [string]$PythonPath = ""
)

$StateDir = Join-Path $env:USERPROFILE ".openclaw\\pocket-tts"
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
            throw "PythonPath points to a WSL filesystem. Install Windows Python + pocket-tts or set OPENCLAW_WIN_PYTHON to a Windows path."
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
    throw "No Python found with required modules: $($Modules -join ', '). Install pocket-tts into a Windows venv."
}

$required = @("pocket_tts", "fastapi", "uvicorn", "soundfile", "torch")
if ($Device -in @("directml", "dml")) {
    $required += "torch_directml"
}

$PythonPath = Resolve-PythonPath -Py $PythonPath -Modules $required

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
                if ($resp.status -eq "healthy") {
                    Write-Host "Pocket TTS server already running (PID: $oldPid)"
                    exit 0
                }
            } catch {}
            Write-Host "Pocket TTS process exists but not healthy. Restarting..."
            try { Stop-Process -Id $oldPid -Force } catch {}
        } catch {
            # stale pid file
        }
        Remove-Item $PidFile -ErrorAction SilentlyContinue
    }
}

$scriptsDir = Split-Path -Parent $PythonPath
$pocketCli = Join-Path $scriptsDir "pocket-tts.exe"

if (Test-Path $pocketCli) {
    $proc = Start-Process -FilePath $pocketCli -ArgumentList @(
        "serve",
        "--host", $BindHost,
        "--port", $Port,
        "--device", $Device
    ) -WorkingDirectory $StateDir -WindowStyle Hidden -PassThru `
      -RedirectStandardOutput $LogFile -RedirectStandardError $ErrFile
} else {
    $proc = Start-Process -FilePath $PythonPath -ArgumentList @(
        "-m", "pocket_tts.main", "serve",
        "--host", $BindHost,
        "--port", $Port,
        "--device", $Device
    ) -WorkingDirectory $StateDir -WindowStyle Hidden -PassThru `
      -RedirectStandardOutput $LogFile -RedirectStandardError $ErrFile
}

$healthHost = $BindHost
if ($healthHost -eq "0.0.0.0") {
    $healthHost = "127.0.0.1"
}
$healthUrl = "http://$healthHost`:$Port/health"
$deadline = (Get-Date).AddSeconds(90)
$healthy = $false
while ((Get-Date) -lt $deadline) {
    try {
        $resp = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2
        if ($resp.status -eq "healthy") {
            $healthy = $true
            break
        }
    } catch {
        # ignore until timeout
    }
    Start-Sleep -Seconds 1
}

if (-not $healthy) {
    try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
    throw "Pocket TTS failed health check at $healthUrl. See log: $LogFile"
}

Set-Content -Path $PidFile -Value $proc.Id
Write-Host "Started Pocket TTS server (PID: $($proc.Id))"
Write-Host "Log: $LogFile"
exit 0
