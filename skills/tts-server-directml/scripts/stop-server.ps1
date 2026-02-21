Param(
    [string]$PidFile = "$env:USERPROFILE\.openclaw\tts-server-directml\server.pid"
)

if (Test-Path $PidFile) {
    $pid = Get-Content $PidFile -ErrorAction SilentlyContinue
    if ($pid) {
        try {
            Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
        } catch {
            # ignore failures when process already exited
        }
    }
    Remove-Item $PidFile -ErrorAction SilentlyContinue
}
