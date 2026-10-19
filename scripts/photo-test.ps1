# Uploads a mixed set of real photos/videos to the native prototype (127.0.0.1:2284) and
# checks that thumbnails/previews were generated for each. Creates a local test admin on first run.
$root = Split-Path $PSScriptRoot
$base = 'http://127.0.0.1:2284/api'
$credFile = "$root\run\test-admin.env"

if (-not (Test-Path $credFile)) {
    $pw = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 20 | ForEach-Object { [char]$_ })
    Set-Content $credFile "EMAIL=test@immich.local`nPASSWORD=$pw`n" -Encoding ascii
    $body = @{ email = 'test@immich.local'; password = $pw; name = 'Test Admin' } | ConvertTo-Json
    Invoke-RestMethod -Method Post "$base/auth/admin-sign-up" -ContentType 'application/json' -Body $body | Out-Null
}
$cred = @{}; Get-Content $credFile | ForEach-Object { $k,$v = $_ -split '=',2; $cred[$k] = $v }
$login = Invoke-RestMethod -Method Post "$base/auth/login" -ContentType 'application/json' `
    -Body (@{ email = $cred.EMAIL; password = $cred.PASSWORD } | ConvertTo-Json)
$h = @{ Authorization = "Bearer $($login.accessToken)" }

$src = 'D:\Google Photos'
$all = Get-ChildItem $src -Recurse -File | Where-Object { $_.Extension -ne '.json' -and $_.FullName -notmatch 'Locked' }
$pick = @()
$recent = $all | Where-Object { $_.FullName -match 'Photos from 202[3-6]' }
$pick += $recent | Where-Object Extension -eq '.jpg' | Select-Object -First 10
$pick += $recent | Where-Object Extension -eq '.png' | Select-Object -First 3
$pick += $all | Where-Object Extension -ieq '.dng'  | Select-Object -First 2
$pick += $all | Where-Object Extension -ieq '.heic' | Select-Object -First 2
$pick += $all | Where-Object { $_.Extension -ieq '.mp4' -and $_.Length -lt 40MB } | Select-Object -First 2
$pick += $all | Where-Object Extension -ieq '.mkv'  | Select-Object -First 1
$pick += $all | Where-Object Extension -ieq '.3gp'  | Select-Object -First 1
"test set: $($pick.Count) files"

$results = @()
foreach ($f in $pick) {
    $m = $f.LastWriteTimeUtc.ToString('o')
    $raw = curl.exe -s -X POST "$base/assets" -H "Authorization: Bearer $($login.accessToken)" `
        -F "deviceAssetId=test-$($f.Name)-$($f.Length)" -F 'deviceId=photo-test' `
        -F "fileCreatedAt=$m" -F "fileModifiedAt=$m" -F "assetData=@$($f.FullName)"
    $r = $raw | ConvertFrom-Json
    $results += [pscustomobject]@{ Name = $f.Name; Ext = $f.Extension.ToLower(); MB = [math]::Round($f.Length/1MB,1); Id = $r.id; Status = $r.status; Thumb = ''; Preview = '' }
}
"uploaded; waiting for thumbnail jobs..."
Start-Sleep 20
$deadline = (Get-Date).AddMinutes(8)
do {
    $pending = 0
    foreach ($x in $results | Where-Object { $_.Id }) {
        if ($x.Thumb -eq 'ok') { continue }
        try {
            $t = Invoke-WebRequest "$base/assets/$($x.Id)/thumbnail?size=thumbnail" -Headers $h -UseBasicParsing -TimeoutSec 20
            $p = Invoke-WebRequest "$base/assets/$($x.Id)/thumbnail?size=preview"   -Headers $h -UseBasicParsing -TimeoutSec 20
            if ($t.Headers['Content-Type'] -like 'image/*' -and $t.RawContentLength -gt 500) { $x.Thumb = 'ok'; $x.Preview = $p.StatusCode } else { $pending++ }
        } catch { $x.Thumb = "wait($($_.Exception.Response.StatusCode.value__))"; $pending++ }
    }
    if ($pending) { Start-Sleep 10 }
} while ($pending -and (Get-Date) -lt $deadline)

$results | Format-Table Name,Ext,MB,Status,Thumb,Preview -AutoSize | Out-String -Width 200
"ok: $(($results | Where-Object Thumb -eq 'ok').Count) / $($results.Count)"
$results | ConvertTo-Json | Set-Content "$root\run\photo-test-results.json"
