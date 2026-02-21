Param(
    [string]$BindHost = "0.0.0.0",
    [int]$Port = 8099,
    [string]$DefaultModel = "piper",
    [string]$Device = "directml",
    [string]$PythonPath = ""
)

$ScriptRoot = $PSScriptRoot
$SkillRoot = Split-Path -Parent $ScriptRoot

if (-not $PythonPath -or $PythonPath -eq "") {
    $VenvPython = Join-Path $SkillRoot ".venv\\Scripts\\python.exe"
    if (Test-Path $VenvPython) {
        $PythonPath = $VenvPython
    } else {
        try {
            $PythonPath = (Get-Command python).Source
        } catch {
            throw "Python not found. Install Python or create a venv in $SkillRoot\\.venv"
        }
    }
}

if (-not (Test-Path $PythonPath)) {
    throw "Python not found at: $PythonPath"
}

$env:TTS_HOST = $BindHost
$env:TTS_PORT = $Port
$env:TTS_DEFAULT_MODEL = $DefaultModel
$env:TTS_DEVICE = $Device

Set-Location $SkillRoot
& $PythonPath "scripts\\server.py"
