Param(
    [string]$TaskName = "TTS-Server-DirectML",
    [string]$BindHost = "0.0.0.0",
    [int]$Port = 8099,
    [string]$DefaultModel = "piper",
    [string]$Device = "directml",
    [string]$PythonPath = "",
    [switch]$StartNow
)

$ScriptRoot = $PSScriptRoot
$SkillRoot = Split-Path -Parent $ScriptRoot
$StartScript = Join-Path $ScriptRoot "start-server.ps1"

if (-not (Test-Path $StartScript)) {
    throw "Missing start script: $StartScript"
}

$Args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$StartScript`"",
    "-BindHost", "`"$BindHost`"",
    "-Port", "$Port",
    "-DefaultModel", "`"$DefaultModel`"",
    "-Device", "`"$Device`""
)

if ($PythonPath -and $PythonPath -ne "") {
    $Args += @("-PythonPath", "`"$PythonPath`"")
}

$ArgString = $Args -join " "

$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $ArgString -WorkingDirectory $SkillRoot
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Description "DirectML TTS server autostart" -Force | Out-Null

Write-Host "Registered scheduled task: $TaskName"
Write-Host "Start script: $StartScript"
Write-Host "Host: $BindHost  Port: $Port  DefaultModel: $DefaultModel  Device: $Device"

if ($StartNow) {
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "Started task: $TaskName"
}
