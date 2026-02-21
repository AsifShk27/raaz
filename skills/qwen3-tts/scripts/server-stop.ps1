Param(
    [string]$PidFile = "$env:USERPROFILE\\.openclaw\\qwen3-tts\\server.pid"
)

if (-not (Test-Path $PidFile)) {
    Write-Host "Server PID file not found: $PidFile"
    exit 0
}

$serverPid = Get-Content $PidFile -ErrorAction SilentlyContinue
if (-not $serverPid) {
    Write-Host "PID file empty."
    Remove-Item $PidFile -ErrorAction SilentlyContinue
    exit 0
}

try {
    Stop-Process -Id $serverPid -Force
    Write-Host "Stopped server (PID: $serverPid)"
} catch {
    Write-Host "Process not running (PID: $serverPid)"
}

Remove-Item $PidFile -ErrorAction SilentlyContinue
