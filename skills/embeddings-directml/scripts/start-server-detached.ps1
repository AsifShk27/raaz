Param(
    [string]$BindHost = "0.0.0.0",
    [int]$Port = 8124,
    [string]$Model = "BAAI/bge-base-en-v1.5",
    [string]$Device = "directml",
    [string]$Pooling = "cls",
    [string]$PythonPath = ""
)

$ScriptRoot = $PSScriptRoot
$SkillRoot = Split-Path -Parent $ScriptRoot
$StateDir = Join-Path $env:USERPROFILE ".openclaw\embeddings-directml"
$PidFile = Join-Path $StateDir "server.pid"
$LogFile = Join-Path $StateDir "server.log"
$ErrFile = Join-Path $StateDir "server.err.log"
$ServerScript = Join-Path $SkillRoot "scripts\embeddings-server.py"

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
    throw "No Python found with required modules: $($Modules -join ', '). Install transformers + torch-directml + fastapi + uvicorn."
}

$modules = @(
    "transformers",
    "torch",
    "fastapi",
    "uvicorn",
    "pydantic",
    "numpy"
)
if ($Device -in @("directml", "dml")) {
    $modules += "torch_directml"
}
$PythonPath = Resolve-PythonPath -Py $PythonPath -Modules $modules

if (-not (Test-Path $ServerScript)) {
    throw "Server script not found: $ServerScript"
}

if (Test-Path $PidFile) {
    $oldPid = Get-Content $PidFile -ErrorAction SilentlyContinue
    if ($oldPid) {
        try {
            $proc = Get-Process -Id $oldPid -ErrorAction Stop
            Write-Host "Embeddings server already running (PID: $oldPid)"
            exit 0
        } catch {
            Remove-Item $PidFile -ErrorAction SilentlyContinue
        }
    }
}

$env:EMBEDDINGS_HOST = $BindHost
$env:EMBEDDINGS_PORT = $Port
$env:EMBEDDINGS_MODEL = $Model
$env:EMBEDDINGS_DEVICE = $Device
$env:EMBEDDINGS_POOLING = $Pooling

$proc = Start-Process -FilePath $PythonPath -ArgumentList "`"$ServerScript`"" -WorkingDirectory $SkillRoot -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $LogFile -RedirectStandardError $ErrFile

Set-Content -Path $PidFile -Value $proc.Id
Write-Host "Started embeddings server (PID: $($proc.Id))"
Write-Host "Log: $LogFile"
exit 0
