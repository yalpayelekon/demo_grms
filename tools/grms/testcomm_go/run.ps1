# Kill any process listening on TESTCOMM_PORT (default 8082), then start testcomm_go with go run .
$port = if ($env:TESTCOMM_PORT) { [int]$env:TESTCOMM_PORT } else { 8082 }

$pids = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique
if ($pids) {
    foreach ($pid in $pids) {
        Write-Host "Stopping process $pid using port $port"
        Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

& go run .
