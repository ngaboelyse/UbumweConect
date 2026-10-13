# ============================================================
# Ubumwe Connect - Register backend auto-start at PC boot
# Run ONCE as Administrator:
#   .\scripts\register_backend_autostart.ps1
# ============================================================
# Ensure script runs elevated (needed to create a scheduled task).
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error 'Please run this script from an elevated (Administrator) PowerShell.'
    exit 1
}

$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$launcher    = Join-Path $projectRoot 'scripts\ensure_backend.ps1'
$taskName    = 'UbumweConnect-Backend'

# Wrapper so the task can run a .ps1 hidden at boot.
$cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`""

$action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $cmd
$trigger   = New-ScheduledTaskTrigger -AtLogOn
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force | Out-Null

Write-Host ""
Write-Host "✅ Scheduled task '$taskName' registered." -ForegroundColor Green
Write-Host "   The backend will now auto-start every time you log in."
Write-Host "   Remove it later with:  Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false"
