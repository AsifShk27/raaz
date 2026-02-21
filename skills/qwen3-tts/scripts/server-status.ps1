Param(
    [string]$PidFile = "$env:USERPROFILE\\.openclaw\\qwen3-tts\\server.pid"
)

if (-not (Test-Path $PidFile)) {
    Write-Host "Not running"
    exit 1
}

$serverPid = Get-Content $PidFile -ErrorAction SilentlyContinue
if (-not $serverPid) {
    Write-Host "Not running"
    exit 1
}

try {
    $proc = Get-Process -Id $serverPid -ErrorAction Stop
    Write-Host "Running (PID: $serverPid)"
    exit 0
} catch {
    Write-Host "Not running"
    exit 1
}
