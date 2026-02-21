Param(
    [string]$ServerHost = "localhost",
    [int]$ServerPort = 8099,
    [switch]$SkipServer
)

Write-Host "=== DirectML / ONNX Runtime Check ==="
$code = @'
import sys
def safe_import(name):
    try:
        return __import__(name)
    except Exception as e:
        print(f"{name}: not available ({e})")
        return None

torch_directml = safe_import("torch_directml")
if torch_directml:
    try:
        print(f"torch_directml.device_count: {torch_directml.device_count()}")
        if torch_directml.device_count() > 0:
            print(f"torch_directml.device(0): {torch_directml.device(0)}")
    except Exception as e:
        print(f"torch_directml error: {e}")

onnxruntime = safe_import("onnxruntime")
if onnxruntime:
    try:
        print("onnxruntime providers:", onnxruntime.get_available_providers())
    except Exception as e:
        print(f"onnxruntime error: {e}")
'@

try {
    $python = (Get-Command python).Source
} catch {
    $python = $null
}

if (-not $python) {
    Write-Warning "python not found in PATH."
} else {
    & $python -c $code
}

if (-not $SkipServer) {
    Write-Host "`n=== Server Check ==="
    $base = "http://$ServerHost`:$ServerPort"
    try {
        $health = Invoke-RestMethod -Uri "$base/health" -TimeoutSec 3
        Write-Host "Health:"
        $health | ConvertTo-Json -Depth 5
        $models = Invoke-RestMethod -Uri "$base/models" -TimeoutSec 3
        Write-Host "Models:"
        $models | ConvertTo-Json -Depth 5
    } catch {
        Write-Warning "Server not reachable at $base"
    }
}
