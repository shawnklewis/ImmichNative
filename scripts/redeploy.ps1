# Rebuilds the supervisor and swaps it into the running service. One UAC prompt.
# 1. (no admin) publish to C:\ProgramData\ImmichNative\supervisor-new
# 2. (admin)    stop the service, clean up anything it left running, swap folders, start the service
# Log of the elevated part: C:\ProgramData\ImmichNative\redeploy.log
param([switch]$Elevated)

$root    = Split-Path $PSScriptRoot
$dest    = 'C:\ProgramData\ImmichNative'
$staging = "$dest\supervisor-new"
$name    = 'ImmichNative'

if (-not $Elevated) {
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
    if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
    dotnet publish "$root\src\ImmichSupervisor" -c Release -o $staging --nologo | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed' }
    icacls $staging /grant 'NT AUTHORITY\NetworkService:(OI)(CI)RX' /T /C /Q | Out-Null
    Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-Elevated'
    Get-Content "$dest\redeploy.log" -Tail 25
    return
}

Start-Transcript -Path "$dest\redeploy.log" -Force | Out-Null
$ErrorActionPreference = 'Continue'

Write-Host "Stopping service (graceful)..."
Stop-Service $name -ErrorAction SilentlyContinue
try { (Get-Service $name).WaitForStatus('Stopped', [TimeSpan]::FromMinutes(4)) } catch { Write-Host "service did not stop in time: $_" }
Write-Host "Service status: $((Get-Service $name).Status)"

# Anything still running from our folders outlived the supervisor. Report it, then stop it the safe way.
$left = Get-CimInstance Win32_Process | Where-Object {
    $_.ExecutablePath -like "$dest\*" -or ($_.Name -eq 'node.exe' -and $_.CommandLine -match 'dist[/\\]main')
}
if ($left) {
    Write-Host "ORPHANS after service stop: $(($left | ForEach-Object { "$($_.Name)($($_.ProcessId))" }) -join ', ')"
    if ($left | Where-Object Name -eq 'redis-server.exe') {
        & "$dest\tools\redis\redis-cli.exe" -p 6380 shutdown save 2>&1 | Out-Null
    }
    $left | Where-Object Name -eq 'node.exe' | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if ($left | Where-Object Name -eq 'postgres.exe') {
        & "$dest\tools\pgsql\bin\pg_ctl.exe" stop -D 'D:\ImmichNative\pgdata' -m fast -w -t 90 2>&1 | Out-Host
    }
    Start-Sleep 2
} else {
    Write-Host "No orphaned processes."
}

Write-Host "Activating staged server build (if any)..."
& "$PSScriptRoot\swap-server.ps1"

Write-Host "Swapping supervisor files..."
if (Test-Path "$dest\supervisor-old") { Remove-Item "$dest\supervisor-old" -Recurse -Force }
if (Test-Path "$dest\supervisor") { Rename-Item "$dest\supervisor" 'supervisor-old' }
Rename-Item $staging 'supervisor'

$ruleName = 'Immich (native) LAN 2283'
if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
    # LAN only: remote address must be on the local subnet, and only the Node binary that runs Immich is allowed.
    # The Public profile is included because Windows classifies this PC's Ethernet connection as Public; the
    # LocalSubnet restriction is what keeps it from being reachable beyond the home network.
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort 2283 `
        -Profile Private, Domain, Public -RemoteAddress LocalSubnet -Program 'C:\Program Files\nodejs\node.exe' | Out-Null
    Write-Host "Added firewall rule '$ruleName'"
} else {
    Write-Host "Firewall rule '$ruleName' already present"
}

Write-Host "Starting service..."
Start-Service $name
Write-Host "Service status: $((Get-Service $name).Status)"
Stop-Transcript | Out-Null

