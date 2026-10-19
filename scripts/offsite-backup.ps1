# Nightly encrypted off-site backup of the native Immich library and database dumps to Google Drive (rclone crypt).
# Runs at 3:00 AM from the "Immich Offsite Backup" scheduled task, after the supervisor's 03:00 pg_dump has landed in
# D:\ImmichNative\backups (the supervisor starts its dump at 03:00; this job's library sync takes long enough that
# the dump is normally finished before the dump folder is synced).
#   D:\ImmichNative\library  -> gdrive-crypt:current            (thumbs/, encoded-video/ and backups/ are not uploaded)
#   D:\ImmichNative\backups  -> gdrive-crypt:current/db-backups
# Files that disappear from the source are moved to gdrive-crypt:deleted/<date> and pruned after 91 days.
# Safety: refuses to run when the source looks missing/empty, and caps deletions per run (--max-delete).
param(
  [string]$RcloneExe = 'rclone',
  [string]$RcloneConfig = '',
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$lib      = 'D:\ImmichNative\library'
$dumps    = 'D:\ImmichNative\backups'
$stamp    = Get-Date -Format 'yyyy-MM-dd'
$logDir   = 'D:\ImmichNative\logs\offsite'
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir ($(if ($DryRun) { "offsite-dryrun-$stamp-$(Get-Date -Format HHmmss).log" } else { "offsite-$stamp.log" }))

function Log($m) { Add-Content $log "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" }

# Guard: a missing or empty source would make 'sync' treat everything offsite as deleted.
$sample = if (Test-Path "$lib\library") { Get-ChildItem "$lib\library" -File -Recurse -Force -ErrorAction SilentlyContinue | Select-Object -First 50 } else { @() }
if (-not (Test-Path "$lib\library\.immich") -or @($sample).Count -lt 50) {
  Log "ABORT: source $lib looks missing or empty; nothing was synced."
  exit 2
}

$common = @('--fast-list', '--transfers', '4', '--checkers', '8', '--max-delete', '1000', '--log-file', $log, '--log-level', 'INFO')
if ($RcloneConfig) { $common += @('--config', $RcloneConfig) }
if ($DryRun) { $common += '--dry-run' }

& $RcloneExe sync $lib 'gdrive-crypt:current' `
  --exclude '/thumbs/**' --exclude '/encoded-video/**' --exclude '/backups/**' --exclude '/db-backups/**' `
  --backup-dir "gdrive-crypt:deleted/$stamp" @common
$libExit = $LASTEXITCODE
if ($libExit -ne 0) { Log "Library sync failed (exit $libExit) - skipping the rest."; exit $libExit }

if (Test-Path $dumps) {
  & $RcloneExe sync $dumps 'gdrive-crypt:current/db-backups' --backup-dir "gdrive-crypt:deleted/$stamp/db-backups" @common
  $dumpExit = $LASTEXITCODE
  if ($dumpExit -ne 0) { Log "DB dump sync failed (exit $dumpExit) - skipping prune."; exit $dumpExit }
}

if ($DryRun) { Log 'Dry run complete; no prune.'; exit 0 }

# Prune versioned deletions: remove deleted/<yyyy-MM-dd> folders older than 91 days (by folder name, not file times).
$retentionDays = 91
$cutoff = (Get-Date).Date.AddDays(-$retentionDays)
$cfg = @(); if ($RcloneConfig) { $cfg = @('--config', $RcloneConfig) }
$dirs = & $RcloneExe lsf --dirs-only 'gdrive-crypt:deleted' @cfg 2>$null
foreach ($d in $dirs) {
  $name = $d.TrimEnd('/')
  $when = [datetime]::MinValue
  if ([datetime]::TryParseExact($name, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None, [ref]$when) -and $when -lt $cutoff) {
    Log "Pruning gdrive-crypt:deleted/$name (older than $retentionDays days)"
    & $RcloneExe purge "gdrive-crypt:deleted/$name" @cfg --log-file $log --log-level INFO
  }
}
exit 0
