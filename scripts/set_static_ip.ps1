# Sets a static IP for the Wi-Fi adapter so the UbumweConnect backend address
# never changes on this network. Run as Administrator.
# Usage: .\set_static_ip.ps1 [ip]   (default: 10.20.0.167)

param(
    [string]$ip = "10.20.0.167"
)

$ErrorActionPreference = "Stop"

$adapter = Get-NetAdapter | Where-Object { $_.Name -eq 'Wi-Fi' -and $_.Status -eq 'Up' }
if (-not $adapter) {
    Write-Error "No connected Wi-Fi adapter found."
    exit 1
}

# Discover current settings before switching to static
$config = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex
$prefix  = $config.IPv4Address.PrefixLength          # e.g. 16
$gateway = $config.IPv4DefaultGateway.NextHop        # e.g. 10.20.0.1
$dns     = $config.DNSServer.ServerAddresses | Select-Object -First 2
if (-not $dns) { $dns = @('8.8.8.8') }

Write-Host "Adapter        : $($adapter.Name) ($($adapter.InterfaceDescription))"
Write-Host "Current IP     : $($config.IPv4Address.IPAddress)/$prefix"
Write-Host "Setting static : $ip/$prefix, gateway $gateway, DNS $($dns -join ', ')"

# Save current (DHCP) state so restore_dhcp.ps1 knows what to re-enable
@{
    interfaceIndex = $adapter.ifIndex
    staticIp       = $ip
    setOn          = (Get-Date).ToString('s')
} | ConvertTo-Json | Set-Content "$PSScriptRoot\static_ip_state.json"

New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $ip -PrefixLength $prefix -DefaultGateway $gateway -ErrorAction SilentlyContinue | Out-Null

# Disable DHCP so the adapter keeps the static address (same IP was handed
# out by DHCP before, so the lease must be dropped and DHCP turned off).
Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -Dhcp Disabled
$dhcpAddr = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 |
    Where-Object { $_.PrefixOrigin -eq 'Dhcp' -and $_.IPAddress -ne $ip }
if ($dhcpAddr) {
    $dhcpAddr | Remove-NetIPAddress -Confirm:$false
}

# Re-assert the static address/gateway in case the removal churned state
if (-not (Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $ip -ErrorAction SilentlyContinue)) {
    New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $ip -PrefixLength $prefix -DefaultGateway $gateway | Out-Null
}
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $dns

Write-Host "`nDone. This PC will now always be $ip on this network." -ForegroundColor Green
Write-Host "To go back to automatic IPs on other networks, run restore_dhcp.ps1 (as Administrator)."
