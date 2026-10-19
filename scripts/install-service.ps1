# Installs the ImmichNative supervisor as a Windows service. Triggers a UAC prompt.
# The service runs as NT AUTHORITY\NetworkService, not LocalSystem: PostgreSQL refuses to start
# under an administrative account.
param([switch]$Start)

$root = Split-Path $PSScriptRoot
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    if ($Start) { $argList += '-Start' }
    Start-Process powershell -Verb RunAs -ArgumentList $argList -Wait
    return
}

$ErrorActionPreference = 'Stop'
$name = 'ImmichNative'
$publish = Join-Path $root 'publish'
$account = 'NT AUTHORITY\NetworkService'

Write-Host 'Publishing...'
dotnet publish "$root\src\ImmichSupervisor" -c Release -o $publish --nologo | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed' }

Write-Host 'Granting file permissions to NetworkService...'
# Read+execute on programs and config, modify on data/log/backup folders, read on the secrets file.
foreach ($p in "$root\tools", "$root\vendor", "$root\config", $publish) {
    icacls $p /grant "${account}:(OI)(CI)RX" /T /C /Q | Out-Null
}
icacls "$root\run\pg.env" /grant "${account}:R" /C /Q | Out-Null
icacls "$root\run" /grant "${account}:(RX)" /C /Q | Out-Null
New-Item -ItemType Directory -Force 'D:\ImmichNative' | Out-Null
icacls 'D:\ImmichNative' /grant "${account}:(OI)(CI)M" /T /C /Q | Out-Null

if (Get-Service $name -ErrorAction SilentlyContinue) {
    Write-Host 'Service exists; stopping and removing the old one...'
    Stop-Service $name -ErrorAction SilentlyContinue
    sc.exe delete $name | Out-Null
    Start-Sleep 2
}

Write-Host 'Creating service...'
sc.exe create $name binPath= "`"$publish\ImmichSupervisor.exe`"" obj= $account start= delayed-auto DisplayName= 'Immich (native)' | Out-Null
sc.exe description $name 'Supervises Postgres, Redis and the Immich server' | Out-Null
sc.exe failure $name reset= 86400 actions= restart/5000/restart/30000/restart/60000 | Out-Null
# Give the supervisor time to stop Postgres/Redis gracefully at shutdown.
reg add "HKLM\SYSTEM\CurrentControlSet\Control" /v WaitToKillServiceTimeout /t REG_SZ /d 180000 /f | Out-Null

if ($Start) { Start-Service $name; Write-Host 'Started.' }
Write-Host "Installed '$name'. Start it with: Start-Service $name   (logs: D:\ImmichNative\logs)"
