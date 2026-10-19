# Copies the Docker Immich instance into the native one WITHOUT modifying Docker.
#   1. pg_dump of the Docker database (consistent snapshot, Docker keeps running)
#   2. restore into a NEW database on the native Postgres, skipping the vchord extension and its two vchordrq indexes
#      (Immich recreates them with pgvector at startup because DB_VECTOR_EXTENSION=pgvector)
#   3. rewrite /data/... file paths to the native media root
#   4. robocopy the library (originals, thumbs, encoded video, profile pictures)
# Re-runnable: the target database is dropped and recreated; robocopy only copies what changed.
param(
    [string]$DbName    = 'immich_mig',
    [string]$MediaRoot = 'D:\ImmichNative\library',
    [switch]$SkipCopy,
    [switch]$SkipDb
)
# Native tools (psql NOTICEs, robocopy) write to stderr; 'Stop' would treat that as fatal in PS 5.1, so exit codes are checked instead.
$ErrorActionPreference = 'Continue'
$root   = Split-Path $PSScriptRoot
$bin    = "$root\tools\pgsql\bin"
$mig    = 'D:\ImmichNative\migration'
$source = 'D:\Immich\library'
$secret = ((Get-Content "$root\run\pg.env") -match '^PGPASSWORD=' -replace '^PGPASSWORD=', '').Trim()
$env:PGPASSWORD = $secret
$pg = @('-h', '127.0.0.1', '-p', '5433', '-U', 'postgres')
function Step($n) { "=== $n ($(Get-Date -Format HH:mm:ss))" }
function Psql($db, $sql) {
    $f = "$mig\tmp.sql"; Set-Content $f $sql -Encoding ascii
    & "$bin\psql.exe" @pg -d $db -v ON_ERROR_STOP=1 -f $f
    if ($LASTEXITCODE -ne 0) { throw "psql failed: $sql" }
}

New-Item -ItemType Directory -Force $mig | Out-Null

if (-not $SkipDb) {
    Step 'dump Docker database'
    docker exec immich_postgres pg_dump -U postgres -d immich -Fc -f /tmp/immich-migration.dump
    if ($LASTEXITCODE -ne 0) { throw 'pg_dump in container failed' }
    docker cp immich_postgres:/tmp/immich-migration.dump "$mig\docker-immich.dump"
    docker exec immich_postgres rm -f /tmp/immich-migration.dump

    Step 'filter restore list (drop vchord + vchordrq indexes)'
    $list = & "$bin\pg_restore.exe" --list "$mig\docker-immich.dump"
    $keep = $list | Where-Object { $_ -notmatch 'EXTENSION - vchord|EXTENSION vchord|INDEX public clip_index|INDEX public face_index' }
    "dropping $($list.Count - $keep.Count) list entries"
    Set-Content "$mig\restore.list" $keep -Encoding ascii

    Step "create database $DbName"
    Psql 'postgres' "drop database if exists $DbName;"
    Psql 'postgres' "create database $DbName;"

    Step 'restore'
    & "$bin\pg_restore.exe" @pg -d $DbName --no-owner -L "$mig\restore.list" "$mig\docker-immich.dump"
    if ($LASTEXITCODE -ne 0) { throw "pg_restore failed ($LASTEXITCODE)" }

    Step "rewrite paths to $MediaRoot"
    $mr = $MediaRoot.TrimEnd('\').Replace("'", "''")
    Psql $DbName @"
begin;
update asset      set "originalPath"  = '$mr\' || replace(substr("originalPath", 7), '/', '\')  where "originalPath"  like '/data/%';
update asset_file set path            = '$mr\' || replace(substr(path, 7), '/', '\')            where path            like '/data/%';
update person     set "thumbnailPath" = '$mr\' || replace(substr("thumbnailPath", 7), '/', '\') where "thumbnailPath" like '/data/%';
-- Immich compares this saved value with IMMICH_MEDIA_LOCATION at startup and refuses to start if the stored paths
-- don't begin with the saved one. Paths were rewritten above, so update the saved value to match.
update system_metadata set value = jsonb_build_object('location', '$mr') where key = 'MediaLocation';
commit;
select 'asset', count(*) filter (where "originalPath" like '$mr\%') as rewritten, count(*) filter (where "originalPath" like '/data/%') as untouched from asset;
select 'asset_file', count(*) filter (where path like '$mr\%'), count(*) filter (where path like '/data/%') from asset_file;
select 'person', count(*) filter (where "thumbnailPath" like '$mr\%'), count(*) filter (where "thumbnailPath" like '/data/%') from person;
"@
}

if (-not $SkipCopy) {
    Step "copy library to $MediaRoot (source is only read)"
    foreach ($d in 'upload', 'library', 'thumbs', 'encoded-video', 'profile') {
        if (-not (Test-Path "$source\$d")) { continue }
        robocopy "$source\$d" "$MediaRoot\$d" /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /MT:8 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy $d failed ($LASTEXITCODE)" }
    }
    # Immich verifies a .immich marker in every storage folder at startup, including backups.
    # Only the marker is needed; Docker's old database backups stay behind.
    New-Item -ItemType Directory -Force "$MediaRoot\backups" | Out-Null
    Copy-Item "$source\backups\.immich" "$MediaRoot\backups\.immich" -Force
}

Step 'verify'
if (-not $SkipDb) {
    Psql $DbName 'select (select count(*) from asset) assets, (select count(*) from album) albums, (select count(*) from person) persons, (select count(*) from asset_face) faces, (select count(*) from smart_search) embeddings;'
}
if (-not $SkipCopy) {
    foreach ($d in 'upload', 'library', 'thumbs', 'encoded-video', 'profile') {
        if (Test-Path "$source\$d") {
            "{0,-14} source {1,7:N0} files | target {2,7:N0} files" -f $d,
                (Get-ChildItem "$source\$d" -Recurse -File -Force).Count, (Get-ChildItem "$MediaRoot\$d" -Recurse -File -Force -ErrorAction SilentlyContinue).Count
        }
    }
}
"=== done ($(Get-Date -Format HH:mm:ss))"

