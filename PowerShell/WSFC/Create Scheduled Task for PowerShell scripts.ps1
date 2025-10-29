# Remove existing task if it already exists
$existing = Get-ScheduledTask -TaskName 'ChangeClusterOwner' -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName 'ChangeClusterOwner' -Confirm:$false
}

# Action: run the PowerShell script with safe switches
$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\Source\ChangeClusterOwner.ps1"'

# Trigger: daily at 02:00
$trigger = New-ScheduledTaskTrigger -Daily -At 02:00

# Build settings only with supported parameters
$settingsParams = @{
    MultipleInstances   = 'IgnoreNew'
    ExecutionTimeLimit  = (New-TimeSpan -Hours 72)
    Hidden              = $false
}
$settingsParameters = (Get-Command New-ScheduledTaskSettingsSet).Parameters.Keys

if ($settingsParameters -contains 'AllowHardTerminate')         { $settingsParams.AllowHardTerminate = $true }
if ($settingsParameters -contains 'StartWhenAvailable')         { $settingsParams.StartWhenAvailable = $false }
if ($settingsParameters -contains 'RunOnlyIfIdle')              { $settingsParams.RunOnlyIfIdle = $false }
if ($settingsParameters -contains 'RestartOnIdle')              { $settingsParams.RestartOnIdle = $false }
if ($settingsParameters -contains 'StopOnIdleEnd')              { $settingsParams.StopOnIdleEnd = $true }
if ($settingsParameters -contains 'UseUnifiedSchedulingEngine') { $settingsParams.UseUnifiedSchedulingEngine = $true }
if ($settingsParameters -contains 'WakeToRun')                  { $settingsParams.WakeToRun = $false }

$settings = New-ScheduledTaskSettingsSet @settingsParams

# Principal: SYSTEM at highest available run level
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

# Register the task
Register-ScheduledTask `
    -TaskName 'ChangeClusterOwner' `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description 'ChangeClusterOwner daily job'

# Optional quick test run
# Start-ScheduledTask -TaskName 'ChangeClusterOwner'

# Verify
Get-ScheduledTask -TaskName 'ChangeClusterOwner' | Select-Object TaskName, State
Get-ScheduledTaskInfo -TaskName 'ChangeClusterOwner'