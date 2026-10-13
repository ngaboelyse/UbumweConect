# ============================================================
# Ubumwe Connect - One-command development startup
# Usage:  .\scripts\ensure_backend.ps1
# ============================================================
$ErrorActionPreference = 'SilentlyContinue'

function Test-Api {
    try {
        $r = Invoke-WebRequest -Uri 'http://localhost:8000/health' -UseBasicParsing -TimeoutSec 5
        return $r.StatusCode -eq 200
    } catch { return $false }
}

# 1. Docker daemon up?
if (-not (docker info *> $null)) {
    Write-Host 'Docker daemon not running - starting Docker Desktop...'
    $dockerExe = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dockerExe) {
        Start-Process $dockerExe
        $deadline = (Get-Date).AddSeconds(120)
        do { Start-Sleep 5 } while ((docker info *> $null) -and ((Get-Date) -lt $deadline) -and ($LASTEXITCODE -ne 0))
    } else {
        Write-Error 'Docker Desktop not found at $dockerExe'; exit 1
    }
}

# 2. Containers running?
$running = docker ps --format '{{.Names}}' | Where-Object { $_ -eq 'ubumwe_backend' }
if (-not $running) {
    Write-Host 'Starting Ubumwe Connect containers...'
    $compose = Join-Path $PSScriptRoot '..\deployment\docker\docker-compose.yml'
    docker compose -f $compose up -d | Out-Null
}

# 3. Wait for healthy backend (max ~60s)
$deadline = (Get-Date).AddSeconds(60)
while (-not (Test-Api) -and ((Get-Date) -lt $deadline)) { Start-Sleep 3 }

if (Test-Api) {
    # 4. Report the PC's LAN IP so the app can reach the backend from a phone.
    $lanIp = (Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.NetAdapter.InterfaceDescription -notmatch 'Virtual|Loopback|Hyper-V|WSL' } |
        ForEach-Object { $_.IPv4Address.IPAddress } | Where-Object { $_ -notmatch '^(127\.|169\.)' } |
        Select-Object -First 1)
    if (-not $lanIp) {
        $lanIp = (Get-NetIPAddress -AddressFamily IPv4 |
            Where-Object { ($_.IPAddress -like '10.*' -or $_.IPAddress -like '192.168.*') -and $_.IPAddress -ne '127.0.0.1' -and $_.PrefixOrigin -ne 'WellKnown' } |
            Select-Object -First 1).IPAddress
    }
    Write-Host ''
    Write-Host '✅ Backend is UP: http://localhost:8000' -ForegroundColor Green
    Write-Host "✅ LAN address for phone/app: http://${lanIp}:8000" -ForegroundColor Green
    Write-Host "   (Flutter auto-discovers this, but defaultHost should match it.)"
    exit 0
} else {
    Write-Host '❌ Backend failed to become healthy - check: docker logs ubumwe_backend' -ForegroundColor Red
    exit 1
}
