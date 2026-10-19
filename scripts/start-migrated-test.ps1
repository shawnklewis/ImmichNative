# Starts a SECOND native Immich server (port 2285) against the migrated scratch database, for verification.
# Shares Postgres/Redis with the service but uses its own database (immich_mig) and Redis DB index 1,
# so it cannot consume the service instance's jobs. Console process: stop it with Stop-Process.
param([string]$DbName = 'immich_mig', [string]$MediaRoot = 'D:\ImmichNative\library', [int]$Port = 2285)
$root = Split-Path $PSScriptRoot
$pw = ((Get-Content "$root\run\pg.env") -match '^PGPASSWORD=' -replace '^PGPASSWORD=','').Trim()
$e = @{
    NODE_ENV = 'production'
    PATH = "C:\ProgramData\ImmichNative\tools\ffmpeg;C:\Program Files\nodejs;C:\Windows\System32;C:\Windows"
    FFMPEG_PATH = 'C:\ProgramData\ImmichNative\tools\ffmpeg\ffmpeg.exe'
    FFPROBE_PATH = 'C:\ProgramData\ImmichNative\tools\ffmpeg\ffprobe.exe'
    DB_HOSTNAME = '127.0.0.1'; DB_PORT = '5433'; DB_USERNAME = 'postgres'; DB_PASSWORD = $pw
    DB_DATABASE_NAME = $DbName; DB_VECTOR_EXTENSION = 'pgvector'
    REDIS_HOSTNAME = '127.0.0.1'; REDIS_PORT = '6380'; REDIS_DBINDEX = '1'
    IMMICH_HOST = '127.0.0.1'; IMMICH_PORT = "$Port"
    IMMICH_MEDIA_LOCATION = $MediaRoot
    IMMICH_BUILD_DATA = 'D:\ImmichNative\build'
    IMMICH_MACHINE_LEARNING_ENABLED = 'false'
}
foreach ($k in $e.Keys) { Set-Item "env:$k" $e[$k] }
Start-Process -FilePath 'C:\Program Files\nodejs\node.exe' -ArgumentList 'dist/main' -WorkingDirectory 'C:\ProgramData\ImmichNative\server' `
    -WindowStyle Hidden -RedirectStandardOutput "$root\run\mig-server.log" -RedirectStandardError "$root\run\mig-server.err"
