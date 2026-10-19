# Builds Immich (server + web) from vendor\immich on Windows, mirroring server\Dockerfile.
# Output: vendor\immich\server\dist, vendor\immich\web\build
# Native tools write progress to stderr, which 'Stop' would treat as fatal in PS 5.1; Step checks exit codes instead.
$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot
$src  = Join-Path $root 'vendor\immich'
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
$env:CI = '1'
$env:COREPACK_ENABLE_DOWNLOAD_PROMPT = '0'
$env:COREPACK_HOME = Join-Path $root 'tools\corepack'
Set-Location $src

function Step($name, [scriptblock]$body) {
    "=== $name ($(Get-Date -Format HH:mm:ss))"
    & $body
    if ($LASTEXITCODE -ne 0) { throw "step failed: $name (exit $LASTEXITCODE)" }
}

$pnpm = { corepack pnpm @args }

Step 'pnpm version'       { corepack pnpm --version }
Step 'install sdk'        { corepack pnpm --filter '@immich/sdk' install --frozen-lockfile }
Step 'build sdk'          { corepack pnpm --filter '@immich/sdk' build }
Step 'install plugin-sdk' { corepack pnpm --filter '@immich/plugin-sdk' install --frozen-lockfile }
Step 'build plugin-sdk'   { corepack pnpm --filter '@immich/plugin-sdk' build }
Step 'install server'     { corepack pnpm --filter immich install --frozen-lockfile }
Step 'build server'       { corepack pnpm --filter immich build }
Step 'install web'        { corepack pnpm --filter immich-web install --frozen-lockfile }
Step 'build web'          { corepack pnpm --filter immich-web build }
"=== done ($(Get-Date -Format HH:mm:ss))"
