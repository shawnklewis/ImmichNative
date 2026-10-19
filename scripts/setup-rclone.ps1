# One-time: create the Google Drive remote and the encrypted "crypt" remote on top of it.
# Run in a NORMAL (non-admin) PowerShell, as the user who will own the backups.
$ErrorActionPreference = 'Stop'
if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) { throw 'rclone not found. Run: winget install -e --id Rclone.Rclone  (then open a new PowerShell)' }

function New-Secret {
  $b = New-Object byte[] 32
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
  ([Convert]::ToBase64String($b)).TrimEnd('=').Replace('+','A').Replace('/','B')
}

Write-Host "Step 1/2: Google Drive. A browser window will open - sign in to Google and allow rclone." -ForegroundColor Cyan
# drive.file scope: rclone can only see files it created itself, not the rest of your Drive.
rclone config create gdrive drive scope=drive.file

Write-Host "Step 2/2: encrypted remote gdrive-crypt -> gdrive:immich-backup" -ForegroundColor Cyan
$p1 = New-Secret; $p2 = New-Secret
rclone config create gdrive-crypt crypt remote=gdrive:immich-backup filename_encryption=standard directory_name_encryption=true password=$p1 password2=$p2 --obscure | Out-Null

Write-Host ""
Write-Host "==================== SAVE THESE NOW ====================" -ForegroundColor Yellow
Write-Host "Put both in your password manager. Without them the Google Drive backup CANNOT be decrypted if melli dies."
Write-Host "crypt password : $p1"
Write-Host "crypt salt     : $p2"
Write-Host "remote         : gdrive:immich-backup (crypt, standard filename encryption, encrypted dir names)"
Write-Host "========================================================" -ForegroundColor Yellow
Write-Host ""
rclone mkdir gdrive-crypt:current
rclone lsd gdrive-crypt:
Write-Host "rclone config file: $(rclone config file | Select-Object -Last 1)"
