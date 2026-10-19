# One-time: register the 3:00 AM off-site backup task. Run in an ADMIN PowerShell.
# Uses S4U so it runs whether or not you are signed in, without storing your password.
$ErrorActionPreference = 'Stop'
$rclone = (Get-Command rclone).Source
$conf   = (rclone config file | Select-Object -Last 1).Trim()
$script = 'C:\Users\shawn\source\repos\ImmichNative\scripts\offsite-backup.ps1'

$action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
               -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -RcloneExe `"$rclone`" -RcloneConfig `"$conf`""
$trigger   = New-ScheduledTaskTrigger -Daily -At 3:00AM
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType S4U -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -WakeToRun -MultipleInstances IgnoreNew `
               -ExecutionTimeLimit (New-TimeSpan -Hours 12)

Register-ScheduledTask -TaskName 'Immich Offsite Backup' -Description 'rclone sync D:\ImmichNative\library + DB dumps -> gdrive-crypt (nightly 3 AM)' `
  -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Get-ScheduledTask 'Immich Offsite Backup' | Format-List TaskName,State
Write-Host "Test now with:  Start-ScheduledTask 'Immich Offsite Backup'   then check D:\ImmichNative\logs\offsite"

