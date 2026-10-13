# Restores automatic (DHCP) addressing on the Wi-Fi adapter.
# Run as Administrator before connecting to other Wi-Fi networks.
$ErrorActionPreference = "Stop"

$adapter = Get-NetAdapter | Where-Object { $_.Name -eq 'Wi-Fi' }
if (-not $adapter) { Write-Error "Wi-Fi adapter not found."; exit 1 }

# Remove the static address
Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress 10.20.0.167 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

# Remove the static default gateway
Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
    Where-Object { $_.Protocol -eq 'NetMgmt' } |
    Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

# Back to DNS-from-DHCP
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses

# Force DHCP mode
Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -Dhcp Enabled

Write-Host "Wi-Fi is back on DHCP (automatic IP)." -ForegroundColor Green
