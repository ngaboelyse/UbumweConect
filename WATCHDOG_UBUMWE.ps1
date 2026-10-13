# UbumweConnect auto-recovery watchdog
# - Restores the Docker stack whenever it is found down
# - Runs continuously; also safe to run at logon (a Scheduled Task starts it)
# Logs to: $env:TEMP\ubumwe_watchdog.log

$dockerBin = "C:\Program Files\Docker\Docker\resources\bin"
$composeDir = "d:\ALL\Project\UbumweConnect\deployment\docker"
$logFile = "$env:TEMP\ubumwe_watchdog.log"
$env:Path += ";$dockerBin"

function Write-Log($msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg" | Add-Content -Path $logFile
}

# Wait for Docker Desktop to be up (it can take a while after logon/wake)
function Wait-DockerReady {
    for ($i = 0; $i -lt 30; $i++) {
        docker info 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return $true }
        Start-Sleep -Seconds 10
    }
    return $false
}

function Start-Stack {
    Write-Log "ACTION: starting docker compose stack"
    Push-Location $composeDir
    docker compose up -d 2>&1 | ForEach-Object { Write-Log "  $_" }
    Pop-Location
    Write-Log "ACTION: stack start command issued"
}

Write-Log "===== Watchdog started (PID $PID) ====="

while ($true) {
    try {
        $backendUp = docker ps --filter "name=^/ubumwe_backend$" --filter "status=running" -q 2>$null
        if ([string]::IsNullOrWhiteSpace($backendUp)) {
            Write-Log "DETECTED: ubumwe_backend not running"
            if (Wait-DockerReady) {
                Start-Stack
            } else {
                Write-Log "Docker daemon not ready; trying to launch Docker Desktop"
                Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe" -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-Log "ERROR: $_"
    }
    Start-Sleep -Seconds 120
}
