Param(
    [Parameter(Mandatory = $true)]
    [string]$ModelPath,
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,
    [string]$VoiceName = ""
)

if (-not (Test-Path $ModelPath)) {
    throw "Model file not found: $ModelPath"
}
if (-not (Test-Path $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

if (-not $VoiceName -or $VoiceName -eq "") {
    $VoiceName = [IO.Path]::GetFileNameWithoutExtension($ModelPath)
}

$DestDir = Join-Path $env:USERPROFILE ".cache\tts-models\piper"
New-Item -ItemType Directory -Force -Path $DestDir | Out-Null

$destModel = Join-Path $DestDir ("$VoiceName.onnx")
$destConfig = Join-Path $DestDir ("$VoiceName.onnx.json")

Copy-Item -Force -Path $ModelPath -Destination $destModel
Copy-Item -Force -Path $ConfigPath -Destination $destConfig

Write-Host "Synced voice '$VoiceName' to $DestDir"
