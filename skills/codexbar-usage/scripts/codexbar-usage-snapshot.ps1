param(
    [string]$Provider = "codex",
    [string]$Target = "\\\\wsl$\\Ubuntu\\home\\shkas\\projects\\raaz\\.runtime\\collab\\usage\\codexbar-usage.json",
    [string]$Source = "web"
)

function Invoke-CodexbarUsage {
    param(
        [string]$UseSource
    )
    if (Get-Command codexbar -ErrorAction SilentlyContinue) {
        return & codexbar usage --provider $Provider --format json --pretty --source $UseSource 2>$null
    }
    if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
        $cmd = 'export PATH=/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:/usr/bin:/bin; codexbar usage --provider ' + $Provider + ' --format json --pretty --source ' + $UseSource
        return & wsl.exe -e bash -lc $cmd 2>$null
    }
    return $null
}

function Write-UsageSnapshot {
    param(
        [string]$UseSource
    )
    $json = Invoke-CodexbarUsage -UseSource $UseSource
    if (-not $json) {
        return $false
    }
    $dir = Split-Path -Parent $Target
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $json | Out-File -FilePath $Target -Encoding utf8
    Write-Host "Wrote usage snapshot to: $Target (source=$UseSource)"
    return $true
}

if (-not (Write-UsageSnapshot -UseSource $Source)) {
    if ($Source -ne "cli") {
        Write-UsageSnapshot -UseSource "cli" | Out-Null
    } else {
        Write-Error "codexbar usage failed."
        exit 1
    }
}
