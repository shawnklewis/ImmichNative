# Installs (or replaces) the ImmichNative supervisor as a Windows service. Triggers a UAC prompt.
# Run scripts\relocate-runtime.ps1 first: the service runs entirely from C:\ProgramData\ImmichNative and never
# touches the user's profile folder.
# The service runs as NT AUTHORITY\NetworkService, not LocalSystem: PostgreSQL refuses to start
# under an administrative account.
param([switch]$Start)

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    if ($Start) { $argList += '-Start' }
    Start-Process powershell -Verb RunAs -ArgumentList $argList -Wait
    return
}

$ErrorActionPreference = 'Stop'
$name    = 'ImmichNative'
$home_   = 'C:\ProgramData\ImmichNative'
$exe     = "$home_\supervisor\ImmichSupervisor.exe"
$account = 'NT AUTHORITY\NetworkService'

if (-not (Test-Path $exe)) { throw "Missing $exe. Run scripts\relocate-runtime.ps1 first." }

# Data, logs, backups and the Redis snapshot live on D: and need write access.
New-Item -ItemType Directory -Force 'D:\ImmichNative' | Out-Null
icacls 'D:\ImmichNative' /grant "${account}:(OI)(CI)M" /T /C /Q | Out-Null

if (Get-Service $name -ErrorAction SilentlyContinue) {
    Write-Host 'Service exists; stopping (graceful) and removing the old one...'
    Stop-Service $name -ErrorAction SilentlyContinue
    (Get-Service $name).WaitForStatus('Stopped', [TimeSpan]::FromMinutes(3))
    sc.exe delete $name | Out-Null
    Start-Sleep 2
}

Write-Host 'Creating service...'
sc.exe create $name binPath= "`"$exe`"" obj= $account start= delayed-auto DisplayName= 'Immich (native)' | Out-Null
sc.exe description $name 'Supervises Postgres, Redis and the Immich server' | Out-Null
sc.exe failure $name reset= 86400 actions= restart/5000/restart/30000/restart/60000 | Out-Null
# Give the supervisor time to stop Postgres/Redis gracefully at shutdown.
reg add "HKLM\SYSTEM\CurrentControlSet\Control" /v WaitToKillServiceTimeout /t REG_SZ /d 180000 /f | Out-Null

if ($Start) { Start-Service $name; Write-Host 'Started.' }
Write-Host "Installed '$name'. Start it with: Start-Service $name   (logs: D:\ImmichNative\logs)"
