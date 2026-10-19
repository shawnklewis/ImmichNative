# Activates the server build staged by relocate-runtime.ps1 by repointing the junction
#   C:\ProgramData\ImmichNative\server  ->  C:\ProgramData\ImmichNative\server-<stamp>
# Never rename a pnpm deploy folder: pnpm writes absolute junction targets, so a renamed folder has broken dependencies.
# Call only while the service is stopped (redeploy.ps1 / install-service.ps1 do).
$dest = 'C:\ProgramData\ImmichNative'
$marker = "$dest\server-staged.txt"
$link = "$dest\server"

if (-not (Test-Path $marker)) { Write-Host 'No staged server build; leaving server as is.'; return }
$new = (Get-Content $marker -Raw).Trim()
if (-not (Test-Path "$new\dist\main.js")) { throw "Staged build looks incomplete: $new" }

if (Test-Path $link) {
    $item = Get-Item $link -Force
    if ($item.LinkType -eq 'Junction') {
        cmd /c rmdir "`"$link`""            # removes only the junction
    } else {
        $legacy = "$dest\server-legacy-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Write-Host "Moving the old real folder aside: $legacy"
        Rename-Item $link $legacy
    }
}
cmd /c mklink /J "`"$link`"" "`"$new`"" | Out-Null
if (-not (Test-Path "$link\dist\main.js")) { throw "Junction $link -> $new did not resolve" }
Write-Host "server -> $new"
Remove-Item $marker

# Keep the active build and the newest previous one; remove the rest. rmdir /s /q never follows junctions.
$active = $new
Get-ChildItem $dest -Directory | Where-Object { $_.Name -like 'server-*' -and $_.FullName -ne $active } |
    Sort-Object LastWriteTime -Descending | Select-Object -Skip 1 | ForEach-Object {
        Write-Host "Removing old build $($_.Name)"
        cmd /c rmdir /s /q "`"$($_.FullName)`""
    }
