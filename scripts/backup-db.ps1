# Logical backup of the Immich database to D:\ImmichNative\backups (restorable with pg_restore).
# Keeps the newest $Keep dumps. Safe to run while Postgres and Immich are running.
param([int]$Keep = 14)
$root = Split-Path $PSScriptRoot
$dir  = 'D:\ImmichNative\backups'
New-Item -ItemType Directory -Force $dir | Out-Null
$env:PGPASSWORD = ((Get-Content "$root\run\pg.env") -match '^PGPASSWORD=' -replace '^PGPASSWORD=','').Trim()
$file = Join-Path $dir ("immich-{0:yyyyMMdd-HHmmss}.dump" -f (Get-Date))
& "$root\tools\pgsql\bin\pg_dump.exe" -h 127.0.0.1 -p 5433 -U postgres -d immich -Fc -f $file
if ($LASTEXITCODE -ne 0) { Remove-Item $file -ErrorAction SilentlyContinue; throw "pg_dump failed ($LASTEXITCODE)" }
# Verify the archive is readable before pruning older ones.
& "$root\tools\pgsql\bin\pg_restore.exe" --list $file *> $null
if ($LASTEXITCODE -ne 0) { throw "backup verification failed for $file" }
Get-ChildItem $dir -Filter 'immich-*.dump' | Sort-Object LastWriteTime -Descending | Select-Object -Skip $Keep | Remove-Item
"backup ok: $file ($([math]::Round((Get-Item $file).Length/1MB,1)) MB)"
