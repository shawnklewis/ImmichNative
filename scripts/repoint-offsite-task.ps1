# Points the existing "Immich Offsite Backup" task at the repo copy of offsite-backup.ps1.
# Changes only the script path inside the action; schedule, account (S4U), rclone path and config stay as they were.
# Needs admin (the task uses S4U), so it elevates itself.
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -Verb RunAs -Wait -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    return
}
$name   = 'Immich Offsite Backup'
$script = Join-Path (Split-Path $PSScriptRoot) 'scripts\offsite-backup.ps1'
$task   = Get-ScheduledTask -TaskName $name
$old    = $task.Actions[0]
$newArgs = $old.Arguments.Replace('D:\Immich\scripts\offsite-backup.ps1', $script)
if ($newArgs -eq $old.Arguments -and $old.Arguments -notmatch [regex]::Escape($script)) { throw 'Did not find the expected script path in the task action.' }
$action = New-ScheduledTaskAction -Execute $old.Execute -Argument $newArgs
Set-ScheduledTask -TaskName $name -Action $action | Out-Null
$task = Get-ScheduledTask -TaskName $name
$task.Description = 'rclone sync D:\ImmichNative\library + DB dumps -> gdrive-crypt (nightly 3 AM)'
Set-ScheduledTask -InputObject $task | Out-Null
Write-Host "Updated '$name': $((Get-ScheduledTask -TaskName $name).Actions[0].Arguments)"
