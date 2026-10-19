# Starts the portable Redis with snapshots stored on D:\ImmichNative\redis.
$root = Split-Path $PSScriptRoot
New-Item -ItemType Directory -Force 'D:\ImmichNative\redis' | Out-Null
Start-Process -FilePath "$root\tools\redis\redis-server.exe" -ArgumentList "`"$root\config\redis.conf`"" `
    -WindowStyle Hidden -RedirectStandardOutput "$root\run\redis.log" -RedirectStandardError "$root\run\redis.err"
