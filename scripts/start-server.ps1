# Starts the Immich server (prototype ports) against the portable Postgres and Redis.
# Postgres: 127.0.0.1:5433, Redis: 127.0.0.1:6380, Immich: 127.0.0.1:2284.
$root = Split-Path $PSScriptRoot
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
$pw = ((Get-Content "$root\run\pg.env") -match '^PGPASSWORD=' -replace '^PGPASSWORD=','').Trim()
$e = @{
    NODE_ENV = 'production'
    DB_HOSTNAME = '127.0.0.1'; DB_PORT = '5433'; DB_USERNAME = 'postgres'; DB_PASSWORD = $pw
    DB_DATABASE_NAME = 'immich'; DB_VECTOR_EXTENSION = 'pgvector'
    REDIS_HOSTNAME = '127.0.0.1'; REDIS_PORT = '6380'
    IMMICH_HOST = '127.0.0.1'; IMMICH_PORT = '2284'
    IMMICH_MEDIA_LOCATION = 'D:\ImmichNative\media'
    IMMICH_BUILD_DATA = 'D:\ImmichNative\build'
    IMMICH_MACHINE_LEARNING_URL = 'http://127.0.0.1:3004'
}
foreach ($k in $e.Keys) { Set-Item "env:$k" $e[$k] }
Start-Process -FilePath node -ArgumentList 'dist/main' -WorkingDirectory "$root\vendor\immich\server" `
    -WindowStyle Hidden -RedirectStandardOutput "$root\run\server.log" -RedirectStandardError "$root\run\server.err"
