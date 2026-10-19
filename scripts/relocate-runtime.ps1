# Copies everything the Windows service needs at runtime to C:\ProgramData\ImmichNative, so the service account
# never needs access to the user's profile. Safe to re-run. Does not need admin rights.
#   tools\       portable Postgres, Redis, ffmpeg
#   server\      self-contained Immich server (pnpm deploy), including the platform-specific sharp binary
#   config\      redis.conf
#   secrets\     pg.env (inheritance removed: only SYSTEM, Administrators, this user and NetworkService)
#   supervisor\  published ImmichSupervisor
$root = Split-Path $PSScriptRoot
$dest = 'C:\ProgramData\ImmichNative'
$svc  = 'NT AUTHORITY\NetworkService'
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
$env:CI = '1'
$env:COREPACK_ENABLE_DOWNLOAD_PROMPT = '0'
$env:COREPACK_HOME = Join-Path $root 'tools\corepack'

function Step($name) { "=== $name ($(Get-Date -Format HH:mm:ss))" }

Step 'folders'
New-Item -ItemType Directory -Force $dest, "$dest\config", "$dest\secrets" | Out-Null

Step 'tools (robocopy)'
robocopy "$root\tools" "$dest\tools" /E /XD corepack /NFL /NDL /NJH /NJS /NP /MT:8 | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }

Step 'server (pnpm deploy into a new server-<stamp> folder, copy mode)'
# Copy mode matters: pnpm's default hard links share one security descriptor with the files in the user's pnpm store,
# so changing permissions on this folder would change them on profile files (and vice versa).
# pnpm writes absolute junction targets, so the folder must keep this name; scripts\swap-server.ps1 repoints the
# 'server' junction at it while the service is stopped (redeploy.ps1 / install-service.ps1 call it).
$serverBuild = "$dest\server-$(Get-Date -Format yyyyMMdd-HHmmss)"
Push-Location "$root\vendor\immich"
corepack pnpm --filter immich --prod deploy $serverBuild --config.package-import-method=copy
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "pnpm deploy failed ($LASTEXITCODE)" }
Pop-Location
icacls $serverBuild /grant "${svc}:(OI)(CI)RX" /T /C /Q | Out-Null
Set-Content "$dest\server-staged.txt" $serverBuild -Encoding ascii

Step 'config + secrets'
Copy-Item "$root\config\redis.conf" "$dest\config\redis.conf" -Force
Copy-Item "$root\run\pg.env" "$dest\secrets\pg.env" -Force
icacls "$dest\secrets" /inheritance:r /grant:r "NT AUTHORITY\SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" `
    "${env:USERDOMAIN}\${env:USERNAME}:(OI)(CI)R" "${svc}:(OI)(CI)R" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'failed to restrict the secrets folder' }

Step 'supervisor (dotnet publish)'
dotnet publish "$root\src\ImmichSupervisor" -c Release -o "$dest\supervisor" --nologo | Out-Null
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed ($LASTEXITCODE)" }

Step 'permissions for NetworkService (read+execute on programs, not on secrets)'
foreach ($d in 'tools', 'config', 'supervisor') {
    if (Test-Path "$dest\$d") { icacls "$dest\$d" /grant "${svc}:(OI)(CI)RX" /T /C /Q | Out-Null }
}
icacls $dest /grant "${svc}:(RX)" /C /Q | Out-Null
"=== done ($(Get-Date -Format HH:mm:ss))"

