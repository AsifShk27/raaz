Param(
    [string]$BindHost = "0.0.0.0",
    [int]$Port = 8111,
    [string]$Model = "medium",
    [string]$Device = "directml",
    [string]$Engine = "auto",
    [string]$PythonPath = ""
)

$ScriptRoot = $PSScriptRoot
$SkillRoot = Split-Path -Parent $ScriptRoot
$StateDir = Join-Path $env:USERPROFILE ".openclaw\\whisper-server"
$PidFile = Join-Path $StateDir "server.pid"
$LogFile = Join-Path $StateDir "server.log"
$ErrFile = Join-Path $StateDir "server.err.log"
$ServerScript = Join-Path $SkillRoot "scripts\\server.py"

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
    param([string]$Py, [object[]]$ModuleGroups)
    if ($Py) {
        if (Is-WslUncPath -Path $Py) {
            throw "PythonPath points to a WSL filesystem. Install Windows Python + onnx-asr/onnxruntime-directml or openai-whisper/torch-directml, or set OPENCLAW_WIN_PYTHON to a Windows path."
        }
        if (Test-Path $Py) {
            foreach ($group in $ModuleGroups) {
                if (Test-PythonModules -Py $Py -Modules $group) {
                    return $Py
                }
            }
            $groupsText = ($ModuleGroups | ForEach-Object { $_ -join ", " }) -join " OR "
            throw "Python at $Py missing required modules: $groupsText"
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
try {
    $PythonPath = Resolve-PythonPath -Py $PythonPath -ModuleGroups @(
        @("onnx_asr", "onnxruntime"),
        @("torch_directml", "whisper")
    )
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}

if (Test-Path $PidFile) {
    $oldPid = Get-Content $PidFile -ErrorAction SilentlyContinue
    if ($oldPid) {
        try {
            $proc = Get-Process -Id $oldPid -ErrorAction Stop
            try {
                $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 2
                if ($resp.status -eq "ok") {
                    Write-Host "Whisper server already running (PID: $oldPid)"
                    exit 0
                }
            } catch {}
            Write-Host "Whisper server process exists but not healthy. Restarting..."
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

$env:WHISPER_HOST = $BindHost
$env:WHISPER_PORT = $Port
$env:WHISPER_MODEL = $Model
$env:WHISPER_DEVICE = $Device
$env:WHISPER_ENGINE = $Engine

$proc = Start-Process -FilePath $PythonPath -ArgumentList "`"$ServerScript`"" -WorkingDirectory $SkillRoot -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $LogFile -RedirectStandardError $ErrFile

$healthHost = $BindHost
if ($healthHost -eq "0.0.0.0") {
    $healthHost = "127.0.0.1"
}
$healthUrl = "http://$healthHost`:$Port/health"
$deadline = (Get-Date).AddSeconds(45)
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
    throw "Whisper server failed health check at $healthUrl. See log: $LogFile"
}

Set-Content -Path $PidFile -Value $proc.Id
Write-Host "Started Whisper server (PID: $($proc.Id))"
Write-Host "Log: $LogFile"
exit 0
