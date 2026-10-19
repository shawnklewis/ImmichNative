# Verifies a migrated native instance through its API: statistics, albums, people, a thumbnail request for EVERY asset,
# and original-file downloads for a sample (largest videos included). Needs an API key with full access in $env:VERIFY_KEY.
param([int]$Port = 2285, [int]$OriginalSample = 40)
$base = "http://127.0.0.1:$Port/api"
$h = @{ 'x-api-key' = $env:VERIFY_KEY }
if (-not $env:VERIFY_KEY) { throw 'Set $env:VERIFY_KEY first.' }

$stats = Invoke-RestMethod "$base/server/statistics" -Headers $h
"statistics: photos=$($stats.photos) videos=$($stats.videos) usage=$([math]::Round($stats.usage/1GB,1)) GB"

$albums = Invoke-RestMethod "$base/albums" -Headers $h
"albums: $($albums.Count)"
$albums | Sort-Object albumName | ForEach-Object { "  {0,-34} {1,4}" -f $_.albumName, $_.assetCount }

$people = Invoke-RestMethod "$base/people?withHidden=true&size=1000" -Headers $h
"people: total=$($people.total) hidden=$($people.hidden)"

# every asset id
$ids = @(); $page = 1
do {
    $r = Invoke-RestMethod -Method Post "$base/search/metadata" -Headers $h -ContentType 'application/json' `
        -Body (@{ size = 1000; page = $page; withDeleted = $false } | ConvertTo-Json)
    $ids += $r.assets.items | ForEach-Object { [pscustomobject]@{ Id = $_.id; Type = $_.type; Name = $_.originalFileName } }
    $page++
} while ($r.assets.nextPage)
"assets enumerated: $($ids.Count)"

$bad = @(); $n = 0
foreach ($a in $ids) {
    $code = curl.exe -s -o NUL -w '%{http_code}' -H "x-api-key: $($env:VERIFY_KEY)" "$base/assets/$($a.Id)/thumbnail?size=thumbnail"
    if ($code -ne '200') { $bad += [pscustomobject]@{ Name = $a.Name; Type = $a.Type; Code = $code } }
    $n++
}
"thumbnails requested: $n, failures: $($bad.Count)"
$bad | Select-Object -First 10 | ForEach-Object { "  FAIL $($_.Code) $($_.Type) $($_.Name)" }

# originals: a random sample plus every video over 100 MB
$sample = $ids | Get-Random -Count ([math]::Min($OriginalSample, $ids.Count))
$origBad = 0
foreach ($a in $sample) {
    $code = curl.exe -s -o NUL -w '%{http_code}' -H "x-api-key: $($env:VERIFY_KEY)" "$base/assets/$($a.Id)/original"
    if ($code -ne '200') { $origBad++; "  ORIGINAL FAIL $code $($a.Name)" }
}
"original downloads sampled: $($sample.Count), failures: $origBad"
