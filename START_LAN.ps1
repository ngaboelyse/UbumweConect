# ============================================================
# Ubumwe Connect - LAN Server
# Serves the web build so ANY device on the same Wi-Fi
# (phone browser, tablet, another PC) can use the app.
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "       Ubumwe Connect - Local Network Server" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Find the PC's LAN IP (Wi-Fi or Ethernet, ignore virtual adapters)
$ip = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
        $_.IPAddress -notlike '127.*' -and
        $_.IPAddress -notlike '169.254.*' -and
        $_.IPAddress -notlike '192.168.56.*' -and
        $_.InterfaceAlias -notlike '*vEthernet*' -and
        $_.InterfaceAlias -notlike '*WSL*'
    } |
    Select-Object -First 1).IPAddress

if (-not $ip) {
    Write-Host "Could not detect a LAN IP. Run: ipconfig" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "This PC's LAN IP: $ip" -ForegroundColor Green

# 2. Backend information
Write-Host ""
Write-Host "Backend must run with:" -ForegroundColor Yellow
Write-Host "uvicorn app.main:app --host 0.0.0.0 --port 8000" -ForegroundColor Yellow
Write-Host "(docker-compose should already use --host 0.0.0.0)" -ForegroundColor Gray

# 3. Display LAN addresses
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  OPEN THIS ON ANY DEVICE ON THE SAME WI-FI:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Web App:       http://${ip}:3000" -ForegroundColor Green
Write-Host ""
Write-Host "  Backend API:   http://${ip}:8000/docs" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# 4. Windows Firewall: allow inbound on 3000 and 8000
#    This requires Administrator privileges.
$firewallOk = $false

try {
    New-NetFirewallRule `
        -DisplayName "Ubumwe Connect Web (3000)" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 3000 `
        -Action Allow `
        -ErrorAction Stop | Out-Null

    New-NetFirewallRule `
        -DisplayName "Ubumwe Connect API (8000)" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 8000 `
        -Action Allow `
        -ErrorAction Stop | Out-Null

    $firewallOk = $true
}
catch {
    Write-Host "Could not add firewall rules." -ForegroundColor Yellow
    Write-Host "Run this script as Administrator once." -ForegroundColor Yellow
    Write-Host $_ -ForegroundColor Yellow
}

if ($firewallOk) {
    Write-Host "Firewall rules added for ports 3000 and 8000." -ForegroundColor Green
}

# 5. Start the web server
Write-Host ""
Write-Host "Serving web app on 0.0.0.0:3000 ..." -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop." -ForegroundColor Gray
Write-Host ""

Set-Location "$PSScriptRoot\frontend\build\web"

python -m http.server 3000 --bind 0.0.0.0